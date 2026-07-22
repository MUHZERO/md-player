// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

package io.flutter.plugins.videoplayer;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertThrows;
import static org.junit.Assert.assertTrue;

import android.content.Context;
import androidx.test.core.app.ApplicationProvider;
import androidx.media3.datasource.ByteArrayDataSource;
import androidx.media3.datasource.DataSource;
import androidx.media3.datasource.DataSpec;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.Base64;
import java.util.Map;
import org.junit.After;
import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;

@RunWith(RobolectricTestRunner.class)
public final class MediaCacheManagerTest {
  private final MediaCacheManager manager = MediaCacheManager.getInstance();
  private Context context;

  @Before
  public void setUp() {
    context = ApplicationProvider.getApplicationContext();
    manager.resetForTests();
  }

  @After
  public void tearDown() {
    manager.resetForTests();
  }

  @Test
  public void leaseBlocksConflictingConfigurationAndMutationUntilReleased() {
    manager.configure(context, MediaCacheManager.MIN_BYTES, "cache-one");
    MediaCacheManager.Lease lease = manager.acquire(context);
    assertNotNull(lease);

    Messages.FlutterError configurationError =
        assertThrows(
            Messages.FlutterError.class,
            () -> manager.configure(context, MediaCacheManager.MIN_BYTES * 2, "cache-two"));
    assertEquals("cache_configuration_in_use", configurationError.code);
    Messages.FlutterError mutationError =
        assertThrows(Messages.FlutterError.class, manager::clear);
    assertEquals("cache_in_use", mutationError.code);

    manager.disable();
    assertNull(manager.acquire(context));
    lease.close();
    manager.configure(context, MediaCacheManager.MIN_BYTES * 2, "cache-two");
    assertTrue(manager.stats().getEnabled());
    assertEquals(MediaCacheManager.MIN_BYTES * 2, manager.stats().getMaxBytes().longValue());
  }

  @Test
  public void equivalentConfigurationIsIdempotentAndDisableKeepsFilesAvailable() {
    manager.configure(context, MediaCacheManager.MIN_BYTES, "cache-idempotent");
    manager.configure(context, MediaCacheManager.MIN_BYTES, "cache-idempotent");
    manager.disable();

    Messages.CacheStatsMessage stats = manager.stats();
    assertFalse(stats.getEnabled());
    assertEquals(MediaCacheManager.MIN_BYTES, stats.getMaxBytes().longValue());
    manager.clear();
  }

  @Test
  public void youtubeKeyParserUsesExactNamespaceSegments() {
    String encoded =
        Base64.getUrlEncoder()
            .withoutPadding()
            .encodeToString("abc".getBytes(StandardCharsets.UTF_8));
    assertEquals("abc", MediaCacheManager.videoIdFromKey("md-player:youtube:" + encoded + ":video:137"));
    assertNull(MediaCacheManager.videoIdFromKey("md-player:youtube:" + encoded + ":video:137:extra"));
    assertNull(MediaCacheManager.videoIdFromKey("md-player:youtube:" + encoded + ":other:137"));
    assertNull(MediaCacheManager.videoIdFromKey("xmd-player:youtube:" + encoded + ":video:137"));
    assertNull(MediaCacheManager.videoIdFromKey("md-player:youtube:" + encoded + ":video:x"));
  }

  @Test
  public void coldAndWarmReadsReportExactByteAndOperationCounters() throws IOException {
    manager.configure(context, MediaCacheManager.MIN_BYTES, "cache-counters");
    MediaCacheManager.Lease lease = manager.acquire(context);
    assertNotNull(lease);
    byte[] fixture = new byte[4096];
    String encodedVideoId =
        Base64.getUrlEncoder()
            .withoutPadding()
            .encodeToString("abc".getBytes(StandardCharsets.UTF_8));
    String cacheKey = "md-player:youtube:" + encodedVideoId + ":muxed:22";
    DataSource.Factory factory =
        lease.dataSourceFactory(() -> new ByteArrayDataSource(fixture));
    DataSpec spec =
        new DataSpec.Builder()
            .setUri("https://example.test/video.mp4?signature=one")
            .setKey(cacheKey)
            .setLength(fixture.length)
            .build();

    readFully(factory.createDataSource(), spec);
    readFully(factory.createDataSource(), spec.withUri(android.net.Uri.parse(
        "https://example.test/video.mp4?signature=two")));

    Messages.CacheStatsMessage stats = manager.stats();
    assertEquals(fixture.length, stats.getUpstreamReadBytes().longValue());
    assertEquals(1, stats.getUpstreamOpenOperations().longValue());
    assertEquals(fixture.length, stats.getCacheReadBytes().longValue());
    assertEquals(1, stats.getCacheReadOperations().longValue());
    assertEquals(1, stats.getCachedResources().longValue());
    lease.close();
    manager.removeVideo("abc");
    assertEquals(0, manager.stats().getCachedResources().longValue());
  }

  @Test
  public void debugSnapshotTracksOneGenerationAndLeaseLifecycle() {
    manager.configure(context, MediaCacheManager.MIN_BYTES, "cache-debug");
    Map<String, Object> configured = manager.debugSnapshot();
    assertEquals(1, configured.get("openCacheCount"));
    assertEquals(1, configured.get("cacheCreateCount"));
    assertNotNull(configured.get("currentGeneration"));

    MediaCacheManager.Lease lease = manager.acquire(context);
    assertNotNull(lease);
    assertEquals(1, manager.debugSnapshot().get("currentLeases"));
    manager.disable();
    assertEquals(1, manager.debugSnapshot().get("retiredLeases"));
    lease.close();
    assertEquals(0, manager.debugSnapshot().get("openCacheCount"));
    assertEquals(1, manager.debugSnapshot().get("cacheReleaseCount"));
  }

  private static void readFully(DataSource source, DataSpec spec) throws IOException {
    byte[] buffer = new byte[1024];
    source.open(spec);
    try {
      while (source.read(buffer, 0, buffer.length) != -1) {}
    } finally {
      source.close();
    }
  }
}
