import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:md_player_android/md_player_android.dart';
import 'package:md_player_android/src/md_player_hls_bridge.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

/// A non-Android platform such as AVFoundation: standard API only.
class _ApplePlatform extends VideoPlayerPlatform {
  final List<String> log = <String>[];
  final Map<int, StreamController<VideoEvent>> events =
      <int, StreamController<VideoEvent>>{};
  final Set<String> failingUris = <String>{};
  final List<VideoFormat?> formats = <VideoFormat?>[];
  int _next = 0;

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    final String uri = options.dataSource.uri!;
    formats.add(options.dataSource.formatHint);
    final int id = ++_next;
    log.add('create $id $uri');
    final StreamController<VideoEvent> controller =
        StreamController<VideoEvent>();
    events[id] = controller;
    scheduleMicrotask(() {
      if (failingUris.contains(uri)) {
        controller.addError(StateError('cannot open $uri'));
      } else {
        controller.add(VideoEvent(
          eventType: VideoEventType.initialized,
          duration: const Duration(minutes: 1),
          size: const Size(640, 360),
        ));
      }
    });
    return id;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => events[playerId]!.stream;

  @override
  Future<void> dispose(int playerId) async => log.add('dispose $playerId');

  @override
  Future<void> play(int playerId) async => log.add('play $playerId');

  @override
  Future<void> pause(int playerId) async => log.add('pause $playerId');

  @override
  Future<void> seekTo(int playerId, Duration position) async =>
      log.add('seek $playerId ${position.inSeconds}');

  @override
  Future<void> setVolume(int playerId, double volume) async {}

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;
}

class _Bridge extends MdPlayerHlsBridge {
  _Bridge() : super(httpClient: null);
  final List<(String, String)> pairs = <(String, String)>[];

  @override
  Future<String> register({
    required String videoUrl,
    required String audioUrl,
    Map<String, String> httpHeaders = const <String, String>{},
    Map<String, String>? audioHttpHeaders,
  }) async {
    pairs.add((videoUrl, audioUrl));
    return 'http://127.0.0.1:1/${pairs.length}/master.m3u8';
  }
}

class _Resolver extends MdPlayerSourceResolver {
  _Resolver(this.source);
  final MdPlayerSource source;

  @override
  Future<MdPlayerSource> resolve(String input) async => source;
}

const MdPlayerQuality _low = MdPlayerQuality(label: '360p', videoUrl: 'low');
const MdPlayerQuality _high = MdPlayerQuality(label: '720p', videoUrl: 'high');

void main() {
  test('non-Android quality switch re-creates the player at the position',
      () async {
    final _ApplePlatform platform = _ApplePlatform();
    final MdPlayerController controller = MdPlayerController.network(
      'video',
      platform: platform,
      resolver: _Resolver(const MdPlayerSource(
        videoUrl: 'low',
        qualityLabel: '360p',
        qualities: <MdPlayerQuality>[_low, _high],
      )),
    );
    await controller.initialize();
    await controller.play();
    controller.value =
        controller.value.copyWith(position: const Duration(seconds: 42));
    platform.log.clear();

    await controller.setQuality(_high);

    expect(platform.log, <String>[
      'dispose 1',
      'create 2 high',
      'seek 2 42',
      'play 2',
    ]);
    expect(controller.value.qualityLabel, '720p');
    expect(controller.confirmedQuality, same(_high));
    expect(controller.qualitySwitchState.value.status,
        MdQualitySwitchStatus.completed);
    await controller.dispose();
  });

  test('a failed non-Android switch rolls back to the previous stream',
      () async {
    final _ApplePlatform platform = _ApplePlatform()..failingUris.add('high');
    final MdPlayerController controller = MdPlayerController.network(
      'video',
      platform: platform,
      resolver: _Resolver(const MdPlayerSource(
        videoUrl: 'low',
        qualityLabel: '360p',
        qualities: <MdPlayerQuality>[_low, _high],
      )),
    );
    await controller.initialize();
    controller.value =
        controller.value.copyWith(position: const Duration(seconds: 7));

    await controller.setQuality(_high);

    expect(platform.log.where((String entry) => entry.startsWith('create')),
        <String>['create 1 low', 'create 2 high', 'create 3 low']);
    expect(platform.log.last, 'seek 3 7');
    final MdQualitySwitchState state = controller.qualitySwitchState.value;
    expect(state.status, MdQualitySwitchStatus.failed);
    expect(state.rollbackSucceeded, isTrue);
    expect(controller.value.qualityLabel, '360p');
    expect(controller.value.hasError, isFalse);
    await controller.dispose();
  });

  test('non-Android players merge separate streams through HLS', () async {
    final _ApplePlatform platform = _ApplePlatform();
    final _Bridge bridge = _Bridge();
    final MdPlayerController controller = MdPlayerController.network(
      'video',
      platform: platform,
      hlsBridge: bridge,
      resolver: _Resolver(const MdPlayerSource(
        videoUrl: 'video-360',
        audioUrl: 'audio',
        qualityLabel: '360p',
        qualities: <MdPlayerQuality>[
          MdPlayerQuality(
              label: '360p', videoUrl: 'video-360', audioUrl: 'audio'),
          MdPlayerQuality(
              label: '720p', videoUrl: 'video-720', audioUrl: 'audio'),
        ],
      )),
    );
    await controller.initialize();
    expect(controller.value.isInitialized, isTrue);
    await controller.setQuality(controller.value.qualities.last);

    expect(bridge.pairs, <(String, String)>[
      ('video-360', 'audio'),
      ('video-720', 'audio'),
    ]);
    expect(
        platform.log.where((String entry) => entry.startsWith('create')),
        <String>[
          'create 1 http://127.0.0.1:1/1/master.m3u8',
          'create 2 http://127.0.0.1:1/2/master.m3u8',
        ]);
    expect(platform.formats, <VideoFormat?>[VideoFormat.hls, VideoFormat.hls]);
    expect(controller.value.qualityLabel, '720p');
    await controller.dispose();
  });
}
