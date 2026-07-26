import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:md_player_android/md_player_android.dart';

class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key});

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  static const List<DeviceOrientation> _normalOrientations =
      <DeviceOrientation>[DeviceOrientation.portraitUp];
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _videoIdController = TextEditingController();
  MdPlayerController? _controller;
  int _loadOperation = 0;
  bool _fullscreen = false;
  bool _modern = true;
  bool _compact = false;
  bool _autoPlay = true;
  bool _keyboard = true;
  bool _volume = true;
  bool _lock = true;
  bool _customPresentation = true;
  bool _loading = false;
  bool _cacheBusy = false;
  String? _inputError;
  String? _cacheMessage;
  MdPlayerCacheStats? _cacheStats;
  Duration _hideDelay = const Duration(seconds: 3);
  Duration _seekInterval = const Duration(seconds: 10);

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations(_normalOrientations);
  }

  @override
  void dispose() {
    unawaited(_controller?.dispose());
    _urlController.dispose();
    _videoIdController.dispose();
    SystemChrome.setPreferredOrientations(_normalOrientations);
    super.dispose();
  }

  Future<void> _load([String? input]) async {
    final String url = (input ?? _urlController.text).trim();
    final Uri? uri = Uri.tryParse(url);
    if (uri == null ||
        !<String>{'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty) {
      setState(() => _inputError = 'Enter a valid HTTP or HTTPS video URL.');
      return;
    }

    final int operation = ++_loadOperation;
    final MdPlayerController? previous = _controller;
    setState(() {
      _controller = null;
      _inputError = null;
      _loading = true;
    });
    await previous?.dispose();
    if (!mounted || operation != _loadOperation) {
      return;
    }

    final MdPlayerController controller =
        MdPlayerController.network(url, autoPlay: _autoPlay);
    setState(() => _controller = controller);
    try {
      await controller.initialize();
    } catch (_) {
      // The controller exposes a sanitized error through its value.
    }
    if (!mounted || operation != _loadOperation) {
      await controller.dispose();
      return;
    }
    setState(() => _loading = false);
  }

  Future<void> _unload() async {
    final MdPlayerController? controller = _controller;
    ++_loadOperation;
    setState(() {
      _controller = null;
      _loading = false;
    });
    await controller?.dispose();
  }

  void _toggleFullscreen() {
    final bool fullscreen = !_fullscreen;
    setState(() => _fullscreen = fullscreen);
    SystemChrome.setPreferredOrientations(
      fullscreen
          ? <DeviceOrientation>[
              DeviceOrientation.landscapeLeft,
              DeviceOrientation.landscapeRight,
            ]
          : _normalOrientations,
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  MdPlayerControlsConfiguration get _controlsConfiguration =>
      MdPlayerControlsConfiguration(
        hideDelay: _hideDelay,
        seekInterval: _seekInterval,
        enableKeyboard: _keyboard,
        enableVolume: _volume,
        enableLock: _lock,
      );

  Widget _buildPlayer(MdPlayerController controller,
      {required bool fullscreen}) {
    return MdPlayer(
      controller: controller,
      controlsMode:
          _modern ? MdPlayerControlsMode.modern : MdPlayerControlsMode.legacy,
      controlsConfiguration: _controlsConfiguration,
      labels: _customPresentation
          ? const MdPlayerControlsLabels(
              settings: 'Player options',
              qualityFailed: 'Quality change failed; playback restored',
            )
          : const MdPlayerControlsLabels(),
      icons: _customPresentation
          ? const MdPlayerControlsIcons(settings: Icons.tune)
          : const MdPlayerControlsIcons(),
      style: _customPresentation
          ? const MdPlayerStyle(accent: Colors.amber)
          : const MdPlayerStyle(),
      title: _modern ? 'MD Player showcase' : null,
      subtitle: _modern ? 'Direct, YouTube, or Vimeo source' : null,
      topActions: _customPresentation
          ? <Widget>[
              IconButton(
                tooltip: 'Example action',
                onPressed: () => _showMessage('Host top action invoked'),
                icon: const Icon(Icons.info_outline),
              ),
            ]
          : const <Widget>[],
      onClose: _customPresentation
          ? () => _showMessage('Host close callback invoked')
          : null,
      isFullscreen: fullscreen,
      onEnterFullscreen: _toggleFullscreen,
      onExitFullscreen: _toggleFullscreen,
      onRetry: _load,
      onFullscreenPressed: _toggleFullscreen,
      loadingBuilder: _customPresentation
          ? (BuildContext context, String label) => Center(
                child: Semantics(
                  label: label,
                  child: const CircularProgressIndicator(color: Colors.amber),
                ),
              )
          : null,
      errorBuilder: _customPresentation
          ? (
              BuildContext context,
              String message,
              Future<void> Function() retry,
            ) =>
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const Icon(Icons.error_outline, color: Colors.white),
                      const SizedBox(height: 8),
                      Text(
                        message,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white),
                      ),
                      TextButton(onPressed: retry, child: const Text('Retry')),
                    ],
                  ),
                ),
              )
          : null,
    );
  }

  Future<void> _cacheAction(
    Future<void> Function() action,
    String success,
  ) async {
    setState(() {
      _cacheBusy = true;
      _cacheMessage = null;
    });
    try {
      await action();
      final MdPlayerCacheStats stats = await MdPlayerCache.stats();
      if (mounted) {
        setState(() {
          _cacheStats = stats;
          _cacheMessage = success;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _cacheMessage = 'Cache action failed: $error');
      }
    } finally {
      if (mounted) {
        setState(() => _cacheBusy = false);
      }
    }
  }

  Future<void> _configureCache() => _cacheAction(
        () => MdPlayerCache.configure(
          MdPlayerCacheConfiguration(
            maxBytes: 256 * 1024 * 1024,
            directoryName: 'md_player_example_cache',
          ),
        ),
        'Cache enabled with a 256 MiB limit.',
      );

  Future<void> _refreshCache() => _cacheAction(
        () async {},
        'Cache statistics refreshed.',
      );

  Widget _section(String title, List<Widget> children) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final MdPlayerController? controller = _controller;
    if (_fullscreen && controller != null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Center(
            child: _buildPlayer(controller, fullscreen: true),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('MD Player')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Text(
            'Android Media3 playback with legacy and modern Flutter controls.',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 16),
          _section('Load a video', <Widget>[
            TextField(
              controller: _urlController,
              decoration: InputDecoration(
                labelText: 'YouTube, Vimeo, or direct video URL',
                hintText: 'https://example.com/video.mp4',
                helperText: 'Paste a URL you are authorized to play.',
                errorText: _inputError,
                border: const OutlineInputBorder(),
              ),
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.done,
              autocorrect: false,
              onSubmitted: _load,
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _loading ? null : _load,
                    icon: _loading
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.play_arrow),
                    label: Text(_loading ? 'Loading…' : 'Load and play'),
                  ),
                ),
              ],
            ),
          ]),
          _section('Player options', <Widget>[
            SegmentedButton<bool>(
              segments: const <ButtonSegment<bool>>[
                ButtonSegment<bool>(
                  value: true,
                  label: Text('Modern'),
                  icon: Icon(Icons.smart_display),
                ),
                ButtonSegment<bool>(
                  value: false,
                  label: Text('Legacy'),
                  icon: Icon(Icons.ondemand_video),
                ),
              ],
              selected: <bool>{_modern},
              onSelectionChanged: (Set<bool> values) =>
                  setState(() => _modern = values.first),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Autoplay new videos'),
              value: _autoPlay,
              onChanged: (bool value) => setState(() => _autoPlay = value),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Compact layout preview'),
              value: _compact,
              onChanged: (bool value) => setState(() => _compact = value),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Custom labels, icons, colors, and overlays'),
              value: _customPresentation,
              onChanged: (bool value) =>
                  setState(() => _customPresentation = value),
            ),
            if (_modern) ...<Widget>[
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Keyboard shortcuts'),
                value: _keyboard,
                onChanged: (bool value) => setState(() => _keyboard = value),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Volume controls'),
                value: _volume,
                onChanged: (bool value) => setState(() => _volume = value),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Controls lock'),
                value: _lock,
                onChanged: (bool value) => setState(() => _lock = value),
              ),
              DropdownButtonFormField<Duration>(
                initialValue: _seekInterval,
                decoration: const InputDecoration(labelText: 'Seek interval'),
                items: const <DropdownMenuItem<Duration>>[
                  DropdownMenuItem(
                    value: Duration(seconds: 5),
                    child: Text('5 seconds'),
                  ),
                  DropdownMenuItem(
                    value: Duration(seconds: 10),
                    child: Text('10 seconds'),
                  ),
                  DropdownMenuItem(
                    value: Duration(seconds: 30),
                    child: Text('30 seconds'),
                  ),
                ],
                onChanged: (Duration? value) =>
                    setState(() => _seekInterval = value!),
              ),
              DropdownButtonFormField<Duration>(
                initialValue: _hideDelay,
                decoration: const InputDecoration(labelText: 'Auto-hide delay'),
                items: const <DropdownMenuItem<Duration>>[
                  DropdownMenuItem(
                    value: Duration(seconds: 2),
                    child: Text('2 seconds'),
                  ),
                  DropdownMenuItem(
                    value: Duration(seconds: 3),
                    child: Text('3 seconds'),
                  ),
                  DropdownMenuItem(
                    value: Duration(seconds: 5),
                    child: Text('5 seconds'),
                  ),
                ],
                onChanged: (Duration? value) =>
                    setState(() => _hideDelay = value!),
              ),
            ],
          ]),
          if (controller != null)
            _section('Player', <Widget>[
              Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: _compact ? 420 : double.infinity,
                  ),
                  child: _buildPlayer(controller, fullscreen: false),
                ),
              ),
              const SizedBox(height: 12),
              ValueListenableBuilder<MdPlayerValue>(
                valueListenable: controller,
                builder: (
                  BuildContext context,
                  MdPlayerValue value,
                  Widget? child,
                ) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Text(
                        value.hasError
                            ? 'Playback error'
                            : value.isResolving
                                ? 'Resolving source…'
                                : value.isInitialized
                                    ? 'Ready • ${value.qualityLabel}'
                                    : 'Initializing…',
                      ),
                      Wrap(
                        spacing: 8,
                        alignment: WrapAlignment.center,
                        children: <Widget>[
                          IconButton(
                            tooltip: 'Play',
                            onPressed:
                                value.isInitialized ? controller.play : null,
                            icon: const Icon(Icons.play_arrow),
                          ),
                          IconButton(
                            tooltip: 'Pause',
                            onPressed:
                                value.isInitialized ? controller.pause : null,
                            icon: const Icon(Icons.pause),
                          ),
                          IconButton(
                            tooltip: 'Seek backward',
                            onPressed: value.isInitialized
                                ? () => controller.seekTo(
                                      value.position - _seekInterval,
                                    )
                                : null,
                            icon: const Icon(Icons.replay_10),
                          ),
                          IconButton(
                            tooltip: 'Seek forward',
                            onPressed: value.isInitialized
                                ? () => controller.seekTo(
                                      value.position + _seekInterval,
                                    )
                                : null,
                            icon: const Icon(Icons.forward_10),
                          ),
                          IconButton(
                            tooltip: value.volume == 0 ? 'Unmute' : 'Mute',
                            onPressed: value.isInitialized
                                ? controller.toggleMute
                                : null,
                            icon: Icon(
                              value.volume == 0
                                  ? Icons.volume_off
                                  : Icons.volume_up,
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: <Widget>[
                          const Icon(Icons.volume_down),
                          Expanded(
                            child: Slider(
                              value: value.volume,
                              onChanged: value.isInitialized
                                  ? controller.setVolume
                                  : null,
                            ),
                          ),
                          Text('${(value.volume * 100).round()}%'),
                        ],
                      ),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: DropdownButtonFormField<double>(
                              key: ValueKey<double>(value.playbackSpeed),
                              initialValue: value.playbackSpeed,
                              decoration:
                                  const InputDecoration(labelText: 'Speed'),
                              items: const <double>[0.5, 1, 1.25, 1.5, 2]
                                  .map(
                                    (double speed) => DropdownMenuItem<double>(
                                      value: speed,
                                      child: Text('${speed}×'),
                                    ),
                                  )
                                  .toList(),
                              onChanged: value.isInitialized
                                  ? (double? speed) =>
                                      controller.setPlaybackSpeed(speed!)
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonFormField<MdPlayerQuality>(
                              key: ValueKey<MdPlayerQuality?>(
                                controller.confirmedQuality,
                              ),
                              initialValue: controller.confirmedQuality,
                              decoration:
                                  const InputDecoration(labelText: 'Quality'),
                              items: value.qualities
                                  .map(
                                    (MdPlayerQuality quality) =>
                                        DropdownMenuItem<MdPlayerQuality>(
                                      value: quality,
                                      child: Text(quality.label),
                                    ),
                                  )
                                  .toList(),
                              onChanged: value.isInitialized
                                  ? (MdPlayerQuality? quality) {
                                      if (quality != null) {
                                        controller.setQuality(quality);
                                      }
                                    }
                                  : null,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _unload,
                        icon: const Icon(Icons.close),
                        label: const Text('Unload player'),
                      ),
                    ],
                  );
                },
              ),
            ]),
          _section('Optional Media3 cache', <Widget>[
            const Text(
              'Caching is disabled by default. Configure it before loading a '
              'video. Clear, disable, and removal can be rejected while a '
              'player holds an active cache lease.',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                FilledButton.tonal(
                  onPressed: _cacheBusy ? null : _configureCache,
                  child: const Text('Enable 256 MiB cache'),
                ),
                OutlinedButton(
                  onPressed: _cacheBusy ? null : _refreshCache,
                  child: const Text('Refresh stats'),
                ),
                OutlinedButton(
                  onPressed: _cacheBusy
                      ? null
                      : () => _cacheAction(
                            MdPlayerCache.disable,
                            'Cache disabled for future players.',
                          ),
                  child: const Text('Disable'),
                ),
                OutlinedButton(
                  onPressed: _cacheBusy || controller != null
                      ? null
                      : () => _cacheAction(
                            MdPlayerCache.clear,
                            'Cache cleared.',
                          ),
                  child: const Text('Clear'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _videoIdController,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Video ID for targeted cache removal',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _cacheBusy ||
                      controller != null ||
                      _videoIdController.text.trim().isEmpty
                  ? null
                  : () => _cacheAction(
                        () => MdPlayerCache.removeVideo(
                          _videoIdController.text.trim(),
                        ),
                        'Cached video resources removed.',
                      ),
              child: const Text('Remove video from cache'),
            ),
            if (_cacheStats case final MdPlayerCacheStats stats) ...<Widget>[
              const SizedBox(height: 12),
              Text(
                '${stats.enabled ? 'Enabled' : 'Disabled'} • '
                '${stats.currentBytes} / ${stats.maxBytes} bytes • '
                '${stats.cachedResources} resources\n'
                'Cache reads: ${stats.cacheReadBytes} bytes • '
                'Upstream reads: ${stats.upstreamReadBytes} bytes',
              ),
            ],
            if (_cacheMessage != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(_cacheMessage!),
            ],
          ]),
        ],
      ),
    );
  }
}
