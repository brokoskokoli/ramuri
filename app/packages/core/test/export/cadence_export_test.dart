import 'package:core/core.dart';
import 'package:test/test.dart';

import 'export_support.dart';
import 'fit_reader.dart';
import 'xml_reader.dart';

/// Schrittfrequenz im Export (FR-0183, FR-0202): aus dem gespeicherten Zähler
/// `raw_steps`. Synthetischer Lauf von 30 s mit Position je Sekunde und
/// manueller Pause [12, 15):
/// - Abschnitt 1: Zähler je Sekunde ab 0,5 s um 3 (180 Schritte/min),
/// - Pause: kein Zähler (die Aufzeichnung zählt dort nicht),
/// - Abschnitt 2: Zähler alle 3 s ab 15,5 s um 8 (160 Schritte/min).
/// Dazu ein geschätzter Wert, der nicht zählen darf.
const List<num> seg1Times = [
  0.5, 1.5, 2.5, 3.5, 4.5, 5.5, 6.5, 7.5, 8.5, 9.5, 10.5, 11.5, //
];
const List<num> seg2Times = [15.5, 18.5, 21.5, 24.5, 27.5];

int countAt(num t) {
  final i = seg1Times.indexOf(t);
  if (i >= 0) return 3 * (i + 1);
  return 36 + 8 * (seg2Times.indexOf(t) + 1);
}

Future<(StorageSession, int)> seedStepsRun() async {
  final s = await xSession();
  final id = await seedRun(
    s,
    seconds: 30,
    batch: RawBatch(
      positions: [
        for (var i = 0; i <= 30; i++)
          if (i < 12 || i >= 15)
            RawPosition(
              time: xAt(i),
              source: 'gps',
              latitude: xLat(i),
              longitude: xLon,
            ),
      ],
      steps: [
        for (final t in [...seg1Times, ...seg2Times])
          RawSteps(time: xAt(t), source: 'phone', count: countAt(t)),
        RawSteps(
          time: xAt(5.9),
          source: 'phone',
          count: 999,
          state: MeasurementState.estimated,
        ),
      ],
    ),
    gaps: [(RunGapKind.manualPause, 12, 15)],
  );
  return (s, id);
}

Future<ExportRun> build(StorageSession s, int id, Duration resolution) async =>
    buildExportRun(
      run: (await s.runs.get(id))!,
      raw: await s.rawData.read(id),
      gaps: await s.markers.gaps(id),
      laps: await s.markers.laps(id),
      resolution: resolution,
    );

Map<Duration, double> cadenceOf(ExportRun run) => {
  for (final seg in run.segments)
    for (final p in seg.points)
      if (p.cadenceStepsPerMinute != null)
        p.time.difference(xStart): p.cadenceStepsPerMinute!,
};

Duration sec(num s) => Duration(microseconds: (s * 1e6).round());

int fitTime(num s) => xAt(s).millisecondsSinceEpoch ~/ 1000 - 631065600;

void main() {
  group('Exportmodell', () {
    test('Schrittfrequenz aus dem Zähler je Abschnitt, erster Wert eines '
        'Abschnitts ohne Frequenz', () async {
      final (s, id) = await seedStepsRun();
      final run = await build(s, id, exportMillisecond);
      final got = cadenceOf(run);
      expect(got.keys, [
        for (final t in [...seg1Times.skip(1), ...seg2Times.skip(1)]) sec(t),
      ]);
      for (final t in seg1Times.skip(1)) {
        expect(got[sec(t)], closeTo(180, 1e-9), reason: '$t');
      }
      for (final t in seg2Times.skip(1)) {
        expect(got[sec(t)], closeTo(160, 1e-9), reason: '$t');
      }
      // Kein Wert aus dem geschätzten Zähler, kein Punkt nur seinetwegen.
      expect(
        run.segments.expand((x) => x.points).map((p) => p.time),
        isNot(contains(xAt(5.9))),
      );
    });

    test('Fenster: Vorgänger älter als 10 s, gleiche Zeit oder fallender '
        'Zähler ergeben keinen Wert', () async {
      final s = await xSession();
      final id = await seedRun(
        s,
        seconds: 40,
        batch: RawBatch(
          steps: [
            RawSteps(time: xAt(1), source: 'phone', count: 10),
            RawSteps(time: xAt(12), source: 'phone', count: 40), // 11 s
            RawSteps(time: xAt(22), source: 'phone', count: 70), // genau 10 s
            RawSteps(time: xAt(25), source: 'phone', count: 60), // fällt
          ],
        ),
      );
      final got = cadenceOf(await build(s, id, exportMillisecond));
      expect(got.keys, [sec(22)]);
      expect(got[sec(22)], closeTo(180, 1e-9));
      expect(exportCadenceWindow, CadenceEstimator.defaultWindow);
    });

    test('Einheit der Formate: Doppelschritte je Minute, 0…254', () {
      expect(exportStrideCadence(180), 90);
      expect(exportStrideCadence(161), 81); // 80,5 rundet auf
      expect(exportStrideCadence(508), 254);
      expect(exportStrideCadence(509), isNull);
      expect(exportStrideCadence(double.nan), isNull);
      expect(exportStrideCadence(null), isNull);
    });
  });

  group('FIT (Rücklesen mit dem Test-Leser)', () {
    test('record trägt cadence (Feld 4) passend zum Zähler', () async {
      final (s, id) = await seedStepsRun();
      final file = await RunFileExportService(session: s)
          .build(id, ExportFormat.fit);
      final fit = readFit(file!.bytes!);
      final records = fit.of(20).toList();
      final cadence = {
        for (final r in records)
          if (r.fields[4] != 0xFF) r.fields[253]!: r.fields[4]!,
      };
      // Zähler bei x,5 s fällt in die Sekunde x zum Punkt mit Position.
      expect(cadence, {
        for (final t in seg1Times.skip(1)) fitTime(t.floor()): 90,
        for (final t in seg2Times.skip(1)) fitTime(t.floor()): 80,
      });
      final withPosition = records.firstWhere(
        (r) => r.fields[253] == fitTime(1),
      );
      expect(withPosition.fields[0], isNot(0x7FFFFFFF));
      expect(withPosition.fields[4], 90);
      // Ohne Schrittfrequenz: Invalid-Wert, nie 0.
      expect(
        records.firstWhere((r) => r.fields[253] == fitTime(0)).fields[4],
        0xFF,
      );
    });

    test('Lauf ohne Schritte: record ohne Feld cadence', () async {
      final s = await xSession();
      final id = await seedMainRun(s);
      final file = await RunFileExportService(session: s)
          .build(id, ExportFormat.fit);
      for (final r in readFit(file!.bytes!).of(20)) {
        expect(r.fields.containsKey(4), isFalse);
      }
    });

    test('Bandlauf: record mit Strecke und cadence', () async {
      final s = await xSession();
      final run = await s.runs.create(
        startedAt: xStart,
        mode: RunMode.treadmill,
      );
      await s.rawData.append(
        run.id,
        RawBatch(
          beltSettings: const [
            BeltSetting(offset: Duration.zero, speedMetersPerSecond: 3),
          ],
          steps: [
            RawSteps(time: xAt(2), source: 'phone', count: 6),
            RawSteps(time: xAt(4), source: 'phone', count: 12),
          ],
        ),
      );
      await s.runs.setState(run.id, RunState.finished, endedAt: xAt(10));
      final file = await RunFileExportService(session: s)
          .build(run.id, ExportFormat.fit);
      final rec = readFit(file!.bytes!)
          .of(20)
          .firstWhere((r) => r.fields[253] == fitTime(4))
          .fields;
      expect(rec[5], 1200); // 12 m in cm
      expect(rec[4], 90);
    });

    // Manuelle Pause [4,4; 4,6): beide Abschnitte enden bzw. beginnen in der
    // FIT-Sekunde 4. Der record dieser Sekunde trägt die Werte des früheren
    // Punkts und ergänzt nur fehlende Kanäle aus dem späteren
    // (docs/contracts/file-export.md, „FIT-Zeit und Zusammenführung“).
    Future<Map<int, int>> recordAt4(RawBatch batch) async {
      final s = await xSession();
      final id = await seedRun(
        s,
        batch: batch,
        gaps: [(RunGapKind.manualPause, 4.4, 4.6)],
      );
      final file = await RunFileExportService(session: s)
          .build(id, ExportFormat.fit);
      final records = readFit(file!.bytes!)
          .of(20)
          .where((r) => r.fields[253] == fitTime(4))
          .toList();
      expect(records, hasLength(1));
      return records.single.fields;
    }

    int semi(double deg) => (deg * 2147483648 / 180).round();

    test('Pause unter einer Sekunde: record trägt die Schrittfrequenz des '
        'früheren Punkts', () async {
      final rec = await recordAt4(
        RawBatch(
          positions: [
            RawPosition(
              time: xAt(4.2),
              source: 'gps',
              latitude: xLat(1),
              longitude: xLon,
            ),
            RawPosition(
              time: xAt(4.7),
              source: 'gps',
              latitude: xLat(2),
              longitude: xLon,
            ),
          ],
          steps: [
            // Abschnitt 1: je Sekunde 3 Schritte, bei 4,2 s 180/min.
            for (var i = 1; i <= 4; i++)
              RawSteps(time: xAt(i + 0.2), source: 'phone', count: 3 * i),
            // Abschnitt 2: 1 Schritt in 0,2 s, bei 4,9 s 300/min.
            RawSteps(time: xAt(4.7), source: 'phone', count: 13),
            RawSteps(time: xAt(4.9), source: 'phone', count: 14),
          ],
        ),
      );
      expect(rec[4], 90); // 180 Schritte/min, nicht 150 aus Abschnitt 2
      expect(rec[0], semi(xLat(1)));
    });

    test('Pause unter einer Sekunde: früherer Punkt ohne Schrittfrequenz, '
        'record ergänzt sie aus dem späteren', () async {
      final rec = await recordAt4(
        RawBatch(
          positions: [
            RawPosition(
              time: xAt(4.2),
              source: 'gps',
              latitude: xLat(1),
              longitude: xLon,
            ),
            RawPosition(
              time: xAt(4.7),
              source: 'gps',
              latitude: xLat(2),
              longitude: xLon,
            ),
          ],
          heartRates: [
            RawHeartRate(time: xAt(4.3), source: 's', bpm: 150),
            RawHeartRate(time: xAt(4.8), source: 's', bpm: 160),
          ],
          steps: [
            // Abschnitt 1: nur ein Zählerwert, also keine Frequenz.
            RawSteps(time: xAt(4.1), source: 'phone', count: 50),
            // Abschnitt 2: 1 Schritt in 0,2 s, bei 4,9 s 300/min.
            RawSteps(time: xAt(4.7), source: 'phone', count: 60),
            RawSteps(time: xAt(4.9), source: 'phone', count: 61),
          ],
        ),
      );
      expect(rec[4], 150); // 300 Schritte/min aus Abschnitt 2
      expect(rec[0], semi(xLat(1)));
      expect(rec[3], 150);
    });
  });

  group('TCX (Struktur nach TrainingCenterDatabase v2 und ActivityExtension '
      'v2)', () {
    test('Trackpoint/Extensions/TPX/RunCadence passend zum Zähler', () async {
      final (s, id) = await seedStepsRun();
      final file = await RunFileExportService(session: s)
          .build(id, ExportFormat.tcx);
      final text = String.fromCharCodes(file!.bytes!);
      final root = parseXml(text);
      expect(
        root.attributes['xmlns:tpx'],
        'http://www.garmin.com/xmlschemas/ActivityExtension/v2',
      );
      final got = <String, String>{};
      for (final tp in root.all('Trackpoint')) {
        final ext = tp.child('Extensions');
        if (ext == null) continue;
        // Schema: Extensions ist das letzte Kind eines Trackpoint.
        expect(tp.children.last, same(ext));
        final tpx = ext.children.single;
        expect(tpx.name, 'tpx:TPX');
        final rc = tpx.children.single;
        expect(rc.name, 'tpx:RunCadence');
        got[tp.child('Time')!.text] = rc.text;
      }
      String iso(num t) => '${xAt(t).toIso8601String().substring(0, 23)}Z';
      expect(got, {
        for (final t in seg1Times.skip(1)) iso(t): '90',
        for (final t in seg2Times.skip(1)) iso(t): '80',
      });
      // Kein Feld Cadence (Rad) am Trackpoint.
      expect(root.descendantNames, isNot(contains('Cadence')));
    });

    test('Lauf ohne Schritte: kein Namensraum und keine Extensions', () async {
      final s = await xSession();
      final id = await seedMainRun(s);
      final file = await RunFileExportService(session: s)
          .build(id, ExportFormat.tcx);
      final text = String.fromCharCodes(file!.bytes!);
      expect(text, isNot(contains('ActivityExtension')));
      expect(parseXml(text).descendantNames, isNot(contains('Extensions')));
    });
  });

  test('GPX trägt keine Schrittfrequenz', () async {
    final (s, id) = await seedStepsRun();
    final file = await RunFileExportService(session: s)
        .build(id, ExportFormat.gpx);
    final text = String.fromCharCodes(file!.bytes!);
    expect(text, isNot(contains('adence')));
    // Ein trkpt entsteht nur aus Positionen, nicht aus Zählerwerten.
    expect(parseXml(text).all('trkpt').length, 28);
  });
}
