// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

package io.flutter.plugins.videoplayer;

import android.content.Context;
import android.net.Uri;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.annotation.OptIn;
import androidx.annotation.VisibleForTesting;
import androidx.media3.common.util.UnstableApi;
import androidx.media3.database.StandaloneDatabaseProvider;
import androidx.media3.datasource.DataSource;
import androidx.media3.datasource.DataSpec;
import androidx.media3.datasource.FileDataSource;
import androidx.media3.datasource.TransferListener;
import androidx.media3.datasource.cache.CacheDataSink;
import androidx.media3.datasource.cache.CacheDataSource;
import androidx.media3.datasource.cache.LeastRecentlyUsedCacheEvictor;
import androidx.media3.datasource.cache.SimpleCache;
import java.io.File;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.Base64;
import java.util.ArrayList;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.atomic.AtomicInteger;

/** Process-wide owner for the single active Media3 byte cache. */
@OptIn(markerClass = UnstableApi.class)
final class MediaCacheManager {
  static final long MIN_BYTES = 1024L * 1024L;
  private static final MediaCacheManager INSTANCE = new MediaCacheManager();

  @Nullable private Generation current;
  @Nullable private Generation retired;
  @Nullable private Context context;
  @Nullable private Configuration lastConfiguration;
  private final AtomicInteger pendingConfigurations = new AtomicInteger();
  private long cacheReadBytes;
  private long upstreamReadBytes;
  private long cacheReadOperations;
  private long upstreamOpenOperations;
  private long generationSequence;
  private int cacheCreateCount;
  private int cacheReleaseCount;
  private int openCacheCount;

  static MediaCacheManager getInstance() {
    return INSTANCE;
  }

  private MediaCacheManager() {}

  @VisibleForTesting
  synchronized void resetForTests() {
    release(current);
    if (retired != current) {
      release(retired);
    }
    current = null;
    retired = null;
    context = null;
    lastConfiguration = null;
    pendingConfigurations.set(0);
    resetCounters();
    clearDebugDiagnostics();
  }

  void configure(Context value, long maxBytes, String directoryName) {
    pendingConfigurations.incrementAndGet();
    try {
      synchronized (this) {
        validate(maxBytes, directoryName);
        context = value.getApplicationContext();
        Configuration requested = new Configuration(maxBytes, directoryName);
        if (current != null && current.configuration.equals(requested)) {
          return;
        }
        if (retired != null && retired.leases != 0) {
          throw error("cache_configuration_in_use", "A disabled cache generation is still in use");
        }
        if (current != null && current.leases != 0) {
          throw error("cache_configuration_in_use", "The cache configuration is in use");
        }
        release(current);
        release(retired);
        retired = null;
        current = open(requested);
        lastConfiguration = requested;
        resetCounters();
      }
    } finally {
      pendingConfigurations.decrementAndGet();
    }
  }

  synchronized void disable() {
    if (current == null) {
      return;
    }
    if (current.leases == 0) {
      release(current);
    } else {
      current.enabled = false;
      retired = current;
    }
    current = null;
  }

  @Nullable
  Lease acquire(Context value) {
    if (pendingConfigurations.get() != 0) {
      throw error("cache_configuration_pending", "Cache configuration is pending");
    }
    synchronized (this) {
      context = value.getApplicationContext();
      if (pendingConfigurations.get() != 0) {
        throw error("cache_configuration_pending", "Cache configuration is pending");
      }
      if (current == null || !current.enabled) {
        return null;
      }
      current.leases++;
      return new Lease(this, current);
    }
  }

  synchronized Messages.CacheStatsMessage stats() {
    Generation generation = operationGeneration(false);
    try {
      long bytes = generation == null ? 0 : generation.cache.getCacheSpace();
      long resources = generation == null ? 0 : generation.cache.getKeys().size();
      long max = lastConfiguration == null ? 0 : lastConfiguration.maxBytes;
      return new Messages.CacheStatsMessage.Builder()
          .setEnabled(current != null && current.enabled)
          .setCurrentBytes(bytes)
          .setMaxBytes(max)
          .setCachedResources(resources)
          .setCacheReadBytes(cacheReadBytes)
          .setUpstreamReadBytes(upstreamReadBytes)
          .setCacheReadOperations(cacheReadOperations)
          .setUpstreamOpenOperations(upstreamOpenOperations)
          .build();
    } finally {
      releaseTemporary(generation);
    }
  }

  synchronized void clear() {
    Generation generation = operationGeneration(true);
    try {
      if (generation != null) {
        for (String key : generation.cache.getKeys()) {
          generation.cache.removeResource(key);
        }
      }
      resetCounters();
    } finally {
      releaseTemporary(generation);
    }
  }

  synchronized void removeVideo(String videoId) {
    Generation generation = operationGeneration(true);
    try {
      if (generation == null) {
        return;
      }
      for (String key : generation.cache.getKeys()) {
        if (videoId.equals(videoIdFromKey(key))) {
          generation.cache.removeResource(key);
        }
      }
    } finally {
      releaseTemporary(generation);
    }
  }

  private Generation operationGeneration(boolean mutation) {
    Generation generation = current != null ? current : retired;
    if (generation != null) {
      if (mutation && generation.leases != 0) {
        throw error("cache_in_use", "The cache is in use");
      }
      return generation;
    }
    if (lastConfiguration == null) {
      return null;
    }
    if (context == null) {
      throw new IllegalStateException("Cache context is unavailable");
    }
    Generation temporary = open(lastConfiguration);
    temporary.temporary = true;
    return temporary;
  }

  private void releaseTemporary(@Nullable Generation generation) {
    if (generation != null && generation.temporary) {
      release(generation);
    }
  }

  private Generation open(Configuration configuration) {
    File directory = new File(context.getCacheDir(), configuration.directoryName);
    if (SimpleCache.isCacheFolderLocked(directory)) {
      throw error("cache_directory_in_use", "Cache directory is already open");
    }
    StandaloneDatabaseProvider database = new StandaloneDatabaseProvider(context);
    try {
      SimpleCache cache =
          new SimpleCache(
              directory,
              new LeastRecentlyUsedCacheEvictor(configuration.maxBytes),
              database);
      cache.checkInitialization();
      cacheCreateCount++;
      openCacheCount++;
      return new Generation(++generationSequence, configuration, cache, database);
    } catch (RuntimeException | IOException exception) {
      database.close();
      throw exception instanceof RuntimeException
          ? (RuntimeException) exception
          : new IllegalStateException("Could not open media cache", exception);
    }
  }

  private void release(@Nullable Generation generation) {
    if (generation != null && !generation.released) {
      generation.released = true;
      generation.cache.release();
      generation.database.close();
      cacheReleaseCount++;
      openCacheCount--;
    }
  }

  private synchronized void releaseLease(Generation generation) {
    if (generation.leases == 0) {
      return;
    }
    generation.leases--;
    if (generation == retired && generation.leases == 0) {
      release(generation);
      retired = null;
    }
  }

  private synchronized void onCacheRead(long bytes, boolean firstForSource) {
    cacheReadBytes += bytes;
    if (firstForSource) {
      cacheReadOperations++;
    }
  }

  private synchronized void onUpstreamOpen() {
    upstreamOpenOperations++;
  }

  private synchronized void onUpstreamRead(int bytes) {
    upstreamReadBytes += bytes;
  }

  private void resetCounters() {
    cacheReadBytes = 0;
    upstreamReadBytes = 0;
    cacheReadOperations = 0;
    upstreamOpenOperations = 0;
  }

  synchronized Map<String, Object> debugSnapshot() {
    Map<String, Object> snapshot = new LinkedHashMap<>();
    snapshot.put("managerIdentity", System.identityHashCode(this));
    snapshot.put("pendingConfigurations", pendingConfigurations.get());
    snapshot.put("cacheCreateCount", cacheCreateCount);
    snapshot.put("cacheReleaseCount", cacheReleaseCount);
    snapshot.put("openCacheCount", openCacheCount);
    snapshot.put("currentGeneration", current == null ? null : current.id);
    snapshot.put("retiredGeneration", retired == null ? null : retired.id);
    snapshot.put("currentLeases", current == null ? 0 : current.leases);
    snapshot.put("retiredLeases", retired == null ? 0 : retired.leases);
    Generation generation = current != null ? current : retired;
    List<String> keys =
        generation == null ? new ArrayList<>() : new ArrayList<>(generation.cache.getKeys());
    Collections.sort(keys);
    snapshot.put("cacheKeys", keys);
    snapshot.put("cacheBytes", generation == null ? 0L : generation.cache.getCacheSpace());
    return snapshot;
  }

  synchronized void clearDebugDiagnostics() {
    cacheCreateCount = 0;
    cacheReleaseCount = 0;
  }

  private static void validate(long maxBytes, String directoryName) {
    if (maxBytes < MIN_BYTES) {
      throw new IllegalArgumentException("maxBytes must be at least 1 MiB");
    }
    if (!directoryName.matches("[A-Za-z0-9][A-Za-z0-9._-]*")
        || ".".equals(directoryName)
        || "..".equals(directoryName)) {
      throw new IllegalArgumentException("directoryName must be one safe relative name");
    }
  }

  @Nullable
  static String videoIdFromKey(String key) {
    String[] parts = key.split(":", -1);
    if (parts.length != 5
        || !"md-player".equals(parts[0])
        || !"youtube".equals(parts[1])
        || !("video".equals(parts[3])
            || "audio".equals(parts[3])
            || "muxed".equals(parts[3]))
        || !parts[4].matches("[0-9]+")) {
      return null;
    }
    try {
      byte[] decoded = Base64.getUrlDecoder().decode(parts[2]);
      if (!Base64.getUrlEncoder().withoutPadding().encodeToString(decoded).equals(parts[2])) {
        return null;
      }
      return new String(decoded, StandardCharsets.UTF_8);
    } catch (IllegalArgumentException exception) {
      return null;
    }
  }

  private static Messages.FlutterError error(String code, String message) {
    return new Messages.FlutterError(code, message, null);
  }

  static final class Lease implements AutoCloseable {
    private final MediaCacheManager owner;
    private final Generation generation;
    private boolean closed;

    Lease(MediaCacheManager owner, Generation generation) {
      this.owner = owner;
      this.generation = generation;
    }

    DataSource.Factory dataSourceFactory(DataSource.Factory upstreamFactory) {
      return () -> {
        CountingDataSource upstream = new CountingDataSource(upstreamFactory.createDataSource(), owner);
        final boolean[] servedCachedBytes = {false};
        return new CacheDataSource.Factory()
            .setCache(generation.cache)
            .setCacheReadDataSourceFactory(FileDataSource::new)
            .setCacheWriteDataSinkFactory(new CacheDataSink.Factory().setCache(generation.cache))
            .setUpstreamDataSourceFactory(() -> upstream)
            .setFlags(CacheDataSource.FLAG_IGNORE_CACHE_ON_ERROR)
            .setEventListener(
                new CacheDataSource.EventListener() {
                  @Override
                  public void onCachedBytesRead(long cacheSizeBytes, long cachedBytesRead) {
                    boolean first = !servedCachedBytes[0] && cachedBytesRead > 0;
                    servedCachedBytes[0] |= cachedBytesRead > 0;
                    owner.onCacheRead(cachedBytesRead, first);
                  }

                  @Override
                  public void onCacheIgnored(int reason) {}
                })
            .createDataSource();
      };
    }

    long generationId() {
      return generation.id;
    }

    @Override
    public void close() {
      synchronized (owner) {
        if (!closed) {
          closed = true;
          owner.releaseLease(generation);
        }
      }
    }
  }

  private static final class CountingDataSource implements DataSource {
    private final DataSource delegate;
    private final MediaCacheManager owner;

    CountingDataSource(DataSource delegate, MediaCacheManager owner) {
      this.delegate = delegate;
      this.owner = owner;
    }

    @Override
    public void addTransferListener(TransferListener listener) {
      delegate.addTransferListener(listener);
    }

    @Override
    public long open(DataSpec dataSpec) throws IOException {
      long result = delegate.open(dataSpec);
      owner.onUpstreamOpen();
      return result;
    }

    @Override
    public int read(byte[] buffer, int offset, int length) throws IOException {
      int result = delegate.read(buffer, offset, length);
      if (result > 0) {
        owner.onUpstreamRead(result);
      }
      return result;
    }

    @Nullable
    @Override
    public Uri getUri() {
      return delegate.getUri();
    }

    @Override
    public Map<String, List<String>> getResponseHeaders() {
      return delegate.getResponseHeaders();
    }

    @Override
    public void close() throws IOException {
      delegate.close();
    }
  }

  private static final class Configuration {
    final long maxBytes;
    final String directoryName;

    Configuration(long maxBytes, String directoryName) {
      this.maxBytes = maxBytes;
      this.directoryName = directoryName;
    }

    @Override
    public boolean equals(Object other) {
      if (!(other instanceof Configuration)) {
        return false;
      }
      Configuration value = (Configuration) other;
      return maxBytes == value.maxBytes && directoryName.equals(value.directoryName);
    }

    @Override
    public int hashCode() {
      return 31 * Long.hashCode(maxBytes) + directoryName.hashCode();
    }
  }

  private static final class Generation {
    final long id;
    final Configuration configuration;
    final SimpleCache cache;
    final StandaloneDatabaseProvider database;
    boolean enabled = true;
    boolean temporary;
    boolean released;
    int leases;

    Generation(
        long id,
        Configuration configuration,
        SimpleCache cache,
        StandaloneDatabaseProvider database) {
      this.id = id;
      this.configuration = configuration;
      this.cache = cache;
      this.database = database;
    }
  }
}
