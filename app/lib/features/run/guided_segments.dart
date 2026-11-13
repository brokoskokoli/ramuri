import 'package:core/core.dart';

/// Abschnitte, die die Seite „Lauf vorbereiten“ zeigt und die Führung (WP24)
/// bekommt. Lockere Einheiten haben keinen eigenen Auf- oder Abwärmabschnitt
/// (PAR-119: Die ersten und letzten Minuten sind darin langsam und zählen zur
/// Dauer): ihre Minuten werden dem Hauptabschnitt zugeschlagen, damit die
/// Führung so lang dauert wie die Einheit. Hat eine Einheit gar keine
/// Abschnitte, gilt ein lockerer Abschnitt über ihre Dauer.
List<PlanSegment> guidedSegmentsOf(PlanUnit unit) {
  final plain =
      unit.kind == PlanUnitKind.easy || unit.kind == PlanUnitKind.long;
  if (!plain) {
    return unit.segments.isEmpty
        ? [PlanSegment(kind: PlanSegmentKind.easy, minutes: unit.minutes)]
        : unit.segments;
  }
  var extra = 0;
  final segments = <PlanSegment>[];
  for (final s in unit.segments) {
    if (s.kind == PlanSegmentKind.warmUp ||
        s.kind == PlanSegmentKind.coolDown) {
      extra += s.durationSeconds;
    } else {
      segments.add(s);
    }
  }
  if (segments.isEmpty) {
    return [PlanSegment(kind: PlanSegmentKind.easy, minutes: unit.minutes)];
  }
  if (extra == 0) return segments;
  final main = segments.first;
  final seconds = main.durationSeconds + extra;
  segments[0] = PlanSegment(
    kind: main.kind,
    minutes: (seconds / 60).round(),
    seconds: seconds,
    intensity: main.intensity,
  );
  return segments;
}
