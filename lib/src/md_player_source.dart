import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// One selectable stream identity and its playback/cache metadata.
///
/// Header maps are treated as immutable after construction and must not be
/// modified while a controller uses this quality.
class MdPlayerQuality {
  /// Creates a selectable quality.
  const MdPlayerQuality({
    required this.label,
    required this.videoUrl,
    this.audioUrl,
    this.httpHeaders = const <String, String>{},
    this.audioHttpHeaders,
    this.videoFormatHint,
    this.audioFormatHint,
    this.videoCacheKey,
    this.audioCacheKey,
    this.videoStreamIdentity,
    this.audioStreamIdentity,
    this.videoItag,
    this.audioItag,
    this.videoRole,
    this.audioRole,
  });

  /// User-visible quality label.
  final String label;

  /// Video or muxed stream URL.
  final String videoUrl;

  /// Optional separate audio stream URL.
  final String? audioUrl;

  /// Headers sent for the video stream.
  final Map<String, String> httpHeaders;

  /// Headers sent for [audioUrl], or null to reuse [httpHeaders].
  final Map<String, String>? audioHttpHeaders;

  /// Optional video format hint passed to Media3.
  final VideoFormat? videoFormatHint;

  /// Optional audio format hint passed to Media3.
  final VideoFormat? audioFormatHint;

  /// Stable cache key for the video or muxed resource.
  final String? videoCacheKey;

  /// Stable cache key for the separate audio resource.
  final String? audioCacheKey;

  /// Stable video identity used by targeted cache removal.
  final String? videoStreamIdentity;

  /// Stable audio identity used by targeted cache removal.
  final String? audioStreamIdentity;

  /// Provider-specific video stream tag.
  final int? videoItag;

  /// Provider-specific audio stream tag.
  final int? audioItag;

  /// Cache role such as `video` or `muxed`.
  final String? videoRole;

  /// Cache role for a separate audio stream.
  final String? audioRole;
}

/// Resolved initial source and its selectable qualities.
///
/// Collection values are treated as immutable after construction.
class MdPlayerSource {
  /// Creates a resolved playback source.
  const MdPlayerSource({
    required this.videoUrl,
    this.audioUrl,
    this.formatHint,
    this.httpHeaders = const <String, String>{},
    this.audioHttpHeaders,
    this.qualityLabel = 'auto',
    this.qualities = const <MdPlayerQuality>[],
    this.videoCacheKey,
    this.audioCacheKey,
    this.videoStreamIdentity,
    this.audioStreamIdentity,
    this.videoItag,
    this.audioItag,
    this.videoRole,
    this.audioRole,
    this.audioFormatHint,
  });

  /// Initial video or muxed stream URL.
  final String videoUrl;

  /// Optional initial separate audio stream URL.
  final String? audioUrl;

  /// Optional video format hint.
  final VideoFormat? formatHint;

  /// Headers sent for [videoUrl].
  final Map<String, String> httpHeaders;

  /// Headers sent for [audioUrl], or null to reuse [httpHeaders].
  final Map<String, String>? audioHttpHeaders;

  /// Label associated with the initial stream.
  final String qualityLabel;

  /// Qualities available for explicit switching.
  final List<MdPlayerQuality> qualities;

  /// Stable initial video or muxed cache key.
  final String? videoCacheKey;

  /// Stable initial audio cache key.
  final String? audioCacheKey;

  /// Stable initial video identity.
  final String? videoStreamIdentity;

  /// Stable initial audio identity.
  final String? audioStreamIdentity;

  /// Provider-specific initial video tag.
  final int? videoItag;

  /// Provider-specific initial audio tag.
  final int? audioItag;

  /// Cache role for the initial video or muxed stream.
  final String? videoRole;

  /// Cache role for the initial audio stream.
  final String? audioRole;

  /// Optional separate-audio format hint.
  final VideoFormat? audioFormatHint;
}

/// Builds a stable cache key for one resolved YouTube resource.
String mdPlayerYoutubeCacheKey(String videoId, String role, int itag) {
  final String encoded =
      base64Url.encode(utf8.encode(videoId)).replaceAll('=', '');
  return 'md-player:youtube:$encoded:$role:$itag';
}

/// Resolves direct, YouTube, and Vimeo URLs into Media3 playback sources.
///
/// YouTube stream URLs can expire and provider restrictions may prevent
/// resolution. Call [close] when a resolver is owned outside a controller.
class MdPlayerSourceResolver {
  /// Creates a resolver.
  ///
  /// When [httpClient] is supplied, ownership is transferred and [close]
  /// closes it.
  MdPlayerSourceResolver({http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;
  final Map<String, MdPlayerSource> _cache = <String, MdPlayerSource>{};

  /// Resolves [input], caching the result for this resolver's lifetime.
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
      final String videoId = VideoId(url).value;
      final StreamManifest manifest =
          await yt.videos.streamsClient.getManifest(VideoId(url));

      if (manifest.videoOnly.isNotEmpty && manifest.audioOnly.isNotEmpty) {
        final AudioOnlyStreamInfo audio = manifest.audioOnly.last;
        final String audioUrl = audio.url.toString();
        final List<MdPlayerQuality> qualities = _uniqueQualities(
          manifest.videoOnly.map(
            (VideoOnlyStreamInfo stream) => MdPlayerQuality(
              label: stream.qualityLabel,
              videoUrl: stream.url.toString(),
              audioUrl: audioUrl,
              videoCacheKey:
                  mdPlayerYoutubeCacheKey(videoId, 'video', stream.tag),
              audioCacheKey:
                  mdPlayerYoutubeCacheKey(videoId, 'audio', audio.tag),
              videoStreamIdentity: videoId,
              audioStreamIdentity: videoId,
              videoItag: stream.tag,
              audioItag: audio.tag,
              videoRole: 'video',
              audioRole: 'audio',
            ),
          ),
        );
        final MdPlayerQuality selected = _defaultQuality(qualities);
        return MdPlayerSource(
          videoUrl: selected.videoUrl,
          audioUrl: selected.audioUrl,
          qualityLabel: selected.label,
          qualities: qualities,
          videoCacheKey: selected.videoCacheKey,
          audioCacheKey: selected.audioCacheKey,
          videoStreamIdentity: selected.videoStreamIdentity,
          audioStreamIdentity: selected.audioStreamIdentity,
          videoItag: selected.videoItag,
          audioItag: selected.audioItag,
          videoRole: 'video',
          audioRole: 'audio',
        );
      }

      final List<MdPlayerQuality> muxedQualities = _uniqueQualities(
        manifest.muxed.map(
          (MuxedStreamInfo stream) => MdPlayerQuality(
            label: stream.qualityLabel,
            videoUrl: stream.url.toString(),
            videoCacheKey:
                mdPlayerYoutubeCacheKey(videoId, 'muxed', stream.tag),
            videoStreamIdentity: videoId,
            videoItag: stream.tag,
            videoRole: 'muxed',
          ),
        ),
      );
      if (muxedQualities.isNotEmpty) {
        final MdPlayerQuality selected = _defaultQuality(muxedQualities);
        return MdPlayerSource(
          videoUrl: selected.videoUrl,
          qualityLabel: selected.label,
          qualities: muxedQualities,
          videoCacheKey: selected.videoCacheKey,
          videoStreamIdentity: selected.videoStreamIdentity,
          videoItag: selected.videoItag,
          videoRole: 'muxed',
        );
      }

      final List<MdPlayerQuality> hlsQualities = <MdPlayerQuality>[];
      for (final HlsMuxedStreamInfo stream
          in manifest.hls.whereType<HlsMuxedStreamInfo>()) {
        hlsQualities.add(MdPlayerQuality(
          label: stream.qualityLabel,
          videoUrl: stream.url.toString(),
        ));
      }
      if (hlsQualities.isNotEmpty) {
        final MdPlayerQuality selected = _defaultQuality(hlsQualities);
        return MdPlayerSource(
          videoUrl: selected.videoUrl,
          formatHint: VideoFormat.hls,
          qualityLabel: selected.label,
          qualities: hlsQualities,
        );
      }

      throw StateError('No playable YouTube stream found');
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
        final MdPlayerQuality selected = _defaultQuality(qualities);
        return MdPlayerSource(
          videoUrl: selected.videoUrl,
          qualityLabel: selected.label,
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

  /// Closes the resolver's HTTP client.
  void close() {
    _httpClient.close();
  }
}

List<MdPlayerQuality> _uniqueQualities(Iterable<MdPlayerQuality> qualities) {
  final Map<String, MdPlayerQuality> byLabel = <String, MdPlayerQuality>{};
  for (final MdPlayerQuality quality in qualities) {
    byLabel[quality.label] = quality;
  }
  final List<MdPlayerQuality> result = byLabel.values.toList()
    ..sort((MdPlayerQuality a, MdPlayerQuality b) =>
        _qualityHeight(a.label).compareTo(_qualityHeight(b.label)));
  return result;
}

MdPlayerQuality _defaultQuality(List<MdPlayerQuality> qualities) {
  return qualities.firstWhere(
    (MdPlayerQuality quality) => quality.label == '360p',
    orElse: () => qualities.first,
  );
}

int _qualityHeight(String label) {
  return int.tryParse(RegExp(r'\d+').firstMatch(label)?.group(0) ?? '') ?? 0;
}
