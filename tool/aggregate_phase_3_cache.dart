import 'dart:convert';
import 'dart:io';

void main(List<String> arguments) {
  if (arguments.length != 2) {
    stderr.writeln('Usage: aggregate_phase_3_cache.dart <report-dir> <count>');
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
  final List<Map<String, dynamic>> records = <Map<String, dynamic>>[
    for (final Map<String, dynamic> run in runs)
      for (final dynamic record in run['records'] as List<dynamic>)
        record as Map<String, dynamic>,
  ];
  final Map<String, List<Map<String, dynamic>>> grouped =
      <String, List<Map<String, dynamic>>>{};
  for (final Map<String, dynamic> record in records) {
    grouped
        .putIfAbsent(
            record['scenario'] as String, () => <Map<String, dynamic>>[])
        .add(record);
  }
  final Map<String, dynamic> aggregate = <String, dynamic>{
    'schemaVersion': 1,
    'repetitions': count,
    'passes':
        records.where((record) => record['terminalState'] == 'passed').length,
    'failures':
        records.where((record) => record['terminalState'] == 'failed').length,
    'timeouts':
        records.where((record) => record['terminalState'] == 'timeout').length,
    'scenarios': grouped.map((String name, List<Map<String, dynamic>> values) =>
        MapEntry<String, dynamic>(name, _aggregate(values))),
    'rawRecords': records,
  };
  File('${directory.path}/aggregate.json')
      .writeAsStringSync('${jsonEncode(aggregate)}\n');
  if (aggregate['failures'] != 0 || aggregate['timeouts'] != 0) exitCode = 1;
}

Map<String, dynamic> _aggregate(List<Map<String, dynamic>> records) {
  final List<num> durations = <num>[
    for (final Map<String, dynamic> record in records)
      record['durationMillis'] as num,
  ]..sort();
  int sumNested(String outer, String inner) =>
      records.fold<int>(0, (int total, record) {
        final Map<String, dynamic>? values =
            record[outer] as Map<String, dynamic>?;
        final dynamic value = values?[inner];
        if (value is num) return total + value.toInt();
        if (value is Map)
          return total +
              value.values
                  .whereType<num>()
                  .fold<int>(0, (a, b) => a + b.toInt());
        return total;
      });
  final int middle = durations.length ~/ 2;
  return <String, dynamic>{
    'totalRepetitions': records.length,
    'passes':
        records.where((record) => record['terminalState'] == 'passed').length,
    'failures':
        records.where((record) => record['terminalState'] == 'failed').length,
    'timeouts':
        records.where((record) => record['terminalState'] == 'timeout').length,
    'upstreamRequestCount': sumNested('server', 'requestsByPath'),
    'upstreamBytes': sumNested('server', 'bytesByPath'),
    'cacheReadBytes': sumNested('cacheStats', 'cacheReadBytes'),
    'cacheSizeAfterTotal': sumNested('cacheStats', 'currentBytes'),
    'cachedResourcesAfterTotal': sumNested('cacheStats', 'cachedResources'),
    'rollbackAttempts': records.fold<int>(0, (int total, record) {
      final Map<String, dynamic>? diagnostics =
          record['diagnostics'] as Map<String, dynamic>?;
      final Iterable<dynamic> players = <dynamic>[
        ...?diagnostics?['players'] as List<dynamic>?,
        ...?diagnostics?['disposedPlayers'] as List<dynamic>?,
      ];
      return total +
          players.fold<int>(
              0,
              (int value, dynamic player) =>
                  value +
                  (((player as Map<String, dynamic>)['rollbackCount'] as num?)
                          ?.toInt() ??
                      0));
    }),
    'duplicateCacheInstanceCount': records.where((record) {
      final cache = (record['diagnostics'] as Map<String, dynamic>?)?['cache']
          as Map<String, dynamic>?;
      return ((cache?['openCacheCount'] as num?)?.toInt() ?? 0) > 1;
    }).length,
    'leaseCountBefore': 0,
    'leaseCountAfter': _lastLeaseCount(records.last),
    'minimumDurationMillis': durations.first,
    'medianDurationMillis': durations.length.isOdd
        ? durations[middle]
        : (durations[middle - 1] + durations[middle]) / 2,
    'maximumDurationMillis': durations.last,
    if (durations.length >= 20)
      'p95DurationMillis': durations[(durations.length * .95).ceil() - 1],
  };
}

int _lastLeaseCount(Map<String, dynamic> record) {
  final cache = (record['diagnostics'] as Map<String, dynamic>?)?['cache']
      as Map<String, dynamic>?;
  return ((cache?['currentLeases'] as num?)?.toInt() ?? 0) +
      ((cache?['retiredLeases'] as num?)?.toInt() ?? 0);
}
