import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

class MdPlayerQuality {
  const MdPlayerQuality({
    required this.label,
    required this.videoUrl,
    this.audioUrl,
  });

  final String label;
  final String videoUrl;
  final String? audioUrl;
}

class MdPlayerSource {
  const MdPlayerSource({
    required this.videoUrl,
    this.audioUrl,
    this.formatHint,
    this.qualities = const <MdPlayerQuality>[],
  });

  final String videoUrl;
  final String? audioUrl;
  final VideoFormat? formatHint;
  final List<MdPlayerQuality> qualities;
}

class MdPlayerSourceResolver {
  MdPlayerSourceResolver({http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;
  final Map<String, MdPlayerSource> _cache = <String, MdPlayerSource>{};

  Future<MdPlayerSource> resolve(String input) async {
    final String url = input.trim();
    if (url.isEmpty) {
      throw ArgumentError('URL is empty');
    }
    return _cache[url] ??= await _resolve(url);
  }

  Future<MdPlayerSource> _resolve(String url) {
    final Uri uri = Uri.parse(url);
    final String host = uri.host.toLowerCase();
    if (host.contains('youtube.com') || host == 'youtu.be') {
      return _resolveYoutube(url);
    }
    if (host.contains('vimeo.com')) {
      return _resolveVimeo(uri);
    }
    return Future<MdPlayerSource>.value(MdPlayerSource(
      videoUrl: url,
      formatHint: _formatHint(uri),
    ));
  }

  Future<MdPlayerSource> _resolveYoutube(String url) async {
    final YoutubeExplode yt = YoutubeExplode();
    try {
      final StreamManifest manifest =
          await yt.videos.streamsClient.getManifest(VideoId(url));
      final List<MdPlayerQuality> qualities = <MdPlayerQuality>[];

      for (final HlsMuxedStreamInfo stream
          in manifest.hls.whereType<HlsMuxedStreamInfo>()) {
        qualities.add(MdPlayerQuality(
          label: stream.qualityLabel,
          videoUrl: stream.url.toString(),
        ));
      }
      if (qualities.isNotEmpty) {
        return MdPlayerSource(
          videoUrl: qualities.last.videoUrl,
          formatHint: VideoFormat.hls,
          qualities: qualities,
        );
      }

      for (final MuxedStreamInfo stream in manifest.muxed) {
        qualities.add(MdPlayerQuality(
          label: stream.qualityLabel,
          videoUrl: stream.url.toString(),
        ));
      }
      if (qualities.isNotEmpty) {
        return MdPlayerSource(
          videoUrl: qualities.last.videoUrl,
          qualities: qualities,
        );
      }

      final String audioUrl = manifest.audioOnly.last.url.toString();
      final Set<String> seen = <String>{};
      for (final VideoOnlyStreamInfo stream in manifest.videoOnly) {
        if (seen.add(stream.qualityLabel)) {
          qualities.add(MdPlayerQuality(
            label: stream.qualityLabel,
            videoUrl: stream.url.toString(),
            audioUrl: audioUrl,
          ));
        }
      }
      if (qualities.isEmpty) {
        throw StateError('No playable YouTube stream found');
      }
      return MdPlayerSource(
        videoUrl: qualities.last.videoUrl,
        audioUrl: audioUrl,
        qualities: qualities,
      );
    } finally {
      yt.close();
    }
  }

  Future<MdPlayerSource> _resolveVimeo(Uri uri) async {
    final RegExpMatch? match =
        RegExp(r'/(?:video/)?(\d+)').firstMatch(uri.path);
    if (match == null) {
      throw StateError('Unsupported Vimeo URL');
    }

    final Uri configUrl =
        Uri.https('player.vimeo.com', '/video/${match.group(1)}/config');
    final http.Response response = await _httpClient.get(configUrl);
    if (response.statusCode != 200) {
      throw StateError('Vimeo video is private or unsupported');
    }

    final Map<String, dynamic> data =
        jsonDecode(response.body) as Map<String, dynamic>;
    final Map<String, dynamic> request =
        data['request'] as Map<String, dynamic>;
    final Map<String, dynamic> files = request['files'] as Map<String, dynamic>;

    final dynamic hls = files['hls'];
    if (hls is Map && hls['cdns'] is Map) {
      final Map<dynamic, dynamic> cdns = hls['cdns'] as Map<dynamic, dynamic>;
      for (final dynamic cdn in cdns.values) {
        if (cdn is Map && cdn['url'] is String) {
          return MdPlayerSource(
            videoUrl: cdn['url'] as String,
            formatHint: VideoFormat.hls,
          );
        }
      }
    }

    final dynamic progressive = files['progressive'];
    if (progressive is List && progressive.isNotEmpty) {
      final List<MdPlayerQuality> qualities = progressive
          .whereType<Map>()
          .where((Map item) => item['url'] is String)
          .map((Map item) => MdPlayerQuality(
                label: '${item['quality'] ?? 'auto'}',
                videoUrl: item['url'] as String,
              ))
          .toList();
      if (qualities.isNotEmpty) {
        return MdPlayerSource(
          videoUrl: qualities.last.videoUrl,
          qualities: qualities,
        );
      }
    }

    throw StateError('No playable Vimeo stream found');
  }

  VideoFormat? _formatHint(Uri uri) {
    final String path = uri.path.toLowerCase();
    if (path.endsWith('.m3u8')) {
      return VideoFormat.hls;
    }
    if (path.endsWith('.mpd')) {
      return VideoFormat.dash;
    }
    if (path.endsWith('.ism') || path.endsWith('.isml')) {
      return VideoFormat.ss;
    }
    return null;
  }

  void close() {
    _httpClient.close();
  }
}
