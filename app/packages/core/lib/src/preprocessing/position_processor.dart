import '../fitness/algorithm_variant.dart';
import 'geo.dart';
import 'latest_value_index.dart';
import 'measurement.dart';
import 'preprocessing_parameters.dart';

/// Kennung und Version des Positionsverfahrens (ADR-0004 P.3).
const String positionMethod = 'position-filter';
const int positionMethodVersion = 1;

/// Kategorie des Verfahrens (NFR-0002, docs/architecture/algorithm-categories.md): B.
const AlgorithmCategory positionCategory = AlgorithmCategory.heuristic;

/// Bewertung einer Positionseingabe.
class ProcessedPosition {
  const ProcessedPosition({
    required this.input,
    required this.state,
    this.reason,
    this.countedDistanceMeters = 0,
  });

  final RawPosition input;

  /// `present`, `estimated` (überbrückt oder vom Sensor geschätzt),
  /// `discarded` (mit [reason]) oder `unavailable` (nicht verwertet, etwa
  /// während einer manuellen Pause).
  final MeasurementState state;
  final DiscardReason? reason;

  /// Strecke, die dieser Punkt zur Summe beigetragen hat.
  final double countedDistanceMeters;

  bool get accepted =>
      state == MeasurementState.present || state == MeasurementState.estimated;
}

/// Zeitraum ohne verwertbare Position (PAR-004).
class PositionGap {
  const PositionGap({
    required this.start,
    required this.end,
    required this.open,
  });

  /// Zeit des letzten akzeptierten Punkts, vor dem ersten Punkt der Beginn des
  /// Abschnitts (Start bzw. Fortsetzen).
  final DateTime start;

  /// Zeit des nächsten akzeptierten Punkts bzw. der Stand der Abfrage.
  final DateTime end;

  /// Noch nicht durch einen Punkt beendet.
  final bool open;

  MeasurementState get state => MeasurementState.unavailable;
}

class PositionResult {
  PositionResult({
    required this.parameterVersion,
    required List<ProcessedPosition> positions,
    required List<RawPosition> acceptedPoints,
    required this.distanceMeters,
    required this.bridgedDistanceMeters,
    required List<PositionGap> gaps,
  }) : positions = List.unmodifiable(positions),
       acceptedPoints = List.unmodifiable(acceptedPoints),
       gaps = List.unmodifiable(gaps);

  String get method => positionMethod;
  int get methodVersion => positionMethodVersion;
  final int parameterVersion;

  /// Je Eingabe eine Bewertung, in Ankunftsreihenfolge.
  final List<ProcessedPosition> positions;
  final List<RawPosition> acceptedPoints;

  /// Summe der plausiblen Distanzen (FR-0049), einschließlich der überbrückten.
  final double? distanceMeters;

  /// Teil von [distanceMeters], der über Aussetzer ≤ PAR-004 geschätzt ist.
  final double bridgedDistanceMeters;
  final List<PositionGap> gaps;
}

/// Positionsfilter, Strecke und Lücken (PAR-001 bis PAR-004).
///
/// Schrittform: Die Gesamtrechnung ist der Fold über [add].
class PositionProcessor {
  /// [sectionStart] ist der Beginn des ersten Abschnitts (Bezugspunkt der
  /// Lückenprüfung, kein Anker für Distanz oder Sprungfilter).
  PositionProcessor(this.parameters, {DateTime? sectionStart})
    // ignore: prefer_initializing_formals
    : _sectionStart = sectionStart;

  final PreprocessingParameters parameters;

  final List<ProcessedPosition> _positions = [];
  final List<RawPosition> _accepted = [];
  final List<PositionGap> _gaps = [];
  final LatestValueIndex<RawPosition> _index = LatestValueIndex();
  RawPosition? _anchor;
  DateTime? _lastTime;
  int _discardedSinceAnchor = 0;
  double _distance = 0;
  double _bridged = 0;
  bool _paused = false;
  DateTime? _sectionStart;

  /// Beginn einer manuellen Pause: Der Abschnitt endet, keine Distanz über die
  /// Pause. Eine bis hierhin offene Lücke wird geschlossen.
  void pause(DateTime time) {
    if (_paused) return;
    _closeGapIfLong(time);
    _paused = true;
    _anchor = null;
    _sectionStart = null;
    _discardedSinceAnchor = 0;
  }

  /// Ende der manuellen Pause: neuer Abschnitt ohne Anker. Pausenzeit ist keine
  /// GPS-Lücke.
  void resume(DateTime time) {
    if (!_paused) return;
    _paused = false;
    _sectionStart = time;
  }

  void _closeGapIfLong(DateTime end) {
    final from = _gapReference;
    if (from != null && end.difference(from) > parameters.gapMaxDuration) {
      _gaps.add(PositionGap(start: from, end: end, open: false));
    }
  }

  /// Bezugspunkt der Lückenprüfung: letzter akzeptierter Punkt, vor dem ersten
  /// Punkt eines Abschnitts dessen Beginn.
  DateTime? get _gapReference => _anchor?.time ?? _sectionStart;

  ProcessedPosition add(RawPosition p) {
    final ProcessedPosition r = _classify(p);
    _positions.add(r);
    return r;
  }

  ProcessedPosition _classify(RawPosition p) {
    final last = _lastTime;
    if (last != null && !p.time.isAfter(last)) {
      return ProcessedPosition(
        input: p,
        state: MeasurementState.discarded,
        reason: DiscardReason.nonMonotonicTime,
      );
    }

    if (_paused ||
        p.state == MeasurementState.unavailable ||
        p.state == MeasurementState.discarded) {
      // Ein Aussetzer des Sensors überbrückt die Strecke wie ein verworfener
      // Punkt; in der Pause gibt es keine Strecke.
      if (!_paused) _discardedSinceAnchor++;
      return ProcessedPosition(input: p, state: MeasurementState.unavailable);
    }

    final reason = _discardReason(p);
    if (reason != null) {
      _discardedSinceAnchor++;
      return ProcessedPosition(
        input: p,
        state: MeasurementState.discarded,
        reason: reason,
      );
    }

    _lastTime = p.time;
    final anchor = _anchor;
    var counted = 0.0;
    var bridged = false;
    final from = _gapReference;
    if (from != null && p.time.difference(from) > parameters.gapMaxDuration) {
      _gaps.add(PositionGap(start: from, end: p.time, open: false));
    } else if (anchor != null) {
      counted = _distanceBetween(anchor, p);
      bridged = _discardedSinceAnchor > 0;
      _distance += counted;
      if (bridged) _bridged += counted;
    }
    _anchor = p;
    _sectionStart = null;
    _discardedSinceAnchor = 0;
    _accepted.add(p);
    final r = ProcessedPosition(
      input: p,
      state: bridged || p.state == MeasurementState.estimated
          ? MeasurementState.estimated
          : MeasurementState.present,
      countedDistanceMeters: counted,
    );
    _index.add(p.time, p, r.state);
    return r;
  }

  double _distanceBetween(RawPosition a, RawPosition b) =>
      haversineMeters(a.latitude, a.longitude, b.latitude, b.longitude);

  DiscardReason? _discardReason(RawPosition p) {
    if (!p.latitude.isFinite || !p.longitude.isFinite) {
      return DiscardReason.invalidValue;
    }
    final acc = p.accuracyMeters;
    if (acc == null ||
        acc < 0 ||
        !(acc <= parameters.positionMaxAccuracyMeters)) {
      return DiscardReason.accuracy;
    }
    final anchor = _anchor;
    if (anchor == null) return null;
    final seconds = p.time.difference(anchor.time).inMicroseconds / 1e6;
    final d = _distanceBetween(anchor, p);
    final speed = d / seconds;
    if (speed > parameters.hardJumpMaxSpeed) return DiscardReason.hardJump;
    if (speed > parameters.softJumpSpeed &&
        d > acc + (anchor.accuracyMeters ?? 0)) {
      return DiscardReason.softJump;
    }
    return null;
  }

  /// Letzte akzeptierte Position `<= t` (FR-0046); `unavailable`, wenn sie
  /// älter als PAR-004 ist.
  Lookup<RawPosition> positionAt(DateTime t) =>
      _index.valueAt(t, maxAge: parameters.gapMaxDuration);

  /// Stand zum Zeitpunkt [at]. Ändert den Zustand nicht.
  PositionResult result({required DateTime at}) {
    final gaps = [..._gaps];
    final from = _gapReference;
    if (!_paused &&
        from != null &&
        at.difference(from) > parameters.gapMaxDuration) {
      gaps.add(PositionGap(start: from, end: at, open: true));
    }
    return PositionResult(
      parameterVersion: parameters.parameterVersion,
      positions: _positions,
      acceptedPoints: _accepted,
      distanceMeters: _accepted.isEmpty ? null : _distance,
      bridgedDistanceMeters: _bridged,
      gaps: gaps,
    );
  }
}
