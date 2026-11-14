import '../profile/resting_hr_origin.dart' show RestingPosture;
import 'readiness_deviation.dart';

/// Ergebnis der Vorrangregel K-1 für einen Faktor.
class FactorEvaluation {
  const FactorEvaluation({
    required this.factor,
    required this.chosen,
    required this.others,
  });

  final ReadinessFactor factor;

  /// Die Reihe, die zählt (mit gültigem `z`), sonst null.
  final DeviationResult? chosen;

  /// Alle anderen betrachteten Reihen: erscheinen nur als Tatsache, nie in
  /// einer Zahl. Eine gesperrte Kamerareihe mit `z` ist hier enthalten.
  final List<DeviationResult> others;

  @override
  String toString() => 'FactorEvaluation($factor)';
}

int _postureRank(DeviationResult r) =>
    r.cameraSeries?.posture == RestingPosture.lying ? 0 : 1;

/// Vorrang je Faktor (docs/phase-2-3-rules.md Abschnitt 7, „Vorrang“): Hat
/// die Health-Connect-Reihe [healthConnect] heute ein gültiges `z`, zählt sie;
/// sonst die erste Kamerareihe mit gültigem `z`, wenn der Faktor für die Kamera
/// freigegeben ist ([cameraReleased], die Sperre selbst ist nicht hier). Nie
/// gemittelt. Mehrere Kamerareihen: liegend vor sitzend, dann die mit mehr
/// Referenzwerten, dann nach Hersteller und Modell (eigene Wahl, die Regel
/// sagt dazu nichts).
FactorEvaluation chooseFactor({
  required ReadinessFactor factor,
  required DeviationResult? healthConnect,
  required Iterable<DeviationResult> camera,
  required bool cameraReleased,
}) {
  final cams =
      [
        for (final c in camera)
          if (c.factor == factor && c.source == ReadinessSource.camera) c,
      ]..sort((a, b) {
        final byPosture = _postureRank(a).compareTo(_postureRank(b));
        if (byPosture != 0) return byPosture;
        final byRef = b.referenceCount.compareTo(a.referenceCount);
        if (byRef != 0) return byRef;
        final ka = a.cameraSeries!, kb = b.cameraSeries!;
        final byMaker = ka.manufacturer.compareTo(kb.manufacturer);
        return byMaker != 0 ? byMaker : ka.model.compareTo(kb.model);
      });
  DeviationResult? chosen;
  if (healthConnect != null && healthConnect.hasZ) {
    chosen = healthConnect;
  } else if (cameraReleased) {
    for (final c in cams) {
      if (c.hasZ) {
        chosen = c;
        break;
      }
    }
  }
  return FactorEvaluation(
    factor: factor,
    chosen: chosen,
    others: [
      if (healthConnect != null && !identical(healthConnect, chosen))
        healthConnect,
      for (final c in cams)
        if (!identical(c, chosen)) c,
    ],
  );
}
