import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'md_player_controller.dart';
import 'md_player_source.dart';

class MdPlayer extends StatefulWidget {
  const MdPlayer({
    super.key,
    required this.controller,
    this.onFullscreenPressed,
  });

  final MdPlayerController controller;
  final VoidCallback? onFullscreenPressed;

  @override
  State<MdPlayer> createState() => _MdPlayerState();
}

class _MdPlayerState extends State<MdPlayer> {
  bool _controlsVisible = true;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  @override
  void didUpdateWidget(MdPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    oldWidget.controller.removeListener(_changed);
    widget.controller.addListener(_changed);
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) {
      setState(() {});
    }
  }

  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
    _scheduleHide();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    if (widget.controller.value.isPlaying) {
      _hideTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) {
          setState(() => _controlsVisible = false);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final MdPlayerValue value = widget.controller.value;
    return AspectRatio(
      aspectRatio: value.aspectRatio,
      child: ColoredBox(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            if (widget.controller.playerId !=
                MdPlayerController.kUninitializedTextureId)
              VideoPlayerPlatform.instance.buildViewWithOptions(
                VideoViewOptions(playerId: widget.controller.playerId),
              ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _toggleControls,
            ),
            if (value.isResolving || value.isBuffering)
              const Center(
                  child: CircularProgressIndicator(color: Colors.white)),
            if (value.hasError)
              _ErrorState(
                message: value.errorDescription!,
                onRetry: widget.controller.initialize,
              ),
            if (_controlsVisible && !value.hasError)
              _Controls(
                controller: widget.controller,
                onFullscreenPressed: widget.onFullscreenPressed,
              ),
          ],
        ),
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.controller,
    required this.onFullscreenPressed,
  });

  static const List<double> _speeds = <double>[0.5, 1, 1.25, 1.5, 2];

  final MdPlayerController controller;
  final VoidCallback? onFullscreenPressed;

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
          _Scrubber(controller: controller),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 8, 8),
            child: Row(
              children: <Widget>[
                Text(
                  '${_format(value.position)} / ${_format(value.duration)}',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
                const Spacer(),
                PopupMenuButton<double>(
                  tooltip: 'Speed',
                  initialValue: value.playbackSpeed,
                  onSelected: controller.setPlaybackSpeed,
                  itemBuilder: (_) => <PopupMenuEntry<double>>[
                    for (final double speed in _speeds)
                      PopupMenuItem<double>(
                        value: speed,
                        child: _CheckedMenuLabel(
                          selected: speed == value.playbackSpeed,
                          label: '${speed}x',
                        ),
                      ),
                  ],
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(
                      '${value.playbackSpeed}x',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ),
                if (value.qualities.isNotEmpty)
                  PopupMenuButton<MdPlayerQuality>(
                    tooltip: 'Quality',
                    onSelected: controller.setQuality,
                    itemBuilder: (_) => <PopupMenuEntry<MdPlayerQuality>>[
                      for (final MdPlayerQuality quality in value.qualities)
                        PopupMenuItem<MdPlayerQuality>(
                          value: quality,
                          child: _CheckedMenuLabel(
                            selected: quality.label == value.qualityLabel,
                            label: quality.label,
                          ),
                        ),
                    ],
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        value.qualityLabel,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                if (onFullscreenPressed != null)
                  IconButton(
                    color: Colors.white,
                    icon: const Icon(Icons.fullscreen),
                    onPressed: onFullscreenPressed,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _format(Duration duration) {
    final int seconds = duration.inSeconds.remainder(60);
    final int minutes = duration.inMinutes.remainder(60);
    final int hours = duration.inHours;
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

class _CheckedMenuLabel extends StatelessWidget {
  const _CheckedMenuLabel({
    required this.selected,
    required this.label,
  });

  final bool selected;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SizedBox(
          width: 24,
          child: selected ? const Icon(Icons.check, size: 18) : null,
        ),
        Text(label),
      ],
    );
  }
}

class _Scrubber extends StatelessWidget {
  const _Scrubber({required this.controller});

  final MdPlayerController controller;

  @override
  Widget build(BuildContext context) {
    final MdPlayerValue value = controller.value;
    final int duration = value.duration.inMilliseconds;
    final int position = value.position.inMilliseconds;
    final int buffered = value.buffered.isEmpty
        ? 0
        : value.buffered
            .map((DurationRange range) => range.end.inMilliseconds)
            .reduce(
              (int a, int b) => a > b ? a : b,
            );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: duration <= 0
          ? null
          : (TapDownDetails details) {
              final RenderBox box = context.findRenderObject()! as RenderBox;
              final double ratio = details.localPosition.dx / box.size.width;
              controller
                  .seekTo(Duration(milliseconds: (duration * ratio).round()));
            },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Stack(
          children: <Widget>[
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
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
