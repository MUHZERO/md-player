package io.flutter.plugins.videoplayerexample;

import android.content.Intent;
import android.content.pm.ActivityInfo;
import android.os.Handler;
import android.os.Looper;
import androidx.annotation.NonNull;
import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;

/** Private lifecycle controls used only by the example's debug integration harness. */
public final class MainActivity extends FlutterActivity {
  private static final String CHANNEL = "md_player_android/example_lifecycle";

  @Override
  public void configureFlutterEngine(@NonNull FlutterEngine flutterEngine) {
    super.configureFlutterEngine(flutterEngine);
    new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), CHANNEL)
        .setMethodCallHandler(
            (call, result) -> {
              switch (call.method) {
                case "orientation":
                  String value = call.argument("value");
                  setRequestedOrientation(
                      "landscape".equals(value)
                          ? ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE
                          : ActivityInfo.SCREEN_ORIENTATION_PORTRAIT);
                  result.success(null);
                  break;
                case "recreate":
                  recreate();
                  result.success(null);
                  break;
                case "backgroundForeground":
                  Number delay = call.argument("milliseconds");
                  long milliseconds = delay == null ? 1000 : delay.longValue();
                  moveTaskToBack(true);
                  new Handler(Looper.getMainLooper())
                      .postDelayed(
                          () -> {
                            Intent intent = new Intent(this, MainActivity.class);
                            intent.addFlags(Intent.FLAG_ACTIVITY_REORDER_TO_FRONT);
                            startActivity(intent);
                          },
                          milliseconds);
                  result.success(null);
                  break;
                default:
                  result.notImplemented();
              }
            });
  }
}
