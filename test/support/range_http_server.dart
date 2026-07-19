import 'dart:async';
import 'dart:io';

class RangeHttpServer {
  RangeHttpServer(this.fixtures);

  final Map<String, List<int>> fixtures;
  final Map<String, int> requestsByRole = <String, int>{};
  final Map<String, int> bytesByRole = <String, int>{};
  HttpServer? _server;
  StreamSubscription<HttpRequest>? _requests;

  Uri get origin =>
      Uri.parse('http://${_server!.address.address}:${_server!.port}');

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _requests = _server!.listen(_handle);
  }

  Future<void> close() async {
    await _requests?.cancel();
    await _server?.close(force: true);
    _requests = null;
    _server = null;
  }

  Future<void> _handle(HttpRequest request) async {
    final List<String> segments = request.uri.pathSegments;
    final String role = segments.isEmpty ? 'unknown' : segments.first;
    final String name = segments.isEmpty ? '' : segments.last;
    final List<int>? fixture = fixtures[name];
    requestsByRole.update(role, (int value) => value + 1, ifAbsent: () => 1);
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
    request.response.add(body);
    bytesByRole.update(role, (int value) => value + body.length,
        ifAbsent: () => body.length);
    await request.response.close();
  }

  Future<void> _rangeNotSatisfiable(HttpResponse response, int length) async {
    response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
    response.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$length');
    await response.close();
  }
}
