import 'dart:convert';

import 'package:core/core.dart';
import 'package:test/test.dart';

import '../support/overlapping_runs.dart';
import 'fit_reader.dart';
import 'xml_reader.dart';

/// Export zweier Läufe, die sich nach einem Rücksprung der Wanduhr
/// überlappen (ADR-0005 Punkt 7): jede Datei enthält nur Zeitpunkte ihres
/// eigenen Laufs.
void main() {
  const fitEpochUnix = 631065600;
  // Globale FIT-Nachrichtennummern (Vertrag `docs/contracts/file-export.md`).
  const fileId = 0, record = 20, session = 18, lap = 19;

  late OverlappingRuns o;
  late StoredRun a;
  late StoredRun b;

  setUp(() async {
    o = await recordOverlappingRuns();
    a = await o.runA();
    b = await o.runB();
    expect(b.startedAt.isBefore(a.endedAt!), isTrue);
  });

  /// Zeitpunkte der gespeicherten Positionen des Laufs (ganze Sekunden):
  /// jeder Punkt der Datei kommt aus genau diesem Lauf, keiner fehlt.
  Future<List<DateTime>> pointTimes(StoredRun run) async => [
    for (final p in (await o.session.rawData.read(run.id)).positions)
      p.value.time,
  ];

  void expectWithin(StoredRun run, Iterable<DateTime> times, String what) {
    expect(times, isNotEmpty, reason: what);
    for (final t in times) {
      expect(t.isBefore(run.startedAt), isFalse, reason: '$what: $t');
      expect(t.isAfter(run.endedAt!), isFalse, reason: '$what: $t');
    }
  }

  test('GPX und TCX: Zeitpunkte nur aus dem eigenen Lauf', () async {
    final service = RunFileExportService(session: o.session);
    for (final run in [a, b]) {
      final gpx = parseXml(
        utf8.decode((await service.build(run.id, ExportFormat.gpx))!.bytes!),
      );
      final gpxTimes = [
        for (final e in gpx.all('time')) DateTime.parse(e.text),
      ];
      expectWithin(run, gpxTimes, 'GPX ${run.id}');
      expect(
        [
          for (final p in gpx.all('trkpt'))
            DateTime.parse(p.child('time')!.text),
        ],
        await pointTimes(run),
        reason: 'GPX ${run.id}',
      );

      final tcx = parseXml(
        utf8.decode((await service.build(run.id, ExportFormat.tcx))!.bytes!),
      );
      final tcxTimes = [
        for (final e in [...tcx.all('Time'), ...tcx.all('Id')])
          DateTime.parse(e.text),
        for (final l in tcx.all('Lap'))
          DateTime.parse(l.attributes['StartTime']!),
      ];
      expectWithin(run, tcxTimes, 'TCX ${run.id}');
      expect(
        [
          for (final p in tcx.all('Trackpoint'))
            DateTime.parse(p.child('Time')!.text),
        ],
        await pointTimes(run),
        reason: 'TCX ${run.id}',
      );
    }
  });

  test('FIT: Zeitstempel nur aus dem eigenen Lauf', () async {
    final service = RunFileExportService(session: o.session);
    DateTime at(int fitSeconds) => DateTime.fromMillisecondsSinceEpoch(
      (fitSeconds + fitEpochUnix) * 1000,
      isUtc: true,
    );
    for (final run in [a, b]) {
      final fit = readFit(
        (await service.build(run.id, ExportFormat.fit))!.bytes!,
      );
      final times = [
        for (final m in fit.messages)
          if (m.fields[253] case final t?) at(t),
        for (final m in [...fit.of(lap), ...fit.of(session)])
          if (m.fields[2] case final t?) at(t),
        for (final m in fit.of(fileId))
          if (m.fields[4] case final t?) at(t),
      ];
      expectWithin(run, times, 'FIT ${run.id}');
      expect(
        [for (final m in fit.of(record)) at(m.fields[253]!)],
        await pointTimes(run),
        reason: 'FIT ${run.id}',
      );
    }
  });

  test('Kennzahlen-CSV: beide Läufe, je Lauf Zeitpunkte aus ihm', () async {
    final calc = ValueCalculationService(session: o.session, clock: o.clock);
    await o.session.profile.save(
      const ProfileRecord(maxHeartRateBpm: 190, restingHeartRateBpm: 60),
    );
    await calc.calculateAfterRun(o.a);
    await calc.calculateAfterRun(o.b);
    final file = await buildMetricsCsvFile(o.session, now: o.clock.now());
    final lines = const LineSplitter().convert(utf8.decode(file.bytes!));
    final head = lines.first.split(',');
    int col(String name) => head.indexOf(name);
    final runRows = <int, List<List<String>>>{};
    for (final l in lines.skip(1)) {
      // Spalten bis `data_to` enthalten keine Kommas (sources steht zuletzt).
      final f = l.split(',');
      if (f[col('owner')] != 'run') continue;
      (runRows[int.parse(f[col('run_id')])] ??= []).add(f);
    }
    expect(runRows.keys.toSet(), {o.a, o.b});
    // Tageszeilen: beide Läufe gehören zum selben Tag (`dayOfRun`).
    expect(
      {
        for (final l in lines.skip(1))
          if (l.split(',')[col('owner')] == 'day') l.split(',')[col('day')],
      },
      {'2030-01-16'},
    );
    for (final run in [a, b]) {
      final rows = runRows[run.id]!;
      expect(
        rows.map((f) => DateTime.parse(f[col('run_started_at')])).toSet(),
        {run.startedAt},
      );
      expectWithin(run, [
        for (final f in rows)
          for (final c in ['data_from', 'data_to'])
            if (f[col(c)].isNotEmpty) DateTime.parse(f[col(c)]),
      ], 'CSV ${run.id}');
    }
  });
}
