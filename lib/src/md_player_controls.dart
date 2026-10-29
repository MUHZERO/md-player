import 'package:flutter/material.dart';

/// Selects the visual controls shown over an `MdPlayer`.
enum MdPlayerControlsMode { legacy, modern }

/// Colors used by the opt-in modern controls.
///
/// A null [accent] resolves from the host theme's [ColorScheme.primary].
@immutable
class MdPlayerStyle {
  /// Creates a modern-control color palette.
  const MdPlayerStyle({
    this.accent,
    this.foreground = Colors.white,
    this.scrim = const Color(0x99000000),
    this.focus = const Color(0xFFFFFFFF),
    this.progressBackground = const Color(0x66FFFFFF),
    this.buffered = const Color(0x99FFFFFF),
  });

  /// Optional primary action and progress color.
  final Color? accent;

  /// Foreground color for icons and labels.
  final Color foreground;

  /// Color drawn behind visible controls.
  final Color scrim;

  /// Keyboard-focus highlight color.
  final Color focus;

  /// Unplayed progress-track color.
  final Color progressBackground;

  /// Buffered progress-track color.
  final Color buffered;

  /// Resolves [accent] against the host theme when it is null.
  Color accentFor(BuildContext context) =>
      accent ?? Theme.of(context).colorScheme.primary;
}

/// Behavior and feature flags for the opt-in modern controls.
@immutable
class MdPlayerControlsConfiguration {
  /// Creates a modern-controls configuration.
  ///
  /// [speedOptions] must contain unique, positive, finite values.
  MdPlayerControlsConfiguration({
    this.animationDuration = const Duration(milliseconds: 180),
    this.hideDelay = const Duration(seconds: 3),
    this.seekInterval = const Duration(seconds: 10),
    this.enableKeyboard = true,
    this.enableVolume = false,
    this.enableLock = true,
    List<double> speedOptions = const <double>[0.5, 1, 1.25, 1.5, 2],
  }) : speedOptions = _validateSpeeds(speedOptions);

  /// Duration of control fades and scales.
  final Duration animationDuration;

  /// Delay before controls hide while playback is active.
  final Duration hideDelay;

  /// Distance used by keyboard and double-tap seeking.
  final Duration seekInterval;

  /// Whether shortcuts are active while the player owns focus.
  final bool enableKeyboard;

  /// Whether volume controls and shortcuts are available.
  final bool enableVolume;

  /// Whether the modern controls can be locked.
  final bool enableLock;

  /// Ordered playback speeds shown to the user.
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

/// User-visible and semantic text used by the modern controls.
///
/// Defaults are English. Supply a localized instance from the host app when
/// another locale is active.
@immutable
class MdPlayerControlsLabels {
  /// Creates a complete labels set with overridable English defaults.
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
    this.normalSpeed = 'Normal',
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

  /// Play action label.
  final String play;

  /// Pause action label.
  final String pause;

  /// Replay action label.
  final String replay;

  /// Mute action label.
  final String mute;

  /// Unmute action label.
  final String unmute;

  /// Volume action label.
  final String volume;

  /// Forward-seek action label.
  final String seekForward;

  /// Backward-seek action label.
  final String seekBackward;

  /// Progress-control semantic label.
  final String progress;

  /// Settings action label.
  final String settings;

  /// Playback-speed setting label.
  final String speed;

  /// Name shown for the 1x playback speed.
  final String normalSpeed;

  /// Quality setting label.
  final String quality;

  /// Enter-fullscreen action label.
  final String fullscreen;

  /// Exit-fullscreen action label.
  final String exitFullscreen;

  /// Lock-controls action label.
  final String lock;

  /// Unlock-controls action label.
  final String unlock;

  /// Close action label.
  final String close;

  /// Initial loading message.
  final String loading;

  /// Rebuffering message.
  final String buffering;

  /// Quality-switch progress message.
  final String switchingQuality;

  /// Recoverable quality-switch failure message.
  final String qualityFailed;

  /// Sanitized fatal playback error message.
  final String error;

  /// Retry action label.
  final String retry;
}

/// Icons used by the opt-in modern controls.
@immutable
class MdPlayerControlsIcons {
  /// Creates an icon set with Material icon defaults.
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
    this.seekBackward = Icons.replay_10,
    this.seekForward = Icons.forward_10,
  });

  /// Play icon.
  final IconData play;

  /// Pause icon.
  final IconData pause;

  /// Replay icon.
  final IconData replay;

  /// Muted-volume icon.
  final IconData mute;

  /// Audible-volume icon.
  final IconData volume;

  /// Settings icon.
  final IconData settings;

  /// Enter-fullscreen icon.
  final IconData fullscreen;

  /// Exit-fullscreen icon.
  final IconData exitFullscreen;

  /// Lock icon.
  final IconData lock;

  /// Unlock icon.
  final IconData unlock;

  /// Close icon.
  final IconData close;

  /// Quality icon.
  final IconData quality;

  /// Playback-speed icon.
  final IconData speed;

  /// Seek-backward icon.
  final IconData seekBackward;

  /// Seek-forward icon.
  final IconData seekForward;
}

/// Builds the initial-loading UI for an `MdPlayer`.
typedef MdPlayerLoadingBuilder = Widget Function(
  BuildContext context,
  String semanticsLabel,
);

/// Builds the fatal-error UI for an `MdPlayer`.
typedef MdPlayerErrorBuilder = Widget Function(
  BuildContext context,
  String message,
  Future<void> Function() retry,
);

/// A titled section of the video, marked on the modern progress bar.
///
/// Jump to one with `controller.seekTo(chapter.start)`.
@immutable
class MdPlayerChapter {
  /// Creates a chapter starting at [start].
  const MdPlayerChapter({required this.start, required this.title});

  /// Position where the chapter begins.
  final Duration start;

  /// Title shown while scrubbing inside the chapter.
  final String title;
}
