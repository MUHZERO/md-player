// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

package io.flutter.plugins.videoplayer;

import android.content.Context;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.media3.common.MediaItem;
import androidx.media3.exoplayer.source.MediaSource;
import androidx.media3.exoplayer.source.MergingMediaSource;
import java.util.Collections;
import java.util.HashMap;
import java.util.Map;

/** Immutable description of one muxed or separate-stream source. */
final class MediaSourceDescriptor {
  @NonNull final VideoAsset videoAsset;
  @Nullable final VideoAsset audioAsset;
  @NonNull final Map<String, String> httpHeaders;
  @Nullable final String videoFormatHint;
  @Nullable final String audioFormatHint;
  @Nullable final String videoCacheKey;
  @Nullable final String audioCacheKey;
  @Nullable final String videoStreamIdentity;
  @Nullable final String audioStreamIdentity;
  @Nullable final Long videoItag;
  @Nullable final Long audioItag;
  @Nullable final String qualityLabel;

  MediaSourceDescriptor(
      @NonNull VideoAsset videoAsset,
      @Nullable VideoAsset audioAsset,
      @NonNull Map<String, String> httpHeaders,
      @Nullable String videoFormatHint,
      @Nullable String audioFormatHint,
      @Nullable String videoCacheKey,
      @Nullable String audioCacheKey,
      @Nullable String videoStreamIdentity,
      @Nullable String audioStreamIdentity,
      @Nullable Long videoItag,
      @Nullable Long audioItag,
      @Nullable String qualityLabel) {
    this.videoAsset = videoAsset;
    this.audioAsset = audioAsset;
    this.httpHeaders = Collections.unmodifiableMap(new HashMap<>(httpHeaders));
    this.videoFormatHint = videoFormatHint;
    this.audioFormatHint = audioFormatHint;
    this.videoCacheKey = videoCacheKey;
    this.audioCacheKey = audioCacheKey;
    this.videoStreamIdentity = videoStreamIdentity;
    this.audioStreamIdentity = audioStreamIdentity;
    this.videoItag = videoItag;
    this.audioItag = audioItag;
    this.qualityLabel = qualityLabel;
  }

  static MediaSourceDescriptor legacy(
      @NonNull VideoAsset videoAsset, @Nullable VideoAsset audioAsset) {
    return new MediaSourceDescriptor(
        videoAsset,
        audioAsset,
        Collections.emptyMap(),
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null);
  }

  @NonNull
  MediaSource build(@NonNull Context context, @NonNull String sourceId) {
    MediaSource videoSource = buildAsset(context, videoAsset, sourceId);
    if (audioAsset == null) {
      return videoSource;
    }
    return new MergingMediaSource(
        videoSource, buildAsset(context, audioAsset, sourceId + ":audio"));
  }

  private static MediaSource buildAsset(
      Context context, VideoAsset asset, String sourceId) {
    MediaItem mediaItem = asset.getMediaItem().buildUpon().setMediaId(sourceId).build();
    return asset.getMediaSourceFactory(context).createMediaSource(mediaItem);
  }
}
