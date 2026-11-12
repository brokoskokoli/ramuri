import 'dart:convert';
import 'dart:typed_data';

import '../../ports/file_handoff.dart';
import '../../ports/storage.dart';
import '../../ports/storage_runs.dart';
import '../../ports/storage_values.dart';
import '../recording/treadmill.dart';

/// Formatversion der Zusatzmetriken-CSV (`docs/contracts/metrics-csv.md`).
const int metricsCsvFormatVersion = 1;

/// MIME-Typ der Datei.
const String metricsCsvMimeType = 'text/csv';

/// Kopfzeile der Formatversion 1 (Namen und Reihenfolge: Vertrag Abschnitt 3).
const List<String> metricsCsvColumns = [
  'format_version',
  'run_id',
  'run_started_at',
  'run_mode',
  'role',
  'value_key',
  'value',
  'unit',
  'quality',
  'unavailable_reason',
  'method',
  'method_version',
  'parameter_version',
  'computed_at',
  'data_from',
  'data_to',
  'measurement_count',
  'sources',
];

/// Ein Lauf mit seinen berechneten Werten, Eingabe des Kodierers.
class MetricsCsvRun {
  const MetricsCsvRun({
    required this.id,
    required this.startedAt,
    required this.mode,
    required this.values,
  });

  final int id;
  final DateTime startedAt;
  final RunMode mode;
  final List<ValuePair> values;
}

/// Kodiert die Läufe als CSV nach `docs/contracts/metrics-csv.md`: RFC 4180,
/// CRLF, Dezimalpunkt unabhängig von der Sprache, Sortierung nach Lauf,
/// Schlüssel, Rolle. Rein; ohne Läufe oder Werte bleibt nur die Kopfzeile.
String encodeMetricsCsv(Iterable<MetricsCsvRun> runs) {
  final rows = <(MetricsCsvRun, String, ComputedValue)>[];
  for (final run in runs) {
    for (final pair in run.values) {
      rows.add((run, 'original', pair.original));
      rows.add((run, 'current', pair.current));
    }
  }
  rows.sort((a, b) {
    final byRun = a.$1.id.compareTo(b.$1.id);
    if (byRun != 0) return byRun;
    final byKey = _compareCodePoints(a.$3.key, b.$3.key);
    if (byKey != 0) return byKey;
    return (a.$2 == 'original' ? 0 : 1).compareTo(b.$2 == 'original' ? 0 : 1);
  });
  final out = StringBuffer(_line(metricsCsvColumns));
  for (final (run, role, v) in rows) {
    out.write(
      _line([
        '$metricsCsvFormatVersion',
        '${run.id}',
        _time(run.startedAt),
        run.mode.wire,
        role,
        v.key,
        v.value == null ? '' : '${v.value}',
        v.unit,
        v.quality.name,
        v.unavailableReason?.name ?? '',
        v.method,
        '${v.methodVersion}',
        '${v.parameterVersion}',
        _time(v.computedAt),
        v.dataFrom == null ? '' : _time(v.dataFrom!),
        v.dataTo == null ? '' : _time(v.dataTo!),
        '${v.measurementCount}',
        jsonEncode(v.sources),
      ]),
    );
  }
  return out.toString();
}

/// Liest alle Läufe samt Werten und baut die Datei für die Übergabe. Wirft
/// Speicherfehler weiter (der Aufrufer meldet „fehlgeschlagen“ ohne Inhalte).
Future<ExportFile> buildMetricsCsvFile(
  StorageSession session, {
  required DateTime now,
}) async {
  final runs = <MetricsCsvRun>[];
  for (final run in await session.runs.list()) {
    runs.add(
      MetricsCsvRun(
        id: run.id,
        startedAt: run.startedAt,
        mode: run.mode,
        values: await session.values.read(ValueOwner.run(run.id)),
      ),
    );
  }
  final day = now.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return ExportFile(
    fileName:
        'running-metriken-${day.year}${two(day.month)}${two(day.day)}.csv',
    mimeType: metricsCsvMimeType,
    bytes: Uint8List.fromList(utf8.encode(encodeMetricsCsv(runs))),
  );
}

String _time(DateTime t) => t.toUtc().toIso8601String();

String _line(List<String> fields) => '${fields.map(_field).join(',')}\r\n';

String _field(String s) {
  if (!s.contains(RegExp(r'[",\r\n]'))) return s;
  return '"${s.replaceAll('"', '""')}"';
}

int _compareCodePoints(String a, String b) {
  final x = a.runes.toList(), y = b.runes.toList();
  for (var i = 0; i < x.length && i < y.length; i++) {
    if (x[i] != y[i]) return x[i].compareTo(y[i]);
  }
  return x.length.compareTo(y.length);
}
