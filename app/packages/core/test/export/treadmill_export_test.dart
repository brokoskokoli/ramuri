import 'package:core/core.dart';
import 'package:test/test.dart';

import 'export_support.dart';
import 'fit_reader.dart';
import 'xml_reader.dart';

/// WP25 C2: Bandlauf im Export (FR-0196, K57). Lauf von 60 s: 0 bis 20 s mit
/// 3 m/s (60 m), 20 bis 30 s Stillstand, ab 30 s mit 4 m/s, Pause [40, 45),
/// Runde bei 30 s. Strecke am Ende 60 + 4 * (10 + 15) = 160 m.
Future<(StorageSession, int)> seedBelt() async {
  final s = await xSession();
  final run = await s.runs.create(startedAt: xStart, mode: RunMode.treadmill);
  await s.rawData.append(
    run.id,
    RawBatch(
      beltSettings: const [
        BeltSetting(offset: Duration.zero, speedMetersPerSecond: 3),
        BeltSetting(offset: Duration(seconds: 20), speedMetersPerSecond: 0),
        BeltSetting(
          offset: Duration(seconds: 30),
          speedMetersPerSecond: 4,
          inclinePercent: 2,
        ),
      ],
      heartRates: [
        for (final i in [0, 10, 31, 59])
          RawHeartRate(time: xAt(i + 0.4), source: 'strap', bpm: xBpm(i)),
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

void main() {
  test('GPX ist für einen Bandlauf gesperrt (Service und Kodierer)', () async {
    final (s, id) = await seedBelt();
    expect(
      RunFileExportService(session: s).build(id, ExportFormat.gpx),
      throwsArgumentError,
    );
    final run = buildExportRun(
      run: (await s.runs.get(id))!,
      raw: await s.rawData.read(id),
      gaps: await s.markers.gaps(id),
      laps: await s.markers.laps(id),
    );
    expect(() => encodeGpx(run), throwsArgumentError);
    expect(ExportFormat.gpx.availableFor(treadmill: true), isFalse);
    expect(ExportFormat.tcx.availableFor(treadmill: true), isTrue);
    expect(ExportFormat.fit.availableFor(treadmill: true), isTrue);
    expect(ExportFormat.gpx.availableFor(treadmill: false), isTrue);
  });

  test('TCX: Trackpoints ohne Position mit kumulierter Strecke', () async {
    final (s, id) = await seedBelt();
    final file = await RunFileExportService(session: s)
        .build(id, ExportFormat.tcx);
    final root = parseXml(String.fromCharCodes(file!.bytes!));
    final activity = root.all('Activity').single;
    expect(activity.attributes['Sport'], 'Running');
    expect(root.all('Position'), isEmpty);
    final points = [
      for (final p in root.all('Trackpoint'))
        (
          t: DateTime.parse(p.child('Time')!.text).difference(xStart),
          d: double.parse(p.child('DistanceMeters')!.text),
          hr: p.child('HeartRateBpm'),
        ),
    ];
    double at(int sec) =>
        points.firstWhere((p) => p.t == Duration(seconds: sec)).d;
    expect(at(10), 30);
    expect(at(20), 60);
    expect(at(30), 60); // Stillstand
    expect(at(31), 64);
    expect(at(40), 100); // Beginn der Pause
    expect(at(45), 100); // Pause trägt nichts bei
    expect(at(60), 160);
    // Streng aufsteigend in der Zeit, Strecke nie fallend.
    for (var i = 1; i < points.length; i++) {
      expect(points[i].t, greaterThan(points[i - 1].t));
      expect(points[i].d, greaterThanOrEqualTo(points[i - 1].d));
    }
    expect(points.where((p) => p.hr != null), hasLength(4));
    // Rundenstrecken: 60 (bis 30 s) und 100.
    final laps = [
      for (final l in root.all('Lap'))
        double.parse(l.child('DistanceMeters')!.text),
    ];
    expect(laps, [60, 100]);
  });

  test('FIT: Records ohne Position mit Strecke und Geschwindigkeit, '
      'Unterart Laufband', () async {
    final (s, id) = await seedBelt();
    final file = await RunFileExportService(session: s)
        .build(id, ExportFormat.fit);
    final fit = readFit(file!.bytes!);
    final records = fit.of(20).toList();
    expect(records, isNotEmpty);
    for (final r in records) {
      expect(r.fields.containsKey(0), isFalse, reason: 'position_lat');
      expect(r.fields.containsKey(1), isFalse, reason: 'position_long');
    }
    Map<int, int> rec(int sec) => records
        .firstWhere((r) => r.fields[253] == fitSeconds2(xStart) + sec)
        .fields;
    expect(rec(10)[5], 3000); // 30 m in cm
    expect(rec(10)[6], 3000); // 3 m/s in mm/s
    expect(rec(25)[5], 6000);
    expect(rec(25)[6], 0);
    expect(rec(31)[5], 6400);
    expect(rec(31)[6], 4000);
    expect(rec(60)[5], 16000);
    final session = fit.of(18).single.fields;
    expect(session[5], 1); // sport running
    expect(session[6], 1); // sub_sport treadmill
    expect(session[9], 16000); // total_distance
    expect([for (final l in fit.of(19)) l.fields[9]], [6000, 10000]);
  });
}

int fitSeconds2(DateTime t) => t.millisecondsSinceEpoch ~/ 1000 - 631065600;
