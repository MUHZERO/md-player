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

  test('range server supports HEAD, open ranges, query reuse and controls',
      () async {
    final RangeHttpServer server = RangeHttpServer(<String, List<int>>{
      'fixture.bin': List<int>.generate(10, (int index) => index),
    });
    final HttpClient client = HttpClient();
    await server.start();
    try {
      final HttpClientRequest head =
          await client.headUrl(server.origin.resolve('/video/fixture.bin'));
      final HttpClientResponse headResponse = await head.close();
      expect(headResponse.statusCode, HttpStatus.ok);
      expect(headResponse.contentLength, 10);
      expect(await headResponse.toList(), isEmpty);

      final HttpClientRequest open = await client.getUrl(
        server.origin.resolve('/video/fixture.bin?token=changed'),
      );
      open.headers.set(HttpHeaders.rangeHeader, 'bytes=7-');
      final HttpClientResponse partial = await open.close();
      expect(partial.statusCode, HttpStatus.partialContent);
      expect(partial.headers.value(HttpHeaders.contentRangeHeader),
          'bytes 7-9/10');
      expect(
        await partial.expand((List<int> value) => value).toList(),
        <int>[7, 8, 9],
      );
      expect(server.requestsByPath, <String, int>{'/video/fixture.bin': 2});
      expect(server.bytesByPath, <String, int>{'/video/fixture.bin': 3});

      final HttpClientResponse unavailable = await (await client.getUrl(
        server.origin.resolve('/_phase3/availability?available=false'),
      ))
          .close();
      await unavailable.drain<void>();
      final HttpClientResponse rejected = await (await client.getUrl(
        server.origin.resolve('/video/fixture.bin'),
      ))
          .close();
      expect(rejected.statusCode, HttpStatus.serviceUnavailable);
      await rejected.drain<void>();

      final HttpClientResponse reset = await (await client.getUrl(
        server.origin.resolve('/_phase3/reset'),
      ))
          .close();
      await reset.drain<void>();
      expect(server.requestsByPath, isEmpty);
      expect(server.bytesByPath, isEmpty);
    } finally {
      client.close(force: true);
      await server.close();
    }
  });

  test('range server restarts on a different ephemeral port', () async {
    final RangeHttpServer server = RangeHttpServer(<String, List<int>>{
      'fixture.bin': <int>[1]
    });
    await server.start();
    final int first = server.origin.port;
    await server.close();
    await server.start();
    expect(server.origin.port, isNot(first));
    await server.close();
  });
}
