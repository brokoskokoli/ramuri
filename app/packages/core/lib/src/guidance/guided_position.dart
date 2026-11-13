import '../plan/plan_unit.dart';
import 'guidance_parameters.dart';

/// Stand in der Abschnittsfolge einer geführten Einheit (FR-0033). Reine
/// Funktion von (Abschnitte, Bewegungszeit), ohne eigenen Zustand
/// (Festlegung 2): Pause und Autopause halten die Bewegungszeit an, ein
/// Wiederanlauf setzt am gespeicherten Stand fort.
class GuidedPosition {
  const GuidedPosition({
    required this.index,
    required this.segment,
    required this.next,
    required this.elapsedInSegment,
    required this.remaining,
    required this.finished,
  });

  /// Index des aktuellen Abschnitts in der übergebenen Liste; bei [finished]
  /// die Länge der Liste.
  final int index;

  /// Aktueller Abschnitt; `null`, wenn [finished].
  final PlanSegment? segment;

  /// Nächster Abschnitt mit Dauer > 0, sonst `null`.
  final PlanSegment? next;

  /// Zeit im aktuellen Abschnitt.
  final Duration elapsedInSegment;

  /// Restzeit des aktuellen Abschnitts (Festlegung 1); bei [finished] null-Dauer.
  final Duration remaining;

  /// Alle Abschnitte sind durchlaufen (oder es gibt keinen mit Dauer).
  final bool finished;

  /// Ziel des aktuellen Abschnitts.
  PlanTargetIntensity? get target => segment?.intensity;
}

/// Stand bei [movingTime] (negativ zählt als null). Abschnitte ohne Dauer
/// werden übersprungen.
GuidedPosition guidedPosition(List<PlanSegment> segments, Duration movingTime) {
  final t = movingTime.isNegative ? Duration.zero : movingTime;
  var start = Duration.zero;
  for (var i = 0; i < segments.length; i++) {
    final len = Duration(seconds: segments[i].durationSeconds);
    if (len <= Duration.zero) continue;
    final end = start + len;
    if (t < end) {
      PlanSegment? next;
      for (var j = i + 1; j < segments.length; j++) {
        if (segments[j].durationSeconds > 0) {
          next = segments[j];
          break;
        }
      }
      return GuidedPosition(
        index: i,
        segment: segments[i],
        next: next,
        elapsedInSegment: t - start,
        remaining: end - t,
        finished: false,
      );
    }
    start = end;
  }
  return GuidedPosition(
    index: segments.length,
    segment: null,
    next: null,
    elapsedInSegment: Duration.zero,
    remaining: Duration.zero,
    finished: true,
  );
}

/// Darf im Abschnitt [pos] bei Bewegungszeit [movingTime] ein Pulshinweis
/// kommen (PAR-107)? Abschnitt mindestens 4 min, erst nach 3 min darin, nur bis
/// Minute 60; ob eine obere Pulsgrenze gesetzt ist, prüft der Aufrufer. Eine
/// Quelle für Ansage und Anzeige.
bool pulseHintAllowed(GuidedPosition pos, Duration movingTime) =>
    !pos.finished &&
    Duration(seconds: pos.segment!.durationSeconds) >=
        pulseAnnounceMinSegmentLength &&
    pos.elapsedInSegment >= pulseAnnounceMinTimeInSegment &&
    movingTime < pulseAnnounceMaxMovingTime;
