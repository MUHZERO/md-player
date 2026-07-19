// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:md_player_android/src/messages.g.dart';
import 'package:md_player_android/md_player_android.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'test_api.g.dart';

class _ApiLogger implements TestHostVideoPlayerApi {
  final List<String> log = <String>[];
  bool throwOnPlay = false;
  TextureMessage? textureMessage;
  CreateMessage? createMessage;
  PositionMessage? positionMessage;
  LoopingMessage? loopingMessage;
  VolumeMessage? volumeMessage;
  PlaybackSpeedMessage? playbackSpeedMessage;
  MixWithOthersMessage? mixWithOthersMessage;
  ChangeQualityMessage? changeQualityMessage;
  CacheConfigurationMessage? cacheConfigurationMessage;
  CacheStatsMessage cacheStatsMessage = CacheStatsMessage(
    enabled: false,
    currentBytes: 0,
    maxBytes: 0,
    cachedResources: 0,
    cacheReadBytes: 0,
    upstreamReadBytes: 0,
    cacheReadOperations: 0,
    upstreamOpenOperations: 0,
  );

  @override
  TextureMessage create(CreateMessage arg) {
    log.add('create');
    createMessage = arg;
    return TextureMessage(textureId: 3);
  }

  @override
  void dispose(TextureMessage arg) {
    log.add('dispose');
    textureMessage = arg;
  }

  @override
  void initialize() {
    log.add('init');
  }

  @override
  void pause(TextureMessage arg) {
    log.add('pause');
    textureMessage = arg;
  }

  @override
  void play(TextureMessage arg) {
    log.add('play');
    textureMessage = arg;
    if (throwOnPlay) {
      throw PlatformException(code: 'VideoError', message: 'Source error');
    }
  }

  @override
  void setMixWithOthers(MixWithOthersMessage arg) {
    log.add('setMixWithOthers');
    mixWithOthersMessage = arg;
  }

  @override
  PositionMessage position(TextureMessage arg) {
    log.add('position');
    textureMessage = arg;
    return PositionMessage(textureId: arg.textureId, position: 234);
  }

  @override
  void seekTo(PositionMessage arg) {
    log.add('seekTo');
    positionMessage = arg;
  }

  @override
  void setLooping(LoopingMessage arg) {
    log.add('setLooping');
    loopingMessage = arg;
  }

  @override
  void setVolume(VolumeMessage arg) {
    log.add('setVolume');
    volumeMessage = arg;
  }

  @override
  void setPlaybackSpeed(PlaybackSpeedMessage arg) {
    log.add('setPlaybackSpeed');
    playbackSpeedMessage = arg;
  }

  @override
  void changeQuality(ChangeQualityMessage arg) {
    log.add('changeQuality');
    changeQualityMessage = arg;
  }

  @override
  void configureCache(CacheConfigurationMessage arg) {
    log.add('configureCache');
    cacheConfigurationMessage = arg;
  }

  @override
  void disableCache() {
    log.add('disableCache');
  }

  @override
  CacheStatsMessage cacheStats() {
    log.add('cacheStats');
    return cacheStatsMessage;
  }

  @override
  void clearCache() {
    log.add('clearCache');
  }

  @override
  void removeCachedVideo(String videoId) {
    log.add('removeCachedVideo');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('registration', () async {
    MdPlayerAndroid.registerWith();
    expect(VideoPlayerPlatform.instance, isA<MdPlayerAndroid>());
  });

  group('$MdPlayerAndroid', () {
    final MdPlayerAndroid player = MdPlayerAndroid();
    late _ApiLogger log;

    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      log = _ApiLogger();
      TestHostVideoPlayerApi.setUp(log);
    });

    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
    });

    test('cache facade validates platform and maps Pigeon statistics',
        () async {
      await MdPlayerCache.configure(
        MdPlayerCacheConfiguration(
          maxBytes: 2 * 1024 * 1024,
          directoryName: 'media-cache',
        ),
      );
      expect(log.cacheConfigurationMessage?.maxBytes, 2 * 1024 * 1024);
      expect(log.cacheConfigurationMessage?.directoryName, 'media-cache');

      log.cacheStatsMessage = CacheStatsMessage(
        enabled: true,
        currentBytes: 11,
        maxBytes: 22,
        cachedResources: 2,
        cacheReadBytes: 3,
        upstreamReadBytes: 4,
        cacheReadOperations: 5,
        upstreamOpenOperations: 6,
      );
      final MdPlayerCacheStats stats = await MdPlayerCache.stats();
      expect(stats.enabled, isTrue);
      expect(stats.currentBytes, 11);
      expect(stats.maxBytes, 22);
      expect(stats.cachedResources, 2);
      expect(stats.cacheReadBytes, 3);
      expect(stats.upstreamReadBytes, 4);
      expect(stats.cacheReadOperations, 5);
      expect(stats.upstreamOpenOperations, 6);

      await MdPlayerCache.disable();
      await MdPlayerCache.removeVideo('abc');
      await MdPlayerCache.clear();
      expect(
          log.log,
          containsAll(<String>[
            'disableCache',
            'removeCachedVideo',
            'clearCache',
          ]));
    });

    test('cache facade is unsupported outside Android', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(
        () => MdPlayerCache.configure(
          MdPlayerCacheConfiguration(maxBytes: 1024 * 1024),
        ),
        throwsUnsupportedError,
      );
      expect(MdPlayerCache.stats(), throwsUnsupportedError);
      expect(() => MdPlayerCache.disable(), throwsUnsupportedError);
      expect(() => MdPlayerCache.clear(), throwsUnsupportedError);
      expect(() => MdPlayerCache.removeVideo('abc'), throwsUnsupportedError);
    });

    test('initial metadata and source-local headers are copied', () async {
      final Map<String, String> videoHeaders = <String, String>{
        'Role': 'video'
      };
      final Map<String, String> audioHeaders = <String, String>{
        'Role': 'audio'
      };
      await player.createMdSource(
        videoUri: 'https://example.test/video',
        audioUri: 'https://example.test/audio',
        httpHeaders: videoHeaders,
        audioHttpHeaders: audioHeaders,
        videoCacheKey: 'video-key',
        audioCacheKey: 'audio-key',
        videoStreamIdentity: 'abc',
        audioStreamIdentity: 'abc',
        videoItag: 137,
        audioItag: 140,
        videoRole: 'video',
        audioRole: 'audio',
      );
      videoHeaders['Role'] = 'changed';
      audioHeaders['Role'] = 'changed';

      expect(log.createMessage?.httpHeaders, <String, String>{'Role': 'video'});
      expect(log.createMessage?.audioHttpHeaders,
          <String, String>{'Role': 'audio'});
      expect(log.createMessage?.videoCacheKey, 'video-key');
      expect(log.createMessage?.audioCacheKey, 'audio-key');
      expect(log.createMessage?.videoItag, 137);
      expect(log.createMessage?.audioItag, 140);
      expect(log.createMessage?.videoRole, 'video');
      expect(log.createMessage?.audioRole, 'audio');
    });

    test('init', () async {
      await player.init();
      expect(
        log.log.last,
        'init',
      );
    });

    test('dispose', () async {
      await player.dispose(1);
      expect(log.log.last, 'dispose');
      expect(log.textureMessage?.textureId, 1);
    });

    test('create with asset', () async {
      final int? textureId = await player.create(DataSource(
        sourceType: DataSourceType.asset,
        asset: 'someAsset',
        package: 'somePackage',
      ));
      expect(log.log.last, 'create');
      expect(log.createMessage?.asset, 'someAsset');
      expect(log.createMessage?.packageName, 'somePackage');
      expect(textureId, 3);
    });

    test('create with network', () async {
      final int? textureId = await player.create(DataSource(
        sourceType: DataSourceType.network,
        uri: 'someUri',
        formatHint: VideoFormat.dash,
      ));
      expect(log.log.last, 'create');
      expect(log.createMessage?.asset, null);
      expect(log.createMessage?.uri, 'someUri');
      expect(log.createMessage?.packageName, null);
      expect(log.createMessage?.formatHint, 'dash');
      expect(log.createMessage?.httpHeaders, <String, String>{});
      expect(textureId, 3);
    });

    test('create with network (some headers)', () async {
      final int? textureId = await player.create(DataSource(
        sourceType: DataSourceType.network,
        uri: 'someUri',
        httpHeaders: <String, String>{'Authorization': 'Bearer token'},
      ));
      expect(log.log.last, 'create');
      expect(log.createMessage?.asset, null);
      expect(log.createMessage?.uri, 'someUri');
      expect(log.createMessage?.packageName, null);
      expect(log.createMessage?.formatHint, null);
      expect(log.createMessage?.httpHeaders,
          <String, String>{'Authorization': 'Bearer token'});
      expect(textureId, 3);
    });

    test('create with network audio', () async {
      final int? textureId = await player.createWithAudio(
        videoUri: 'videoUri',
        audioUri: 'audioUri',
        formatHint: VideoFormat.dash,
        httpHeaders: <String, String>{'Authorization': 'Bearer token'},
      );
      expect(log.log.last, 'create');
      expect(log.createMessage?.asset, null);
      expect(log.createMessage?.uri, 'videoUri');
      expect(log.createMessage?.audioUri, 'audioUri');
      expect(log.createMessage?.formatHint, 'dash');
      expect(log.createMessage?.httpHeaders,
          <String, String>{'Authorization': 'Bearer token'});
      expect(textureId, 3);
    });

    test('create with file', () async {
      final int? textureId = await player.create(DataSource(
        sourceType: DataSourceType.file,
        uri: 'someUri',
      ));
      expect(log.log.last, 'create');
      expect(log.createMessage?.uri, 'someUri');
      expect(textureId, 3);
    });

    test('create with file (some headers)', () async {
      final int? textureId = await player.create(DataSource(
        sourceType: DataSourceType.file,
        uri: 'someUri',
        httpHeaders: <String, String>{'Authorization': 'Bearer token'},
      ));
      expect(log.log.last, 'create');
      expect(log.createMessage?.uri, 'someUri');
      expect(log.createMessage?.httpHeaders,
          <String, String>{'Authorization': 'Bearer token'});
      expect(textureId, 3);
    });
    test('setLooping', () async {
      await player.setLooping(1, true);
      expect(log.log.last, 'setLooping');
      expect(log.loopingMessage?.textureId, 1);
      expect(log.loopingMessage?.isLooping, true);
    });

    test('play', () async {
      await player.play(1);
      expect(log.log.last, 'play');
      expect(log.textureMessage?.textureId, 1);
    });

    test('changeQuality', () async {
      await player.changeQuality(
        1,
        'newUri',
        operationId: 'operation-1',
        audioUri: 'audioUri',
        httpHeaders: const <String, String>{'Authorization': 'token'},
        videoFormatHint: VideoFormat.dash,
        audioFormatHint: VideoFormat.other,
        videoCacheKey: 'video-cache',
        audioCacheKey: 'audio-cache',
        videoStreamIdentity: 'video-stream',
        audioStreamIdentity: 'audio-stream',
        videoItag: 22,
        audioItag: 140,
        requestedLabel: '720p',
      );
      expect(log.log.last, 'changeQuality');
      expect(log.changeQualityMessage?.textureId, 1);
      expect(log.changeQualityMessage?.newUrl, 'newUri');
      expect(log.changeQualityMessage?.videoUri, 'newUri');
      expect(log.changeQualityMessage?.operationId, 'operation-1');
      expect(log.changeQualityMessage?.audioUri, 'audioUri');
      expect(log.changeQualityMessage?.videoFormatHint, 'dash');
      expect(log.changeQualityMessage?.audioFormatHint, 'other');
      expect(log.changeQualityMessage?.videoCacheKey, 'video-cache');
      expect(log.changeQualityMessage?.audioItag, 140);
      expect(log.changeQualityMessage?.requestedLabel, '720p');
    });

    test('standard and quality projections share one channel listen', () async {
      const String mockChannel = 'flutter.io/videoPlayer/videoEvents321';
      int listens = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMessageHandler(mockChannel, (ByteData? message) async {
        final MethodCall call =
            const StandardMethodCodec().decodeMethodCall(message);
        if (call.method == 'listen') {
          listens++;
        }
        return const StandardMethodCodec().encodeSuccessEnvelope(null);
      });

      final StreamSubscription<VideoEvent> standard =
          player.videoEventsFor(321).listen((_) {});
      final StreamSubscription<MdQualitySwitchEvent> quality =
          player.qualityEventsFor(321).listen((_) {});
      await pumpEventQueue();

      expect(listens, 1);
      await standard.cancel();
      await quality.cancel();
      await player.dispose(321);
    });

    test('pause', () async {
      await player.pause(1);
      expect(log.log.last, 'pause');
      expect(log.textureMessage?.textureId, 1);
    });

    test('setMixWithOthers', () async {
      await player.setMixWithOthers(true);
      expect(log.log.last, 'setMixWithOthers');
      expect(log.mixWithOthersMessage?.mixWithOthers, true);

      await player.setMixWithOthers(false);
      expect(log.log.last, 'setMixWithOthers');
      expect(log.mixWithOthersMessage?.mixWithOthers, false);
    });

    test('setVolume', () async {
      await player.setVolume(1, 0.7);
      expect(log.log.last, 'setVolume');
      expect(log.volumeMessage?.textureId, 1);
      expect(log.volumeMessage?.volume, 0.7);
    });

    test('setPlaybackSpeed', () async {
      await player.setPlaybackSpeed(1, 1.5);
      expect(log.log.last, 'setPlaybackSpeed');
      expect(log.playbackSpeedMessage?.textureId, 1);
      expect(log.playbackSpeedMessage?.speed, 1.5);
    });

    test('seekTo', () async {
      await player.seekTo(1, const Duration(milliseconds: 12345));
      expect(log.log.last, 'seekTo');
      expect(log.positionMessage?.textureId, 1);
      expect(log.positionMessage?.position, 12345);
    });

    test('getPosition', () async {
      final Duration position = await player.getPosition(1);
      expect(log.log.last, 'position');
      expect(log.textureMessage?.textureId, 1);
      expect(position, const Duration(milliseconds: 234));
    });

    test('videoEventsFor', () async {
      const String mockChannel = 'flutter.io/videoPlayer/videoEvents123';
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMessageHandler(
        mockChannel,
        (ByteData? message) async {
          final MethodCall methodCall =
              const StandardMethodCodec().decodeMethodCall(message);
          if (methodCall.method == 'listen') {
            await TestDefaultBinaryMessengerBinding
                .instance.defaultBinaryMessenger
                .handlePlatformMessage(
                    mockChannel,
                    const StandardMethodCodec()
                        .encodeSuccessEnvelope(<String, dynamic>{
                      'event': 'initialized',
                      'duration': 98765,
                      'width': 1920,
                      'height': 1080,
                    }),
                    (ByteData? data) {});

            await TestDefaultBinaryMessengerBinding
                .instance.defaultBinaryMessenger
                .handlePlatformMessage(
                    mockChannel,
                    const StandardMethodCodec()
                        .encodeSuccessEnvelope(<String, dynamic>{
                      'event': 'initialized',
                      'duration': 98765,
                      'width': 1920,
                      'height': 1080,
                      'rotationCorrection': 180,
                    }),
                    (ByteData? data) {});

            await TestDefaultBinaryMessengerBinding
                .instance.defaultBinaryMessenger
                .handlePlatformMessage(
                    mockChannel,
                    const StandardMethodCodec()
                        .encodeSuccessEnvelope(<String, dynamic>{
                      'event': 'completed',
                    }),
                    (ByteData? data) {});

            await TestDefaultBinaryMessengerBinding
                .instance.defaultBinaryMessenger
                .handlePlatformMessage(
                    mockChannel,
                    const StandardMethodCodec()
                        .encodeSuccessEnvelope(<String, dynamic>{
                      'event': 'bufferingUpdate',
                      'values': <List<dynamic>>[
                        <int>[0, 1234],
                        <int>[1235, 4000],
                      ],
                    }),
                    (ByteData? data) {});

            await TestDefaultBinaryMessengerBinding
                .instance.defaultBinaryMessenger
                .handlePlatformMessage(
                    mockChannel,
                    const StandardMethodCodec()
                        .encodeSuccessEnvelope(<String, dynamic>{
                      'event': 'bufferingStart',
                    }),
                    (ByteData? data) {});

            await TestDefaultBinaryMessengerBinding
                .instance.defaultBinaryMessenger
                .handlePlatformMessage(
                    mockChannel,
                    const StandardMethodCodec()
                        .encodeSuccessEnvelope(<String, dynamic>{
                      'event': 'bufferingEnd',
                    }),
                    (ByteData? data) {});

            await TestDefaultBinaryMessengerBinding
                .instance.defaultBinaryMessenger
                .handlePlatformMessage(
                    mockChannel,
                    const StandardMethodCodec()
                        .encodeSuccessEnvelope(<String, dynamic>{
                      'event': 'isPlayingStateUpdate',
                      'isPlaying': true,
                    }),
                    (ByteData? data) {});

            await TestDefaultBinaryMessengerBinding
                .instance.defaultBinaryMessenger
                .handlePlatformMessage(
                    mockChannel,
                    const StandardMethodCodec()
                        .encodeSuccessEnvelope(<String, dynamic>{
                      'event': 'isPlayingStateUpdate',
                      'isPlaying': false,
                    }),
                    (ByteData? data) {});

            return const StandardMethodCodec().encodeSuccessEnvelope(null);
          } else if (methodCall.method == 'cancel') {
            return const StandardMethodCodec().encodeSuccessEnvelope(null);
          } else {
            fail('Expected listen or cancel');
          }
        },
      );
      expect(
          player.videoEventsFor(123),
          emitsInOrder(<dynamic>[
            VideoEvent(
              eventType: VideoEventType.initialized,
              duration: const Duration(milliseconds: 98765),
              size: const Size(1920, 1080),
              rotationCorrection: 0,
            ),
            VideoEvent(
              eventType: VideoEventType.initialized,
              duration: const Duration(milliseconds: 98765),
              size: const Size(1920, 1080),
              rotationCorrection: 180,
            ),
            VideoEvent(eventType: VideoEventType.completed),
            VideoEvent(
                eventType: VideoEventType.bufferingUpdate,
                buffered: <DurationRange>[
                  DurationRange(
                    Duration.zero,
                    const Duration(milliseconds: 1234),
                  ),
                  DurationRange(
                    const Duration(milliseconds: 1235),
                    const Duration(milliseconds: 4000),
                  ),
                ]),
            VideoEvent(eventType: VideoEventType.bufferingStart),
            VideoEvent(eventType: VideoEventType.bufferingEnd),
            VideoEvent(
              eventType: VideoEventType.isPlayingStateUpdate,
              isPlaying: true,
            ),
            VideoEvent(
              eventType: VideoEventType.isPlayingStateUpdate,
              isPlaying: false,
            ),
          ]));
    });

    test('controller play stores platform errors', () async {
      MdPlayerAndroid.registerWith();
      log.throwOnPlay = true;
      const String mockChannel = 'flutter.io/videoPlayer/videoEvents3';
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMessageHandler(
        mockChannel,
        (ByteData? message) async {
          final MethodCall methodCall =
              const StandardMethodCodec().decodeMethodCall(message);
          if (methodCall.method == 'listen') {
            await TestDefaultBinaryMessengerBinding
                .instance.defaultBinaryMessenger
                .handlePlatformMessage(
                    mockChannel,
                    const StandardMethodCodec()
                        .encodeSuccessEnvelope(<String, dynamic>{
                      'event': 'initialized',
                      'duration': 98765,
                      'width': 1920,
                      'height': 1080,
                    }),
                    (ByteData? data) {});
          }
          return const StandardMethodCodec().encodeSuccessEnvelope(null);
        },
      );

      final MdPlayerController controller = MdPlayerController.network(
        'https://example.com/video.mp4',
      );
      await controller.initialize();
      await controller.play();

      expect(controller.value.hasError, true);
      expect(controller.value.errorDescription, 'Source error');
      await controller.dispose();
    });
  });
}
