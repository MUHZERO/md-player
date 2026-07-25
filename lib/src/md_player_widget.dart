import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'md_player_controller.dart';
import 'md_player_controls.dart';
import 'md_player_debug.dart';
import 'md_player_source.dart';

/// Renders a stable Android video texture with legacy or modern Flutter controls.
///
/// Modern controls are opt-in. Fullscreen callbacks report intent to the host;
/// this widget never changes routes, orientation, system UI, or activity state.
class MdPlayer extends StatefulWidget {
  /// Creates a player widget.
  const MdPlayer({
    super.key,
    required this.controller,
    this.onFullscreenPressed,
    this.controlsMode = MdPlayerControlsMode.legacy,
    this.controlsConfiguration,
    this.labels = const MdPlayerControlsLabels(),
    this.icons = const MdPlayerControlsIcons(),
    this.style = const MdPlayerStyle(),
    this.title,
    this.subtitle,
    this.onClose,
    this.topActions = const <Widget>[],
    this.isFullscreen = false,
    this.onEnterFullscreen,
    this.onExitFullscreen,
    this.onRetry,
    this.loadingBuilder,
    this.errorBuilder,
  });

  /// Playback controller that owns the texture and native player.
  final MdPlayerController controller;

  /// Compatibility fullscreen callback used when the state-specific callback
  /// for the requested transition is absent.
  final VoidCallback? onFullscreenPressed;

  /// Controls implementation; defaults to [MdPlayerControlsMode.legacy].
  final MdPlayerControlsMode controlsMode;

  /// Optional modern-control behavior configuration.
  final MdPlayerControlsConfiguration? controlsConfiguration;

  /// Modern-control labels and semantic text.
  final MdPlayerControlsLabels labels;

  /// Modern-control icons.
  final MdPlayerControlsIcons icons;

  /// Modern-control colors.
  final MdPlayerStyle style;

  /// Optional modern-control title.
  final String? title;

  /// Optional modern-control subtitle.
  final String? subtitle;

  /// Optional close action shown by modern controls.
  final VoidCallback? onClose;

  /// Additional host-owned actions shown in the modern top bar.
  final List<Widget> topActions;

  /// Host-owned fullscreen state used to select enter/exit behavior.
  final bool isFullscreen;

  /// Requests that the host enter fullscreen.
  final VoidCallback? onEnterFullscreen;

  /// Requests that the host exit fullscreen.
  final VoidCallback? onExitFullscreen;

  /// Optional retry operation for fatal playback errors.
  final FutureOr<void> Function()? onRetry;

  /// Optional replacement for the initial modern loading indicator.
  final MdPlayerLoadingBuilder? loadingBuilder;

  /// Optional replacement for the fatal modern error overlay.
  final MdPlayerErrorBuilder? errorBuilder;

  @override
  State<MdPlayer> createState() => _MdPlayerState();
}

class _MdPlayerState extends State<MdPlayer> {
  late _MdPlayerAdapter _adapter;
  late Widget _surface;

  @override
  void initState() {
    super.initState();
    _adapter = _MdPlayerAdapter(widget.controller);
    _surface = _StableSurface(playerId: _adapter.playerId);
  }

  @override
  void didUpdateWidget(MdPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _adapter.dispose();
      _adapter = _MdPlayerAdapter(widget.controller);
      _surface = _StableSurface(playerId: _adapter.playerId);
    }
  }

  @override
  void dispose() {
    _adapter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Widget overlay = widget.controlsMode == MdPlayerControlsMode.modern
        ? _ModernControls(player: widget, adapter: _adapter)
        : _LegacyOverlay(player: widget, adapter: _adapter);
    return ValueListenableBuilder<double>(
      valueListenable: _adapter.aspectRatio,
      child: ColoredBox(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            _surface,
            overlay,
          ],
        ),
      ),
      builder: (_, double aspectRatio, Widget? child) =>
          AspectRatio(aspectRatio: aspectRatio, child: child),
    );
  }
}

typedef _Timeline = ({
  Duration duration,
  Duration position,
  List<DurationRange> buffered,
});
typedef _Playback = ({bool initialized, bool playing});
typedef _SpeedVolume = ({double speed, double volume});

class _MdPlayerAdapter {
  _MdPlayerAdapter(this.controller)
      : value = ValueNotifier<MdPlayerValue>(controller.value),
        playerId = ValueNotifier<int>(controller.playerId),
        aspectRatio = ValueNotifier<double>(controller.value.aspectRatio),
        playback = ValueNotifier<_Playback>((
          initialized: controller.value.isInitialized,
          playing: controller.value.isPlaying,
        )),
        timeline = ValueNotifier<_Timeline>((
          duration: controller.value.duration,
          position: controller.value.position,
          buffered: controller.value.buffered,
        )),
        buffering = ValueNotifier<bool>(controller.value.isBuffering),
        resolving = ValueNotifier<bool>(controller.value.isResolving),
        error = ValueNotifier<String?>(controller.value.errorDescription),
        speedVolume = ValueNotifier<_SpeedVolume>((
          speed: controller.value.playbackSpeed,
          volume: controller.value.volume,
        )),
        confirmedQuality =
            ValueNotifier<MdPlayerQuality?>(controller.confirmedQuality),
        quality = ValueNotifier<MdQualitySwitchState>(
          controller.qualitySwitchState.value,
        ) {
    controller.addListener(_changed);
    controller.qualitySwitchState.addListener(_qualityChanged);
  }

  final MdPlayerController controller;
  final ValueNotifier<MdPlayerValue> value;
  final ValueNotifier<int> playerId;
  final ValueNotifier<double> aspectRatio;
  final ValueNotifier<_Playback> playback;
  final ValueNotifier<_Timeline> timeline;
  final ValueNotifier<bool> buffering;
  final ValueNotifier<bool> resolving;
  final ValueNotifier<String?> error;
  final ValueNotifier<_SpeedVolume> speedVolume;
  final ValueNotifier<MdPlayerQuality?> confirmedQuality;
  final ValueNotifier<MdQualitySwitchState> quality;

  void _changed() {
    final MdPlayerValue next = controller.value;
    value.value = next;
    playerId.value = controller.playerId;
    aspectRatio.value = next.aspectRatio;
    playback.value = (
      initialized: next.isInitialized,
      playing: next.isPlaying,
    );
    timeline.value = (
      duration: next.duration,
      position: next.position,
      buffered: next.buffered,
    );
    buffering.value = next.isBuffering;
    resolving.value = next.isResolving;
    error.value = next.errorDescription;
    speedVolume.value = (speed: next.playbackSpeed, volume: next.volume);
    confirmedQuality.value = controller.confirmedQuality;
  }

  void _qualityChanged() => quality.value = controller.qualitySwitchState.value;

  void dispose() {
    controller.removeListener(_changed);
    controller.qualitySwitchState.removeListener(_qualityChanged);
    for (final ChangeNotifier notifier in <ChangeNotifier>[
      value,
      playerId,
      aspectRatio,
      playback,
      timeline,
      buffering,
      resolving,
      error,
      speedVolume,
      confirmedQuality,
      quality,
    ]) {
      notifier.dispose();
    }
  }
}

class _StableSurface extends StatelessWidget {
  const _StableSurface({required this.playerId});

  final ValueListenable<int> playerId;

  @override
  Widget build(BuildContext context) {
    MdPlayerRebuildDiagnostics.surface();
    return RepaintBoundary(
      child: ValueListenableBuilder<int>(
        valueListenable: playerId,
        builder: (_, int id, __) {
          if (id == MdPlayerController.kUninitializedTextureId) {
            return const SizedBox.expand();
          }
          return VideoPlayerPlatform.instance.buildViewWithOptions(
            VideoViewOptions(playerId: id),
          );
        },
      ),
    );
  }
}

class _LegacyOverlay extends StatefulWidget {
  const _LegacyOverlay({required this.player, required this.adapter});

  final MdPlayer player;
  final _MdPlayerAdapter adapter;

  @override
  State<_LegacyOverlay> createState() => _LegacyOverlayState();
}

class _LegacyOverlayState extends State<_LegacyOverlay> {
  bool _visible = true;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _toggle() {
    setState(() => _visible = !_visible);
    _timer?.cancel();
    if (widget.adapter.controller.value.isPlaying) {
      _timer = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _visible = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<MdPlayerValue>(
      valueListenable: widget.adapter.value,
      builder: (_, MdPlayerValue value, __) => Stack(
        fit: StackFit.expand,
        children: <Widget>[
          GestureDetector(behavior: HitTestBehavior.opaque, onTap: _toggle),
          if (value.isResolving || value.isBuffering)
            const Center(child: CircularProgressIndicator(color: Colors.white)),
          if (value.hasError)
            _LegacyError(
              message: value.errorDescription!,
              onRetry: widget.adapter.controller.initialize,
            ),
          if (_visible && !value.hasError)
            _LegacyControls(
              controller: widget.adapter.controller,
              onFullscreenPressed: widget.player.onFullscreenPressed,
            ),
        ],
      ),
    );
  }
}

enum _VisibilityState { hidden, visible, interacting, settings, locked, error }

class _PlayPauseIntent extends Intent {
  const _PlayPauseIntent();
}

class _SeekIntent extends Intent {
  const _SeekIntent(this.forward);
  final bool forward;
}

class _MuteIntent extends Intent {
  const _MuteIntent();
}

class _VolumeIntent extends Intent {
  const _VolumeIntent(this.up);
  final bool up;
}

class _FullscreenIntent extends Intent {
  const _FullscreenIntent();
}

class _EscapeIntent extends Intent {
  const _EscapeIntent();
}

class _ModernControls extends StatefulWidget {
  const _ModernControls({required this.player, required this.adapter});

  final MdPlayer player;
  final _MdPlayerAdapter adapter;

  @override
  State<_ModernControls> createState() => _ModernControlsState();
}

class _ModernControlsState extends State<_ModernControls> {
  late final MdPlayerControlsConfiguration _configuration;
  _VisibilityState _visibility = _VisibilityState.visible;
  Timer? _hideTimer;
  Timer? _feedbackTimer;
  int _hideGeneration = 0;
  Offset? _doubleTapPosition;
  Duration? _requestedTarget;
  Duration? _feedbackTarget;
  Duration? _dragPreview;
  String? _qualityFailure;

  bool get _shown => _visibility != _VisibilityState.hidden;
  bool get _settings => _visibility == _VisibilityState.settings;
  bool get _locked => _visibility == _VisibilityState.locked;

  @override
  void initState() {
    super.initState();
    _configuration =
        widget.player.controlsConfiguration ?? MdPlayerControlsConfiguration();
    widget.adapter.playback.addListener(_playbackChanged);
    widget.adapter.error.addListener(_errorChanged);
    widget.adapter.quality.addListener(_qualityChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scheduleHide());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.accessibleNavigationOf(context)) {
      _hideTimer?.cancel();
      if (_visibility == _VisibilityState.hidden) {
        _visibility = _VisibilityState.visible;
      }
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _feedbackTimer?.cancel();
    widget.adapter.playback.removeListener(_playbackChanged);
    widget.adapter.error.removeListener(_errorChanged);
    widget.adapter.quality.removeListener(_qualityChanged);
    super.dispose();
  }

  void _playbackChanged() => _scheduleHide();

  void _errorChanged() {
    if (!mounted) return;
    setState(() {
      _visibility = widget.adapter.error.value == null
          ? _VisibilityState.visible
          : _VisibilityState.error;
    });
    _scheduleHide();
  }

  void _qualityChanged() {
    if (!mounted) return;
    final MdQualitySwitchState state = widget.adapter.quality.value;
    if (state.status == MdQualitySwitchStatus.completed) {
      setState(() {
        _qualityFailure = null;
        _visibility = _VisibilityState.visible;
      });
      _scheduleHide();
    } else if (state.status == MdQualitySwitchStatus.failed) {
      setState(() {
        _qualityFailure = widget.player.labels.qualityFailed;
        _visibility = _VisibilityState.settings;
      });
    }
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    final int generation = ++_hideGeneration;
    if (!mounted ||
        !widget.adapter.playback.value.playing ||
        _settings ||
        _locked ||
        _visibility == _VisibilityState.interacting ||
        widget.adapter.error.value != null ||
        MediaQuery.maybeOf(context)?.accessibleNavigation == true) {
      return;
    }
    _hideTimer = Timer(_configuration.hideDelay, () {
      if (mounted && generation == _hideGeneration) {
        setState(() => _visibility = _VisibilityState.hidden);
      }
    });
  }

  void _toggleControls() {
    if (_settings || _dragPreview != null) return;
    setState(() {
      _visibility = _shown ? _VisibilityState.hidden : _VisibilityState.visible;
    });
    _scheduleHide();
  }

  Future<void> _togglePlayback() async {
    final MdPlayerValue value = widget.adapter.controller.value;
    if (value.position >= value.duration && value.duration > Duration.zero) {
      await widget.adapter.controller.seekTo(Duration.zero);
      await widget.adapter.controller.play();
    } else if (value.isPlaying) {
      await widget.adapter.controller.pause();
    } else {
      await widget.adapter.controller.play();
    }
    _show();
  }

  void _show() {
    if (!mounted) return;
    setState(() => _visibility = _VisibilityState.visible);
    _scheduleHide();
  }

  Future<void> _seekBy(Duration delta) async {
    final MdPlayerValue value = widget.adapter.controller.value;
    if (value.duration <= Duration.zero) return;
    final Duration base = _requestedTarget ?? value.position;
    final Duration target = _clampDuration(base + delta, value.duration);
    setState(() {
      _requestedTarget = target;
      _feedbackTarget = target;
      _visibility = _VisibilityState.interacting;
    });
    _feedbackTimer?.cancel();
    await widget.adapter.controller.seekTo(target);
    _feedbackTimer = Timer(const Duration(milliseconds: 700), () {
      if (!mounted) return;
      setState(() {
        _requestedTarget = null;
        _feedbackTarget = null;
        _visibility = _VisibilityState.visible;
      });
      _scheduleHide();
    });
  }

  void _handleDoubleTap(BoxConstraints constraints) {
    if (_settings || _locked || _dragPreview != null) return;
    final double x = _doubleTapPosition?.dx ?? constraints.maxWidth / 2;
    if (x < constraints.maxWidth / 3) {
      unawaited(_seekBy(-_configuration.seekInterval));
    } else if (x > constraints.maxWidth * 2 / 3) {
      unawaited(_seekBy(_configuration.seekInterval));
    } else {
      unawaited(_togglePlayback());
    }
  }

  void _fullscreen() {
    if (widget.player.isFullscreen) {
      (widget.player.onExitFullscreen ?? widget.player.onFullscreenPressed)
          ?.call();
    } else {
      (widget.player.onEnterFullscreen ?? widget.player.onFullscreenPressed)
          ?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    MdPlayerRebuildDiagnostics.controls();
    final bool disableAnimations = MediaQuery.disableAnimationsOf(context);
    final MdPlayerStyle style = widget.player.style;
    final Map<ShortcutActivator, Intent> shortcuts =
        <ShortcutActivator, Intent>{
      if (_configuration.enableKeyboard) ...<ShortcutActivator, Intent>{
        const SingleActivator(LogicalKeyboardKey.space):
            const _PlayPauseIntent(),
        const SingleActivator(LogicalKeyboardKey.keyK):
            const _PlayPauseIntent(),
        const SingleActivator(LogicalKeyboardKey.arrowLeft):
            const _SeekIntent(false),
        const SingleActivator(LogicalKeyboardKey.keyJ):
            const _SeekIntent(false),
        const SingleActivator(LogicalKeyboardKey.arrowRight):
            const _SeekIntent(true),
        const SingleActivator(LogicalKeyboardKey.keyL): const _SeekIntent(true),
        const SingleActivator(LogicalKeyboardKey.keyF):
            const _FullscreenIntent(),
        const SingleActivator(LogicalKeyboardKey.escape): const _EscapeIntent(),
        if (_configuration.enableVolume) ...<ShortcutActivator, Intent>{
          const SingleActivator(LogicalKeyboardKey.keyM): const _MuteIntent(),
          const SingleActivator(LogicalKeyboardKey.arrowUp):
              const _VolumeIntent(true),
          const SingleActivator(LogicalKeyboardKey.arrowDown):
              const _VolumeIntent(false),
        },
      },
    };
    return Theme(
      data: Theme.of(context).copyWith(focusColor: style.focus),
      child: Shortcuts(
        shortcuts: shortcuts,
        child: Actions(
          actions: <Type, Action<Intent>>{
            _PlayPauseIntent: CallbackAction<_PlayPauseIntent>(
              onInvoke: (_) => unawaited(_togglePlayback()),
            ),
            _SeekIntent: CallbackAction<_SeekIntent>(
              onInvoke: (_SeekIntent intent) => unawaited(_seekBy(
                intent.forward
                    ? _configuration.seekInterval
                    : -_configuration.seekInterval,
              )),
            ),
            _MuteIntent: CallbackAction<_MuteIntent>(
              onInvoke: (_) =>
                  unawaited(widget.adapter.controller.toggleMute()),
            ),
            _VolumeIntent: CallbackAction<_VolumeIntent>(
              onInvoke: (_VolumeIntent intent) => unawaited(
                widget.adapter.controller.setVolume(
                  widget.adapter.controller.value.volume +
                      (intent.up ? 0.1 : -0.1),
                ),
              ),
            ),
            _FullscreenIntent: CallbackAction<_FullscreenIntent>(
              onInvoke: (_) => _fullscreen(),
            ),
            _EscapeIntent: CallbackAction<_EscapeIntent>(
              onInvoke: (_) => setState(() {
                _visibility = _settings || _locked
                    ? _VisibilityState.visible
                    : _VisibilityState.hidden;
              }),
            ),
          },
          child: Focus(
            canRequestFocus: true,
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final _PlayerLayout layout = _PlayerLayout.forSize(constraints);
                return Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _toggleControls,
                      onDoubleTapDown: (TapDownDetails details) =>
                          _doubleTapPosition = details.localPosition,
                      onDoubleTap: () => _handleDoubleTap(constraints),
                    ),
                    _StatusOverlays(
                        player: widget.player, adapter: widget.adapter),
                    if (_feedbackTarget != null)
                      Center(
                        child: Semantics(
                          liveRegion: true,
                          label: _format(_feedbackTarget!),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: style.scrim,
                              borderRadius: BorderRadius.circular(24),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                              child: Text(
                                _format(_feedbackTarget!),
                                style: TextStyle(color: style.foreground),
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (_shown && widget.adapter.error.value == null)
                      SafeArea(
                        child: ColoredBox(
                          color: style.scrim,
                          child: _locked
                              ? Align(
                                  alignment: Alignment.centerLeft,
                                  child: _ControlButton(
                                    icon: widget.player.icons.unlock,
                                    label: widget.player.labels.unlock,
                                    color: style.foreground,
                                    onPressed: () => setState(() =>
                                        _visibility = _VisibilityState.visible),
                                  ),
                                )
                              : Column(
                                  children: <Widget>[
                                    _TopBar(player: widget.player),
                                    Expanded(
                                      child: _settings
                                          ? _SettingsPanel(
                                              player: widget.player,
                                              adapter: widget.adapter,
                                              configuration: _configuration,
                                              failure: _qualityFailure,
                                            )
                                          : Center(
                                              child: ValueListenableBuilder<
                                                  _Playback>(
                                                valueListenable:
                                                    widget.adapter.playback,
                                                builder: (_, _Playback playback,
                                                    __) {
                                                  final MdPlayerValue value =
                                                      widget.adapter.controller
                                                          .value;
                                                  final bool replay =
                                                      !playback.playing &&
                                                          value.duration >
                                                              Duration.zero &&
                                                          value.position >=
                                                              value.duration;
                                                  return AnimatedScale(
                                                    scale: 1,
                                                    duration: disableAnimations
                                                        ? Duration.zero
                                                        : _configuration
                                                            .animationDuration,
                                                    child: _ControlButton(
                                                      size: 64,
                                                      icon: replay
                                                          ? widget.player.icons
                                                              .replay
                                                          : playback.playing
                                                              ? widget.player
                                                                  .icons.pause
                                                              : widget.player
                                                                  .icons.play,
                                                      label: replay
                                                          ? widget.player.labels
                                                              .replay
                                                          : playback.playing
                                                              ? widget.player
                                                                  .labels.pause
                                                              : widget.player
                                                                  .labels.play,
                                                      color: style.foreground,
                                                      onPressed:
                                                          _togglePlayback,
                                                    ),
                                                  );
                                                },
                                              ),
                                            ),
                                    ),
                                    _ProgressBar(
                                      player: widget.player,
                                      adapter: widget.adapter,
                                      preview: _dragPreview,
                                      onInteraction: (Duration? preview) {
                                        setState(() {
                                          _dragPreview = preview;
                                          _visibility = preview == null
                                              ? _VisibilityState.visible
                                              : _VisibilityState.interacting;
                                        });
                                        if (preview == null) _scheduleHide();
                                      },
                                    ),
                                    _BottomBar(
                                      player: widget.player,
                                      adapter: widget.adapter,
                                      configuration: _configuration,
                                      layout: layout,
                                      onSettings: () => setState(() {
                                        _qualityFailure = null;
                                        _visibility = _settings
                                            ? _VisibilityState.visible
                                            : _VisibilityState.settings;
                                      }),
                                      onFullscreen: _fullscreen,
                                      onLock: _configuration.enableLock
                                          ? () => setState(() => _visibility =
                                              _VisibilityState.locked)
                                          : null,
                                    ),
                                  ],
                                ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

enum _PlayerLayout {
  compact,
  standard,
  expanded;

  static _PlayerLayout forSize(BoxConstraints constraints) {
    if (constraints.maxWidth < 480 || constraints.maxHeight < 280) {
      return compact;
    }
    if (constraints.maxWidth >= 900 && constraints.maxHeight >= 420) {
      return expanded;
    }
    return standard;
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.player});
  final MdPlayer player;

  @override
  Widget build(BuildContext context) => Row(
        children: <Widget>[
          if (player.onClose != null)
            _ControlButton(
              icon: player.icons.close,
              label: player.labels.close,
              color: player.style.foreground,
              onPressed: player.onClose,
            ),
          if (player.title != null || player.subtitle != null)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    if (player.title != null)
                      Text(
                        player.title!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: player.style.foreground,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    if (player.subtitle != null)
                      Text(
                        player.subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: player.style.foreground),
                      ),
                  ],
                ),
              ),
            )
          else
            const Spacer(),
          ...player.topActions,
        ],
      );
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.player,
    required this.adapter,
    required this.configuration,
    required this.layout,
    required this.onSettings,
    required this.onFullscreen,
    required this.onLock,
  });

  final MdPlayer player;
  final _MdPlayerAdapter adapter;
  final MdPlayerControlsConfiguration configuration;
  final _PlayerLayout layout;
  final VoidCallback onSettings;
  final VoidCallback onFullscreen;
  final VoidCallback? onLock;

  bool get _hasFullscreen =>
      player.onFullscreenPressed != null ||
      player.onEnterFullscreen != null ||
      player.onExitFullscreen != null;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
        child: Row(
          children: <Widget>[
            ValueListenableBuilder<_Timeline>(
              valueListenable: adapter.timeline,
              builder: (_, _Timeline value, __) => Text(
                '${_format(value.position)} / ${_format(value.duration)}',
                style: TextStyle(color: player.style.foreground, fontSize: 12),
              ),
            ),
            const Spacer(),
            if (layout == _PlayerLayout.expanded)
              _InlineSpeed(
                player: player,
                adapter: adapter,
                options: configuration.speedOptions,
              ),
            if (layout != _PlayerLayout.compact &&
                adapter.controller.value.qualities.isNotEmpty)
              _InlineQuality(player: player, adapter: adapter),
            if (layout == _PlayerLayout.expanded && configuration.enableVolume)
              _VolumeButton(player: player, adapter: adapter),
            _ControlButton(
              icon: player.icons.settings,
              label: player.labels.settings,
              color: player.style.foreground,
              onPressed: onSettings,
            ),
            if (onLock != null)
              _ControlButton(
                icon: player.icons.lock,
                label: player.labels.lock,
                color: player.style.foreground,
                onPressed: onLock,
              ),
            if (_hasFullscreen)
              _ControlButton(
                icon: player.isFullscreen
                    ? player.icons.exitFullscreen
                    : player.icons.fullscreen,
                label: player.isFullscreen
                    ? player.labels.exitFullscreen
                    : player.labels.fullscreen,
                color: player.style.foreground,
                onPressed: onFullscreen,
              ),
          ],
        ),
      );
}

class _ProgressBar extends StatefulWidget {
  const _ProgressBar({
    required this.player,
    required this.adapter,
    required this.preview,
    required this.onInteraction,
  });

  final MdPlayer player;
  final _MdPlayerAdapter adapter;
  final Duration? preview;
  final ValueChanged<Duration?> onInteraction;

  @override
  State<_ProgressBar> createState() => _ProgressBarState();
}

class _ProgressBarState extends State<_ProgressBar> {
  Duration _target(double dx, double width, Duration duration) => Duration(
      milliseconds: (duration.inMilliseconds * (dx / width))
          .round()
          .clamp(0, duration.inMilliseconds));

  @override
  Widget build(BuildContext context) {
    MdPlayerRebuildDiagnostics.progress();
    return ValueListenableBuilder<_Timeline>(
      valueListenable: widget.adapter.timeline,
      builder: (_, _Timeline timeline, __) => LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final Duration shown = widget.preview ?? timeline.position;
          final double duration = timeline.duration.inMilliseconds.toDouble();
          final double played =
              duration <= 0 ? 0 : (shown.inMilliseconds / duration).clamp(0, 1);
          final int bufferedMs = timeline.buffered.fold<int>(
            0,
            (int value, DurationRange range) => range.end.inMilliseconds > value
                ? range.end.inMilliseconds
                : value,
          );
          final double buffered =
              duration <= 0 ? 0 : (bufferedMs / duration).clamp(0, 1);
          void update(double dx) {
            if (duration <= 0) return;
            widget.onInteraction(
              _target(dx, constraints.maxWidth, timeline.duration),
            );
          }

          return Semantics(
            label: widget.player.labels.progress,
            value: '${_format(shown)} / ${_format(timeline.duration)}',
            slider: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: duration <= 0
                  ? null
                  : (TapDownDetails details) async {
                      final Duration target = _target(
                        details.localPosition.dx,
                        constraints.maxWidth,
                        timeline.duration,
                      );
                      widget.onInteraction(target);
                      await widget.adapter.controller.seekTo(target);
                      if (mounted) widget.onInteraction(null);
                    },
              onHorizontalDragStart: duration <= 0
                  ? null
                  : (DragStartDetails details) =>
                      update(details.localPosition.dx),
              onHorizontalDragUpdate: duration <= 0
                  ? null
                  : (DragUpdateDetails details) =>
                      update(details.localPosition.dx),
              onHorizontalDragEnd: duration <= 0
                  ? null
                  : (_) async {
                      final Duration? target = widget.preview;
                      if (target != null) {
                        await widget.adapter.controller.seekTo(target);
                      }
                      if (mounted) widget.onInteraction(null);
                    },
              child: SizedBox(
                height: 48,
                child: Stack(
                  alignment: Alignment.centerLeft,
                  children: <Widget>[
                    LinearProgressIndicator(
                      value: buffered,
                      minHeight: 4,
                      backgroundColor: widget.player.style.progressBackground,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        widget.player.style.buffered,
                      ),
                    ),
                    LinearProgressIndicator(
                      value: played,
                      minHeight: 4,
                      backgroundColor: Colors.transparent,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        widget.player.style.accentFor(context),
                      ),
                    ),
                    Align(
                      alignment: Alignment(played * 2 - 1, 0),
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: widget.player.style.accentFor(context),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    if (widget.preview != null)
                      Align(
                        alignment: Alignment(played * 2 - 1, -1),
                        child: Text(
                          _format(widget.preview!),
                          style: TextStyle(
                            color: widget.player.style.foreground,
                            fontSize: 11,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SettingsPanel extends StatelessWidget {
  const _SettingsPanel({
    required this.player,
    required this.adapter,
    required this.configuration,
    required this.failure,
  });

  final MdPlayer player;
  final _MdPlayerAdapter adapter;
  final MdPlayerControlsConfiguration configuration;
  final String? failure;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 190, maxWidth: 560),
          child: Material(
            color: player.style.scrim,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(player.labels.speed,
                      style: TextStyle(color: player.style.foreground)),
                  _InlineSpeed(
                    player: player,
                    adapter: adapter,
                    options: configuration.speedOptions,
                  ),
                  if (adapter
                      .controller.value.qualities.isNotEmpty) ...<Widget>[
                    Text(player.labels.quality,
                        style: TextStyle(color: player.style.foreground)),
                    _QualityChoices(player: player, adapter: adapter),
                  ],
                  if (configuration.enableVolume)
                    _VolumeSlider(player: player, adapter: adapter),
                  if (failure != null)
                    Semantics(
                      liveRegion: true,
                      child: Text(failure!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          )),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
}

class _InlineSpeed extends StatelessWidget {
  const _InlineSpeed(
      {required this.player, required this.adapter, required this.options});
  final MdPlayer player;
  final _MdPlayerAdapter adapter;
  final List<double> options;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<_SpeedVolume>(
        valueListenable: adapter.speedVolume,
        builder: (_, _SpeedVolume value, __) => PopupMenuButton<double>(
          tooltip: player.labels.speed,
          initialValue: value.speed,
          onSelected: adapter.controller.setPlaybackSpeed,
          itemBuilder: (_) => <PopupMenuEntry<double>>[
            for (final double speed in options)
              PopupMenuItem<double>(value: speed, child: Text('${speed}x')),
          ],
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text('${value.speed}x',
                style: TextStyle(color: player.style.foreground)),
          ),
        ),
      );
}

class _InlineQuality extends StatelessWidget {
  const _InlineQuality({required this.player, required this.adapter});
  final MdPlayer player;
  final _MdPlayerAdapter adapter;

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<MdPlayerQuality?>(
        valueListenable: adapter.confirmedQuality,
        builder: (_, MdPlayerQuality? quality, __) =>
            PopupMenuButton<MdPlayerQuality>(
          tooltip: player.labels.quality,
          onSelected: adapter.controller.setQuality,
          itemBuilder: (_) => <PopupMenuEntry<MdPlayerQuality>>[
            for (final ({MdPlayerQuality quality, String label}) item
                in _qualityItems(adapter.controller.value.qualities))
              PopupMenuItem<MdPlayerQuality>(
                value: item.quality,
                child: Row(children: <Widget>[
                  SizedBox(
                    width: 24,
                    child: identical(item.quality, quality)
                        ? const Icon(Icons.check, size: 18)
                        : null,
                  ),
                  Text(item.label),
                ]),
              ),
          ],
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              quality?.label ?? adapter.controller.value.qualityLabel,
              style: TextStyle(color: player.style.foreground),
            ),
          ),
        ),
      );
}

class _QualityChoices extends StatelessWidget {
  const _QualityChoices({required this.player, required this.adapter});
  final MdPlayer player;
  final _MdPlayerAdapter adapter;

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<MdPlayerQuality?>(
        valueListenable: adapter.confirmedQuality,
        builder: (_, MdPlayerQuality? selected, __) => Wrap(
          spacing: 8,
          children: <Widget>[
            for (final ({MdPlayerQuality quality, String label}) item
                in _qualityItems(adapter.controller.value.qualities))
              ChoiceChip(
                label: Text(item.label),
                selected: identical(item.quality, selected),
                onSelected: (_) => adapter.controller.setQuality(item.quality),
              ),
          ],
        ),
      );
}

class _VolumeButton extends StatelessWidget {
  const _VolumeButton({required this.player, required this.adapter});
  final MdPlayer player;
  final _MdPlayerAdapter adapter;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<_SpeedVolume>(
        valueListenable: adapter.speedVolume,
        builder: (_, _SpeedVolume value, __) => _ControlButton(
          icon: value.volume == 0 ? player.icons.mute : player.icons.volume,
          label: value.volume == 0 ? player.labels.unmute : player.labels.mute,
          color: player.style.foreground,
          onPressed: adapter.controller.toggleMute,
        ),
      );
}

class _VolumeSlider extends StatelessWidget {
  const _VolumeSlider({required this.player, required this.adapter});
  final MdPlayer player;
  final _MdPlayerAdapter adapter;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<_SpeedVolume>(
        valueListenable: adapter.speedVolume,
        builder: (_, _SpeedVolume value, __) => Semantics(
          label: player.labels.volume,
          child: Slider(
            value: value.volume,
            onChanged: adapter.controller.setVolume,
          ),
        ),
      );
}

class _StatusOverlays extends StatelessWidget {
  const _StatusOverlays({required this.player, required this.adapter});
  final MdPlayer player;
  final _MdPlayerAdapter adapter;

  @override
  Widget build(BuildContext context) => Stack(
        fit: StackFit.expand,
        children: <Widget>[
          ValueListenableBuilder<bool>(
            valueListenable: adapter.resolving,
            builder: (_, bool resolving, __) => resolving
                ? player.loadingBuilder?.call(context, player.labels.loading) ??
                    _Loading(label: player.labels.loading)
                : const SizedBox.shrink(),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: adapter.buffering,
            builder: (_, bool buffering, __) {
              MdPlayerRebuildDiagnostics.buffering();
              return buffering
                  ? _Loading(label: player.labels.buffering)
                  : const SizedBox.shrink();
            },
          ),
          ValueListenableBuilder<MdQualitySwitchState>(
            valueListenable: adapter.quality,
            builder: (_, MdQualitySwitchState state, __) {
              MdPlayerRebuildDiagnostics.quality();
              return state.isSwitching
                  ? _Loading(label: player.labels.switchingQuality)
                  : const SizedBox.shrink();
            },
          ),
          ValueListenableBuilder<String?>(
            valueListenable: adapter.error,
            builder: (_, String? error, __) {
              if (error == null) return const SizedBox.shrink();
              final Future<void> Function() retry = () async {
                final FutureOr<void> Function()? callback = player.onRetry;
                if (callback == null) {
                  await adapter.controller.initialize();
                } else {
                  await callback();
                }
              };
              return player.errorBuilder?.call(
                    context,
                    player.labels.error,
                    retry,
                  ) ??
                  _ModernError(
                    message: player.labels.error,
                    retryLabel: player.labels.retry,
                    onRetry: retry,
                  );
            },
          ),
        ],
      );
}

class _Loading extends StatelessWidget {
  const _Loading({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Center(
        child: Semantics(
          label: label,
          liveRegion: true,
          child: const CircularProgressIndicator(),
        ),
      );
}

class _ModernError extends StatelessWidget {
  const _ModernError(
      {required this.message, required this.retryLabel, required this.onRetry});
  final String message;
  final String retryLabel;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(message, style: const TextStyle(color: Colors.white)),
            const SizedBox(height: 8),
            FilledButton(onPressed: onRetry, child: Text(retryLabel)),
          ],
        ),
      );
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
    this.size = 24,
  });
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onPressed;
  final double size;

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: label,
        iconSize: size,
        color: color,
        onPressed: onPressed,
        icon: Icon(icon, semanticLabel: label),
      );
}

class _LegacyControls extends StatelessWidget {
  const _LegacyControls(
      {required this.controller, required this.onFullscreenPressed});
  final MdPlayerController controller;
  final VoidCallback? onFullscreenPressed;
  static const List<double> _speeds = <double>[0.5, 1, 1.25, 1.5, 2];

  @override
  Widget build(BuildContext context) {
    final MdPlayerValue value = controller.value;
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[Colors.transparent, Colors.black87],
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: <Widget>[
          Expanded(
            child: Center(
              child: IconButton(
                iconSize: 72,
                color: Colors.white,
                icon: Icon(
                    value.isPlaying ? Icons.pause_circle : Icons.play_circle),
                onPressed: value.isPlaying ? controller.pause : controller.play,
              ),
            ),
          ),
          _LegacyScrubber(controller: controller),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 8, 8),
            child: Row(children: <Widget>[
              Text('${_format(value.position)} / ${_format(value.duration)}',
                  style: const TextStyle(color: Colors.white, fontSize: 12)),
              const Spacer(),
              PopupMenuButton<double>(
                tooltip: 'Speed',
                initialValue: value.playbackSpeed,
                onSelected: controller.setPlaybackSpeed,
                itemBuilder: (_) => <PopupMenuEntry<double>>[
                  for (final double speed in _speeds)
                    PopupMenuItem<double>(
                        value: speed, child: Text('${speed}x')),
                ],
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text('${value.playbackSpeed}x',
                      style: const TextStyle(color: Colors.white)),
                ),
              ),
              if (value.qualities.isNotEmpty)
                PopupMenuButton<MdPlayerQuality>(
                  tooltip: 'Quality',
                  onSelected: controller.setQuality,
                  itemBuilder: (_) => <PopupMenuEntry<MdPlayerQuality>>[
                    for (final MdPlayerQuality quality in value.qualities)
                      PopupMenuItem<MdPlayerQuality>(
                          value: quality, child: Text(quality.label)),
                  ],
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(value.qualityLabel,
                        style: const TextStyle(color: Colors.white)),
                  ),
                ),
              if (onFullscreenPressed != null)
                IconButton(
                  color: Colors.white,
                  icon: const Icon(Icons.fullscreen),
                  onPressed: onFullscreenPressed,
                ),
            ]),
          ),
        ],
      ),
    );
  }
}

class _LegacyScrubber extends StatelessWidget {
  const _LegacyScrubber({required this.controller});
  final MdPlayerController controller;

  @override
  Widget build(BuildContext context) {
    final MdPlayerValue value = controller.value;
    final int duration = value.duration.inMilliseconds;
    final int position = value.position.inMilliseconds;
    final int buffered = value.buffered.fold<int>(
        0,
        (int current, DurationRange range) => range.end.inMilliseconds > current
            ? range.end.inMilliseconds
            : current);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: duration <= 0
          ? null
          : (TapDownDetails details) {
              final RenderBox box = context.findRenderObject()! as RenderBox;
              controller.seekTo(Duration(
                milliseconds:
                    (duration * details.localPosition.dx / box.size.width)
                        .round(),
              ));
            },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Stack(children: <Widget>[
          LinearProgressIndicator(
            value: duration <= 0 ? 0 : buffered / duration,
            minHeight: 4,
            backgroundColor: Colors.white24,
            valueColor: const AlwaysStoppedAnimation<Color>(Colors.white38),
          ),
          LinearProgressIndicator(
            value: duration <= 0 ? 0 : position / duration,
            minHeight: 4,
            backgroundColor: Colors.transparent,
            valueColor: const AlwaysStoppedAnimation<Color>(Colors.red),
          ),
        ]),
      ),
    );
  }
}

class _LegacyError extends StatelessWidget {
  const _LegacyError({required this.message, required this.onRetry});
  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white)),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ),
        ),
      );
}

List<({MdPlayerQuality quality, String label})> _qualityItems(
  List<MdPlayerQuality> qualities,
) {
  final List<({MdPlayerQuality quality, int index})> sorted = <({
    MdPlayerQuality quality,
    int index
  })>[
    for (int index = 0; index < qualities.length; index++)
      (quality: qualities[index], index: index),
  ]..sort((a, b) {
      final int resolution =
          _resolution(b.quality.label).compareTo(_resolution(a.quality.label));
      if (resolution != 0) return resolution;
      final int itag =
          (b.quality.videoItag ?? -1).compareTo(a.quality.videoItag ?? -1);
      return itag != 0 ? itag : a.index.compareTo(b.index);
    });
  final Map<String, int> totals = <String, int>{};
  final Map<String, int> seen = <String, int>{};
  for (final item in sorted) {
    totals[item.quality.label] = (totals[item.quality.label] ?? 0) + 1;
  }
  return <({MdPlayerQuality quality, String label})>[
    for (final item in sorted)
      (
        quality: item.quality,
        label: totals[item.quality.label] == 1
            ? item.quality.label
            : '${item.quality.label} ${(seen[item.quality.label] = (seen[item.quality.label] ?? 0) + 1)}',
      ),
  ];
}

int _resolution(String label) =>
    int.tryParse(RegExp(r'(\d+)').firstMatch(label)?.group(1) ?? '') ?? -1;

Duration _clampDuration(Duration value, Duration duration) =>
    value < Duration.zero
        ? Duration.zero
        : value > duration
            ? duration
            : value;

String _format(Duration duration) {
  final int seconds = duration.inSeconds.remainder(60);
  final int minutes = duration.inMinutes.remainder(60);
  final int hours = duration.inHours;
  return hours > 0
      ? '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}'
      : '$minutes:${seconds.toString().padLeft(2, '0')}';
}
