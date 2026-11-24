import 'dart:convert';

import 'package:core/core.dart';
import 'package:core/fakes/fake_storage_morning.dart';
import 'package:test/test.dart';

import '../ppg/ppg_synth.dart';
import 'export_support.dart';

const _header =
    'format_version,morning_id,row_type,key,seq,sub,time,value,unit\r\n';

final _t0 = DateTime.utc(2030, 1, 1, 6, 30);

/// Synthetischer Morgen: Kamera und Gurt im selben Zeitfenster
/// (Ruhephase ab 06:28, Messung 06:30 bis 06:31).
MorningMeasurement _m({
  DateTime? at,
  RestingPosture posture = RestingPosture.lying,
  List<double> ibi = const [810.5, double.nan, 805.25],
  double? rmssd = 41.5,
  double? noise,
  PpgQuality quality = PpgQuality.good,
  MorningUnusableReason? reason,
  double? windowStart,
  double? windowEnd,
  double? restSkipped,
  bool outside = false,
  bool chosen = false,
  int methodVersion = 3,
}) => MorningMeasurement(
  measuredAt: at ?? _t0,
  utcOffset: const Duration(hours: 1),
  posture: posture,
  deviceManufacturer: 'Testhersteller',
  deviceModel: 'Test, "Modell"',
  method: ppgMethod,
  // Gespeicherte Messung einer früheren Verfahrensversion: sie exportiert unverändert.
  methodVersion: methodVersion,
  quality: quality,
  unusableReason: reason,
  windowStartS: windowStart,
  windowEndS: windowEnd,
  restSkippedAfterS: restSkipped,
  restingHrBpm: quality == PpgQuality.unusable ? null : 58.04,
  rmssdMs: rmssd,
  timingNoiseMs: noise,
  cameraIntervalsMs: ibi,
  beforeValidation: true,
  outsideWindow: outside,
  chosen: chosen,
);

RrPacket _p(int seconds, List<int> rr) => RrPacket(
  time: DateTime.utc(2030, 1, 1, 6, 28).add(Duration(seconds: seconds)),
  source: 'gurt-1',
  intervals: rr,
);

/// 19 synthetische ISP-Werte eines Bildes; [missing] = nicht gemeldet (NaN).
List<double> _isp(int i, {Set<int> missing = const {}}) {
  final v = <double>[
    1.875 + i / 1024, 1.0, 1.0, 2.1 + i / 10, // Farbverstärkungen R, Gg, Go, B
    2,
    1,
    0,
    0,
    1,
    1,
    1, // AWB-Zustand/-Modus, Farbkorrektur, NR, Kanten, Tonwert, Shading
    33333333.0 - i,
    400,
    2,
    33366666, // Belichtung ns, ISO, AE-Zustand, Bilddauer ns
    0, 10.0 / 3, 0, 0, // AF-Modus, Fokusdistanz dpt, OIS, Linsenzustand
  ];
  for (final k in missing) {
    v[k] = double.nan;
  }
  return v;
}

void main() {
  test('Kopfzeile ohne Morgen, CRLF, kein BOM', () {
    final csv = encodeMorningPairsCsv(const []);
    expect(csv, _header);
    expect(utf8.encode(csv).take(3), isNot([0xEF, 0xBB, 0xBF]));
  });

  test('Golden: ein Morgen mit Kamera und Gurt im selben Fenster', () {
    final csv = encodeMorningPairsCsv([
      MorningPair(
        id: 7,
        measurement: _m(windowStart: 31.5, windowEnd: 91.5, restSkipped: 12),
        rawSignal: MorningRawSignal(
          frames: [
            for (var i = 0; i < 2; i++)
              PpgFrame(
                t: 0.0333 * i,
                r: 200.25 + i,
                g: 100.5,
                r16: [for (var k = 0; k < 16; k++) 200 + k / 4],
                g16: [for (var k = 0; k < 16; k++) 100 + k / 8],
              ),
          ],
          frameGapCount: 1,
          frameGapTotalS: 0.4,
          exposureTimeNs: 16666666,
          iso: 100,
          timestampSource: CameraTimestampSource.realtime,
          torchStrength: 1,
          saturatedFraction: 0.01,
          cameraId: '0',
          physicalCameraId: '2',
          focalLengthMm: 2.2,
          // Formatversion 5: ISP-Werte je Bild (Bild 2 ohne Farbverstärkungen
          // und Fokusdistanz) und gesetzte Schalter (synthetisch).
          ispFrames: [
            _isp(0),
            _isp(1, missing: {0, 1, 2, 3, 16}),
          ],
          diagnostics: const {
            PpgCameraDiagnostic.noiseReductionOff,
            PpgCameraDiagnostic.awbFixed,
          },
          awbVariant: PpgAwbVariant.matrix,
        ),
        beltPackets: [
          _p(5, [900, 910]),
          _p(7, [915]),
          _p(125, [880, 885, 890]),
        ],
      ),
    ]);
    expectGolden(csv, 'morning_pairs.csv');
  });

  test('Formatversion 5: Schalter-meta nach focal_length, raw_isp je Bild '
      'nach den raw_frame-Zeilen, 19 Felder, leer = nicht gemeldet', () {
    final csv = encodeMorningPairsCsv([
      MorningPair(
        id: 1,
        measurement: _m(),
        rawSignal: MorningRawSignal(
          frames: [
            for (var i = 0; i < 3; i++)
              PpgFrame(
                t: 0.0333 * i,
                r: 200,
                g: 100,
                r16: List.filled(16, 200),
                g16: List.filled(16, 100),
              ),
          ],
          frameGapCount: 0,
          frameGapTotalS: 0,
          ispFrames: [
            _isp(0),
            _isp(1, missing: {4}),
            List.filled(ppgIspValueCount, double.nan),
          ],
          diagnostics: const {
            PpgCameraDiagnostic.edgeOff,
            PpgCameraDiagnostic.awbFixed,
            PpgCameraDiagnostic.tonemapLinear,
            PpgCameraDiagnostic.shadingOff,
          },
          awbVariant: PpgAwbVariant.lock,
        ),
      ),
    ]);
    final lines = csv.split('\r\n');
    final focal = lines.indexWhere((l) => l.contains(',meta,focal_length,'));
    expect(lines.sublist(focal + 1, focal + 8), [
      '5,1,meta,diag_noise_reduction_off,,,,0,',
      '5,1,meta,diag_edge_off,,,,1,',
      '5,1,meta,diag_awb_fixed,,,,1,',
      '5,1,meta,diag_awb_variant,,,,lock,',
      '5,1,meta,diag_tonemap_linear,,,,1,',
      '5,1,meta,diag_shading_off,,,,1,',
      '5,1,meta,raw_isp_frames,,,,3,',
    ]);
    final types = [
      for (final l in lines.skip(1))
        if (l.isNotEmpty) l.split(',')[2],
    ];
    final firstIsp = types.indexOf('raw_isp');
    expect(types.lastIndexOf('raw_frame'), firstIsp - 1);
    expect(types.sublist(firstIsp), ['raw_isp', 'raw_isp', 'raw_isp']);
    final isp = [
      for (final l in lines)
        if (l.contains(',raw_isp,')) l,
    ];
    expect(isp.map((l) => l.split(',')[4]), ['1', '2', '3']);
    final f0 = isp[0].split(',')[7].split(';');
    expect(f0, hasLength(19));
    expect(f0, [
      '1.875',
      '1.0',
      '1.0',
      '2.1',
      '2',
      '1',
      '0',
      '0',
      '1',
      '1',
      '1',
      '33333333',
      '400',
      '2',
      '33366666',
      '0',
      '3.3333333333333335',
      '0',
      '0',
    ]);
    // Verlustfrei zurückgelesen; ein nicht gemeldeter Wert ist ein leeres Feld.
    expect(double.parse(f0[16]), 10.0 / 3);
    final f1 = isp[1].split(',')[7].split(';');
    expect(f1[4], '');
    expect(f1[11], '33333332');
    expect(isp[2].split(',')[7], List.filled(19, '').join(';'));
    // raw_frame bleibt bei genau 35 Zahlen.
    for (final l in lines.where((l) => l.contains(',raw_frame,'))) {
      expect(l.split(',')[7].split(';'), hasLength(35));
    }
  });

  test('Formatversion 5: Rohsignal ohne ISP-Werte und Schalter: 0, leer, '
      'keine raw_isp-Zeilen', () {
    final csv = encodeMorningPairsCsv([
      MorningPair(
        id: 1,
        measurement: _m(),
        rawSignal: const MorningRawSignal(
          frames: [],
          frameGapCount: 0,
          frameGapTotalS: 0,
        ),
      ),
    ]);
    for (final k in [
      'diag_noise_reduction_off',
      'diag_edge_off',
      'diag_awb_fixed',
      'diag_tonemap_linear',
      'diag_shading_off',
      'raw_isp_frames',
    ]) {
      expect(csv, contains('5,1,meta,$k,,,,0,\r\n'), reason: k);
    }
    expect(csv, contains('5,1,meta,diag_awb_variant,,,,,\r\n'));
    expect(csv, isNot(contains(',raw_isp,')));
  });

  test('Formatversion 4: counts und chosen je Morgen nach outside_window '
      '(PAR-160K)', () {
    final later = _t0.add(const Duration(minutes: 20));
    final next = _t0.add(const Duration(days: 1));
    final csv = encodeMorningPairsCsv([
      // erster des Tages, nicht gewählt
      MorningPair(id: 1, measurement: _m()),
      // später, gewählt: zählt statt des ersten
      MorningPair(id: 2, measurement: _m(at: later, chosen: true)),
      // außerhalb, gewählt (alte Daten): zählt nicht
      MorningPair(
        id: 3,
        measurement: _m(
          at: later.add(const Duration(minutes: 5)),
          outside: true,
          chosen: true,
        ),
      ),
      // nächster Tag ohne Wahl: zählt
      MorningPair(id: 4, measurement: _m(at: next)),
    ]);
    String block(int id, String outside, String counts, String chosen) =>
        '5,$id,meta,outside_window,,,,$outside,\r\n'
        '5,$id,meta,counts,,,,$counts,\r\n'
        '5,$id,meta,chosen,,,,$chosen,\r\n'
        '5,$id,meta,sleep_band,';
    expect(csv, contains(block(1, '0', '0', '0')));
    expect(csv, contains(block(2, '0', '1', '1')));
    expect(csv, contains(block(3, '1', '0', '1')));
    expect(csv, contains(block(4, '0', '1', '0')));
  });

  test('frühere Verfahrensversionen 1 bis 4 exportieren und zählen wie die '
      'aktuelle (DEC-0074 E7c)', () {
    final versions = [1, 2, 3, 4, ppgMethodVersion];
    expect(ppgMethodVersion, 5);
    final csv = encodeMorningPairsCsv([
      for (var i = 0; i < versions.length; i++)
        MorningPair(
          id: i + 1,
          measurement: _m(
            at: _t0.add(Duration(days: i)),
            methodVersion: versions[i],
          ),
        ),
    ]);
    for (var i = 0; i < versions.length; i++) {
      final id = i + 1;
      expect(csv, contains('5,$id,meta,method_version,,,,${versions[i]},\r\n'));
      // Jede ist die erste ihres Tages und zählt, gleich welche Version.
      expect(csv, contains('5,$id,meta,counts,,,,1,\r\n'));
    }
  });

  test('ungültiges Kamera-Intervall ist ein leeres Feld, nie NaN', () {
    final csv = encodeMorningPairsCsv([MorningPair(id: 1, measurement: _m())]);
    expect(csv, contains('5,1,camera_ibi,ibi,2,,,,ms\r\n'));
    expect(csv.toLowerCase(), isNot(contains('nan')));
  });

  test('fehlende RMSSD und Zeitrauschen sind leer, nie 0', () {
    final csv = encodeMorningPairsCsv([
      MorningPair(id: 1, measurement: _m(rmssd: null)),
    ]);
    expect(csv, contains('5,1,camera,rmssd,,,,,ms\r\n'));
    expect(csv, contains('5,1,camera,timing_noise,,,,,ms\r\n'));
  });

  test('sehr kleine Werte ohne Exponentschreibweise', () {
    final csv = encodeMorningPairsCsv([
      MorningPair(id: 1, measurement: _m(rmssd: 1e-7, noise: 2e-8)),
    ]);
    expect(csv, contains('5,1,camera,rmssd,,,,0.0000001,ms\r\n'));
    expect(csv, contains('5,1,camera,timing_noise,,,,0.00000002,ms\r\n'));
    expect(csv.toLowerCase(), isNot(contains('e-')));
  });

  test('Sortierung nach Zeitpunkt, dann Id; Feld mit Komma in Anführungen', () {
    final csv = encodeMorningPairsCsv([
      MorningPair(id: 2, measurement: _m(at: _t0.add(const Duration(days: 1)))),
      MorningPair(id: 9, measurement: _m()),
    ]);
    final ids = [
      for (final l in csv.split('\r\n').skip(1))
        if (l.contains(',meta,measured_at,')) l.split(',')[1],
    ];
    expect(ids, ['9', '2']);
    expect(csv, contains('"Test, ""Modell"""'));
  });

  test(
    'buildMorningPairsCsvFile: Name, Typ, Zählung mit und ohne Gurt',
    () async {
      final store = FakeMorningStore(FakeStorageData());
      await store.add(
        _m(),
        beltPackets: [
          _p(5, [900]),
        ],
      );
      await store.add(_m(at: _t0.add(const Duration(days: 1))));
      final file = await buildMorningPairsCsvFile(
        store,
        now: DateTime.utc(2031, 2, 3),
      );
      expect(file.fileName, 'running-morgenpaare-20310203.csv');
      expect(file.mimeType, 'text/csv');
      final text = utf8.decode(file.bytes!);
      expect(text, contains(',belt_rr,rr,1,1,2030-01-01T06:28:05.000Z,900,'));
      expect(text, contains(',meta,belt_packets,,,,1,'));
      final n = await countMorningPairs(store);
      expect((n.withBelt, n.without), (1, 1));
    },
  );

  test('Fenster und Ruhe-Vermerk stehen als Meta-Zeilen', () {
    final csv = encodeMorningPairsCsv([
      MorningPair(
        id: 1,
        measurement: _m(windowStart: 31.5, windowEnd: 91.5, restSkipped: 12),
      ),
      MorningPair(id: 2, measurement: _m(at: _t0.add(const Duration(days: 1)))),
    ]);
    expect(csv, contains('5,1,meta,window_start,,,,31.5,s\r\n'));
    expect(csv, contains('5,1,meta,window_end,,,,91.5,s\r\n'));
    expect(csv, contains('5,1,meta,rest_skipped_after,,,,12.0,s\r\n'));
    // Ohne Fenster und ohne Überspringen: leer, nie 0.
    expect(csv, contains('5,2,meta,window_start,,,,,s\r\n'));
    expect(csv, contains('5,2,meta,rest_skipped_after,,,,,s\r\n'));
  });

  test('unbrauchbare Messung ist enthalten und markiert', () {
    final csv = encodeMorningPairsCsv([
      MorningPair(
        id: 3,
        measurement: _m(
          quality: PpgQuality.unusable,
          reason: MorningUnusableReason.weakSignal,
          ibi: const [],
          rmssd: null,
        ),
      ),
      MorningPair(id: 4, measurement: _m()),
    ]);
    expect(csv, contains('5,3,meta,quality,,,,unusable,\r\n'));
    expect(csv, contains('5,3,meta,usable,,,,0,\r\n'));
    expect(csv, contains('5,3,meta,quality_reason,,,,weakSignal,\r\n'));
    expect(csv, contains('5,3,camera,resting_hr,,,,,bpm\r\n'));
    expect(csv, contains('5,4,meta,usable,,,,1,\r\n'));
    expect(csv, contains('5,4,meta,quality_reason,,,,,\r\n'));
  });

  test('Puls außerhalb PAR-017: Zeile unbrauchbar mit Grund, ohne Puls', () {
    final m = buildMorningMeasurement(
      result: const PpgMeasurement(
        quality: PpgQuality.good,
        reasons: [],
        bpm: 121,
        rmssdMs: 40,
        timingNoiseMs: 10,
        intervalsMs: [495.5, 496],
      ),
      measuredAt: _t0,
      utcOffset: const Duration(hours: 1),
      posture: RestingPosture.lying,
      deviceManufacturer: 'Testhersteller',
      deviceModel: 'M',
      keepUnusable: true,
    )!;
    final csv = encodeMorningPairsCsv([MorningPair(id: 5, measurement: m)]);
    expect(csv, startsWith(_header));
    expect(csv, contains('5,5,meta,quality,,,,unusable,\r\n'));
    expect(csv, contains('5,5,meta,usable,,,,0,\r\n'));
    expect(
      csv,
      contains('5,5,meta,quality_reason,,,,restingHrOutOfRange,\r\n'),
    );
    expect(csv, contains('5,5,camera,resting_hr,,,,,bpm\r\n'));
    expect(csv, contains('5,5,camera,rmssd,,,,,ms\r\n'));
    expect(csv, isNot(contains('121')));
  });

  test('ohne Rohsignal keine Rohzeilen, raw_frames ist 0', () {
    final csv = encodeMorningPairsCsv([MorningPair(id: 1, measurement: _m())]);
    expect(csv, isNot(contains(',raw_frame,')));
    expect(csv, contains('5,1,meta,raw_frames,,,,0,\r\n'));
    expect(csv, isNot(contains('exposure_time')));
    // Kamera-Angaben (Formatversion 3) fehlen wie die übrigen.
    expect(csv, isNot(contains('camera_id')));
    expect(csv, isNot(contains('focal_length')));
    // Diagnose-Angaben (Formatversion 5) nur mit gespeichertem Rohsignal.
    expect(csv, isNot(contains('diag_')));
    expect(csv, isNot(contains('raw_isp')));
  });

  test('Formatversion 3: verwendete Kamera nach saturated_fraction', () {
    final csv = encodeMorningPairsCsv([
      MorningPair(
        id: 1,
        measurement: _m(),
        rawSignal: MorningRawSignal(
          frames: const [],
          frameGapCount: 0,
          frameGapTotalS: 0,
          saturatedFraction: 0.5,
          cameraId: '0',
          physicalCameraId: '3',
          focalLengthMm: 4.25,
        ),
      ),
    ]);
    expect(
      csv,
      contains(
        '5,1,meta,saturated_fraction,,,,0.5,\r\n'
        '5,1,meta,camera_id,,,,0,\r\n'
        '5,1,meta,physical_camera_id,,,,3,\r\n'
        '5,1,meta,focal_length,,,,4.25,mm\r\n'
        // Ab Formatversion 5 folgen die Diagnose-Angaben.
        '5,1,meta,diag_noise_reduction_off,',
      ),
    );
    for (final l in csv.split('\r\n').skip(1).where((l) => l.isNotEmpty)) {
      expect(l, startsWith('5,'));
    }
  });

  test('unbekannte Kamera: die drei Zeilen stehen mit leerem Wert', () {
    final csv = encodeMorningPairsCsv([
      MorningPair(
        id: 1,
        measurement: _m(),
        rawSignal: MorningRawSignal(
          frames: const [],
          frameGapCount: 0,
          frameGapTotalS: 0,
        ),
      ),
    ]);
    expect(
      csv,
      contains(
        '5,1,meta,camera_id,,,,,\r\n'
        '5,1,meta,physical_camera_id,,,,,\r\n'
        '5,1,meta,focal_length,,,,,mm\r\n',
      ),
    );
  });

  test(
    'buildMorningPairsCsvFile übernimmt das gespeicherte Rohsignal',
    () async {
      final store = FakeMorningStore(FakeStorageData());
      await store.add(
        _m(),
        rawSignal: _raw(_synthFrames(3).take(3).toList(), gaps: 2),
      );
      final text = utf8.decode(
        (await buildMorningPairsCsvFile(store, now: _t0)).bytes!,
      );
      expect(text, contains(',meta,raw_frames,,,,3,'));
      expect(text, contains(',meta,frame_gap_count,,,,2,'));
      expect(_readFrames(text), hasLength(3));
    },
  );

  test('Zahlen ohne Exponent, auch bei sehr kleinen Bildwerten', () {
    final f = PpgFrame(
      t: 1e-7,
      r: 1e22,
      g: 0,
      r16: List.filled(16, 5e-324),
      g16: List.filled(16, 255.0),
    );
    final csv = encodeMorningPairsCsv([
      MorningPair(id: 1, measurement: _m(), rawSignal: _raw([f])),
    ]);
    final line = csv.split('\r\n').firstWhere((l) => l.contains(',raw_frame,'));
    final value = line.split(',')[7];
    expect(value.toLowerCase(), isNot(contains('e')));
    expect(value.split(';'), hasLength(35));
  });

  test('Rundweg: Rohsignal -> CSV -> Bilder ergibt dieselbe Auswertung', () {
    final frames = _synthFrames(95);
    final csv = encodeMorningPairsCsv([
      MorningPair(id: 1, measurement: _m(), rawSignal: _raw(frames)),
    ]);
    final back = _readFrames(csv);
    expect(back.length, frames.length);
    // Verlustfrei: jede der 35 Zahlen je Bild ist bitgleich.
    for (var i = 0; i < frames.length; i++) {
      expect(_values(back[i]), _values(frames[i]), reason: 'Bild $i');
    }
    final a = evaluatePpgBestWindow(frames);
    final b = evaluatePpgBestWindow(back);
    expect(a.measurement.quality, PpgQuality.good);
    expect(b.measurement.intervalsMs, a.measurement.intervalsMs);
    expect(b.windowStartSeconds, a.windowStartSeconds);
    expect(b.windowEndSeconds, a.windowEndSeconds);
    expect(b.measurement.bpm, a.measurement.bpm);
  });
}

List<double> _values(PpgFrame f) => [f.t, f.r, f.g, ...f.r16, ...f.g16];

MorningRawSignal _raw(List<PpgFrame> frames, {int gaps = 0}) =>
    MorningRawSignal(
      frames: frames,
      frameGapCount: gaps,
      frameGapTotalS: gaps * 0.2,
      exposureTimeNs: 16666666,
      iso: 100,
      timestampSource: CameraTimestampSource.realtime,
    );

/// Synthetisches Rohsignal: ein Puls mit Rauschen, 30 Bilder/s; [seconds]
/// Sekunden (bei weniger als 5 nur wenige Bilder).
List<PpgFrame> _synthFrames(num seconds) {
  final s = synth(0.85, 0.05, 0.03, 0.3, 30.0, 1, duration: seconds.toDouble());
  return [
    for (var i = 0; i < s.t.length; i++)
      PpgFrame(
        t: s.t[i],
        r: s.red[i],
        g: s.green[i],
        r16: [for (var k = 0; k < 16; k++) s.red[i] + k / 7],
        g16: [for (var k = 0; k < 16; k++) s.green[i] - k / 3],
      ),
  ];
}

/// Leser, wie ihn ein Skript schreiben würde: nur Zeilen `raw_frame`, Wert =
/// 35 Zahlen mit `;`. Felder ohne Anführungszeichen (die Zeile enthält keine).
List<PpgFrame> _readFrames(String csv) {
  final out = <PpgFrame>[];
  for (final line in csv.split('\r\n')) {
    final c = line.split(',');
    if (c.length != 9 || c[2] != 'raw_frame') continue;
    expect(c[0], '$morningPairsCsvFormatVersion');
    expect(c[4], '${out.length + 1}');
    final v = [for (final x in c[7].split(';')) double.parse(x)];
    expect(v, hasLength(35));
    out.add(
      PpgFrame(
        t: v[0],
        r: v[1],
        g: v[2],
        r16: v.sublist(3, 19),
        g16: v.sublist(19, 35),
      ),
    );
  }
  return out;
}
