import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:md_player_android/md_player_android.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

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
}
