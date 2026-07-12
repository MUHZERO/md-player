// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

package io.flutter.plugins.videoplayer;

import static androidx.media3.common.Player.REPEAT_MODE_ALL;
import static androidx.media3.common.Player.REPEAT_MODE_OFF;

import android.content.Context;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.annotation.RestrictTo;
import androidx.annotation.VisibleForTesting;
import androidx.media3.common.AudioAttributes;
import androidx.media3.common.C;
import androidx.media3.common.MediaItem;
import androidx.media3.common.PlaybackParameters;
import androidx.media3.exoplayer.ExoPlayer;
import androidx.media3.exoplayer.source.MediaSource;
import androidx.media3.exoplayer.source.MergingMediaSource;

import io.flutter.view.TextureRegistry;

final class VideoPlayer implements TextureRegistry.SurfaceProducer.Callback {
  @NonNull private final Context context;
  @NonNull private final ExoPlayerProvider exoPlayerProvider;
  @NonNull private VideoAsset videoAsset;
  @Nullable private final VideoAsset audioAsset;

  @NonNull private final TextureRegistry.SurfaceProducer surfaceProducer;
  @NonNull private final VideoPlayerCallbacks videoPlayerEvents;
  @NonNull private final VideoPlayerOptions options;
  @NonNull private ExoPlayer exoPlayer;
  @Nullable private ExoPlayerState savedStateDuring;

  /**
   * Creates a video player.
   *
   * @param context application context.
   * @param events event callbacks.
   * @param surfaceProducer produces a texture to render to.
   * @param asset asset to play.
   * @param options options for playback.
   * @return a video player instance.
   */
  @NonNull
  static VideoPlayer create(
      @NonNull Context context,
      @NonNull VideoPlayerCallbacks events,
      @NonNull TextureRegistry.SurfaceProducer surfaceProducer,
      @NonNull VideoAsset asset,
      @Nullable VideoAsset audio,
      @NonNull VideoPlayerOptions options) {
    return new VideoPlayer(
        () -> {
          ExoPlayer.Builder builder =
              new ExoPlayer.Builder(context)
                  .setMediaSourceFactory(asset.getMediaSourceFactory(context));
          return builder.build();
        },
        context,
        events,
        surfaceProducer,
        asset,
        audio,
        options);
  }

  public void updateVideoAsset(VideoAsset newVideoAsset) {
    long currentPosition = this.getPosition();
    boolean playWhenReady = this.exoPlayer.getPlayWhenReady();
    this.videoAsset = newVideoAsset;
    this.exoPlayer.stop();
    setMediaSource(this.exoPlayer);
    this.exoPlayer.prepare();
    this.exoPlayer.seekTo(currentPosition);
    this.exoPlayer.setPlayWhenReady(playWhenReady);
  }

  public boolean isPlaying() {
    return this.exoPlayer.isPlaying();
  }

  /** A closure-compatible signature since {@link java.util.function.Supplier} is API level 24. */
  interface ExoPlayerProvider {
    /**
     * Returns a new {@link ExoPlayer}.
     *
     * @return new instance.
     */
    ExoPlayer get();
  }

  @VisibleForTesting
  VideoPlayer(
      @NonNull ExoPlayerProvider exoPlayerProvider,
      @NonNull Context context,
      @NonNull VideoPlayerCallbacks events,
      @NonNull TextureRegistry.SurfaceProducer surfaceProducer,
      @NonNull VideoAsset videoAsset,
      @Nullable VideoAsset audioAsset,
      @NonNull VideoPlayerOptions options) {
    this.context = context;
    this.exoPlayerProvider = exoPlayerProvider;
    this.videoPlayerEvents = events;
    this.surfaceProducer = surfaceProducer;
    this.videoAsset = videoAsset;
    this.audioAsset = audioAsset;
    this.options = options;
    this.exoPlayer = createVideoPlayer();
    surfaceProducer.setCallback(this);
  }

  @RestrictTo(RestrictTo.Scope.LIBRARY)
  public void onSurfaceCreated() {
    exoPlayer = createVideoPlayer();
    if (savedStateDuring != null) {
      savedStateDuring.restore(exoPlayer);
      savedStateDuring = null;
    }
  }

  @RestrictTo(RestrictTo.Scope.LIBRARY)
  public void onSurfaceDestroyed() {
    exoPlayer.stop();
    savedStateDuring = ExoPlayerState.save(exoPlayer);
    exoPlayer.release();
  }

  private ExoPlayer createVideoPlayer() {
    ExoPlayer exoPlayer = exoPlayerProvider.get();
    setMediaSource(exoPlayer);
    exoPlayer.prepare();
    exoPlayer.setVideoSurface(surfaceProducer.getSurface());
    exoPlayer.addListener(new ExoPlayerEventListener(exoPlayer, videoPlayerEvents));
    setAudioAttributes(exoPlayer, options.mixWithOthers);

    return exoPlayer;
  }

  private void setMediaSource(ExoPlayer exoPlayer) {
    if (audioAsset == null) {
      exoPlayer.setMediaItem(videoAsset.getMediaItem());
      return;
    }
    MediaSource videoSource =
        videoAsset.getMediaSourceFactory(context).createMediaSource(videoAsset.getMediaItem());
    MediaSource audioSource =
        audioAsset.getMediaSourceFactory(context).createMediaSource(audioAsset.getMediaItem());
    exoPlayer.setMediaSource(new MergingMediaSource(videoSource, audioSource));
  }

  void sendBufferingUpdate() {
    videoPlayerEvents.onBufferingUpdate(exoPlayer.getBufferedPosition());
  }

  private static void setAudioAttributes(ExoPlayer exoPlayer, boolean isMixMode) {
    exoPlayer.setAudioAttributes(
        new AudioAttributes.Builder().setContentType(C.AUDIO_CONTENT_TYPE_MOVIE).build(),
        !isMixMode);
  }

  void play() {
    exoPlayer.play();
  }

  void playWhenReady() {
    exoPlayer.setPlayWhenReady(true);
  }

  void pause() {
    exoPlayer.pause();
  }

  void setLooping(boolean value) {
    exoPlayer.setRepeatMode(value ? REPEAT_MODE_ALL : REPEAT_MODE_OFF);
  }

  void setVolume(double value) {
    float bracketedValue = (float) Math.max(0.0, Math.min(1.0, value));
    exoPlayer.setVolume(bracketedValue);
  }

  void setPlaybackSpeed(double value) {
    // We do not need to consider pitch and skipSilence for now as we do not handle them and
    // therefore never diverge from the default values.
    final PlaybackParameters playbackParameters = new PlaybackParameters(((float) value));

    exoPlayer.setPlaybackParameters(playbackParameters);
  }

  void seekTo(int location) {
    exoPlayer.seekTo(location);
  }

  long getPosition() {
    return exoPlayer.getCurrentPosition();
  }

  void dispose() {
    surfaceProducer.release();
    exoPlayer.release();
  }
}
