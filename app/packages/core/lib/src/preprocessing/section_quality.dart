import 'heart_rate_beat.dart';
import 'heart_rate_processor.dart';
import 'measurement.dart';
import 'movement_time_processor.dart';
import 'position_processor.dart';
import 'preprocessing_parameters.dart';

/// Kennung und Version der Abschnittsqualität (ADR-0004 P.3).
const String sectionQualityMethod = 'section-quality';
const int sectionQualityMethodVersion = 2;

/// Qualität der Daten eines Abschnitts (FR-0048). Beschreibt nur; ob ein
/// Abschnitt taugt, entscheidet die Abschnittsauswahl (WP09).
class SectionQuality {
  /// Öffentlich, damit eine gespeicherte Bewertung wieder geladen werden kann
  /// (FR-0048, FR-0058).
  SectionQuality({
    required this.parameterVersion,
    required this.from,
    required this.to,
    required Map<MeasurementState, int> heartRateCounts,
    required Map<MeasurementState, int> positionCounts,
    required this.missingHeartRateShare,
    required this.longestHeartRateGap,
    required this.meetsHeartRateGapRule,
    required this.settlingOverlap,
    required this.settlingShare,
    required List<PositionGap> gpsGaps,
  }) : heartRateCounts = Map.unmodifiable(heartRateCounts),
       positionCounts = Map.unmodifiable(positionCounts),
       gpsGaps = List.unmodifiable(gpsGaps);

  /// Bewertet `[from, to]` aus den Ergebnissen der Prozessoren. Reine
  /// Funktion; ändert die Eingaben nicht. Die Version stammt aus den Eingaben;
  /// weichen Position oder Parametersatz ab, wird ein [ArgumentError] geworfen.
  factory SectionQuality.assess({
    required DateTime from,
    required DateTime to,
    required HeartRateResult heartRate,
    required PositionResult position,
    required List<TimeSpan> settlingIntervals,
    required PreprocessingParameters parameters,
  }) {
    final version = heartRate.parameterVersion;
    if (position.parameterVersion != version ||
        parameters.parameterVersion != version) {
      throw ArgumentError(
        'Parameterversionen weichen ab: Puls $version, '
        'Position ${position.parameterVersion}, '
        'Parametersatz ${parameters.parameterVersion}',
      );
    }
    if (!to.isAfter(from)) {
      throw ArgumentError.value(to, 'to', 'muss nach from liegen');
    }
    bool inside(DateTime t) => !t.isBefore(from) && !t.isAfter(to);

    Map<MeasurementState, int> count(
      Iterable<(DateTime, MeasurementState)> xs,
    ) {
      final m = {for (final s in MeasurementState.values) s: 0};
      for (final (t, s) in xs) {
        if (inside(t)) m[s] = m[s]! + 1;
      }
      return m;
    }

    final times = [
      for (final h in heartRate.acceptedValues)
        if (inside(h.time)) h.time,
    ];
    final gaps = _gapDurations(from, to, times);
    final longest = gaps.isEmpty
        ? to.difference(from)
        : gaps.reduce((a, b) => a > b ? a : b);
    final span = to.difference(from).inMicroseconds;
    final received = [
      for (final p in heartRate.processed)
        if (p.reason != DiscardReason.nonMonotonicTime && inside(p.input.time))
          p.input.time,
    ];
    final missing = _missing(gaps, times, received);

    var overlap = Duration.zero;
    for (final s in settlingIntervals) {
      final a = s.start.isAfter(from) ? s.start : from;
      final b = s.end.isBefore(to) ? s.end : to;
      if (b.isAfter(a)) overlap += b.difference(a);
    }

    return SectionQuality(
      parameterVersion: version,
      from: from,
      to: to,
      heartRateCounts: Map.unmodifiable(
        count([for (final p in heartRate.processed) (p.input.time, p.state)]),
      ),
      positionCounts: Map.unmodifiable(
        count([for (final p in position.positions) (p.input.time, p.state)]),
      ),
      missingHeartRateShare: missing.inMicroseconds / span,
      longestHeartRateGap: longest,
      meetsHeartRateGapRule:
          missing.inMicroseconds / span <=
              parameters.heartRateMaxMissingShare &&
          longest <= parameters.heartRateMaxSingleGap,
      settlingOverlap: overlap,
      settlingShare: overlap.inMicroseconds / span,
      gpsGaps: [
        for (final g in position.gaps)
          if (g.start.isBefore(to) && g.end.isAfter(from)) g,
      ],
    );
  }

  /// Abstände der aufeinanderfolgenden Werte einschließlich Anfang und Ende
  /// des Abschnitts. Ohne Wert: eine Lücke über den ganzen Abschnitt.
  static List<Duration> _gapDurations(
    DateTime from,
    DateTime to,
    List<DateTime> times,
  ) {
    final edges = [from, ...times, to];
    return [
      for (var i = 1; i < edges.length; i++) edges[i].difference(edges[i - 1]),
    ];
  }

  /// Fehlende Zeit: Σ über die Abstände der akzeptierten Werte, je Abstand
  /// 0, wenn nur ein Wert zu erwarten war (`round(Δt / Takt) <= 1`, siehe
  /// [beatCoversGap]), sonst Δt − Median-Takt. Der Takt ist der Median der Abstände zwischen allen
  /// eingegangenen Werten im Abschnitt, auch verworfenen ([received]), damit
  /// verworfene Werte den Takt nicht senken. Ohne mindestens zwei akzeptierte
  /// oder zwei eingegangene Werte ist kein Takt bekannt: dann fehlt die ganze
  /// Zeit.
  static Duration _missing(
    List<Duration> gaps,
    List<DateTime> times,
    List<DateTime> received,
  ) {
    if (times.length < 2 || received.length < 2) {
      return gaps.fold(Duration.zero, (a, b) => a + b);
    }
    final beat = medianBeatMicros(received)!;
    var micros = 0;
    for (final g in gaps) {
      micros += missingMicrosInGap(g.inMicroseconds, beat);
    }
    return Duration(microseconds: micros);
  }

  String get method => sectionQualityMethod;
  int get methodVersion => sectionQualityMethodVersion;
  final int parameterVersion;
  final DateTime from;
  final DateTime to;

  /// Zählwerte der Pulseingaben im Abschnitt je Zustand (alle vier Schlüssel).
  final Map<MeasurementState, int> heartRateCounts;

  /// Zählwerte der Positionseingaben im Abschnitt je Zustand.
  final Map<MeasurementState, int> positionCounts;

  /// Anteil fehlender Pulszeit am Abschnitt; ohne Werte 1,0.
  final double missingHeartRateShare;

  /// Längste Zeit ohne akzeptierten Puls im Abschnitt.
  final Duration longestHeartRateGap;

  /// PAR-010: Anteil höchstens 5 % und keine Einzellücke über 10 s.
  final bool meetsHeartRateGapRule;

  /// PAR-011: Zeit des Abschnitts innerhalb der Einschwingzeit.
  final Duration settlingOverlap;
  final double settlingShare;
  bool get overlapsSettling => settlingOverlap > Duration.zero;

  /// GPS-Lücken (PAR-004), die den Abschnitt berühren.
  final List<PositionGap> gpsGaps;
}
