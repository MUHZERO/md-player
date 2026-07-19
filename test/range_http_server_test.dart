import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/range_http_server.dart';

void main() {
  test('range server reports complete and partial responses by role', () async {
    final RangeHttpServer server = RangeHttpServer(<String, List<int>>{
      'fixture.bin': List<int>.generate(10, (int index) => index),
    });
    final HttpClient client = HttpClient();
    await server.start();
    try {
      final HttpClientResponse complete = await (await client
              .getUrl(server.origin.resolve('/video/fixture.bin')))
          .close();
      expect(complete.statusCode, HttpStatus.ok);
      expect(complete.headers.value(HttpHeaders.acceptRangesHeader), 'bytes');
      expect(complete.contentLength, 10);
      expect(
          await complete.fold<List<int>>(
              <int>[], (List<int> a, List<int> b) => a..addAll(b)),
          List<int>.generate(10, (int index) => index));

      final HttpClientRequest request =
          await client.getUrl(server.origin.resolve('/audio/fixture.bin'));
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=2-5');
      final HttpClientResponse partial = await request.close();
      expect(partial.statusCode, HttpStatus.partialContent);
      expect(partial.headers.value(HttpHeaders.contentRangeHeader),
          'bytes 2-5/10');
      expect(partial.contentLength, 4);
      expect(
          await partial.fold<List<int>>(
              <int>[], (List<int> a, List<int> b) => a..addAll(b)),
          <int>[2, 3, 4, 5]);

      expect(server.requestsByRole, <String, int>{'video': 1, 'audio': 1});
      expect(server.bytesByRole, <String, int>{'video': 10, 'audio': 4});
    } finally {
      client.close(force: true);
      await server.close();
    }
  });

  test('range server rejects invalid ranges', () async {
    final RangeHttpServer server = RangeHttpServer(<String, List<int>>{
      'fixture.bin': <int>[1, 2, 3],
    });
    final HttpClient client = HttpClient();
    await server.start();
    try {
      final HttpClientRequest request =
          await client.getUrl(server.origin.resolve('/video/fixture.bin'));
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=9-10');
      final HttpClientResponse response = await request.close();
      expect(response.statusCode, HttpStatus.requestedRangeNotSatisfiable);
      expect(
          response.headers.value(HttpHeaders.contentRangeHeader), 'bytes */3');
      await response.drain<void>();
    } finally {
      client.close(force: true);
      await server.close();
    }
  });
}
