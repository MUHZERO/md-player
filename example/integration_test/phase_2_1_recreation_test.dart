import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:md_player_android/md_player_android.dart';

import 'phase_2_1_source.dart';

const MethodChannel _diagnostics =
    MethodChannel('md_player_android/debug_diagnostics');
const MethodChannel _lifecycle =
    MethodChannel('md_player_android/example_lifecycle');

void main() {
  final IntegrationTestWidgetsFlutterBinding binding =
      IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('explicit Activity recreation documents host-engine disposal',
      (WidgetTester tester) async {
    final int count =
        await _lifecycle.invokeMethod<int>('recreationCount') ?? 0;
    if (count == 0) {
      final MdPlayerController controller = MdPlayerController.network(
        'fixture',
        resolver: Phase21SourceResolver(),
      );
      await controller.initialize().timeout(const Duration(seconds: 20));
      final Map<Object?, Object?> before =
          await _diagnostics.invokeMapMethod<Object?, Object?>('snapshot') ??
              <Object?, Object?>{};
      expect(before['playerCreateCount'], 1);
      await _lifecycle.invokeMethod<void>('recreate');
      await Completer<void>().future;
      return;
    }

    final Map<Object?, Object?> after =
        await _diagnostics.invokeMapMethod<Object?, Object?>('snapshot') ??
            <Object?, Object?>{};
    expect(count, 1);
    expect(after['playerCreateCount'], 0);
    expect(after['players'], isEmpty);
    binding.reportData = <String, Object?>{
      'recreationCount': count,
      'hostEngineDisposed': true,
      'activePlayersAfterRecreation': 0,
    };
  }, timeout: const Timeout(Duration(minutes: 2)));
}
