import '../preprocessing/motion_segments.dart';
import 'statistics_parameters.dart';

/// Einheit: Meter je Kilometer und Mikrosekunden je Sekunde.
const double _metersPerKilometer = 1000;
const double _microsPerSecond = 1e6;

enum BestPaceUnavailable {
  /// Kein zusammenhängender Abschnitt der geforderten Länge: Lauf kürzer, oder
  /// Lücken und manuelle Pausen zerlegen ihn in kürzere Stücke.
  noQualifyingSection,
}

/// Schnellster zusammenhängender Abschnitt (OQ-0037, FR-0037). Fehlt er, ist
/// [secondsPerKm] `null` und [unavailable] gesetzt, nie 0.
class BestPace {
  const BestPace.available({
    required double this.secondsPerKm,
    required DateTime this.sectionStart,
    required DateTime this.sectionEnd,
  }) : unavailable = null;

  const BestPace.unavailable(BestPaceUnavailable this.unavailable)
    : secondsPerKm = null,
      sectionStart = null,
      sectionEnd = null;

  final double? secondsPerKm;
  final DateTime? sectionStart;
  final DateTime? sectionEnd;
  final BestPaceUnavailable? unavailable;

  bool get isAvailable => secondsPerKm != null;
}

/// Bestpace aus den zählenden Segmenten eines Laufs (`PaceResult.segments`).
///
/// Zusammenhängend heißt: lückenlos aneinander anschließende Segmente. Eine
/// Lücke über PAR-004 oder eine manuelle Pause trennt, ein Abschnitt reicht nie
/// darüber. Innerhalb eines Abschnitts zählt die Zeit einschließlich erkannter
/// Stillstände (die Spec nimmt sie nicht aus). Die Strecke eines Segments
/// verteilt sich gleichmäßig über seine Zeit. Gesucht ist das Fenster der
/// Länge `bestPaceDistanceMeters` mit der kürzesten Zeit.
BestPace bestPace(
  Iterable<MotionSegment> segments, {
  StatisticsParameters parameters = const StatisticsParameters(),
}) {
  final window = parameters.bestPaceDistanceMeters;
  _Window? best;
  for (final chain in _chains(segments)) {
    final w = _fastestWindow(chain, window);
    if (w != null && (best == null || w.micros < best.micros)) best = w;
  }
  if (best == null) {
    return const BestPace.unavailable(BestPaceUnavailable.noQualifyingSection);
  }
  final seconds = best.micros / _microsPerSecond;
  return BestPace.available(
    secondsPerKm: seconds / (window / _metersPerKilometer),
    sectionStart: best.start,
    sectionEnd: best.end,
  );
}

/// Aneinander anschließende Segmente; Lücken- und Nullsegmente trennen.
List<List<MotionSegment>> _chains(Iterable<MotionSegment> segments) {
  final chains = <List<MotionSegment>>[];
  List<MotionSegment>? current;
  for (final s in segments) {
    if (s.isGap) {
      current = null;
      continue;
    }
    final last = current?.last;
    if (current == null || !last!.end.isAtSameMomentAs(s.start)) {
      current = [];
      chains.add(current);
    }
    current.add(s);
  }
  return chains;
}

class _Window {
  _Window(this.micros, this.start, this.end);
  final int micros;
  final DateTime start;
  final DateTime end;
}

/// Kürzeste Zeit für [window] Meter in einer Kette. Die Zeit als Funktion der
/// Strecke ist stückweise linear; das Minimum liegt dort, wo Anfang oder Ende
/// des Fensters auf einer Segmentgrenze steht. Beide Fälle werden geprüft.
_Window? _fastestWindow(List<MotionSegment> chain, double window) {
  final n = chain.length;
  final origin = chain.first.start;
  // Grenze i: Zeit t[i] (µs seit Beginn) und Strecke d[i] (m, kumuliert).
  final t = List<int>.filled(n + 1, 0);
  final d = List<double>.filled(n + 1, 0);
  for (var i = 0; i < n; i++) {
    t[i + 1] = chain[i].end.difference(origin).inMicroseconds;
    d[i + 1] = d[i] + chain[i].meters;
  }
  if (d[n] < window) return null;

  int? best;
  int bestStart = 0;
  int bestEnd = 0;
  void offer(double startMicros, double endMicros) {
    final micros = (endMicros - startMicros).round();
    if (best == null || micros < best!) {
      best = micros;
      bestStart = startMicros.round();
      bestEnd = endMicros.round();
    }
  }

  // Anfang auf der Grenze i: Ende zur frühesten Zeit bei d[i] + window.
  for (var i = 0; i <= n && d[i] + window <= d[n]; i++) {
    final target = d[i] + window;
    final k = _firstAtLeast(d, target);
    final from = d[k - 1];
    final share = (target - from) / (d[k] - from);
    offer(t[i].toDouble(), t[k - 1] + share * (t[k] - t[k - 1]));
  }
  // Ende auf der Grenze k: Anfang zur spätesten Zeit bei d[k] - window.
  for (var k = n; k >= 0 && d[k] - window >= 0; k--) {
    final target = d[k] - window;
    final j = _lastAtMost(d, target);
    // j < n, da target < d[k] <= d[n]; d[j + 1] > target nach Wahl von j.
    final share = (target - d[j]) / (d[j + 1] - d[j]);
    offer(t[j] + share * (t[j + 1] - t[j]), t[k].toDouble());
  }
  return _Window(
    best!,
    origin.add(Duration(microseconds: bestStart)),
    origin.add(Duration(microseconds: bestEnd)),
  );
}

/// Kleinster Index mit `d[k] >= target` (`d` nicht fallend, `target > d[0]`).
int _firstAtLeast(List<double> d, double target) {
  var lo = 0;
  var hi = d.length - 1;
  while (lo < hi) {
    final mid = (lo + hi) ~/ 2;
    if (d[mid] >= target) {
      hi = mid;
    } else {
      lo = mid + 1;
    }
  }
  return lo;
}

/// Größter Index mit `d[j] <= target`.
int _lastAtMost(List<double> d, double target) {
  var lo = 0;
  var hi = d.length - 1;
  while (lo < hi) {
    final mid = (lo + hi + 1) ~/ 2;
    if (d[mid] <= target) {
      lo = mid;
    } else {
      hi = mid - 1;
    }
  }
  return lo;
}
