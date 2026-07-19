import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'android_video_player.dart';
import 'md_player_source.dart';

const Object _errorDescriptionNotProvided = Object();

enum MdQualitySwitchStatus { idle, preparing, switching, completed, failed }

@immutable
class MdQualitySwitchState {
  const MdQualitySwitchState({
    this.status = MdQualitySwitchStatus.idle,
    this.operationId,
    this.requestedLabel,
    this.errorDescription,
    this.rollbackSucceeded,
  });

  final MdQualitySwitchStatus status;
  final String? operationId;
  final String? requestedLabel;
  final String? errorDescription;
  final bool? rollbackSucceeded;

  bool get isSwitching =>
      status == MdQualitySwitchStatus.preparing ||
      status == MdQualitySwitchStatus.switching;
}

@immutable
class MdPlayerValue {
  const MdPlayerValue({
    required this.duration,
    this.size = Size.zero,
    this.position = Duration.zero,
    this.buffered = const <DurationRange>[],
    this.isInitialized = false,
    this.isPlaying = false,
    this.isBuffering = false,
    this.isResolving = false,
    this.playbackSpeed = 1.0,
    this.qualityLabel = 'auto',
    this.qualities = const <MdPlayerQuality>[],
    this.errorDescription,
  });

  const MdPlayerValue.uninitialized()
      : this(duration: Duration.zero, isResolving: false);

  const MdPlayerValue.erroneous(String errorDescription)
      : this(duration: Duration.zero, errorDescription: errorDescription);

  final Duration duration;
  final Duration position;
  final List<DurationRange> buffered;
  final bool isInitialized;
  final bool isPlaying;
  final bool isBuffering;
  final bool isResolving;
  final double playbackSpeed;
  final String qualityLabel;
  final List<MdPlayerQuality> qualities;
  final String? errorDescription;
  final Size size;

  bool get hasError => errorDescription != null;

  double get aspectRatio {
    if (!isInitialized || size.width == 0 || size.height == 0) {
      return 16 / 9;
    }
    final double value = size.width / size.height;
    return value <= 0 ? 16 / 9 : value;
  }

  MdPlayerValue copyWith({
    Duration? duration,
    Duration? position,
    List<DurationRange>? buffered,
    bool? isInitialized,
    bool? isPlaying,
    bool? isBuffering,
    bool? isResolving,
    double? playbackSpeed,
    String? qualityLabel,
    List<MdPlayerQuality>? qualities,
    Object? errorDescription = _errorDescriptionNotProvided,
    Size? size,
  }) {
    return MdPlayerValue(
      duration: duration ?? this.duration,
      position: position ?? this.position,
      buffered: buffered ?? this.buffered,
      isInitialized: isInitialized ?? this.isInitialized,
      isPlaying: isPlaying ?? this.isPlaying,
      isBuffering: isBuffering ?? this.isBuffering,
      isResolving: isResolving ?? this.isResolving,
      playbackSpeed: playbackSpeed ?? this.playbackSpeed,
      qualityLabel: qualityLabel ?? this.qualityLabel,
      qualities: qualities ?? this.qualities,
      errorDescription:
          identical(errorDescription, _errorDescriptionNotProvided)
              ? this.errorDescription
              : errorDescription as String?,
      size: size ?? this.size,
    );
  }
}

class MdPlayerController extends ValueNotifier<MdPlayerValue> {
  MdPlayerController.network(
    this.url, {
    this.autoPlay = false,
    MdPlayerSourceResolver? resolver,
    @visibleForTesting VideoPlayerPlatform? platform,
  })  : _resolver = resolver ?? MdPlayerSourceResolver(),
        _ownsResolver = resolver == null,
        _platform = platform ?? VideoPlayerPlatform.instance,
        super(const MdPlayerValue.uninitialized());

  static const int kUninitializedTextureId = -1;

  final String url;
  final bool autoPlay;
  final MdPlayerSourceResolver _resolver;
  final bool _ownsResolver;
  final VideoPlayerPlatform _platform;

  Timer? _positionTimer;
  StreamSubscription<MdPlayerPlatformEvent>? _events;
  final ValueNotifier<MdQualitySwitchState> _qualitySwitchState =
      ValueNotifier<MdQualitySwitchState>(const MdQualitySwitchState());
  Completer<void>? _operationCancellation;
  Completer<void>? _qualitySwitchCompleter;
  Future<void> _pendingPlayerCleanup = Future<void>.value();
  Future<void>? _disposeFuture;
  int _textureId = kUninitializedTextureId;
  int _playerOperation = 0;
  int _playbackCommand = 0;
  int _positionCommand = 0;
  int _speedCommand = 0;
  int _qualityCommand = 0;
  int _qualityOperationId = 0;
  bool _positionRequestInFlight = false;
  bool _isDisposed = false;
  bool _resolverClosed = false;
  MdPlayerSource? _source;
  MdPlayerQuality? _requestedQuality;
  String? _activeQualityOperationId;

  ValueListenable<MdQualitySwitchState> get qualitySwitchState =>
      _qualitySwitchState;

  @visibleForTesting
  int get textureId => _textureId;

  int get playerId => _textureId;

  Future<void> initialize() async {
    if (_isDisposed) {
      return;
    }
    final int operation = _beginPlayerOperation();
    final Future<void> released = _releaseActivePlayer();
    value = value.copyWith(isResolving: true, errorDescription: null);

    try {
      await released;
      if (!_isCurrentOperation(operation)) {
        return;
      }
      final (bool, MdPlayerSource?) resolution = await _raceCancellation(
        _resolver.resolve(url),
        operation,
      );
      if (resolution.$1 || !_isCurrentOperation(operation)) {
        return;
      }
      final MdPlayerSource source = resolution.$2!;
      _source = source;
      value = value.copyWith(
        isResolving: false,
        qualities: List<MdPlayerQuality>.unmodifiable(source.qualities),
        qualityLabel: source.qualityLabel,
      );
      await _create(source, operation);
    } catch (error) {
      if (!_isCurrentOperation(operation)) {
        return;
      }
      await _releaseActivePlayer(swallowErrors: true);
      if (_isCurrentOperation(operation)) {
        value = MdPlayerValue.erroneous(error.toString());
        rethrow;
      }
    }
  }

  Future<bool> _create(MdPlayerSource source, int operation) async {
    final bool hasCacheMetadata = source.videoCacheKey != null ||
        source.audioCacheKey != null ||
        source.videoStreamIdentity != null;
    final Future<int?> creation = hasCacheMetadata
        ? _androidPlatform.createMdSource(
            videoUri: source.videoUrl,
            audioUri: source.audioUrl,
            videoFormatHint: source.formatHint,
            audioFormatHint: source.audioFormatHint,
            httpHeaders: source.httpHeaders,
            audioHttpHeaders: source.audioHttpHeaders,
            videoCacheKey: source.videoCacheKey,
            audioCacheKey: source.audioCacheKey,
            videoStreamIdentity: source.videoStreamIdentity,
            audioStreamIdentity: source.audioStreamIdentity,
            videoItag: source.videoItag,
            audioItag: source.audioItag,
            videoRole: source.videoRole,
            audioRole: source.audioRole,
          )
        : source.audioUrl == null
            ? _platform.createWithOptions(
                VideoCreationOptions(
                  dataSource: DataSource(
                    sourceType: DataSourceType.network,
                    uri: source.videoUrl,
                    formatHint: source.formatHint,
                    httpHeaders: source.httpHeaders,
                  ),
                  viewType: VideoViewType.textureView,
                ),
              )
            : _androidPlatform.createWithAudio(
                videoUri: source.videoUrl,
                audioUri: source.audioUrl!,
                formatHint: source.formatHint,
                httpHeaders: source.httpHeaders,
                audioHttpHeaders: source.audioHttpHeaders,
              );
    final (bool, int?) result =
        await _raceCancellation<int?>(creation, operation);
    if (result.$1) {
      unawaited(creation.then(_disposeStaleTexture, onError: (_) {}));
      return false;
    }

    final int textureId = result.$2 ?? kUninitializedTextureId;
    if (!_isCurrentOperation(operation)) {
      await _disposeStaleTexture(textureId);
      return false;
    }
    if (textureId == kUninitializedTextureId) {
      throw StateError('Platform did not create a video player');
    }

    final Completer<void> initialized = Completer<void>();
    final StreamSubscription<MdPlayerPlatformEvent>? previousEvents = _events;
    _events = null;
    await previousEvents?.cancel();
    if (!_isCurrentOperation(operation)) {
      await _disposeStaleTexture(textureId);
      return false;
    }

    _textureId = textureId;
    _events = _androidPlatform.playerEventsFor(textureId).listen(
      (MdPlayerPlatformEvent event) =>
          _handlePlatformEvent(event, operation, textureId, initialized),
      onError: (Object error) {
        if (!_isCurrentPlayer(operation, textureId)) {
          return;
        }
        value = value.copyWith(errorDescription: '$error');
        if (!initialized.isCompleted) {
          initialized.completeError(error);
        }
      },
    );

    final (bool, void) wait =
        await _raceCancellation(initialized.future, operation);
    if (wait.$1 || !_isCurrentPlayer(operation, textureId)) {
      return false;
    }
    try {
      await _platform.setVolume(textureId, 1);
    } on PlatformException catch (error) {
      _setPlatformError(error, operation: operation, textureId: textureId);
    }
    if (_isCurrentPlayer(operation, textureId) &&
        (autoPlay || value.isPlaying)) {
      await play();
    }
    return _isCurrentPlayer(operation, textureId);
  }

  void _handlePlatformEvent(
    MdPlayerPlatformEvent event,
    int operation,
    int textureId,
    Completer<void> initialized,
  ) {
    final VideoEvent? videoEvent = event.videoEvent;
    if (videoEvent != null) {
      _handleEvent(videoEvent, operation, textureId, initialized);
    }
    final MdQualitySwitchEvent? qualityEvent = event.qualityEvent;
    if (qualityEvent != null) {
      _handleQualityEvent(qualityEvent, operation, textureId);
    }
  }

  void _handleQualityEvent(
    MdQualitySwitchEvent event,
    int operation,
    int textureId,
  ) {
    if (!_isCurrentPlayer(operation, textureId) ||
        event.operationId != _activeQualityOperationId) {
      return;
    }
    final MdQualitySwitchStatus status = MdQualitySwitchStatus.values.byName(
      event.phase.name,
    );
    _qualitySwitchState.value = MdQualitySwitchState(
      status: status,
      operationId: event.operationId,
      requestedLabel: event.requestedLabel,
      errorDescription: event.errorDescription,
      rollbackSucceeded: event.rollbackSucceeded,
    );
    if (!event.isTerminal) {
      return;
    }
    if (event.phase == MdQualitySwitchPhase.completed) {
      final MdPlayerQuality? quality = _requestedQuality;
      if (quality != null) {
        value = value.copyWith(qualityLabel: quality.label);
        _source = MdPlayerSource(
          videoUrl: quality.videoUrl,
          audioUrl: quality.audioUrl,
          formatHint: quality.videoFormatHint,
          httpHeaders: quality.httpHeaders,
          audioHttpHeaders: quality.audioHttpHeaders,
          qualityLabel: quality.label,
          qualities: _source?.qualities ?? const <MdPlayerQuality>[],
          videoCacheKey: quality.videoCacheKey,
          audioCacheKey: quality.audioCacheKey,
          videoStreamIdentity: quality.videoStreamIdentity,
          audioStreamIdentity: quality.audioStreamIdentity,
          videoItag: quality.videoItag,
          audioItag: quality.audioItag,
          videoRole: quality.videoRole,
          audioRole: quality.audioRole,
          audioFormatHint: quality.audioFormatHint,
        );
      }
    }
    final Completer<void>? completer = _qualitySwitchCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
    _qualitySwitchCompleter = null;
    _requestedQuality = null;
  }

  void _handleEvent(
    VideoEvent event,
    int operation,
    int textureId,
    Completer<void> initialized,
  ) {
    if (!_isCurrentPlayer(operation, textureId)) {
      return;
    }
    switch (event.eventType) {
      case VideoEventType.initialized:
        value = value.copyWith(
          duration: event.duration,
          size: event.size,
          isInitialized: event.duration != null,
        );
        if (!initialized.isCompleted) {
          initialized.complete();
        }
        break;
      case VideoEventType.completed:
        unawaited(pause());
        unawaited(seekTo(value.duration));
        break;
      case VideoEventType.bufferingUpdate:
        value = value.copyWith(
          buffered: List<DurationRange>.unmodifiable(
            event.buffered ?? const <DurationRange>[],
          ),
        );
        break;
      case VideoEventType.bufferingStart:
        value = value.copyWith(isBuffering: true);
        break;
      case VideoEventType.bufferingEnd:
        value = value.copyWith(isBuffering: false);
        break;
      case VideoEventType.isPlayingStateUpdate:
        value = value.copyWith(isPlaying: event.isPlaying);
        break;
      case VideoEventType.unknown:
        break;
    }
  }

  Future<void> play() async {
    if (!_hasActivePlayer) {
      return;
    }
    final int textureId = _textureId;
    final int operation = _playerOperation;
    final int command = ++_playbackCommand;
    value = value.copyWith(isPlaying: true);
    try {
      await _platform.play(textureId);
    } on PlatformException catch (error) {
      _setPlatformError(
        error,
        operation: operation,
        textureId: textureId,
        playbackCommand: command,
      );
      return;
    }
    if (!_isCurrentPlayer(operation, textureId) ||
        command != _playbackCommand) {
      return;
    }
    _startPositionPolling();
    final int speedCommand = ++_speedCommand;
    try {
      await _platform.setPlaybackSpeed(textureId, value.playbackSpeed);
    } on PlatformException catch (error) {
      _setPlatformError(
        error,
        operation: operation,
        textureId: textureId,
        speedCommand: speedCommand,
      );
    }
  }

  Future<void> pause() async {
    if (!_hasActivePlayer) {
      return;
    }
    final int textureId = _textureId;
    final int operation = _playerOperation;
    final int command = ++_playbackCommand;
    _invalidatePosition();
    value = value.copyWith(isPlaying: false);
    try {
      await _platform.pause(textureId);
    } on PlatformException catch (error) {
      _setPlatformError(
        error,
        operation: operation,
        textureId: textureId,
        playbackCommand: command,
      );
    }
  }

  Future<void> seekTo(Duration position) async {
    if (!_hasActivePlayer) {
      return;
    }
    final int textureId = _textureId;
    final int operation = _playerOperation;
    final int command = ++_positionCommand;
    final Duration clamped = position < Duration.zero
        ? Duration.zero
        : position > value.duration
            ? value.duration
            : position;
    try {
      await _platform.seekTo(textureId, clamped);
      if (_isCurrentPlayer(operation, textureId) &&
          command == _positionCommand) {
        value = value.copyWith(position: clamped);
      }
    } on PlatformException catch (error) {
      _setPlatformError(
        error,
        operation: operation,
        textureId: textureId,
        positionCommand: command,
      );
    }
  }

  Future<void> setPlaybackSpeed(double speed) async {
    if (!_hasActivePlayer) {
      return;
    }
    final int textureId = _textureId;
    final int operation = _playerOperation;
    final int command = ++_speedCommand;
    value = value.copyWith(playbackSpeed: speed);
    if (!value.isPlaying) {
      return;
    }
    try {
      await _platform.setPlaybackSpeed(textureId, speed);
    } on PlatformException catch (error) {
      _setPlatformError(
        error,
        operation: operation,
        textureId: textureId,
        speedCommand: command,
      );
    }
  }

  /// Starts a quality switch on the current player.
  ///
  /// For compatibility, this future completes when Android accepts the
  /// request. Observe [qualitySwitchState] for terminal success or failure.
  Future<void> setQuality(MdPlayerQuality quality) async {
    if (!_hasActivePlayer) {
      return;
    }
    final int qualityCommand = ++_qualityCommand;
    final int textureId = _textureId;
    final int operation = _playerOperation;
    _completePendingQualitySwitch();
    final String operationId = '$textureId-${++_qualityOperationId}';
    _activeQualityOperationId = operationId;
    _requestedQuality = quality;
    _qualitySwitchCompleter = Completer<void>();
    _qualitySwitchState.value = MdQualitySwitchState(
      status: MdQualitySwitchStatus.preparing,
      operationId: operationId,
      requestedLabel: quality.label,
    );
    try {
      await _androidPlatform.changeQuality(
        textureId,
        quality.videoUrl,
        operationId: operationId,
        audioUri: quality.audioUrl,
        httpHeaders: quality.httpHeaders,
        audioHttpHeaders: quality.audioHttpHeaders,
        videoFormatHint: quality.videoFormatHint,
        audioFormatHint: quality.audioFormatHint,
        videoCacheKey: quality.videoCacheKey,
        audioCacheKey: quality.audioCacheKey,
        videoStreamIdentity: quality.videoStreamIdentity,
        audioStreamIdentity: quality.audioStreamIdentity,
        videoItag: quality.videoItag,
        audioItag: quality.audioItag,
        videoRole: quality.videoRole,
        audioRole: quality.audioRole,
        requestedLabel: quality.label,
      );
    } on PlatformException catch (error) {
      _setPlatformError(
        error,
        operation: operation,
        textureId: textureId,
        qualityCommand: qualityCommand,
      );
      if (_isCurrentQuality(operation, qualityCommand)) {
        _qualitySwitchState.value = MdQualitySwitchState(
          status: MdQualitySwitchStatus.failed,
          operationId: operationId,
          requestedLabel: quality.label,
          errorDescription: error.message ?? error.toString(),
        );
        _completePendingQualitySwitch();
      }
    }
  }

  @override
  // super.dispose() runs once in _finishDispose, after asynchronous cleanup.
  // ignore: must_call_super
  Future<void> dispose() {
    final Future<void>? existing = _disposeFuture;
    if (existing != null) {
      return existing;
    }
    _isDisposed = true;
    _cancelOperation();
    _playerOperation++;
    _playbackCommand++;
    _positionCommand++;
    _speedCommand++;
    _qualityCommand++;
    _completePendingQualitySwitch();
    _qualitySwitchState.value = const MdQualitySwitchState();
    final Future<void> cleanup = _releaseActivePlayer();
    return _disposeFuture = _finishDispose(cleanup);
  }

  Future<void> _finishDispose(Future<void> cleanup) async {
    try {
      await cleanup;
    } finally {
      try {
        if (_ownsResolver && !_resolverClosed) {
          _resolverClosed = true;
          _resolver.close();
        }
      } finally {
        super.dispose();
        _qualitySwitchState.dispose();
      }
    }
  }

  int _beginPlayerOperation({bool invalidateQuality = true}) {
    _cancelOperation();
    _operationCancellation = Completer<void>();
    _playerOperation++;
    _playbackCommand++;
    _speedCommand++;
    if (invalidateQuality) {
      _qualityCommand++;
      _completePendingQualitySwitch();
      _qualitySwitchState.value = const MdQualitySwitchState();
    }
    _invalidatePosition();
    return _playerOperation;
  }

  void _cancelOperation() {
    final Completer<void>? cancellation = _operationCancellation;
    if (cancellation != null && !cancellation.isCompleted) {
      cancellation.complete();
    }
    _operationCancellation = null;
  }

  Future<(bool, T?)> _raceCancellation<T>(
    Future<T> future,
    int operation,
  ) {
    final Completer<void>? cancellation = _operationCancellation;
    if (!_isCurrentOperation(operation) || cancellation == null) {
      return Future<(bool, T?)>.value((true, null));
    }
    return Future.any(<Future<(bool, T?)>>[
      future.then<(bool, T?)>((T result) => (false, result)),
      cancellation.future.then<(bool, T?)>((_) => (true, null)),
    ]);
  }

  Future<void> _releaseActivePlayer({bool swallowErrors = false}) {
    _invalidatePosition();
    final StreamSubscription<MdPlayerPlatformEvent>? events = _events;
    final int textureId = _textureId;
    _events = null;
    _textureId = kUninitializedTextureId;
    final Future<void> cleanup = _pendingPlayerCleanup.then((_) async {
      await events?.cancel();
      if (textureId != kUninitializedTextureId) {
        await _platform.dispose(textureId);
      }
    });
    _pendingPlayerCleanup = cleanup.then<void>((_) {}, onError: (_) {});
    return swallowErrors ? cleanup.catchError((_) {}) : cleanup;
  }

  void _completePendingQualitySwitch() {
    final Completer<void>? completer = _qualitySwitchCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
    _qualitySwitchCompleter = null;
    _requestedQuality = null;
    _activeQualityOperationId = null;
  }

  Future<void> _disposeStaleTexture(int? textureId) async {
    if (textureId == null || textureId == kUninitializedTextureId) {
      return;
    }
    try {
      await _platform.dispose(textureId);
    } catch (_) {
      // A stale operation no longer owns controller state.
    }
  }

  void _startPositionPolling() {
    _positionTimer?.cancel();
    _positionTimer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => _pollPosition(),
    );
  }

  Future<void> _pollPosition() async {
    if (_positionRequestInFlight || !_hasActivePlayer) {
      return;
    }
    final int textureId = _textureId;
    final int operation = _playerOperation;
    final int command = _positionCommand;
    _positionRequestInFlight = true;
    try {
      final Duration position = await _platform.getPosition(textureId);
      if (_isCurrentPlayer(operation, textureId) &&
          command == _positionCommand &&
          position != value.position) {
        value = value.copyWith(position: position);
      }
    } on PlatformException {
      if (_isCurrentPlayer(operation, textureId) &&
          command == _positionCommand) {
        _positionTimer?.cancel();
        _positionTimer = null;
      }
    } finally {
      _positionRequestInFlight = false;
    }
  }

  void _invalidatePosition() {
    _positionCommand++;
    _positionTimer?.cancel();
    _positionTimer = null;
  }

  bool get _hasActivePlayer =>
      !_isDisposed &&
      _textureId != kUninitializedTextureId &&
      value.isInitialized;

  MdPlayerAndroid get _androidPlatform =>
      _platform is MdPlayerAndroid ? _platform : MdPlayerAndroid();

  bool _isCurrentOperation(int operation) =>
      !_isDisposed && operation == _playerOperation;

  bool _isCurrentPlayer(int operation, int textureId) =>
      _isCurrentOperation(operation) && _textureId == textureId;

  bool _isCurrentQuality(int operation, int command) =>
      _isCurrentOperation(operation) && command == _qualityCommand;

  void _setPlatformError(
    PlatformException error, {
    required int operation,
    required int textureId,
    int? playbackCommand,
    int? positionCommand,
    int? speedCommand,
    int? qualityCommand,
  }) {
    if (!_isCurrentPlayer(operation, textureId) ||
        (playbackCommand != null && playbackCommand != _playbackCommand) ||
        (positionCommand != null && positionCommand != _positionCommand) ||
        (speedCommand != null && speedCommand != _speedCommand) ||
        (qualityCommand != null && qualityCommand != _qualityCommand)) {
      return;
    }
    _invalidatePosition();
    value = value.copyWith(
      isPlaying: false,
      isBuffering: false,
      errorDescription: error.message ?? error.toString(),
    );
  }
}
