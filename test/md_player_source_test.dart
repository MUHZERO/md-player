import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:md_player_android/md_player_android.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

void main() {
  test('cache configuration validates bounds and directory names', () {
    expect(
      () => MdPlayerCacheConfiguration(maxBytes: 1024 * 1024 - 1),
      throwsArgumentError,
    );
    for (final String name in <String>[
      '',
      '.',
      '..',
      '../cache',
      'a/b',
      '/tmp'
    ]) {
      expect(
        () => MdPlayerCacheConfiguration(
          maxBytes: 1024 * 1024,
          directoryName: name,
        ),
        throwsArgumentError,
      );
    }
    final MdPlayerCacheConfiguration value =
        MdPlayerCacheConfiguration(maxBytes: 1024 * 1024);
    expect(value.directoryName, 'md_player_media_cache');
  });

  test('YouTube progressive cache keys are stable and role-specific', () {
    final String first = mdPlayerYoutubeCacheKey('å/video', 'video', 137);
    final String second = mdPlayerYoutubeCacheKey('å/video', 'video', 137);

    expect(first, second);
    expect(first, startsWith('md-player:youtube:'));
    expect(first, isNot(contains('=')));
    expect(
      mdPlayerYoutubeCacheKey('å/video', 'audio', 137),
      isNot(first),
    );
    expect(
      mdPlayerYoutubeCacheKey('å/video', 'video', 136),
      isNot(first),
    );
  });

  test('direct URLs are returned without resolving', () async {
    final MdPlayerSourceResolver resolver = MdPlayerSourceResolver();

    final MdPlayerSource source =
        await resolver.resolve('https://example.com/video.m3u8');

    expect(source.videoUrl, 'https://example.com/video.m3u8');
    expect(source.formatHint, VideoFormat.hls);
    expect(source.audioUrl, isNull);
    expect(source.qualities, isEmpty);
    resolver.close();
  });

  test('Vimeo prefers HLS config URL', () async {
    final MdPlayerSourceResolver resolver = MdPlayerSourceResolver(
      httpClient: MockClient((http.Request request) async {
        expect(request.url.toString(),
            'https://player.vimeo.com/video/123/config');
        return http.Response('''
{
  "request": {
    "files": {
      "hls": {
        "cdns": {
          "fastly": {"url": "https://vimeo.example/video.m3u8"}
        }
      }
    }
  }
}
''', 200);
      }),
    );

    final MdPlayerSource source =
        await resolver.resolve('https://vimeo.com/123');

    expect(source.videoUrl, 'https://vimeo.example/video.m3u8');
    expect(source.formatHint, VideoFormat.hls);
    resolver.close();
  });

  test('Vimeo falls back to progressive MP4 qualities', () async {
    final MdPlayerSourceResolver resolver = MdPlayerSourceResolver(
      httpClient: MockClient((http.Request request) async {
        return http.Response('''
{
  "request": {
    "files": {
      "progressive": [
        {"quality": "360p", "url": "https://vimeo.example/360.mp4"},
        {"quality": "720p", "url": "https://vimeo.example/720.mp4"}
      ]
    }
  }
}
''', 200);
      }),
    );

    final MdPlayerSource source =
        await resolver.resolve('https://vimeo.com/123');

    expect(source.videoUrl, 'https://vimeo.example/360.mp4');
    expect(source.qualityLabel, '360p');
    expect(source.qualities.map((MdPlayerQuality q) => q.label),
        <String>['360p', '720p']);
    resolver.close();
  });

  test('private Vimeo videos return a clear error', () async {
    final MdPlayerSourceResolver resolver = MdPlayerSourceResolver(
      httpClient: MockClient((http.Request request) async {
        return http.Response('private', 403);
      }),
    );

    expect(
      resolver.resolve('https://vimeo.com/123'),
      throwsA(isA<StateError>()),
    );
    resolver.close();
  });

  test('YouTube skips streams that reject open-ended range requests', () async {
    final List<String> probed = <String>[];
    final MdPlayerSourceResolver resolver = MdPlayerSourceResolver(
      httpClient: MockClient((http.Request request) async {
        probed.add('${request.url} ${request.headers['range']}');
        return http.Response('', request.url.path == '/muxed' ? 206 : 403);
      }),
    );
    const MdPlayerSource muxed = MdPlayerSource(
      videoUrl: 'https://g.test/muxed',
      videoRole: 'muxed',
    );

    final MdPlayerSource picked = await resolver.firstPlayableSource(
      const <MdPlayerSource>[
        MdPlayerSource(
          videoUrl: 'https://g.test/video',
          audioUrl: 'https://g.test/audio',
        ),
        muxed,
      ],
    );

    expect(picked, same(muxed));
    expect(probed, <String>[
      'https://g.test/video bytes=0-',
      'https://g.test/muxed bytes=0-',
    ]);
    await expectLater(
      resolver.firstPlayableSource(const <MdPlayerSource>[
        MdPlayerSource(videoUrl: 'https://g.test/video'),
      ]),
      throwsA(isA<StateError>()),
    );
    resolver.close();
  });

  test('YouTube keeps adaptive streams when both parts are accepted', () async {
    final MdPlayerSourceResolver resolver = MdPlayerSourceResolver(
      httpClient: MockClient((http.Request request) async {
        return http.Response('', 206);
      }),
    );
    const MdPlayerSource adaptive = MdPlayerSource(
      videoUrl: 'https://g.test/video',
      audioUrl: 'https://g.test/audio',
    );

    expect(
      await resolver.firstPlayableSource(const <MdPlayerSource>[
        adaptive,
        MdPlayerSource(videoUrl: 'https://g.test/muxed'),
      ]),
      same(adaptive),
    );
    resolver.close();
  });

  test('YouTube adaptive qualities prefer H.264 video and AAC audio', () {
    final MdPlayerSourceResolver resolver = MdPlayerSourceResolver();
    final List<MdPlayerQuality> qualities = resolver
        .youtubeCandidates(
          'aqz-KE-bpKQ',
          StreamManifest(<StreamInfo>[
            _video(396, '360p', 'av01.0.01M.08'),
            _video(134, '360p', 'avc1.4d401e'),
            _video(243, '360p', 'vp9'),
            _video(401, '2160p', 'av01.0.12M.08'),
            _video(315, '2160p', 'vp9'),
            _audio(251, StreamContainer.webM, 'opus', 160000),
            _audio(140, StreamContainer.mp4, 'mp4a.40.2', 130000),
            _audio(139, StreamContainer.mp4, 'mp4a.40.5', 50000),
          ]),
        )
        .single
        .qualities;

    expect(
      qualities.map((MdPlayerQuality quality) =>
          '${quality.label}:${quality.videoItag}:${quality.audioItag}'),
      <String>['360p:134:140', '2160p:315:140'],
    );
    resolver.close();
  });
}

Map<String, dynamic> _stream(
  int tag,
  StreamContainer container,
  String mimeType,
  int bitrate,
) =>
    <String, dynamic>{
      'videoId': VideoId('aqz-KE-bpKQ'),
      'tag': tag,
      'url': 'https://g.test/$tag',
      'container': container,
      'size': const FileSize(1000),
      'bitrate': Bitrate(bitrate),
      'fragments': <Object>[],
      'codec': mimeType,
    };

VideoOnlyStreamInfo _video(int tag, String label, String codec) =>
    VideoOnlyStreamInfo.fromJson(jsonDecode(jsonEncode(<String, dynamic>{
      ..._stream(tag, StreamContainer.mp4, 'video/mp4; codecs="$codec"', 1),
      'videoCodec': codec,
      'qualityLabel': label,
      'videoQuality': 'unknown',
      'videoResolution': const VideoResolution(640, 360),
      'framerate': const Framerate(30),
    })) as Map<String, dynamic>);

AudioOnlyStreamInfo _audio(
  int tag,
  StreamContainer container,
  String codec,
  int bitrate,
) =>
    AudioOnlyStreamInfo.fromJson(jsonDecode(jsonEncode(<String, dynamic>{
      ..._stream(
          tag, container, 'audio/${container.name}; codecs="$codec"', bitrate),
      'audioCodec': codec,
      'qualityLabel': 'audio',
    })) as Map<String, dynamic>);
