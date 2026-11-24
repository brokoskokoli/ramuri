import 'package:core/core.dart';
import 'package:test/test.dart';

import 'export_support.dart';
import 'fit_reader.dart';
import 'xml_reader.dart';

/// Andere Sportart im Export (FR-0221, FR-0182, FR-0183). Synthetische
/// Einheit von 60 s: Puls bei 0, 10, 31 und 59 s (je + 0,4 s), Runde bei
/// 30 s, Pause [40, 45). Dazu Positionen, Höhen und Schritte, die eine
/// Sporteinheit nie exportieren darf.
const List<int> _heartSeconds = [0, 10, 31, 59];

Future<(StorageSession, int)> seedSport(OtherSport sport) async {
  final s = await xSession();
  final run = await s.runs.create(
    startedAt: xStart,
    mode: RunMode.sport,
    sport: sport,
  );
  await s.rawData.append(
    run.id,
    RawBatch(
      heartRates: [
        for (final i in _heartSeconds)
          RawHeartRate(time: xAt(i + 0.4), source: 'strap', bpm: xBpm(i)),
      ],
      positions: [
        for (var i = 0; i <= 20; i++)
          RawPosition(
            time: xAt(i),
            source: 'gps',
            latitude: xLat(i),
            longitude: xLon,
          ),
      ],
      altitudes: [
        for (var i = 0; i <= 20; i++)
          RawAltitude(time: xAt(i), source: 'gps', meters: xEle(i)),
      ],
      steps: [
        for (var i = 0; i <= 20; i++)
          RawSteps(time: xAt(i), source: 'phone', count: i * 3),
      ],
    ),
  );
  await s.markers.addLap(
    run.id,
    StoredLap(
      index: 1,
      markedAt: xAt(30),
      lapTime: const Duration(seconds: 30),
    ),
  );
  final pause = await s.markers.openGap(
    run.id,
    RunGapKind.manualPause,
    xAt(40),
  );
  await s.markers.closeGap(pause, xAt(45));
  await s.runs.setState(run.id, RunState.finished, endedAt: xAt(60));
  return (s, run.id);
}

int _fitSeconds(DateTime t) => t.millisecondsSinceEpoch ~/ 1000 - 631065600;

void main() {
  test('FIT-Sportwerte nach Profil 21.40 festgeschrieben', () {
    // Typ `sport` im FIT-Profil 21.40: generic 0, running 1, cycling 2,
    // rowing 15.
    expect(fitSport(null), 1);
    expect(fitSport(OtherSport.cycling), 2);
    expect(fitSport(OtherSport.rowing), 15);
    expect(fitSport(OtherSport.rope), 0);
    expect(fitSport(OtherSport.other), 0);
    expect(tcxSport(null), 'Running');
    expect(tcxSport(OtherSport.cycling), 'Biking');
    expect(tcxSport(OtherSport.rope), 'Other');
    expect(tcxSport(OtherSport.rowing), 'Other');
    expect(tcxSport(OtherSport.other), 'Other');
  });

  test(
    'GPX ist für Sporteinheiten gesperrt (Formatwahl, Service, Kodierer)',
    () async {
      expect(ExportFormat.gpx.availableFor(RunMode.sport), isFalse);
      expect(ExportFormat.tcx.availableFor(RunMode.sport), isTrue);
      expect(ExportFormat.fit.availableFor(RunMode.sport), isTrue);
      for (final sport in OtherSport.values) {
        final (s, id) = await seedSport(sport);
        await expectLater(
          RunFileExportService(session: s).build(id, ExportFormat.gpx),
          throwsArgumentError,
          reason: sport.name,
        );
        final run = (await RunExportService(session: s).load(id))!;
        expect(run.sport, sport);
        expect(run.hasRoute, isFalse);
        expect(() => encodeGpx(run), throwsArgumentError);
      }
    },
  );

  for (final (sport, tcx) in [
    (OtherSport.cycling, 'Biking'),
    (OtherSport.rope, 'Other'),
    (OtherSport.rowing, 'Other'),
    (OtherSport.other, 'Other'),
  ]) {
    test('TCX ${sport.name}: Sport="$tcx", nur Zeit und Puls', () async {
      final (s, id) = await seedSport(sport);
      final file = await RunFileExportService(session: s)
          .build(id, ExportFormat.tcx);
      final text = String.fromCharCodes(file!.bytes!);
      final root = parseXml(text);
      expect(root.all('Activity').single.attributes['Sport'], tcx);
      expect(root.all('Position'), isEmpty);
      expect(root.all('AltitudeMeters'), isEmpty);
      expect(root.all('Extensions'), isEmpty);
      expect(text, isNot(contains('RunCadence')));
      // Strecke nur als Pflichtfeld der Runde, immer 0.
      final laps = root.all('Lap').toList();
      expect(laps, hasLength(2));
      for (final l in laps) {
        expect(double.parse(l.child('DistanceMeters')!.text), 0);
        // Keine berechneten Werte (Regel 2): nur die Pflichtfelder.
        expect(
          [for (final c in l.children) c.name],
          everyElement(
            isIn([
              'TotalTimeSeconds',
              'DistanceMeters',
              'Calories',
              'Intensity',
              'TriggerMethod',
              'Track',
            ]),
          ),
        );
        expect(l.child('Calories')!.text, '0');
      }
      expect(
        [for (final l in laps) double.parse(l.child('TotalTimeSeconds')!.text)],
        [30, 25],
      );
      final points = root.all('Trackpoint').toList();
      for (final p in points) {
        expect(p.child('DistanceMeters'), isNull);
        expect([
          for (final c in p.children) c.name,
        ], everyElement(isIn(['Time', 'HeartRateBpm'])));
      }
      // Puls und Zeitstempel wie gespeichert.
      expect(
        [
          for (final p in points)
            (
              DateTime.parse(p.child('Time')!.text),
              int.parse(p.child('HeartRateBpm')!.child('Value')!.text),
            ),
        ],
        [for (final i in _heartSeconds) (xAt(i + 0.4), xBpm(i))],
      );
    });
  }

  for (final (sport, fit) in [
    (OtherSport.cycling, 2),
    (OtherSport.rowing, 15),
    (OtherSport.rope, 0),
    (OtherSport.other, 0),
  ]) {
    test('FIT ${sport.name}: sport $fit, sub_sport generic, ohne Strecke, '
        'Position und Kadenz', () async {
      final (s, id) = await seedSport(sport);
      final file = await RunFileExportService(session: s)
          .build(id, ExportFormat.fit);
      // Kopf, Längen und beide CRC prüft der Leser.
      final f = readFit(file!.bytes!);
      expect(f.profile, fitProfileVersion);
      final session = f.of(18).single.fields;
      expect(session[5], fit);
      expect(session[6], 0);
      // Keine Strecke und keine berechneten Werte (Puls-Mittel, Kalorien,
      // Zonen): genau diese Felder.
      expect(session.keys.toSet(), {254, 253, 0, 1, 2, 5, 6, 7, 8, 25, 26, 28});
      final laps = f.of(19).toList();
      expect(laps, hasLength(2));
      for (final l in laps) {
        expect(l.fields[25], fit);
        expect(l.fields.keys.toSet(), {254, 253, 0, 1, 2, 7, 8, 24, 25});
      }
      expect([for (final l in laps) l.fields[8]], [30000, 25000]);
      final records = f.of(20).toList();
      for (final r in records) {
        expect(r.fields.keys.toSet(), {253, 3});
      }
      expect(
        [for (final r in records) (r.fields[253], r.fields[3])],
        [for (final i in _heartSeconds) (_fitSeconds(xAt(i)), xBpm(i))],
      );
    });
  }
}
