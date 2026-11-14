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
    'Morgenmessung: Schlafstufe nachtragen ändert nur sie, unbekannte Messung',
    _sleepBand,
  ),
  const StorageContractCase(
    'Morgenmessung: Fenster, Ruhe-Übersprung, unbrauchbare Stufe, Kamera-Rohsignal bitgenau',
    _extended,
  ),
  const StorageContractCase(
    'Morgenmessung: ungültiges Fenster, Grund oder Rohsignal wird abgelehnt, nichts bleibt',
    _extendedRejected,
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
  double? windowStart,
  double? windowEnd,
  double? skippedAfter,
  PpgQualityReason? reason,
}) => MorningMeasurement(
  measuredAt: at(seconds),
  utcOffset: offset,
  posture: posture,
  deviceManufacturer: 'Testhersteller',
  deviceModel: 'Testmodell 1',
  method: ppgMethod,
  methodVersion: ppgMethodVersion,
  quality: quality,
  restingHrBpm: quality == PpgQuality.unusable ? null : bpm,
  windowStartS: windowStart,
  windowEndS: windowEnd,
  restSkippedAfterS: skippedAfter,
  unusableReason: reason,
  rmssdMs: rmssd,
  timingNoiseMs: noise,
  sleepBand: band,
  cameraIntervalsMs: ibi,
  beforeValidation: before,
  outsideWindow: outside,
);

PpgFrame _frame(double t) => PpgFrame(
  t: t,
  r: 200.0 + t / 3,
  g: 40.5 + t / 7,
  r16: [for (var i = 0; i < 16; i++) 190.0 + i + t / 11],
  g16: [for (var i = 0; i < 16; i++) 38.0 + i / 3 + t / 13],
);

MorningRawSignal _raw({
  List<PpgFrame>? frames,
  int? exposure = 16666666,
  int? iso = 100,
  CameraTimestampSource? source = CameraTimestampSource.realtime,
  int? skew = 12000000,
  int? torch = 1,
  int gaps = 2,
  double gapS = 0.35,
  double? saturated = 0.0125,
}) => MorningRawSignal(
  frames: frames ?? [_frame(0.033), _frame(0.0667), _frame(0.1)],
  exposureTimeNs: exposure,
  iso: iso,
  timestampSource: source,
  rollingShutterSkewNs: skew,
  torchStrength: torch,
  frameGapCount: gaps,
  frameGapTotalS: gapS,
  saturatedFraction: saturated,
);

String _rawFields(MorningRawSignal r) => [
  for (final f in r.frames) [f.t, f.r, f.g, ...f.r16, ...f.g16].join(','),
  r.exposureTimeNs,
  r.iso,
  r.timestampSource?.code,
  r.rollingShutterSkewNs,
  r.torchStrength,
  r.frameGapCount,
  r.frameGapTotalS,
  r.saturatedFraction,
].join('|');

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
  m.windowStartS,
  m.windowEndS,
  m.restSkippedAfterS,
  m.unusableReason?.name,
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

Future<void> _extended(StorageContractHarness h) async {
  var s = await h.open();
  final a = _measurement(
    0,
    windowStart: 5.5,
    windowEnd: 65.5,
    skippedAfter: 37.25,
  );
  final raw = _raw();
  final idA = await _m(s).add(a, rawSignal: raw);
  // Unbrauchbar: ohne Puls, mit Grund, ohne Fenster, Rohsignal ohne
  // Kamera-Angaben (alles nicht geliefert) und ohne Bilder.
  final b = _measurement(
    100,
    quality: PpgQuality.unusable,
    rmssd: null,
    noise: null,
    ibi: const [],
    reason: PpgQualityReason.noFinger,
  );
  final rawB = _raw(
    frames: const [],
    exposure: null,
    iso: null,
    source: null,
    skew: null,
    torch: null,
    gaps: 0,
    gapS: 0,
    saturated: null,
  );
  final idB = await _m(s).add(b, rawSignal: rawB);
  final idC = await _m(s).add(_measurement(200));
  for (var round = 0; round < 2; round++) {
    final list = await _m(s).list();
    expectEq(list.map((e) => e.id), [idA, idB, idC], 'Ids (Runde $round)');
    expectEq(
      _fields(list[0].value),
      _fields(
        _measurement(
          0,
          bpm: 52.3,
          windowStart: 5.5,
          windowEnd: 65.5,
          skippedAfter: 37.25,
        ),
      ),
      'Fenster und Übersprung (Runde $round)',
    );
    expectEq(list[1].value.quality, PpgQuality.unusable, 'Stufe unbrauchbar');
    expectTrue(list[1].value.restingHrBpm == null, 'kein Puls');
    expectTrue(list[1].value.roundedRestingHr == null, 'kein gerundeter Puls');
    expectEq(list[1].value.unusableReason, PpgQualityReason.noFinger, 'Grund');
    expectTrue(!list[1].value.isUsable, 'unbrauchbar zählt nicht');
    expectTrue(list[2].value.windowStartS == null, 'Fenster unbekannt');
    expectTrue(list[2].value.restSkippedAfterS == null, 'nicht übersprungen');
    expectEq(
      _rawFields((await _m(s).rawSignal(idA))!),
      _rawFields(raw),
      'Rohsignal bitgenau (Runde $round)',
    );
    final gotB = (await _m(s).rawSignal(idB))!;
    expectEq(_rawFields(gotB), _rawFields(rawB), 'leeres Rohsignal');
    expectTrue(gotB.timestampSource == null, 'Zeitstempelquelle unbekannt');
    expectTrue(
      await _m(s).rawSignal(idC) == null,
      'ohne Rohsignal null (nicht im Entwicklermodus)',
    );
    await expectFails(
      () => _m(s).rawSignal(idC + 99),
      StorageFailure.notFound,
      'unbekannte Messung',
    );
    await s.close();
    s = await h.open();
  }
  await s.close();
}

Future<void> _extendedRejected(StorageContractHarness h) async {
  final s = await h.open();
  final bad = <String, MorningMeasurement>{
    'Fenster ohne Ende': _measurement(0, windowStart: 5),
    'Fenster verkehrt': _measurement(0, windowStart: 65, windowEnd: 5),
    'Fenster leer': _measurement(0, windowStart: 5, windowEnd: 5),
    'Fenster negativ': _measurement(0, windowStart: -1, windowEnd: 5),
    'Übersprung negativ': _measurement(0, skippedAfter: -1),
    'Übersprung NaN': _measurement(0, skippedAfter: double.nan),
    'Grund bei brauchbarer Messung': _measurement(
      0,
      reason: PpgQualityReason.weakSignal,
    ),
    'unbrauchbar mit Puls': MorningMeasurement(
      measuredAt: at(0),
      utcOffset: Duration.zero,
      posture: RestingPosture.lying,
      deviceManufacturer: 'H',
      deviceModel: 'M',
      method: ppgMethod,
      methodVersion: ppgMethodVersion,
      quality: PpgQuality.unusable,
      restingHrBpm: 50,
      cameraIntervalsMs: const [],
      beforeValidation: false,
      outsideWindow: false,
    ),
    'brauchbar ohne Puls': MorningMeasurement(
      measuredAt: at(0),
      utcOffset: Duration.zero,
      posture: RestingPosture.lying,
      deviceManufacturer: 'H',
      deviceModel: 'M',
      method: ppgMethod,
      methodVersion: ppgMethodVersion,
      quality: PpgQuality.good,
      cameraIntervalsMs: const [],
      beforeValidation: false,
      outsideWindow: false,
    ),
  };
  for (final e in bad.entries) {
    await expectFails(() => _m(s).add(e.value), StorageFailure.rejected, e.key);
  }
  final badRaw = <String, MorningRawSignal>{
    'Bild ohne 16 Teilbereiche': _raw(
      frames: [
        PpgFrame(t: 0, r: 1, g: 1, r16: const [1], g16: List.filled(16, 1)),
      ],
    ),
    'Bild nicht endlich': _raw(
      frames: [
        PpgFrame(
          t: double.nan,
          r: 1,
          g: 1,
          r16: List.filled(16, 1),
          g16: List.filled(16, 1),
        ),
      ],
    ),
    'Belichtung 0': _raw(exposure: 0),
    'ISO 0': _raw(iso: 0),
    'Versatz negativ': _raw(skew: -1),
    'Torch negativ': _raw(torch: -1),
    'Lücken negativ': _raw(gaps: -1),
    'Lückendauer negativ': _raw(gapS: -0.1),
    'Sättigung über 1': _raw(saturated: 1.5),
  };
  for (final e in badRaw.entries) {
    await expectFails(
      () => _m(s).add(_measurement(0), rawSignal: e.value),
      StorageFailure.rejected,
      e.key,
    );
  }
  expectEq((await _m(s).list()).length, 0, 'nichts geschrieben');
  await s.close();
}

Future<void> _rejected(StorageContractHarness h) async {
  final s = await h.open();
  final bad = <String, MorningMeasurement>{
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
    rawSignal: _raw(),
  );
  await s.deleteRun(run);
  expectEq((await _m(s).list()).length, 1, 'Messung übersteht deleteRun');
  expectEq(
    (await _m(s).beltPackets(id)).length,
    1,
    'Gurt-RR übersteht deleteRun',
  );
  expectTrue(
    await _m(s).rawSignal(id) != null,
    'Rohsignal übersteht deleteRun',
  );
  await s.deleteAll();
  expectEq((await _m(s).list()).length, 0, 'Messungen nach Alles löschen');
  await expectFails(
    () => _m(s).beltPackets(id),
    StorageFailure.notFound,
    'Gurt-RR nach Alles löschen',
  );
  await expectFails(
    () => _m(s).rawSignal(id),
    StorageFailure.notFound,
    'Rohsignal nach Alles löschen',
  );
  await s.close();
  s = await h.open();
  expectEq((await _m(s).list()).length, 0, 'nach Neuöffnen leer');
  // Zähler zurückgesetzt: die erste Messung nach dem Löschen hat wieder Id 1.
  expectEq(await _m(s).add(_measurement(0)), 1, 'Id-Zähler zurückgesetzt');
  await s.close();
}

Future<void> _sleepBand(StorageContractHarness h) async {
  var s = await h.open();
  final id = await _m(s).add(_measurement(0, band: null));
  final other = await _m(s).add(_measurement(10, band: SleepBand.under5));
  await _m(s).setSleepBand(id, SleepBand.over8);
  for (var round = 0; round < 2; round++) {
    final list = await _m(s).list();
    expectEq(
      _fields(list[0].value),
      _fields(_measurement(0, bpm: 52.3, band: SleepBand.over8)),
      'nur die Schlafstufe ändert sich (Runde $round)',
    );
    expectEq(list[1].value.sleepBand, SleepBand.under5, 'andere unberührt');
    await s.close();
    s = await h.open();
  }
  await _m(s).setSleepBand(id, null);
  expectTrue(
    (await _m(s).list()).first.value.sleepBand == null,
    'Schlafstufe löschen',
  );
  await expectFails(
    () => _m(s).setSleepBand(other + 99, SleepBand.from5to6),
    StorageFailure.notFound,
    'unbekannte Messung',
  );
  await s.close();
}
