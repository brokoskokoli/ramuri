import '../morning/morning_marks.dart';
import '../ppg/validation_status.dart';
import '../profile/resting_hr_origin.dart' show RestingPosture;
import 'readiness_deviation.dart';

/// Freigabe eines Kamerafaktors für die Readiness samt Markierung.
class CameraFactorRelease {
  const CameraFactorRelease({required this.released, required this.mark});

  /// Darf die Kamerareihe als Faktor zählen?
  final bool released;

  /// Markierung für Wert und Tatsache (dieselbe Quelle wie auf der Seite
  /// Morgenwerte, [morningTrendMarks]). Ändert nie einen Faktor.
  final MorningRmssdMark mark;
}

/// Validierungssperre für die Readiness (docs/phase-2-3-rules.md Abschnitt 7,
/// PAR-171K, K65). Die Regel selbst steht in [morningTrendMarks]; hier wird
/// nur daraus abgeleitet, ob ein Faktor zählt.
///
/// Entwicklermodus: Ruhepuls und RMSSD immer freigegeben, ohne Markierung, ohne
/// Opt-in; das Merkmal „vor der Validierung gemessen“ spielt keine Rolle.
/// Sonst: RMSSD nur bei Stand „bestanden“ (liegend, sitzend gilt er mit,
/// solange sitzend nicht eingeschränkt/nicht bestanden) und eingeschaltetem
/// Opt-in; Ruhepuls bei „nicht geprüft“, „bestanden“ und „eingeschränkt“, nur bei
/// „nicht bestanden“ gesperrt (Markierung „ungenauer als erwartet“).
class CameraRelease {
  const CameraRelease({
    required this.developerMode,
    required this.rmssdOptIn,
    this.state = ppgValidationState,
  });

  final bool developerMode;
  final bool rmssdOptIn;
  final Map<ValidationQuantity, ValidationState> state;

  /// Gehen Kamerawerte überhaupt ein, auch als Tatsache (K62 Punkt 1)? Im
  /// Entwicklermodus immer, sonst erst bei freigeschalteter Morgenmessung.
  bool get cameraValuesAllowed =>
      developerMode ||
      morningMeasurementReachable(developerMode: false, state: state);

  CameraFactorRelease forFactor(
    ReadinessFactor factor,
    RestingPosture posture,
  ) {
    // Fail-closed (K62 Punkt 1, WP34 Teil B): Ohne Entwicklermodus zählen
    // Kamerawerte erst, wenn die Morgenmessung freigeschaltet ist; sonst
    // blieben im Entwicklermodus gespeicherte Messungen wirksam. Weder
    // Faktor noch Tatsache.
    if (!cameraValuesAllowed) {
      return const CameraFactorRelease(
        released: false,
        mark: MorningRmssdMark.notChecked,
      );
    }
    final marks = morningTrendMarks(
      developerMode: developerMode,
      posture: posture,
      optIn: rmssdOptIn,
      state: state,
    );
    switch (factor) {
      case ReadinessFactor.hrv:
        final released = switch (marks.rmssd) {
          MorningRmssdMark.none ||
          MorningRmssdMark.optIn ||
          MorningRmssdMark.optInSitting => true,
          _ => false,
        };
        return CameraFactorRelease(released: released, mark: marks.rmssd);
      case ReadinessFactor.restingHeartRate:
        if (developerMode) {
          return const CameraFactorRelease(
            released: true,
            mark: MorningRmssdMark.none,
          );
        }
        final failed =
            state[ValidationQuantity.restingHr] == ValidationState.failed;
        return CameraFactorRelease(
          released: !failed,
          mark: failed ? MorningRmssdMark.inaccurate : MorningRmssdMark.none,
        );
    }
  }

  /// Zählt die Kamerareihe [r] (Faktor und Haltung der Reihe)? Reihen anderer
  /// Herkunft sind nicht Sache der Sperre.
  bool isReleased(DeviationResult r) {
    final s = r.cameraSeries;
    if (r.source != ReadinessSource.camera) return true;
    if (s == null) return false;
    return forFactor(r.factor, s.posture).released;
  }
}
