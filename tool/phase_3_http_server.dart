import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../test/support/range_http_server.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    stderr.writeln('Usage: phase_3_http_server.dart <fixture-directory>');
    exitCode = 64;
    return;
  }
  final Directory directory = Directory(arguments.single);
  final Map<String, List<int>> fixtures = <String, List<int>>{};
  for (final String name in <String>[
    'audio.m4a',
    'low.mp4',
    'high.mp4',
    'muxed.mp4',
    'invalid.mp4',
  ]) {
    fixtures[name] = await File('${directory.path}/$name').readAsBytes();
  }
  final RangeHttpServer server = RangeHttpServer(fixtures);
  await server.start(address: InternetAddress.anyIPv4);
  stdout.writeln('PHASE_3_SERVER=${jsonEncode(<String, Object>{
        'port': server.origin.port,
      })}');
  final Completer<void> done = Completer<void>();
  final List<StreamSubscription<ProcessSignal>> signals =
      <StreamSubscription<ProcessSignal>>[
    ProcessSignal.sigint.watch().listen((_) {
      if (!done.isCompleted) done.complete();
    }),
    ProcessSignal.sigterm.watch().listen((_) {
      if (!done.isCompleted) done.complete();
    }),
  ];
  await done.future;
  for (final StreamSubscription<ProcessSignal> signal in signals) {
    await signal.cancel();
  }
  await server.close();
}
