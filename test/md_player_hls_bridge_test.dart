import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:md_player_android/src/md_player_hls_bridge.dart';

Uint8List _box(String type, List<int> payload) {
  final ByteData header = ByteData(8)..setUint32(0, payload.length + 8);
  return Uint8List.fromList(
      <int>[...header.buffer.asUint8List(0, 4), ...type.codeUnits, ...payload]);
}

/// ftyp + moov + a version-0 sidx with two segments (2 s and 1.5 s).
Uint8List _stream() {
  final ByteData sidx = ByteData(44)
    ..setUint32(0, 0) // version 0, flags
    ..setUint32(4, 1) // reference_ID
    ..setUint32(8, 1000) // timescale
    ..setUint32(12, 0) // earliest presentation time
    ..setUint32(16, 10) // first_offset
    ..setUint16(22, 2) // reference_count
    ..setUint32(24, 5000)
    ..setUint32(28, 2000)
    ..setUint32(36, 3000)
    ..setUint32(40, 1500);
  return Uint8List.fromList(<int>[
    ..._box('ftyp', List<int>.filled(16, 0)),
    ..._box('moov', List<int>.filled(32, 0)),
    ..._box('sidx', sidx.buffer.asUint8List()),
  ]);
}

void main() {
  test('sidx segments follow the index and its first offset', () {
    final MdSidx sidx = MdSidx.find(_stream())!;
    expect(sidx.boxStart, 64);
    expect(sidx.boxEnd, 116);
    expect(sidx.segments, <(int, int, double)>[
      (126, 5000, 2.0),
      (5126, 3000, 1.5),
    ]);
    expect(MdSidx.find(Uint8List.fromList(_stream().sublist(0, 80))), isNull);
    expect(MdSidx.endOf(Uint8List.fromList(_stream().sublist(0, 80))), 116);
  });

  test('a video/audio pair becomes HLS with an alternate audio rendition',
      () async {
    final List<String> ranges = <String>[];
    final MdPlayerHlsBridge bridge = MdPlayerHlsBridge(
      httpClient: MockClient((http.Request request) async {
        ranges.add('${request.url.path} ${request.headers['range']}');
        return http.Response.bytes(_stream(), 206);
      }),
    );

    final String master = await bridge.register(
      videoUrl: 'https://media.test/video',
      audioUrl: 'https://media.test/audio',
    );

    expect(ranges..sort(), <String>[
      '/audio bytes=0-65535',
      '/video bytes=0-65535',
    ]);
    final Uri uri = Uri.parse(master);
    expect(uri.host, '127.0.0.1');
    final String id = uri.pathSegments.first;
    expect(bridge.playlist('$id/video.m3u8'), '''
#EXTM3U
#EXT-X-VERSION:7
#EXT-X-PLAYLIST-TYPE:VOD
#EXT-X-TARGETDURATION:2
#EXT-X-INDEPENDENT-SEGMENTS
#EXT-X-MAP:URI="https://media.test/video",BYTERANGE="64@0"
#EXTINF:2.000000,
#EXT-X-BYTERANGE:5000@126
https://media.test/video
#EXTINF:1.500000,
#EXT-X-BYTERANGE:3000@5126
https://media.test/video
#EXT-X-ENDLIST
''');

    final HttpClient client = HttpClient();
    final HttpClientResponse response =
        await (await client.getUrl(uri)).close();
    final String body = await response.transform(utf8.decoder).join();
    client.close();
    expect(response.statusCode, 200);
    expect(body, contains('TYPE=AUDIO,GROUP-ID="audio"'));
    expect(body, contains('URI="audio.m3u8"'));
    expect(body, contains('BANDWIDTH=40000,AUDIO="audio"\nvideo.m3u8'));
  });

  test('a stream without sidx is rejected', () async {
    final MdPlayerHlsBridge bridge = MdPlayerHlsBridge(
      httpClient: MockClient((_) async =>
          http.Response.bytes(_box('ftyp', List<int>.filled(16, 0)), 206)),
    );
    await expectLater(
      bridge.register(videoUrl: 'https://v.test', audioUrl: 'https://a.test'),
      throwsStateError,
    );
  });
}
