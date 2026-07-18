package io.flutter.plugins.videoplayerexample;

import android.app.ActivityManager;
import android.content.Context;
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
  private static int recreationCount;

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
                  recreationCount++;
                  result.success(null);
                  new Handler(Looper.getMainLooper()).post(this::recreate);
                  break;
                case "recreationCount":
                  result.success(recreationCount);
                  break;
                case "backgroundForeground":
                  Number delay = call.argument("milliseconds");
                  long milliseconds = delay == null ? 1000 : delay.longValue();
                  moveTaskToBack(true);
                  new Handler(Looper.getMainLooper())
                      .postDelayed(
                          () -> {
                            ActivityManager manager =
                                (ActivityManager) getSystemService(Context.ACTIVITY_SERVICE);
                            manager.getAppTasks().get(0).moveToFront();
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
