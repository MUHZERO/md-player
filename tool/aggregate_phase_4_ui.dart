import 'dart:convert';
import 'dart:io';

void main(List<String> arguments) {
  if (arguments.length != 2) {
    stderr.writeln('Usage: aggregate_phase_4_ui.dart <report-dir> <count>');
    exitCode = 64;
    return;
  }
  final Directory directory = Directory(arguments.first);
  final int count = int.parse(arguments.last);
  final List<Map<String, dynamic>> runs = <Map<String, dynamic>>[
    for (int i = 1; i <= count; i++)
      jsonDecode(File('${directory.path}/run_$i.json').readAsStringSync())
          as Map<String, dynamic>,
  ];
  final List<dynamic> failures = <dynamic>[
    for (final Map<String, dynamic> run in runs)
      ...(run['failures'] as List<dynamic>? ?? const <dynamic>[]),
  ];
  File('${directory.path}/aggregate.json').writeAsStringSync(jsonEncode(
    <String, Object?>{
      'schemaVersion': 1,
      'repetitions': count,
      'passes': count - failures.length,
      'failures': failures,
      'runs': runs,
    },
  ));
  if (failures.isNotEmpty) exitCode = 1;
}
