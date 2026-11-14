import '../core.dart';
import 'contract_support.dart';

/// Vertrag der Morgenmessungen (WP33 Teil B). Der Speicher muss
/// [MorningStorage] sein. Nur synthetische Werte.
final List<StorageContractCase> morningContractCases = [
  const StorageContractCase(
    'Morgenmessung: Rundgang aller Felder samt Gurt-RR, Neuöffnen',
    _roundTrip,
  ),
  const StorageContractCase(
    'Morgenmessung: ungültige Werte und Pakete werden abgelehnt, nichts bleibt',
    _rejected,
  ),
  const StorageContractCase(
    'Morgenmessung: Reihenfolge, Gurt-RR je Messung, unbekannte Messung',
    _order,
  ),
  const StorageContractCase(
    'Morgenmessung übersteht das Löschen eines Laufs, Alles löschen leert sie',
    _delete,
  ),
];

MorningStore _m(StorageSession s) => (s as MorningStorage).morning;

MorningMeasurement _measurement(
  int seconds, {
  double bpm = 52.34,
  double? rmssd = 41.5,
  double? noise = 12.25,
  SleepBand? band = SleepBand.from6to7,
  RestingPosture posture = RestingPosture.lying,
  PpgQuality quality = PpgQuality.good,
  List<double> ibi = const [1100.5, 1180.25, 1150.0],
  bool before = true,
  bool outside = false,
  Duration offset = const Duration(hours: 1),
}) => MorningMeasurement(
  measuredAt: at(seconds),
  utcOffset: offset,
  posture: posture,
  deviceManufacturer: 'Testhersteller',
  deviceModel: 'Testmodell 1',
  method: ppgMethod,
  methodVersion: ppgMethodVersion,
  quality: quality,
  restingHrBpm: bpm,
  rmssdMs: rmssd,
  timingNoiseMs: noise,
  sleepBand: band,
  cameraIntervalsMs: ibi,
  beforeValidation: before,
  outsideWindow: outside,
);

RrPacket _packet(int seconds, List<int> rr, [String source = 'gurt-1']) =>
    RrPacket(time: at(seconds, 7), source: source, intervals: rr);

String _fields(MorningMeasurement m) => [
  us(m.measuredAt),
  m.utcOffset.inSeconds,
  m.posture.name,
  m.deviceManufacturer,
  m.deviceModel,
  m.method,
  m.methodVersion,
  m.quality.name,
  m.restingHrBpm,
  m.rmssdMs,
  m.timingNoiseMs,
  m.sleepBand?.code,
  m.cameraIntervalsMs,
  m.beforeValidation,
  m.outsideWindow,
].join('|');

String _packets(List<StoredRrPacket> p) => [
  for (final x in p)
    '${us(x.value.time)}/${x.value.source}/${x.value.intervals}',
].join(';');

Future<void> _roundTrip(StorageContractHarness h) async {
  var s = await h.open();
  final a = _measurement(0);
  final packets = [
    _packet(1, [1024, 1000, 65535]),
    _packet(2, [0, 900]),
  ];
  final id = await _m(s).add(a, beltPackets: packets);
  // Zweite Messung: alles Optionale leer, sitzend, eingeschränkt, ohne Gurt.
  final b = _measurement(
    100,
    bpm: 60.05,
    rmssd: null,
    noise: null,
    band: null,
    posture: RestingPosture.sitting,
    quality: PpgQuality.limited,
    ibi: const [],
    before: false,
    outside: true,
    offset: const Duration(hours: -3, minutes: -30),
  );
  final idB = await _m(s).add(b);
  for (var round = 0; round < 2; round++) {
    final list = await _m(s).list();
    expectEq(list.map((e) => e.id), [id, idB], 'Ids (Runde $round)');
    // Ruhepuls mit einer Nachkommastelle: 52.34 -> 52.3, 60.05 -> 60.1.
    expectEq(
      _fields(list[0].value),
      _fields(_measurement(0, bpm: 52.3, ibi: const [1100.5, 1180.25, 1150.0])),
      'Felder A (Runde $round)',
    );
    expectEq(list[1].value.restingHrBpm, 60.1, 'Rundung B');
    expectTrue(list[1].value.rmssdMs == null, 'RMSSD unbekannt bleibt null');
    expectTrue(list[1].value.timingNoiseMs == null, 'Zeitrauschen null');
    expectTrue(list[1].value.sleepBand == null, 'Schlafstufe null');
    expectEq(list[1].value.cameraIntervalsMs, <double>[], 'keine Abstände');
    expectEq(list[1].value.utcOffset.inSeconds, -12600, 'Versatz negativ');
    expectEq(list[1].value.posture, RestingPosture.sitting, 'Haltung B');
    expectEq(list[1].value.quality, PpgQuality.limited, 'Qualität B');
    expectEq(list[1].value.beforeValidation, false, 'Merkmal Validierung B');
    expectEq(list[1].value.outsideWindow, true, 'Merkmal Fenster B');
    expectTrue(list[0].value.measuredAt.isUtc, 'Zeit in UTC');
    expectEq(
      _packets(await _m(s).beltPackets(id)),
      _packets([
        for (var i = 0; i < packets.length; i++)
          StoredRrPacket(i + 1, packets[i]),
      ]),
      'Gurt-RR bitgenau (Runde $round)',
    );
    expectEq(await _m(s).beltPackets(idB), <StoredRrPacket>[], 'ohne Gurt');
    await s.close();
    s = await h.open();
  }
  await s.close();
}

Future<void> _rejected(StorageContractHarness h) async {
  final s = await h.open();
  final bad = <String, MorningMeasurement>{
    'unbrauchbar': _measurement(0, quality: PpgQuality.unusable),
    'Puls NaN': _measurement(0, bpm: double.nan),
    'Puls 0': _measurement(0, bpm: 0),
    'RMSSD negativ': _measurement(0, rmssd: -1),
    'Zeitrauschen unendlich': _measurement(0, noise: double.infinity),
    'Abstand 0': _measurement(0, ibi: const [0.0]),
    'Versatz zu groß': _measurement(0, offset: const Duration(hours: 19)),
  };
  for (final e in bad.entries) {
    await expectFails(() => _m(s).add(e.value), StorageFailure.rejected, e.key);
  }
  await expectFails(
    () => _m(s).add(
      _measurement(0),
      beltPackets: [
        _packet(1, [1000]),
        _packet(2, [70000]),
      ],
    ),
    StorageFailure.rejected,
    'RR über uint16',
  );
  await expectFails(
    () => _m(s).add(_measurement(0), beltPackets: [_packet(1, [])]),
    StorageFailure.rejected,
    'leeres Paket',
  );
  expectEq(
    (await _m(s).list()).length,
    0,
    'nichts geschrieben (auch nicht die Messung)',
  );
  await s.close();
}

Future<void> _order(StorageContractHarness h) async {
  final s = await h.open();
  final late = await _m(s).add(_measurement(500));
  final early = await _m(s).add(
    _measurement(10),
    beltPackets: [
      _packet(30, [1000]),
      _packet(20, [1001]),
    ],
  );
  final other = await _m(s).add(
    _measurement(20),
    beltPackets: [
      _packet(5, [999], 'gurt-2'),
    ],
  );
  expectEq((await _m(s).list()).map((e) => e.id), [
    early,
    other,
    late,
  ], 'nach Zeitpunkt sortiert');
  expectEq(
    (await _m(s).beltPackets(early)).map((p) => p.value.intervals.single),
    [1001, 1000],
    'nach Empfangszeit sortiert',
  );
  expectEq((await _m(s).beltPackets(other)).map((p) => p.value.source), [
    'gurt-2',
  ], 'Pakete nur der eigenen Messung');
  await expectFails(
    () => _m(s).beltPackets(999),
    StorageFailure.notFound,
    'unbekannte Messung',
  );
  await s.close();
}

Future<void> _delete(StorageContractHarness h) async {
  var s = await h.open();
  final run = (await s.runs.create(startedAt: at(0))).id;
  final id = await _m(s).add(
    _measurement(0),
    beltPackets: [
      _packet(1, [1000]),
    ],
  );
  await s.deleteRun(run);
  expectEq((await _m(s).list()).length, 1, 'Messung übersteht deleteRun');
  expectEq(
    (await _m(s).beltPackets(id)).length,
    1,
    'Gurt-RR übersteht deleteRun',
  );
  await s.deleteAll();
  expectEq((await _m(s).list()).length, 0, 'Messungen nach Alles löschen');
  await expectFails(
    () => _m(s).beltPackets(id),
    StorageFailure.notFound,
    'Gurt-RR nach Alles löschen',
  );
  await s.close();
  s = await h.open();
  expectEq((await _m(s).list()).length, 0, 'nach Neuöffnen leer');
  // Zähler zurückgesetzt: die erste Messung nach dem Löschen hat wieder Id 1.
  expectEq(await _m(s).add(_measurement(0)), 1, 'Id-Zähler zurückgesetzt');
  await s.close();
}
