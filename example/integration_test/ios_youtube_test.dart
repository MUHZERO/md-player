// Manual check against the network: flutter test
// integration_test/ios_youtube_test.dart -d <iOS simulator>
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:md_player_android/md_player_android.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('iOS merges YouTube video-only and audio-only streams',
      (WidgetTester tester) async {
    final MdPlayerController controller = MdPlayerController.network(
      'https://www.youtube.com/watch?v=aqz-KE-bpKQ',
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MdPlayer(
          controller: controller,
          controlsMode: MdPlayerControlsMode.modern,
        ),
      ),
    ));
    await tester.runAsync(() => controller.initialize());
    final MdPlayerValue ready = controller.value;
    debugPrint('MD ready size=${ready.size} duration=${ready.duration} '
        'quality=${ready.qualityLabel} '
        'qualities=${ready.qualities.map((MdPlayerQuality q) => q.label)} '
        'separate=${ready.qualities.first.audioUrl != null}');
    expect(ready.isInitialized, isTrue);
    expect(ready.qualities.first.audioUrl, isNotNull);
    expect(ready.size.height, greaterThan(0));

    await controller.play();
    await tester.runAsync(() async {
      for (int i = 0; i < 60; i++) {
        if (controller.value.position >= const Duration(seconds: 3)) break;
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
    });
    debugPrint('MD playing position=${controller.value.position}');
    expect(controller.value.position,
        greaterThanOrEqualTo(const Duration(seconds: 3)));

    await controller.seekTo(const Duration(minutes: 5));
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(seconds: 4)));
    debugPrint('MD after seek position=${controller.value.position}');
    expect(controller.value.position,
        greaterThanOrEqualTo(const Duration(minutes: 5)));

    final MdPlayerQuality hd = controller.value.qualities
        .firstWhere((MdPlayerQuality q) => q.label == '720p');
    await tester.runAsync(() => controller.setQuality(hd));
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(seconds: 4)));
    debugPrint('MD after switch quality=${controller.value.qualityLabel} '
        'size=${controller.value.size} position=${controller.value.position} '
        'state=${controller.qualitySwitchState.value.status}');
    expect(controller.qualitySwitchState.value.status,
        MdQualitySwitchStatus.completed);
    expect(controller.value.size.height, 720);
    expect(controller.value.position,
        greaterThanOrEqualTo(const Duration(minutes: 5)));
    final Duration switched = controller.value.position;
    await tester.runAsync(() async {
      for (int i = 0; i < 40; i++) {
        if (controller.value.position > switched) break;
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
    });
    debugPrint('MD resumed playing=${controller.value.isPlaying} '
        'position=${controller.value.position}');
    expect(controller.value.position, greaterThan(switched));
    await tester.runAsync(() => controller.dispose());
  }, skip: !Platform.isIOS);
}
