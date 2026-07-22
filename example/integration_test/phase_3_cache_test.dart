import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:md_player_android/md_player_android.dart';

const String _origin = String.fromEnvironment('PHASE_3_ORIGIN');
const String _runId = String.fromEnvironment('PHASE_3_RUN_ID');
const int _repetition =
    int.fromEnvironment('PHASE_3_REPETITION', defaultValue: 1);
const MethodChannel _diagnostics =
    MethodChannel('md_player_android/debug_diagnostics');

void main() {
  final IntegrationTestWidgetsFlutterBinding binding =
      IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('phase 3.1 bounded cache scenarios', (WidgetTester tester) async {
    expect(_origin, isNotEmpty);
    final _ServerControl server = _ServerControl(Uri.parse(_origin));
    final List<Map<String, Object?>> records = <Map<String, Object?>>[];
    final List<Map<String, Object?>> failures = <Map<String, Object?>>[];

    Future<void> scenario(String name, Future<void> Function() body) async {
      final Stopwatch watch = Stopwatch()..start();
      String terminal = 'passed';
      String? failure;
      String? timeoutPhase;
      try {
        await server.available(true);
        await server.throttle();
        await body().timeout(const Duration(minutes: 2));
      } on TimeoutException catch (error, stack) {
        terminal = 'timeout';
        failure = '$error';
        timeoutPhase = name;
        failures.add(<String, Object?>{
          'scenario': name,
          'error': failure,
          'stack': '$stack',
          'timeout': true,
        });
      } catch (error, stack) {
        terminal = 'failed';
        failure = '$error';
        failures.add(<String, Object?>{
          'scenario': name,
          'error': failure,
          'stack': '$stack',
          'timeout': false,
        });
      } finally {
        watch.stop();
        records.add(<String, Object?>{
          'runId': _runId,
          'scenario': name,
          'repetition': _repetition,
          'terminalState': terminal,
          'failureCode': failure,
          'timeoutPhase': timeoutPhase,
          'durationMillis': watch.elapsedMilliseconds,
          'server': await server.snapshot(),
          'cacheStats': _statsMap(await MdPlayerCache.stats()),
          'diagnostics': await _snapshot(),
        });
      }
    }

    await _diagnostics.invokeMethod<void>('clear');
    await MdPlayerCache.disable();
    await scenario('disabled cache baseline', () async {
      await server.reset();
      final int before = (await MdPlayerCache.stats()).currentBytes;
      await _play(tester, _muxed('disabled', 1));
      await _play(tester, _muxed('disabled', 1));
      final MdPlayerCacheStats stats = await MdPlayerCache.stats();
      final Map<String, dynamic> network = await server.snapshot();
      expect(stats.enabled, isFalse);
      expect(stats.currentBytes, before);
      expect(
          _number(network, 'bytesByPath', '/muxed/muxed.mp4'), greaterThan(0));
      expect(_number(network, 'requestsByPath', '/muxed/muxed.mp4'),
          greaterThan(1));
    });

    await scenario('cold cache', () async {
      await _freshCache();
      await server.reset();
      final MdPlayerCacheStats before = await MdPlayerCache.stats();
      await _play(tester, _muxed('cold', 2));
      final MdPlayerCacheStats after = await MdPlayerCache.stats();
      expect(after.upstreamReadBytes, greaterThan(before.upstreamReadBytes));
      expect(after.currentBytes, greaterThan(before.currentBytes));
      expect(after.cachedResources, greaterThan(0));
    });

    await scenario('warm cache and unavailable upstream', () async {
      await server.reset();
      final MdPlayerCacheStats before = await MdPlayerCache.stats();
      await server.available(false);
      await _play(tester, _muxed('cold', 2));
      final MdPlayerCacheStats after = await MdPlayerCache.stats();
      expect(after.cacheReadBytes, greaterThan(before.cacheReadBytes));
      expect(after.upstreamReadBytes, before.upstreamReadBytes);
      expect(
          _number(await server.snapshot(), 'bytesByPath', '/muxed/muxed.mp4'),
          0);
    });

    await scenario('partial cache combines cache and upstream', () async {
      await _freshCache();
      await server.reset();
      await server.throttle(chunkBytes: 16384, delayMs: 80);
      await _play(tester, _muxed('partial', 3),
          playFor: const Duration(milliseconds: 350));
      await server.throttle();
      final MdPlayerCacheStats before = await MdPlayerCache.stats();
      final MdPlayerController controller =
          await _open(tester, _muxed('partial', 3));
      await controller.seekTo(const Duration(seconds: 8));
      await _finish(tester, controller);
      await controller.dispose();
      final MdPlayerCacheStats after = await MdPlayerCache.stats();
      expect(after.cacheReadBytes, greaterThan(before.cacheReadBytes));
      expect(after.upstreamReadBytes, greaterThan(before.upstreamReadBytes));
    });

    await scenario('merged audio and video cache', () async {
      await _freshCache();
      await server.reset();
      final MdPlayerSource source = _merged('merged', 10, 20);
      await _play(tester, source);
      final Map<String, dynamic> cold = await server.snapshot();
      expect(_number(cold, 'bytesByRole', 'video'), greaterThan(0));
      expect(_number(cold, 'bytesByRole', 'audio'), greaterThan(0));
      await server.reset();
      await server.available(false);
      await _play(tester, source);
      expect(_number(await server.snapshot(), 'bytesByRole', 'video'), 0);
      expect(
          (await _cacheDebug())['cacheKeys'],
          containsAll(<String>[
            mdPlayerYoutubeCacheKey('merged', 'video', 10),
            mdPlayerYoutubeCacheKey('merged', 'audio', 20),
          ]));
    });

    await scenario('stable signed query reuse', () async {
      await _freshCache();
      await server.reset();
      final String key = mdPlayerYoutubeCacheKey('signed', 'muxed', 22);
      await _play(tester, _muxed('signed', 22, query: 'token=one&expire=100'));
      await server.reset();
      await _play(tester, _muxed('signed', 22, query: 'token=two&expire=200'));
      expect(
          _number(await server.snapshot(), 'bytesByPath', '/muxed/muxed.mp4'),
          0);
      final List<Object?> keys =
          (await _cacheDebug())['cacheKeys']! as List<Object?>;
      expect(keys.where((Object? value) => value == key), hasLength(1));
      expect(key, isNot(contains('token=')));
    });

    await scenario('quality switching with cache', () async {
      await _freshCache();
      await server.reset();
      final MdPlayerSource source = _qualitySource('switch');
      final MdPlayerController controller = await _open(tester, source);
      final Map<String, Object?> before = await _activePlayer();
      await _switch(controller, source.qualities.last);
      await _switch(controller, source.qualities.first);
      final Map<String, Object?> after = await _activePlayer();
      expect(after['textureId'], before['textureId']);
      expect(after['playerIdentity'], before['playerIdentity']);
      expect(controller.value.qualityLabel, 'low');
      await controller.dispose();
    });

    await scenario('rollback with cache', () async {
      await _freshCache();
      final MdPlayerSource source = _qualitySource('rollback');
      final MdPlayerController controller = await _open(tester, source);
      await _finish(tester, controller);
      final int creates = (await _cacheDebug())['cacheCreateCount']! as int;
      await controller.setQuality(MdPlayerQuality(
        label: 'invalid',
        videoUrl: '$_origin/video/invalid.mp4',
        audioUrl: '$_origin/audio/audio.m4a',
        videoCacheKey: mdPlayerYoutubeCacheKey('rollback', 'video', 999),
        audioCacheKey: mdPlayerYoutubeCacheKey('rollback', 'audio', 20),
      ));
      await _terminal(controller);
      expect(controller.qualitySwitchState.value.status,
          MdQualitySwitchStatus.failed);
      expect(controller.qualitySwitchState.value.rollbackSucceeded, isTrue);
      expect(controller.value.qualityLabel, 'low');
      expect((await _cacheDebug())['cacheCreateCount'], creates);
      await controller.dispose();
    });

    await scenario('rapid quality switching', () async {
      await _freshCache();
      final MdPlayerSource source = _qualitySource('rapid');
      final MdPlayerController controller = await _open(tester, source);
      unawaited(controller.setQuality(source.qualities.last));
      unawaited(controller.setQuality(source.qualities.first));
      unawaited(controller.setQuality(source.qualities.last));
      await _terminal(controller);
      expect(controller.value.qualityLabel, 'high');
      expect((await _cacheDebug())['openCacheCount'], 1);
      await controller.dispose();
      expect(_leaseCount(await _cacheDebug()), 0);
    });

    await scenario('LRU eviction', () async {
      await _freshCache(maxBytes: 1024 * 1024);
      await _play(tester, _muxed('lru-a', 1, file: 'low.mp4'));
      await _play(tester, _muxed('lru-b', 2));
      await _play(tester, _muxed('lru-a', 1, file: 'low.mp4'));
      await _play(tester, _muxed('lru-c', 3));
      final List<Object?> keys =
          (await _cacheDebug())['cacheKeys']! as List<Object?>;
      expect(keys, contains(mdPlayerYoutubeCacheKey('lru-a', 'muxed', 1)));
      expect(
          keys, isNot(contains(mdPlayerYoutubeCacheKey('lru-b', 'muxed', 2))));
      expect((await MdPlayerCache.stats()).currentBytes,
          lessThanOrEqualTo(1024 * 1024));
      await server.reset();
      await _play(tester, _muxed('lru-b', 2));
      expect(
          _number(await server.snapshot(), 'bytesByPath', '/muxed/muxed.mp4'),
          greaterThan(0));
    });

    await scenario('exact per-video removal', () async {
      await _freshCache(maxBytes: 4 * 1024 * 1024);
      await _play(tester, _merged('abc', 10, 20));
      await _play(tester, _muxed('abc', 22));
      await _play(tester, _muxed('abc1', 22));
      await _play(tester, _muxed('xabc', 22));
      await MdPlayerCache.removeVideo('abc');
      final List<Object?> keys =
          (await _cacheDebug())['cacheKeys']! as List<Object?>;
      expect(
        keys.where((Object? key) {
          final List<String> parts = '$key'.split(':');
          return parts.length == 5 && parts[2] == _encoded('abc');
        }),
        isEmpty,
      );
      expect(keys, contains(mdPlayerYoutubeCacheKey('abc1', 'muxed', 22)));
      expect(keys, contains(mdPlayerYoutubeCacheKey('xabc', 'muxed', 22)));
      await server.reset();
      await _play(tester, _muxed('abc', 22));
      expect(
          _number(await server.snapshot(), 'bytesByPath', '/muxed/muxed.mp4'),
          greaterThan(0));
    });

    await scenario('clear cache and active lease rejection', () async {
      await _freshCache();
      final MdPlayerController controller =
          await _open(tester, _muxed('clear', 1));
      await expectLater(
          MdPlayerCache.clear(), throwsA(isA<PlatformException>()));
      await controller.dispose();
      await MdPlayerCache.clear();
      final MdPlayerCacheStats empty = await MdPlayerCache.stats();
      expect(empty.currentBytes, 0);
      expect(empty.cachedResources, 0);
      expect(empty.cacheReadBytes, 0);
      expect((await _cacheDebug())['cacheKeys'], isEmpty);
      await _play(tester, _muxed('clear', 1));
      expect((await MdPlayerCache.stats()).currentBytes, greaterThan(0));
    });

    await scenario('disable preserves active generation', () async {
      await _freshCache();
      final MdPlayerController controller =
          await _open(tester, _muxed('disable', 1));
      await _finish(tester, controller);
      final int bytes = (await MdPlayerCache.stats()).currentBytes;
      await MdPlayerCache.disable();
      expect((await MdPlayerCache.stats()).enabled, isFalse);
      expect((await MdPlayerCache.stats()).currentBytes, bytes);
      expect((await _cacheDebug())['retiredLeases'], 1);
      await _play(tester, _muxed('disable-future', 2));
      await controller.dispose();
      expect(_leaseCount(await _cacheDebug()), 0);
      expect((await MdPlayerCache.stats()).currentBytes,
          greaterThanOrEqualTo(bytes));
    });

    await server.available(true);
    await MdPlayerCache.disable();
    final Map<String, Object?> report = <String, Object?>{
      'schemaVersion': 1,
      'runId': _runId,
      'repetition': _repetition,
      'device': 'Android device selected by flutter drive',
      'records': records,
      'failures': failures,
      'diagnostics': await _snapshot(),
    };
    binding.reportData = report;
    expect(failures, isEmpty);
  }, timeout: const Timeout(Duration(minutes: 20)));
}

Future<void> _freshCache({int maxBytes = 2 * 1024 * 1024}) async {
  await MdPlayerCache.disable();
  await MdPlayerCache.configure(MdPlayerCacheConfiguration(
    maxBytes: maxBytes,
    directoryName: 'phase_3_cache',
  ));
  await MdPlayerCache.clear();
}

MdPlayerSource _muxed(String id, int itag,
    {String file = 'muxed.mp4', String? query}) {
  final String suffix = query == null ? '' : '?$query';
  return MdPlayerSource(
    videoUrl: '$_origin/muxed/$file$suffix',
    qualityLabel: id,
    videoCacheKey: mdPlayerYoutubeCacheKey(id, 'muxed', itag),
    videoStreamIdentity: id,
    videoItag: itag,
    videoRole: 'muxed',
  );
}

MdPlayerSource _merged(String id, int videoItag, int audioItag) =>
    MdPlayerSource(
      videoUrl: '$_origin/video/low.mp4',
      audioUrl: '$_origin/audio/audio.m4a',
      qualityLabel: 'low',
      videoCacheKey: mdPlayerYoutubeCacheKey(id, 'video', videoItag),
      audioCacheKey: mdPlayerYoutubeCacheKey(id, 'audio', audioItag),
      videoStreamIdentity: id,
      audioStreamIdentity: id,
      videoItag: videoItag,
      audioItag: audioItag,
      videoRole: 'video',
      audioRole: 'audio',
    );

MdPlayerSource _qualitySource(String id) {
  final MdPlayerQuality low = MdPlayerQuality(
    label: 'low',
    videoUrl: '$_origin/video/low.mp4',
    audioUrl: '$_origin/audio/audio.m4a',
    videoCacheKey: mdPlayerYoutubeCacheKey(id, 'video', 10),
    audioCacheKey: mdPlayerYoutubeCacheKey(id, 'audio', 20),
    videoRole: 'video',
    audioRole: 'audio',
  );
  final MdPlayerQuality high = MdPlayerQuality(
    label: 'high',
    videoUrl: '$_origin/video/high.mp4',
    audioUrl: '$_origin/audio/audio.m4a',
    videoCacheKey: mdPlayerYoutubeCacheKey(id, 'video', 11),
    audioCacheKey: mdPlayerYoutubeCacheKey(id, 'audio', 20),
    videoRole: 'video',
    audioRole: 'audio',
  );
  return MdPlayerSource(
    videoUrl: low.videoUrl,
    audioUrl: low.audioUrl,
    qualityLabel: low.label,
    qualities: <MdPlayerQuality>[low, high],
    videoCacheKey: low.videoCacheKey,
    audioCacheKey: low.audioCacheKey,
    videoRole: 'video',
    audioRole: 'audio',
  );
}

Future<MdPlayerController> _open(
    WidgetTester tester, MdPlayerSource source) async {
  final MdPlayerController controller =
      MdPlayerController.network('phase3', resolver: _FixedResolver(source));
  await controller.initialize().timeout(const Duration(seconds: 25));
  await tester.pumpWidget(_Surface(controller));
  await controller.play();
  await tester.pump(const Duration(milliseconds: 700));
  expect(controller.value.isInitialized, isTrue);
  expect(controller.value.errorDescription, isNull);
  return controller;
}

Future<void> _finish(WidgetTester tester, MdPlayerController controller,
    {Duration playFor = const Duration(seconds: 4)}) async {
  await controller.setPlaybackSpeed(4);
  final DateTime deadline = DateTime.now().add(playFor);
  while (DateTime.now().isBefore(deadline) && !controller.value.hasError) {
    await tester.pump(const Duration(milliseconds: 200));
  }
  expect(controller.value.errorDescription, isNull);
}

Future<void> _play(WidgetTester tester, MdPlayerSource source,
    {Duration playFor = const Duration(seconds: 4)}) async {
  final MdPlayerController controller = await _open(tester, source);
  await _finish(tester, controller, playFor: playFor);
  await controller.dispose();
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _switch(
    MdPlayerController controller, MdPlayerQuality quality) async {
  await controller.setQuality(quality);
  await _terminal(controller);
  expect(controller.qualitySwitchState.value.status,
      MdQualitySwitchStatus.completed);
}

Future<void> _terminal(MdPlayerController controller) async {
  if (_terminalStatus(controller.qualitySwitchState.value.status)) return;
  final Completer<void> completer = Completer<void>();
  void listener() {
    if (_terminalStatus(controller.qualitySwitchState.value.status) &&
        !completer.isCompleted) completer.complete();
  }

  controller.qualitySwitchState.addListener(listener);
  try {
    await completer.future.timeout(const Duration(seconds: 40));
  } finally {
    controller.qualitySwitchState.removeListener(listener);
  }
}

bool _terminalStatus(MdQualitySwitchStatus status) =>
    status == MdQualitySwitchStatus.completed ||
    status == MdQualitySwitchStatus.failed;

class _FixedResolver extends MdPlayerSourceResolver {
  _FixedResolver(this.source);
  final MdPlayerSource source;
  @override
  Future<MdPlayerSource> resolve(String input) async => source;
}

class _Surface extends StatelessWidget {
  const _Surface(this.controller);
  final MdPlayerController controller;
  @override
  Widget build(BuildContext context) =>
      MaterialApp(home: Scaffold(body: MdPlayer(controller: controller)));
}

class _ServerControl {
  _ServerControl(this.origin);
  final Uri origin;

  Future<Map<String, dynamic>> snapshot() async =>
      jsonDecode(await _get('/_phase3/snapshot')) as Map<String, dynamic>;
  Future<void> reset() async => _get('/_phase3/reset');
  Future<void> available(bool value) async =>
      _get('/_phase3/availability?available=$value');
  Future<void> throttle({int chunkBytes = 0, int delayMs = 0}) async =>
      _get('/_phase3/throttle?chunkBytes=$chunkBytes&delayMs=$delayMs');

  Future<String> _get(String path) async {
    final HttpClient client = HttpClient();
    try {
      final HttpClientResponse response =
          await (await client.getUrl(origin.resolve(path))).close();
      return utf8
          .decode(await response.expand((List<int> bytes) => bytes).toList());
    } finally {
      client.close(force: true);
    }
  }
}

Future<Map<String, dynamic>> _snapshot() async => _stringMap(
      await _diagnostics.invokeMapMethod<Object?, Object?>('snapshot') ??
          <Object?, Object?>{},
    );

Future<Map<String, Object?>> _activePlayer() async {
  final List<dynamic> players =
      (await _snapshot())['players']! as List<dynamic>;
  return _stringMap(players.single as Map<Object?, Object?>);
}

Future<Map<String, Object?>> _cacheDebug() async =>
    _stringMap((await _snapshot())['cache']! as Map<Object?, Object?>);

Map<String, dynamic> _stringMap(Map<Object?, Object?> source) => source.map(
      (Object? key, Object? value) => MapEntry<String, dynamic>('$key', value),
    );

Map<String, Object?> _statsMap(MdPlayerCacheStats stats) => <String, Object?>{
      'enabled': stats.enabled,
      'currentBytes': stats.currentBytes,
      'maxBytes': stats.maxBytes,
      'cachedResources': stats.cachedResources,
      'cacheReadBytes': stats.cacheReadBytes,
      'upstreamReadBytes': stats.upstreamReadBytes,
      'cacheReadOperations': stats.cacheReadOperations,
      'upstreamOpenOperations': stats.upstreamOpenOperations,
    };

int _number(Map<String, dynamic> snapshot, String group, String key) =>
    ((snapshot[group] as Map<dynamic, dynamic>?)?[key] as num?)?.toInt() ?? 0;

int _leaseCount(Map<String, Object?> cache) =>
    (cache['currentLeases']! as int) + (cache['retiredLeases']! as int);

String _encoded(String value) =>
    base64Url.encode(utf8.encode(value)).replaceAll('=', '');
