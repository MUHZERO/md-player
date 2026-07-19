import 'dart:async';

import 'package:flutter/foundation.dart';

import 'messages.g.dart';

const int _minimumCacheBytes = 1024 * 1024;

@immutable
class MdPlayerCacheConfiguration {
  MdPlayerCacheConfiguration({
    required this.maxBytes,
    this.directoryName = 'md_player_media_cache',
  }) {
    if (maxBytes < _minimumCacheBytes) {
      throw ArgumentError.value(maxBytes, 'maxBytes', 'Must be at least 1 MiB');
    }
    if (!_safeDirectory.hasMatch(directoryName) ||
        directoryName == '.' ||
        directoryName == '..') {
      throw ArgumentError.value(
        directoryName,
        'directoryName',
        'Must be one safe relative directory name',
      );
    }
  }

  static final RegExp _safeDirectory = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*$');

  final int maxBytes;
  final String directoryName;
}

@immutable
class MdPlayerCacheStats {
  const MdPlayerCacheStats({
    required this.enabled,
    required this.currentBytes,
    required this.maxBytes,
    required this.cachedResources,
    required this.cacheReadBytes,
    required this.upstreamReadBytes,
    required this.cacheReadOperations,
    required this.upstreamOpenOperations,
  });

  final bool enabled;
  final int currentBytes;
  final int maxBytes;
  final int cachedResources;
  final int cacheReadBytes;
  final int upstreamReadBytes;
  final int cacheReadOperations;
  final int upstreamOpenOperations;
}

abstract final class MdPlayerCache {
  static final AndroidVideoPlayerApi _api = AndroidVideoPlayerApi();
  static Future<void>? _pendingConfiguration;

  static Future<void> configure(MdPlayerCacheConfiguration configuration) {
    _requireAndroid();
    final Future<void> operation = _api.configureCache(
      CacheConfigurationMessage(
        maxBytes: configuration.maxBytes,
        directoryName: configuration.directoryName,
      ),
    );
    _pendingConfiguration = operation;
    operation.then<void>((_) {
      if (identical(_pendingConfiguration, operation)) {
        _pendingConfiguration = null;
      }
    }, onError: (Object _, StackTrace __) {
      if (identical(_pendingConfiguration, operation)) {
        _pendingConfiguration = null;
      }
    });
    return operation;
  }

  static Future<void> disable() {
    _requireAndroid();
    return _api.disableCache();
  }

  static Future<MdPlayerCacheStats> stats() async {
    _requireAndroid();
    final CacheStatsMessage value = await _api.cacheStats();
    return MdPlayerCacheStats(
      enabled: value.enabled,
      currentBytes: value.currentBytes,
      maxBytes: value.maxBytes,
      cachedResources: value.cachedResources,
      cacheReadBytes: value.cacheReadBytes,
      upstreamReadBytes: value.upstreamReadBytes,
      cacheReadOperations: value.cacheReadOperations,
      upstreamOpenOperations: value.upstreamOpenOperations,
    );
  }

  static Future<void> clear() {
    _requireAndroid();
    return _api.clearCache();
  }

  static Future<void> removeVideo(String videoId) {
    _requireAndroid();
    if (videoId.isEmpty) {
      throw ArgumentError.value(videoId, 'videoId', 'Must not be empty');
    }
    return _api.removeCachedVideo(videoId);
  }

  static Future<void> waitForPendingConfiguration() async {
    final Future<void>? pending = _pendingConfiguration;
    if (pending != null) {
      await pending.timeout(const Duration(seconds: 5));
    }
  }

  static void _requireAndroid() {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      throw UnsupportedError('MdPlayerCache is only supported on Android');
    }
  }
}
