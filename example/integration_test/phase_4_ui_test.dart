import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:md_player_android/md_player_android.dart';
import 'package:md_player_android/src/md_player_debug.dart';

const String _origin = String.fromEnvironment('PHASE_4_ORIGIN');
const String _runId = String.fromEnvironment('PHASE_4_RUN_ID');
const int _repetition =
    int.fromEnvironment('PHASE_4_REPETITION', defaultValue: 1);
const MethodChannel _diagnostics =
    MethodChannel('md_player_android/debug_diagnostics');

void main() {
  final IntegrationTestWidgetsFlutterBinding binding =
      IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('phase 4 modern controls preserve player and cache identity',
      (WidgetTester tester) async {
    expect(_origin, isNotEmpty);
    MdPlayerRebuildDiagnostics.reset();
    await MdPlayerCache.disable();
    await MdPlayerCache.configure(MdPlayerCacheConfiguration(
      maxBytes: 2 * 1024 * 1024,
      directoryName: 'phase_4_ui',
    ));
    await MdPlayerCache.clear();

    final MdPlayerSource source = _source();
    final MdPlayerController controller = MdPlayerController.network(
      'phase4',
      resolver: _FixedResolver(source),
    );
    await controller.initialize().timeout(const Duration(seconds: 25));
    final Map<String, Object?> before = await _activePlayer();
    int enteredFullscreen = 0;
    int exitedFullscreen = 0;
    bool fullscreen = false;

    Future<void> pumpPlayer() => tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 960,
              height: 540,
              child: MdPlayer(
                controller: controller,
                controlsMode: MdPlayerControlsMode.modern,
                controlsConfiguration: MdPlayerControlsConfiguration(
                  enableVolume: true,
                ),
                labels: const MdPlayerControlsLabels(
                  settings: 'Phase 4 settings',
                ),
                style: const MdPlayerStyle(accent: Colors.amber),
                isFullscreen: fullscreen,
                onEnterFullscreen: () {
                  enteredFullscreen++;
                  fullscreen = true;
                },
                onExitFullscreen: () {
                  exitedFullscreen++;
                  fullscreen = false;
                },
              ),
            ),
          ),
        ));

    await pumpPlayer();
    expect(find.byTooltip('Phase 4 settings'), findsOneWidget);
    await tester.tap(find.byTooltip('Play'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(controller.value.isPlaying, isTrue);

    await tester.tap(find.byTooltip('Phase 4 settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Playback speed'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1.5x').last);
    await tester.pump();
    expect(controller.value.playbackSpeed, 1.5);

    final Finder progress = find.bySemanticsLabel('Playback position');
    expect(progress, findsOneWidget);
    await tester.drag(progress, const Offset(220, 0));
    await tester.pump(const Duration(milliseconds: 300));
    expect(controller.value.position, greaterThan(Duration.zero));

    await tester.tap(find.byTooltip('Phase 4 settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1080p').last);
    await _waitForQuality(controller);
    expect(controller.confirmedQuality?.label, '1080p');

    await _showControls(tester, 'Enter fullscreen');
    await tester.tap(find.byTooltip('Enter fullscreen'));
    await pumpPlayer();
    expect(enteredFullscreen, 1);
    await _showControls(tester, 'Exit fullscreen');
    await tester.tap(find.byTooltip('Exit fullscreen'));
    expect(exitedFullscreen, 1);

    binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(milliseconds: 200));
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 200));

    final Map<String, Object?> after = await _activePlayer();
    expect(after['textureId'], before['textureId']);
    expect(after['playerIdentity'], before['playerIdentity']);
    final MdPlayerCacheStats stats = await MdPlayerCache.stats();
    final String? confirmedQuality = controller.confirmedQuality?.label;
    final double speed = controller.value.playbackSpeed;
    await tester.pumpWidget(const SizedBox.shrink());
    await controller.dispose();

    final Map<String, Object?> report = <String, Object?>{
      'schemaVersion': 1,
      'runId': _runId,
      'repetition': _repetition,
      'records': <Map<String, Object?>>[
        <String, Object?>{
          'scenario': 'modern controls and stable identity',
          'terminalState': 'passed',
          'textureId': before['textureId'],
          'playerIdentity': before['playerIdentity'],
          'enteredFullscreen': enteredFullscreen,
          'exitedFullscreen': exitedFullscreen,
          'quality': confirmedQuality,
          'speed': speed,
          'cacheStats': <String, Object?>{
            'currentBytes': stats.currentBytes,
            'cachedResources': stats.cachedResources,
          },
        },
      ],
      'failures': <Object?>[],
      'flutterRebuilds': MdPlayerRebuildDiagnostics.snapshot(),
      'diagnostics': await _snapshot(),
    };
    binding.reportData = report;
  }, timeout: const Timeout(Duration(minutes: 5)));
}

MdPlayerSource _source() {
  MdPlayerQuality quality(String label, String file, int itag) =>
      MdPlayerQuality(
        label: label,
        videoUrl: '$_origin/video/$file',
        audioUrl: '$_origin/audio/audio.m4a',
        videoCacheKey: mdPlayerYoutubeCacheKey('phase4', 'video', itag),
        audioCacheKey: mdPlayerYoutubeCacheKey('phase4', 'audio', 20),
        videoStreamIdentity: 'phase4',
        audioStreamIdentity: 'phase4',
        videoItag: itag,
        audioItag: 20,
        videoRole: 'video',
        audioRole: 'audio',
      );
  final MdPlayerQuality low = quality('360p', 'low.mp4', 10);
  final MdPlayerQuality high = quality('1080p', 'high.mp4', 11);
  return MdPlayerSource(
    videoUrl: low.videoUrl,
    audioUrl: low.audioUrl,
    qualityLabel: low.label,
    qualities: <MdPlayerQuality>[low, high],
    videoCacheKey: low.videoCacheKey,
    audioCacheKey: low.audioCacheKey,
    videoStreamIdentity: low.videoStreamIdentity,
    audioStreamIdentity: low.audioStreamIdentity,
    videoItag: low.videoItag,
    audioItag: low.audioItag,
    videoRole: low.videoRole,
    audioRole: low.audioRole,
  );
}

Future<void> _waitForQuality(MdPlayerController controller) async {
  if (_terminal(controller.qualitySwitchState.value.status)) return;
  final Completer<void> done = Completer<void>();
  void listener() {
    if (_terminal(controller.qualitySwitchState.value.status) &&
        !done.isCompleted) {
      done.complete();
    }
  }

  controller.qualitySwitchState.addListener(listener);
  try {
    await done.future.timeout(const Duration(seconds: 40));
  } finally {
    controller.qualitySwitchState.removeListener(listener);
  }
  expect(controller.qualitySwitchState.value.status,
      MdQualitySwitchStatus.completed);
}

bool _terminal(MdQualitySwitchStatus status) =>
    status == MdQualitySwitchStatus.completed ||
    status == MdQualitySwitchStatus.failed;

Future<void> _showControls(WidgetTester tester, String tooltip) async {
  if (find.byTooltip(tooltip).evaluate().isNotEmpty) return;
  await tester.tap(find.byType(MdPlayer));
  await tester.pump();
  expect(find.byTooltip(tooltip), findsOneWidget);
}

class _FixedResolver extends MdPlayerSourceResolver {
  _FixedResolver(this.source);
  final MdPlayerSource source;

  @override
  Future<MdPlayerSource> resolve(String input) async => source;
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

Map<String, dynamic> _stringMap(Map<Object?, Object?> source) => source.map(
      (Object? key, Object? value) => MapEntry<String, dynamic>('$key', value),
    );
