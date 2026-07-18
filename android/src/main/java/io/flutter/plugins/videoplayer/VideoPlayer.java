// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

package io.flutter.plugins.videoplayer;

import static androidx.media3.common.Player.REPEAT_MODE_ALL;
import static androidx.media3.common.Player.REPEAT_MODE_OFF;

import android.content.Context;
import android.content.pm.ApplicationInfo;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import android.view.Surface;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.annotation.RestrictTo;
import androidx.annotation.VisibleForTesting;
import androidx.media3.common.AudioAttributes;
import androidx.media3.common.C;
import androidx.media3.common.PlaybackException;
import androidx.media3.common.PlaybackParameters;
import androidx.media3.common.Player;
import androidx.media3.common.Timeline;
import androidx.media3.common.Tracks;
import androidx.media3.exoplayer.ExoPlayer;
import androidx.media3.exoplayer.analytics.AnalyticsListener;
import androidx.media3.exoplayer.source.MediaSource;
import io.flutter.view.TextureRegistry;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

final class VideoPlayer implements TextureRegistry.SurfaceProducer.Callback {
  static final long PREPARATION_TIMEOUT_MS = 15_000;
  static final long FIRST_FRAME_TIMEOUT_MS = 8_000;
  static final long ROLLBACK_TIMEOUT_MS = 15_000;
  // Active-surface worst case: preparation + first frame + rollback = 38 seconds.

  @NonNull private final Context context;
  @NonNull private final TextureRegistry.SurfaceProducer surfaceProducer;
  @NonNull private final VideoPlayerCallbacks events;
  @NonNull private final ExoPlayer exoPlayer;
  @NonNull private final Handler handler;
  private final boolean debugEnabled;
  @NonNull private MediaSourceDescriptor lastConfirmedSourceDescriptor;
  @Nullable private SwitchOperation activeOperation;
  private long sourceGeneration;
  private boolean surfaceAvailable;
  private boolean disposed;
  private int replacementCount;
  private int rollbackCount;
  private int acceptedFrameCount;
  private int rejectedStaleFrameCount;
  private int surfaceLossCount;
  private long lastSurfaceAttachmentNanos;
  @NonNull private final List<Map<String, Object>> operationHistory = new ArrayList<>();

  @NonNull
  static VideoPlayer create(
      @NonNull Context context,
      @NonNull VideoPlayerCallbacks events,
      @NonNull TextureRegistry.SurfaceProducer surfaceProducer,
      @NonNull VideoAsset asset,
      @Nullable VideoAsset audio,
      @NonNull VideoPlayerOptions options) {
    return create(context, events, surfaceProducer, MediaSourceDescriptor.legacy(asset, audio), options);
  }

  @NonNull
  static VideoPlayer create(
      @NonNull Context context,
      @NonNull VideoPlayerCallbacks events,
      @NonNull TextureRegistry.SurfaceProducer surfaceProducer,
      @NonNull MediaSourceDescriptor descriptor,
      @NonNull VideoPlayerOptions options) {
    return new VideoPlayer(
        () ->
            new ExoPlayer.Builder(context)
                .setMediaSourceFactory(descriptor.videoAsset.getMediaSourceFactory(context))
                .build(),
        context,
        events,
        surfaceProducer,
        descriptor,
        options,
        new Handler(Looper.getMainLooper()));
  }

  /** A closure-compatible signature since {@link java.util.function.Supplier} is API level 24. */
  interface ExoPlayerProvider {
    ExoPlayer get();
  }

  @VisibleForTesting
  VideoPlayer(
      @NonNull ExoPlayerProvider provider,
      @NonNull Context context,
      @NonNull VideoPlayerCallbacks events,
      @NonNull TextureRegistry.SurfaceProducer surfaceProducer,
      @NonNull VideoAsset videoAsset,
      @Nullable VideoAsset audioAsset,
      @NonNull VideoPlayerOptions options) {
    this(
        provider,
        context,
        events,
        surfaceProducer,
        MediaSourceDescriptor.legacy(videoAsset, audioAsset),
        options,
        new Handler(Looper.getMainLooper()));
  }

  @VisibleForTesting
  VideoPlayer(
      @NonNull ExoPlayerProvider provider,
      @NonNull Context context,
      @NonNull VideoPlayerCallbacks events,
      @NonNull TextureRegistry.SurfaceProducer surfaceProducer,
      @NonNull MediaSourceDescriptor descriptor,
      @NonNull VideoPlayerOptions options,
      @NonNull Handler handler) {
    this.context = context;
    this.events = events;
    this.surfaceProducer = surfaceProducer;
    this.lastConfirmedSourceDescriptor = descriptor;
    this.handler = handler;
    this.debugEnabled =
        (context.getApplicationInfo().flags & ApplicationInfo.FLAG_DEBUGGABLE) != 0;
    this.exoPlayer = provider.get();
    setSource(descriptor, 0, "initial");
    exoPlayer.prepare();
    attachSurface();
    exoPlayer.addListener(
        new ExoPlayerEventListener(exoPlayer, events, this::handlePlaybackError));
    exoPlayer.addListener(new SwitchListener());
    exoPlayer.addAnalyticsListener(new FrameListener());
    setAudioAttributes(exoPlayer, options.mixWithOthers);
    surfaceProducer.setCallback(this);
  }

  void changeQuality(@NonNull String operationId, @NonNull MediaSourceDescriptor descriptor) {
    if (disposed) {
      throw new IllegalStateException("Player is disposed");
    }
    PlaybackSnapshot snapshot = PlaybackSnapshot.capture(exoPlayer);
    SwitchOperation superseded = activeOperation;
    if (superseded != null) {
      snapshot = snapshot.withDesired(superseded.desiredPositionMs, superseded.desiredPlayWhenReady);
    }
    cancelOperation();
    SwitchOperation operation =
        new SwitchOperation(
            operationId, descriptor, lastConfirmedSourceDescriptor, snapshot, ++sourceGeneration);
    if (debugEnabled) {
      replacementCount++;
      operation.diagnostics = new LinkedHashMap<>();
      diagnostic(operation, "operationId", operationId);
      diagnostic(operation, "requestedQuality", label(descriptor));
      diagnostic(operation, "previousQuality", label(lastConfirmedSourceDescriptor));
      diagnostic(operation, "state", "active");
      diagnostic(operation, "requestNanos", SystemClock.elapsedRealtimeNanos());
      diagnostic(operation, "requestPositionMs", snapshot.positionMs);
      diagnostic(operation, "desiredPositionMs", snapshot.positionMs);
      diagnostic(operation, "desiredPlayWhenReady", snapshot.playWhenReady);
      diagnostic(operation, "sourceGeneration", operation.sourceGeneration);
      operationHistory.add(operation.diagnostics);
      if (operationHistory.size() > 64) {
        operationHistory.remove(0);
      }
    }
    MediaSource requestedSource = descriptor.build(context, operation.sourceId());
    activeOperation = operation;
    emit(operation, "preparing", null, null);
    try {
      exoPlayer.setMediaSource(requestedSource, operation.desiredPositionMs);
      diagnostic(operation, "acceptanceNanos", SystemClock.elapsedRealtimeNanos());
      snapshot.restoreSettings(exoPlayer);
      exoPlayer.setPlayWhenReady(operation.desiredPlayWhenReady);
      exoPlayer.prepare();
      emit(operation, "switching", null, null);
      schedule(operation, PREPARATION_TIMEOUT_MS, "preparation timeout");
    } catch (RuntimeException error) {
      fail(operation, "source replacement failed: " + error);
    }
  }

  private void setSource(MediaSourceDescriptor descriptor, long positionMs, String sourceId) {
    MediaSource source = descriptor.build(context, sourceId);
    exoPlayer.setMediaSource(source, positionMs);
  }

  private final class SwitchListener implements Player.Listener {
    @Override
    public void onPlaybackStateChanged(int state) {
      if (state == Player.STATE_READY) {
        onReady();
      }
    }
  }

  private final class FrameListener implements AnalyticsListener {
    @Override
    public void onRenderedFirstFrame(
        @NonNull EventTime eventTime, @NonNull Object output, long renderTimeMs) {
      SwitchOperation operation = activeOperation;
      if (operation == null) {
        return;
      }
      if (!operation.ready || !operation.sourceId().equals(sourceId(eventTime))) {
        if (debugEnabled) {
          rejectedStaleFrameCount++;
        }
        return;
      }
      if (debugEnabled) {
        acceptedFrameCount++;
      }
      diagnostic(operation, "firstFrameNanos", SystemClock.elapsedRealtimeNanos());
      finishReadyOperation(operation);
    }
  }

  @Nullable
  private static String sourceId(AnalyticsListener.EventTime eventTime) {
    Timeline timeline = eventTime.timeline;
    if (timeline.isEmpty() || eventTime.windowIndex < 0 || eventTime.windowIndex >= timeline.getWindowCount()) {
      return null;
    }
    return timeline.getWindow(eventTime.windowIndex, new Timeline.Window()).mediaItem.mediaId;
  }

  @VisibleForTesting
  void onReady() {
    SwitchOperation operation = activeOperation;
    if (operation == null) {
      return;
    }
    cancelTimeout(operation);
    operation.ready = true;
    diagnostic(operation, "readyNanos", SystemClock.elapsedRealtimeNanos());
    if (operation.rollback || !hasSelectedVideoTrack()) {
      finishReadyOperation(operation);
      return;
    }
    operation.firstFrameRemainingMs = FIRST_FRAME_TIMEOUT_MS;
    if (surfaceAvailable) {
      scheduleFirstFrame(operation);
    }
  }

  private boolean hasSelectedVideoTrack() {
    Tracks tracks = exoPlayer.getCurrentTracks();
    for (Tracks.Group group : tracks.getGroups()) {
      if (group.getType() == C.TRACK_TYPE_VIDEO && group.isSelected()) {
        return true;
      }
    }
    return false;
  }

  @VisibleForTesting
  void onRenderedFirstFrameForSource(@NonNull String sourceId) {
    SwitchOperation operation = activeOperation;
    if (operation != null && operation.ready && operation.sourceId().equals(sourceId)) {
      if (debugEnabled) {
        acceptedFrameCount++;
      }
      diagnostic(operation, "firstFrameNanos", SystemClock.elapsedRealtimeNanos());
      finishReadyOperation(operation);
    } else {
      if (debugEnabled) {
        rejectedStaleFrameCount++;
      }
    }
  }

  private void finishReadyOperation(SwitchOperation operation) {
    if (!isCurrent(operation)) {
      return;
    }
    cancelTimeout(operation);
    if (operation.rollback) {
      emit(operation, "failed", operation.failureReason, true);
      finishDiagnostics(operation, "failed", true);
    } else {
      lastConfirmedSourceDescriptor = operation.requested;
      emit(operation, "completed", null, null);
      finishDiagnostics(operation, "completed", null);
    }
    activeOperation = null;
  }

  private boolean handlePlaybackError(@NonNull PlaybackException error) {
    if (activeOperation == null) {
      return false;
    }
    fail(activeOperation, "Video player had error " + error);
    return true;
  }

  private void fail(SwitchOperation operation, String reason) {
    if (!isCurrent(operation)) {
      return;
    }
    cancelTimeout(operation);
    if (operation.rollback) {
      exoPlayer.stop();
      emit(operation, "failed", operation.failureReason, false);
      finishDiagnostics(operation, "failed", false);
      activeOperation = null;
      return;
    }
    operation.rollback = true;
    if (debugEnabled) {
      rollbackCount++;
    }
    operation.ready = false;
    operation.failureReason = reason;
    diagnostic(operation, "rollbackStartedNanos", SystemClock.elapsedRealtimeNanos());
    diagnostic(operation, "failure", reason);
    operation.sourceGeneration = ++sourceGeneration;
    try {
      setSource(
          operation.previous,
          operation.desiredPositionMs,
          operation.sourceId());
      operation.snapshot.restoreSettings(exoPlayer);
      exoPlayer.setPlayWhenReady(operation.desiredPlayWhenReady);
      exoPlayer.prepare();
      schedule(operation, ROLLBACK_TIMEOUT_MS, "rollback preparation timeout");
    } catch (RuntimeException rollbackError) {
      exoPlayer.stop();
      emit(operation, "failed", reason, false);
      finishDiagnostics(operation, "failed", false);
      activeOperation = null;
    }
  }

  private void schedule(SwitchOperation operation, long delayMs, String reason) {
    operation.timeout = () -> fail(operation, reason);
    handler.postDelayed(operation.timeout, delayMs);
  }

  private void scheduleFirstFrame(SwitchOperation operation) {
    operation.firstFrameDeadlineMs = SystemClock.uptimeMillis() + operation.firstFrameRemainingMs;
    schedule(operation, operation.firstFrameRemainingMs, "first frame timeout");
  }

  private void suspendFirstFrameTimeout() {
    SwitchOperation operation = activeOperation;
    if (operation == null || !operation.ready || operation.timeout == null) {
      return;
    }
    operation.firstFrameRemainingMs =
        Math.max(1, operation.firstFrameDeadlineMs - SystemClock.uptimeMillis());
    cancelTimeout(operation);
  }

  private void cancelTimeout(SwitchOperation operation) {
    if (operation.timeout != null) {
      handler.removeCallbacks(operation.timeout);
      operation.timeout = null;
    }
  }

  private void cancelOperation() {
    SwitchOperation operation = activeOperation;
    if (operation != null) {
      cancelTimeout(operation);
      finishDiagnostics(operation, "cancelled", null);
      activeOperation = null;
    }
  }

  private boolean isCurrent(SwitchOperation operation) {
    return !disposed && activeOperation == operation;
  }

  private static String label(MediaSourceDescriptor descriptor) {
    return descriptor.qualityLabel == null ? "initial" : descriptor.qualityLabel;
  }

  private static void diagnostic(SwitchOperation operation, String key, Object value) {
    if (operation.diagnostics != null) {
      operation.diagnostics.put(key, value);
    }
  }

  private void finishDiagnostics(
      SwitchOperation operation, String state, @Nullable Boolean rollbackSucceeded) {
    if (operation.diagnostics == null) {
      return;
    }
    diagnostic(operation, "state", state);
    diagnostic(operation, "completionNanos", SystemClock.elapsedRealtimeNanos());
    diagnostic(operation, "finalPositionMs", exoPlayer.getCurrentPosition());
    diagnostic(operation, "desiredPositionMs", operation.desiredPositionMs);
    diagnostic(operation, "desiredPlayWhenReady", operation.desiredPlayWhenReady);
    diagnostic(operation, "surfaceLossCount", surfaceLossCount);
    diagnostic(operation, "rejectedStaleFrameCount", rejectedStaleFrameCount);
    if (rollbackSucceeded != null) {
      diagnostic(operation, "rollbackSucceeded", rollbackSucceeded);
    }
  }

  private void emit(
      SwitchOperation operation,
      String phase,
      @Nullable String errorDescription,
      @Nullable Boolean rollbackSucceeded) {
    if (!isCurrent(operation)) {
      return;
    }
    Map<String, Object> event = new HashMap<>();
    event.put("event", "qualitySwitch");
    event.put("operationId", operation.id);
    event.put("phase", phase);
    if (operation.requested.qualityLabel != null) {
      event.put("requestedLabel", operation.requested.qualityLabel);
    }
    if (errorDescription != null) {
      event.put("errorDescription", errorDescription);
    }
    if (rollbackSucceeded != null) {
      event.put("rollbackSucceeded", rollbackSucceeded);
    }
    events.onQualitySwitch(event);
  }

  @RestrictTo(RestrictTo.Scope.LIBRARY)
  @SuppressWarnings("removal")
  public void onSurfaceCreated() {
    onSurfaceAvailable();
  }

  @RestrictTo(RestrictTo.Scope.LIBRARY)
  @SuppressWarnings("removal")
  public void onSurfaceDestroyed() {
    onSurfaceCleanup();
  }

  @Override
  public void onSurfaceAvailable() {
    if (disposed) {
      return;
    }
    attachSurface();
    SwitchOperation operation = activeOperation;
    if (surfaceAvailable
        && operation != null
        && operation.ready
        && operation.timeout == null) {
      scheduleFirstFrame(operation);
    }
  }

  private void attachSurface() {
    Surface surface = surfaceProducer.getSurface();
    surfaceAvailable = surface != null && surface.isValid();
    if (surfaceAvailable) {
      exoPlayer.setVideoSurface(surface);
      lastSurfaceAttachmentNanos = SystemClock.elapsedRealtimeNanos();
      SwitchOperation operation = activeOperation;
      if (operation != null) {
        diagnostic(operation, "surfaceAttachmentNanos", lastSurfaceAttachmentNanos);
      }
    }
  }

  @Override
  public void onSurfaceCleanup() {
    if (disposed) {
      return;
    }
    surfaceAvailable = false;
    if (debugEnabled) {
      surfaceLossCount++;
    }
    SwitchOperation operation = activeOperation;
    if (operation != null) {
      diagnostic(operation, "surfaceLossNanos", SystemClock.elapsedRealtimeNanos());
    }
    suspendFirstFrameTimeout();
    exoPlayer.clearVideoSurface();
  }

  void sendBufferingUpdate() {
    events.onBufferingUpdate(exoPlayer.getBufferedPosition());
  }

  private static void setAudioAttributes(ExoPlayer exoPlayer, boolean isMixMode) {
    exoPlayer.setAudioAttributes(
        new AudioAttributes.Builder().setContentType(C.AUDIO_CONTENT_TYPE_MOVIE).build(),
        !isMixMode);
  }

  void play() {
    SwitchOperation operation = activeOperation;
    if (operation != null) {
      operation.desiredPlayWhenReady = true;
      diagnostic(operation, "desiredPlayWhenReady", true);
    }
    exoPlayer.play();
  }

  void pause() {
    SwitchOperation operation = activeOperation;
    if (operation != null) {
      operation.desiredPlayWhenReady = false;
      diagnostic(operation, "desiredPlayWhenReady", false);
    }
    exoPlayer.pause();
  }

  void setLooping(boolean value) {
    exoPlayer.setRepeatMode(value ? REPEAT_MODE_ALL : REPEAT_MODE_OFF);
  }

  void setVolume(double value) {
    exoPlayer.setVolume((float) Math.max(0.0, Math.min(1.0, value)));
  }

  void setPlaybackSpeed(double value) {
    exoPlayer.setPlaybackParameters(new PlaybackParameters((float) value));
  }

  void seekTo(int location) {
    SwitchOperation operation = activeOperation;
    if (operation != null) {
      operation.desiredPositionMs = location;
      diagnostic(operation, "desiredPositionMs", location);
    }
    exoPlayer.seekTo(location);
  }

  long getPosition() {
    return exoPlayer.getCurrentPosition();
  }

  void dispose() {
    if (disposed) {
      return;
    }
    disposed = true;
    cancelOperation();
    surfaceAvailable = false;
    surfaceProducer.release();
    exoPlayer.release();
  }

  @VisibleForTesting
  @Nullable
  MediaSourceDescriptor getLastConfirmedSourceDescriptor() {
    return lastConfirmedSourceDescriptor;
  }

  @NonNull
  Map<String, Object> debugSnapshot(long textureId) {
    Map<String, Object> snapshot = new LinkedHashMap<>();
    snapshot.put("textureId", textureId);
    snapshot.put("playerIdentity", System.identityHashCode(exoPlayer));
    snapshot.put("activeOperation", activeOperation == null ? null : activeOperation.id);
    snapshot.put("disposed", disposed);
    snapshot.put("confirmedSource", label(lastConfirmedSourceDescriptor));
    snapshot.put("sourceGeneration", sourceGeneration);
    snapshot.put("replacementCount", replacementCount);
    snapshot.put("rollbackCount", rollbackCount);
    snapshot.put("acceptedFrameCount", acceptedFrameCount);
    snapshot.put("rejectedStaleFrameCount", rejectedStaleFrameCount);
    snapshot.put("surfaceAttached", surfaceAvailable);
    snapshot.put("surfaceLossCount", surfaceLossCount);
    snapshot.put("lastSurfaceAttachmentNanos", lastSurfaceAttachmentNanos);
    snapshot.put("operations", new ArrayList<>(operationHistory));
    return snapshot;
  }

  void clearDebugDiagnostics() {
    replacementCount = 0;
    rollbackCount = 0;
    acceptedFrameCount = 0;
    rejectedStaleFrameCount = 0;
    surfaceLossCount = 0;
    operationHistory.clear();
  }

  private static final class PlaybackSnapshot {
    final long positionMs;
    final boolean playWhenReady;
    final PlaybackParameters playbackParameters;
    final float volume;
    final int repeatMode;
    final boolean shuffleModeEnabled;

    static PlaybackSnapshot capture(ExoPlayer player) {
      return new PlaybackSnapshot(
          player.getCurrentPosition(),
          player.getPlayWhenReady(),
          player.getPlaybackParameters(),
          player.getVolume(),
          player.getRepeatMode(),
          player.getShuffleModeEnabled());
    }

    PlaybackSnapshot(
        long positionMs,
        boolean playWhenReady,
        PlaybackParameters playbackParameters,
        float volume,
        int repeatMode,
        boolean shuffleModeEnabled) {
      this.positionMs = positionMs;
      this.playWhenReady = playWhenReady;
      this.playbackParameters = playbackParameters;
      this.volume = volume;
      this.repeatMode = repeatMode;
      this.shuffleModeEnabled = shuffleModeEnabled;
    }

    void restoreSettings(ExoPlayer player) {
      player.setPlaybackParameters(playbackParameters);
      player.setVolume(volume);
      player.setRepeatMode(repeatMode);
      player.setShuffleModeEnabled(shuffleModeEnabled);
    }

    PlaybackSnapshot withDesired(long desiredPositionMs, boolean desiredPlayWhenReady) {
      return new PlaybackSnapshot(
          desiredPositionMs,
          desiredPlayWhenReady,
          playbackParameters,
          volume,
          repeatMode,
          shuffleModeEnabled);
    }
  }

  private static final class SwitchOperation {
    final String id;
    final MediaSourceDescriptor requested;
    final MediaSourceDescriptor previous;
    final PlaybackSnapshot snapshot;
    long desiredPositionMs;
    boolean desiredPlayWhenReady;
    long sourceGeneration;
    boolean ready;
    boolean rollback;
    @Nullable String failureReason;
    @Nullable Runnable timeout;
    long firstFrameRemainingMs;
    long firstFrameDeadlineMs;
    @Nullable Map<String, Object> diagnostics;

    SwitchOperation(
        String id,
        MediaSourceDescriptor requested,
        MediaSourceDescriptor previous,
        PlaybackSnapshot snapshot,
        long sourceGeneration) {
      this.id = id;
      this.requested = requested;
      this.previous = previous;
      this.snapshot = snapshot;
      this.desiredPositionMs = snapshot.positionMs;
      this.desiredPlayWhenReady = snapshot.playWhenReady;
      this.sourceGeneration = sourceGeneration;
    }

    String sourceId() {
      return "quality:" + sourceGeneration;
    }
  }
}
