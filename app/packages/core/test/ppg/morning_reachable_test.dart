import 'package:core/core.dart';
import 'package:test/test.dart';

void main() {
  Map<ValidationQuantity, ValidationState> only(
    ValidationQuantity q,
    ValidationState s,
  ) => {
    for (final k in ValidationQuantity.values) k: ValidationState.notChecked,
    q: s,
  };

  test('heutiger Stand: alles nicht geprüft, Verfahren camera-ppg v2', () {
    expect(ppgMethod, 'camera-ppg');
    expect(ppgMethodVersion, 2);
    expect(ppgValidationState.keys, ValidationQuantity.values);
    expect(
      ppgValidationState.values.every((s) => s == ValidationState.notChecked),
      isTrue,
    );
    expect(morningMeasurementReachable(developerMode: false), isFalse);
    expect(morningMeasurementReachable(developerMode: true), isTrue);
  });

  for (final s in ValidationState.values) {
    for (final dev in [false, true]) {
      test('lnRMSSD liegend $s, Entwicklermodus $dev', () {
        final r = morningMeasurementReachable(
          developerMode: dev,
          state: only(ValidationQuantity.lnRmssdSupine, s),
        );
        expect(r, dev || s == ValidationState.passed);
      });
    }
  }

  test(
    'andere Größen allein schalten nicht frei (auch Ruhepuls bestanden)',
    () {
      for (final q in [ValidationQuantity.restingHr]) {
        expect(
          morningMeasurementReachable(
            developerMode: false,
            state: only(q, ValidationState.passed),
          ),
          isFalse,
          reason: '$q',
        );
      }
    },
  );

  test(
    'Validierungsstand: eine Größe je Verfahren, keine je Haltung (K67)',
    () {
      expect(ValidationQuantity.values, [
        ValidationQuantity.restingHr,
        ValidationQuantity.lnRmssdSupine,
      ]);
      expect(
        ppgValidationState.keys.toSet(),
        ValidationQuantity.values.toSet(),
      );
    },
  );
}
