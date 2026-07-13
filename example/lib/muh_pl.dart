import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:md_player_android/md_player_android.dart';

class MuhPl extends StatefulWidget {
  const MuhPl({super.key});

  @override
  State<MuhPl> createState() => _MuhPlState();
}

class _MuhPlState extends State<MuhPl> {
  final TextEditingController _urlController = TextEditingController(
    text: 'https://www.youtube.com/watch?v=qy6b7p92YAI',
  );
  MdPlayerController? _controller;
  bool _fullscreen = false;

  @override
  void dispose() {
    _controller?.dispose();
    _urlController.dispose();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
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
    setState(() => _fullscreen = !_fullscreen);
    SystemChrome.setPreferredOrientations(
      _fullscreen
          ? <DeviceOrientation>[DeviceOrientation.portraitUp]
          : <DeviceOrientation>[
              DeviceOrientation.landscapeLeft,
              DeviceOrientation.landscapeRight,
            ],
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
          if (controller != null)
            MdPlayer(
              controller: controller,
              onFullscreenPressed: _toggleFullscreen,
            ),
        ],
      ),
    );
  }
}
