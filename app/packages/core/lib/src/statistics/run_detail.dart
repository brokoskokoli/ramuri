import '../preprocessing/movement_time_processor.dart' show TimeSpan;
import '../preprocessing/pace.dart';
import '../preprocessing/run_preprocessor.dart';

/// Ein Punkt eines Verlaufs: Sekunden seit Laufstart (Uhrzeit, mit Pausen)
/// und Messwert.
class DetailPoint {
  const DetailPoint(this.seconds, this.value);
  final double seconds;
  final double value;
}

class RoutePoint {
  const RoutePoint(this.latitude, this.longitude);
  final double latitude;
  final double longitude;
}

/// Zeichendaten eines Laufs (FR-0041, FR-0042) aus der Vorverarbeitung. Jede
/// Reihe besteht aus zusammenhängenden Teilen ("parts"). Zwischen zwei Teilen
/// liegt eine Positionslücke, eine Pulslücke oder eine manuelle Pause; die
/// Zeichnung darf sie nie verbinden.
class RunDetailData {
  RunDetailData({
    required this.route,
    required this.pace,
    required this.heartRate,
    required this.altitude,
    required this.totalSeconds,
    required this.pauses,
  });

  /// Gefilterte, akzeptierte Positionen.
  final List<List<RoutePoint>> route;

  /// Pace in Sekunden je Kilometer (nur Bewegung, kein Stillstand).
  final List<List<DetailPoint>> pace;

  /// Puls in bpm (geglättet, nur akzeptierte Werte).
  final List<List<DetailPoint>> heartRate;

  /// Geglättete Höhe in Metern.
  final List<List<DetailPoint>> altitude;

  /// Länge der Zeitachse in Sekunden (Gesamtzeit).
  final double totalSeconds;

  /// Manuelle Pausen als Sekunden seit Start (Anfang, Ende).
  final List<({double start, double end})> pauses;

  bool get hasRoute => route.any((p) => p.length >= 2);
  bool get hasPace => pace.any((p) => p.isNotEmpty);
  bool get hasHeartRate => heartRate.any((p) => p.isNotEmpty);
  bool get hasAltitude => altitude.any((p) => p.isNotEmpty);

  int get routeSegmentCount => route.where((p) => p.length >= 2).length;
}

/// [buildRunDetail] als Auftrag für einen anderen Isolate.
RunDetailData buildRunDetailJob(
  ({RunPreprocessing pre, DateTime start, DateTime end, List<TimeSpan> pauses})
  a,
) => buildRunDetail(a.pre, start: a.start, end: a.end, pauses: a.pauses);

/// Baut die Zeichendaten. [pauses] sind die manuellen Pausen des Laufs.
/// Übersteigt eine Reihe [maxPoints] Punkte, wird sie je Teil ausgedünnt: erster
/// und letzter Punkt jedes Teils bleiben, Teile werden nie verbunden, und aus
/// jedem Abschnitt bleiben der kleinste und der größte Wert erhalten (kurze
/// Spitzen gehen nicht verloren; Kleinst- und Größtwert der Reihe bleiben
/// exakt).
RunDetailData buildRunDetail(
  RunPreprocessing pre, {
  required DateTime start,
  required DateTime end,
  List<TimeSpan> pauses = const [],
  int maxPoints = 2000,
}) {
  double x(DateTime t) => t.difference(start).inMicroseconds / 1e6;

  final positionBreaks = _merge([
    ...pauses,
    for (final g in pre.position.gaps) TimeSpan(start: g.start, end: g.end),
    for (final s in pre.pace.segments)
      if (s.isGap) TimeSpan(start: s.start, end: s.end),
  ]);
  final heartBreaks = _merge([
    ...pauses,
    for (final g in pre.heartRate.gaps) TimeSpan(start: g.start, end: g.end),
  ]);

  final route = _split<RoutePoint>([
    for (final p in pre.position.acceptedPoints)
      (p.time, RoutePoint(p.latitude, p.longitude)),
  ], positionBreaks);

  final paceSamples = <(DateTime, DetailPoint?)>[];
  for (final s in pre.pace.medianSeries) {
    final d = paceDisplay(s.metersPerSecond, pre.parameters);
    // Stillstand und fehlende Pace unterbrechen die Linie.
    paceSamples.add((
      s.time,
      d is PaceValue ? DetailPoint(x(s.time), d.secondsPerKm) : null,
    ));
  }

  return RunDetailData(
    route: _thinRoute(route, maxPoints),
    pace: _thin(_splitNullable(paceSamples, positionBreaks), maxPoints),
    heartRate: _thin(
      _split<DetailPoint>([
        for (final s in pre.heartRate.medianSeries)
          (s.time, DetailPoint(x(s.time), s.bpm)),
      ], heartBreaks),
      maxPoints,
    ),
    altitude: _thin(
      _split<DetailPoint>([
        for (final s in pre.altitude.smoothed)
          (s.time, DetailPoint(x(s.time), s.meters)),
      ], positionBreaks),
      maxPoints,
    ),
    totalSeconds: x(end),
    pauses: [for (final p in pauses) (start: x(p.start), end: x(p.end))],
  );
}

/// Sortiert und fasst überlappende Zeiträume zusammen.
List<TimeSpan> _merge(List<TimeSpan> spans) {
  final sorted = [...spans]..sort((a, b) => a.start.compareTo(b.start));
  final out = <TimeSpan>[];
  for (final s in sorted) {
    if (out.isNotEmpty && !s.start.isAfter(out.last.end)) {
      if (s.end.isAfter(out.last.end)) {
        out[out.length - 1] = TimeSpan(start: out.last.start, end: s.end);
      }
    } else {
      out.add(s);
    }
  }
  return out;
}

/// Teilt eine nach Zeit sortierte Reihe überall dort, wo ein Zeitraum aus
/// [breaks] (sortiert, überlappungsfrei) zwischen zwei Nachbarn liegt oder sie
/// berührt.
List<List<T>> _split<T>(List<(DateTime, T)> items, List<TimeSpan> breaks) {
  final parts = <List<T>>[];
  var idx = 0;
  DateTime? prev;
  for (final (t, v) in items) {
    if (prev == null) {
      parts.add([v]);
    } else {
      while (idx < breaks.length && !breaks[idx].end.isAfter(prev)) {
        idx++;
      }
      final cut = idx < breaks.length && breaks[idx].start.isBefore(t);
      if (cut) {
        parts.add([v]);
      } else {
        parts.last.add(v);
      }
    }
    prev = t;
  }
  return parts;
}

List<List<DetailPoint>> _splitNullable(
  List<(DateTime, DetailPoint?)> items,
  List<TimeSpan> breaks,
) {
  final parts = <List<DetailPoint>>[];
  var idx = 0;
  DateTime? prev;
  var open = false;
  for (final (t, v) in items) {
    var cut = !open;
    if (prev != null && !cut) {
      while (idx < breaks.length && !breaks[idx].end.isAfter(prev)) {
        idx++;
      }
      cut = idx < breaks.length && breaks[idx].start.isBefore(t);
    }
    prev = t;
    if (v == null) {
      open = false;
      continue;
    }
    if (cut) parts.add([]);
    parts.last.add(v);
    open = true;
  }
  return parts;
}

List<int> _keep(int length, int budget) {
  if (length <= budget || length <= 2) {
    return [for (var i = 0; i < length; i++) i];
  }
  final step = (length - 1) / (budget - 1);
  final out = <int>{0, length - 1};
  for (var i = 1; i < budget - 1; i++) {
    out.add((i * step).round());
  }
  return out.toList()..sort();
}

int _budget(int partLength, int total, int maxPoints) {
  if (total <= maxPoints) return partLength;
  final share = (maxPoints * partLength / total).floor();
  return share < 2 ? 2 : share;
}

/// Min/Max-Ausdünnung eines Teils: erster und letzter Punkt, dazwischen je
/// Abschnitt der kleinste und der größte Wert, in Zeitreihenfolge.
List<DetailPoint> _thinPart(List<DetailPoint> p, int budget) {
  if (p.length <= budget || p.length <= 2) return p;
  final buckets = (budget - 2) ~/ 2;
  final keep = <int>{0, p.length - 1};
  final inner = p.length - 2;
  for (var b = 0; b < buckets; b++) {
    final from = 1 + (b * inner / buckets).floor();
    final to = 1 + ((b + 1) * inner / buckets).floor();
    if (to <= from) continue;
    var lo = from, hi = from;
    for (var i = from + 1; i < to; i++) {
      if (p[i].value < p[lo].value) lo = i;
      if (p[i].value > p[hi].value) hi = i;
    }
    keep
      ..add(lo)
      ..add(hi);
  }
  return [for (final i in keep.toList()..sort()) p[i]];
}

List<List<DetailPoint>> _thin(List<List<DetailPoint>> parts, int maxPoints) {
  final total = parts.fold<int>(0, (n, p) => n + p.length);
  return [
    for (final p in parts)
      if (p.isNotEmpty) _thinPart(p, _budget(p.length, total, maxPoints)),
  ];
}

List<List<RoutePoint>> _thinRoute(List<List<RoutePoint>> parts, int maxPoints) {
  final total = parts.fold<int>(0, (n, p) => n + p.length);
  return [
    for (final p in parts)
      if (p.isNotEmpty)
        [
          for (final i in _keep(p.length, _budget(p.length, total, maxPoints)))
            p[i],
        ],
  ];
}
