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
  @NonNull final Map<String, String> audioHttpHeaders;
  @Nullable final String videoFormatHint;
  @Nullable final String audioFormatHint;
  @Nullable final String videoCacheKey;
  @Nullable final String audioCacheKey;
  @Nullable final String videoStreamIdentity;
  @Nullable final String audioStreamIdentity;
  @Nullable final Long videoItag;
  @Nullable final Long audioItag;
  @Nullable final String videoRole;
  @Nullable final String audioRole;
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
    this(
        videoAsset,
        audioAsset,
        httpHeaders,
        null,
        videoFormatHint,
        audioFormatHint,
        videoCacheKey,
        audioCacheKey,
        videoStreamIdentity,
        audioStreamIdentity,
        videoItag,
        audioItag,
        null,
        null,
        qualityLabel);
  }

  MediaSourceDescriptor(
      @NonNull VideoAsset videoAsset,
      @Nullable VideoAsset audioAsset,
      @NonNull Map<String, String> httpHeaders,
      @Nullable Map<String, String> audioHttpHeaders,
      @Nullable String videoFormatHint,
      @Nullable String audioFormatHint,
      @Nullable String videoCacheKey,
      @Nullable String audioCacheKey,
      @Nullable String videoStreamIdentity,
      @Nullable String audioStreamIdentity,
      @Nullable Long videoItag,
      @Nullable Long audioItag,
      @Nullable String videoRole,
      @Nullable String audioRole,
      @Nullable String qualityLabel) {
    this.videoAsset = videoAsset;
    this.audioAsset = audioAsset;
    this.httpHeaders = Collections.unmodifiableMap(new HashMap<>(httpHeaders));
    this.audioHttpHeaders =
        Collections.unmodifiableMap(
            new HashMap<>(audioHttpHeaders == null ? httpHeaders : audioHttpHeaders));
    this.videoFormatHint = videoFormatHint;
    this.audioFormatHint = audioFormatHint;
    this.videoCacheKey = videoCacheKey;
    this.audioCacheKey = audioCacheKey;
    this.videoStreamIdentity = videoStreamIdentity;
    this.audioStreamIdentity = audioStreamIdentity;
    this.videoItag = videoItag;
    this.audioItag = audioItag;
    this.videoRole = videoRole;
    this.audioRole = audioRole;
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
  BuiltMediaSource build(
      @NonNull Context context,
      @NonNull String sourceId,
      @Nullable MediaCacheManager.Lease retainedLease) {
    MediaCacheManager.Lease lease = retainedLease;
    boolean acquired = false;
    if (lease == null && (isHttp(videoAsset) || isHttp(audioAsset))) {
      lease = MediaCacheManager.getInstance().acquire(context);
      acquired = lease != null;
    }
    try {
      MediaSource videoSource = buildAsset(context, videoAsset, sourceId, videoCacheKey, lease);
      MediaSource source =
          audioAsset == null
              ? videoSource
              : new MergingMediaSource(
                  videoSource,
                  buildAsset(context, audioAsset, sourceId + ":audio", audioCacheKey, lease));
      return new BuiltMediaSource(source, lease);
    } catch (RuntimeException exception) {
      if (acquired) {
        lease.close();
      }
      throw exception;
    }
  }

  private static MediaSource buildAsset(
      Context context,
      VideoAsset asset,
      String sourceId,
      @Nullable String cacheKey,
      @Nullable MediaCacheManager.Lease lease) {
    MediaItem.Builder item = asset.getMediaItem().buildUpon().setMediaId(sourceId);
    if (cacheKey != null) {
      item.setCustomCacheKey(cacheKey);
    }
    MediaSource.Factory factory;
    if (lease != null && asset instanceof HttpVideoAsset) {
      HttpVideoAsset http = (HttpVideoAsset) asset;
      factory =
          http.getMediaSourceFactory(
              context, lease.dataSourceFactory(http.createHttpDataSourceFactory()));
    } else {
      factory = asset.getMediaSourceFactory(context);
    }
    return factory.createMediaSource(item.build());
  }

  private static boolean isHttp(@Nullable VideoAsset asset) {
    return asset != null
        && asset.assetUrl != null
        && (asset.assetUrl.startsWith("http://") || asset.assetUrl.startsWith("https://"));
  }

  static final class BuiltMediaSource {
    @NonNull final MediaSource mediaSource;
    @Nullable final MediaCacheManager.Lease lease;

    BuiltMediaSource(
        @NonNull MediaSource mediaSource, @Nullable MediaCacheManager.Lease lease) {
      this.mediaSource = mediaSource;
      this.lease = lease;
    }
  }
}
