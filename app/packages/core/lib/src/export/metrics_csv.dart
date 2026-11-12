import 'dart:convert';
import 'dart:typed_data';

import '../../ports/file_handoff.dart';
import '../../ports/storage.dart';
import '../../ports/storage_values.dart';
import '../recalculation/run_analysis.dart' show dayValueKeys;
import '../recalculation/value_calculation_service.dart' show dayOfRun;
import '../recording/treadmill.dart';

/// Formatversion der Zusatzmetriken-CSV (`docs/contracts/metrics-csv.md`).
const int metricsCsvFormatVersion = 1;

/// MIME-Typ der Datei.
const String metricsCsvMimeType = 'text/csv';

/// Kopfzeile der Formatversion 1 (Namen und Reihenfolge: Vertrag Abschnitt 3).
const List<String> metricsCsvColumns = [
  'format_version',
  'owner',
  'day',
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

/// Die berechneten Werte eines Tages (`day` als `JJJJ-MM-TT`), etwa die
/// langfristige VO₂max.
class MetricsCsvDay {
  const MetricsCsvDay({required this.day, required this.values});

  final String day;
  final List<ValuePair> values;
}

/// Kodiert die Läufe und Tage als CSV nach `docs/contracts/metrics-csv.md`: RFC 4180,
/// CRLF, Dezimalpunkt unabhängig von der Sprache, Sortierung nach Lauf,
/// Schlüssel, Rolle; Tageszeilen (`owner` = `day`) folgen den Laufzeilen,
/// aufsteigend nach Tag. Nicht endliche Werte weist er mit [ArgumentError] ab.
/// Rein; ohne Läufe oder Werte bleibt nur die Kopfzeile.
String encodeMetricsCsv(
  Iterable<MetricsCsvRun> runs, {
  Iterable<MetricsCsvDay> days = const [],
}) {
  final rows = <(MetricsCsvRun?, MetricsCsvDay?, String, ComputedValue)>[];
  for (final run in runs) {
    for (final pair in run.values) {
      rows.add((run, null, 'original', pair.original));
      rows.add((run, null, 'current', pair.current));
    }
  }
  for (final day in days) {
    for (final pair in day.values) {
      rows.add((null, day, 'original', pair.original));
      rows.add((null, day, 'current', pair.current));
    }
  }
  for (final r in rows) {
    final x = r.$4.value;
    if (x != null && !x.isFinite) {
      throw ArgumentError('Nicht endlicher Wert in der Zusatzmetriken-CSV.');
    }
  }
  rows.sort((a, b) {
    final byOwner = (a.$1 == null ? 1 : 0).compareTo(b.$1 == null ? 1 : 0);
    if (byOwner != 0) return byOwner;
    final byOwnerId = a.$1 != null
        ? a.$1!.id.compareTo(b.$1!.id)
        : a.$2!.day.compareTo(b.$2!.day);
    if (byOwnerId != 0) return byOwnerId;
    final byKey = _compareCodePoints(a.$4.key, b.$4.key);
    if (byKey != 0) return byKey;
    return (a.$3 == 'original' ? 0 : 1).compareTo(b.$3 == 'original' ? 0 : 1);
  });
  final out = StringBuffer(_line(metricsCsvColumns));
  for (final (run, day, role, v) in rows) {
    out.write(
      _line([
        '$metricsCsvFormatVersion',
        run != null ? 'run' : 'day',
        day?.day ?? '',
        run == null ? '' : '${run.id}',
        run == null ? '' : _time(run.startedAt),
        run?.mode.wire ?? '',
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
  final stored = await session.runs.list();
  final runs = <MetricsCsvRun>[];
  for (final run in stored) {
    runs.add(
      MetricsCsvRun(
        id: run.id,
        startedAt: run.startedAt,
        mode: run.mode,
        values: await session.values.read(ValueOwner.run(run.id)),
      ),
    );
  }
  // Tage beendeter Läufe plus alle Tage mit gespeichertem Tageswert, auch wenn
  // ihr Lauf gelöscht ist (der Export zeigt, was gespeichert ist).
  final dayKeys = <String>{
    for (final r in stored)
      if (r.endedAt != null) dayOfRun(r),
    ...(await session.values.readDayValues(dayValueKeys)).keys,
  };
  final days = [
    for (final d in dayKeys)
      MetricsCsvDay(
        day: d,
        values: await session.values.read(ValueOwner.day(d)),
      ),
  ];
  final day = now.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return ExportFile(
    fileName:
        'running-metriken-${day.year}${two(day.month)}${two(day.day)}.csv',
    mimeType: metricsCsvMimeType,
    bytes: Uint8List.fromList(utf8.encode(encodeMetricsCsv(runs, days: days))),
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
