import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:md_player_android/md_player_android.dart';

class MuhPl extends StatefulWidget {
  const MuhPl({super.key});

  @override
  State<MuhPl> createState() => _MuhPlState();
}

class _MuhPlState extends State<MuhPl> {
  static const List<DeviceOrientation> _normalOrientations =
      <DeviceOrientation>[DeviceOrientation.portraitUp];
  final TextEditingController _urlController = TextEditingController(
    text: 'https://www.youtube.com/watch?v=qy6b7p92YAI',
  );
  MdPlayerController? _controller;
  bool _fullscreen = false;
  bool _modern = false;
  bool _compact = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations(_normalOrientations);
  }

  @override
  void dispose() {
    _controller?.dispose();
    _urlController.dispose();
    SystemChrome.setPreferredOrientations(_normalOrientations);
    super.dispose();
  }

  Future<void> _load(String url) async {
    await _controller?.dispose();
    final MdPlayerController controller =
        MdPlayerController.network(url, autoPlay: true);
    setState(() => _controller = controller);
    try {
      await controller.initialize();
    } catch (_) {
      if (mounted) {
        setState(() {});
      }
    }
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

  @override
  Widget build(BuildContext context) {
    final MdPlayerController? controller = _controller;
    if (_fullscreen && controller != null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Center(
            child: MdPlayer(
              controller: controller,
              controlsMode: _modern
                  ? MdPlayerControlsMode.modern
                  : MdPlayerControlsMode.legacy,
              title: _modern ? 'Modern fullscreen' : null,
              isFullscreen: true,
              onExitFullscreen: _toggleFullscreen,
              onFullscreenPressed: _toggleFullscreen,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('MD Player')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          TextField(
            controller: _urlController,
            decoration: const InputDecoration(
              labelText: 'YouTube, Vimeo, or direct video URL',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.done,
            onSubmitted: _load,
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () => _load(_urlController.text),
            icon: const Icon(Icons.play_arrow),
            label: const Text('Play'),
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Modern controls (opt-in)'),
            value: _modern,
            onChanged: (bool value) => setState(() => _modern = value),
          ),
          if (_modern)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Compact layout preview'),
              value: _compact,
              onChanged: (bool value) => setState(() => _compact = value),
            ),
          if (controller != null)
            Center(
              child: SizedBox(
                width: _compact ? 420 : double.infinity,
                child: MdPlayer(
                  controller: controller,
                  controlsMode: _modern
                      ? MdPlayerControlsMode.modern
                      : MdPlayerControlsMode.legacy,
                  controlsConfiguration: MdPlayerControlsConfiguration(
                    enableVolume: true,
                  ),
                  labels: const MdPlayerControlsLabels(
                    settings: 'Player options',
                    qualityFailed: 'Quality change failed; playback restored',
                  ),
                  style: const MdPlayerStyle(accent: Colors.amber),
                  title: _modern ? 'Modern controls' : null,
                  subtitle: _modern ? 'Quality, speed, volume, and keys' : null,
                  isFullscreen: false,
                  onEnterFullscreen: _toggleFullscreen,
                  onRetry: () => _load(_urlController.text),
                  onFullscreenPressed: _toggleFullscreen,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
