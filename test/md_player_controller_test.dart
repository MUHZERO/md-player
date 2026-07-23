import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:md_player_android/md_player_android.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

class _Resolver extends MdPlayerSourceResolver {
  final List<Completer<MdPlayerSource>> requests =
      <Completer<MdPlayerSource>>[];

  @override
  Future<MdPlayerSource> resolve(String input) {
    final Completer<MdPlayerSource> request = Completer<MdPlayerSource>();
    requests.add(request);
    return request.future;
  }
}

class _Platform extends MdPlayerAndroid {
  final List<Completer<int?>> creations = <Completer<int?>>[];
  final Map<int, StreamController<MdPlayerPlatformEvent>> events =
      <int, StreamController<MdPlayerPlatformEvent>>{};
  final List<int> disposed = <int>[];
  final List<int> played = <int>[];
  final List<int> paused = <int>[];
  final List<int> positionTargets = <int>[];
  final List<Completer<Duration>> positions = <Completer<Duration>>[];
  final List<(int, Duration)> seeks = <(int, Duration)>[];
  final List<(int, double)> speeds = <(int, double)>[];
  final List<(int, double)> volumes = <(int, double)>[];
  final List<Completer<void>> qualityChanges = <Completer<void>>[];
  final List<(int, String)> qualityTargets = <(int, String)>[];
  final List<String?> qualityOperationIds = <String?>[];
  final List<String?> qualityAudioUris = <String?>[];
  Completer<void>? nextPlay;
  Completer<void>? nextDispose;
  Completer<void>? nextVolume;
  Object? creationError;
  int initCalls = 0;

  @override
  Future<void> init() async {
    initCalls++;
  }

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) {
    return _create();
  }

  @override
  Future<int?> createWithAudio({
    required String videoUri,
    required String audioUri,
    VideoFormat? formatHint,
    Map<String, String> httpHeaders = const <String, String>{},
    Map<String, String>? audioHttpHeaders,
  }) {
    return _create();
  }

  Future<int?> _create() {
    final Completer<int?> creation = Completer<int?>();
    creations.add(creation);
    final Object? error = creationError;
    if (error != null) {
      scheduleMicrotask(() => creation.completeError(error));
    }
    return creation.future;
  }

  @override
  Stream<MdPlayerPlatformEvent> playerEventsFor(int textureId) {
    return (events[textureId] ??=
            StreamController<MdPlayerPlatformEvent>.broadcast(sync: true))
        .stream;
  }

  void emit(int textureId, VideoEvent event) {
    events[textureId]!.add(MdPlayerPlatformEvent.video(event));
  }

  void emitQuality(int textureId, MdQualitySwitchEvent event) {
    events[textureId]!.add(MdPlayerPlatformEvent.quality(event));
  }

  @override
  Future<void> dispose(int textureId) async {
    disposed.add(textureId);
    final Completer<void>? pending = nextDispose;
    nextDispose = null;
    await pending?.future;
  }

  @override
  Future<void> setVolume(int textureId, double volume) async {
    volumes.add((textureId, volume));
    final Completer<void>? pending = nextVolume;
    nextVolume = null;
    await pending?.future;
  }

  @override
  Future<void> play(int textureId) {
    played.add(textureId);
    final Completer<void>? pending = nextPlay;
    nextPlay = null;
    return pending?.future ?? Future<void>.value();
  }

  @override
  Future<void> pause(int textureId) async {
    paused.add(textureId);
  }

  @override
  Future<void> setPlaybackSpeed(int textureId, double speed) async {
    speeds.add((textureId, speed));
  }

  @override
  Future<void> seekTo(int textureId, Duration position) async {
    seeks.add((textureId, position));
  }

  @override
  Future<Duration> getPosition(int textureId) {
    positionTargets.add(textureId);
    final Completer<Duration> position = Completer<Duration>();
    positions.add(position);
    return position.future;
  }

  @override
  Future<void> changeQuality(
    int textureId,
    String newQuality, {
    String? operationId,
    String? audioUri,
    Map<String, String> httpHeaders = const <String, String>{},
    Map<String, String>? audioHttpHeaders,
    VideoFormat? videoFormatHint,
    VideoFormat? audioFormatHint,
    String? videoCacheKey,
    String? audioCacheKey,
    String? videoStreamIdentity,
    String? audioStreamIdentity,
    int? videoItag,
    int? audioItag,
    String? videoRole,
    String? audioRole,
    String? requestedLabel,
  }) {
    qualityTargets.add((textureId, newQuality));
    qualityOperationIds.add(operationId);
    qualityAudioUris.add(audioUri);
    final Completer<void> change = Completer<void>();
    qualityChanges.add(change);
    return change.future;
  }
}

VideoEvent _initialized([Duration duration = const Duration(seconds: 30)]) {
  return VideoEvent(
    eventType: VideoEventType.initialized,
    duration: duration,
    size: const Size(640, 360),
  );
}

Future<void> _flush() => pumpEventQueue();

Future<void> _finishInitialization(
  Future<void> initialization,
  _Resolver resolver,
  _Platform platform,
  int textureId, {
  MdPlayerSource source = const MdPlayerSource(videoUrl: 'video'),
}) async {
  await _flush();
  resolver.requests.last.complete(source);
  await _flush();
  platform.creations.last.complete(textureId);
  await _flush();
  platform.emit(textureId, _initialized());
  await initialization;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('copyWith preserves, clears, and replaces errors', () {
    const MdPlayerValue value = MdPlayerValue.erroneous('old');

    expect(value.copyWith().errorDescription, 'old');
    expect(value.copyWith(errorDescription: null).errorDescription, isNull);
    expect(value.copyWith(errorDescription: 'new').errorDescription, 'new');
  });

  test('latest initialization wins and never initializes the platform',
      () async {
    final _Resolver resolver = _Resolver();
    final _Platform platform = _Platform();
    final MdPlayerController controller = MdPlayerController.network(
      'url',
      resolver: resolver,
      platform: platform,
    );

    final Future<void> first = controller.initialize();
    await _flush();
    final Future<void> second = controller.initialize();
    await first.timeout(const Duration(seconds: 1));
    await _finishInitialization(second, resolver, platform, 2);
    resolver.requests.first.complete(const MdPlayerSource(videoUrl: 'stale'));
    await _flush();

    expect(controller.textureId, 2);
    expect(platform.creations, hasLength(1));
    expect(platform.initCalls, 0);
    await controller.dispose();
  });

  test('slow first creation is cleaned after fast second creation', () async {
    final _Resolver resolver = _Resolver();
    final _Platform platform = _Platform();
    final MdPlayerController controller = MdPlayerController.network(
      'url',
      resolver: resolver,
      platform: platform,
    );

    final Future<void> first = controller.initialize();
    await _flush();
    resolver.requests.single.complete(const MdPlayerSource(videoUrl: 'first'));
    await _flush();
    final Completer<int?> slowCreation = platform.creations.single;
    final Future<void> second = controller.initialize();
    await first.timeout(const Duration(seconds: 1));
    await _finishInitialization(second, resolver, platform, 2,
        source: const MdPlayerSource(videoUrl: 'second'));
    slowCreation.complete(1);
    await _flush();

    expect(controller.textureId, 2);
    expect(platform.disposed, contains(1));
    await controller.dispose();
  });

  test('old texture events cannot update a replacement', () async {
    final _Resolver resolver = _Resolver();
    final _Platform platform = _Platform();
    final MdPlayerController controller = MdPlayerController.network(
      'url',
      resolver: resolver,
      platform: platform,
    );
    await _finishInitialization(controller.initialize(), resolver, platform, 1);
    final Future<void> replacement = controller.initialize();
    await _finishInitialization(replacement, resolver, platform, 2);

    platform.emit(1, _initialized(const Duration(seconds: 99)));
    expect(controller.value.duration, const Duration(seconds: 30));
    expect(platform.disposed.where((int id) => id == 1), hasLength(1));
    await controller.dispose();
  });

  test('current creation failures are published and thrown', () async {
    final _Resolver resolver = _Resolver();
    final _Platform platform = _Platform()
      ..creationError = StateError('create failed');
    final MdPlayerController controller = MdPlayerController.network(
      'url',
      resolver: resolver,
      platform: platform,
    );
    final Future<void> initialization = controller.initialize();
    await _flush();
    resolver.requests.single.complete(const MdPlayerSource(videoUrl: 'video'));

    await expectLater(initialization, throwsStateError);
    expect(controller.value.errorDescription, contains('create failed'));
    await controller.dispose();
  });

  test('dispose during resolution cancels initialization', () async {
    final _Resolver resolver = _Resolver();
    final _Platform platform = _Platform();
    final MdPlayerController controller = MdPlayerController.network('url',
        resolver: resolver, platform: platform);
    final Future<void> initialization = controller.initialize();
    await _flush();

    await controller.dispose();
    await initialization.timeout(const Duration(seconds: 1));
    resolver.requests.single.complete(const MdPlayerSource(videoUrl: 'late'));
    await _flush();
    expect(platform.creations, isEmpty);
  });

  test('dispose during creation cleans a late texture', () async {
    final _Resolver resolver = _Resolver();
    final _Platform platform = _Platform();
    final MdPlayerController controller = MdPlayerController.network('url',
        resolver: resolver, platform: platform);
    final Future<void> initialization = controller.initialize();
    await _flush();
    resolver.requests.single.complete(const MdPlayerSource(videoUrl: 'video'));
    await _flush();

    await controller.dispose();
    await initialization.timeout(const Duration(seconds: 1));
    platform.creations.single.complete(4);
    await _flush();
    expect(platform.disposed, <int>[4]);
  });

  test('dispose while waiting for initialized event is idempotent', () async {
    final _Resolver resolver = _Resolver();
    final _Platform platform = _Platform();
    final MdPlayerController controller = MdPlayerController.network('url',
        resolver: resolver, platform: platform);
    final Future<void> initialization = controller.initialize();
    await _flush();
    resolver.requests.single.complete(const MdPlayerSource(videoUrl: 'video'));
    await _flush();
    platform.creations.single.complete(5);
    await _flush();

    final Future<void> firstDispose = controller.dispose();
    final Future<void> secondDispose = controller.dispose();
    await Future.wait(
        <Future<void>>[firstDispose, secondDispose, initialization]);
    platform.emit(5, _initialized(const Duration(seconds: 99)));
    expect(platform.disposed, <int>[5]);
  });

  test('dispose waits for ownership already captured by replacement', () async {
    final _Resolver resolver = _Resolver();
    final _Platform platform = _Platform();
    final MdPlayerController controller = MdPlayerController.network('url',
        resolver: resolver, platform: platform);
    await _finishInitialization(
        controller.initialize(), resolver, platform, 15);
    final Completer<void> nativeDispose = Completer<void>();
    platform.nextDispose = nativeDispose;

    final Future<void> replacement = controller.initialize();
    final Future<void> disposal = controller.dispose();
    bool disposed = false;
    disposal.then((_) => disposed = true);
    await _flush();
    expect(disposed, isFalse);
    nativeDispose.complete();
    await Future.wait(<Future<void>>[replacement, disposal]);
    expect(platform.disposed, <int>[15]);
  });

  test('polling is serialized and targets the current texture', () async {
    final _Resolver resolver = _Resolver();
    final _Platform platform = _Platform();
    final MdPlayerController controller = MdPlayerController.network('url',
        resolver: resolver, platform: platform);
    await _finishInitialization(controller.initialize(), resolver, platform, 6);
    await controller.play();

    await Future<void>.delayed(const Duration(milliseconds: 550));
    await Future<void>.delayed(const Duration(milliseconds: 550));
    expect(platform.positions, hasLength(1));
    expect(platform.positionTargets, <int>[6]);
    platform.positions.single.complete(const Duration(seconds: 1));
    await _flush();
    await Future<void>.delayed(const Duration(milliseconds: 550));
    expect(platform.positions, hasLength(2));
    platform.positions.last.complete(const Duration(seconds: 2));
    await _flush();
    await controller.dispose();
  });

  test('late polling cannot overwrite seek or pause', () async {
    final _Resolver resolver = _Resolver();
    final _Platform platform = _Platform();
    final MdPlayerController controller = MdPlayerController.network('url',
        resolver: resolver, platform: platform);
    await _finishInitialization(controller.initialize(), resolver, platform, 7);
    await controller.play();
    await Future<void>.delayed(const Duration(milliseconds: 550));
    final Completer<Duration> poll = platform.positions.single;

    await controller.seekTo(const Duration(seconds: 8));
    await controller.pause();
    poll.complete(const Duration(seconds: 2));
    await _flush();
    expect(controller.value.position, const Duration(seconds: 8));
    await controller.dispose();
  });

  test('late polling cannot overwrite a replacement', () async {
    final _Resolver resolver = _Resolver();
    final _Platform platform = _Platform();
    final MdPlayerController controller = MdPlayerController.network('url',
        resolver: resolver, platform: platform);
    await _finishInitialization(controller.initialize(), resolver, platform, 8);
    await controller.play();
    await Future<void>.delayed(const Duration(milliseconds: 550));
    final Completer<Duration> oldPoll = platform.positions.single;
    final Future<void> replacement = controller.initialize();
    await _finishInitialization(replacement, resolver, platform, 9);

    oldPoll.complete(const Duration(seconds: 12));
    await _flush();
    expect(controller.value.position, Duration.zero);
    await controller.dispose();
    expect(platform.disposed, containsAll(<int>[8, 9]));
  });

  test('late polling cannot publish after disposal', () async {
    final _Resolver resolver = _Resolver();
    final _Platform platform = _Platform();
    final MdPlayerController controller = MdPlayerController.network('url',
        resolver: resolver, platform: platform);
    await _finishInitialization(
        controller.initialize(), resolver, platform, 14);
    await controller.play();
    await Future<void>.delayed(const Duration(milliseconds: 550));
    final Completer<Duration> poll = platform.positions.single;
    int notifications = 0;
    controller.addListener(() => notifications++);

    await controller.dispose();
    poll.complete(const Duration(seconds: 12));
    await _flush();
    expect(notifications, 0);
  });

  test('play followed by pause cannot restart polling or speed', () async {
    final _Resolver resolver = _Resolver();
    final _Platform platform = _Platform();
    final MdPlayerController controller = MdPlayerController.network('url',
        resolver: resolver, platform: platform);
    await _finishInitialization(
        controller.initialize(), resolver, platform, 10);
    final Completer<void> play = Completer<void>();
    platform.nextPlay = play;

    final Future<void> playing = controller.play();
    await controller.pause();
    play.complete();
    await playing;
    await Future<void>.delayed(const Duration(milliseconds: 550));
    expect(controller.value.isPlaying, isFalse);
    expect(platform.positions, isEmpty);
    expect(platform.speeds, isEmpty);
    await controller.dispose();
  });

  test('identical polled positions are not published', () async {
    final _Resolver resolver = _Resolver();
    final _Platform platform = _Platform();
    final MdPlayerController controller = MdPlayerController.network('url',
        resolver: resolver, platform: platform);
    await _finishInitialization(
        controller.initialize(), resolver, platform, 11);
    await controller.play();
    int notifications = 0;
    controller.addListener(() => notifications++);

    await Future<void>.delayed(const Duration(milliseconds: 550));
    platform.positions.single.complete(Duration.zero);
    await _flush();
    expect(notifications, 0);
    await controller.dispose();
  });

  test('stale quality completions cannot change the current label', () async {
    final _Resolver resolver = _Resolver();
    final _Platform platform = _Platform();
    final MdPlayerController controller = MdPlayerController.network('url',
        resolver: resolver, platform: platform);
    await _finishInitialization(
        controller.initialize(), resolver, platform, 12);

    final Future<void> first = controller.setQuality(
      const MdPlayerQuality(label: '720p', videoUrl: '720'),
    );
    final Future<void> second = controller.setQuality(
      const MdPlayerQuality(label: '1080p', videoUrl: '1080'),
    );
    platform.qualityChanges.last.complete();
    await second;
    platform.qualityChanges.first.complete();
    await first;

    platform.emitQuality(
      12,
      MdQualitySwitchEvent(
        operationId: platform.qualityOperationIds.first!,
        phase: MdQualitySwitchPhase.completed,
        requestedLabel: '720p',
      ),
    );
    expect(controller.value.qualityLabel, 'auto');
    platform.emitQuality(
      12,
      MdQualitySwitchEvent(
        operationId: platform.qualityOperationIds.last!,
        phase: MdQualitySwitchPhase.completed,
        requestedLabel: '1080p',
      ),
    );

    expect(controller.value.qualityLabel, '1080p');
    expect(platform.qualityTargets, <(int, String)>[(12, '720'), (12, '1080')]);
    await controller.dispose();
  });

  test('separate-stream quality keeps the texture and restores nothing in Dart',
      () async {
    final _Resolver resolver = _Resolver();
    final _Platform platform = _Platform();
    final MdPlayerController controller = MdPlayerController.network('url',
        resolver: resolver, platform: platform);
    await _finishInitialization(
        controller.initialize(), resolver, platform, 16);
    await controller.seekTo(const Duration(seconds: 6));

    final Future<void> quality = controller.setQuality(
      const MdPlayerQuality(
        label: '720p',
        videoUrl: 'video-720',
        audioUrl: 'audio',
      ),
    );
    await _flush();
    platform.qualityChanges.single.complete();
    await quality;

    expect(controller.textureId, 16);
    expect(controller.value.qualityLabel, 'auto');
    expect(platform.qualityAudioUris.single, 'audio');
    expect(platform.disposed, isEmpty);
    expect(platform.seeks, <(int, Duration)>[
      (16, const Duration(seconds: 6)),
    ]);
    expect(platform.played, isEmpty);

    platform.emitQuality(
      16,
      MdQualitySwitchEvent(
        operationId: platform.qualityOperationIds.single!,
        phase: MdQualitySwitchPhase.completed,
        requestedLabel: '720p',
      ),
    );

    expect(controller.value.qualityLabel, '720p');
    await controller.dispose();
  });

  test('setQuality future completes on acceptance before terminal event',
      () async {
    final _Resolver resolver = _Resolver();
    final _Platform platform = _Platform();
    final MdPlayerController controller = MdPlayerController.network('url',
        resolver: resolver, platform: platform);
    await _finishInitialization(
        controller.initialize(), resolver, platform, 18);

    final Future<void> accepted = controller.setQuality(
      const MdPlayerQuality(label: '720p', videoUrl: '720'),
    );
    await _flush();
    platform.qualityChanges.single.complete();
    await accepted;

    expect(controller.value.qualityLabel, 'auto');
    expect(controller.qualitySwitchState.value.status,
        MdQualitySwitchStatus.preparing);
    platform.emitQuality(
      18,
      MdQualitySwitchEvent(
        operationId: platform.qualityOperationIds.single!,
        phase: MdQualitySwitchPhase.switching,
        requestedLabel: '720p',
      ),
    );
    expect(controller.qualitySwitchState.value.status,
        MdQualitySwitchStatus.switching);
    await controller.dispose();
  });

  test('failed switch publishes rollback outcome without changing label',
      () async {
    final _Resolver resolver = _Resolver();
    final _Platform platform = _Platform();
    final MdPlayerController controller = MdPlayerController.network('url',
        resolver: resolver, platform: platform);
    await _finishInitialization(
        controller.initialize(), resolver, platform, 19);
    final Future<void> accepted = controller.setQuality(
      const MdPlayerQuality(label: '720p', videoUrl: '720'),
    );
    await _flush();
    platform.qualityChanges.single.complete();
    await accepted;

    platform.emitQuality(
      19,
      MdQualitySwitchEvent(
        operationId: platform.qualityOperationIds.single!,
        phase: MdQualitySwitchPhase.failed,
        requestedLabel: '720p',
        errorDescription: 'decoder failed',
        rollbackSucceeded: true,
      ),
    );

    expect(controller.value.qualityLabel, 'auto');
    expect(controller.qualitySwitchState.value.status,
        MdQualitySwitchStatus.failed);
    expect(controller.qualitySwitchState.value.rollbackSucceeded, true);
    await controller.dispose();
  });

  test('latest volume command wins and mute restores the last nonzero value',
      () async {
    final _Resolver resolver = _Resolver();
    final _Platform platform = _Platform();
    final MdPlayerController controller = MdPlayerController.network('url',
        resolver: resolver, platform: platform);
    await _finishInitialization(
        controller.initialize(), resolver, platform, 21);
    platform.volumes.clear();
    final Completer<void> slow = Completer<void>();
    platform.nextVolume = slow;

    final Future<void> first = controller.setVolume(0.4);
    await controller.setVolume(0.8);
    slow.completeError(PlatformException(code: 'stale'));
    await first;
    expect(controller.value.hasError, isFalse);
    await controller.toggleMute();
    expect(controller.value.volume, 0);
    await controller.toggleMute();

    expect(controller.value.volume, 0.8);
    expect(platform.volumes, <(int, double)>[
      (21, 0.4),
      (21, 0.8),
      (21, 0),
      (21, 0.8),
    ]);
    await controller.dispose();
  });

  test('confirmed quality uses identity when labels are duplicated', () async {
    final _Resolver resolver = _Resolver();
    final _Platform platform = _Platform();
    final MdPlayerQuality first = const MdPlayerQuality(
      label: '720p',
      videoUrl: 'first',
      videoItag: 1,
    );
    final MdPlayerQuality second = const MdPlayerQuality(
      label: '720p',
      videoUrl: 'second',
      videoItag: 2,
    );
    final MdPlayerController controller = MdPlayerController.network('url',
        resolver: resolver, platform: platform);
    await _finishInitialization(
      controller.initialize(),
      resolver,
      platform,
      22,
      source: MdPlayerSource(
        videoUrl: first.videoUrl,
        videoItag: first.videoItag,
        qualityLabel: first.label,
        qualities: <MdPlayerQuality>[first, second],
      ),
    );
    expect(identical(controller.confirmedQuality, first), isTrue);

    final Future<void> accepted = controller.setQuality(second);
    await _flush();
    platform.qualityChanges.single.complete();
    await accepted;
    platform.emitQuality(
      22,
      MdQualitySwitchEvent(
        operationId: platform.qualityOperationIds.single!,
        phase: MdQualitySwitchPhase.failed,
        requestedLabel: second.label,
        rollbackSucceeded: true,
      ),
    );
    expect(identical(controller.confirmedQuality, first), isTrue);

    final Future<void> retry = controller.setQuality(second);
    await _flush();
    platform.qualityChanges.last.complete();
    await retry;
    platform.emitQuality(
      22,
      MdQualitySwitchEvent(
        operationId: platform.qualityOperationIds.last!,
        phase: MdQualitySwitchPhase.completed,
        requestedLabel: second.label,
      ),
    );
    expect(identical(controller.confirmedQuality, second), isTrue);
    await controller.dispose();
  });

  test('initialization invalidates an accepted quality operation', () async {
    final _Resolver resolver = _Resolver();
    final _Platform platform = _Platform();
    final MdPlayerController controller = MdPlayerController.network('url',
        resolver: resolver, platform: platform);
    await _finishInitialization(
        controller.initialize(), resolver, platform, 20);
    final Future<void> accepted = controller.setQuality(
      const MdPlayerQuality(label: '720p', videoUrl: '720'),
    );
    await _flush();
    platform.qualityChanges.single.complete();
    await accepted;
    final String staleId = platform.qualityOperationIds.single!;

    final Future<void> reinitialization = controller.initialize();
    await _flush();
    expect(
        controller.qualitySwitchState.value.status, MdQualitySwitchStatus.idle);
    platform.emitQuality(
      20,
      MdQualitySwitchEvent(
        operationId: staleId,
        phase: MdQualitySwitchPhase.completed,
        requestedLabel: '720p',
      ),
    );
    expect(controller.value.qualityLabel, 'auto');
    await controller.dispose();
    await reinitialization;
  });

  test('controller publishes unmodifiable collection copies', () async {
    final _Resolver resolver = _Resolver();
    final _Platform platform = _Platform();
    final MdPlayerController controller = MdPlayerController.network('url',
        resolver: resolver, platform: platform);
    final List<MdPlayerQuality> qualities = <MdPlayerQuality>[
      const MdPlayerQuality(label: '360p', videoUrl: '360'),
    ];
    await _finishInitialization(
      controller.initialize(),
      resolver,
      platform,
      13,
      source: MdPlayerSource(videoUrl: 'video', qualities: qualities),
    );
    qualities.clear();
    final List<DurationRange> buffered = <DurationRange>[
      DurationRange(Duration.zero, const Duration(seconds: 1)),
    ];
    platform.emit(
      13,
      VideoEvent(
        eventType: VideoEventType.bufferingUpdate,
        buffered: buffered,
      ),
    );
    buffered.clear();

    expect(controller.value.qualities, hasLength(1));
    expect(controller.value.buffered, hasLength(1));
    expect(
      () => controller.value.qualities.add(
        const MdPlayerQuality(label: '720p', videoUrl: '720'),
      ),
      throwsUnsupportedError,
    );
    expect(
      () => controller.value.buffered.add(
        DurationRange(Duration.zero, const Duration(seconds: 2)),
      ),
      throwsUnsupportedError,
    );
    await controller.dispose();
  });
}
