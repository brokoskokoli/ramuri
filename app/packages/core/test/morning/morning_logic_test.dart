import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:core/fakes/fake_storage_morning.dart';
import 'package:test/test.dart';

import '../ppg/ppg_synth.dart';

PpgMeasurement meas({
  PpgQuality quality = PpgQuality.good,
  double? bpm = 58,
  double? rmssd = 42,
  double? noise = 10,
  List<double> ibis = const [1000, 1040, 1020],
}) => PpgMeasurement(
  quality: quality,
  reasons: const [],
  bpm: bpm,
  rmssdMs: rmssd,
  timingNoiseMs: noise,
  intervalsMs: ibis,
);

const lyingKey = MorningSeriesKey('H', 'M1');

// 2026-11-14 ist ein Samstag; Ortszeit = UTC + 1 h.
const off = Duration(hours: 1);
DateTime local(int h, [int min = 0, int day = 14]) =>
    DateTime.utc(2026, 11, day, h, min).subtract(off);

MorningMeasurement? build(
  PpgMeasurement r, {
  DateTime? at,
  RestingPosture posture = RestingPosture.lying,
  String model = 'M1',
  MorningWindow window = MorningWindow.standard,
  Map<ValidationQuantity, ValidationState>? state,
}) => buildMorningMeasurement(
  result: r,
  measuredAt: at ?? local(7),
  utcOffset: off,
  posture: posture,
  deviceManufacturer: 'H',
  deviceModel: model,
  window: window,
  validationState: state ?? ppgValidationState,
);

MorningMeasurement m(
  int h, {
  int day = 14,
  RestingPosture posture = RestingPosture.lying,
  String model = 'M1',
  int min = 0,
}) => build(meas(), at: local(h, min, day), posture: posture, model: model)!;

void main() {
  group('Parameter (PAR-160K, PAR-164K/165K, PAR-017)', () {
    test('Werte', () {
      expect(morningWindowDefaultStartHour, 4);
      expect(morningWindowDefaultEndHour, 11);
      expect(morningRestSeconds, 120);
      expect(morningMeasureSeconds, 60);
      expect(morningRmssdTimingNoiseLimitMs, 25.0);
      expect(morningRmssdMinMs, 1.0);
      expect(morningRmssdMaxMs, 200.0);
      expect(morningSleepBandHours, [4.5, 5.5, 6.5, 7.5, 8.5]);
      expect(SleepBand.values.map(sleepBandHours), morningSleepBandHours);
    });

    test('Ruhepulsgrenzen sind die aus PAR-017 (Profil)', () {
      const p = ProfileParameters.v4();
      expect(morningRestingHrMinBpm, p.restHrRejectBelowBpm.toDouble());
      expect(morningRestingHrMaxBpm, p.restHrRejectAboveBpm.toDouble());
    });
  });

  group('Messergebnis -> Datensatz', () {
    test('gut: Ruhepuls, RMSSD, Intervalle, Methode', () {
      final x = build(meas())!;
      expect(x.restingHrBpm, 58);
      expect(x.rmssdMs, 42);
      expect(x.cameraIntervalsMs, [1000, 1040, 1020]);
      expect(x.method, 'camera-ppg');
      expect(x.methodVersion, ppgMethodVersion);
      expect(x.quality, PpgQuality.good);
      expect(x.outsideWindow, isFalse);
      expect(x.measuredAt, DateTime.utc(2026, 11, 14, 6));
      expect(x.utcOffset, off);
    });

    test(
      'Version 5 (Belichtung) wird gespeichert, ältere Datensätze mit '
      'Version 1 bis 4 bleiben lesbar und unverändert (Fake-Speicher)',
      () async {
        final store = FakeMorningStore(FakeStorageData());
        final v5 = build(meas(ibis: const [1000, double.nan, 1020, 1010]))!;
        expect(v5.methodVersion, 5);
        MorningMeasurement old(int version) => MorningMeasurement(
          measuredAt: local(7, version, 13).toUtc(),
          utcOffset: off,
          posture: RestingPosture.lying,
          deviceManufacturer: 'H',
          deviceModel: 'M1',
          method: 'camera-ppg',
          methodVersion: version,
          quality: PpgQuality.good,
          restingHrBpm: 57.5,
          rmssdMs: 61,
          timingNoiseMs: 12,
          cameraIntervalsMs: const [1000, 1100, double.nan, 1050],
          beforeValidation: true,
          outsideWindow: false,
        );
        final oldIds = {
          for (final v in [1, 2, 3, 4]) v: await store.add(old(v)),
        };
        final newId = await store.add(v5);
        final byId = {for (final e in await store.list()) e.id: e.value};
        expect(byId[newId]!.methodVersion, 5);
        expect(byId[newId]!.method, 'camera-ppg');
        for (final MapEntry(key: v, value: id) in oldIds.entries) {
          final o = byId[id]!;
          expect(o.methodVersion, v);
          expect(o.rmssdMs, 61);
          expect(o.restingHrBpm, 57.5);
          expect(o.timingNoiseMs, 12);
          expect(o.cameraIntervalsMs.take(2), [1000, 1100]);
          expect(o.cameraIntervalsMs[2].isNaN, isTrue);
          expect(o.cameraIntervalsMs[3], 1050);
        }
      },
    );

    test('eingeschränkt: Ruhepuls ja, RMSSD nie', () {
      final x = build(meas(quality: PpgQuality.limited))!;
      expect(x.restingHrBpm, 58);
      expect(x.rmssdMs, isNull);
    });

    test('unbrauchbar wird verworfen, auch mit Puls im Ergebnis', () {
      expect(build(meas(quality: PpgQuality.unusable)), isNull);
      expect(build(meas(quality: PpgQuality.unusable, bpm: null)), isNull);
    });

    test('ohne Puls verworfen', () => expect(build(meas(bpm: null)), isNull));

    test('Ruhepuls PAR-017: 30 und 120 gelten, 29,9 und 120,1 nicht', () {
      expect(build(meas(bpm: 30)), isNotNull);
      expect(build(meas(bpm: 120)), isNotNull);
      expect(build(meas(bpm: 29.9)), isNull);
      expect(build(meas(bpm: 120.1)), isNull);
    });

    test('RMSSD-Qualitätsgrenze je Messung: 25 ms gilt, darüber nicht', () {
      expect(build(meas(noise: 25))!.rmssdMs, 42);
      final over = build(meas(noise: 25.1))!;
      expect(over.rmssdMs, isNull);
      expect(over.restingHrBpm, 58);
      expect(over.timingNoiseMs, 25.1);
    });

    test('Zeitrauschen unbekannt: kein RMSSD (fail closed)', () {
      expect(build(meas(noise: null))!.rmssdMs, isNull);
    });

    test('RMSSD-Bereich 1 bis 200 ms, Grenzen gelten', () {
      expect(build(meas(rmssd: 1))!.rmssdMs, 1);
      expect(build(meas(rmssd: 200))!.rmssdMs, 200);
      expect(build(meas(rmssd: 0.9))!.rmssdMs, isNull);
      expect(build(meas(rmssd: 200.1))!.rmssdMs, isNull);
      expect(build(meas(rmssd: null))!.rmssdMs, isNull);
    });

    test('Schlafstufe wird übernommen', () {
      final x = buildMorningMeasurement(
        result: meas(),
        measuredAt: local(7),
        utcOffset: off,
        posture: RestingPosture.sitting,
        deviceManufacturer: 'H',
        deviceModel: 'M1',
        sleepBand: SleepBand.from6to7,
      )!;
      expect(x.sleepBand, SleepBand.from6to7);
      expect(x.posture, RestingPosture.sitting);
    });

    test('Datensatz besteht die Prüfung des Speichers', () {
      checkMorningForStorage(build(meas())!);
      checkMorningForStorage(build(meas(quality: PpgQuality.limited))!);
    });
  });

  group('Fenster, Vermerk, unbrauchbar, Rohsignal (WP37 C1)', () {
    MorningMeasurement? withExtras(PpgMeasurement r, {bool keep = false}) =>
        buildMorningMeasurement(
          result: r,
          measuredAt: local(6),
          utcOffset: off,
          posture: RestingPosture.lying,
          deviceManufacturer: 'H',
          deviceModel: 'M1',
          windowStartS: 30,
          windowEndS: 90,
          restSkippedAfterS: 41.5,
          keepUnusable: keep,
        );

    test('Fenster und Vermerk gehen an die Messung', () {
      final x = withExtras(meas())!;
      expect(
        [x.windowStartS, x.windowEndS, x.restSkippedAfterS],
        [30, 90, 41.5],
      );
    });

    const bad = PpgMeasurement(
      quality: PpgQuality.unusable,
      reasons: [PpgQualityReason.weakSignal],
      intervalsMs: [900, 910],
    );

    test('unbrauchbar: ohne Entwicklermodus verworfen', () {
      expect(withExtras(bad), isNull);
    });

    test('unbrauchbar im Entwicklermodus: Stufe, Grund, Schlagabstände, '
        'ohne Puls und RMSSD, zählt nirgends', () {
      final x = withExtras(bad, keep: true)!;
      expect(x.quality, PpgQuality.unusable);
      expect(x.isUsable, isFalse);
      expect(x.unusableReason, MorningUnusableReason.weakSignal);
      expect(x.restingHrBpm, isNull);
      expect(x.rmssdMs, isNull);
      expect(x.cameraIntervalsMs, [900, 910]);
      expect([x.windowStartS, x.restSkippedAfterS], [30, 41.5]);
      checkMorningForStorage(x);
      expect(countingMorningMeasurements([x]), isEmpty);
    });

    test('brauchbar bleibt mit keepUnusable unverändert', () {
      expect(withExtras(meas(), keep: true)!.quality, PpgQuality.good);
    });

    group('Ruhepuls außerhalb PAR-017', () {
      for (final q in [PpgQuality.good, PpgQuality.limited]) {
        for (final hr in [29.0, 121.0]) {
          test('${q.name}, $hr bpm: im Entwicklermodus unbrauchbar mit Grund, '
              'ohne Puls', () {
            final x = withExtras(meas(quality: q, bpm: hr), keep: true)!;
            expect(x.quality, PpgQuality.unusable);
            expect(x.isUsable, isFalse);
            expect(x.unusableReason, MorningUnusableReason.restingHrOutOfRange);
            expect(x.restingHrBpm, isNull);
            expect(x.roundedRestingHr, isNull);
            expect(x.rmssdMs, isNull);
            expect(x.timingNoiseMs, isNull);
            expect(x.cameraIntervalsMs, [1000, 1040, 1020]);
            expect([x.windowStartS, x.windowEndS], [30, 90]);
            checkMorningForStorage(x);
            expect(countingMorningMeasurements([x]), isEmpty);
          });

          test('${q.name}, $hr bpm: ohne Entwicklermodus verworfen', () {
            expect(withExtras(meas(quality: q, bpm: hr)), isNull);
          });
        }
      }

      test('Grenzen 30 und 120 bleiben brauchbar, auch im Entwicklermodus', () {
        for (final hr in [30.0, 120.0]) {
          final x = withExtras(meas(bpm: hr), keep: true)!;
          expect(x.quality, PpgQuality.good, reason: '$hr');
          expect(x.restingHrBpm, hr);
          expect(x.unusableReason, isNull);
        }
      });

      test(
        'zählt weder in der Reihe noch in der Readiness (FR-0115, FR-0215)',
        () {
          MorningMeasurement at(int h, double hr) => buildMorningMeasurement(
            result: meas(bpm: hr),
            measuredAt: local(h),
            utcOffset: off,
            posture: RestingPosture.lying,
            deviceManufacturer: 'H',
            deviceModel: 'M1',
            keepUnusable: true,
          )!;
          final out = at(6, 121);
          final ok = at(7, 58);
          final all = [out, ok];
          expect(countingMorningMeasurements(all), [ok]);
          expect(morningSeries(all)[lyingKey], [ok]);
          final today = DateTime.utc(2026, 11, 14);
          for (final d in cameraDeviations(all, today: today)) {
            expect(d.byDay.values, isNot(contains(121)), reason: d.factor.name);
            expect(d.todayValue, isNot(121), reason: d.factor.name);
          }
          final hr = cameraDeviations(
            [out],
            today: today,
          ).where((d) => d.factor == ReadinessFactor.restingHeartRate);
          expect(
            hr.every((d) => d.byDay.isEmpty && d.todayValue == null),
            isTrue,
          );
        },
      );

      test('nicht endlicher Puls bleibt verworfen', () {
        expect(withExtras(meas(bpm: double.nan), keep: true), isNull);
      });
    });

    test(
      'jeder Grund der Auswertung hat denselben Namen in der Speicherung',
      () {
        for (final r in PpgQualityReason.values) {
          expect(MorningUnusableReason.fromPpg(r).name, r.name);
        }
        expect(
          MorningUnusableReason.fromName('restingHrOutOfRange'),
          MorningUnusableReason.restingHrOutOfRange,
        );
        expect(MorningUnusableReason.fromName('x'), isNull);
      },
    );

    PpgFrame frame(double t) => PpgFrame(
      t: t,
      r: 200,
      g: 40,
      r16: List.filled(16, 200),
      g16: List.filled(16, 40),
    );

    test('Rohsignal: Bilder unverändert, Lücken über der Grenze gezählt', () {
      final frames = [
        for (final t in [0.0, 0.5, 1.0, 3.5, 4.0, 5.5]) frame(t),
      ];
      final raw = buildMorningRawSignal(frames);
      expect(raw.frames.map((f) => f.t), [0.0, 0.5, 1.0, 3.5, 4.0, 5.5]);
      expect(raw.frameGapCount, 2);
      expect(raw.frameGapTotalS, closeTo(4.0, 1e-9));
      expect(raw.exposureTimeNs, isNull);
      checkMorningForStorage(withExtras(meas())!, rawSignal: raw);
    });

    test('Kamera-Angaben des Adapters gehen ins Rohsignal', () {
      final raw = buildMorningRawSignal(
        [frame(0), frame(0.5)],
        details: const PpgCameraDetails(
          exposureTimeNs: 1,
          iso: 2,
          timestampSource: CameraTimestampSource.unknown,
          rollingShutterSkewNs: 3,
          torchStrength: 4,
          saturatedFraction: 0.5,
        ),
      );
      expect(
        [
          raw.exposureTimeNs,
          raw.iso,
          raw.rollingShutterSkewNs,
          raw.torchStrength,
        ],
        [1, 2, 3, 4],
      );
      expect(raw.timestampSource, CameraTimestampSource.unknown);
      expect(raw.saturatedFraction, 0.5);
    });

    test('verwendete Kamera mit der Brennweite derselben Kamera (FR-0220)', () {
      const cams = [
        PpgCameraInfo(
          ref: PpgCameraRef('0'),
          focalLengthMm: 5.4,
          isDefault: true,
        ),
        PpgCameraInfo(ref: PpgCameraRef('0', '2'), focalLengthMm: 2.2),
        PpgCameraInfo(ref: PpgCameraRef('2'), focalLengthMm: 3.1),
      ];
      final raw = buildMorningRawSignal(
        [frame(0)],
        camera: const PpgCameraRef('0', '2'),
        cameras: cams,
      );
      expect(raw.cameraId, '0');
      expect(raw.physicalCameraId, '2');
      expect(raw.focalLengthMm, 2.2);
      checkMorningForStorage(withExtras(meas())!, rawSignal: raw);
      final logical = buildMorningRawSignal(
        [frame(0)],
        camera: const PpgCameraRef('0'),
        cameras: cams,
      );
      expect(logical.physicalCameraId, isNull);
      expect(logical.focalLengthMm, 5.4);
    });

    test('ISP-Werte je Bild und gesetzte Schalter gehen ins Rohsignal', () {
      final isp = [
        for (var i = 0; i < 3; i++)
          [
            for (var k = 0; k < ppgIspValueCount; k++)
              k == 5 ? double.nan : k + i / 10,
          ],
      ];
      final raw = buildMorningRawSignal(
        [frame(0), frame(0.5), frame(1)],
        ispFrames: isp,
        diagnostics: const {
          PpgCameraDiagnostic.edgeOff,
          PpgCameraDiagnostic.awbFixed,
        },
        awbVariant: PpgAwbVariant.matrix,
      );
      expect(raw.ispFrames!.length, 3);
      expect(raw.ispFrames![2][7], 7.2);
      expect(raw.ispFrames![1][5].isNaN, isTrue);
      expect(raw.diagnostics, {
        PpgCameraDiagnostic.edgeOff,
        PpgCameraDiagnostic.awbFixed,
      });
      expect(raw.awbVariant, PpgAwbVariant.matrix);
      expect(raw.withCameraDiagnostics, isTrue);
      checkMorningForStorage(withExtras(meas())!, rawSignal: raw);
      final plain = buildMorningRawSignal([frame(0)]);
      expect(plain.ispFrames, isNull);
      expect(plain.diagnostics, isEmpty);
      expect(plain.withCameraDiagnostics, isFalse);
      // Variante ohne festen Weißabgleich wird nicht übernommen.
      expect(
        buildMorningRawSignal([
          frame(0),
        ], awbVariant: PpgAwbVariant.lock).awbVariant,
        isNull,
      );
      expect(
        () => buildMorningRawSignal([frame(0)], ispFrames: const []),
        throwsArgumentError,
      );
    });

    test(
      'Auswertung mit und ohne ISP-Werte und Schalter identisch (FR-0215)',
      () {
        final s = synth(0.95, 0.03, 0.01, 0.4, 30, 7);
        final frames = [
          for (var i = 0; i < s.t.length; i++)
            PpgFrame(
              t: s.t[i],
              r: s.red[i],
              g: s.green[i],
              r16: List.filled(16, s.red[i]),
              g16: List.filled(16, s.green[i]),
            ),
        ];
        final plain = buildMorningRawSignal(frames);
        final diag = buildMorningRawSignal(
          frames,
          ispFrames: [
            for (var i = 0; i < frames.length; i++)
              List.filled(ppgIspValueCount, i.isEven ? 1.0 : double.nan),
          ],
          diagnostics: PpgCameraDiagnostic.values.toSet(),
          awbVariant: PpgAwbVariant.lock,
        );
        final a = evaluatePpgBestWindow(plain.frames);
        final b = evaluatePpgBestWindow(diag.frames);
        String key(PpgWindowedMeasurement w) => [
          w.measurement.quality,
          w.measurement.bpm,
          w.measurement.rmssdMs,
          w.measurement.timingNoiseMs,
          w.measurement.intervalsMs.join(','),
          w.windowStartSeconds,
          w.windowEndSeconds,
        ].join('|');
        expect(key(b), key(a));
        expect(a.measurement.bpm, isNotNull);
        final ma = build(a.measurement)!;
        final mb = build(b.measurement)!;
        expect(mb.quality, ma.quality);
        expect(mb.restingHrBpm, ma.restingHrBpm);
        expect(mb.rmssdMs, ma.rmssdMs);
        expect(mb.methodVersion, ppgMethodVersion);
      },
    );

    test('Kamera ohne Eintrag in der Liste: Brennweite unbekannt', () {
      final raw = buildMorningRawSignal(
        [frame(0)],
        camera: const PpgCameraRef('7'),
        cameras: const [
          PpgCameraInfo(ref: PpgCameraRef('0'), focalLengthMm: 5.4),
        ],
      );
      expect(raw.cameraId, '7');
      expect(raw.focalLengthMm, isNull);
      final none = buildMorningRawSignal([frame(0)]);
      expect(
        [none.cameraId, none.physicalCameraId, none.focalLengthMm],
        [null, null, null],
      );
    });
  });

  group('Vor der Validierung gemessen', () {
    Map<ValidationQuantity, ValidationState> st(ValidationState s) => {
      for (final k in ValidationQuantity.values) k: ValidationState.notChecked,
      ValidationQuantity.lnRmssdSupine: s,
    };
    test(
      'heutiger Stand: ja',
      () => expect(build(meas())!.beforeValidation, isTrue),
    );
    for (final s in ValidationState.values) {
      test('lnRMSSD liegend $s', () {
        expect(
          build(meas(), state: st(s))!.beforeValidation,
          s != ValidationState.passed,
        );
      });
    }
    test('Merkmal ändert die Werte nicht', () {
      final a = build(meas(), state: st(ValidationState.passed))!;
      final b = build(meas(), state: st(ValidationState.notChecked))!;
      expect(a.rmssdMs, b.rmssdMs);
      expect(a.restingHrBpm, b.restingHrBpm);
    });
  });

  group('Morgenfenster (PAR-160K)', () {
    test('Vorgabe 4-11: Beginn gilt, Ende nicht', () {
      bool out(int h, int min) =>
          build(meas(), at: local(h, min))!.outsideWindow;
      expect(out(3, 59), isTrue);
      expect(out(4, 0), isFalse);
      expect(out(10, 59), isFalse);
      expect(out(11, 0), isTrue);
    });

    test('Ortszeit, nicht UTC: Versatz verschiebt die Grenze', () {
      // 03:30 UTC = 04:30 Ortszeit (+1 h): im Fenster.
      final x = buildMorningMeasurement(
        result: meas(),
        measuredAt: DateTime.utc(2026, 11, 14, 3, 30),
        utcOffset: off,
        posture: RestingPosture.lying,
        deviceManufacturer: 'H',
        deviceModel: 'M',
      )!;
      expect(x.outsideWindow, isFalse);
    });

    test('eigenes Fenster', () {
      const w = MorningWindow(6, 9);
      expect(build(meas(), at: local(5, 59), window: w)!.outsideWindow, isTrue);
      expect(build(meas(), at: local(6), window: w)!.outsideWindow, isFalse);
      expect(build(meas(), at: local(9), window: w)!.outsideWindow, isTrue);
    });

    test(
      'außerhalb: gespeichert mit Merkmal, zählt nicht, blockiert nicht',
      () {
        final early = m(3);
        expect(early.outsideWindow, isTrue);
        expect(countingMorningMeasurements([early]), isEmpty);
        final inWin = m(8);
        expect(countingMorningMeasurements([early, inWin]), [inWin]);
      },
    );

    test('Fenster parsen und prüfen', () {
      expect(MorningWindow.parse('4-11'), MorningWindow.standard);
      expect(MorningWindow.parse('0-24'), const MorningWindow(0, 24));
      for (final bad in ['', '4', '11-4', '5-5', '4-25', 'a-b', '-1-5', null]) {
        expect(MorningWindow.parse(bad), isNull, reason: '$bad');
      }
      expect(const MorningWindow(4, 11).format(), '4-11');
    });

    test('Einstellung: Vorgabe, setzen, ungültig, Alles löschen', () async {
      final session = await FakeStorage().open(Uint8List(32));
      final store = SettingsMorningWindowStore(
        session.settings,
        FakeClock(DateTime.utc(2026, 11, 14, 7)),
      );
      expect(await store.read(), MorningWindow.standard);
      await store.set(const MorningWindow(5, 9));
      expect(await store.read(), const MorningWindow(5, 9));
      expect(() => store.set(const MorningWindow(9, 5)), throwsArgumentError);
      expect(await store.read(), const MorningWindow(5, 9));
      await session.settings.set(
        SettingKeys.morningWindow,
        'kaputt',
        at: DateTime.utc(2026, 11, 14),
      );
      expect(await store.read(), MorningWindow.standard);
    });
  });

  group('Zählt heute: erste Messung des Tages im Fenster', () {
    test('die erste zählt, spätere am selben Tag nicht', () {
      final a = m(9), b = m(7), c = m(10);
      expect(countingMorningMeasurements([a, b, c]), [b]);
    });

    test('je Ortstag eine', () {
      final d1 = m(7), d2 = m(8, day: 15), d2b = m(6, day: 15);
      expect(countingMorningMeasurements([d1, d2, d2b]), [d1, d2b]);
    });

    test(
      'eine Reihe: liegend und sitzend am selben Morgen, die erste zählt (K67)',
      () {
        final lying = m(7), sitting = m(8, posture: RestingPosture.sitting);
        expect(countingMorningMeasurements([sitting, lying]), [lying]);
        // sitzend zuerst: dann zählt sitzend, die spätere liegende nicht
        final early = m(6, posture: RestingPosture.sitting);
        expect(countingMorningMeasurements([lying, early]), [early]);
      },
    );

    test(
      'liegend und sitzend an verschiedenen Tagen: eine gemeinsame Reihe',
      () {
        final l = m(7), s = m(7, day: 15, posture: RestingPosture.sitting);
        expect(countingMorningMeasurements([s, l]), [l, s]);
      },
    );

    test(
      'unbrauchbare (Entwicklermodus, K68) zählen nirgends und blocken nicht',
      () {
        final bad = MorningMeasurement(
          measuredAt: local(6),
          utcOffset: off,
          posture: RestingPosture.lying,
          deviceManufacturer: 'H',
          deviceModel: 'M1',
          method: ppgMethod,
          methodVersion: ppgMethodVersion,
          quality: PpgQuality.unusable,
          cameraIntervalsMs: const [],
          beforeValidation: true,
          outsideWindow: false,
        );
        final good = m(8);
        expect(countingMorningMeasurements([bad]), isEmpty);
        expect(countingMorningMeasurements([bad, good]), [good]);
        expect(morningSeries([bad]), isEmpty);
      },
    );

    test('je Reihe: anderes Gerät am selben Morgen zählt, zweite derselben Reihe nicht', () {
      final a = m(7), b = m(8, model: 'M2'), c = m(9, model: 'M2');
      expect(countingMorningMeasurements([c, b, a]), [a, b]);
    });

    test(
      'Tag nach Ortszeit: 23:30 UTC am Vortag ist 00:30 Ortszeit, außerhalb',
      () {
        final x = buildMorningMeasurement(
          result: meas(),
          measuredAt: DateTime.utc(2026, 11, 13, 23, 30),
          utcOffset: off,
          posture: RestingPosture.lying,
          deviceManufacturer: 'H',
          deviceModel: 'M',
        )!;
        expect(morningLocalDay(x), DateTime.utc(2026, 11, 14));
      },
    );

    test('heute zählend je Reihe: Haltung gleich, anderes Gerät eigene Reihe, '
        'gestern nicht', () {
      List<MorningMeasurement> today(List<MorningMeasurement> l) =>
          morningCountingToday(l, nowUtc: local(8), utcOffset: off);
      expect(today(const []), isEmpty);
      final sitting = m(7, posture: RestingPosture.sitting);
      expect(today([m(8), sitting]), [sitting]);
      final other = m(8, model: 'M2');
      expect(today([sitting, other]), [sitting, other]);
      expect(today([m(7, day: 13)]), isEmpty);
    });
  });

  group('Wahl der gültigen Messung des Tages (PAR-160K, FR-0215)', () {
    MorningMeasurement raw(
      DateTime utc, {
      Duration offset = off,
      double bpm = 58,
      bool chosen = false,
      String model = 'M1',
      RestingPosture posture = RestingPosture.lying,
      PpgQuality quality = PpgQuality.good,
      bool outside = false,
    }) => MorningMeasurement(
      measuredAt: utc,
      utcOffset: offset,
      posture: posture,
      deviceManufacturer: 'H',
      deviceModel: model,
      method: ppgMethod,
      methodVersion: ppgMethodVersion,
      quality: quality,
      restingHrBpm: quality == PpgQuality.unusable ? null : bpm,
      cameraIntervalsMs: const [],
      beforeValidation: true,
      outsideWindow: outside,
      chosen: chosen,
    );
    final today = DateTime.utc(2026, 11, 14);
    double? hrOn(List<MorningMeasurement> all, DateTime day) =>
        cameraDeviations(all, today: day)
            .firstWhere((d) => d.factor == ReadinessFactor.restingHeartRate)
            .byDay[day];

    test('drei brauchbare, keine gewählt: die früheste zählt', () {
      final a = raw(local(6), bpm: 50);
      final b = raw(local(6, 30), bpm: 60);
      final c = raw(local(7), bpm: 70);
      expect(countingMorningMeasurements([c, b, a]), [a]);
      expect(morningSeries([c, b, a])[lyingKey], [a]);
      expect(
        morningCountingToday([c, b, a], nowUtc: local(10), utcOffset: off),
        [a],
      );
      expect(hrOn([c, b, a], today), 50);
    });

    test(
      'die mittlere gewählt: nur sie zählt, überall statt der frühesten',
      () {
        final a = raw(local(6), bpm: 50);
        final b = raw(local(6, 30), bpm: 60, chosen: true);
        final c = raw(local(7), bpm: 70);
        final all = [a, b, c];
        expect(countingMorningMeasurements(all), [b]);
        expect(morningSeries(all)[lyingKey], [b]);
        expect(morningCountingToday(all, nowUtc: local(10), utcOffset: off), [
          b,
        ]);
        expect(hrOn(all, today), 60);
        // Schlafquelle folgt der zählenden Messung.
        expect(morningSleepSource(countingMorningMeasurements(all)), same(b));
      },
    );

    test('Haltung: liegend 06:00, sitzend 06:30 gewählt, eine Reihe (K67)', () {
      final lying = raw(local(6), bpm: 50);
      final sitting = raw(
        local(6, 30),
        bpm: 55,
        posture: RestingPosture.sitting,
        chosen: true,
      );
      final series = morningSeries([lying, sitting]);
      expect(series.keys, [lyingKey]);
      expect(series[lyingKey], [sitting]);
      expect(series[lyingKey]!.single.posture, RestingPosture.sitting);
    });

    test('Wahl an nicht wählbarer Messung wird übergangen', () {
      final a = raw(local(6), bpm: 50);
      final bad = raw(local(5), quality: PpgQuality.unusable, chosen: true);
      final outside = raw(local(12), bpm: 70, outside: true, chosen: true);
      expect(bad.isChoosable, isFalse);
      expect(outside.isChoosable, isFalse);
      expect(a.isChoosable, isTrue);
      expect(countingMorningMeasurements([bad, a, outside]), [a]);
      // Ohne wählbare Messung zählt keine.
      expect(countingMorningMeasurements([bad, outside]), isEmpty);
    });

    test('zwei gewählte in einer Reihe am selben Tag: die frühere', () {
      final a = raw(local(6), bpm: 50);
      final b = raw(local(6, 30), bpm: 60, chosen: true);
      final c = raw(local(7), bpm: 70, chosen: true);
      expect(countingMorningMeasurements([c, a, b]), [b]);
      expect(countingMorningMeasurements([c, b, a]), [b]);
    });

    test('anderer Tag und andere Reihe bleiben unberührt (K67)', () {
      final yesterday1 = raw(local(6, 0, 13), bpm: 40);
      final yesterday2 = raw(local(7, 0, 13), bpm: 45, chosen: true);
      final a = raw(local(6), bpm: 50);
      final b = raw(local(7), bpm: 60);
      final other = raw(local(6, 30), bpm: 65, model: 'M2');
      final all = [yesterday1, yesterday2, a, b, other];
      expect(countingMorningMeasurements(all), [yesterday2, a, other]);
      final series = morningSeries(all);
      expect(series[lyingKey], [yesterday2, a]);
      expect(series[const MorningSeriesKey('H', 'M2')], [other]);
    });

    test('Mitternacht (Fenster 0-24): 23:58 und 00:02 sind zwei Ortstage', () {
      final x = raw(local(23, 50), bpm: 50);
      final a = raw(local(23, 58), bpm: 55);
      final b = raw(local(0, 2, 15), bpm: 60, chosen: true);
      final c = raw(local(0, 1, 15), bpm: 65);
      expect(countingMorningMeasurements([x, a, b, c]), [x, b]);
      // ohne Wahl am 15. die früheste dort, der 14. bleibt gleich
      final b0 = raw(local(0, 2, 15), bpm: 60);
      expect(countingMorningMeasurements([x, a, b0, c]), [x, c]);
    });

    test('Versatz -5 h: Ortstag nach eigenem Versatz (K65)', () {
      final x = raw(local(6), bpm: 50);
      // 03:00 UTC am 15. ist mit -5 h 22:00 am 14.
      final y = raw(
        DateTime.utc(2026, 11, 15, 3),
        offset: const Duration(hours: -5),
        bpm: 60,
        chosen: true,
      );
      expect(morningLocalDay(y), DateTime.utc(2026, 11, 14));
      expect(countingMorningMeasurements([x, y]), [y]);
    });

    test('Zeitumstellung Europa/Berlin (25.10.2026): Ortstag je Versatz', () {
      const cest = Duration(hours: 2), cet = Duration(hours: 1);
      // 23:30 CEST am 24. (21:30 UTC), 01:30 CEST am 25. (23:30 UTC am 24.),
      // 07:00 CET am 25. (06:00 UTC), gewählt.
      final eve = raw(DateTime.utc(2026, 10, 24, 21, 30), offset: cest);
      final night = raw(DateTime.utc(2026, 10, 24, 23, 30), offset: cest);
      final morning = raw(
        DateTime.utc(2026, 10, 25, 6),
        offset: cet,
        chosen: true,
      );
      expect(morningLocalDay(night), DateTime.utc(2026, 10, 25));
      expect(countingMorningMeasurements([eve, night, morning]), [
        eve,
        morning,
      ]);
    });
  });

  group('Schlafangabe: zu welcher Messung (PAR-164K)', () {
    MorningMeasurement sm(
      int h, {
      int min = 0,
      int day = 14,
      String model = 'M1',
      SleepBand? band,
    }) => buildMorningMeasurement(
      result: meas(),
      measuredAt: local(h, min, day),
      utcOffset: off,
      posture: RestingPosture.lying,
      deviceManufacturer: 'H',
      deviceModel: model,
      sleepBand: band,
    )!;
    List<MorningMeasurement> today(List<MorningMeasurement> all) =>
        morningCountingToday(all, nowUtc: local(10), utcOffset: off);

    test('ohne zählende Messung keine', () {
      expect(morningSleepSource(const []), isNull);
    });

    test('zwei Geräte, nur das spätere mit Stufe: das spätere', () {
      final a = sm(6),
          b = sm(6, min: 30, model: 'M2', band: SleepBand.from6to7);
      final counting = today([a, b]);
      expect(counting, [a, b]);
      final source = morningSleepSource(counting);
      expect(source, same(b));
      expect(source!.sleepBand, SleepBand.from6to7);
      // die Reihenfolge der Liste ändert nichts
      expect(morningSleepSource(counting.reversed.toList()), same(b));
    });

    test('beide Geräte mit Stufe: die frühere', () {
      final a = sm(6, band: SleepBand.under5);
      final b = sm(6, min: 30, model: 'M2', band: SleepBand.over8);
      expect(morningSleepSource(today([b, a])), same(a));
      expect(morningSleepSource([b, a]), same(a));
    });

    test('ein Gerät ohne Stufe: die erste zählende', () {
      final a = sm(7), later = sm(8);
      expect(morningSleepSource(today([later, a])), same(a));
      expect(morningSleepSource(today([later, a]))!.sleepBand, isNull);
    });

    test('zwei Geräte ohne Stufe: die früheste', () {
      final a = sm(6, min: 30), b = sm(6, model: 'M2');
      expect(morningSleepSource(today([a, b])), same(b));
    });

    test('Gegenfall: Vortag, außerhalb des Fensters und zweite derselben Reihe '
        'mit Stufe zählen nicht', () {
      final a = sm(7);
      final yesterday = sm(6, day: 13, band: SleepBand.over8);
      final outside = sm(12, model: 'M2', band: SleepBand.from5to6);
      final second = sm(8, band: SleepBand.from7to8);
      expect(outside.outsideWindow, isTrue);
      final counting = today([yesterday, outside, second, a]);
      expect(counting, [a]);
      final source = morningSleepSource(counting);
      expect(source, same(a));
      expect(source!.sleepBand, isNull);
    });
  });

  group('Reihen', () {
    test('eine Reihe je Gerät, Haltung bleibt an der Messung', () {
      final l1 = m(7), l2 = m(7, day: 15);
      final s1 = m(7, day: 16, posture: RestingPosture.sitting);
      final other = m(7, day: 17, model: 'M2');
      final s = morningSeries([l1, l2, s1, other]);
      expect(s.length, 2);
      expect(s[lyingKey], [l1, l2, s1]);
      expect(s[lyingKey]!.last.posture, RestingPosture.sitting);
      expect(s[const MorningSeriesKey('H', 'M2')], [other]);
    });

    test('es gibt keine Haltung stehend', () {
      expect(RestingPosture.values.map((p) => p.storageValue), [
        'sitting',
        'lying',
      ]);
    });

    test('nur zählende Messungen in der Reihe', () {
      expect(morningSeries([m(3), m(7), m(9)]).values.single.length, 1);
    });
  });

  group('Sichtbarkeit', () {
    final all = [1, 2, 3];
    test('ohne Entwicklermodus und ohne Freigabe: nichts', () {
      expect(visibleMorningMeasurements(all, developerMode: false), isEmpty);
    });
    test('Entwicklermodus: alles', () {
      expect(visibleMorningMeasurements(all, developerMode: true), all);
    });
    test('lnRMSSD liegend bestanden: alles', () {
      final st = {
        for (final k in ValidationQuantity.values)
          k: ValidationState.notChecked,
        ValidationQuantity.lnRmssdSupine: ValidationState.passed,
      };
      expect(
        visibleMorningMeasurements(all, developerMode: false, state: st),
        all,
      );
    });
  });
}
