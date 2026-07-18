import 'dart:convert';
import 'dart:io';

void main(List<String> arguments) {
  if (arguments.length != 2) {
    stderr.writeln('Usage: aggregate_phase_2_1.dart <report-dir> <count>');
    exitCode = 64;
    return;
  }
  final Directory directory = Directory(arguments[0]);
  final int count = int.parse(arguments[1]);
  final List<Map<String, dynamic>> runs = <Map<String, dynamic>>[
    for (int i = 1; i <= count; i++)
      jsonDecode(File('${directory.path}/run_$i.json').readAsStringSync())
          as Map<String, dynamic>,
  ];
  final List<Map<String, dynamic>> operations = <Map<String, dynamic>>[];
  for (int run = 0; run < runs.length; run++) {
    final Map<String, dynamic> diagnostics =
        runs[run]['diagnostics'] as Map<String, dynamic>;
    for (final Object? player in <Object?>[
      ...diagnostics['players'] as List<dynamic>,
      ...diagnostics['disposedPlayers'] as List<dynamic>,
    ]) {
      for (final Object? operation
          in (player! as Map<String, dynamic>)['operations'] as List<dynamic>) {
        operations.add(<String, dynamic>{
          'run': run + 1,
          ...(operation! as Map<String, dynamic>),
        });
      }
    }
  }

  final Map<String, List<num>> durations = <String, List<num>>{
    'requestToAcceptance': <num>[],
    'acceptanceToReady': <num>[],
    'readyToFirstFrame': <num>[],
    'firstFrameToCompletion': <num>[],
    'requestToCompletion': <num>[],
    'rollback': <num>[],
  };
  for (final Map<String, dynamic> operation in operations) {
    void add(String phase, String start, String end) {
      if (operation[start] is num && operation[end] is num) {
        durations[phase]!
            .add((operation[end] as num) - (operation[start] as num));
      }
    }

    add('requestToAcceptance', 'requestNanos', 'acceptanceNanos');
    add('acceptanceToReady', 'acceptanceNanos', 'readyNanos');
    add('readyToFirstFrame', 'readyNanos', 'firstFrameNanos');
    add('firstFrameToCompletion', 'firstFrameNanos', 'completionNanos');
    add('requestToCompletion', 'requestNanos', 'completionNanos');
    add('rollback', 'rollbackStartedNanos', 'completionNanos');
  }

  final Map<String, dynamic> aggregate = <String, dynamic>{
    'schemaVersion': 1,
    'repetitions': count,
    'failures': <Object?>[
      for (int run = 0; run < runs.length; run++)
        for (final Object? failure in runs[run]['failures'] as List<dynamic>)
          <String, dynamic>{
            'run': run + 1,
            ...(failure! as Map<String, dynamic>),
          },
    ],
    'operationCount': operations.length,
    'operations': operations,
    'statistics': durations.map(
      (String phase, List<num> values) =>
          MapEntry<String, dynamic>(phase, _summary(values)),
    ),
    'audioCapture': false,
    'intervalTerminology': 'non-playing intervals',
  };
  File('${directory.path}/aggregate.json')
      .writeAsStringSync('${jsonEncode(aggregate)}\n');
}

Map<String, dynamic> _summary(List<num> values) {
  values.sort();
  if (values.isEmpty) return <String, dynamic>{'sampleCount': 0};
  final int middle = values.length ~/ 2;
  return <String, dynamic>{
    'sampleCount': values.length,
    'minNanos': values.first,
    'medianNanos': values.length.isOdd
        ? values[middle]
        : (values[middle - 1] + values[middle]) / 2,
    'maxNanos': values.last,
    if (values.length >= 20)
      'p95Nanos': values[(values.length * .95).ceil() - 1],
  };
}
