import 'dart:async';
import 'dart:convert';
import 'dart:io';

class RangeHttpServer {
  RangeHttpServer(this.fixtures);

  final Map<String, List<int>> fixtures;
  final Map<String, int> requestsByRole = <String, int>{};
  final Map<String, int> bytesByRole = <String, int>{};
  final Map<String, int> requestsByPath = <String, int>{};
  final Map<String, int> bytesByPath = <String, int>{};
  HttpServer? _server;
  StreamSubscription<HttpRequest>? _requests;
  bool mediaAvailable = true;
  int throttleChunkBytes = 0;
  Duration throttleDelay = Duration.zero;

  Uri get origin =>
      Uri.parse('http://${_server!.address.address}:${_server!.port}');

  Future<void> start({InternetAddress? address, int port = 0}) async {
    _server = await HttpServer.bind(
      address ?? InternetAddress.loopbackIPv4,
      port,
    );
    _requests = _server!.listen(_handle);
  }

  void resetCounters() {
    requestsByRole.clear();
    bytesByRole.clear();
    requestsByPath.clear();
    bytesByPath.clear();
  }

  Map<String, Object> snapshot() => <String, Object>{
        'requestsByRole': requestsByRole,
        'bytesByRole': bytesByRole,
        'requestsByPath': requestsByPath,
        'bytesByPath': bytesByPath,
        'mediaAvailable': mediaAvailable,
      };

  Future<void> close() async {
    await _requests?.cancel();
    await _server?.close(force: true);
    _requests = null;
    _server = null;
  }

  Future<void> _handle(HttpRequest request) async {
    if (request.uri.path.startsWith('/_phase3/')) {
      await _handleControl(request);
      return;
    }
    final List<String> segments = request.uri.pathSegments;
    final String role = segments.isEmpty ? 'unknown' : segments.first;
    final String name = segments.isEmpty ? '' : segments.last;
    final List<int>? fixture = fixtures[name];
    requestsByRole.update(role, (int value) => value + 1, ifAbsent: () => 1);
    requestsByPath.update(
      request.uri.path,
      (int value) => value + 1,
      ifAbsent: () => 1,
    );
    if (!mediaAvailable) {
      request.response.statusCode = HttpStatus.serviceUnavailable;
      await request.response.close();
      return;
    }
    if (fixture == null) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    int start = 0;
    int end = fixture.length - 1;
    final String? range = request.headers.value(HttpHeaders.rangeHeader);
    if (range != null) {
      final RegExpMatch? match =
          RegExp(r'^bytes=(\d+)-(\d*)$').firstMatch(range);
      if (match == null) {
        await _rangeNotSatisfiable(request.response, fixture.length);
        return;
      }
      start = int.parse(match.group(1)!);
      end = match.group(2)!.isEmpty ? end : int.parse(match.group(2)!);
      if (start >= fixture.length || end < start) {
        await _rangeNotSatisfiable(request.response, fixture.length);
        return;
      }
      end = end.clamp(start, fixture.length - 1);
      request.response.statusCode = HttpStatus.partialContent;
      request.response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes $start-$end/${fixture.length}',
      );
    }

    final List<int> body = fixture.sublist(start, end + 1);
    request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    request.response.contentLength = body.length;
    if (request.method == 'HEAD') {
      await request.response.close();
      return;
    }
    if (request.method != 'GET') {
      request.response.statusCode = HttpStatus.methodNotAllowed;
      await request.response.close();
      return;
    }
    final int chunkSize =
        throttleChunkBytes <= 0 ? body.length : throttleChunkBytes;
    for (int offset = 0; offset < body.length; offset += chunkSize) {
      final int limit = (offset + chunkSize).clamp(0, body.length);
      final List<int> chunk = body.sublist(offset, limit);
      request.response.add(chunk);
      await request.response.flush();
      bytesByRole.update(role, (int value) => value + chunk.length,
          ifAbsent: () => chunk.length);
      bytesByPath.update(request.uri.path, (int value) => value + chunk.length,
          ifAbsent: () => chunk.length);
      if (throttleDelay > Duration.zero && limit < body.length) {
        await Future<void>.delayed(throttleDelay);
      }
    }
    await request.response.close();
  }

  Future<void> _handleControl(HttpRequest request) async {
    request.response.headers.contentType = ContentType.json;
    switch (request.uri.path) {
      case '/_phase3/snapshot':
        request.response.write(jsonEncode(snapshot()));
        break;
      case '/_phase3/reset':
        resetCounters();
        request.response.write('{}');
        break;
      case '/_phase3/availability':
        mediaAvailable = request.uri.queryParameters['available'] != 'false';
        request.response.write(jsonEncode(<String, Object>{
          'mediaAvailable': mediaAvailable,
        }));
        break;
      case '/_phase3/throttle':
        throttleChunkBytes =
            int.tryParse(request.uri.queryParameters['chunkBytes'] ?? '') ?? 0;
        throttleDelay = Duration(
          milliseconds:
              int.tryParse(request.uri.queryParameters['delayMs'] ?? '') ?? 0,
        );
        request.response.write('{}');
        break;
      default:
        request.response.statusCode = HttpStatus.notFound;
    }
    await request.response.close();
  }

  Future<void> _rangeNotSatisfiable(HttpResponse response, int length) async {
    response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
    response.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$length');
    await response.close();
  }
}
