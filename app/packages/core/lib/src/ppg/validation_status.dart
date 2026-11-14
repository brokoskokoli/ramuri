import 'ppg_parameters.dart';

/// Stand der Validierung einer Größe des Verfahrens (WP33, K62 Punkt 1).
enum ValidationState { notChecked, passed, limited, failed }

/// Größen, die die Validierung einzeln bewertet.
enum ValidationQuantity { restingHr, lnRmssdSupine, lnRmssdSitting }

/// Validierungsstand von `camera-ppg` in [ppgMethodVersion] (E7c: am Verfahren,
/// nicht am Gerät). Versioniert wie das Verfahren: Ändert sich der Algorithmus,
/// beginnt die Validierung neu. Nur WP36 ändert die Werte, nach dem Ergebnis
/// der Validierungsmessung und mit Freigabe des Maintainers.
const Map<ValidationQuantity, ValidationState> ppgValidationState = {
  ValidationQuantity.restingHr: ValidationState.notChecked,
  ValidationQuantity.lnRmssdSupine: ValidationState.notChecked,
  ValidationQuantity.lnRmssdSitting: ValidationState.notChecked,
};

/// Ist die Morgenmessung erreichbar (FR-0217, K62 Punkt 1)? Im Entwicklermodus
/// immer; sonst für alle erst, wenn lnRMSSD liegend „bestanden“ ist. Ein
/// gemischtes Ergebnis (etwa Ruhepuls bestanden, lnRMSSD nicht) schaltet nicht
/// frei.
bool morningMeasurementReachable({
  required bool developerMode,
  Map<ValidationQuantity, ValidationState> state = ppgValidationState,
}) =>
    developerMode ||
    state[ValidationQuantity.lnRmssdSupine] == ValidationState.passed;
