import 'dart:typed_data';

import 'package:core/core.dart';
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

const lyingKey = MorningSeriesKey(RestingPosture.lying, 'H', 'M1');

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

    test('je Reihe: liegend und sitzend am selben Morgen zählen beide', () {
      final lying = m(7), sitting = m(8, posture: RestingPosture.sitting);
      expect(countingMorningMeasurements([sitting, lying]), [lying, sitting]);
    });

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
      // andere Haltung oder anderes Gerät: eigene Reihe, noch offen
      expect(
        allowed([
          m(7),
        ], const MorningSeriesKey(RestingPosture.sitting, 'H', 'M1')),
        isTrue,
      );
      expect(
        allowed([
          m(7),
        ], const MorningSeriesKey(RestingPosture.lying, 'H', 'M2')),
        isTrue,
      );
      // gestrige gültige blockiert heute nicht
      expect(allowed([m(7, day: 13)], lyingKey), isTrue);
    });
  });

  group('Reihen', () {
    test('Haltung ist eine eigene Reihe, Gerät auch', () {
      final l1 = m(7), l2 = m(7, day: 15);
      final s1 = m(7, day: 16, posture: RestingPosture.sitting);
      final other = m(7, day: 17, model: 'M2');
      final s = morningSeries([l1, l2, s1, other]);
      expect(s.length, 3);
      expect(s[const MorningSeriesKey(RestingPosture.lying, 'H', 'M1')], [
        l1,
        l2,
      ]);
      expect(s[const MorningSeriesKey(RestingPosture.sitting, 'H', 'M1')], [
        s1,
      ]);
      expect(s[const MorningSeriesKey(RestingPosture.lying, 'H', 'M2')], [
        other,
      ]);
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
