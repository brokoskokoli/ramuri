import 'measurement.dart';

/// Strecke zwischen zwei aufeinanderfolgenden akzeptierten Punkten desselben
/// Abschnitts. Gemeinsame Grundlage von Tempo und Bewegungszeit.
class MotionSegment {
  const MotionSegment({
    required this.start,
    required this.end,
    required this.meters,
    required this.isGap,
  });

  final DateTime start;
  final DateTime end;

  /// Gezählte Strecke; bei einer Lücke 0.
  final double meters;

  /// Abstand über PAR-004: Zeit und Strecke zählen nicht für das Tempo.
  final bool isGap;

  double get seconds => end.difference(start).inMicroseconds / 1e6;
}

/// Bildet aus akzeptierten Punkten Segmente. Ein neuer Abschnitt (Start,
/// Fortsetzen nach manueller Pause) beginnt ohne Vorgänger.
class SegmentBuilder {
  SegmentBuilder(this.gapMaxDuration);

  final Duration gapMaxDuration;
  DateTime? _previous;

  /// Nimmt einen akzeptierten Punkt mit seiner gezählten Strecke auf.
  MotionSegment? add(RawPosition p, double countedMeters) {
    final before = _previous;
    _previous = p.time;
    if (before == null) return null;
    final gap = p.time.difference(before) > gapMaxDuration;
    return MotionSegment(
      start: before,
      end: p.time,
      meters: gap ? 0 : countedMeters,
      isGap: gap,
    );
  }

  /// Abschnittsgrenze (manuelle Pause oder Fortsetzen).
  void reset() => _previous = null;
}
