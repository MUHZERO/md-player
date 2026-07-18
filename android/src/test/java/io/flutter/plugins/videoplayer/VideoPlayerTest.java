// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

package io.flutter.plugins.videoplayer;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertSame;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;
import static org.robolectric.Shadows.shadowOf;

import android.view.Surface;
import android.os.Looper;
import androidx.media3.common.AudioAttributes;
import androidx.media3.common.C;
import androidx.media3.common.MediaItem;
import androidx.media3.common.PlaybackParameters;
import androidx.media3.common.Player;
import androidx.media3.common.Tracks;
import androidx.media3.exoplayer.ExoPlayer;
import androidx.media3.exoplayer.source.MediaSource;
import androidx.test.core.app.ApplicationProvider;
import io.flutter.view.TextureRegistry;
import org.junit.Before;
import org.junit.Rule;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Captor;
import org.mockito.Mock;
import org.mockito.junit.MockitoJUnit;
import org.mockito.junit.MockitoRule;
import org.robolectric.RobolectricTestRunner;
import java.time.Duration;
import java.util.Collections;
import java.util.Map;

/**
 * Unit tests for {@link VideoPlayer}.
 *
 * <p>This test suite <em>narrowly verifies</em> that {@link VideoPlayer} interfaces with the {@link
 * ExoPlayer} interface <em>exactly</em> as it did when the test suite was created. That is, if the
 * behavior changes, this test will need to change. However, this suite should catch bugs related to
 * <em>"this is a safe refactor with no behavior changes"</em>.
 *
 * <p>It's hypothetically possible to write better tests using {@link
 * androidx.media3.test.utils.FakeMediaSource}, but you really need a PhD in the Android media APIs
 * in order to figure out how to set everything up so the player "works".
 */
@RunWith(RobolectricTestRunner.class)
@SuppressWarnings("unchecked")
public final class VideoPlayerTest {
  private static final String FAKE_ASSET_URL = "https://flutter.dev/movie.mp4";
  private FakeVideoAsset fakeVideoAsset;

  @Mock private VideoPlayerCallbacks mockEvents;
  @Mock private TextureRegistry.SurfaceProducer mockProducer;
  @Mock private ExoPlayer mockExoPlayer;
  @Captor private ArgumentCaptor<AudioAttributes> attributesCaptor;
  @Captor private ArgumentCaptor<TextureRegistry.SurfaceProducer.Callback> callbackCaptor;

  @Rule public MockitoRule initRule = MockitoJUnit.rule();

  @Before
  public void setUp() {
    fakeVideoAsset = new FakeVideoAsset(FAKE_ASSET_URL);
    Surface surface = mock(Surface.class);
    when(surface.isValid()).thenReturn(true);
    when(mockProducer.getSurface()).thenReturn(surface);
    when(mockExoPlayer.getPlaybackParameters()).thenReturn(PlaybackParameters.DEFAULT);
    when(mockExoPlayer.getCurrentTracks()).thenReturn(Tracks.EMPTY);
  }

  private VideoPlayer createVideoPlayer() {
    return createVideoPlayer(new VideoPlayerOptions());
  }

  private VideoPlayer createVideoPlayer(VideoPlayerOptions options) {
    return new VideoPlayer(
        () -> mockExoPlayer,
        ApplicationProvider.getApplicationContext(),
        mockEvents,
        mockProducer,
        fakeVideoAsset,
        null,
        options);
  }

  private VideoPlayer createVideoPlayerWithAudio() {
    return new VideoPlayer(
        () -> mockExoPlayer,
        ApplicationProvider.getApplicationContext(),
        mockEvents,
        mockProducer,
        fakeVideoAsset,
        new FakeVideoAsset("https://flutter.dev/audio.mp4"),
        new VideoPlayerOptions());
  }

  @Test
  public void loadsAndPreparesProvidedMediaEnablesAudioFocusByDefault() {
    VideoPlayer videoPlayer = createVideoPlayer();

    verify(mockExoPlayer).setMediaSource(any(MediaSource.class), eq(0L));
    verify(mockExoPlayer).prepare();
    verify(mockProducer).getSurface();
    verify(mockExoPlayer).setVideoSurface(any());

    verify(mockExoPlayer).setAudioAttributes(attributesCaptor.capture(), eq(true));
    assertEquals(attributesCaptor.getValue().contentType, C.AUDIO_CONTENT_TYPE_MOVIE);

    videoPlayer.dispose();
  }

  @Test
  public void loadsAndPreparesMergedMediaWhenAudioProvided() {
    VideoPlayer videoPlayer = createVideoPlayerWithAudio();

    verify(mockExoPlayer).setMediaSource(any(MediaSource.class), eq(0L));
    verify(mockExoPlayer, never()).setMediaItem(any(MediaItem.class));
    verify(mockExoPlayer).prepare();

    videoPlayer.dispose();
  }

  @Test
  public void loadsAndPreparesProvidedMediaDisablesAudioFocusWhenMixModeSet() {
    VideoPlayerOptions options = new VideoPlayerOptions();
    options.mixWithOthers = true;

    VideoPlayer videoPlayer = createVideoPlayer(options);

    verify(mockExoPlayer).setAudioAttributes(attributesCaptor.capture(), eq(false));
    assertEquals(attributesCaptor.getValue().contentType, C.AUDIO_CONTENT_TYPE_MOVIE);

    videoPlayer.dispose();
  }

  @Test
  public void playsAndPausesProvidedMedia() {
    VideoPlayer videoPlayer = createVideoPlayer();

    videoPlayer.play();
    verify(mockExoPlayer).play();

    videoPlayer.pause();
    verify(mockExoPlayer).pause();

    videoPlayer.dispose();
  }

  @Test
  public void sendsBufferingUpdatesOnDemand() {
    VideoPlayer videoPlayer = createVideoPlayer();

    when(mockExoPlayer.getBufferedPosition()).thenReturn(10L);
    videoPlayer.sendBufferingUpdate();
    verify(mockEvents).onBufferingUpdate(10L);

    videoPlayer.dispose();
  }

  @Test
  public void togglesLoopingEnablesAndDisablesRepeatMode() {
    VideoPlayer videoPlayer = createVideoPlayer();

    videoPlayer.setLooping(true);
    verify(mockExoPlayer).setRepeatMode(Player.REPEAT_MODE_ALL);

    videoPlayer.setLooping(false);
    verify(mockExoPlayer).setRepeatMode(Player.REPEAT_MODE_OFF);

    videoPlayer.dispose();
  }

  @Test
  public void setVolumeIsClampedBetween0and1() {
    VideoPlayer videoPlayer = createVideoPlayer();

    videoPlayer.setVolume(-1.0);
    verify(mockExoPlayer).setVolume(0f);

    videoPlayer.setVolume(2.0);
    verify(mockExoPlayer).setVolume(1f);

    videoPlayer.setVolume(0.5);
    verify(mockExoPlayer).setVolume(0.5f);

    videoPlayer.dispose();
  }

  @Test
  public void setPlaybackSpeedSetsPlaybackParametersWithValue() {
    VideoPlayer videoPlayer = createVideoPlayer();

    videoPlayer.setPlaybackSpeed(2.5);
    verify(mockExoPlayer).setPlaybackParameters(new PlaybackParameters(2.5f));

    videoPlayer.dispose();
  }

  @Test
  public void seekAndGetPosition() {
    VideoPlayer videoPlayer = createVideoPlayer();

    videoPlayer.seekTo(10);
    verify(mockExoPlayer).seekTo(10);

    when(mockExoPlayer.getCurrentPosition()).thenReturn(20L);
    assertEquals(20L, videoPlayer.getPosition());
  }

  @Test
  public void onSurfaceProducerDestroyedAndRecreatedKeepsTheSamePlayer() {
    VideoPlayer videoPlayer = createVideoPlayer();

    verify(mockProducer).setCallback(callbackCaptor.capture());
    verify(mockExoPlayer, never()).release();

    TextureRegistry.SurfaceProducer.Callback producerLifecycle = callbackCaptor.getValue();
    producerLifecycle.onSurfaceCleanup();

    verify(mockExoPlayer).clearVideoSurface();
    verify(mockExoPlayer, never()).release();
    producerLifecycle.onSurfaceAvailable();

    verify(mockExoPlayer, times(2)).setVideoSurface(any());
    verify(mockExoPlayer, never()).seekTo(anyLong());

    videoPlayer.dispose();
  }

  @Test
  public void disposeReleasesTextureAndPlayer() {
    VideoPlayer videoPlayer = createVideoPlayer();
    videoPlayer.dispose();

    verify(mockProducer).release();
    verify(mockExoPlayer).release();
  }

  private MediaSourceDescriptor descriptor(String label, boolean withAudio) {
    return new MediaSourceDescriptor(
        new FakeVideoAsset("https://flutter.dev/" + label + ".mp4"),
        withAudio ? new FakeVideoAsset("https://flutter.dev/audio.mp4") : null,
        Collections.singletonMap("Authorization", "token"),
        "dash",
        "other",
        "video-cache",
        "audio-cache",
        "video-stream",
        "audio-stream",
        22L,
        140L,
        label);
  }

  @Test
  public void qualitySwitchUsesSamePlayerAndCompletesAudioOnlyAtReady() {
    when(mockExoPlayer.getCurrentPosition()).thenReturn(42L);
    when(mockExoPlayer.getPlayWhenReady()).thenReturn(true);
    VideoPlayer videoPlayer = createVideoPlayer();
    MediaSourceDescriptor requested = descriptor("720p", true);

    videoPlayer.changeQuality("operation-1", requested);

    verify(mockExoPlayer).setMediaSource(any(MediaSource.class), eq(42L));
    verify(mockExoPlayer, times(2)).prepare();
    verify(mockExoPlayer).setPlayWhenReady(true);
    verify(mockExoPlayer, never()).seekTo(42L);
    assertEquals("video-cache", requested.videoCacheKey);
    assertEquals("audio-stream", requested.audioStreamIdentity);

    videoPlayer.onReady();

    assertSame(requested, videoPlayer.getLastConfirmedSourceDescriptor());
    ArgumentCaptor<Map<String, Object>> events = ArgumentCaptor.forClass(Map.class);
    verify(mockEvents, times(3)).onQualitySwitch(events.capture());
    assertEquals("preparing", events.getAllValues().get(0).get("phase"));
    assertEquals("switching", events.getAllValues().get(1).get("phase"));
    assertEquals("completed", events.getAllValues().get(2).get("phase"));
  }

  @Test
  public void videoSwitchRequiresCurrentSourceFirstFrame() {
    Tracks.Group videoGroup = mock(Tracks.Group.class);
    when(videoGroup.getType()).thenReturn(C.TRACK_TYPE_VIDEO);
    when(videoGroup.isSelected()).thenReturn(true);
    when(mockExoPlayer.getCurrentTracks())
        .thenReturn(new Tracks(Collections.singletonList(videoGroup)));
    VideoPlayer videoPlayer = createVideoPlayer();
    MediaSourceDescriptor previous = videoPlayer.getLastConfirmedSourceDescriptor();
    MediaSourceDescriptor requested = descriptor("1080p", false);

    videoPlayer.changeQuality("operation-2", requested);
    videoPlayer.onReady();
    assertSame(previous, videoPlayer.getLastConfirmedSourceDescriptor());

    videoPlayer.onRenderedFirstFrameForSource("quality:0");
    assertSame(previous, videoPlayer.getLastConfirmedSourceDescriptor());
    videoPlayer.onRenderedFirstFrameForSource("quality:1");
    assertSame(requested, videoPlayer.getLastConfirmedSourceDescriptor());
  }

  @Test
  public void timeoutRollsBackConfirmedSourceUsingLatestCommands() {
    when(mockExoPlayer.getCurrentPosition()).thenReturn(7L);
    VideoPlayer videoPlayer = createVideoPlayer();
    MediaSourceDescriptor previous = videoPlayer.getLastConfirmedSourceDescriptor();
    videoPlayer.changeQuality("operation-3", descriptor("720p", false));
    videoPlayer.seekTo(99);
    videoPlayer.play();
    videoPlayer.pause();

    shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(15));

    verify(mockExoPlayer).setMediaSource(any(MediaSource.class), eq(99L));
    verify(mockExoPlayer, times(2)).setPlayWhenReady(false);
    assertSame(previous, videoPlayer.getLastConfirmedSourceDescriptor());
    videoPlayer.onReady();

    ArgumentCaptor<Map<String, Object>> events = ArgumentCaptor.forClass(Map.class);
    verify(mockEvents, atLeast(3)).onQualitySwitch(events.capture());
    Map<String, Object> terminal = events.getAllValues().get(events.getAllValues().size() - 1);
    assertEquals("failed", terminal.get("phase"));
    assertEquals(true, terminal.get("rollbackSucceeded"));
  }

  @Test
  public void surfaceLossSuspendsFirstFrameTimeoutAndDisposalCancelsIt() {
    Tracks.Group videoGroup = mock(Tracks.Group.class);
    when(videoGroup.getType()).thenReturn(C.TRACK_TYPE_VIDEO);
    when(videoGroup.isSelected()).thenReturn(true);
    when(mockExoPlayer.getCurrentTracks())
        .thenReturn(new Tracks(Collections.singletonList(videoGroup)));
    VideoPlayer videoPlayer = createVideoPlayer();
    verify(mockProducer).setCallback(callbackCaptor.capture());
    videoPlayer.changeQuality("operation-4", descriptor("720p", false));
    videoPlayer.onReady();

    callbackCaptor.getValue().onSurfaceCleanup();
    shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(9));
    verify(mockExoPlayer, never()).stop();
    callbackCaptor.getValue().onSurfaceAvailable();
    videoPlayer.onRenderedFirstFrameForSource("quality:1");
    assertEquals("720p", videoPlayer.getLastConfirmedSourceDescriptor().qualityLabel);

    callbackCaptor.getValue().onSurfaceCleanup();
    videoPlayer.dispose();
    shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(30));
  }

  @Test
  public void rapidSwitchKeepsDesiredPositionAndRejectsOldCompletion() {
    when(mockExoPlayer.getCurrentPosition()).thenReturn(5L);
    VideoPlayer videoPlayer = createVideoPlayer();
    MediaSourceDescriptor first = descriptor("720p", false);
    MediaSourceDescriptor second = descriptor("1080p", true);
    videoPlayer.changeQuality("first", first);
    videoPlayer.seekTo(88);

    videoPlayer.changeQuality("second", second);

    verify(mockExoPlayer).setMediaSource(any(MediaSource.class), eq(88L));
    videoPlayer.onRenderedFirstFrameForSource("quality:1");
    videoPlayer.onReady();
    assertSame(second, videoPlayer.getLastConfirmedSourceDescriptor());
  }

  @Test
  public void rollbackConstructionFailureLeavesDeterministicErrorState() {
    doNothing()
        .doNothing()
        .doThrow(new IllegalStateException("rollback failed"))
        .when(mockExoPlayer)
        .setMediaSource(any(MediaSource.class), anyLong());
    VideoPlayer videoPlayer = createVideoPlayer();
    videoPlayer.changeQuality("operation-5", descriptor("720p", false));

    shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(15));

    verify(mockExoPlayer).stop();
    ArgumentCaptor<Map<String, Object>> events = ArgumentCaptor.forClass(Map.class);
    verify(mockEvents, atLeast(3)).onQualitySwitch(events.capture());
    Map<String, Object> terminal = events.getAllValues().get(events.getAllValues().size() - 1);
    assertEquals("failed", terminal.get("phase"));
    assertEquals(false, terminal.get("rollbackSucceeded"));
    assertEquals(15_000, VideoPlayer.PREPARATION_TIMEOUT_MS);
    assertEquals(8_000, VideoPlayer.FIRST_FRAME_TIMEOUT_MS);
    assertEquals(15_000, VideoPlayer.ROLLBACK_TIMEOUT_MS);
  }
}
