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
    'Morgenmessung: Schlafstufe an mehreren Messungen löschen, Neuöffnen',
    _clearSleepBands,
  ),
  const StorageContractCase(
    'Morgenmessung: Schlafstufen löschen mit unbekannter Messung ändert nichts',
    _clearSleepBandsRollback,
  ),
  const StorageContractCase(
    'Morgenmessung: Schlafstufen löschen, leere Liste und doppelte Id',
    _clearSleepBandsEdges,
  ),
  const StorageContractCase(
    'Morgenmessung: Wahl setzt sie und löscht die der Reihe am Ortstag, Neuöffnen',
    _choose,
  ),
  const StorageContractCase(
    'Morgenmessung: Wahl unbekannt oder nicht wählbar ändert nichts, Neuöffnen',
    _chooseRejected,
  ),
  const StorageContractCase(
    'Morgenmessung: Wahl übernimmt die Schlafstufe des Tages',
    _chooseSleepBand,
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
  MorningUnusableReason? reason,
  String model = 'Testmodell 1',
  bool chosen = false,
}) => MorningMeasurement(
  measuredAt: at(seconds),
  utcOffset: offset,
  posture: posture,
  deviceManufacturer: 'Testhersteller',
  deviceModel: model,
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
  chosen: chosen,
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
  String? cameraId = '0',
  String? physicalCameraId = '2',
  double? focal = 2.2,
  List<List<double>>? isp,
  Set<PpgCameraDiagnostic> diagnostics = const {},
  PpgAwbVariant? awb,
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
  cameraId: cameraId,
  physicalCameraId: physicalCameraId,
  focalLengthMm: focal,
  ispFrames: isp,
  diagnostics: diagnostics,
  awbVariant: awb,
);

/// Synthetische Werte der Bildverarbeitung je Bild (19, mit nicht gemeldeten).
List<double> _isp(int i) => [
  for (var k = 0; k < ppgIspValueCount; k++)
    k == 16
        ? 10.0 + i / 3
        : k == 18 || (i == 1 && k < 4)
        ? double.nan
        : (k * 7 + i).toDouble(),
];

/// Bitgenau, auch `NaN` (über die gespeicherte Form).
String _ispBits(List<List<double>>? v) =>
    v == null ? 'null' : encodeIspFrames(v).join(',');

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
  r.cameraId,
  r.physicalCameraId,
  r.focalLengthMm,
  _ispBits(r.ispFrames),
  [for (final d in PpgCameraDiagnostic.values) r.diagnostics.contains(d)],
  r.awbVariant?.wire,
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
  m.chosen,
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
  // Mit Werten der Bildverarbeitung (auch nicht gemeldet = NaN) und Schaltern.
  final raw = _raw(
    isp: [_isp(0), _isp(1), _isp(2)],
    diagnostics: const {
      PpgCameraDiagnostic.noiseReductionOff,
      PpgCameraDiagnostic.awbFixed,
      PpgCameraDiagnostic.shadingOff,
    },
    awb: PpgAwbVariant.lock,
  );
  final idA = await _m(s).add(a, rawSignal: raw);
  // Unbrauchbar: ohne Puls, mit Grund, ohne Fenster, Rohsignal ohne
  // Kamera-Angaben (alles nicht geliefert) und ohne Bilder.
  final b = _measurement(
    100,
    quality: PpgQuality.unusable,
    rmssd: null,
    noise: null,
    ibi: const [],
    reason: MorningUnusableReason.restingHrOutOfRange,
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
    cameraId: null,
    physicalCameraId: null,
    focal: null,
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
    expectEq(
      list[1].value.unusableReason,
      MorningUnusableReason.restingHrOutOfRange,
      'Grund',
    );
    expectTrue(!list[1].value.isUsable, 'unbrauchbar zählt nicht');
    expectTrue(list[2].value.windowStartS == null, 'Fenster unbekannt');
    expectTrue(list[2].value.restSkippedAfterS == null, 'nicht übersprungen');
    expectEq(
      _rawFields((await _m(s).rawSignal(idA))!),
      _rawFields(raw),
      'Rohsignal bitgenau (Runde $round)',
    );
    final gotA = (await _m(s).rawSignal(idA))!;
    expectTrue(gotA.ispFrames![1][0].isNaN, 'nicht gemeldet bleibt NaN');
    expectTrue(gotA.withCameraDiagnostics, 'Merkmal Diagnose-Einstellung');
    final gotB = (await _m(s).rawSignal(idB))!;
    expectEq(_rawFields(gotB), _rawFields(rawB), 'leeres Rohsignal');
    expectTrue(gotB.ispFrames == null, 'ohne ISP-Werte null');
    expectTrue(gotB.diagnostics.isEmpty, 'ohne Schalter keine');
    expectTrue(!gotB.withCameraDiagnostics, 'ohne Schalter kein Merkmal');
    expectTrue(gotB.awbVariant == null, 'ohne Variante');
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
      reason: MorningUnusableReason.weakSignal,
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
    'unbrauchbar mit RMSSD': _measurement(
      0,
      quality: PpgQuality.unusable,
      noise: null,
      reason: MorningUnusableReason.noFinger,
    ),
    'unbrauchbar mit Zeitrauschen': _measurement(
      0,
      quality: PpgQuality.unusable,
      rmssd: null,
      reason: MorningUnusableReason.noFinger,
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
    'physische Kamera ohne Kamera-ID': _raw(cameraId: null),
    'Brennweite 0': _raw(focal: 0),
    'Brennweite negativ': _raw(focal: -1.5),
    'Brennweite nicht endlich': _raw(focal: double.nan),
    'ISP-Werte nicht je Bild': _raw(isp: [_isp(0)]),
    'ISP-Werte nicht 19': _raw(isp: [_isp(0), _isp(1), _isp(2).sublist(1)]),
    'ISP-Wert unendlich': _raw(
      isp: [_isp(0), _isp(1), List.filled(19, double.infinity)],
    ),
    'Weißabgleich-Variante ohne Schalter': _raw(awb: PpgAwbVariant.matrix),
    'mehr Bilder als morningRawMaxFrames': _raw(
      frames: List.filled(morningRawMaxFrames + 1, _frame(0.5)),
    ),
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

Future<void> _clearSleepBands(StorageContractHarness h) async {
  var s = await h.open();
  final a = await _m(s).add(_measurement(0, band: SleepBand.over8));
  final b = await _m(s).add(_measurement(10, band: SleepBand.under5));
  final c = await _m(s).add(_measurement(20, band: SleepBand.from5to6));
  await _m(s).clearSleepBands([a, b]);
  for (var round = 0; round < 2; round++) {
    final byId = {for (final e in await _m(s).list()) e.id: e.value};
    expectEq(
      _fields(byId[a]!),
      _fields(_measurement(0, bpm: 52.3, band: null)),
      'a: nur die Schlafstufe gelöscht (Runde $round)',
    );
    expectEq(
      _fields(byId[b]!),
      _fields(_measurement(10, bpm: 52.3, band: null)),
      'b: nur die Schlafstufe gelöscht (Runde $round)',
    );
    expectEq(byId[c]!.sleepBand, SleepBand.from5to6, 'andere unberührt');
    await s.close();
    s = await h.open();
  }
  await s.close();
}

Future<void> _clearSleepBandsRollback(StorageContractHarness h) async {
  var s = await h.open();
  final a = await _m(s).add(_measurement(0, band: SleepBand.over8));
  final b = await _m(s).add(_measurement(10, band: SleepBand.under5));
  // Die unbekannte Id kommt zuletzt: a und b wären schon geschrieben.
  await expectFails(
    () => _m(s).clearSleepBands([a, b, b + 99]),
    StorageFailure.notFound,
    'unbekannte Messung',
  );
  for (var round = 0; round < 2; round++) {
    final byId = {for (final e in await _m(s).list()) e.id: e.value};
    expectEq(byId[a]!.sleepBand, SleepBand.over8, 'a unverändert ($round)');
    expectEq(byId[b]!.sleepBand, SleepBand.under5, 'b unverändert ($round)');
    await s.close();
    s = await h.open();
  }
  await s.close();
}

Future<void> _clearSleepBandsEdges(StorageContractHarness h) async {
  var s = await h.open();
  final a = await _m(s).add(_measurement(0, band: SleepBand.over8));
  final b = await _m(s).add(_measurement(10, band: SleepBand.under5));
  await _m(s).clearSleepBands(const []);
  var byId = {for (final e in await _m(s).list()) e.id: e.value};
  expectEq(byId[a]!.sleepBand, SleepBand.over8, 'leere Liste: a unverändert');
  expectEq(byId[b]!.sleepBand, SleepBand.under5, 'leere Liste: b unverändert');
  await _m(s).clearSleepBands([a, a]);
  await s.close();
  s = await h.open();
  byId = {for (final e in await _m(s).list()) e.id: e.value};
  expectTrue(byId[a]!.sleepBand == null, 'doppelte Id: a gelöscht');
  expectEq(byId[b]!.sleepBand, SleepBand.under5, 'doppelte Id: b unberührt');
  await s.close();
}

/// Erwartet einen [ArgumentError] (nicht wählbare Messung).
Future<void> _expectArgumentError(
  Future<Object?> Function() f,
  String what,
) async {
  try {
    await f();
  } on ArgumentError {
    return;
  }
  throw ContractViolation('$what: kein ArgumentError');
}

Future<Map<int, MorningMeasurement>> _byId(StorageSession s) async => {
  for (final e in await _m(s).list()) e.id: e.value,
};

Future<void> _choose(StorageContractHarness h) async {
  var s = await h.open();
  // `add` schreibt die Wahl nie, auch wenn der Wert sie trägt.
  final a = await _m(s).add(_measurement(0, chosen: true));
  final b = await _m(s).add(_measurement(600));
  // Gleiche Reihe am nächsten Ortstag, andere Reihe am selben Ortstag.
  final c = await _m(s).add(_measurement(86400));
  final d = await _m(s).add(_measurement(300, model: 'Testmodell 2'));
  var byId = await _byId(s);
  expectTrue(!byId[a]!.chosen, 'add schreibt keine Wahl');
  await _m(s).choose(c);
  await _m(s).choose(d);
  await _m(s).choose(a);
  await _m(s).choose(b);
  for (var round = 0; round < 2; round++) {
    byId = await _byId(s);
    expectEq(
      [
        for (final id in [a, b, c, d]) byId[id]!.chosen,
      ],
      [false, true, true, true],
      'Wahl a, b, c, d (Runde $round)',
    );
    final counting = countingMorningMeasurements(byId.values);
    expectEq(
      [for (final m in counting) us(m.measuredAt)],
      [us(at(300)), us(at(600)), us(at(86400))],
      'zählende Messungen (Runde $round)',
    );
    await s.close();
    s = await h.open();
  }
  // Zurück zur ersten: nur wählen, kein Zurücksetzen.
  await _m(s).choose(a);
  byId = await _byId(s);
  expectEq(
    [
      for (final id in [a, b, c, d]) byId[id]!.chosen,
    ],
    [true, false, true, true],
    'Wahl zurück auf a',
  );
  await s.close();
}

Future<void> _chooseRejected(StorageContractHarness h) async {
  var s = await h.open();
  final a = await _m(s).add(_measurement(0));
  final b = await _m(s).add(_measurement(600));
  final unusable = await _m(s).add(
    _measurement(
      300,
      quality: PpgQuality.unusable,
      rmssd: null,
      noise: null,
      reason: MorningUnusableReason.weakSignal,
    ),
  );
  final outside = await _m(s).add(_measurement(900, outside: true));
  await _m(s).choose(b);
  final before = [for (final e in await _m(s).list()) _fields(e.value)];
  await expectFails(
    () => _m(s).choose(b + 99),
    StorageFailure.notFound,
    'unbekannte Messung',
  );
  // Die Wahl an b steht in derselben Reihe am selben Ortstag: ein Abbruch
  // muss das Löschen dort zurückrollen.
  await _expectArgumentError(() => _m(s).choose(unusable), 'unbrauchbar');
  await _expectArgumentError(() => _m(s).choose(outside), 'außerhalb');
  for (var round = 0; round < 2; round++) {
    expectEq(
      [for (final e in await _m(s).list()) _fields(e.value)],
      before,
      'nichts geändert (Runde $round)',
    );
    final byId = await _byId(s);
    expectTrue(!byId[a]!.chosen && byId[b]!.chosen, 'b bleibt gewählt');
    await s.close();
    s = await h.open();
  }
  await s.close();
}

Future<void> _chooseSleepBand(StorageContractHarness h) async {
  var s = await h.open();
  final a = await _m(s).add(_measurement(0, band: SleepBand.from6to7));
  final b = await _m(s).add(_measurement(600, band: null));
  await _m(s).choose(b);
  await s.close();
  s = await h.open();
  var byId = await _byId(s);
  expectEq(byId[b]!.sleepBand, SleepBand.from6to7, 'b trägt die Stufe');
  expectEq(byId[a]!.sleepBand, SleepBand.from6to7, 'a behält die Stufe');
  final source = morningSleepSource(countingMorningMeasurements(byId.values));
  expectEq(us(source?.measuredAt), us(at(600)), 'Schlafquelle ist b');
  expectEq(source?.sleepBand, SleepBand.from6to7, 'Stufe des Tages gleich');
  await s.close();

  // Ohne Stufe am Tag bleibt die gewählte, wie sie ist (auch mit eigener).
  s = await h.open();
  final day2 = 2 * 86400;
  final c = await _m(s).add(_measurement(day2, band: null));
  final d = await _m(s).add(_measurement(day2 + 600, band: null));
  final e = await _m(s).add(_measurement(day2 + 900, band: SleepBand.over8));
  await _m(s).choose(d);
  byId = await _byId(s);
  expectTrue(byId[d]!.sleepBand == null, 'd ohne Stufe bleibt ohne');
  expectTrue(byId[c]!.sleepBand == null, 'c ohne Stufe');
  await _m(s).choose(c);
  await _m(s).choose(e);
  byId = await _byId(s);
  expectEq(byId[e]!.sleepBand, SleepBand.over8, 'e behält die eigene Stufe');
  await s.close();
}
