import 'package:core/core.dart';

/// Abschnitte, die die Seite „Lauf vorbereiten“ zeigt und die Führung (WP24)
/// bekommt. Lockere Einheiten haben keinen eigenen Auf- oder Abwärmabschnitt
/// (PAR-119: Die ersten und letzten Minuten sind darin langsam und zählen zur
/// Dauer); solche Abschnitte fallen dort weg. Hat eine Einheit gar keine
/// Abschnitte, gilt ein lockerer Abschnitt über ihre Dauer.
List<PlanSegment> guidedSegmentsOf(PlanUnit unit) {
  final plain =
      unit.kind == PlanUnitKind.easy || unit.kind == PlanUnitKind.long;
  final segments = [
    for (final s in unit.segments)
      if (!plain ||
          (s.kind != PlanSegmentKind.warmUp &&
              s.kind != PlanSegmentKind.coolDown))
        s,
  ];
  if (segments.isNotEmpty) return segments;
  return [PlanSegment(kind: PlanSegmentKind.easy, minutes: unit.minutes)];
}
