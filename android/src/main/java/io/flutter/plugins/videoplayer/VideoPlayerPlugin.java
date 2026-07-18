// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

package io.flutter.plugins.videoplayer;

import android.content.Context;
import android.content.pm.ApplicationInfo;
import android.os.Build;
import android.util.LongSparseArray;
import androidx.annotation.NonNull;
import io.flutter.FlutterInjector;
import io.flutter.Log;
import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugins.videoplayer.Messages.AndroidVideoPlayerApi;
import io.flutter.plugins.videoplayer.Messages.CreateMessage;
import io.flutter.plugins.videoplayer.Messages.LoopingMessage;
import io.flutter.plugins.videoplayer.Messages.MixWithOthersMessage;
import io.flutter.plugins.videoplayer.Messages.PlaybackSpeedMessage;
import io.flutter.plugins.videoplayer.Messages.PositionMessage;
import io.flutter.plugins.videoplayer.Messages.ChangeQualityMessage;
import io.flutter.plugins.videoplayer.Messages.TextureMessage;
import io.flutter.plugins.videoplayer.Messages.VolumeMessage;
import io.flutter.view.TextureRegistry;
import java.security.KeyManagementException;
import java.security.NoSuchAlgorithmException;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import javax.net.ssl.HttpsURLConnection;

/** Android platform implementation of the VideoPlayerPlugin. */
public class VideoPlayerPlugin implements FlutterPlugin, AndroidVideoPlayerApi {
  private static final String TAG = "VideoPlayerPlugin";
  private final LongSparseArray<VideoPlayer> videoPlayers = new LongSparseArray<>();
  private FlutterState flutterState;
  private final VideoPlayerOptions options = new VideoPlayerOptions();
  private MethodChannel diagnosticsChannel;
  private boolean diagnosticsEnabled;
  private int playerCreateCount;
  private int playerDisposeCount;
  private final List<Map<String, Object>> disposedPlayerSnapshots = new ArrayList<>();

  /** Register this with the v2 embedding for the plugin to respond to lifecycle callbacks. */
  public VideoPlayerPlugin() {}

  @Override
  public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
    if (android.os.Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP) {
      try {
        HttpsURLConnection.setDefaultSSLSocketFactory(new CustomSSLSocketFactory());
      } catch (KeyManagementException | NoSuchAlgorithmException e) {
        Log.w(
            TAG,
            "Failed to enable TLSv1.1 and TLSv1.2 Protocols for API level 19 and below.\n"
                + "For more information about Socket Security, please consult the following link:\n"
                + "https://developer.android.com/reference/javax/net/ssl/SSLSocket",
            e);
      }
    }

    final FlutterInjector injector = FlutterInjector.instance();
    this.flutterState =
        new FlutterState(
            binding.getApplicationContext(),
            binding.getBinaryMessenger(),
            injector.flutterLoader()::getLookupKeyForAsset,
            injector.flutterLoader()::getLookupKeyForAsset,
            binding.getTextureRegistry());
    flutterState.startListening(this, binding.getBinaryMessenger());
    diagnosticsEnabled =
        (binding.getApplicationContext().getApplicationInfo().flags
                & ApplicationInfo.FLAG_DEBUGGABLE)
            != 0;
    if (diagnosticsEnabled) {
      diagnosticsChannel =
          new MethodChannel(binding.getBinaryMessenger(), "md_player_android/debug_diagnostics");
      diagnosticsChannel.setMethodCallHandler(
          (call, result) -> {
            if ("snapshot".equals(call.method)) {
              result.success(debugSnapshot());
            } else if ("clear".equals(call.method)) {
              clearDebugDiagnostics();
              result.success(null);
            } else {
              result.notImplemented();
            }
          });
    }
  }

  @Override
  public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
    if (flutterState == null) {
      Log.wtf(TAG, "Detached from the engine before registering to it.");
    }
    flutterState.stopListening(binding.getBinaryMessenger());
    if (diagnosticsChannel != null) {
      diagnosticsChannel.setMethodCallHandler(null);
      diagnosticsChannel = null;
    }
    flutterState = null;
    onDestroy();
    diagnosticsEnabled = false;
  }

  private void disposeAllPlayers() {
    for (int i = 0; i < videoPlayers.size(); i++) {
      disposePlayer(videoPlayers.keyAt(i), videoPlayers.valueAt(i));
    }
    videoPlayers.clear();
  }

  public void onDestroy() {
    // The whole FlutterView is being destroyed. Here we release resources acquired for all
    // instances
    // of VideoPlayer. Once https://github.com/flutter/flutter/issues/19358 is resolved this may
    // be replaced with just asserting that videoPlayers.isEmpty().
    // https://github.com/flutter/flutter/issues/20989 tracks this.
    disposeAllPlayers();
  }

  public void initialize() {
    disposeAllPlayers();
  }

  public @NonNull TextureMessage create(@NonNull CreateMessage arg) {
    TextureRegistry.SurfaceProducer handle = flutterState.textureRegistry.createSurfaceProducer();
    EventChannel eventChannel =
        new EventChannel(
            flutterState.binaryMessenger, "flutter.io/videoPlayer/videoEvents" + handle.id());

    final VideoAsset videoAsset = assetFromCreateMessage(arg);
    final VideoAsset audioAsset =
        arg.getAudioUri() == null || arg.getAudioUri().isEmpty()
            ? null
            : VideoAsset.fromRemoteUrl(
                arg.getAudioUri(), VideoAsset.StreamingFormat.UNKNOWN, arg.getHttpHeaders());
    final MediaSourceDescriptor descriptor =
        new MediaSourceDescriptor(
            videoAsset,
            audioAsset,
            arg.getHttpHeaders(),
            arg.getFormatHint(),
            null,
            null,
            null,
            null,
            null,
            null,
            null,
            null);

    videoPlayers.put(
        handle.id(),
        VideoPlayer.create(
            flutterState.applicationContext,
            VideoPlayerEventCallbacks.bindTo(eventChannel),
            handle,
            descriptor,
            options));
    if (diagnosticsEnabled) {
      playerCreateCount++;
    }

    return new TextureMessage.Builder().setTextureId(handle.id()).build();
  }

  private VideoAsset assetFromCreateMessage(@NonNull CreateMessage arg) {
    if (arg.getAsset() != null) {
      String assetLookupKey;
      if (arg.getPackageName() != null) {
        assetLookupKey =
            flutterState.keyForAssetAndPackageName.get(arg.getAsset(), arg.getPackageName());
      } else {
        assetLookupKey = flutterState.keyForAsset.get(arg.getAsset());
      }
      return VideoAsset.fromAssetUrl("asset:///" + assetLookupKey);
    }
    if (arg.getUri().startsWith("rtsp://")) {
      return VideoAsset.fromRtspUrl(arg.getUri());
    }
    return VideoAsset.fromRemoteUrl(
        arg.getUri(), streamingFormat(arg.getFormatHint()), arg.getHttpHeaders());
  }

  private static VideoAsset.StreamingFormat streamingFormat(String formatHint) {
    if (formatHint == null) {
      return VideoAsset.StreamingFormat.UNKNOWN;
    }
    switch (formatHint) {
      case "ss":
        return VideoAsset.StreamingFormat.SMOOTH;
      case "dash":
        return VideoAsset.StreamingFormat.DYNAMIC_ADAPTIVE;
      case "hls":
        return VideoAsset.StreamingFormat.HTTP_LIVE;
      default:
        return VideoAsset.StreamingFormat.UNKNOWN;
    }
  }

  public void dispose(@NonNull TextureMessage arg) {
    VideoPlayer player = videoPlayers.get(arg.getTextureId());
    if (player == null) {
      Log.w(TAG, "Ignoring dispose for missing player " + arg.getTextureId());
      return;
    }
    videoPlayers.remove(arg.getTextureId());
    disposePlayer(arg.getTextureId(), player);
  }

  public void setLooping(@NonNull LoopingMessage arg) {
    VideoPlayer player = videoPlayers.get(arg.getTextureId());
    if (player == null) {
      Log.w(TAG, "Ignoring setLooping for missing player " + arg.getTextureId());
      return;
    }
    player.setLooping(arg.getIsLooping());
  }

  public void setVolume(@NonNull VolumeMessage arg) {
    VideoPlayer player = videoPlayers.get(arg.getTextureId());
    if (player == null) {
      Log.w(TAG, "Ignoring setVolume for missing player " + arg.getTextureId());
      return;
    }
    player.setVolume(arg.getVolume());
  }

  public void setPlaybackSpeed(@NonNull PlaybackSpeedMessage arg) {
    VideoPlayer player = videoPlayers.get(arg.getTextureId());
    if (player == null) {
      Log.w(TAG, "Ignoring setPlaybackSpeed for missing player " + arg.getTextureId());
      return;
    }
    player.setPlaybackSpeed(arg.getSpeed());
  }

  public void play(@NonNull TextureMessage arg) {
    VideoPlayer player = videoPlayers.get(arg.getTextureId());
    if (player != null) {
      player.play();
    } else {
      Log.e("VideoPlayerPlugin", "VideoPlayer instance is null when trying to play");
    }
  }

  public void changeQuality(@NonNull ChangeQualityMessage arg) {
    VideoPlayer player = videoPlayers.get(arg.getTextureId());
    if (player == null) {
      throw new IllegalStateException("Missing player " + arg.getTextureId());
    }
    String videoUri = arg.getVideoUri() == null ? arg.getNewUrl() : arg.getVideoUri();
    if (videoUri.trim().isEmpty()) {
      throw new IllegalArgumentException("Quality video URI is empty");
    }
    Map<String, String> headers =
        arg.getHttpHeaders() == null ? Collections.emptyMap() : arg.getHttpHeaders();
    VideoAsset video =
        VideoAsset.fromRemoteUrl(videoUri, streamingFormat(arg.getVideoFormatHint()), headers);
    VideoAsset audio =
        arg.getAudioUri() == null || arg.getAudioUri().isEmpty()
            ? null
            : VideoAsset.fromRemoteUrl(
                arg.getAudioUri(), streamingFormat(arg.getAudioFormatHint()), headers);
    MediaSourceDescriptor descriptor =
        new MediaSourceDescriptor(
            video,
            audio,
            headers,
            arg.getVideoFormatHint(),
            arg.getAudioFormatHint(),
            arg.getVideoCacheKey(),
            arg.getAudioCacheKey(),
            arg.getVideoStreamIdentity(),
            arg.getAudioStreamIdentity(),
            arg.getVideoItag(),
            arg.getAudioItag(),
            arg.getRequestedLabel());
    String operationId =
        arg.getOperationId() == null ? "legacy-" + UUID.randomUUID() : arg.getOperationId();
    player.changeQuality(operationId, descriptor);
  }

  public @NonNull PositionMessage position(@NonNull TextureMessage arg) {
    VideoPlayer player = videoPlayers.get(arg.getTextureId());
    if (player == null) {
      Log.w(TAG, "Returning zero position for missing player " + arg.getTextureId());
      return new PositionMessage.Builder()
          .setPosition(0L)
          .setTextureId(arg.getTextureId())
          .build();
    }
    PositionMessage result =
        new PositionMessage.Builder()
            .setPosition(player.getPosition())
            .setTextureId(arg.getTextureId())
            .build();
    player.sendBufferingUpdate();
    return result;
  }

  public void seekTo(@NonNull PositionMessage arg) {
    VideoPlayer player = videoPlayers.get(arg.getTextureId());
    if (player == null) {
      Log.w(TAG, "Ignoring seekTo for missing player " + arg.getTextureId());
      return;
    }
    player.seekTo(arg.getPosition().intValue());
  }

  public void pause(@NonNull TextureMessage arg) {
    VideoPlayer player = videoPlayers.get(arg.getTextureId());
    if (player != null) {
      player.pause();
    } else {
      Log.e("VideoPlayerPlugin", "VideoPlayer instance is null when trying to pause");
    }
    //player.pause();
  }

  @Override
  public void setMixWithOthers(@NonNull MixWithOthersMessage arg) {
    options.mixWithOthers = arg.getMixWithOthers();
  }

  private void disposePlayer(long textureId, VideoPlayer player) {
    player.dispose();
    if (!diagnosticsEnabled) {
      return;
    }
    playerDisposeCount++;
    disposedPlayerSnapshots.add(player.debugSnapshot(textureId));
    if (disposedPlayerSnapshots.size() > 64) {
      disposedPlayerSnapshots.remove(0);
    }
  }

  @NonNull
  Map<String, Object> debugSnapshot() {
    Map<String, Object> snapshot = new HashMap<>();
    List<Map<String, Object>> players = new ArrayList<>();
    for (int i = 0; i < videoPlayers.size(); i++) {
      players.add(videoPlayers.valueAt(i).debugSnapshot(videoPlayers.keyAt(i)));
    }
    snapshot.put("elapsedRealtimeNanos", android.os.SystemClock.elapsedRealtimeNanos());
    snapshot.put("playerCreateCount", playerCreateCount);
    snapshot.put("playerDisposeCount", playerDisposeCount);
    snapshot.put("players", players);
    snapshot.put("disposedPlayers", new ArrayList<>(disposedPlayerSnapshots));
    return snapshot;
  }

  void clearDebugDiagnostics() {
    playerCreateCount = 0;
    playerDisposeCount = 0;
    disposedPlayerSnapshots.clear();
    for (int i = 0; i < videoPlayers.size(); i++) {
      videoPlayers.valueAt(i).clearDebugDiagnostics();
    }
  }

  private interface KeyForAssetFn {
    String get(String asset);
  }

  private interface KeyForAssetAndPackageName {
    String get(String asset, String packageName);
  }

  private static final class FlutterState {
    final Context applicationContext;
    final BinaryMessenger binaryMessenger;
    final KeyForAssetFn keyForAsset;
    final KeyForAssetAndPackageName keyForAssetAndPackageName;
    final TextureRegistry textureRegistry;

    FlutterState(
        Context applicationContext,
        BinaryMessenger messenger,
        KeyForAssetFn keyForAsset,
        KeyForAssetAndPackageName keyForAssetAndPackageName,
        TextureRegistry textureRegistry) {
      this.applicationContext = applicationContext;
      this.binaryMessenger = messenger;
      this.keyForAsset = keyForAsset;
      this.keyForAssetAndPackageName = keyForAssetAndPackageName;
      this.textureRegistry = textureRegistry;
    }

    void startListening(VideoPlayerPlugin methodCallHandler, BinaryMessenger messenger) {
      AndroidVideoPlayerApi.setUp(messenger, methodCallHandler);
    }

    void stopListening(BinaryMessenger messenger) {
      AndroidVideoPlayerApi.setUp(messenger, null);
    }
  }
}
