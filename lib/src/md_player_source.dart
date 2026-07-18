import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

class MdPlayerQuality {
  const MdPlayerQuality({
    required this.label,
    required this.videoUrl,
    this.audioUrl,
    this.httpHeaders = const <String, String>{},
    this.videoFormatHint,
    this.audioFormatHint,
    this.videoCacheKey,
    this.audioCacheKey,
    this.videoStreamIdentity,
    this.audioStreamIdentity,
    this.videoItag,
    this.audioItag,
  });

  final String label;
  final String videoUrl;
  final String? audioUrl;
  final Map<String, String> httpHeaders;
  final VideoFormat? videoFormatHint;
  final VideoFormat? audioFormatHint;
  final String? videoCacheKey;
  final String? audioCacheKey;
  final String? videoStreamIdentity;
  final String? audioStreamIdentity;
  final int? videoItag;
  final int? audioItag;
}

class MdPlayerSource {
  const MdPlayerSource({
    required this.videoUrl,
    this.audioUrl,
    this.formatHint,
    this.httpHeaders = const <String, String>{},
    this.qualityLabel = 'auto',
    this.qualities = const <MdPlayerQuality>[],
  });

  final String videoUrl;
  final String? audioUrl;
  final VideoFormat? formatHint;
  final Map<String, String> httpHeaders;
  final String qualityLabel;
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

      if (manifest.videoOnly.isNotEmpty && manifest.audioOnly.isNotEmpty) {
        final String audioUrl = manifest.audioOnly.last.url.toString();
        final List<MdPlayerQuality> qualities = _uniqueQualities(
          manifest.videoOnly.map(
            (VideoOnlyStreamInfo stream) => MdPlayerQuality(
              label: stream.qualityLabel,
              videoUrl: stream.url.toString(),
              audioUrl: audioUrl,
            ),
          ),
        );
        final MdPlayerQuality selected = _defaultQuality(qualities);
        return MdPlayerSource(
          videoUrl: selected.videoUrl,
          audioUrl: selected.audioUrl,
          qualityLabel: selected.label,
          qualities: qualities,
        );
      }

      final List<MdPlayerQuality> muxedQualities = _uniqueQualities(
        manifest.muxed.map(
          (MuxedStreamInfo stream) => MdPlayerQuality(
            label: stream.qualityLabel,
            videoUrl: stream.url.toString(),
          ),
        ),
      );
      if (muxedQualities.isNotEmpty) {
        final MdPlayerQuality selected = _defaultQuality(muxedQualities);
        return MdPlayerSource(
          videoUrl: selected.videoUrl,
          qualityLabel: selected.label,
          qualities: muxedQualities,
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
