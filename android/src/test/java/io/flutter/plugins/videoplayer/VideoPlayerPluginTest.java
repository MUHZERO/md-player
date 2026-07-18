// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

package io.flutter.plugins.videoplayer;

import static org.junit.Assert.assertEquals;

import io.flutter.plugins.videoplayer.Messages.PositionMessage;
import io.flutter.plugins.videoplayer.Messages.TextureMessage;
import org.junit.Test;

public class VideoPlayerPluginTest {
  // This is only a placeholder test and doesn't actually initialize the plugin.
  @Test
  public void initPluginDoesNotThrow() {
    final VideoPlayerPlugin plugin = new VideoPlayerPlugin();
  }

  @Test
  public void missingPlayerCommandsDoNotThrow() {
    final VideoPlayerPlugin plugin = new VideoPlayerPlugin();
    final TextureMessage texture = new TextureMessage.Builder().setTextureId(404L).build();

    plugin.dispose(texture);
    plugin.play(texture);
    plugin.pause(texture);

    final PositionMessage position = plugin.position(texture);

    assertEquals(404L, position.getTextureId().longValue());
    assertEquals(0L, position.getPosition().longValue());
  }

  @Test
  public void emptyDiagnosticsSnapshotHasStableCounters() {
    final VideoPlayerPlugin plugin = new VideoPlayerPlugin();

    assertEquals(0, plugin.debugSnapshot().get("playerCreateCount"));
    assertEquals(0, plugin.debugSnapshot().get("playerDisposeCount"));
  }
}
