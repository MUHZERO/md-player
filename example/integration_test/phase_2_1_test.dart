import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:md_player_android/md_player_android.dart';

import 'phase_2_1_source.dart';

const bool _fixturesEnabled = bool.fromEnvironment('PHASE_2_1_FIXTURES');
const MethodChannel _diagnostics =
    MethodChannel('md_player_android/debug_diagnostics');
const MethodChannel _lifecycle =
    MethodChannel('md_player_android/example_lifecycle');

void main() {
  final IntegrationTestWidgetsFlutterBinding binding =
      IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'phase 2.1 controlled Android smoke scenarios',
    (WidgetTester tester) async {
      await _diagnostics.invokeMethod<void>('clear');
      final Phase21SourceResolver resolver = Phase21SourceResolver();
      final List<Map<String, Object?>> failures = <Map<String, Object?>>[];
      MdPlayerController? controller;

      Future<void> scenario(String name, Future<void> Function() body) async {
        try {
          await body();
        } catch (error, stack) {
          failures.add(<String, Object?>{
            'scenario': name,
            'error': '$error',
            'stack': '$stack',
          });
        }
      }

      await scenario('initial merged playback', () async {
        controller = MdPlayerController.network('muxed', resolver: resolver);
        await controller!.initialize().timeout(
              const Duration(seconds: 20),
              onTimeout: () => throw TimeoutException(
                'initialization exceeded the 20-second bound',
              ),
            );
        await tester.pumpWidget(_SurfaceHarness(controller!));
        await controller!.play();
        await tester.pump(const Duration(seconds: 1));
        expect(controller!.value.position, greaterThan(Duration.zero));
        await controller!.dispose();
        controller = MdPlayerController.network('fixture', resolver: resolver);
        await controller!.initialize().timeout(
              const Duration(seconds: 20),
              onTimeout: () => throw TimeoutException(
                'separate-stream initialization exceeded the 20-second bound',
              ),
            );
        await tester.pumpWidget(_SurfaceHarness(controller!));
      });

      final List<MdPlayerQuality> qualities = controller!.value.qualities;
      final MdPlayerQuality low = qualities.first;
      final MdPlayerQuality high = qualities.last;

      await scenario('playing and paused switches', () async {
        await _switch(controller!, high, const Duration(seconds: 25));
        expect(controller!.value.qualityLabel, high.label);
        await controller!.pause();
        final Duration paused = controller!.value.position;
        await _switch(controller!, low, const Duration(seconds: 25));
        await tester.pump(const Duration(milliseconds: 200));
        expect(
          (controller!.value.position - paused).abs(),
          lessThanOrEqualTo(const Duration(milliseconds: 200)),
        );
        expect(controller!.value.isPlaying, isFalse);
      });

      await scenario('rapid switching and command authority', () async {
        unawaited(controller!.setQuality(high));
        unawaited(controller!.setQuality(low));
        await controller!.seekTo(const Duration(seconds: 4));
        await controller!.pause();
        unawaited(controller!.setQuality(high));
        await controller!.play();
        await _terminal(controller!, const Duration(seconds: 25));
        expect(controller!.value.qualityLabel, high.label);
        expect(controller!.value.isPlaying, isTrue);
        expect(
          (controller!.value.position - const Duration(seconds: 4)).abs(),
          lessThanOrEqualTo(const Duration(milliseconds: 500)),
        );
      });

      await scenario('accepted invalid replacement rolls back once', () async {
        final List<MdQualitySwitchStatus> phases = <MdQualitySwitchStatus>[];
        void listener() =>
            phases.add(controller!.qualitySwitchState.value.status);
        controller!.qualitySwitchState.addListener(listener);
        await controller!.setQuality(await resolver.invalidQuality());
        await _terminal(controller!, const Duration(seconds: 40));
        controller!.qualitySwitchState.removeListener(listener);
        expect(phases, contains(MdQualitySwitchStatus.switching));
        expect(
          controller!.qualitySwitchState.value.status,
          MdQualitySwitchStatus.failed,
        );
        expect(controller!.qualitySwitchState.value.rollbackSucceeded, isTrue);
        expect(controller!.value.qualityLabel, high.label);
      });

      await scenario('empty URI is rejected immediately', () async {
        await expectLater(
          MdPlayerAndroid().changeQuality(controller!.textureId, ''),
          throwsA(isA<PlatformException>()),
        );
      });

      await scenario('widget and rotation surface recreation', () async {
        final int player = controller!.playerId;
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pumpWidget(_SurfaceHarness(controller!));
        await _lifecycle.invokeMethod<void>(
          'orientation',
          <String, Object>{'value': 'landscape'},
        );
        await tester.pump(const Duration(seconds: 1));
        await _lifecycle.invokeMethod<void>(
          'orientation',
          <String, Object>{'value': 'portrait'},
        );
        expect(controller!.playerId, player);
      });

      await scenario('background and foreground', () async {
        await _lifecycle.invokeMethod<void>(
          'backgroundForeground',
          <String, Object>{'milliseconds': 1000},
        );
        await tester.pump(const Duration(seconds: 3));
        expect(controller!.value.isInitialized, isTrue);
      });

      await scenario('disposal during pending switch', () async {
        unawaited(controller!.setQuality(low));
        await controller!.dispose();
        controller = null;
        await tester.pump(const Duration(seconds: 1));
      });

      final Map<Object?, Object?> raw =
          await _diagnostics.invokeMapMethod<Object?, Object?>('snapshot') ??
              <Object?, Object?>{};
      final Map<String, Object?> report = <String, Object?>{
        'schemaVersion': 1,
        'device': 'Android device selected by flutter drive',
        'boundsSeconds': <String, int>{
          'initialization': 20,
          'switchOrSurface': 25,
          'rollbackOrBackground': 40,
        },
        'failures': failures,
        'diagnostics': _stringMap(raw),
        'statistics': _statistics(raw),
        'audioCapture': false,
        'intervalTerminology': 'non-playing intervals',
      };
      binding.reportData = report;
      _assertDiagnostics(raw);
      expect(failures, isEmpty);
    },
    skip: !_fixturesEnabled,
    timeout: const Timeout(Duration(minutes: 8)),
  );
}

Future<void> _switch(
  MdPlayerController controller,
  MdPlayerQuality quality,
  Duration timeout,
) async {
  await controller.setQuality(quality);
  await _terminal(controller, timeout);
  expect(
    controller.qualitySwitchState.value.status,
    MdQualitySwitchStatus.completed,
  );
}

Future<void> _terminal(MdPlayerController controller, Duration timeout) async {
  if (_isTerminal(controller.qualitySwitchState.value.status)) return;
  final Completer<void> result = Completer<void>();
  void listener() {
    if (_isTerminal(controller.qualitySwitchState.value.status) &&
        !result.isCompleted) {
      result.complete();
    }
  }

  controller.qualitySwitchState.addListener(listener);
  try {
    await result.future.timeout(
      timeout,
      onTimeout: () => throw TimeoutException(
        'quality operation did not reach a terminal phase within '
        '${timeout.inSeconds} seconds',
      ),
    );
  } finally {
    controller.qualitySwitchState.removeListener(listener);
  }
}

bool _isTerminal(MdQualitySwitchStatus status) =>
    status == MdQualitySwitchStatus.completed ||
    status == MdQualitySwitchStatus.failed;

Map<String, Object?> _stringMap(Map<Object?, Object?> source) => source.map(
      (Object? key, Object? value) => MapEntry<String, Object?>('$key', value),
    );

Map<String, Object?> _statistics(Map<Object?, Object?> snapshot) {
  final Map<String, List<num>> phases = <String, List<num>>{
    'requestToAcceptance': <num>[],
    'acceptanceToReady': <num>[],
    'readyToFirstFrame': <num>[],
    'firstFrameToCompletion': <num>[],
    'requestToCompletion': <num>[],
    'rollback': <num>[],
  };
  for (final Map<Object?, Object?> record in _operationRecords(snapshot)) {
    void add(String phase, String start, String end) {
      if (record[start] is num && record[end] is num) {
        phases[phase]!.add((record[end]! as num) - (record[start]! as num));
      }
    }

    add('requestToAcceptance', 'requestNanos', 'acceptanceNanos');
    add('acceptanceToReady', 'acceptanceNanos', 'readyNanos');
    add('readyToFirstFrame', 'readyNanos', 'firstFrameNanos');
    add('firstFrameToCompletion', 'firstFrameNanos', 'completionNanos');
    add('requestToCompletion', 'requestNanos', 'completionNanos');
    add('rollback', 'rollbackStartedNanos', 'completionNanos');
  }
  return phases.map(
    (String phase, List<num> values) => MapEntry<String, Object?>(
      phase,
      _summary(values),
    ),
  );
}

Iterable<Map<Object?, Object?>> _operationRecords(
  Map<Object?, Object?> snapshot,
) sync* {
  for (final Object? player in <Object?>[
    ...?snapshot['players'] as List<Object?>?,
    ...?snapshot['disposedPlayers'] as List<Object?>?,
  ]) {
    final Map<Object?, Object?> map = player! as Map<Object?, Object?>;
    for (final Object? operation in map['operations']! as List<Object?>) {
      yield operation! as Map<Object?, Object?>;
    }
  }
}

Map<String, Object?> _summary(List<num> values) {
  values.sort();
  if (values.isEmpty) return <String, Object?>{'sampleCount': 0};
  final int middle = values.length ~/ 2;
  return <String, Object?>{
    'sampleCount': values.length,
    'minNanos': values.first,
    'medianNanos': values.length.isOdd
        ? values[middle]
        : (values[middle - 1] + values[middle]) / 2,
    'maxNanos': values.last,
    if (values.length >= 20)
      'p95Nanos': values[((values.length * .95).ceil() - 1)],
  };
}

void _assertDiagnostics(Map<Object?, Object?> snapshot) {
  final List<Map<Object?, Object?>> records =
      _operationRecords(snapshot).toList();
  final List<Map<Object?, Object?>> invalid = records
      .where((Map<Object?, Object?> record) =>
          record['requestedQuality'] == 'invalid')
      .toList();
  expect(invalid, hasLength(1));
  expect(invalid.single['state'], 'failed');
  expect(invalid.single['rollbackSucceeded'], isTrue);
  expect(
    records.where((Map<Object?, Object?> record) =>
        record['rollbackStartedNanos'] != null),
    hasLength(1),
  );
  for (final Map<Object?, Object?> record in records) {
    if (record['firstFrameNanos'] case final num firstFrame) {
      expect(firstFrame, lessThanOrEqualTo(record['completionNanos']! as num));
    }
    if (record['state'] == 'completed') {
      expect(record['rollbackSucceeded'], isNull);
    }
  }
}

class _SurfaceHarness extends StatelessWidget {
  const _SurfaceHarness(this.controller);

  final MdPlayerController controller;

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: Scaffold(body: Center(child: MdPlayer(controller: controller))),
      );
}
