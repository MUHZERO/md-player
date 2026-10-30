import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:md_player_android/md_player_android.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

/// A non-Android platform such as AVFoundation: standard API only.
class _ApplePlatform extends VideoPlayerPlatform {
  final List<String> log = <String>[];
  final Map<int, StreamController<VideoEvent>> events =
      <int, StreamController<VideoEvent>>{};
  final Set<String> failingUris = <String>{};
  int _next = 0;

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    final String uri = options.dataSource.uri!;
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

  test('non-Android players reject separate audio streams', () async {
    final MdPlayerController controller = MdPlayerController.network(
      'video',
      platform: _ApplePlatform(),
      resolver: _Resolver(const MdPlayerSource(
        videoUrl: 'video-only',
        audioUrl: 'audio-only',
      )),
    );
    await expectLater(controller.initialize(), throwsUnsupportedError);
    expect(controller.value.hasError, isTrue);
    await controller.dispose();
  });
}
