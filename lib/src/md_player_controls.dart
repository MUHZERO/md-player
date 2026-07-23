import 'package:flutter/material.dart';

enum MdPlayerControlsMode { legacy, modern }

@immutable
class MdPlayerStyle {
  const MdPlayerStyle({
    this.accent,
    this.foreground = Colors.white,
    this.scrim = const Color(0x99000000),
    this.focus = const Color(0xFFFFFFFF),
    this.progressBackground = const Color(0x66FFFFFF),
    this.buffered = const Color(0x99FFFFFF),
  });

  final Color? accent;
  final Color foreground;
  final Color scrim;
  final Color focus;
  final Color progressBackground;
  final Color buffered;

  Color accentFor(BuildContext context) =>
      accent ?? Theme.of(context).colorScheme.primary;
}

@immutable
class MdPlayerControlsConfiguration {
  MdPlayerControlsConfiguration({
    this.animationDuration = const Duration(milliseconds: 180),
    this.hideDelay = const Duration(seconds: 3),
    this.seekInterval = const Duration(seconds: 10),
    this.enableKeyboard = true,
    this.enableVolume = false,
    this.enableLock = true,
    List<double> speedOptions = const <double>[0.5, 1, 1.25, 1.5, 2],
  }) : speedOptions = _validateSpeeds(speedOptions);

  final Duration animationDuration;
  final Duration hideDelay;
  final Duration seekInterval;
  final bool enableKeyboard;
  final bool enableVolume;
  final bool enableLock;
  final List<double> speedOptions;

  static List<double> _validateSpeeds(List<double> values) {
    if (values.isEmpty ||
        values.any((double value) => !value.isFinite || value <= 0) ||
        values.toSet().length != values.length) {
      throw ArgumentError.value(
        values,
        'speedOptions',
        'must contain unique, positive, finite values',
      );
    }
    return List<double>.unmodifiable(values);
  }
}

@immutable
class MdPlayerControlsLabels {
  const MdPlayerControlsLabels({
    this.play = 'Play',
    this.pause = 'Pause',
    this.replay = 'Replay',
    this.mute = 'Mute',
    this.unmute = 'Unmute',
    this.volume = 'Volume',
    this.seekForward = 'Seek forward',
    this.seekBackward = 'Seek backward',
    this.progress = 'Playback position',
    this.settings = 'Settings',
    this.speed = 'Playback speed',
    this.quality = 'Quality',
    this.fullscreen = 'Enter fullscreen',
    this.exitFullscreen = 'Exit fullscreen',
    this.lock = 'Lock controls',
    this.unlock = 'Unlock controls',
    this.close = 'Close',
    this.loading = 'Loading video',
    this.buffering = 'Buffering',
    this.switchingQuality = 'Switching quality',
    this.qualityFailed = 'Could not change quality',
    this.error = 'Video could not be played',
    this.retry = 'Retry',
  });

  final String play;
  final String pause;
  final String replay;
  final String mute;
  final String unmute;
  final String volume;
  final String seekForward;
  final String seekBackward;
  final String progress;
  final String settings;
  final String speed;
  final String quality;
  final String fullscreen;
  final String exitFullscreen;
  final String lock;
  final String unlock;
  final String close;
  final String loading;
  final String buffering;
  final String switchingQuality;
  final String qualityFailed;
  final String error;
  final String retry;
}

@immutable
class MdPlayerControlsIcons {
  const MdPlayerControlsIcons({
    this.play = Icons.play_arrow,
    this.pause = Icons.pause,
    this.replay = Icons.replay,
    this.mute = Icons.volume_off,
    this.volume = Icons.volume_up,
    this.settings = Icons.settings,
    this.fullscreen = Icons.fullscreen,
    this.exitFullscreen = Icons.fullscreen_exit,
    this.lock = Icons.lock_outline,
    this.unlock = Icons.lock_open,
    this.close = Icons.close,
    this.quality = Icons.high_quality,
    this.speed = Icons.speed,
  });

  final IconData play;
  final IconData pause;
  final IconData replay;
  final IconData mute;
  final IconData volume;
  final IconData settings;
  final IconData fullscreen;
  final IconData exitFullscreen;
  final IconData lock;
  final IconData unlock;
  final IconData close;
  final IconData quality;
  final IconData speed;
}

typedef MdPlayerLoadingBuilder = Widget Function(
  BuildContext context,
  String semanticsLabel,
);

typedef MdPlayerErrorBuilder = Widget Function(
  BuildContext context,
  String message,
  Future<void> Function() retry,
);
