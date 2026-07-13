import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'android_video_player.dart';
import 'md_player_source.dart';

VideoPlayerPlatform? _cachedPlatform;

VideoPlayerPlatform get _platform {
  _cachedPlatform ??= VideoPlayerPlatform.instance..init();
  return _cachedPlatform!;
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
    String? errorDescription,
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
      errorDescription: errorDescription,
      size: size ?? this.size,
    );
  }
}

class MdPlayerController extends ValueNotifier<MdPlayerValue> {
  MdPlayerController.network(
    this.url, {
    this.autoPlay = false,
    MdPlayerSourceResolver? resolver,
  })  : _resolver = resolver ?? MdPlayerSourceResolver(),
        _ownsResolver = resolver == null,
        super(const MdPlayerValue.uninitialized());

  final String url;
  final bool autoPlay;
  final MdPlayerSourceResolver _resolver;
  final bool _ownsResolver;

  Timer? _positionTimer;
  StreamSubscription<VideoEvent>? _events;
  Completer<void>? _creatingCompleter;
  int _textureId = kUninitializedTextureId;
  MdPlayerSource? _source;

  static const int kUninitializedTextureId = -1;

  @visibleForTesting
  int get textureId => _textureId;

  int get playerId => _textureId;

  Future<void> initialize() async {
    value = value.copyWith(isResolving: true, errorDescription: null);
    try {
      _source = await _resolver.resolve(url);
      value = value.copyWith(
        isResolving: false,
        qualities: _source!.qualities,
        qualityLabel: _source!.qualityLabel,
      );
      await _create(_source!);
    } catch (error) {
      value = MdPlayerValue.erroneous(error.toString());
      rethrow;
    }
  }

  Future<void> _create(MdPlayerSource source) async {
    _creatingCompleter = Completer<void>();
    if (source.audioUrl == null) {
      _textureId = await _platform.createWithOptions(
            VideoCreationOptions(
              dataSource: DataSource(
                sourceType: DataSourceType.network,
                uri: source.videoUrl,
                formatHint: source.formatHint,
              ),
              viewType: VideoViewType.textureView,
            ),
          ) ??
          kUninitializedTextureId;
    } else {
      _textureId = await MdPlayerAndroid().createWithAudio(
            videoUri: source.videoUrl,
            audioUri: source.audioUrl!,
            formatHint: source.formatHint,
          ) ??
          kUninitializedTextureId;
    }
    _creatingCompleter!.complete();

    final Completer<void> initialized = Completer<void>();
    _events = _platform.videoEventsFor(_textureId).listen(
      (VideoEvent event) {
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
            _platform.setVolume(_textureId, 1);
            if (autoPlay || value.isPlaying) {
              play();
            }
            break;
          case VideoEventType.completed:
            pause();
            seekTo(value.duration);
            break;
          case VideoEventType.bufferingUpdate:
            value = value.copyWith(buffered: event.buffered);
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
      },
      onError: (Object error) {
        value = value.copyWith(errorDescription: '$error');
        if (!initialized.isCompleted) {
          initialized.completeError(error);
        }
      },
    );
    await initialized.future;
  }

  Future<void> play() async {
    value = value.copyWith(isPlaying: true);
    try {
      await _platform.play(_textureId);
    } on PlatformException catch (error) {
      _setPlatformError(error);
      return;
    }
    _positionTimer?.cancel();
    _positionTimer =
        Timer.periodic(const Duration(milliseconds: 500), (_) async {
      final int textureId = _textureId;
      if (textureId == kUninitializedTextureId) {
        return;
      }
      try {
        value =
            value.copyWith(position: await _platform.getPosition(textureId));
      } on PlatformException catch (_) {
        _positionTimer?.cancel();
      }
    });
    try {
      await _platform.setPlaybackSpeed(_textureId, value.playbackSpeed);
    } on PlatformException catch (error) {
      _setPlatformError(error);
    }
  }

  Future<void> pause() async {
    value = value.copyWith(isPlaying: false);
    _positionTimer?.cancel();
    try {
      await _platform.pause(_textureId);
    } on PlatformException catch (error) {
      _setPlatformError(error);
    }
  }

  Future<void> seekTo(Duration position) async {
    final Duration clamped = position < Duration.zero
        ? Duration.zero
        : position > value.duration
            ? value.duration
            : position;
    try {
      await _platform.seekTo(_textureId, clamped);
      value = value.copyWith(position: clamped);
    } on PlatformException catch (error) {
      _setPlatformError(error);
    }
  }

  Future<void> setPlaybackSpeed(double speed) async {
    value = value.copyWith(playbackSpeed: speed);
    if (value.isPlaying) {
      try {
        await _platform.setPlaybackSpeed(_textureId, speed);
      } on PlatformException catch (error) {
        _setPlatformError(error);
      }
    }
  }

  Future<void> setQuality(MdPlayerQuality quality) async {
    if (quality.audioUrl != null) {
      final Duration position = value.position;
      final bool wasPlaying = value.isPlaying;
      await _disposePlatformPlayer();
      value = value.copyWith(
        isInitialized: false,
        isBuffering: true,
        qualityLabel: quality.label,
      );
      try {
        await _create(MdPlayerSource(
          videoUrl: quality.videoUrl,
          audioUrl: quality.audioUrl,
          qualityLabel: quality.label,
        ));
        await seekTo(position);
        if (wasPlaying) {
          await play();
        }
      } on PlatformException catch (error) {
        _setPlatformError(error);
      }
      return;
    }
    try {
      await MdPlayerAndroid().changeQuality(_textureId, quality.videoUrl);
      value = value.copyWith(qualityLabel: quality.label);
    } on PlatformException catch (error) {
      _setPlatformError(error);
    }
  }

  @override
  Future<void> dispose() async {
    await _disposePlatformPlayer();
    if (_ownsResolver) {
      _resolver.close();
    }
    super.dispose();
  }

  Future<void> _disposePlatformPlayer() async {
    _positionTimer?.cancel();
    _positionTimer = null;
    await _events?.cancel();
    _events = null;
    final int textureId = _textureId;
    _textureId = kUninitializedTextureId;
    if (_creatingCompleter != null && textureId != kUninitializedTextureId) {
      await _creatingCompleter!.future;
      await _platform.dispose(textureId);
    }
    _creatingCompleter = null;
  }

  void _setPlatformError(PlatformException error) {
    _positionTimer?.cancel();
    value = value.copyWith(
      isPlaying: false,
      isBuffering: false,
      errorDescription: error.message ?? error.toString(),
    );
  }
}
