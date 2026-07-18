import 'dart:io';

import 'package:flutter/services.dart';
import 'package:md_player_android/md_player_android.dart';
import 'package:path_provider/path_provider.dart';

const String phase21AssetRoot = 'assets/phase_2_1';

class Phase21SourceResolver extends MdPlayerSourceResolver {
  final Map<String, String> _files = <String, String>{};

  @override
  Future<MdPlayerSource> resolve(String input) async {
    if (input == 'muxed') {
      return MdPlayerSource(videoUrl: await muxedUri());
    }
    final String audio = await _copy('audio.m4a');
    final MdPlayerQuality low = MdPlayerQuality(
      label: '180p',
      videoUrl: await _copy('low.mp4'),
      audioUrl: audio,
    );
    final MdPlayerQuality high = MdPlayerQuality(
      label: '360p',
      videoUrl: await _copy('high.mp4'),
      audioUrl: audio,
    );
    return MdPlayerSource(
      videoUrl: low.videoUrl,
      audioUrl: audio,
      qualityLabel: low.label,
      qualities: <MdPlayerQuality>[low, high],
    );
  }

  Future<MdPlayerQuality> invalidQuality() async => MdPlayerQuality(
        label: 'invalid',
        videoUrl: await _copy('invalid.mp4'),
        audioUrl: await _copy('audio.m4a'),
      );

  Future<String> muxedUri() => _copy('muxed.mp4');

  Future<String> _copy(String name) async {
    if (_files[name] case final String path) return path;
    final ByteData data = await rootBundle.load('$phase21AssetRoot/$name');
    final Directory directory = await getTemporaryDirectory();
    final File file = File('${directory.path}/phase_2_1_$name');
    await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
    return _files[name] = file.uri.toString();
  }
}
