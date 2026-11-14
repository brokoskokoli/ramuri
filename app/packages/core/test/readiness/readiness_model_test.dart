import 'dart:math';

import 'package:core/core.dart';
import 'package:test/test.dart';

import 'readiness_helpers.dart' as h;

final today = DateTime.utc(2026, 11, 14);
final now = DateTime.utc(2026, 11, 14, 8);

DeviationResult dev(
  ReadinessFactor f,
  double z, {
  ReadinessSource source = ReadinessSource.healthConnect,
  MorningSeriesKey? key,
}) => DeviationResult(
  factor: f,
  source: source,
  origin: source == ReadinessSource.healthConnect ? 'app.a' : null,
  cameraSeries: key,
  z: z,
  windowCount: 7,
  referenceCount: 28,
);

DeviationResult noZ(ReadinessFactor f, NoDeviationReason r) => DeviationResult(
  factor: f,
  source: ReadinessSource.healthConnect,
  origin: 'app.a',
  reason: r,
);

/// Schlafsitzung mit [hours] Schlafzeit; mit [eff] Prozent Effizienz aus
/// Phasen (Rest „wach“), sonst ohne Phasen.
SleepSession night(double hours, {double? eff, String origin = 'app.s'}) {
  final sleepMs = (hours * 3600000).round();
  final totalMs = eff == null ? sleepMs : (sleepMs * 100 / eff).round();
  final end = now.subtract(const Duration(hours: 1));
  final start = end.subtract(Duration(milliseconds: totalMs));
  return SleepSession(
    origin: origin,
    start: start,
    end: end,
    stages: eff == null
        ? const []
        : [
            SleepStage(
              kind: SleepStageKind.sleeping,
              start: start,
              end: start.add(Duration(milliseconds: sleepMs)),
            ),
            SleepStage(
              kind: SleepStageKind.awake,
              start: start.add(Duration(milliseconds: sleepMs)),
              end: end,
            ),
          ],
  );
}

ReadinessInputs inputs({
  double? hrvZ,
  double? rhrZ,
  double? hours,
  double? eff,
  SleepBand? band,
  double? tsb,
  int? wellbeing,
  int wellbeingAge = 0,
  Iterable<DeviationResult> camera = const [],
  CameraRelease? release,
}) => ReadinessInputs(
  today: today,
  now: now,
  hrvHealthConnect: hrvZ == null ? null : dev(ReadinessFactor.hrv, hrvZ),
  restingHrHealthConnect: rhrZ == null
      ? null
      : dev(ReadinessFactor.restingHeartRate, rhrZ),
  cameraDeviations: camera,
  release:
      release ?? const CameraRelease(developerMode: false, rmssdOptIn: false),
  sleepSessions: hours == null ? const [] : [night(hours, eff: eff)],
  sleepBand: band,
  tsbPercent: tsb,
  wellbeing: wellbeing == null
      ? null
      : ReadinessWellbeing(
          level: wellbeing,
          day: today.subtract(Duration(days: wellbeingAge)),
        ),
);

ReadinessResult calc(ReadinessInputs i) => computeReadiness(i);

Map<ValidationQuantity, ValidationState> st(
  ValidationState hr,
  ValidationState rmssd,
) => {
  ValidationQuantity.restingHr: hr,
  ValidationQuantity.lnRmssdSupine: rmssd,
  ValidationQuantity.lnRmssdSitting: rmssd,
};

List<MorningMeasurement> camSeries({double rmssdBase = 40}) => [
  for (var i = 0; i < 29; i++)
    h.morning(
      dayIdx: i,
      hr: 55 + (i % 5) * 2,
      rmssd: rmssdBase + (i % 4) * 3.0,
    ),
];

void main() {
  group('Teilskalen und ihre Grenzen', () {
    test('PAR-163: z', () {
      expect(readinessScaleZ(0), 60);
      expect(readinessScaleZ(-1), 35);
      expect(readinessScaleZ(-2), 10);
      expect(readinessScaleZ(1), 80);
      expect(readinessScaleZ(-2.4), 0);
      expect(readinessScaleZ(-5), 0);
      expect(readinessScaleZ(-2.39), closeTo(0.25, 1e-9));
      expect(readinessScaleZ(1.5), 90);
      expect(readinessScaleZ(4), 90);
      expect(readinessScaleZ(1.49), closeTo(89.8, 1e-9));
      expect(readinessScaleZ(-0.0001), closeTo(59.99750, 1e-9));
    });
    test('PAR-165: Schlafdauer', () {
      expect(readinessScaleSleepDuration(7), 70);
      expect(readinessScaleSleepDuration(6), 45);
      expect(readinessScaleSleepDuration(5), 20);
      expect(readinessScaleSleepDuration(7.5), 75);
      expect(readinessScaleSleepDuration(8), 80);
      expect(readinessScaleSleepDuration(9), 80);
      expect(readinessScaleSleepDuration(12), 80);
      expect(readinessScaleSleepDuration(4.2), 0);
      expect(readinessScaleSleepDuration(2), 0);
      expect(readinessScaleSleepDuration(4.4), closeTo(5, 1e-9));
    });
    test('PAR-166/167: Schlaf mit und ohne Effizienz', () {
      expect(readinessScaleSleep(hours: 8, efficiencyPercent: 90), 79);
      expect(readinessScaleSleep(hours: 8, efficiencyPercent: null), 80);
      // E 80: 70 - 5*5 = 45.
      expect(
        readinessScaleSleep(hours: 7, efficiencyPercent: 80),
        closeTo(0.8 * 70 + 0.2 * 45, 1e-9),
      );
      expect(
        readinessScaleSleep(hours: 7, efficiencyPercent: 100),
        closeTo(0.8 * 70 + 0.2 * 80, 1e-9),
      );
    });
    test('PAR-168: Belastung', () {
      expect(readinessScaleLoad(-10), 60);
      expect(readinessScaleLoad(0), 60);
      expect(readinessScaleLoad(25), 60);
      expect(readinessScaleLoad(-5), 60);
      expect(readinessScaleLoad(-20), 40);
      expect(readinessScaleLoad(-30), 20);
      expect(readinessScaleLoad(-35), 10);
      expect(readinessScaleLoad(-40), 0);
      expect(readinessScaleLoad(-80), 0);
      expect(readinessScaleLoad(-10.5), closeTo(59, 1e-9));
    });
    test('PAR-169: Befinden', () {
      expect(
        [for (var l = 1; l <= 5; l++) readinessScaleWellbeing(l)],
        [10, 35, 60, 75, 90],
      );
      expect(() => readinessScaleWellbeing(0), throwsRangeError);
      expect(() => readinessScaleWellbeing(6), throwsRangeError);
    });
  });

  group('Rechenbeispiele (phase-2-3-rules.md Abschnitt 5)', () {
    void ex(
      String name,
      ReadinessInputs i,
      int value,
      ReadinessBand band, {
      bool restricted = false,
    }) {
      test(name, () {
        final r = calc(i);
        expect(r.state, ReadinessState.number);
        expect(r.value, value);
        expect(r.band, band);
        expect(r.restricted, restricted);
      });
    }

    ex(
      'Alles unauffällig',
      inputs(hrvZ: 0, rhrZ: 0, hours: 7, tsb: -5, wellbeing: 3),
      63,
      ReadinessBand.normal,
    );
    ex(
      'Überall günstig',
      inputs(hrvZ: 1, rhrZ: 1, hours: 8, eff: 90, tsb: -5, wellbeing: 4),
      76,
      ReadinessBand.wellRecovered,
    );
    ex(
      'Nur HRV fällt',
      inputs(hrvZ: -2, rhrZ: 0, hours: 7, tsb: -5, wellbeing: 3),
      51,
      ReadinessBand.normal,
    );
    ex(
      'Nur wenig Schlaf',
      inputs(hrvZ: 0, rhrZ: 0, hours: 5, tsb: -5, wellbeing: 3),
      48,
      ReadinessBand.elevatedLoad,
    );
    ex(
      'Nur hohe Belastung',
      inputs(hrvZ: 0, rhrZ: 0, hours: 7, tsb: -30, wellbeing: 3),
      57,
      ReadinessBand.normal,
    );
    ex(
      'Mehrere Faktoren mäßig',
      inputs(hrvZ: -1, rhrZ: -1, hours: 6, tsb: -20, wellbeing: 3),
      41,
      ReadinessBand.elevatedLoad,
    );
    ex(
      'Mehrere Faktoren stark',
      inputs(hrvZ: -2, rhrZ: -2, hours: 5, tsb: -35, wellbeing: 2),
      16,
      ReadinessBand.recoveryAdvised,
    );
    ex(
      'Nur HRV und Schlaf',
      inputs(hrvZ: 0, hours: 7),
      65,
      ReadinessBand.normal,
      restricted: true,
    );

    test('Höchstwerte aus PAR-170 (82,5 / 86,5 / 86 / 84,5 vor Rundung)', () {
      // Ohne Kappung: rohe Mittel aus den Teilskalen.
      final all = calc(
        inputs(hrvZ: 9, rhrZ: 9, hours: 9, tsb: 0, wellbeing: 5),
      );
      expect(all.value, 83); // 82,5 rundet auf 83
      expect(all.capped, isFalse);
      double raw(Set<ReadinessFactorId> ids) {
        final r = calc(
          inputs(hrvZ: 9, rhrZ: 9, hours: 9, tsb: 0, wellbeing: 5),
        );
        var s = 0.0, w = 0.0;
        for (final f in r.factors.where((f) => ids.contains(f.id))) {
          s += f.weight * f.score;
          w += f.weight;
        }
        return s / w;
      }

      expect(raw(ReadinessFactorId.values.toSet()), 82.5);
      expect(
        raw({
          ReadinessFactorId.hrv,
          ReadinessFactorId.restingHeartRate,
          ReadinessFactorId.sleep,
          ReadinessFactorId.wellbeing,
        }),
        closeTo(86.47, 0.01),
      );
      expect(
        raw({
          ReadinessFactorId.hrv,
          ReadinessFactorId.restingHeartRate,
          ReadinessFactorId.sleep,
        }),
        86,
      );
      expect(
        raw({ReadinessFactorId.hrv, ReadinessFactorId.sleep}),
        closeTo(84.5, 0.05),
      );
    });

    test('Erreichbarkeit „Gut erholt“ (Tabelle, Befinden 3/4/5)', () {
      int v(double z, double h, int b) =>
          calc(inputs(hrvZ: z, rhrZ: z, hours: h, tsb: -5, wellbeing: b))
              .value!;
      // 8 h: Befinden 3 ab z 0,94 (74,46 gerundet 74; 0,95 ergibt 75).
      expect(v(0.93, 8, 3), 74);
      expect(v(0.95, 8, 3), 75);
      expect(v(0.77, 8, 4), 74);
      expect(v(0.78, 8, 4), 75);
      expect(v(1.28, 7, 3), 75);
      expect(v(1.2, 7, 3), 74);
      // 6,5 h: nur mit Befinden 5 erreichbar.
      expect(v(1.5, 6.5, 3), 73);
      expect(v(1.5, 6.5, 4), 74);
      expect(v(1.5, 6.5, 5), 76);
    });
  });

  group('Gesamtwert PAR-170', () {
    test('Kappung 74 ohne Belastung, mit Belastung nicht', () {
      final capped = calc(inputs(hrvZ: 2, rhrZ: 2, hours: 9, wellbeing: 5));
      expect(capped.value, 74);
      expect(capped.capped, isTrue);
      expect(capped.band, ReadinessBand.normal);
      final full = calc(
        inputs(hrvZ: 2, rhrZ: 2, hours: 9, wellbeing: 5, tsb: 0),
      );
      expect(full.value, 83);
      expect(full.capped, isFalse);
    });
    test('Kappung greift erst über 74', () {
      // Roh 73,6 ergibt gerundet 74 (nicht gekappt), roh 65 bleibt.
      final r = calc(inputs(hrvZ: 0, hours: 7));
      expect(r.capped, isFalse);
      final r2 = calc(inputs(hrvZ: 1.5, hours: 7.5));
      // (25*90+30*75)/55 = 81,8, gekappt.
      expect(r2.value, 74);
      expect(r2.capped, isTrue);
    });
    test('Rundung halb auf (50,5 und 15,5)', () {
      expect(
        calc(inputs(hrvZ: -2, rhrZ: 0, hours: 7, tsb: -5, wellbeing: 3)).value,
        51,
      );
    });
    test('Gewichte, Faktoren und fehlende Faktoren werden ausgewiesen', () {
      final r = calc(inputs(hrvZ: 0, rhrZ: 0, hours: 7, wellbeing: 3));
      expect(
        {for (final f in r.factors) f.id: f.weight},
        {
          ReadinessFactorId.hrv: 25,
          ReadinessFactorId.restingHeartRate: 20,
          ReadinessFactorId.sleep: 30,
          ReadinessFactorId.wellbeing: 10,
        },
      );
      expect(r.missing, [ReadinessFactorId.load]);
      expect(r.restricted, isTrue);
      expect(r.method, 'readiness');
      expect(r.methodVersion, 1);
    });
    test('Band-Grenzen (FR-0116)', () {
      expect(readinessBandOf(100), ReadinessBand.wellRecovered);
      expect(readinessBandOf(75), ReadinessBand.wellRecovered);
      expect(readinessBandOf(74), ReadinessBand.normal);
      expect(readinessBandOf(50), ReadinessBand.normal);
      expect(readinessBandOf(49), ReadinessBand.elevatedLoad);
      expect(readinessBandOf(25), ReadinessBand.elevatedLoad);
      expect(readinessBandOf(24), ReadinessBand.recoveryAdvised);
      expect(readinessBandOf(0), ReadinessBand.recoveryAdvised);
    });
    test('Wert nie außerhalb 0 bis 100', () {
      final lo = calc(
        inputs(hrvZ: -9, rhrZ: -9, hours: 3, tsb: -90, wellbeing: 1),
      );
      expect(lo.value, inInclusiveRange(0, 100));
      expect(lo.band, ReadinessBand.recoveryAdvised);
    });
  });

  group('Faktoren: Schlaf, Belastung, Befinden', () {
    test('Schlaf aus Health Connect: Hauptschlaf, Effizienz, Schätzung', () {
      final r = calc(inputs(hrvZ: 0, hours: 8, eff: 90));
      final s = r.factors.singleWhere((f) => f.id == ReadinessFactorId.sleep);
      expect(s.source, ReadinessFactorSource.healthConnect);
      expect(s.score, closeTo(79, 1e-6));
      expect(s.estimated, isFalse);
      final e = calc(inputs(hrvZ: 0, hours: 7)).factors
          .singleWhere((f) => f.id == ReadinessFactorId.sleep);
      expect(e.estimated, isTrue); // ohne Phasen: Schätzung, Dauer allein
      expect(e.score, 70);
    });
    test('Nickerchen (unter 3 h) ist kein Hauptschlaf', () {
      final r = calc(inputs(hrvZ: 0, hours: 2.9));
      expect(r.missing, contains(ReadinessFactorId.sleep));
      expect(r.state, ReadinessState.limited);
    });
    test('Selbstangabe: feste Stundenwerte, ohne Effizienz', () {
      final expected = {
        SleepBand.under5: 4.5,
        SleepBand.from5to6: 5.5,
        SleepBand.from6to7: 6.5,
        SleepBand.from7to8: 7.5,
        SleepBand.over8: 8.5,
      };
      for (final e in expected.entries) {
        final r = calc(inputs(hrvZ: 0, band: e.key));
        final s = r.factors.singleWhere((f) => f.id == ReadinessFactorId.sleep);
        expect(s.source, ReadinessFactorSource.selfReport);
        expect(s.score, readinessScaleSleepDuration(e.value));
        expect(
          r.facts
              .singleWhere((f) => f.kind == ReadinessFactKind.sleepDuration)
              .hours,
          e.value,
        );
      }
    });
    test('Health Connect geht der Selbstangabe vor', () {
      final r = calc(inputs(hrvZ: 0, hours: 7, band: SleepBand.under5));
      final s = r.factors.singleWhere((f) => f.id == ReadinessFactorId.sleep);
      expect(s.source, ReadinessFactorSource.healthConnect);
      expect(s.score, 70);
    });
    test('Befinden: höchstens 3 Tage alt, sonst herausgerechnet', () {
      for (final age in [0, 1, 3]) {
        final r = calc(
          inputs(hrvZ: 0, hours: 7, wellbeing: 5, wellbeingAge: age),
        );
        expect(r.missing, isNot(contains(ReadinessFactorId.wellbeing)));
      }
      for (final age in [4, 10, -1]) {
        final r = calc(
          inputs(hrvZ: 0, hours: 7, wellbeing: 5, wellbeingAge: age),
        );
        expect(r.missing, contains(ReadinessFactorId.wellbeing));
        expect(r.value, 65);
      }
    });
    test('Befinden außerhalb 1 bis 5 wirft', () {
      expect(
        () => calc(inputs(hrvZ: 0, hours: 7, wellbeing: 6)),
        throwsArgumentError,
      );
    });
    test('TSB%: fehlt bei Sperre (PAR-073, PAR-090)', () {
      LoadDay day({
        Set<LoadProvisionalReason> ctl = const {},
        double? m = -20,
      }) => LoadDay(
        day: today,
        load: 0,
        atl: 1,
        ctl: 1,
        tsb: 0,
        tsbPercentMean7: m,
        flags: const {},
        atlProvisionalReasons: const {},
        ctlProvisionalReasons: ctl,
        unitCount: 0,
        ratedUnits: 0,
        convertedUnits: 0,
        unratedUnits: 0,
      );
      expect(readinessTsbPercent(day()), -20);
      expect(readinessTsbPercent(day(m: null)), isNull);
      expect(readinessTsbPercent(null), isNull);
      for (final reason in LoadProvisionalReason.values) {
        expect(readinessTsbPercent(day(ctl: {reason})), isNull);
      }
    });
  });

  group('Entscheidung Zahl / eingeschränkt / unzureichend (PAR-171)', () {
    test('Zahl nur mit HRV und Schlaf', () {
      expect(calc(inputs(hrvZ: 0, hours: 7)).state, ReadinessState.number);
      final noSleep = calc(inputs(hrvZ: 0, rhrZ: 0));
      expect(noSleep.state, ReadinessState.limited);
      expect(noSleep.value, isNull);
      expect(noSleep.band, isNull);
      expect(noSleep.blockers, [ReadinessFactorId.sleep]);
      final noHrv = calc(inputs(rhrZ: 0, hours: 6, tsb: -5, wellbeing: 3));
      expect(noHrv.state, ReadinessState.limited);
      expect(noHrv.value, isNull);
      expect(noHrv.blockers, [ReadinessFactorId.hrv]);
      expect(
        noHrv.facts.map((f) => f.kind),
        containsAll([
          ReadinessFactKind.restingHeartRateDeviation,
          ReadinessFactKind.sleepDuration,
        ]),
      );
    });
    test('Referenz fehlt: HRV ohne z gibt keine Zahl', () {
      final i = ReadinessInputs(
        today: today,
        now: now,
        hrvHealthConnect: noZ(
          ReadinessFactor.hrv,
          NoDeviationReason.tooFewReference,
        ),
        sleepSessions: [night(7)],
      );
      final r = calc(i);
      expect(r.state, ReadinessState.limited);
      expect(r.hasFreshMeasurement, isTrue);
    });
    test('Eingeschränkt auch mit nur einer frischen Messung', () {
      final i = ReadinessInputs(
        today: today,
        now: now,
        restingHrHealthConnect: noZ(
          ReadinessFactor.restingHeartRate,
          NoDeviationReason.tooFewReference,
        ),
      );
      expect(calc(i).state, ReadinessState.limited);
    });
    test('Unzureichende Daten ohne Schlaf und ohne frische Messung', () {
      expect(calc(inputs()).state, ReadinessState.insufficient);
      final old = ReadinessInputs(
        today: today,
        now: now,
        hrvHealthConnect: noZ(
          ReadinessFactor.hrv,
          NoDeviationReason.noValueToday,
        ),
        restingHrHealthConnect: noZ(
          ReadinessFactor.restingHeartRate,
          NoDeviationReason.noSeries,
        ),
      );
      final r = calc(old);
      expect(r.state, ReadinessState.insufficient);
      expect(r.hasFreshMeasurement, isFalse);
      expect(r.value, isNull);
    });
    test('Nur Schlaf: eingeschränkt mit der Tatsache', () {
      final r = calc(inputs(hours: 6));
      expect(r.state, ReadinessState.limited);
      expect(r.facts.single.kind, ReadinessFactKind.sleepDuration);
      expect(r.facts.single.hours, 6);
    });
    test('Nur Selbstangabe des Schlafs ohne HRV: eingeschränkt', () {
      expect(
        calc(inputs(band: SleepBand.from6to7)).state,
        ReadinessState.limited,
      );
    });
    test('toString nennt keine Werte', () {
      final r = calc(inputs(hrvZ: 0.123456, hours: 7.77, wellbeing: 3));
      final all = [
        r.toString(),
        ...r.factors.map((f) => f.toString()),
        ...r.facts.map((f) => f.toString()),
        ReadinessWellbeing(level: 3, day: today).toString(),
      ].join(' ');
      expect(all, isNot(contains('0.12')));
      expect(all, isNot(contains('7.77')));
      expect(all, isNot(contains(r.value.toString())));
    });
  });

  group('Kamera (Teil B) im Gesamtmodell', () {
    final cams = cameraDeviations(camSeries(), today: h.todayKey);
    ReadinessInputs camIn(CameraRelease rel, {SleepBand? band}) =>
        ReadinessInputs(
          today: h.todayKey,
          now: now,
          cameraDeviations: cams,
          release: rel,
          sleepBand: band ?? SleepBand.from7to8,
        );

    test('Vorlage hat z für beide Faktoren', () {
      expect(cams.where((c) => c.hasZ).length, greaterThanOrEqualTo(2));
    });
    test('E1: ohne Entwicklermodus, nicht geprüft, ohne Uhr nie eine Zahl', () {
      for (final optIn in [false, true]) {
        final r = calc(
          camIn(
            CameraRelease(
              developerMode: false,
              rmssdOptIn: optIn,
              state: st(ValidationState.notChecked, ValidationState.notChecked),
            ),
          ),
        );
        expect(r.state, ReadinessState.limited);
        expect(r.value, isNull);
        expect(r.blockers, [ReadinessFactorId.hrv]);
        // Kamera-RMSSD steht nur als markierte Tatsache da.
        final m = r.markedFacts.singleWhere(
          (f) => f.kind == ReadinessFactKind.hrvDeviation,
        );
        expect(m.mark, MorningRmssdMark.notChecked);
        expect(
          r.factors.map((f) => f.id),
          isNot(contains(ReadinessFactorId.hrv)),
        );
      }
    });
    test(
      'Stand bestanden ohne Opt-in: keine Zahl, markiert nicht eingeschaltet',
      () {
        final r = calc(
          camIn(
            CameraRelease(
              developerMode: false,
              rmssdOptIn: false,
              state: st(ValidationState.passed, ValidationState.passed),
            ),
          ),
        );
        expect(r.value, isNull);
        expect(
          r.markedFacts
              .singleWhere((f) => f.kind == ReadinessFactKind.hrvDeviation)
              .mark,
          MorningRmssdMark.notEnabled,
        );
      },
    );
    test('eingeschränkt/nicht bestanden: „ungenauer als erwartet“', () {
      for (final s in [ValidationState.limited, ValidationState.failed]) {
        final r = calc(
          camIn(
            CameraRelease(
              developerMode: false,
              rmssdOptIn: true,
              state: st(s, s),
            ),
          ),
        );
        expect(r.value, isNull);
        expect(
          r.markedFacts
              .singleWhere((f) => f.kind == ReadinessFactKind.hrvDeviation)
              .mark,
          MorningRmssdMark.inaccurate,
        );
      }
    });
    test('Ruhepuls nicht bestanden: markierte Tatsache, nie Faktor', () {
      final r = calc(
        camIn(
          CameraRelease(
            developerMode: false,
            rmssdOptIn: false,
            state: st(ValidationState.failed, ValidationState.notChecked),
          ),
        ),
      );
      expect(
        r.markedFacts.any(
          (f) => f.kind == ReadinessFactKind.restingHeartRateDeviation,
        ),
        isTrue,
      );
      expect(
        r.factors.map((f) => f.id),
        isNot(contains(ReadinessFactorId.restingHeartRate)),
      );
    });
    test('Entwicklermodus = bestanden + Opt-in: dieselbe Zahl', () {
      final dev = calc(
        camIn(
          CameraRelease(
            developerMode: true,
            rmssdOptIn: false,
            state: st(ValidationState.notChecked, ValidationState.notChecked),
          ),
        ),
      );
      final passed = calc(
        camIn(
          CameraRelease(
            developerMode: false,
            rmssdOptIn: true,
            state: st(ValidationState.passed, ValidationState.passed),
          ),
        ),
      );
      expect(dev.state, ReadinessState.number);
      expect(dev.value, isNotNull);
      expect(passed.value, dev.value);
      expect(
        [for (final f in dev.factors) (f.id, f.score)],
        [for (final f in passed.factors) (f.id, f.score)],
      );
      expect(dev.markedFacts, isEmpty);
    });
    test('Ohne Schlafangabe auch im Entwicklermodus keine Zahl', () {
      final i = ReadinessInputs(
        today: h.todayKey,
        now: now,
        cameraDeviations: cams,
        release: const CameraRelease(developerMode: true, rmssdOptIn: false),
      );
      final r = calc(i);
      expect(r.value, isNull);
      expect(r.state, ReadinessState.limited);
      expect(r.blockers, [ReadinessFactorId.sleep]);
    });
    test('Health Connect geht der Kamera vor, nie gemittelt', () {
      final withHc = ReadinessInputs(
        today: h.todayKey,
        now: now,
        hrvHealthConnect: dev(ReadinessFactor.hrv, -1),
        cameraDeviations: cams,
        release: const CameraRelease(developerMode: true, rmssdOptIn: false),
        sleepBand: SleepBand.from7to8,
      );
      final r = calc(withHc);
      final f = r.factors.singleWhere((f) => f.id == ReadinessFactorId.hrv);
      expect(f.source, ReadinessFactorSource.healthConnect);
      expect(f.score, 35);
    });
  });

  group('Eigenschaften (Zufallsdaten, Seed fest)', () {
    test('Fehlende Faktoren heben den Wert ohne Belastung nie über 74', () {
      var over = 0;
      for (var seed = 0; seed < 400; seed++) {
        final rnd = Random(seed);
        double? z() => rnd.nextBool() ? (rnd.nextDouble() * 6 - 3) : null;
        final hrvZ = z() ?? 3.0, rhrZ = z();
        final hours = 3 + rnd.nextDouble() * 8;
        final w = rnd.nextBool() ? 1 + rnd.nextInt(5) : null;
        final i = inputs(hrvZ: hrvZ, rhrZ: rhrZ, hours: hours, wellbeing: w);
        final r = calc(i);
        expect(r.value!, lessThanOrEqualTo(74), reason: 'seed $seed');
        final withLoad = calc(
          inputs(hrvZ: hrvZ, rhrZ: rhrZ, hours: hours, wellbeing: w, tsb: 0),
        );
        if (withLoad.value! > 74) over++;
      }
      expect(over, greaterThan(20), reason: 'Kappung wird ausgeübt');
    });

    test('Markierte Tatsache ändert die Zahl nie', () {
      var marked = 0;
      final lying = const MorningSeriesKey(RestingPosture.lying, 'H', 'M1');
      for (var seed = 0; seed < 300; seed++) {
        final rnd = Random(seed);
        final hours = 4 + rnd.nextDouble() * 6;
        final base = inputs(
          hrvZ: rnd.nextDouble() * 4 - 2,
          rhrZ: rnd.nextDouble() * 4 - 2,
          hours: hours,
          tsb: rnd.nextBool() ? -rnd.nextDouble() * 40 : null,
          wellbeing: rnd.nextBool() ? 1 + rnd.nextInt(5) : null,
        );
        final states = ValidationState.values;
        final rel = CameraRelease(
          developerMode: false,
          rmssdOptIn: rnd.nextBool(),
          state: st(states[rnd.nextInt(4)], states[rnd.nextInt(4)]),
        );
        // Kamera extrem, aber HC hat z: gesperrte Reihen dürfen nichts ändern.
        final cam = [
          dev(
            ReadinessFactor.hrv,
            rnd.nextDouble() * 20 - 10,
            source: ReadinessSource.camera,
            key: lying,
          ),
          dev(
            ReadinessFactor.restingHeartRate,
            rnd.nextDouble() * 20 - 10,
            source: ReadinessSource.camera,
            key: lying,
          ),
        ];
        final r0 = calc(base);
        final r1 = calc(
          ReadinessInputs(
            today: today,
            now: now,
            hrvHealthConnect: base.hrvHealthConnect,
            restingHrHealthConnect: base.restingHrHealthConnect,
            sleepSessions: base.sleepSessions,
            tsbPercent: base.tsbPercent,
            wellbeing: base.wellbeing,
            cameraDeviations: cam,
            release: rel,
          ),
        );
        // HC hat jeweils z, Kamera wird nie gewählt: Zahl und Faktoren gleich.
        expect(r1.value, r0.value, reason: 'seed $seed');
        expect(
          [for (final f in r1.factors) (f.id, f.score, f.source)],
          [for (final f in r0.factors) (f.id, f.score, f.source)],
        );
        marked += r1.markedFacts.length;
      }
      expect(marked, greaterThan(100));
    });

    test('Nur-Kamera: gesperrte Reihe ändert Zahl oder Faktoren nie', () {
      final lying = const MorningSeriesKey(RestingPosture.lying, 'H', 'M1');
      for (var seed = 0; seed < 200; seed++) {
        final rnd = Random(seed);
        final rel = CameraRelease(
          developerMode: false,
          rmssdOptIn: false, // HRV nie frei
          state: st(
            ValidationState.values[rnd.nextInt(4)],
            ValidationState.values[rnd.nextInt(4)],
          ),
        );
        DeviationResult camHrv(double z) => dev(
          ReadinessFactor.hrv,
          z,
          source: ReadinessSource.camera,
          key: lying,
        );
        ReadinessResult run(double z) => calc(
          ReadinessInputs(
            today: today,
            now: now,
            cameraDeviations: [camHrv(z)],
            release: rel,
            sleepBand: SleepBand.from7to8,
          ),
        );
        final a = run(-8), b = run(8);
        expect(a.value, isNull);
        expect(b.value, isNull);
        expect(a.state, ReadinessState.limited);
        expect(a.factors.length, b.factors.length);
      }
    });
  });
}
