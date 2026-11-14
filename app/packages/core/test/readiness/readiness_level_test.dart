import 'dart:math';

import 'package:core/core.dart';
import 'package:test/test.dart';

import 'readiness_c2_helpers.dart';

List<ReadinessLevelReasonCode> codes(ReadinessResult r) => [
  for (final x in r.levelReasons) x.code,
];

void main() {
  group('Stufe PAR-148 vorläufig / PAR-149 ausreichend', () {
    test('Grenzfälle HRV-Referenz 14, 17, 18 (mit Ruhepuls)', () {
      for (final n in [14, 17]) {
        final r = computeReadiness(
          inputs(hrvZ: 0, rhrZ: 0, hours: 7, hrvRef: n),
        );
        expect(r.level, ReadinessLevel.provisional, reason: '$n');
        expect(
          r.levelReasons.first.code,
          ReadinessLevelReasonCode.hrvReferenceBelowSufficient,
        );
        expect(r.levelReasons.first.count, n);
        expect(r.levelReasons.first.required, 18);
      }
      final r18 = computeReadiness(
        inputs(hrvZ: 0, rhrZ: 0, hours: 7, hrvRef: 18),
      );
      expect(r18.level, ReadinessLevel.sufficient);
      expect(
        codes(r18),
        isNot(contains(ReadinessLevelReasonCode.hrvReferenceBelowSufficient)),
      );
    });
    test('18 Messungen ohne Ruhepuls bleibt vorläufig (PAR-149)', () {
      final r = computeReadiness(inputs(hrvZ: 0, hours: 7, hrvRef: 28));
      expect(r.level, ReadinessLevel.provisional);
      expect(codes(r), [ReadinessLevelReasonCode.restingHrMissing]);
    });
    test('Ruhepuls ohne eigene Referenz zählt nicht als Faktor', () {
      final i = ReadinessInputs(
        today: today,
        now: now,
        hrvHealthConnect: dev(ReadinessFactor.hrv, 0),
        restingHrHealthConnect: noZ(
          ReadinessFactor.restingHeartRate,
          NoDeviationReason.tooFewReference,
          ref: 10,
        ),
        sleepSessions: [night(7)],
      );
      final r = computeReadiness(i);
      expect(r.level, ReadinessLevel.provisional);
      expect(codes(r), contains(ReadinessLevelReasonCode.restingHrMissing));
    });
    test('nur HRV und Schlaf, 14 Messungen: beide Gründe, HRV zuerst', () {
      final r = computeReadiness(inputs(hrvZ: 0, hours: 7, hrvRef: 14));
      expect(r.level, ReadinessLevel.provisional);
      expect(codes(r), [
        ReadinessLevelReasonCode.hrvReferenceBelowSufficient,
        ReadinessLevelReasonCode.restingHrMissing,
      ]);
    });
  });

  group('Stufe PAR-150 gut', () {
    test('alle Bedingungen: gut, ohne Grund', () {
      final r = computeReadiness(goodInputs());
      expect(r.level, ReadinessLevel.good);
      expect(r.levelReasons, isEmpty);
    });
    test('Referenz 20 statt 21: ausreichend', () {
      final r = computeReadiness(goodInputs(hrvRef: 20));
      expect(r.level, ReadinessLevel.sufficient);
      expect(
        r.levelReasons.single.code,
        ReadinessLevelReasonCode.hrvReferenceBelowGood,
      );
      expect(r.levelReasons.single.count, 20);
      expect(r.levelReasons.single.required, 21);
    });
    test('Schlafphasen fehlen (ohne Phasen, Selbstangabe)', () {
      final noPhases = computeReadiness(goodInputs(eff: null));
      expect(noPhases.level, ReadinessLevel.sufficient);
      expect(codes(noPhases), [ReadinessLevelReasonCode.sleepPhasesMissing]);
      final selfReport = computeReadiness(
        inputs(
          hrvZ: 0,
          rhrZ: 0,
          band: SleepBand.from7to8,
          tsb: -5,
          hrvRef: 21,
          span: 28,
        ),
      );
      expect(selfReport.level, ReadinessLevel.sufficient);
      expect(codes(selfReport), [ReadinessLevelReasonCode.sleepPhasesMissing]);
    });
    test('Belastung fehlt', () {
      final r = computeReadiness(goodInputs(tsb: null));
      expect(r.level, ReadinessLevel.sufficient);
      expect(codes(r), [ReadinessLevelReasonCode.loadMissing]);
    });
    test('gleiche Quelle seit 27 / 28 Tagen', () {
      final r27 = computeReadiness(goodInputs(span: 27));
      expect(r27.level, ReadinessLevel.sufficient);
      expect(
        r27.levelReasons.single.code,
        ReadinessLevelReasonCode.sourceTooShort,
      );
      expect(r27.levelReasons.single.count, 27);
      expect(r27.levelReasons.single.required, 28);
      expect(computeReadiness(goodInputs(span: 28)).level, ReadinessLevel.good);
      expect(
        computeReadiness(goodInputs(span: 0)).level,
        ReadinessLevel.sufficient,
      );
    });
    test('Befinden ist nicht nötig, ändert die Stufe nicht', () {
      final base = computeReadiness(goodInputs());
      final withW = computeReadiness(
        inputs(
          hrvZ: 0,
          rhrZ: 0,
          hours: 7,
          eff: 95,
          tsb: -5,
          hrvRef: 21,
          span: 28,
          wellbeing: 1,
        ),
      );
      expect(base.level, withW.level);
    });
    test('readinessSourceSpanDays', () {
      final t = DateTime.utc(2026, 11, 14);
      expect(readinessSourceSpanDays([], t), 0);
      expect(readinessSourceSpanDays([DateTime.utc(2026, 10, 17), t], t), 28);
      expect(readinessSourceSpanDays([DateTime.utc(2026, 10, 18)], t), 27);
      expect(readinessSourceSpanDays([DateTime.utc(2026, 11, 20)], t), 0);
    });
  });

  group('Stufe PAR-147 nicht bestimmbar', () {
    ReadinessResult withHrv(DeviationResult d, {bool sleep = true}) =>
        computeReadiness(
          ReadinessInputs(
            today: today,
            now: now,
            hrvHealthConnect: d,
            sleepSessions: sleep ? [night(7)] : const [],
          ),
        );
    test('je Grund ohne z ein Code, Referenz mit Zahl', () {
      final expected = {
        NoDeviationReason.noSeries: ReadinessLevelReasonCode.hrvNoSeries,
        NoDeviationReason.noValueToday:
            ReadinessLevelReasonCode.hrvNoValueToday,
        NoDeviationReason.tooFewInWindow:
            ReadinessLevelReasonCode.hrvTooFewInWindow,
        NoDeviationReason.tooFewReference:
            ReadinessLevelReasonCode.hrvTooFewReference,
        NoDeviationReason.madTooSmall: ReadinessLevelReasonCode.hrvMadTooSmall,
      };
      for (final e in expected.entries) {
        final r = withHrv(noZ(ReadinessFactor.hrv, e.key, ref: 9));
        expect(r.state, ReadinessState.limited);
        expect(r.level, ReadinessLevel.notDeterminable);
        expect(r.levelReasons.single.code, e.value);
        if (e.key == NoDeviationReason.tooFewReference) {
          expect(r.levelReasons.single.count, 9);
          expect(r.levelReasons.single.required, 14);
        }
      }
    });
    test('keine Reihe: hrvNoSeries; Schlaf fehlt: sleepMissing', () {
      final r = computeReadiness(ReadinessInputs(today: today, now: now));
      expect(r.state, ReadinessState.insufficient);
      expect(r.level, ReadinessLevel.notDeterminable);
      expect(codes(r), [
        ReadinessLevelReasonCode.hrvNoSeries,
        ReadinessLevelReasonCode.sleepMissing,
      ]);
      final s = withHrv(dev(ReadinessFactor.hrv, 0), sleep: false);
      expect(codes(s), [ReadinessLevelReasonCode.sleepMissing]);
      expect(s.level, ReadinessLevel.notDeterminable);
    });
    test('gesperrte Kamera-HRV mit z', () {
      final key = const MorningSeriesKey(RestingPosture.sitting, 'H', 'M1');
      final i = ReadinessInputs(
        today: today,
        now: now,
        cameraDeviations: [
          dev(ReadinessFactor.hrv, 0, source: ReadinessSource.camera, key: key),
        ],
        release: CameraRelease(
          developerMode: false,
          rmssdOptIn: true,
          state: {
            ValidationQuantity.lnRmssdSupine: ValidationState.passed,
            ValidationQuantity.lnRmssdSitting: ValidationState.failed,
          },
        ),
        sleepSessions: [night(7)],
      );
      final r = computeReadiness(i);
      expect(r.state, ReadinessState.limited);
      expect(r.level, ReadinessLevel.notDeterminable);
      expect(codes(r), contains(ReadinessLevelReasonCode.hrvCameraLocked));
    });
  });

  group('Hinweis „wenige Messungen“ (PAR-148, PAR-161K)', () {
    final key = const MorningSeriesKey(RestingPosture.lying, 'H', 'M1');
    ReadinessResult cam({required bool few, int ref = 28}) => computeReadiness(
      ReadinessInputs(
        today: today,
        now: now,
        cameraDeviations: [
          dev(
            ReadinessFactor.hrv,
            0,
            source: ReadinessSource.camera,
            key: key,
            few: few,
            ref: ref,
          ),
          dev(
            ReadinessFactor.restingHeartRate,
            0,
            source: ReadinessSource.camera,
            key: key,
            ref: ref,
          ),
        ],
        release: CameraRelease(developerMode: true, rmssdOptIn: false),
        sleepSessions: [night(7)],
      ),
    );
    test('Hinweis steht im Grund, ändert die Stufe nicht', () {
      final r = cam(few: true);
      expect(r.state, ReadinessState.number);
      expect(r.level, ReadinessLevel.sufficient);
      expect(codes(r).last, ReadinessLevelReasonCode.fewMeasurements);
      final r2 = cam(few: false);
      expect(
        codes(r2),
        isNot(contains(ReadinessLevelReasonCode.fewMeasurements)),
      );
      expect(r2.level, r.level);
    });
    test('bei vorläufig ebenfalls, nach den Bedingungen', () {
      final r = cam(few: true, ref: 15);
      expect(r.level, ReadinessLevel.provisional);
      expect(codes(r), [
        ReadinessLevelReasonCode.hrvReferenceBelowSufficient,
        ReadinessLevelReasonCode.fewMeasurements,
      ]);
    });
  });

  group('Einordnung (PAR-159)', () {
    test('keine Zahl ohne Band und Stufe; Gründe nicht leer ohne gut', () {
      var numbers = 0;
      for (var seed = 0; seed < 400; seed++) {
        final rnd = Random(seed);
        final r = computeReadiness(
          inputs(
            hrvZ: rnd.nextInt(4) == 0 ? null : rnd.nextDouble() * 4 - 2,
            rhrZ: rnd.nextBool() ? rnd.nextDouble() * 4 - 2 : null,
            hours: rnd.nextInt(4) == 0 ? null : 3 + rnd.nextDouble() * 7,
            eff: rnd.nextBool() ? 80 + rnd.nextDouble() * 15 : null,
            tsb: rnd.nextBool() ? -rnd.nextDouble() * 40 : null,
            wellbeing: rnd.nextBool() ? 1 + rnd.nextInt(5) : null,
            hrvRef: 14 + rnd.nextInt(16),
            span: rnd.nextInt(40),
          ),
        );
        if (r.value != null) {
          numbers++;
          expect(r.band, isNotNull, reason: 'seed $seed');
          expect(r.level, isNot(ReadinessLevel.notDeterminable));
        } else {
          expect(r.band, isNull);
          expect(r.level, ReadinessLevel.notDeterminable);
          expect(r.levelReasons, isNotEmpty);
        }
        if (r.level != ReadinessLevel.good) {
          expect(r.levelReasons, isNotEmpty, reason: 'seed $seed');
        }
      }
      expect(numbers, greaterThan(100));
    });
    test('toString nennt keine Werte', () {
      final r = computeReadiness(goodInputs(hrvRef: 15));
      expect(r.levelReasons.first.toString(), isNot(contains('15')));
    });
  });
}
