import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import 'mini_controller.dart';

class MuhPl extends StatefulWidget {
  const MuhPl({super.key});

  @override
  State<MuhPl> createState() => _MuhPlState();
}

class _MuhPlState extends State<MuhPl> {
  MiniController? _controller;
  bool loading = true;
  List<Map<String, String>> videoLinks = [];
  String audioUrl = '';
  bool isFullScreen = false;

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> getLinks(String videoUrl) async {
    final yt = YoutubeExplode(); // Initialize YoutubeExplode

    try {
      var videoId = VideoId(videoUrl);
      var manifest = await yt.videos.streamsClient.getManifest(videoId);

      // Clear the existing list of video links
      videoLinks.clear();

      List<String> addedQualities = [];
      // Populate video links
      for (var videoStream in manifest.videoOnly) {
        String quality = videoStream.qualityLabel;

        if (!addedQualities.contains(quality)) {
          // Add the quality to the Set
          setState(() {
            addedQualities.add(quality);
            // Add the video link to the list
            videoLinks.add({
              'url': videoStream.url.toString(),
              'quality': quality,
            });
          });
        }
      }

      // Get the first available audio URL

      // Update the loading state
      setState(() {
        loading = false;
        audioUrl = manifest.audioOnly.first.url.toString();
        changeUrl(videoLinks.last['url']!, audioUrl);
      });
    } catch (e) {
      debugPrint('Error: $e');
    } finally {
      yt.close();
    }
  }

  Future<void> changeUrl(String url, String audio) async {
    if (_controller != null) {
      await _controller!.dispose();
    }

    setState(() {
      _controller = MiniController.network(url, audio);
    });

    _controller!.addListener(() {
      setState(() {});
    });

    return _controller!.initialize();
  }

  String? _validateRtspUrl(String? value) {
    if (value == null || !value.startsWith('http')) {
      return 'Enter a valid http URL';
    }
    return null;
  }

  void _toggleFullScreen() {
    setState(() {
      isFullScreen = !isFullScreen;
      if (isFullScreen) {
        // Set landscape mode
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      } else {
        // Set portrait mode
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
        ]);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Scaffold(
        body: isFullScreen
            ? Scaffold(
                backgroundColor: Colors.black,
                body: Stack(
                  alignment: Alignment.bottomCenter,
                  children: [
                    Center(
                      child: AspectRatio(
                        aspectRatio: _controller?.value.aspectRatio ?? 16 / 9,
                        child: VideoPlayer(_controller!),
                      ),
                    ),
                    _ControlsOverlay(
                      controller: _controller!,
                      qualities: videoLinks,
                      onFullScreenPressed: _toggleFullScreen,
                    ),
                    VideoProgressIndicator(_controller!),
                    Positioned(
                      top: 40,
                      left: 16,
                      child: IconButton(
                        icon: Icon(Icons.close, color: Colors.white, size: 30),
                        onPressed: () {
                          setState(() {
                            isFullScreen = false;
                          });
                        },
                      ),
                    ),
                  ],
                ),
              )
            : SingleChildScrollView(
                child: Column(
                  children: <Widget>[
                    Container(padding: const EdgeInsets.only(top: 20.0)),
                    const Text('With YT streaming'),
                    Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: TextFormField(
                        controller: TextEditingController(
                            text:
                                'https://www.youtube.com/watch?v=qy6b7p92YAI'),
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        decoration:
                            const InputDecoration(label: Text('http URL')),
                        validator: _validateRtspUrl,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (String value) {
                          if (_validateRtspUrl(value) == null) {
                            getLinks(value);
                            setState(() {
                              loading = true;
                            });
                          } else {
                            setState(() {
                              _controller?.dispose();
                              _controller = null;
                            });
                          }
                        },
                      ),
                    ),
                    if (_controller != null)
                      Container(
                        padding: const EdgeInsets.all(20),
                        child: AspectRatio(
                          aspectRatio: _controller!.value.aspectRatio,
                          child: Stack(
                            alignment: Alignment.bottomCenter,
                            children: <Widget>[
                              VideoPlayer(_controller!),
                              _ControlsOverlay(
                                controller: _controller!,
                                qualities: videoLinks,
                                onFullScreenPressed: _toggleFullScreen,
                              ),
                              VideoProgressIndicator(_controller!),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _ControlsOverlay extends StatefulWidget {
  final List<Map<String, String>> qualities;
  final VoidCallback onFullScreenPressed;
  const _ControlsOverlay({
    required this.controller,
    required this.qualities,
    required this.onFullScreenPressed,
  });

  static const List<double> _examplePlaybackRates = <double>[
    0.25,
    0.5,
    1.0,
    1.5,
    2.0,
    3.0,
    5.0,
    10.0,
  ];

  final MiniController controller;

  @override
  State<_ControlsOverlay> createState() => _ControlsOverlayState();
}

class _ControlsOverlayState extends State<_ControlsOverlay> {
  String selectedQ = 'auto';
  double selectedS = 1.0;
  bool _controlsVisible = true;
  late Timer _hideControlsTimer;
  late Timer _showControlsTimer;
  @override
  void initState() {
    super.initState();
    selectedQ = widget.qualities.last['quality'] ?? 'auto';

    _hideControlsTimer = Timer.periodic(
      Duration(seconds: 5),
      (timer) {
        if (widget.controller.value.isPlaying) {
          setState(() {
            _controlsVisible = false;
          });
        }
      },
    );
  }

  @override
  void dispose() {
    _hideControlsTimer.cancel();
    _showControlsTimer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        Visibility(
          visible: _controlsVisible,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 50),
            reverseDuration: const Duration(milliseconds: 200),
            child: widget.controller.value.isPlaying
                ? ColoredBox(
                    color: Colors.black26,
                    child: Center(
                      child: Icon(
                        Icons.pause,
                        color: Colors.white,
                        size: 60.0,
                        semanticLabel: 'Play',
                      ),
                    ),
                  )
                : widget.controller.value.isBuffering
                    ? Center(
                        child: CircularProgressIndicator(
                          color: Colors.white,
                        ),
                      )
                    : const ColoredBox(
                        color: Colors.black26,
                        child: Center(
                          child: Icon(
                            Icons.play_arrow,
                            color: Colors.white,
                            size: 60.0,
                            semanticLabel: 'Play',
                          ),
                        ),
                      ),
          ),
        ),
        GestureDetector(
          onTap: () {
            if (_controlsVisible) {
              widget.controller.value.isPlaying
                  ? widget.controller.pause()
                  : widget.controller.play();
            }
            setState(() {
              _controlsVisible = true;
            });
            // Hide the controls after 3 seconds of showing them
            _showControlsTimer = Timer(Duration(seconds: 5), () {
              setState(() {
                _controlsVisible = false;
              });
            });
          },
        ),
        Positioned(
          bottom: 8,
          child: Visibility(
            visible: _controlsVisible,
            child: PopupMenuButton<double>(
              initialValue: widget.controller.value.playbackSpeed,
              tooltip: 'السرعة',
              onSelected: (double speed) {
                widget.controller.setPlaybackSpeed(speed);
                setState(() {
                  selectedS = speed;
                });
              },
              itemBuilder: (BuildContext context) {
                return <PopupMenuItem<double>>[
                  for (final double speed
                      in _ControlsOverlay._examplePlaybackRates)
                    PopupMenuItem<double>(
                      value: speed,
                      child: Row(
                        children: [
                          speed == selectedQ
                              ? Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8.0),
                                  child: Icon(
                                    Icons.check,
                                    color: Colors.black,
                                  ),
                                )
                              : SizedBox(),
                          Text('${speed}x'),
                        ],
                      ),
                    )
                ];
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: 16,
                ),
                child: Text(
                  '${widget.controller.value.playbackSpeed}x',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          bottom: 4,
          right: 0,
          child: Visibility(
            visible: _controlsVisible,
            child: PopupMenuButton<String>(
              initialValue: widget.controller.value.qualityUrl,
              tooltip: 'Quality',
              onSelected: (String url) {
                // Update the selected quality URL in the controller
                widget.controller.setQualityUrl(url);
                setState(() {
                  selectedQ = widget.qualities.where((test) {
                        return test['url']! == url;
                      }).first['quality'] ??
                      'auto';
                });
              },
              itemBuilder: (BuildContext context) {
                return <PopupMenuItem<String>>[
                  for (final quality in widget.qualities)
                    PopupMenuItem<String>(
                      value: quality['url']!,
                      child: Row(
                        children: [
                          quality['quality']! == selectedQ
                              ? Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8.0),
                                  child: Icon(
                                    Icons.check,
                                    color: Colors.black,
                                  ),
                                )
                              : SizedBox(),
                          Text(quality['quality']!),
                        ],
                        mainAxisAlignment: MainAxisAlignment.end,
                      ),
                    ),
                ];
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: 16,
                ),
                child: Icon(
                  Icons.settings,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
        Positioned(
          top: 8,
          right: 8,
          child: IconButton(
            icon: Icon(Icons.fullscreen, color: Colors.white, size: 30),
            onPressed: widget.onFullScreenPressed,
          ),
        ),
      ],
    );
  }
}
