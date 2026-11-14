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

/// Ein Eintrag der Abschnittsliste auf „Lauf vorbereiten“: ein Abschnitt
/// ([repeat] 1) oder eine [repeat]-mal wiederholte Folge gleicher Abschnitte.
class SegmentGroup {
  const SegmentGroup(this.segments, this.repeat);

  /// Der Abschnitt bzw. die Folge, die sich wiederholt.
  final List<PlanSegment> segments;
  final int repeat;

  /// Gesamtdauer aller Wiederholungen in Sekunden.
  int get durationSeconds =>
      repeat * segments.fold<int>(0, (sum, s) => sum + s.durationSeconds);
}

bool _sameIntensity(PlanTargetIntensity? a, PlanTargetIntensity? b) {
  if (a == null || b == null) return a == b;
  return a.rpeMin == b.rpeMin &&
      a.rpeMax == b.rpeMax &&
      a.paceFastSecondsPerKm == b.paceFastSecondsPerKm &&
      a.paceSlowSecondsPerKm == b.paceSlowSecondsPerKm &&
      a.basisCode == b.basisCode &&
      a.hrMinBpm == b.hrMinBpm &&
      a.hrMaxBpm == b.hrMaxBpm &&
      a.estimated == b.estimated &&
      a.maxHrEstimated == b.maxHrEstimated &&
      a.paceIsLimit == b.paceIsLimit;
}

bool _sameSegment(PlanSegment a, PlanSegment b) =>
    a.kind == b.kind &&
    a.durationSeconds == b.durationSeconds &&
    _sameIntensity(a.intensity, b.intensity);

bool _edge(PlanSegment s) =>
    s.kind == PlanSegmentKind.warmUp || s.kind == PlanSegmentKind.coolDown;

/// Fasst unmittelbar wiederholte gleiche Abschnittsfolgen zusammen (etwa
/// 8× Laufen 1 min, Gehen 2 min). Aufwärmen und Abwärmen bleiben einzeln;
/// die Reihenfolge und die Gesamtdauer ändern sich nicht. Gewählt wird an
/// jeder Stelle die Folge, die die meisten Abschnitte abdeckt (bei Gleichstand
/// die kürzere); eine Folge zählt ab zwei Wiederholungen.
List<SegmentGroup> groupSegments(List<PlanSegment> segments) {
  final out = <SegmentGroup>[];
  var i = 0;
  while (i < segments.length) {
    var bestLen = 1;
    var bestRepeat = 1;
    if (!_edge(segments[i])) {
      for (var len = 1; i + 2 * len <= segments.length; len++) {
        final block = segments.sublist(i, i + len);
        if (block.any(_edge)) break;
        var r = 1;
        while (i + (r + 1) * len <= segments.length &&
            [
              for (var k = 0; k < len; k++)
                _sameSegment(block[k], segments[i + r * len + k]),
            ].every((same) => same)) {
          r++;
        }
        if (r >= 2 && r * len > bestRepeat * bestLen) {
          bestLen = len;
          bestRepeat = r;
        }
      }
    }
    out.add(SegmentGroup(segments.sublist(i, i + bestLen), bestRepeat));
    i += bestLen * bestRepeat;
  }
  return out;
}
