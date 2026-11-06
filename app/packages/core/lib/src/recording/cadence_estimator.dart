/// Schrittfrequenz aus den Zeitpunkten einzelner Schritte (FR-0202).
///
/// Gleitendes Fenster: Aus den Schritten der letzten [window] ergibt sich
/// `(n - 1) / Spanne * 60` Schritte je Minute. Bei weniger als [minSteps]
/// Schritten im Fenster gibt es keinen Wert (kein Raten, kein Auffüllen).
/// Anzeigewert, kein Messergebnis; Fenster und Mindestzahl sind
/// Vorschläge (Heuristik) und stehen in keinem PAR.
class CadenceEstimator {
  CadenceEstimator({this.window = defaultWindow, this.minSteps = 3});

  static const Duration defaultWindow = Duration(seconds: 10);

  /// Länge des Fensters; ältere Schritte zählen nicht mehr.
  final Duration window;

  /// Mindestzahl Schritte im Fenster für einen Wert.
  final int minSteps;

  final List<DateTime> _steps = [];

  /// Nimmt einen Schritt auf und liefert die Schrittfrequenz, sofern es eine
  /// gibt. Ein Schritt, der nicht nach dem letzten liegt, wird ignoriert.
  double? add(DateTime step) {
    if (_steps.isNotEmpty && !step.isAfter(_steps.last)) return null;
    _steps.add(step);
    _steps.removeWhere((s) => step.difference(s) > window);
    return value;
  }

  /// Frequenz aus den Schritten im Fenster; `null`, wenn zu wenige.
  double? get value {
    if (_steps.length < minSteps) return null;
    final span = _steps.last.difference(_steps.first).inMicroseconds;
    if (span <= 0) return null;
    return (_steps.length - 1) * 60 * 1e6 / span;
  }
}
