import '../core.dart';
import 'contract_samples.dart';
import 'contract_support.dart';

final runContractCases = <StorageContractCase>[
  const StorageContractCase(
    'Läufe: anlegen, lesen, Liste, nicht beendete',
    _runs,
  ),
  const StorageContractCase(
    'Läufe: Zustandsregeln und unbekannter Lauf',
    _runRules,
  ),
  const StorageContractCase('Läufe: UTC-Versatz des Laufendes', _runEndOffset),
  const StorageContractCase('Runden und Lücken', _markers),
];

final rawContractCases = <StorageContractCase>[
  const StorageContractCase(
    'Rohdaten: anhängen und lesen, auch ohne Wert',
    _rawRoundtrip,
  ),
  const StorageContractCase(
    'Rohdaten: nur anhängen, Läufe getrennt',
    _rawAppend,
  ),
  const StorageContractCase('Rohdaten: Stapel ganz oder gar nicht', _rawAtomic),
  const StorageContractCase(
    'Rohdaten: fehlendes Tempo bleibt null, nie 0 (K12)',
    _rawSpeedNullNotZero,
  ),
];

Future<void> _runs(StorageContractHarness h) async {
  final s = await h.open();
  expectEq(await s.runs.list(), '[]', 'leere Liste');
  expectTrue(await s.runs.get(1) == null, 'unbekannter Lauf ist null');
  final a = await s.runs.create(startedAt: at(10, 5));
  final b = await s.runs.create(startedAt: at(20));
  expectTrue(a.id != b.id, 'Ids verschieden');
  expectEq(
    describeRun(a),
    '${a.id}|active|${us(at(10, 5))}|null/null|null',
    'angelegter Lauf',
  );
  expectEq(describeRun(await s.runs.get(a.id)), describeRun(a), 'lesen');
  expectEq((await s.runs.list()).map((r) => r.id), [
    b.id,
    a.id,
  ], 'neuester zuerst');
  await s.runs.setState(a.id, RunState.paused);
  expectEq((await s.runs.unfinished()).map((r) => r.id), [
    a.id,
    b.id,
  ], 'nicht beendete, ältester zuerst');
  await s.runs.setState(a.id, RunState.finished, endedAt: at(99, 1));
  expectEq(
    describeRun(await s.runs.get(a.id)),
    '${a.id}|finished|${us(at(10, 5))}|${us(at(99, 1))}|null',
    'beendet',
  );
  expectEq((await s.runs.unfinished()).map((r) => r.id), [
    b.id,
  ], 'beendeter fehlt bei nicht beendeten');
  // Zeitraum: from einschließlich, to ausschließlich, nur beendete,
  // frühestes Ende zuerst.
  final c = await s.runs.create(startedAt: at(30));
  await s.runs.setState(c.id, RunState.finished, endedAt: at(50));
  final e = await s.runs.create(startedAt: at(31));
  await s.runs.setState(e.id, RunState.finished, endedAt: at(120));
  Future<List<int>> between(int from, int to) async => [
    for (final r in await s.runs.finishedBetween(at(from), at(to))) r.id,
  ];
  expectEq(await between(0, 200), [c.id, a.id, e.id], 'Zeitraum: alle');
  expectEq(await between(50, 120), [c.id, a.id], 'Zeitraum: Grenzen');
  expectEq(await between(51, 99), <int>[], 'Zeitraum: leer');
  expectEq(await between(99, 121), [a.id, e.id], 'Zeitraum: Ende');
  await s.close();
}

Future<void> _runRules(StorageContractHarness h) async {
  final s = await h.open();
  final a = await s.runs.create(startedAt: at(0));
  await expectFails(
    () => s.runs.setState(a.id, RunState.finished),
    StorageFailure.rejected,
    'finished ohne Ende',
  );
  await expectFails(
    () => s.runs.setState(a.id, RunState.paused, endedAt: at(1)),
    StorageFailure.rejected,
    'Ende ohne finished',
  );
  await expectFails(
    () => s.runs.setState(999, RunState.paused),
    StorageFailure.notFound,
    'unbekannter Lauf',
  );
  expectEq(
    (await s.runs.get(a.id))!.state,
    RunState.active,
    'Zustand unverändert',
  );
  await s.runs.setState(a.id, RunState.finished, endedAt: at(1));
  await s.runs.setState(a.id, RunState.active);
  expectEq(
    describeRun(await s.runs.get(a.id)),
    '${a.id}|active|${us(at(0))}|null/null|null',
    'Wiederaufnahme löscht das Ende',
  );
  await s.close();
}

Future<void> _runEndOffset(StorageContractHarness h) async {
  final s = await h.open();
  final a = await s.runs.create(startedAt: at(0));
  final b = await s.runs.create(startedAt: at(0));
  const offset = Duration(hours: 5, minutes: 30);
  await s.runs.setState(
    a.id,
    RunState.finished,
    endedAt: at(9),
    endedUtcOffset: offset,
  );
  expectEq(
    describeRun(await s.runs.get(a.id)),
    '${a.id}|finished|${us(at(0))}|${us(at(9))}|${offset.inSeconds}',
    'Versatz gespeichert',
  );
  expectEq(
    describeRun((await s.runs.list()).firstWhere((r) => r.id == a.id)),
    describeRun(await s.runs.get(a.id)),
    'Liste liefert ihn auch',
  );
  await s.runs.setState(
    b.id,
    RunState.finished,
    endedAt: at(9),
    endedUtcOffset: const Duration(hours: -3),
  );
  expectEq(
    (await s.runs.get(b.id))!.endedUtcOffset,
    const Duration(hours: -3),
    'negativer Versatz',
  );
  // Ohne Angabe bleibt er unbekannt, auch nach erneutem Beenden.
  await s.runs.setState(a.id, RunState.finished, endedAt: at(10));
  expectEq(
    (await s.runs.get(a.id))!.endedUtcOffset,
    null,
    'ohne Angabe unbekannt',
  );
  // Wiederaufnahme löscht Ende und Versatz.
  await s.runs.setState(b.id, RunState.active);
  expectEq((await s.runs.get(b.id))!.endedUtcOffset, null, 'Wiederaufnahme');
  final before = describeRun(await s.runs.get(a.id));
  for (final (name, state, end, off)
      in <(String, RunState, DateTime?, Duration)>[
        ('ohne Ende', RunState.active, null, offset),
        ('bei paused mit Ende', RunState.paused, at(1), offset),
        (
          'über 18 Stunden',
          RunState.finished,
          at(1),
          const Duration(hours: 19),
        ),
        (
          'unter -18 Stunden',
          RunState.finished,
          at(1),
          const Duration(hours: -19),
        ),
        (
          'keine ganzen Sekunden',
          RunState.finished,
          at(1),
          const Duration(seconds: 1, milliseconds: 500),
        ),
      ]) {
    await expectFails(
      () => s.runs.setState(a.id, state, endedAt: end, endedUtcOffset: off),
      StorageFailure.rejected,
      'Versatz $name',
    );
  }
  expectEq(
    describeRun(await s.runs.get(a.id)),
    before,
    'abgelehnt ändert nichts',
  );
  await s.close();
}

Future<void> _markers(StorageContractHarness h) async {
  final s = await h.open();
  final r = (await s.runs.create(startedAt: at(0))).id;
  final other = (await s.runs.create(startedAt: at(0))).id;
  await s.markers.addLap(
    r,
    StoredLap(
      index: 2,
      markedAt: at(20, 7),
      lapTime: const Duration(seconds: 301, microseconds: 500000),
    ),
  );
  await s.markers.addLap(
    r,
    StoredLap(
      index: 1,
      markedAt: at(10),
      lapTime: const Duration(seconds: 300),
    ),
  );
  await s.markers.addLap(
    other,
    StoredLap(index: 1, markedAt: at(10), lapTime: Duration.zero),
  );
  final laps = await s.markers.laps(r);
  expectEq(
    laps.map((l) => '${l.index}|${us(l.markedAt)}|${l.lapTime.inMicroseconds}'),
    ['1|${us(at(10))}|300000000', '2|${us(at(20, 7))}|301500000'],
    'Runden sortiert',
  );
  await expectFails(
    () => s.markers.addLap(
      r,
      StoredLap(index: 1, markedAt: at(30), lapTime: Duration.zero),
    ),
    StorageFailure.rejected,
    'doppelte Rundennummer',
  );
  await expectFails(
    () => s.markers.addLap(
      999,
      StoredLap(index: 1, markedAt: at(30), lapTime: Duration.zero),
    ),
    StorageFailure.notFound,
    'Runde an unbekanntem Lauf',
  );
  expectEq((await s.markers.laps(r)).length, 2, 'Fehler schreibt nichts');

  final g2 = await s.markers.openGap(r, RunGapKind.heartRateLoss, at(50));
  final g1 = await s.markers.openGap(r, RunGapKind.positionLoss, at(40, 3));
  expectEq(
    (await s.markers.gaps(r)).map(
      (g) =>
          '${g.id == g1 ? 'g1' : 'g2'}|${g.kind.name}|${us(g.start)}|${us(g.end)}',
    ),
    [
      'g1|positionLoss|${us(at(40, 3))}|null/null',
      'g2|heartRateLoss|${us(at(50))}|null/null',
    ],
    'offene Lücken sortiert',
  );
  await s.markers.closeGap(g1, at(45, 9));
  expectEq(
    us((await s.markers.gaps(r)).first.end),
    us(at(45, 9)),
    'Lücke geschlossen',
  );
  await expectFails(
    () => s.markers.closeGap(g1, at(46)),
    StorageFailure.rejected,
    'zweites Schließen',
  );
  await expectFails(
    () => s.markers.closeGap(99999, at(46)),
    StorageFailure.notFound,
    'unbekannte Lücke',
  );
  await expectFails(
    () => s.markers.openGap(999, RunGapKind.interruption, at(1)),
    StorageFailure.notFound,
    'Lücke an unbekanntem Lauf',
  );
  expectEq(
    (await s.markers.gaps(other)).length,
    0,
    'Lücken anderer Läufe getrennt',
  );
  expectTrue(g2 != g1, 'Lücken-Ids verschieden');
  await s.close();
}

String _positions(StoredRawData d) => d.positions
    .map(
      (p) =>
          '${us(p.value.time)}|${p.value.source}|${p.value.latitude}|${p.value.longitude}|${p.value.accuracyMeters}|${p.value.speedMetersPerSecond}|${p.value.speedAccuracyMetersPerSecond}|${p.value.verticalAccuracyMeters}|${p.value.state.name}',
    )
    .join(';');

Future<void> _rawRoundtrip(StorageContractHarness h) async {
  final s = await h.open();
  final r = (await s.runs.create(startedAt: at(0))).id;
  await s.rawData.append(r, sampleBatch());
  final d = await s.rawData.read(r);
  expectEq(
    _positions(d),
    '${us(at(1))}|gps|52.0|13.0|null|null|null|null|estimated;${us(at(2, 123457))}|gps|52.5|13.25|4.5|3.25|0.5|2.5|present',
    'Positionen nach Zeit sortiert, Mikrosekunden, fehlende Werte null '
        '(Tempo, Tempo- und Vertikalgenauigkeit, K12)',
  );
  expectEq(
    d.heartRates.map(
      (x) =>
          '${x.value.bpm}|${x.value.contact.name}|${x.value.state.name}|${x.value.source}',
    ),
    ['140|good|present|strap'],
    'Puls',
  );
  expectEq(
    d.altitudes.map(
      (x) => '${x.value.meters}|${x.value.verticalAccuracyMeters}',
    ),
    ['35.5|3.0'],
    'Höhe',
  );
  expectEq(d.steps.map((x) => '${x.value.count}|${x.value.source}'), [
    '12|phone',
  ], 'Schritte');
  expectEq(
    d.unavailable.map(
      (x) =>
          '${x.value.channel.name}|${us(x.value.time)}|${x.value.source}|${x.value.state.name}',
    ),
    ['heartRate|${us(at(3))}|strap|unavailable'],
    'Zeile ohne Wert',
  );
  expectEq(d.heartRates.length, 1, 'Zeile ohne Wert zählt nicht als Pulswert');
  expectEq(
    {...d.positions.map((p) => p.id)}.length,
    2,
    'Ids der Positionen verschieden',
  );
  await s.close();
}

Future<void> _rawAppend(StorageContractHarness h) async {
  final s = await h.open();
  final r = (await s.runs.create(startedAt: at(0))).id;
  final other = (await s.runs.create(startedAt: at(0))).id;
  await s.rawData.append(r, sampleBatch());
  await s.rawData.append(
    r,
    RawBatch(
      steps: [RawSteps(time: at(9), source: 'phone', count: 99)],
    ),
  );
  await s.rawData.append(r, const RawBatch());
  await s.rawData.append(
    other,
    RawBatch(
      steps: [RawSteps(time: at(1), source: 'x', count: 1)],
    ),
  );
  final d = await s.rawData.read(r);
  expectEq(d.steps.map((x) => x.value.count), [
    12,
    99,
  ], 'zweiter Stapel hängt an');
  expectEq(d.positions.length, 2, 'erste Zeilen bleiben');
  expectEq(
    (await s.rawData.read(other)).steps.length,
    1,
    'anderer Lauf getrennt',
  );
  final again = await s.rawData.read(r);
  expectEq(
    again.steps.map((x) => x.id),
    d.steps.map((x) => x.id),
    'Ids stabil beim erneuten Lesen',
  );
  await s.close();
}

/// K12: Ein echter Wert 0 bleibt 0, ein fehlender bleibt null (nie 0).
Future<void> _rawSpeedNullNotZero(StorageContractHarness h) async {
  final s = await h.open();
  final r = (await s.runs.create(startedAt: at(0))).id;
  await s.rawData.append(
    r,
    RawBatch(
      positions: [
        RawPosition(
          time: at(1),
          source: 'gps',
          latitude: 1,
          longitude: 2,
          speedMetersPerSecond: 0,
          speedAccuracyMetersPerSecond: 0,
          verticalAccuracyMeters: 0,
        ),
        RawPosition(time: at(2), source: 'gps', latitude: 1, longitude: 2),
      ],
    ),
  );
  final p = (await s.rawData.read(r)).positions.map((x) => x.value).toList();
  expectEq(
    '${p[0].speedMetersPerSecond}|${p[0].speedAccuracyMetersPerSecond}|${p[0].verticalAccuracyMeters}',
    '0.0|0.0|0.0',
    'gelieferte Nullen bleiben 0',
  );
  expectTrue(
    p[1].speedMetersPerSecond == null &&
        p[1].speedAccuracyMetersPerSecond == null &&
        p[1].verticalAccuracyMeters == null,
    'fehlende Werte bleiben null, nie 0',
  );
  await expectFails(
    () => s.rawData.append(
      r,
      RawBatch(
        positions: [
          RawPosition(
            time: at(3),
            source: 'gps',
            latitude: 1,
            longitude: 2,
            speedMetersPerSecond: double.nan,
          ),
        ],
      ),
    ),
    StorageFailure.rejected,
    'NaN im Tempo',
  );
  await s.close();
}

Future<void> _rawAtomic(StorageContractHarness h) async {
  final s = await h.open();
  final r = (await s.runs.create(startedAt: at(0))).id;
  final bad = RawBatch(
    steps: [RawSteps(time: at(1), source: 'phone', count: 1)],
    positions: [
      RawPosition(
        time: at(1),
        source: 'gps',
        latitude: double.nan,
        longitude: 1,
      ),
    ],
  );
  await expectFails(
    () => s.rawData.append(r, bad),
    StorageFailure.rejected,
    'nicht endlicher Wert',
  );
  expectEq(
    (await s.rawData.read(r)).steps.length,
    0,
    'nichts aus dem fehlerhaften Stapel',
  );
  await expectFails(
    () => s.rawData.append(999, sampleBatch()),
    StorageFailure.notFound,
    'unbekannter Lauf',
  );
  expectEq(
    (await s.rawData.read(999)).positions.length,
    0,
    'Lesen eines unbekannten Laufs ist leer',
  );
  await s.close();
}
