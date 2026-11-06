import 'motion_segments.dart';
import 'preprocessing_parameters.dart';

/// Kennung und Version des Bewegungszeitverfahrens (ADR-0004 P.3).
const String movementMethod = 'movement-time';
const int movementMethodVersion = 1;

/// Zustand der erkannten Pause (nur Zustand; die Steuerung ist WP06).
enum AutoPauseState { moving, standstillPause }

/// Zeitraum, der zur Bewegungszeit zählt.
class TimeSpan {
  const TimeSpan({required this.start, required this.end});
  final DateTime start;
  final DateTime end;
  Duration get duration => end.difference(start);
}

class MovementResult {
  MovementResult({
    required this.parameterVersion,
    required this.totalTime,
    required this.movingTime,
    required List<TimeSpan> movingIntervals,
    required this.autoPauseState,
    required this.manuallyPaused,
    required List<DateTime> resumedAt,
  }) : movingIntervals = List.unmodifiable(movingIntervals),
       resumedAt = List.unmodifiable(resumedAt);

  String get method => movementMethod;
  int get methodVersion => movementMethodVersion;
  final int parameterVersion;

  /// `at - start`, einschließlich aller Pausen (FR-0052).
  final Duration totalTime;
  final Duration movingTime;
  final List<TimeSpan> movingIntervals;
  final AutoPauseState autoPauseState;
  final bool manuallyPaused;

  /// Zeitpunkte, an denen nach einer Pause (manuell oder erkannt) wieder
  /// Bewegung beginnt; Grundlage der Einschwingzeit (PAR-011).
  final List<DateTime> resumedAt;
}

/// Bewegungszeit mit Hysterese (PAR-014) und Haltedauern (PAR-015).
///
/// Zustandswechsel geschehen nur mit einem Segment; nichts wird rückwirkend
/// geändert. Zeit nach dem letzten Punkt zählt nach dem aktuellen Zustand.
class MovementTimeProcessor {
  MovementTimeProcessor(this.parameters, {required this.start})
    : _openStart = start;

  final PreprocessingParameters parameters;
  final DateTime start;

  final List<TimeSpan> _intervals = [];
  final List<DateTime> _resumes = [];

  /// Beginn der laufenden Bewegungsphase, `null` in Pause (auto oder manuell).
  DateTime? _openStart;
  AutoPauseState _state = AutoPauseState.moving;
  bool _manual = false;

  /// Beginn des laufenden Kandidaten (Stillstand im Zustand `moving`,
  /// Bewegung im Zustand `standstillPause`).
  DateTime? _candidate;

  /// Erkannter Zustand, ohne das Ergebnis aufzubauen (billig je Punkt).
  AutoPauseState get autoPauseState => _state;

  void add(MotionSegment s) {
    if (_manual) return;
    if (s.isGap) {
      // PAR-004-Lücke: Kandidat bricht ab, Zustand bleibt, keine Pause.
      _candidate = null;
      return;
    }
    final v = s.meters / s.seconds;
    final moving = _state == AutoPauseState.moving;
    final matches = moving
        ? v < parameters.standstillBelow
        : v >= parameters.movementFrom;
    if (!matches) {
      _candidate = null; // auch das Band dazwischen unterbricht
      return;
    }
    final begin = _candidate ??= s.start;
    final hold = moving
        ? parameters.standstillMinDuration
        : parameters.resumeMinDuration;
    final switchAt = begin.add(hold);
    if (switchAt.isAfter(s.end)) return;
    _candidate = null;
    if (moving) {
      _close(switchAt);
      _state = AutoPauseState.standstillPause;
    } else {
      _state = AutoPauseState.moving;
      _openStart = switchAt;
      _resumes.add(switchAt);
    }
  }

  void _close(DateTime end) {
    final from = _openStart;
    if (from != null && end.isAfter(from)) {
      _intervals.add(TimeSpan(start: from, end: end));
    }
    _openStart = null;
  }

  /// Manuelle Pause: zählt nie zur Bewegungszeit, immer zur Gesamtzeit.
  void pause(DateTime time) {
    if (_manual) return;
    _close(time);
    _manual = true;
    _candidate = null;
  }

  /// Fortsetzen: neuer Abschnitt im Zustand `moving`.
  void resume(DateTime time) {
    if (!_manual) return;
    _manual = false;
    _state = AutoPauseState.moving;
    _candidate = null;
    _openStart = time;
    _resumes.add(time);
  }

  /// Stand zum Zeitpunkt [at] (nicht vor der letzten Eingabe).
  MovementResult result({required DateTime at}) {
    // Auf [at] gekappt: Bewegungszeit ist nie größer als die Gesamtzeit,
    // auch bei einer Abfrage vor bereits geschlossenen Intervallen.
    final intervals = [
      for (final i in _intervals)
        if (i.start.isBefore(at))
          TimeSpan(start: i.start, end: i.end.isAfter(at) ? at : i.end),
    ];
    final open = _openStart;
    if (open != null && at.isAfter(open)) {
      intervals.add(TimeSpan(start: open, end: at));
    }
    var moving = Duration.zero;
    for (final i in intervals) {
      moving += i.duration;
    }
    final total = at.difference(start);
    return MovementResult(
      parameterVersion: parameters.parameterVersion,
      totalTime: total.isNegative ? Duration.zero : total,
      movingTime: moving,
      movingIntervals: intervals,
      autoPauseState: _state,
      manuallyPaused: _manual,
      resumedAt: _resumes,
    );
  }
}
