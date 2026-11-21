import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:core/fakes/fake_storage_morning.dart';
import 'package:test/test.dart';

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

    test('Version 3 (PAR-230) wird gespeichert, ein älterer Datensatz mit Version 2 bleibt '
        'lesbar und unverändert (Fake-Speicher)', () async {
      final store = FakeMorningStore(FakeStorageData());
      final v3 = build(meas(ibis: const [1000, double.nan, 1020, 1010]))!;
      expect(v3.methodVersion, 3);
      final old = MorningMeasurement(
        measuredAt: local(7, 0, 13).toUtc(),
        utcOffset: off,
        posture: RestingPosture.lying,
        deviceManufacturer: 'H',
        deviceModel: 'M1',
        method: 'camera-ppg',
        methodVersion: 2,
        quality: PpgQuality.good,
        restingHrBpm: 57.5,
        rmssdMs: 61,
        timingNoiseMs: 12,
        cameraIntervalsMs: const [1000, 1100, double.nan, 1050],
        beforeValidation: true,
        outsideWindow: false,
      );
      final oldId = await store.add(old);
      final newId = await store.add(v3);
      final byId = {for (final e in await store.list()) e.id: e.value};
      expect(byId[newId]!.methodVersion, 3);
      expect(byId[newId]!.method, 'camera-ppg');
      final o = byId[oldId]!;
      expect(o.methodVersion, 2);
      expect(o.rmssdMs, 61);
      expect(o.restingHrBpm, 57.5);
      expect(o.timingNoiseMs, 12);
      expect(o.cameraIntervalsMs.take(2), [1000, 1100]);
      expect(o.cameraIntervalsMs[2].isNaN, isTrue);
      expect(o.cameraIntervalsMs[3], 1050);
    });

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
          expect(
            morningRepeatAllowed(
              [out],
              nowUtc: local(8),
              utcOffset: off,
              series: lyingKey,
            ),
            isTrue,
          );
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
        expect(
          morningRepeatAllowed(
            [early],
            nowUtc: local(8),
            utcOffset: off,
            series: lyingKey,
          ),
          isTrue,
        );
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
        expect(
          morningRepeatAllowed(
            [bad],
            nowUtc: local(8),
            utcOffset: off,
            series: lyingKey,
          ),
          isTrue,
        );
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

    test('Wiederholung nur, solange heute keine gültige', () {
      bool allowed(List<MorningMeasurement> l, MorningSeriesKey k) =>
          morningRepeatAllowed(l, nowUtc: local(8), utcOffset: off, series: k);
      expect(allowed(const [], lyingKey), isTrue);
      expect(allowed([m(7)], lyingKey), isFalse);
      // die Haltung ändert nichts: eine liegende Messung sperrt auch sitzend
      expect(
        allowed([m(7, posture: RestingPosture.sitting)], lyingKey),
        isFalse,
      );
      // anderes Gerät: eigene Reihe, noch offen
      expect(allowed([m(7)], const MorningSeriesKey('H', 'M2')), isTrue);
      // gestrige gültige blockiert heute nicht
      expect(allowed([m(7, day: 13)], lyingKey), isTrue);
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
