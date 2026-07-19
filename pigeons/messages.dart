// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// ignore_for_file: deprecated_member_use

import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(PigeonOptions(
  dartOut: 'lib/src/messages.g.dart',
  dartTestOut: 'test/test_api.g.dart',
  javaOut: 'android/src/main/java/io/flutter/plugins/videoplayer/Messages.java',
  javaOptions: JavaOptions(
    package: 'io.flutter.plugins.videoplayer',
  ),
  copyrightHeader: 'pigeons/copyright.txt',
))
class TextureMessage {
  TextureMessage(this.textureId);
  int textureId;
}

class LoopingMessage {
  LoopingMessage(this.textureId, this.isLooping);
  int textureId;
  bool isLooping;
}

class VolumeMessage {
  VolumeMessage(this.textureId, this.volume);
  int textureId;
  double volume;
}

class PlaybackSpeedMessage {
  PlaybackSpeedMessage(this.textureId, this.speed);
  int textureId;
  double speed;
}

class PositionMessage {
  PositionMessage(this.textureId, this.position);
  int textureId;
  int position;
}

class ChangeQualityMessage {
  ChangeQualityMessage({required this.textureId, required this.newUrl});
  int textureId;
  // Retained for source compatibility. New callers also set videoUri.
  String newUrl;
  String? operationId;
  String? videoUri;
  String? audioUri;
  Map<String?, String?>? httpHeaders;
  Map<String?, String?>? audioHttpHeaders;
  String? videoFormatHint;
  String? audioFormatHint;
  String? videoCacheKey;
  String? audioCacheKey;
  String? videoStreamIdentity;
  String? audioStreamIdentity;
  int? videoItag;
  int? audioItag;
  String? videoRole;
  String? audioRole;
  String? requestedLabel;
}

class CreateMessage {
  CreateMessage({required this.httpHeaders});
  String? asset;
  String? uri;
  String? audioUri;
  String? packageName;
  String? formatHint;
  Map<String?, String?> httpHeaders;
  Map<String?, String?>? audioHttpHeaders;
  String? audioFormatHint;
  String? videoCacheKey;
  String? audioCacheKey;
  String? videoStreamIdentity;
  String? audioStreamIdentity;
  int? videoItag;
  int? audioItag;
  String? videoRole;
  String? audioRole;
}

class CacheConfigurationMessage {
  CacheConfigurationMessage(
      {required this.maxBytes, required this.directoryName});
  int maxBytes;
  String directoryName;
}

class CacheStatsMessage {
  CacheStatsMessage({
    required this.enabled,
    required this.currentBytes,
    required this.maxBytes,
    required this.cachedResources,
    required this.cacheReadBytes,
    required this.upstreamReadBytes,
    required this.cacheReadOperations,
    required this.upstreamOpenOperations,
  });
  bool enabled;
  int currentBytes;
  int maxBytes;
  int cachedResources;
  int cacheReadBytes;
  int upstreamReadBytes;
  int cacheReadOperations;
  int upstreamOpenOperations;
}

class MixWithOthersMessage {
  MixWithOthersMessage(this.mixWithOthers);
  bool mixWithOthers;
}

@HostApi(dartHostTestHandler: 'TestHostVideoPlayerApi')
abstract class AndroidVideoPlayerApi {
  void initialize();
  TextureMessage create(CreateMessage msg);
  void dispose(TextureMessage msg);
  void setLooping(LoopingMessage msg);
  void setVolume(VolumeMessage msg);
  void setPlaybackSpeed(PlaybackSpeedMessage msg);
  void play(TextureMessage msg);
  void changeQuality(ChangeQualityMessage msg);
  PositionMessage position(TextureMessage msg);
  void seekTo(PositionMessage msg);
  void pause(TextureMessage msg);
  void setMixWithOthers(MixWithOthersMessage msg);
  @TaskQueue(type: TaskQueueType.serialBackgroundThread)
  void configureCache(CacheConfigurationMessage msg);
  @TaskQueue(type: TaskQueueType.serialBackgroundThread)
  void disableCache();
  @TaskQueue(type: TaskQueueType.serialBackgroundThread)
  CacheStatsMessage cacheStats();
  @TaskQueue(type: TaskQueueType.serialBackgroundThread)
  void clearCache();
  @TaskQueue(type: TaskQueueType.serialBackgroundThread)
  void removeCachedVideo(String videoId);
}
