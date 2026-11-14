import '../preprocessing/gap_moving_time.dart'
    show overlapDuration, positionLossSpans;
import '../preprocessing/measurement.dart';
import '../preprocessing/movement_time_processor.dart' show TimeSpan;
import '../preprocessing/motion_segments.dart';
import '../preprocessing/run_preprocessor.dart';
import '../recording/belt_track.dart';
import 'run_detail.dart' show RoutePoint;

/// Kennung und Version der Kilometerrechnung (NFR-0001, NFR-0005).
const String kilometerSplitsMethod = 'kilometer-splits';
const int kilometerSplitsMethodVersion = 1;

/// Länge eines Abschnitts in Metern (FR-0211, NFR-0006). Die internationale
/// Meile ist per Definition 1609,344 m.
const double kilometerMeters = 1000;
const double mileMeters = 1609.344;

/// Rundungsspielraum für Summen von Segmentlängen (Meter).
const double _lengthEpsilonMeters = 1e-6;

/// Ein Abschnitt (voller Kilometer bzw. volle Meile, oder der angebrochene
/// letzte) der Kilometertabelle (FR-0211).
class KilometerSplit {
  const KilometerSplit({
    required this.index,
    required this.lengthMeters,
    required this.isPartial,
    required this.time,
    required this.positionGapTime,
    this.paceSecondsPerKm,
    this.heartRateAverageBpm,
  });

  /// Ab 1; der angebrochene letzte Abschnitt trägt die nächste Nummer.
  final int index;

  /// Volle Abschnitte: die Einheit; der angebrochene: seine Restlänge.
  final double lengthMeters;
  final bool isPartial;

  /// Bewegungszeit des Abschnitts. Die Summe aller Abschnitte ist genau die
  /// Bewegungszeit des Laufs.
  final Duration time;

  /// Bewegungszeit des Abschnitts, die in einer Positionslücke lag.
  final Duration positionGapTime;

  /// Kennzeichen GPS-Lücke.
  bool get hasPositionGap => positionGapTime > Duration.zero;

  /// Pace in s/km aus Zeit ohne Lückenzeit (K20) und Länge; `null`, wenn
  /// nichts übrig bleibt. In Meilen rechnet die Oberfläche um (wie sonst).
  final double? paceSecondsPerKm;

  /// Mittel der akzeptierten Pulswerte in der Bewegungszeit des Abschnitts;
  /// `null` ohne Wert (nie 0).
  final double? heartRateAverageBpm;
}

/// Kilometermarke auf der Route: Ende des vollen Abschnitts [index].
class KilometerMark {
  const KilometerMark({
    required this.index,
    required this.position,
    required this.time,
  });
  final int index;
  final RoutePoint position;
  final DateTime time;
}

/// Kilometerwerte eines Laufs (FR-0211).
class KilometerSplits {
  KilometerSplits({
    required this.unitMeters,
    required List<KilometerSplit> splits,
    required List<KilometerMark> marks,
    required this.ascentMeters,
    required this.descentMeters,
  }) : splits = List.unmodifiable(splits),
       marks = List.unmodifiable(marks);

  String get method => kilometerSplitsMethod;
  int get methodVersion => kilometerSplitsMethodVersion;

  final double unitMeters;

  /// Leer, wenn der Lauf keine gezählte Strecke hat.
  final List<KilometerSplit> splits;

  /// Eine Marke je voll gelaufenem Abschnitt, auch am Ende eines genau vollen
  /// letzten Abschnitts.
  final List<KilometerMark> marks;

  /// Anstieg und Gefälle in Metern aus dem Höhenprofil (PAR-012); `null` ohne
  /// Höhendaten.
  final double? ascentMeters;
  final double? descentMeters;
}

/// Teilt die Bewegungsstrecke eines Laufs nach der Vorverarbeitung in Abschnitte
/// von [unitMeters] ([kilometerMeters] oder [mileMeters]).
///
/// Grenzen liegen dort, wo die gezählte Strecke ein Vielfaches erreicht
/// (linear innerhalb des Segments zwischen zwei akzeptierten Punkten). Die Zeit
/// eines Abschnitts ist der Zuwachs der Bewegungszeit (ohne Pausen) zwischen
/// seinen Grenzen. Bewegungszeit vor der ersten und nach der letzten Grenze und
/// in Lücken ohne Strecke fällt in den Abschnitt, in dem sie liegt; die Summe
/// ist deshalb genau die Bewegungszeit. Ein Rest unter einer Einheit ist der
/// angebrochene letzte Abschnitt mit seiner Länge. Liegt das Tempo eines
/// Abschnitts unter `standstillBelow` (PAR-014), ist seine Pace `null`.
KilometerSplits computeKilometerSplits(
  RunPreprocessing pre, {
  double unitMeters = kilometerMeters,
  BeltTrack? belt,
}) {
  assert(unitMeters > 0);
  if (belt != null) return computeBeltSplits(pre, belt, unitMeters: unitMeters);
  final moving = pre.movement.movingIntervals;
  final totalMicros = pre.movement.movingTime.inMicroseconds;

  // Grenzen: Zeit und Ort, an denen k * unit erreicht wird.
  final points = <DateTime, RawPosition>{
    for (final p in pre.position.acceptedPoints) p.time: p,
  };
  final boundaries = <({DateTime time, RoutePoint? position})>[];
  var cumulative = 0.0;
  for (final MotionSegment s in pre.pace.segments) {
    if (s.isGap || !(s.meters > 0)) continue;
    while ((boundaries.length + 1) * unitMeters <=
        cumulative + s.meters + _lengthEpsilonMeters) {
      final target = (boundaries.length + 1) * unitMeters;
      final f = ((target - cumulative) / s.meters).clamp(0.0, 1.0);
      final at = s.start.add(
        Duration(
          microseconds: (s.end.difference(s.start).inMicroseconds * f).round(),
        ),
      );
      boundaries.add((time: at, position: _between(points, s, f)));
    }
    cumulative += s.meters;
  }
  final restMeters = cumulative - boundaries.length * unitMeters;
  final hasPartial = restMeters > _lengthEpsilonMeters;
  if (boundaries.isEmpty && !hasPartial) {
    return KilometerSplits(
      unitMeters: unitMeters,
      splits: const [],
      marks: const [],
      ascentMeters: pre.altitude.ascentMeters,
      descentMeters: pre.altitude.descentMeters,
    );
  }

  // Fenster [von, bis) je Abschnitt; das letzte reicht bis zum Ende des Laufs.
  final count = boundaries.length + (hasPartial ? 1 : 0);
  final windows = <({DateTime? from, DateTime? to})>[
    for (var i = 0; i < count; i++)
      (
        from: i == 0 ? null : boundaries[i - 1].time,
        to: i < boundaries.length && i < count - 1 ? boundaries[i].time : null,
      ),
  ];

  int movingMicrosUntil(DateTime? t) {
    if (t == null) return totalMicros;
    var sum = 0;
    for (final m in moving) {
      if (!m.start.isBefore(t)) break;
      final end = m.end.isAfter(t) ? t : m.end;
      sum += end.difference(m.start).inMicroseconds;
    }
    return sum;
  }

  List<TimeSpan> clipped(({DateTime? from, DateTime? to}) w) => [
    for (final m in moving)
      if ((w.to == null || m.start.isBefore(w.to!)) &&
          (w.from == null || m.end.isAfter(w.from!)))
        TimeSpan(
          start: w.from != null && w.from!.isAfter(m.start) ? w.from! : m.start,
          end: w.to != null && w.to!.isBefore(m.end) ? w.to! : m.end,
        ),
  ];

  bool inMoving(DateTime t) {
    for (final m in moving) {
      if (!t.isBefore(m.start) && !t.isAfter(m.end)) return true;
    }
    return false;
  }

  final gapSpans = positionLossSpans(pre);
  final heart = pre.heartRate.acceptedValues;

  final splits = <KilometerSplit>[];
  var previousMicros = 0;
  for (var i = 0; i < count; i++) {
    final w = windows[i];
    final untilMicros = movingMicrosUntil(w.to);
    final time = Duration(microseconds: untilMicros - previousMicros);
    previousMicros = untilMicros;
    final gap = overlapDuration(clipped(w), gapSpans);
    final partial = hasPartial && i == count - 1;
    final length = partial ? restMeters : unitMeters;

    var sum = 0;
    var n = 0;
    for (final h in heart) {
      final t = h.time;
      if (w.from != null && t.isBefore(w.from!)) continue;
      if (w.to != null && !t.isBefore(w.to!)) continue;
      if (!inMoving(t)) continue;
      sum += h.bpm;
      n++;
    }
    final paceTime = time - gap;
    // OQ-0076: Ein Abschnitt unter der Stillstandsgrenze (PAR-014) hat keine
    // Pace, meist der kurze Rest; Länge und Zeit bleiben. Tempobasis wie die
    // Pace (ohne Lückenzeit). Genau die Grenze gilt noch als Bewegung.
    final speed = paceTime > Duration.zero
        ? length / (paceTime.inMicroseconds / 1e6)
        : null;
    splits.add(
      KilometerSplit(
        index: i + 1,
        lengthMeters: length,
        isPartial: partial,
        time: time,
        positionGapTime: gap,
        paceSecondsPerKm:
            speed == null || speed < pre.parameters.standstillBelow
            ? null
            : paceTime.inMicroseconds / 1e6 / (length / 1000),
        heartRateAverageBpm: n == 0 ? null : sum / n,
      ),
    );
  }

  return KilometerSplits(
    unitMeters: unitMeters,
    splits: splits,
    marks: [
      for (var i = 0; i < boundaries.length; i++)
        if (boundaries[i].position != null)
          KilometerMark(
            index: i + 1,
            position: boundaries[i].position!,
            time: boundaries[i].time,
          ),
    ],
    ascentMeters: pre.altitude.ascentMeters,
    descentMeters: pre.altitude.descentMeters,
  );
}

/// Abschnitte eines Bandlaufs (FR-0196, K57) aus dem Bandverlauf statt aus
/// Positionen: die Grenzen liegen dort, wo die eingestellte Geschwindigkeit,
/// über die Bewegungszeit summiert, ein Vielfaches von [unitMeters] erreicht.
/// Zeit eines Abschnitts ist seine Bewegungszeit (Stillstand und Pausen zählen
/// nicht), die Summe ist die Bewegungszeit des Bandes. Keine Lücken, keine
/// Marken, kein Anstieg (die Höhe ist unbekannt). Puls: Mittel der
/// akzeptierten Werte in der Bewegungszeit des Abschnitts.
KilometerSplits computeBeltSplits(
  RunPreprocessing pre,
  BeltTrack belt, {
  double unitMeters = kilometerMeters,
}) {
  assert(unitMeters > 0);
  final heart = pre.heartRate.acceptedValues;
  final splits = <KilometerSplit>[];
  var micros = 0;
  var meters = 0.0; // im laufenden Abschnitt
  var sum = 0;
  var n = 0;

  void heartIn(DateTime from, DateTime to) {
    for (final h in heart) {
      if (!h.time.isBefore(from) && h.time.isBefore(to)) {
        sum += h.bpm;
        n++;
      }
    }
  }

  void close(double length, {required bool partial}) {
    final time = Duration(microseconds: micros);
    final speed = time > Duration.zero ? length / (micros / 1e6) : null;
    splits.add(
      KilometerSplit(
        index: splits.length + 1,
        lengthMeters: length,
        isPartial: partial,
        time: time,
        positionGapTime: Duration.zero,
        paceSecondsPerKm:
            speed == null || speed < pre.parameters.standstillBelow
            ? null
            : micros / 1e6 / (length / 1000),
        heartRateAverageBpm: n == 0 ? null : sum / n,
      ),
    );
    micros = 0;
    meters = 0;
    sum = 0;
    n = 0;
  }

  for (final p in belt.pieces) {
    if (!p.isMoving) continue;
    final v = p.speedMetersPerSecond;
    var from = p.span.start;
    final end = p.span.end;
    while (true) {
      final toGo = unitMeters - meters;
      final remainingMeters = v * end.difference(from).inMicroseconds / 1e6;
      if (remainingMeters + _lengthEpsilonMeters < toGo) {
        micros += end.difference(from).inMicroseconds;
        meters += remainingMeters;
        heartIn(from, end);
        break;
      }
      final cut = from.add(Duration(microseconds: (toGo / v * 1e6).round()));
      final at = cut.isAfter(end) ? end : cut;
      micros += at.difference(from).inMicroseconds;
      heartIn(from, at);
      close(unitMeters, partial: false);
      from = at;
      if (!from.isBefore(end)) break;
    }
  }
  if (meters > _lengthEpsilonMeters) close(meters, partial: true);

  return KilometerSplits(
    unitMeters: unitMeters,
    splits: splits,
    marks: const [],
    ascentMeters: null,
    descentMeters: null,
  );
}

/// [computeKilometerSplits] als Auftrag für einen anderen Isolate; [belt] nur
/// bei einem Bandlauf.
KilometerSplits kilometerSplitsJob(
  ({RunPreprocessing pre, double unitMeters, BeltTrack? belt}) a,
) => computeKilometerSplits(a.pre, unitMeters: a.unitMeters, belt: a.belt);

RoutePoint? _between(
  Map<DateTime, RawPosition> points,
  MotionSegment s,
  double f,
) {
  final a = points[s.start];
  final b = points[s.end];
  if (a == null || b == null) return null;
  return RoutePoint(
    a.latitude + (b.latitude - a.latitude) * f,
    a.longitude + (b.longitude - a.longitude) * f,
  );
}
