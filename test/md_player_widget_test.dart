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

  testWidgets('settings sheet opens quality and speed lists',
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

    expect(find.byTooltip('Seek backward'), findsOneWidget);
    expect(find.byTooltip('Seek forward'), findsOneWidget);
    expect(find.text('Playback speed'), findsNothing);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Playback speed'), findsOneWidget);
    expect(find.text('Normal'), findsOneWidget);

    await tester.tap(find.text('Playback speed'));
    await tester.pumpAndSettle();
    expect(find.text('1.5x'), findsOneWidget);
    await tester.tap(find.text('1.5x'));
    await tester.pumpAndSettle();
    expect(find.text('1.5x'), findsNothing);

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Quality'));
    await tester.pumpAndSettle();
    expect(find.text('1080p'), findsOneWidget);
    expect(find.text('360p'), findsOneWidget);
    await tester.tap(find.byType(BackButtonIcon));
    await tester.pumpAndSettle();
    expect(find.text('Playback speed'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await controller.dispose().timeout(const Duration(seconds: 2));
  });

  testWidgets('a tap while locked does not unlock the controls',
      (WidgetTester tester) async {
    final _Platform platform = _Platform();
    VideoPlayerPlatform.instance = platform;
    final MdPlayerController controller = _controller(platform);

    await tester.pumpWidget(_host(MdPlayer(
      controller: controller,
      controlsMode: MdPlayerControlsMode.modern,
      controlsConfiguration: MdPlayerControlsConfiguration(enableLock: true),
    )));
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lock controls'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Settings'), findsNothing);

    await tester.pump(const Duration(seconds: 4));
    expect(find.byTooltip('Unlock controls'), findsNothing);
    final Offset center = tester.getCenter(find.byType(MdPlayer));
    await tester.tapAt(center);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byTooltip('Unlock controls'), findsOneWidget);
    expect(find.byTooltip('Settings'), findsNothing);

    await tester.tapAt(center + const Offset(250, 0));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(center + const Offset(250, 0));
    await tester.pump(const Duration(milliseconds: 400));
    expect(platform.seeks, isEmpty);
    expect(find.byTooltip('Settings'), findsNothing);

    await tester.tap(find.byTooltip('Unlock controls'));
    await tester.pump();
    expect(find.byTooltip('Settings'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await controller.dispose().timeout(const Duration(seconds: 2));
  });

  testWidgets('chapters are marked and named while scrubbing',
      (WidgetTester tester) async {
    final _Platform platform = _Platform();
    VideoPlayerPlatform.instance = platform;
    final MdPlayerController controller = _controller(platform);
    const List<MdPlayerChapter> chapters = <MdPlayerChapter>[
      MdPlayerChapter(start: Duration.zero, title: 'Intro'),
      MdPlayerChapter(start: Duration(seconds: 30), title: 'Practice'),
    ];

    await tester.pumpWidget(_host(MdPlayer(
      controller: controller,
      controlsMode: MdPlayerControlsMode.modern,
      chapters: chapters,
    )));
    expect(find.byKey(const ValueKey<Duration>(Duration.zero)), findsNothing);
    expect(
      find.byKey(const ValueKey<Duration>(Duration(seconds: 30))),
      findsOneWidget,
    );

    final Rect bar = tester.getRect(find.byType(LinearProgressIndicator).first);
    final TestGesture drag =
        await tester.startGesture(bar.centerLeft + const Offset(20, 0));
    await drag.moveBy(const Offset(40, 0));
    await tester.pump();
    expect(find.textContaining('Intro'), findsOneWidget);
    await drag.moveTo(bar.centerLeft + Offset(bar.width * 0.75, 0));
    await tester.pump();
    expect(find.textContaining('Practice'), findsOneWidget);
    await drag.up();
    await tester.pump();
    expect(find.textContaining('Practice'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await controller.dispose().timeout(const Duration(seconds: 2));
  });

  testWidgets('no chapters leaves the progress bar unmarked',
      (WidgetTester tester) async {
    final _Platform platform = _Platform();
    VideoPlayerPlatform.instance = platform;
    final MdPlayerController controller = _controller(platform);

    await tester.pumpWidget(_host(MdPlayer(
      controller: controller,
      controlsMode: MdPlayerControlsMode.modern,
    )));
    expect(find.byWidgetPredicate((Widget w) => w.key is ValueKey<Duration>),
        findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await controller.dispose().timeout(const Duration(seconds: 2));
  });

  testWidgets('double-tap seek shows an accumulating side ripple',
      (WidgetTester tester) async {
    final _Platform platform = _Platform();
    VideoPlayerPlatform.instance = platform;
    final MdPlayerController controller = _controller(platform);
    final List<String> announcements = <String>[];
    tester.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<dynamic>(
      SystemChannels.accessibility,
      (dynamic message) async {
        final Map<dynamic, dynamic> event = message as Map<dynamic, dynamic>;
        if (event['type'] == 'announce') {
          announcements.add(
              (event['data'] as Map<dynamic, dynamic>)['message'] as String);
        }
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockDecodedMessageHandler<dynamic>(
            SystemChannels.accessibility, null));

    // RTL host: left still seeks backward and right forward.
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.rtl,
      child: _host(MdPlayer(
        controller: controller,
        controlsMode: MdPlayerControlsMode.modern,
        controlsConfiguration: MdPlayerControlsConfiguration(
          seekInterval: const Duration(seconds: 5),
        ),
      )),
    ));
    final Rect player = tester.getRect(find.byType(MdPlayer));
    final Offset right = player.centerRight - const Offset(60, 0);
    final Offset left = player.centerLeft + const Offset(60, 0);
    double opacity() => tester
        .widget<AnimatedOpacity>(find.ancestor(
          of: find.byType(Icon).last,
          matching: find.byType(AnimatedOpacity),
        ))
        .opacity;

    await tester.tapAt(right);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(right);
    await tester.pump();
    expect(find.text('5 seconds'), findsOneWidget);
    expect(opacity(), 1);

    // Single taps on the same side while the ripple shows accumulate.
    await tester.tapAt(right);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tapAt(right);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('15 seconds'), findsOneWidget);
    expect(announcements.last, 'Seek forward, 15 seconds');

    await tester.pump(const Duration(milliseconds: 800));
    await tester.pumpAndSettle();
    expect(opacity(), 0);

    await tester.tapAt(left);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(left);
    await tester.pump();
    expect(find.text('5 seconds'), findsOneWidget);
    expect(announcements.last, 'Seek backward, 5 seconds');
    final Rect ripple = tester.getRect(find.ancestor(
      of: find.text('5 seconds'),
      matching: find.byType(AnimatedOpacity),
    ));
    expect(ripple.left, player.left);
    await tester.pumpAndSettle(const Duration(seconds: 4));

    await tester.pumpWidget(const SizedBox.shrink());
    await controller.dispose().timeout(const Duration(seconds: 2));
  });

  testWidgets('seek feedback uses the host label', (WidgetTester tester) async {
    final _Platform platform = _Platform();
    VideoPlayerPlatform.instance = platform;
    final MdPlayerController controller = _controller(platform);

    await tester.pumpWidget(_host(MdPlayer(
      controller: controller,
      controlsMode: MdPlayerControlsMode.modern,
      labels: const MdPlayerControlsLabels(seekFeedback: '{seconds} s'),
    )));
    final Offset right =
        tester.getRect(find.byType(MdPlayer)).centerRight - const Offset(60, 0);
    await tester.tapAt(right);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(right);
    await tester.pump();
    expect(find.text('10 s'), findsOneWidget);
    await tester.pumpAndSettle(const Duration(seconds: 4));
    await tester.pumpWidget(const SizedBox.shrink());
    await controller.dispose().timeout(const Duration(seconds: 2));
  });

  testWidgets('controlsScale shrinks icons but keeps 44px targets',
      (WidgetTester tester) async {
    final _Platform platform = _Platform();
    VideoPlayerPlatform.instance = platform;
    final MdPlayerController controller = _controller(platform);

    Future<void> pumpScale(double scale) => tester.pumpWidget(_host(MdPlayer(
          controller: controller,
          controlsMode: MdPlayerControlsMode.modern,
          controlsConfiguration:
              MdPlayerControlsConfiguration(controlsScale: scale),
        )));

    await pumpScale(1);
    final double fullPlay = tester
        .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.play_arrow))
        .iconSize!;
    await pumpScale(0.5);
    expect(
      tester
          .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.play_arrow))
          .iconSize,
      fullPlay / 2,
    );
    expect(
      tester
          .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.settings))
          .iconSize,
      12,
    );
    for (final Element button in find.byType(IconButton).evaluate()) {
      final Size size = tester.getSize(find.byWidget(button.widget));
      expect(size.width, greaterThanOrEqualTo(44));
      expect(size.height, greaterThanOrEqualTo(44));
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await controller.dispose().timeout(const Duration(seconds: 2));
  });

  test('controlsScale rejects values outside 0.5 to 1.5', () {
    expect(MdPlayerControlsConfiguration().controlsScale, 1.0);
    for (final double scale in <double>[0.49, 1.51, double.nan]) {
      expect(
        () => MdPlayerControlsConfiguration(controlsScale: scale),
        throwsArgumentError,
      );
    }
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
