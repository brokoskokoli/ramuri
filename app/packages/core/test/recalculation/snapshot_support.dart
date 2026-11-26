import 'package:core/core.dart';

import 'recalc_support.dart';

/// Gemischter synthetischer Bestand für den Vergleich des Zwischenstands:
/// GPS-Läufe mit verschiedenem Tempo, Puls und Pulsabdeckung, einer mit
/// Pause-Taste, ein Bandlauf und ein Lauf ohne Dauer; jeder sofort berechnet.
/// Danach wechselt die HFmax (190 → 180), damit die Neuberechnung andere Werte
/// liefert als die gespeicherten.
Future<void> seedMixedRuns(RecalcWorld w) async {
  final calc = w.calc();
  final specs = <(DateTime, double, int, double)>[
    (DateTime.utc(2030, 1, 12, 7), 2.9, 142, 1),
    (DateTime.utc(2030, 1, 20, 8), 3.0, 145, 1),
    (DateTime.utc(2030, 1, 25, 18), 3.1, 146, 0.8),
    (DateTime.utc(2030, 2, 3, 6, 30), 3.3, 162, 1),
    (DateTime.utc(2030, 2, 20, 8), 3.15, 144, 1),
    (DateTime.utc(2030, 2, 25, 8), 3.2, 147, 1),
    (DateTime.utc(2030, 2, 26, 8), 3.25, 158, 0.6),
  ];
  for (final (start, speed, bpm, share) in specs) {
    final id = await w.seedRun(
      start,
      minutes: 35,
      speed: speed,
      bpm: bpm,
      heartRateShare: share,
    );
    await calc.calculateAfterRun(id);
  }
  // GPS-Lauf mit Pause-Taste in der Mitte.
  final paused = await w.seedRun(DateTime.utc(2030, 2, 10, 9), minutes: 40);
  final run = (await w.session.runs.get(paused))!;
  final gap = await w.session.markers.openGap(
    paused,
    RunGapKind.manualPause,
    run.startedAt.add(const Duration(minutes: 18)),
  );
  await w.session.markers.closeGap(
    gap,
    run.startedAt.add(const Duration(minutes: 22)),
  );
  await calc.calculateAfterRun(paused);
  // Bandlauf (FR-0196).
  final beltStart = DateTime.utc(2030, 2, 15, 17);
  final belt = await w.session.runs.create(
    startedAt: beltStart,
    mode: RunMode.treadmill,
  );
  await w.session.rawData.append(
    belt.id,
    RawBatch(
      heartRates: [
        for (var s = 0; s <= 1800; s++)
          RawHeartRate(
            time: beltStart.add(Duration(seconds: s)),
            source: 'strap',
            bpm: 145 + (s ~/ 300),
            contact: SensorContact.good,
          ),
      ],
      beltSettings: [
        BeltSetting(
          offset: Duration.zero,
          speedMetersPerSecond: 2.8,
          inclinePercent: 0,
        ),
        BeltSetting(
          offset: const Duration(minutes: 15),
          speedMetersPerSecond: 3.1,
          inclinePercent: 1,
        ),
      ],
    ),
  );
  await w.session.runs.setState(
    belt.id,
    RunState.finished,
    endedAt: beltStart.add(const Duration(seconds: 1800)),
  );
  w.clock.set(beltStart.add(const Duration(minutes: 31)));
  await calc.calculateAfterRun(belt.id);
  // Lauf ohne Dauer.
  final zero = await w.session.runs.create(
    startedAt: DateTime.utc(2030, 2, 27, 8),
  );
  await w.session.runs.setState(
    zero.id,
    RunState.finished,
    endedAt: DateTime.utc(2030, 2, 27, 8),
  );
  await calc.calculateAfterRun(zero.id);
  w.clock.set(recalcNow);
  await w.session.profile.save(profile180);
}

/// Der ganze Zwischenstand als Text, mit ALLEN Feldern jedes Werts und jedes
/// Abschnitts (Vergleich vorher/nachher, NFR-0001).
String snapshotDump(ValueSnapshot s) {
  final out = StringBuffer();
  void section(String name, Map<ValueOwner, List<ComputedValue>> m) {
    final owners = m.keys.toList()
      ..sort((a, b) => '${a.runId}/${a.day}'.compareTo('${b.runId}/${b.day}'));
    for (final o in owners) {
      for (final v in m[o]!) {
        out.writeln('$name ${o.runId}/${o.day} ${valueDump(v)}');
      }
    }
  }

  section('run', s.runValues);
  section('runCreate', s.runCreates);
  section('day', s.dayValues);
  section('dayCreate', s.dayCreates);
  out.writeln('removed ${s.removedDays.toList()..sort()}');
  return out.toString();
}

String valueDump(ComputedValue v) {
  final b = v.heartRateBasis;
  return [
    'key=${v.key}',
    'value=${v.value}',
    'unit=${v.unit}',
    'reason=${v.unavailableReason?.name}',
    'quality=${v.quality.name}',
    'method=${v.method}/${v.methodVersion}/p${v.parameterVersion}',
    'pre=${v.preprocessingVersion}',
    'basis=${b == null ? null : '${b.maxBpm}/${b.restingBpm}/${b.maxIsEstimated}'}',
    'n=${v.measurementCount}',
    'sources=${v.sources}',
    'at=${v.computedAt.toIso8601String()}',
    'from=${v.dataFrom?.toIso8601String()}',
    'to=${v.dataTo?.toIso8601String()}',
    'sections=${[for (final x in v.sections) _sectionDump(x)]}',
  ].join('|');
}

String _sectionDump(ValueSection s) => [
  s.start.toIso8601String(),
  s.end.toIso8601String(),
  s.weight,
  s.lateFactor,
  s.status.name,
  s.reasons,
  s.gpsMedianAccuracyMeters,
  s.discard?.name,
  s.oxygenDemand,
  s.estimate,
].join(';');
