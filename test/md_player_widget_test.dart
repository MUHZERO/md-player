import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:md_player_android/md_player_android.dart';
import 'package:md_player_android/src/md_player_debug.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

class _Resolver extends MdPlayerSourceResolver {
  _Resolver(this.source);
  final MdPlayerSource source;

  @override
  Future<MdPlayerSource> resolve(String input) async => source;
}

class _Platform extends MdPlayerAndroid {
  final List<Duration> seeks = <Duration>[];

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async => 7;

  @override
  Future<void> dispose(int textureId) async {}

  @override
  Future<void> play(int textureId) async {}

  @override
  Future<void> pause(int textureId) async {}

  @override
  Future<void> setVolume(int textureId, double volume) async {}

  @override
  Future<void> setPlaybackSpeed(int textureId, double speed) async {}

  @override
  Future<void> seekTo(int textureId, Duration position) async {
    seeks.add(position);
  }

  @override
  Future<Duration> getPosition(int textureId) async => Duration.zero;
}

class _Controller extends MdPlayerController {
  _Controller(_Platform platform)
      : super.network(
          'video',
          resolver: _Resolver(const MdPlayerSource(videoUrl: 'video')),
          platform: platform,
        );

  @override
  int get playerId => 7;
}

MdPlayerController _controller(
  _Platform platform, {
  List<MdPlayerQuality> qualities = const <MdPlayerQuality>[],
}) {
  final MdPlayerController controller = _Controller(platform)
    ..value = MdPlayerValue(
      duration: const Duration(minutes: 1),
      size: const Size(640, 360),
      isInitialized: true,
      qualities: qualities,
    );
  return controller;
}

Widget _host(Widget child) => MaterialApp(
      home: Scaffold(
        body: Center(child: SizedBox(width: 640, child: child)),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'legacy remains the default and position does not rebuild texture',
      (WidgetTester tester) async {
    final _Platform platform = _Platform();
    VideoPlayerPlatform.instance = platform;
    final MdPlayerController controller = _controller(platform);
    MdPlayerRebuildDiagnostics.reset();

    await tester.pumpWidget(_host(MdPlayer(controller: controller)));
    final Texture texture = tester.widget<Texture>(find.byType(Texture));
    expect(find.byTooltip('Speed'), findsOneWidget);
    expect(find.byTooltip('Settings'), findsNothing);

    controller.value = controller.value.copyWith(
      position: const Duration(seconds: 4),
    );
    await tester.pump();
    expect(identical(tester.widget<Texture>(find.byType(Texture)), texture),
        isTrue);
    expect(MdPlayerRebuildDiagnostics.snapshot()['surface'], 1);
    await tester.pumpWidget(const SizedBox.shrink());
    await controller.dispose().timeout(const Duration(seconds: 2));
  });

  testWidgets(
      'modern controls are opt-in and use host labels and fullscreen state',
      (WidgetTester tester) async {
    final _Platform platform = _Platform();
    VideoPlayerPlatform.instance = platform;
    final MdPlayerController controller = _controller(platform);
    int enter = 0;
    int legacy = 0;
    const MdPlayerControlsLabels labels = MdPlayerControlsLabels(
      settings: 'Player options',
      fullscreen: 'Go large',
    );
    MdPlayerRebuildDiagnostics.reset();

    await tester.pumpWidget(_host(MdPlayer(
      controller: controller,
      controlsMode: MdPlayerControlsMode.modern,
      labels: labels,
      onEnterFullscreen: () => enter++,
      onFullscreenPressed: () => legacy++,
    )));

    expect(find.byTooltip('Player options'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    expect(enter, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.pump();
    expect((enter, legacy), (1, 0));
    await tester.pumpWidget(_host(MdPlayer(
      controller: controller,
      controlsMode: MdPlayerControlsMode.modern,
      labels: labels,
      isFullscreen: true,
      onExitFullscreen: () {},
    )));
    expect(MdPlayerRebuildDiagnostics.snapshot()['surface'], 1);
    await tester.pumpWidget(const SizedBox.shrink());
    await controller.dispose().timeout(const Duration(seconds: 2));
  });

  testWidgets('compact modern layout exposes speed through settings',
      (WidgetTester tester) async {
    final _Platform platform = _Platform();
    VideoPlayerPlatform.instance = platform;
    final MdPlayerController controller = _controller(
      platform,
      qualities: const <MdPlayerQuality>[
        MdPlayerQuality(label: '360p', videoUrl: 'low'),
        MdPlayerQuality(label: '1080p', videoUrl: 'high'),
      ],
    );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 400,
          height: 240,
          child: MdPlayer(
            controller: controller,
            controlsMode: MdPlayerControlsMode.modern,
          ),
        ),
      ),
    ));

    expect(find.byTooltip('Playback speed'), findsNothing);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Playback speed'), findsOneWidget);
    expect(find.text('1080p'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await controller.dispose().timeout(const Duration(seconds: 2));
  });

  test('speed options reject unsafe consumer input', () {
    expect(
      () => MdPlayerControlsConfiguration(speedOptions: <double>[1, 1]),
      throwsArgumentError,
    );
    expect(
      () => MdPlayerControlsConfiguration(speedOptions: <double>[0]),
      throwsArgumentError,
    );
  });
}
