import 'dart:async';

import 'package:flutter/foundation.dart';

import 'messages.g.dart';

const int _minimumCacheBytes = 1024 * 1024;

/// Validated process-level Media3 cache configuration.
@immutable
class MdPlayerCacheConfiguration {
  /// Creates a bounded cache configuration.
  ///
  /// [maxBytes] must be at least 1 MiB. [directoryName] must be one safe
  /// relative directory name inside the application's private cache directory.
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

  /// Maximum cache size in bytes.
  final int maxBytes;

  /// Private cache-directory name.
  final String directoryName;
}

/// Snapshot of native Media3 cache usage and process-session I/O counters.
@immutable
class MdPlayerCacheStats {
  /// Creates an immutable cache-statistics snapshot.
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

  /// Whether future eligible sources use caching.
  final bool enabled;

  /// Bytes currently stored on disk.
  final int currentBytes;

  /// Configured maximum size in bytes.
  final int maxBytes;

  /// Number of resource keys currently stored.
  final int cachedResources;

  /// Bytes served from cache during this process session.
  final int cacheReadBytes;

  /// Bytes read upstream during this process session.
  final int upstreamReadBytes;

  /// Cache read operations during this process session.
  final int cacheReadOperations;

  /// Upstream open operations during this process session.
  final int upstreamOpenOperations;
}

/// Process-level facade for the optional Android Media3 cache.
///
/// Caching is disabled by default. Active cache-backed players hold generation
/// leases, so configuration and destructive operations may fail until affected
/// controllers are disposed.
abstract final class MdPlayerCache {
  static final AndroidVideoPlayerApi _api = AndroidVideoPlayerApi();
  static Future<void>? _pendingConfiguration;

  /// Configures caching for players created after this future completes.
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

  /// Disables caching for future players.
  ///
  /// Android rejects the operation while the active generation is leased.
  static Future<void> disable() {
    _requireAndroid();
    return _api.disableCache();
  }

  /// Returns current disk usage and process-session I/O counters.
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

  /// Removes all cached resources.
  ///
  /// Android rejects the operation while the active generation is leased.
  static Future<void> clear() {
    _requireAndroid();
    return _api.clearCache();
  }

  /// Removes resources whose stable identity is [videoId].
  ///
  /// Android rejects removal while a matching resource is leased.
  static Future<void> removeVideo(String videoId) {
    _requireAndroid();
    if (videoId.isEmpty) {
      throw ArgumentError.value(videoId, 'videoId', 'Must not be empty');
    }
    return _api.removeCachedVideo(videoId);
  }

  /// Waits for a configuration request that was issued immediately before
  /// player creation.
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
