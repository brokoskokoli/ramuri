import '../algorithm_category.dart';
import 'motion_segments.dart';
import 'pace.dart';
import 'preprocessing_parameters.dart';

/// Kennung und Version des Tempoverfahrens (ADR-0004 P.3).
const String paceMethod = 'pace';
const int paceMethodVersion = 1;

/// Kategorie des Verfahrens (NFR-0002, docs/architecture/algorithm-categories.md): B.
const AlgorithmCategory paceCategory = AlgorithmCategory.heuristic;

/// Median der Segmentgeschwindigkeit im Fenster, das an [time] endet.
class SpeedSample {
  const SpeedSample({required this.time, required this.metersPerSecond});
  final DateTime time;
  final double metersPerSecond;
}

class PaceResult {
  PaceResult({
    required this.parameterVersion,
    required this.liveSpeed,
    required this.livePace,
    required this.liveCountedTime,
    required this.medianSpeed,
    required this.medianPace,
    required List<SpeedSample> medianSeries,
  }) : medianSeries = List.unmodifiable(medianSeries);

  String get method => paceMethod;
  int get methodVersion => paceMethodVersion;
  final int parameterVersion;

  /// PAR-005: Σ Strecke / Σ Zeit im Fenster; `null` unter der Mindestdatenzeit.
  final double? liveSpeed;
  final PaceDisplay livePace;

  /// Zählende Zeit (ohne Lücken) im Live-Fenster.
  final Duration liveCountedTime;

  /// PAR-006: Median der Segmentgeschwindigkeiten in `[at-30 s, at]`.
  final double? medianSpeed;
  final PaceDisplay medianPace;

  /// PAR-006: Median je akzeptiertem Punkt (nachlaufendes Fenster).
  final List<SpeedSample> medianSeries;
}

/// Live-Tempo (PAR-005) und 30-s-Median (PAR-006) über akzeptierte Segmente.
///
/// Schrittform: [add] je Segment; [result] verändert den Zustand nicht.
class PaceProcessor {
  PaceProcessor(this.parameters);

  final PreprocessingParameters parameters;

  /// Segmente ohne Lücken, in Zeitreihenfolge.
  final List<MotionSegment> _segments = [];
  final List<SpeedSample> _speeds = [];
  final List<SpeedSample> _medians = [];

  void add(MotionSegment s) {
    if (s.isGap) return;
    final v = speedMetersPerSecond(s.meters, s.seconds);
    if (v == null) return;
    _segments.add(s);
    _speeds.add(SpeedSample(time: s.end, metersPerSecond: v));
    _medians.add(SpeedSample(time: s.end, metersPerSecond: _median(s.end)!));
  }

  /// Median der Segmentgeschwindigkeiten mit Ende in `[to-30 s, to]`.
  double? _median(DateTime to) {
    final from = to.subtract(parameters.selectionMedianWindow);
    final values = <double>[];
    for (var i = _speeds.length - 1; i >= 0; i--) {
      final s = _speeds[i];
      if (s.time.isBefore(from)) break;
      if (!s.time.isAfter(to)) values.add(s.metersPerSecond);
    }
    if (values.isEmpty) return null;
    values.sort();
    final n = values.length;
    return n.isOdd ? values[n ~/ 2] : (values[n ~/ 2 - 1] + values[n ~/ 2]) / 2;
  }

  /// [inAutoPause]: Zustand erkannte Pause; die Live-Anzeige ist dann
  /// `PaceStandstill`, auch wenn das Fenstermittel noch darüber liegt.
  PaceResult result({required DateTime at, bool inAutoPause = false}) {
    // Nur Segmente, die ganz im Fenster [at-20 s, at] liegen.
    final from = at.subtract(parameters.liveSmoothingWindow);
    var meters = 0.0;
    var micros = 0;
    for (var i = _segments.length - 1; i >= 0; i--) {
      final s = _segments[i];
      if (s.start.isBefore(from)) break;
      if (s.end.isAfter(at)) continue;
      meters += s.meters;
      micros += s.end.difference(s.start).inMicroseconds;
    }
    final counted = Duration(microseconds: micros);
    final live = counted < parameters.liveMinData || micros == 0
        ? null
        : speedMetersPerSecond(meters, micros / 1e6);
    final median = _median(at);
    return PaceResult(
      parameterVersion: parameters.parameterVersion,
      liveSpeed: live,
      livePace: inAutoPause
          ? const PaceStandstill()
          : paceDisplay(live, parameters),
      liveCountedTime: counted,
      medianSpeed: median,
      medianPace: paceDisplay(median, parameters),
      medianSeries: _medians,
    );
  }
}
