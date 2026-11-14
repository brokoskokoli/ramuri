import '../ppg/validation_status.dart';

/// Markierung des Kamera-RMSSD auf der Seite Morgenwerte (K-1, PAR-171K und
/// Validierungssperre). Es gibt einen Stand für das Verfahren, keinen je
/// Haltung (K67); der Opt-in ist ein Schalter für beide Haltungen (E2).
enum MorningRmssdMark {
  /// Keine Markierung (Entwicklermodus: gilt als gültig, K62 Punkt 6).
  none,

  /// lnRMSSD bestanden, Opt-in aus: „experimentell, nicht eingeschaltet“.
  notEnabled,

  /// lnRMSSD bestanden, Opt-in an: „experimentell, mit einem Brustgurt
  /// verglichen (ein Handy)“.
  experimental,

  /// „eingeschränkt“ oder „nicht bestanden“: „ungenauer als erwartet“.
  inaccurate,

  /// Validierung nicht gelaufen: „noch nicht geprüft“.
  notChecked,
}

/// Was die Seite je Reihe zeigt.
class MorningTrendMarks {
  const MorningTrendMarks({
    required this.rmssd,
    required this.hrInaccurate,
    required this.optInVisible,
  });

  final MorningRmssdMark rmssd;

  /// Ruhepuls „nicht bestanden“: „ungenauer als erwartet“.
  final bool hrInaccurate;

  /// Opt-in-Schalter nur bei „bestanden“, nie im Entwicklermodus.
  final bool optInVisible;

  /// RMSSD wird gezeigt, geht aber in nichts ein (gesperrt, nicht
  /// eingeschaltet oder ungeprüft): gedämpft gezeichnet.
  bool get rmssdLocked =>
      rmssd == MorningRmssdMark.notEnabled ||
      rmssd == MorningRmssdMark.inaccurate ||
      rmssd == MorningRmssdMark.notChecked;
}

/// Markierungen aus dem Stand des Verfahrens, für beide Haltungen gleich (K67).
/// Im Entwicklermodus keine Markierung und kein Opt-in nötig; sonst zählt bei
/// „bestanden“ die Kamera-RMSSD nur mit [optIn].
MorningTrendMarks morningTrendMarks({
  required bool developerMode,
  required bool optIn,
  Map<ValidationQuantity, ValidationState> state = ppgValidationState,
}) {
  if (developerMode) {
    return const MorningTrendMarks(
      rmssd: MorningRmssdMark.none,
      hrInaccurate: false,
      optInVisible: false,
    );
  }
  final eff = state[ValidationQuantity.lnRmssdSupine];
  final rmssd = switch (eff) {
    ValidationState.passed =>
      optIn ? MorningRmssdMark.experimental : MorningRmssdMark.notEnabled,
    ValidationState.limited ||
    ValidationState.failed => MorningRmssdMark.inaccurate,
    _ => MorningRmssdMark.notChecked,
  };
  return MorningTrendMarks(
    rmssd: rmssd,
    hrInaccurate: state[ValidationQuantity.restingHr] == ValidationState.failed,
    optInVisible: eff == ValidationState.passed,
  );
}
