import 'dart:convert';

import 'package:core/core.dart';
import 'package:test/test.dart';

import 'export_support.dart';

const _header =
    'format_version,owner,day,run_id,run_started_at,run_mode,role,value_key,value,unit,'
    'quality,unavailable_reason,method,method_version,parameter_version,'
    'computed_at,data_from,data_to,measurement_count,sources\r\n';

final _t = DateTime.utc(2030, 1, 1, 8);

ComputedValue _v(
  String key,
  double? value, {
  String unit = 'ml/kg/min',
  String method = 'm',
  List<String> sources = const ['strap'],
  DateTime? from,
}) => ComputedValue(
  key: key,
  value: value,
  unit: unit,
  computedAt: _t,
  measurementCount: 3,
  sources: sources,
  method: method,
  methodVersion: 2,
  parameterVersion: 5,
  quality: value == null ? ValueQuality.undeterminable : ValueQuality.good,
  unavailableReason: value == null
      ? UnavailableReason.missingMaxHeartRate
      : null,
  dataFrom: from,
);

MetricsCsvRun _run(int id, List<ComputedValue> values, {RunMode? mode}) =>
    MetricsCsvRun(
      id: id,
      startedAt: _t,
      mode: mode ?? RunMode.gps,
      values: [for (final v in values) ValuePair(original: v, current: v)],
    );

List<String> _lines(String csv) => csv.split('\r\n');

/// Datenzeilen ohne `format_version`: owner, day, run_id, started, mode, role,
/// key, value, ...
List<List<String>> _rows(String csv) => [
  for (final l in _lines(csv).skip(1).where((l) => l.isNotEmpty))
    l.split(',').skip(1).toList(),
];

void main() {
  test('leere Daten: nur die Kopfzeile, CRLF, Formatversion 1', () {
    expect(encodeMetricsCsv(const []), _header);
    expect(encodeMetricsCsv([_run(1, const [])]), _header);
    expect(metricsCsvFormatVersion, 1);
  });

  test('Zeile: Formatversion, Dezimalpunkt, Zeiten, Lauf-Art, leere Felder', () {
    final csv = encodeMetricsCsv([
      _run(7, [_v('vo2', 52.5, from: _t)], mode: RunMode.treadmill),
    ]);
    final lines = _lines(csv);
    expect(lines.first, _header.trimRight());
    expect(
      lines[1],
      '1,run,,7,2030-01-01T08:00:00.000Z,treadmill,original,vo2,52.5,ml/kg/min,'
      'good,,m,2,5,2030-01-01T08:00:00.000Z,2030-01-01T08:00:00.000Z,,3,'
      '"[""strap""]"',
    );
    expect(lines[2], contains(',current,vo2,52.5,'));
    expect(csv.endsWith('\r\n'), isTrue);
  });

  test('fehlender Wert: leeres Feld und Grund, nie 0 oder NaN', () {
    final line = _lines(
      encodeMetricsCsv([
        _run(1, [_v('vo2', null)]),
      ]),
    )[1];
    expect(
      line,
      contains(
        ',original,vo2,,ml/kg/min,undeterminable,'
        'missingMaxHeartRate,',
      ),
    );
    expect(line, isNot(contains('NaN')));
  });

  test('Escaping nach RFC 4180: Komma, Anführungszeichen, Zeilenumbruch', () {
    final csv = encodeMetricsCsv([
      _run(1, [
        _v('a', 1, method: 'x,"y"', unit: 'l\nm', sources: ['a,b']),
      ]),
    ]);
    expect(csv, contains(',"x,""y""",'));
    expect(csv, contains(',"l\nm",'));
    expect(csv, contains('"[""a,b""]"'));
    // Eingabe ohne Sonderzeichen bleibt ohne Anführungszeichen.
    expect(
      _lines(
        encodeMetricsCsv([
          _run(1, [_v('a', 1)]),
        ]),
      )[1],
      contains(',a,1.0,ml/kg/min,'),
    );
  });

  test('Sortierung: Lauf, Schlüssel, original vor current', () {
    final csv = encodeMetricsCsv([
      _run(2, [_v('b', 1)]),
      _run(1, [_v('z', 1), _v('a', 1)]),
    ]);
    expect(
      [for (final r in _rows(csv)) '${r[2]}:${r[5]}:${r[6]}'],
      [
        '1:original:a',
        '1:current:a',
        '1:original:z',
        '1:current:z',
        '2:original:b',
        '2:current:b',
      ],
    );
  });

  test('Rolle ordnet original vor current, auch bei gleichem Schlüssel', () {
    // Zwei Paare mit demselben Schlüssel und verschiedenen Werten: erst beide
    // originals, dann beide currents (nicht Paar für Paar).
    final csv = encodeMetricsCsv([
      MetricsCsvRun(
        id: 1,
        startedAt: _t,
        mode: RunMode.gps,
        values: [
          ValuePair(original: _v('a', 1), current: _v('a', 2)),
          ValuePair(original: _v('a', 3), current: _v('a', 4)),
        ],
      ),
    ]);
    expect(
      [for (final r in _rows(csv)) '${r[5]}:${r[7]}'],
      ['original:1.0', 'original:3.0', 'current:2.0', 'current:4.0'],
    );
  });

  test('Tageswerte: owner day, Datum, Laufspalten leer, nach den Läufen', () {
    final csv = encodeMetricsCsv(
      [
        _run(3, [_v('a', 1)]),
      ],
      days: [
        MetricsCsvDay(
          day: '2030-01-02',
          values: [ValuePair(original: _v('v', 9), current: _v('v', 8))],
        ),
        MetricsCsvDay(
          day: '2030-01-01',
          values: [ValuePair(original: _v('v', 7), current: _v('v', 7))],
        ),
      ],
    );
    final lines = _lines(csv);
    expect(
      lines[3],
      '1,day,2030-01-01,,,,original,v,7.0,ml/kg/min,'
      'good,,m,2,5,2030-01-01T08:00:00.000Z,,,3,"[""strap""]"',
    );
    expect(
      [for (final r in _rows(csv)) '${r[0]}:${r[1]}:${r[5]}:${r[7]}'],
      [
        'run::original:1.0',
        'run::current:1.0',
        'day:2030-01-01:original:7.0',
        'day:2030-01-01:current:7.0',
        'day:2030-01-02:original:9.0',
        'day:2030-01-02:current:8.0',
      ],
    );
  });

  test('Feld nur mit CR wird gequotet', () {
    final csv = encodeMetricsCsv([
      _run(1, [_v('a', 1, unit: 'l\rm')]),
    ]);
    expect(csv, contains(',"l\rm",'));
  });

  test('Zeitpunkte werden als UTC mit Z geschrieben', () {
    // Lokale Zeit (nicht UTC): die Ausgabe muss trotzdem auf Z enden.
    final local = DateTime.utc(2030, 1, 1, 8).toLocal();
    final csv = encodeMetricsCsv([
      MetricsCsvRun(
        id: 1,
        startedAt: local,
        mode: RunMode.gps,
        values: [ValuePair(original: _v('a', 1), current: _v('a', 1))],
      ),
    ]);
    expect(_lines(csv)[1], contains(',2030-01-01T08:00:00.000Z,gps,'));
  });

  test('nicht endlicher Wert wird abgewiesen, kein NaN in der Datei', () {
    for (final x in [double.nan, double.infinity, double.negativeInfinity]) {
      expect(
        () => encodeMetricsCsv([
          _run(1, [_v('a', x)]),
        ]),
        throwsArgumentError,
      );
    }
  });

  test('Dezimalpunkt in jeder Darstellung, auch bei kleinen Zahlen', () {
    final csv = encodeMetricsCsv([
      _run(1, [_v('a', 0.5), _v('b', 1234567.25)]),
    ]);
    expect(csv, contains(',0.5,'));
    expect(csv, contains(',1234567.25,'));
    expect(csv, isNot(contains('0,5')));
  });

  test('buildMetricsCsvFile liest Läufe und Werte aus dem Speicher', () async {
    final s = await xSession();
    final run = await s.runs.create(startedAt: xStart, mode: RunMode.treadmill);
    await s.runs.setState(
      run.id,
      RunState.finished,
      endedAt: xStart.add(const Duration(minutes: 30)),
    );
    await s.values.createOriginals(ValueOwner.run(run.id), [_v('vo2', 48.5)]);
    await s.values.createOriginals(const ValueOwner.day('2030-01-01'), [
      _v('vo2max_long_term', 47.0),
    ]);
    final file = await buildMetricsCsvFile(s, now: DateTime.utc(2031, 2, 3));
    expect(file.fileName, 'running-metriken-20310203.csv');
    expect(file.mimeType, 'text/csv');
    final text = utf8.decode(file.bytes!);
    expect(text, startsWith(_header));
    expect(text, contains('treadmill,original,vo2,48.5,'));
    expect(text, contains('treadmill,current,vo2,48.5,'));
    expect(
      text,
      contains('1,day,2030-01-01,,,,original,vo2max_long_term,47.0,'),
    );
    expect(
      text,
      contains('1,day,2030-01-01,,,,current,vo2max_long_term,47.0,'),
    );
  });
}
