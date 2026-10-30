import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Merges a video-only and an audio-only fragmented MP4 stream for AVPlayer.
///
/// AVPlayer cannot merge two progressive files, and an `AVURLAsset` over a
/// remote DASH-style MP4 downloads the whole file before reporting tracks.
/// Instead, each stream's `sidx` index is turned into a byte-range HLS media
/// playlist (segments stay on the origin server), and a master playlist pairs
/// the video with the audio as an alternate rendition. AVPlayer then plays and
/// seeks both natively. The playlists are served from a loopback HTTP server
/// because AVPlayer does not load HLS from `file:` URLs.
class MdPlayerHlsBridge {
  /// Creates a bridge; [httpClient] reads stream indexes.
  @visibleForTesting
  MdPlayerHlsBridge({http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client();

  /// Shared bridge used by controllers on non-Android platforms.
  static final MdPlayerHlsBridge instance = MdPlayerHlsBridge();

  final http.Client _httpClient;
  HttpServer? _server;
  int _nextId = 0;
  // ponytail: keeps the 16 latest sources (a few KB each); a player older
  // than that can no longer reload its playlists.
  final LinkedHashMap<String, String> _playlists =
      LinkedHashMap<String, String>();

  /// Returns a loopback URL of an HLS master playlist that plays [videoUrl]
  /// with [audioUrl] as its audio.
  ///
  /// Throws [StateError] when either stream has no `sidx` index.
  Future<String> register({
    required String videoUrl,
    required String audioUrl,
    Map<String, String> httpHeaders = const <String, String>{},
    Map<String, String>? audioHttpHeaders,
  }) async {
    final List<Object> parts = await Future.wait(<Future<Object>>[
      _mediaPlaylist(videoUrl, httpHeaders),
      _mediaPlaylist(audioUrl, audioHttpHeaders ?? httpHeaders),
      _ensureServer(),
    ]);
    final _MediaPlaylist video = parts[0] as _MediaPlaylist;
    final _MediaPlaylist audio = parts[1] as _MediaPlaylist;
    final String id = '${++_nextId}';
    _put('$id/video.m3u8', video.text);
    _put('$id/audio.m3u8', audio.text);
    _put(
      '$id/master.m3u8',
      '#EXTM3U\n'
          '#EXT-X-VERSION:7\n'
          '#EXT-X-INDEPENDENT-SEGMENTS\n'
          '#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio",NAME="audio",'
          'DEFAULT=YES,AUTOSELECT=YES,URI="audio.m3u8"\n'
          '#EXT-X-STREAM-INF:BANDWIDTH='
          '${video.peakBandwidth + audio.peakBandwidth},AUDIO="audio"\n'
          'video.m3u8\n',
    );
    return 'http://${InternetAddress.loopbackIPv4.address}:${_server!.port}'
        '/$id/master.m3u8';
  }

  /// Playlist text served at [path], for tests.
  @visibleForTesting
  String? playlist(String path) => _playlists[path];

  void _put(String path, String text) {
    _playlists[path] = text;
    while (_playlists.length > 48) {
      _playlists.remove(_playlists.keys.first);
    }
  }

  Future<HttpServer> _ensureServer() async {
    final HttpServer? existing = _server;
    if (existing != null) return existing;
    final HttpServer server =
        await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    server.listen((HttpRequest request) {
      final String? body = _playlists[request.uri.path.substring(1)];
      request.response
        ..statusCode = body == null ? HttpStatus.notFound : HttpStatus.ok
        ..headers.contentType =
            ContentType('application', 'vnd.apple.mpegurl', charset: 'utf-8')
        ..write(body ?? '')
        ..close();
    }, onDone: () => _server = null);
    return server;
  }

  Future<_MediaPlaylist> _mediaPlaylist(
    String url,
    Map<String, String> headers,
  ) async {
    // Init segment and index sit at the start; 64 KiB covers hours of
    // segments, and a longer index is read in a second request.
    Uint8List head = await _range(url, headers, 0, 65535);
    final MdSidx sidx = MdSidx.find(head) ??
        await () async {
          final int? end = MdSidx.endOf(head);
          if (end == null || end <= head.length) {
            throw StateError('Stream has no sidx index: $url');
          }
          head = await _range(url, headers, 0, end - 1);
          return MdSidx.find(head) ??
              (throw StateError('Stream has no sidx index: $url'));
        }();
    return _MediaPlaylist.build(url, sidx);
  }

  Future<Uint8List> _range(
    String url,
    Map<String, String> headers,
    int start,
    int end,
  ) async {
    final http.Response response = await _httpClient.get(
      Uri.parse(url),
      headers: <String, String>{...headers, 'range': 'bytes=$start-$end'},
    );
    if (response.statusCode != 200 && response.statusCode != 206) {
      throw StateError('Stream index request failed: ${response.statusCode}');
    }
    return response.bodyBytes;
  }
}

/// A parsed ISO-BMFF `sidx` box: segment byte ranges and durations.
@visibleForTesting
class MdSidx {
  const MdSidx._(this.boxStart, this.boxEnd, this.segments);

  /// Offset of the `sidx` box; the init segment is everything before it.
  final int boxStart;

  /// Offset just past the `sidx` box.
  final int boxEnd;

  /// (byte offset, byte size, seconds) of each referenced segment.
  final List<(int, int, double)> segments;

  /// Top-level boxes in [bytes] up to `sidx`, as (type, start, size).
  static Iterable<(String, int, int)> _boxes(Uint8List bytes) sync* {
    final ByteData data = ByteData.sublistView(bytes);
    int offset = 0;
    while (offset + 8 <= bytes.length) {
      int size = data.getUint32(offset);
      final String type = String.fromCharCodes(bytes, offset + 4, offset + 8);
      if (size == 1 && offset + 16 <= bytes.length) {
        size = data.getUint64(offset + 8);
      }
      if (size < 8) return;
      yield (type, offset, size);
      if (type == 'sidx') return;
      offset += size;
    }
  }

  /// End offset of the `sidx` box, when its header is inside [bytes].
  static int? endOf(Uint8List bytes) {
    for (final (String type, int start, int size) in _boxes(bytes)) {
      if (type == 'sidx') return start + size;
    }
    return null;
  }

  /// Parses the first `sidx` box when [bytes] holds all of it.
  static MdSidx? find(Uint8List bytes) {
    for (final (String type, int start, int size) in _boxes(bytes)) {
      if (type != 'sidx') continue;
      if (start + size > bytes.length) return null;
      final ByteData data = ByteData.sublistView(bytes, start, start + size);
      final int version = data.getUint8(8);
      int p = 16; // header, version/flags, reference_ID
      final int timescale = data.getUint32(p);
      p += 4;
      final int firstOffset;
      if (version == 0) {
        firstOffset = data.getUint32(p + 4);
        p += 8;
      } else {
        firstOffset = data.getUint64(p + 8);
        p += 16;
      }
      final int count = data.getUint16(p + 2);
      p += 4;
      int offset = start + size + firstOffset;
      final List<(int, int, double)> segments = <(int, int, double)>[];
      for (int i = 0; i < count; i++) {
        final int referenced = data.getUint32(p) & 0x7fffffff;
        final int duration = data.getUint32(p + 4);
        p += 12;
        segments.add((offset, referenced, duration / timescale));
        offset += referenced;
      }
      return MdSidx._(start, start + size, segments);
    }
    return null;
  }
}

class _MediaPlaylist {
  const _MediaPlaylist(this.text, this.peakBandwidth);

  factory _MediaPlaylist.build(String url, MdSidx sidx) {
    double longest = 1;
    int peak = 1;
    final StringBuffer segments = StringBuffer();
    for (final (int offset, int size, double seconds) in sidx.segments) {
      if (seconds > longest) longest = seconds;
      if (seconds > 0 && size * 8 / seconds > peak) {
        peak = (size * 8 / seconds).ceil();
      }
      segments
        ..writeln('#EXTINF:${seconds.toStringAsFixed(6)},')
        ..writeln('#EXT-X-BYTERANGE:$size@$offset')
        ..writeln(url);
    }
    return _MediaPlaylist(
      '#EXTM3U\n'
      '#EXT-X-VERSION:7\n'
      '#EXT-X-PLAYLIST-TYPE:VOD\n'
      '#EXT-X-TARGETDURATION:${longest.ceil()}\n'
      '#EXT-X-INDEPENDENT-SEGMENTS\n'
      '#EXT-X-MAP:URI="$url",BYTERANGE="${sidx.boxStart}@0"\n'
      '$segments'
      '#EXT-X-ENDLIST\n',
      peak,
    );
  }

  final String text;
  final int peakBandwidth;
}
