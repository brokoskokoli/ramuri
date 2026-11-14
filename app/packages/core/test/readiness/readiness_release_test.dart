import 'package:core/core.dart';
import 'package:test/test.dart';

import 'readiness_helpers.dart';

Map<ValidationQuantity, ValidationState> st({
  ValidationState hr = ValidationState.passed,
  ValidationState supine = ValidationState.passed,
  ValidationState sitting = ValidationState.passed,
}) => {
  ValidationQuantity.restingHr: hr,
  ValidationQuantity.lnRmssdSupine: supine,
  ValidationQuantity.lnRmssdSitting: sitting,
};

List<MorningMeasurement> series(
  RestingPosture posture, {
  bool before = false,
}) => [
  for (var i = 0; i < 29; i++)
    morning(
      dayIdx: i,
      hr: 55 + (i % 5) * 2,
      rmssd: 40 + (i % 4) * 3.0,
      posture: posture,
      before: before,
    ),
];

/// Wahl je Faktor für die Kamera allein (kein Health Connect).
DeviationResult? chosen(
  ReadinessFactor f,
  List<MorningMeasurement> all,
  CameraRelease release,
) {
  final cam = cameraDeviations(all, today: todayKey);
  return chooseFactor(
    factor: f,
    healthConnect: null,
    camera: cam,
    cameraReleased: true,
    seriesReleased: release.isReleased,
  ).chosen;
}

void main() {
  const states = ValidationState.values;
  const P = ValidationState.passed;

  group(
    'Sperre: Matrix Stand x Entwicklermodus x Opt-in x Faktor x Haltung',
    () {
      for (final supine in states) {
        for (final posture in RestingPosture.values) {
          for (final dev in [false, true]) {
            for (final optIn in [false, true]) {
              final rel = CameraRelease(
                developerMode: dev,
                rmssdOptIn: optIn,
                state: st(supine: supine, hr: supine),
              );
              final name =
                  '${supine.name} ${posture.name} dev=$dev optIn=$optIn';
              test('HRV $name', () {
                final expected = dev || (supine == P && optIn);
                final r = rel.forFactor(ReadinessFactor.hrv, posture);
                expect(r.released, expected);
                if (dev) expect(r.mark, MorningRmssdMark.none);
                final z = chosen(ReadinessFactor.hrv, series(posture), rel);
                expect(z != null, expected);
              });
              test('Ruhepuls $name', () {
                final expected =
                    dev || supine == P || supine == ValidationState.limited;
                final r = rel.forFactor(
                  ReadinessFactor.restingHeartRate,
                  posture,
                );
                expect(r.released, expected);
                if (dev) expect(r.mark, MorningRmssdMark.none);
                if (!dev && supine == ValidationState.failed) {
                  expect(r.mark, MorningRmssdMark.inaccurate);
                }
                final z = chosen(
                  ReadinessFactor.restingHeartRate,
                  series(posture),
                  rel,
                );
                expect(z != null, expected);
              });
            }
          }
        }
      }

      test('Ruhepuls und RMSSD haben getrennte Stände', () {
        // Ruhepuls bestanden, lnRMSSD nicht geprüft.
        final rel = CameraRelease(
          developerMode: false,
          rmssdOptIn: true,
          state: st(supine: ValidationState.notChecked),
        );
        expect(
          rel
              .forFactor(ReadinessFactor.restingHeartRate, RestingPosture.lying)
              .released,
          isTrue,
        );
        expect(
          rel.forFactor(ReadinessFactor.hrv, RestingPosture.lying).released,
          isFalse,
        );
      });

      test(
        'sitzend gesperrt, wenn im Sitzen eingeschränkt oder nicht bestanden',
        () {
          for (final s in [ValidationState.limited, ValidationState.failed]) {
            final rel = CameraRelease(
              developerMode: false,
              rmssdOptIn: true,
              state: st(sitting: s),
            );
            expect(
              rel
                  .forFactor(ReadinessFactor.hrv, RestingPosture.sitting)
                  .released,
              isFalse,
            );
            expect(
              rel.forFactor(ReadinessFactor.hrv, RestingPosture.lying).released,
              isTrue,
            );
          }
        },
      );

      test('sitzend mit Opt-in: "liegend verglichen", liegend: Brustgurt', () {
        final rel = CameraRelease(
          developerMode: false,
          rmssdOptIn: true,
          state: st(),
        );
        expect(
          rel.forFactor(ReadinessFactor.hrv, RestingPosture.sitting).mark,
          MorningRmssdMark.optInSitting,
        );
        expect(
          rel.forFactor(ReadinessFactor.hrv, RestingPosture.lying).mark,
          MorningRmssdMark.optIn,
        );
      });

      test('gesperrte liegende Reihe: nur die freigegebene sitzende zählt nicht Ersatz', () {
        // sitzend freigegeben, liegend gesperrt gibt es nicht (gleicher Stand);
        // umgekehrt: sitzend gesperrt, liegend zählt, auch wenn sitzend zuerst käme.
        final rel = CameraRelease(
          developerMode: false,
          rmssdOptIn: true,
          state: st(sitting: ValidationState.failed),
        );
        final all = [...series(RestingPosture.sitting)];
        expect(chosen(ReadinessFactor.hrv, all, rel), isNull);
        expect(chosen(ReadinessFactor.restingHeartRate, all, rel), isNotNull);
      });

      test('gesperrte Reihe bleibt als Tatsache in others', () {
        final rel = CameraRelease(
          developerMode: false,
          rmssdOptIn: false,
          state: st(),
        );
        final e = chooseFactor(
          factor: ReadinessFactor.hrv,
          healthConnect: null,
          camera: cameraDeviations(
            series(RestingPosture.lying),
            today: todayKey,
          ),
          cameraReleased: true,
          seriesReleased: rel.isReleased,
        );
        expect(e.chosen, isNull);
        expect(e.others.length, 1);
      });

      test('Health Connect mit z bleibt vorrangig, Sperre ändert nichts', () {
        final hc = DeviationResult(
          factor: ReadinessFactor.hrv,
          source: ReadinessSource.healthConnect,
          origin: 'a',
          z: -1,
        );
        for (final dev in [false, true]) {
          final e = chooseFactor(
            factor: ReadinessFactor.hrv,
            healthConnect: hc,
            camera: cameraDeviations(
              series(RestingPosture.lying),
              today: todayKey,
            ),
            cameraReleased: true,
            seriesReleased: CameraRelease(
              developerMode: dev,
              rmssdOptIn: true,
              state: st(),
            ).isReleased,
          );
          expect(identical(e.chosen, hc), isTrue);
        }
      });
    },
  );

  group('Entwicklermodus = bestanden mit Opt-in', () {
    for (final supine in states) {
      for (final posture in RestingPosture.values) {
        test(
          '${supine.name} ${posture.name}: gleiche Eingaben, gleiche Ausgabe',
          () {
            final dev = CameraRelease(
              developerMode: true,
              rmssdOptIn: false,
              state: st(supine: supine, hr: supine, sitting: supine),
            );
            final ref = CameraRelease(
              developerMode: false,
              rmssdOptIn: true,
              state: st(),
            );
            for (final f in ReadinessFactor.values) {
              final a = chosen(f, series(posture, before: true), dev);
              final b = chosen(f, series(posture), ref);
              expect(a, isNotNull);
              expect(a!.z, b!.z);
              expect(a.cameraSeries!.posture, b.cameraSeries!.posture);
              expect(a.referenceCount, b.referenceCount);
              expect(a.windowCount, b.windowCount);
              expect(a.fewMeasurements, b.fewMeasurements);
              expect(dev.forFactor(f, posture).mark, MorningRmssdMark.none);
            }
          },
        );
      }
    }

    test('Merkmal "vor der Validierung gemessen" ändert nichts', () {
      for (final dev in [false, true]) {
        final rel = CameraRelease(
          developerMode: dev,
          rmssdOptIn: true,
          state: st(),
        );
        for (final f in ReadinessFactor.values) {
          final a = chosen(f, series(RestingPosture.lying, before: true), rel);
          final b = chosen(f, series(RestingPosture.lying), rel);
          expect(a!.z, b!.z);
        }
      }
    });
  });

  test('Eigenschaft: eine Markierung ändert nie einen Faktor', () {
    // Gleiche Freigabe, verschiedene Markierung (none/optIn/optInSitting):
    // gleiches z. Ruhepuls: "bestanden" und "eingeschränkt" gleich.
    final zs = <double>{};
    for (final rel in [
      CameraRelease(developerMode: true, rmssdOptIn: false, state: st()),
      CameraRelease(developerMode: false, rmssdOptIn: true, state: st()),
    ]) {
      zs.add(
        chosen(ReadinessFactor.hrv, series(RestingPosture.lying), rel)!.z!,
      );
    }
    expect(zs.length, 1);
    final a = chosen(
      ReadinessFactor.restingHeartRate,
      series(RestingPosture.lying),
      CameraRelease(
        developerMode: false,
        rmssdOptIn: false,
        state: st(hr: ValidationState.limited),
      ),
    )!;
    final b = chosen(
      ReadinessFactor.restingHeartRate,
      series(RestingPosture.lying),
      CameraRelease(developerMode: false, rmssdOptIn: false, state: st()),
    )!;
    expect(a.z, b.z);
    // Ohne Freigabe entsteht nie ein Faktor, egal welche Markierung.
    for (final s in [
      ValidationState.notChecked,
      ValidationState.limited,
      ValidationState.failed,
    ]) {
      for (final optIn in [false, true]) {
        expect(
          chosen(
            ReadinessFactor.hrv,
            series(RestingPosture.lying),
            CameraRelease(
              developerMode: false,
              rmssdOptIn: optIn,
              state: st(supine: s),
            ),
          ),
          isNull,
        );
      }
    }
  });
}
