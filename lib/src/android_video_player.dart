// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'messages.g.dart';
import 'md_player_cache.dart';

/// Native quality-switch progress reported on the player's event channel.
enum MdQualitySwitchPhase { preparing, switching, completed, failed }

@immutable
class MdQualitySwitchEvent {
  const MdQualitySwitchEvent({
    required this.operationId,
    required this.phase,
    this.requestedLabel,
    this.errorDescription,
    this.rollbackSucceeded,
  });

  final String operationId;
  final MdQualitySwitchPhase phase;
  final String? requestedLabel;
  final String? errorDescription;
  final bool? rollbackSucceeded;

  bool get isTerminal =>
      phase == MdQualitySwitchPhase.completed ||
      phase == MdQualitySwitchPhase.failed;
}

/// One typed projection of the shared per-texture native event stream.
@immutable
class MdPlayerPlatformEvent {
  const MdPlayerPlatformEvent.video(this.videoEvent) : qualityEvent = null;
  const MdPlayerPlatformEvent.quality(this.qualityEvent) : videoEvent = null;

  final VideoEvent? videoEvent;
  final MdQualitySwitchEvent? qualityEvent;
}

/// An Android implementation of [VideoPlayerPlatform] that uses the
/// Pigeon-generated [VideoPlayerApi].
class MdPlayerAndroid extends VideoPlayerPlatform {
  final AndroidVideoPlayerApi _api = AndroidVideoPlayerApi();
  final Map<int, Stream<Map<dynamic, dynamic>>> _rawEventStreams =
      <int, Stream<Map<dynamic, dynamic>>>{};

  /// Registers this class as the default instance of [VideoPlayerPlatform].
  static void registerWith() {
    VideoPlayerPlatform.instance = MdPlayerAndroid();
  }

  @override
  Future<void> init() {
    _rawEventStreams.clear();
    return _api.initialize();
  }

  @override
  Future<void> dispose(int textureId) async {
    try {
      await _api.dispose(TextureMessage(textureId: textureId));
    } finally {
      _rawEventStreams.remove(textureId);
    }
  }

  @override
  Future<int?> create(DataSource dataSource) async {
    await MdPlayerCache.waitForPendingConfiguration();
    String? asset;
    String? packageName;
    String? uri;
    String? formatHint;
    Map<String, String> httpHeaders = <String, String>{};

    switch (dataSource.sourceType) {
      case DataSourceType.asset:
        asset = dataSource.asset;
        packageName = dataSource.package;
        break;
      case DataSourceType.network:
        uri = dataSource.uri;
        formatHint = _videoFormatStringMap[dataSource.formatHint];
        httpHeaders = dataSource.httpHeaders;
        break;
      case DataSourceType.file:
        uri = dataSource.uri;
        httpHeaders = dataSource.httpHeaders;
        break;
      case DataSourceType.contentUri:
        uri = dataSource.uri;
        break;
    }

    final CreateMessage message = CreateMessage(
      asset: asset,
      packageName: packageName,
      uri: uri,
      httpHeaders: httpHeaders,
      formatHint: formatHint,
    );

    final TextureMessage response = await _api.create(message);
    return response.textureId;
  }

  /// Creates a network video player that syncs a video-only stream with a
  /// separate audio-only stream.
  Future<int?> createWithAudio({
    required String videoUri,
    required String audioUri,
    VideoFormat? formatHint,
    Map<String, String> httpHeaders = const <String, String>{},
    Map<String, String>? audioHttpHeaders,
  }) async {
    await MdPlayerCache.waitForPendingConfiguration();
    final TextureMessage response = await _api.create(CreateMessage(
      uri: videoUri,
      audioUri: audioUri,
      formatHint: _videoFormatStringMap[formatHint],
      httpHeaders: httpHeaders,
      audioHttpHeaders: audioHttpHeaders,
    ));
    return response.textureId;
  }

  Future<int?> createMdSource({
    required String videoUri,
    String? audioUri,
    VideoFormat? videoFormatHint,
    VideoFormat? audioFormatHint,
    Map<String, String> httpHeaders = const <String, String>{},
    Map<String, String>? audioHttpHeaders,
    String? videoCacheKey,
    String? audioCacheKey,
    String? videoStreamIdentity,
    String? audioStreamIdentity,
    int? videoItag,
    int? audioItag,
    String? videoRole,
    String? audioRole,
  }) async {
    await MdPlayerCache.waitForPendingConfiguration();
    final TextureMessage response = await _api.create(CreateMessage(
      uri: videoUri,
      audioUri: audioUri,
      formatHint: _videoFormatStringMap[videoFormatHint],
      audioFormatHint: _videoFormatStringMap[audioFormatHint],
      httpHeaders: Map<String, String>.of(httpHeaders),
      audioHttpHeaders: audioHttpHeaders == null
          ? null
          : Map<String, String>.of(audioHttpHeaders),
      videoCacheKey: videoCacheKey,
      audioCacheKey: audioCacheKey,
      videoStreamIdentity: videoStreamIdentity,
      audioStreamIdentity: audioStreamIdentity,
      videoItag: videoItag,
      audioItag: audioItag,
      videoRole: videoRole,
      audioRole: audioRole,
    ));
    return response.textureId;
  }

  @override
  Future<void> setLooping(int textureId, bool looping) {
    return _api.setLooping(LoopingMessage(
      textureId: textureId,
      isLooping: looping,
    ));
  }

  @override
  Future<void> play(int textureId) {
    return _api.play(TextureMessage(textureId: textureId));
  }

  @override
  Future<void> pause(int textureId) {
    return _api.pause(TextureMessage(textureId: textureId));
  }

  @override
  Future<void> setVolume(int textureId, double volume) {
    return _api.setVolume(VolumeMessage(
      textureId: textureId,
      volume: volume,
    ));
  }

  @override
  Future<void> setPlaybackSpeed(int textureId, double speed) {
    assert(speed > 0);

    return _api.setPlaybackSpeed(PlaybackSpeedMessage(
      textureId: textureId,
      speed: speed,
    ));
  }

  @override
  Future<void> seekTo(int textureId, Duration position) {
    return _api.seekTo(PositionMessage(
      textureId: textureId,
      position: position.inMilliseconds,
    ));
  }

  /// Starts a native quality switch and completes after native acceptance.
  ///
  /// Terminal success or failure is reported by [qualityEventsFor].
  Future<void> changeQuality(
    int textureId,
    String newQuality, {
    String? operationId,
    String? audioUri,
    Map<String, String> httpHeaders = const <String, String>{},
    Map<String, String>? audioHttpHeaders,
    VideoFormat? videoFormatHint,
    VideoFormat? audioFormatHint,
    String? videoCacheKey,
    String? audioCacheKey,
    String? videoStreamIdentity,
    String? audioStreamIdentity,
    int? videoItag,
    int? audioItag,
    String? videoRole,
    String? audioRole,
    String? requestedLabel,
  }) async {
    await MdPlayerCache.waitForPendingConfiguration();
    return _api.changeQuality(
      ChangeQualityMessage(
        textureId: textureId,
        newUrl: newQuality,
        operationId: operationId,
        videoUri: newQuality,
        audioUri: audioUri,
        httpHeaders: Map<String, String>.of(httpHeaders),
        audioHttpHeaders: audioHttpHeaders == null
            ? null
            : Map<String, String>.of(audioHttpHeaders),
        videoFormatHint: _videoFormatStringMap[videoFormatHint],
        audioFormatHint: _videoFormatStringMap[audioFormatHint],
        videoCacheKey: videoCacheKey,
        audioCacheKey: audioCacheKey,
        videoStreamIdentity: videoStreamIdentity,
        audioStreamIdentity: audioStreamIdentity,
        videoItag: videoItag,
        audioItag: audioItag,
        videoRole: videoRole,
        audioRole: audioRole,
        requestedLabel: requestedLabel,
      ),
    );
  }

  @override
  Future<Duration> getPosition(int textureId) async {
    final PositionMessage response =
        await _api.position(TextureMessage(textureId: textureId));
    return Duration(milliseconds: response.position);
  }

  @override
  Stream<VideoEvent> videoEventsFor(int textureId) {
    return playerEventsFor(textureId)
        .where((MdPlayerPlatformEvent event) => event.videoEvent != null)
        .map((MdPlayerPlatformEvent event) => event.videoEvent!);
  }

  Stream<MdQualitySwitchEvent> qualityEventsFor(int textureId) {
    return playerEventsFor(textureId)
        .where((MdPlayerPlatformEvent event) => event.qualityEvent != null)
        .map((MdPlayerPlatformEvent event) => event.qualityEvent!);
  }

  Stream<MdPlayerPlatformEvent> playerEventsFor(int textureId) {
    return _rawEventsFor(textureId).map((Map<dynamic, dynamic> map) {
      if (map['event'] == 'qualitySwitch') {
        return MdPlayerPlatformEvent.quality(_qualityEvent(map));
      }
      return MdPlayerPlatformEvent.video(_videoEvent(map));
    });
  }

  Stream<Map<dynamic, dynamic>> _rawEventsFor(int textureId) {
    return _rawEventStreams.putIfAbsent(
      textureId,
      () => _eventChannelFor(textureId)
          .receiveBroadcastStream()
          .map((dynamic event) => event as Map<dynamic, dynamic>)
          .asBroadcastStream(),
    );
  }

  VideoEvent _videoEvent(Map<dynamic, dynamic> map) {
    switch (map['event']) {
      case 'initialized':
        return VideoEvent(
          eventType: VideoEventType.initialized,
          duration: Duration(milliseconds: map['duration'] as int),
          size: Size((map['width'] as num?)?.toDouble() ?? 0.0,
              (map['height'] as num?)?.toDouble() ?? 0.0),
          rotationCorrection: map['rotationCorrection'] as int? ?? 0,
        );
      case 'completed':
        return VideoEvent(
          eventType: VideoEventType.completed,
        );
      case 'bufferingUpdate':
        final List<dynamic> values = map['values'] as List<dynamic>;

        return VideoEvent(
          buffered: values.map<DurationRange>(_toDurationRange).toList(),
          eventType: VideoEventType.bufferingUpdate,
        );
      case 'bufferingStart':
        return VideoEvent(eventType: VideoEventType.bufferingStart);
      case 'bufferingEnd':
        return VideoEvent(eventType: VideoEventType.bufferingEnd);
      case 'isPlayingStateUpdate':
        return VideoEvent(
          eventType: VideoEventType.isPlayingStateUpdate,
          isPlaying: map['isPlaying'] as bool,
        );
      default:
        return VideoEvent(eventType: VideoEventType.unknown);
    }
  }

  MdQualitySwitchEvent _qualityEvent(Map<dynamic, dynamic> map) {
    return MdQualitySwitchEvent(
      operationId: map['operationId'] as String,
      phase: MdQualitySwitchPhase.values.byName(map['phase'] as String),
      requestedLabel: map['requestedLabel'] as String?,
      errorDescription: map['errorDescription'] as String?,
      rollbackSucceeded: map['rollbackSucceeded'] as bool?,
    );
  }

  @override
  Widget buildView(int textureId) {
    return Texture(textureId: textureId);
  }

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) {
    return _api
        .setMixWithOthers(MixWithOthersMessage(mixWithOthers: mixWithOthers));
  }

  EventChannel _eventChannelFor(int textureId) {
    return EventChannel('flutter.io/videoPlayer/videoEvents$textureId');
  }

  static const Map<VideoFormat, String> _videoFormatStringMap =
      <VideoFormat, String>{
    VideoFormat.ss: 'ss',
    VideoFormat.hls: 'hls',
    VideoFormat.dash: 'dash',
    VideoFormat.other: 'other',
  };

  DurationRange _toDurationRange(dynamic value) {
    final List<dynamic> pair = value as List<dynamic>;
    return DurationRange(
      Duration(milliseconds: pair[0] as int),
      Duration(milliseconds: pair[1] as int),
    );
  }
}

typedef AndroidVideoPlayer = MdPlayerAndroid;
