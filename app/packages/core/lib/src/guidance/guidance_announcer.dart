import '../plan/plan_unit.dart';
import '../recording/recording_session.dart';
import 'guidance_event.dart';
import 'guidance_parameters.dart';
import 'guided_position.dart';

/// Eingabe je Tick (aus dem `RecordingSnapshot`).
class GuidanceTick {
  const GuidanceTick({
    required this.movingTime,
    required this.phase,
    this.distanceMeters,
    this.heartRateBpm,
  });

  final Duration movingTime;
  final RecordingPhase phase;
  final double? distanceMeters;
  final int? heartRateBpm;
}

/// Ereignisgeber der geführten Einheit: entscheidet je Tick, welche Ansagen
/// fällig sind. Hält nur flüchtigen Zustand; ein neuer Geber mit denselben
/// Abschnitten setzt beim ersten Tick aus (Abschnitte, Bewegungszeit,
/// Strecke) neu auf und sagt Vergangenes nicht noch einmal an (Wiederanlauf).
/// Nur im Zustand `running` kommen Ansagen; in Pause und Autopause steht die
/// Bewegungszeit und damit der Abschnitt still.
///
/// Zustand läuft unabhängig von [switches] weiter: ein abgeschalteter Kanal
/// sagt später nichts Altes nach.
class GuidanceAnnouncer {
  GuidanceAnnouncer({
    required List<PlanSegment> segments,
    this.switches = const GuidanceSwitches(),
    this.suppressHeartRateForWalkBreaks = false,
    bool walkBreakHintGiven = false,
  }) : segments = List.unmodifiable(segments),
       _walkHintGiven = walkBreakHintGiven;

  final List<PlanSegment> segments;

  /// Änderbar während des Laufs.
  GuidanceSwitches switches;

  /// PAR-107: obere Grenze in den letzten 3 lockeren Einheiten überwiegend
  /// überschritten (`easyRunsMostlyAboveUpper`): keine Pulsansagen, einmal der
  /// Gehpausen-Hinweis.
  final bool suppressHeartRateForWalkBreaks;

  bool _walkHintGiven;

  /// Der Gehpausen-Hinweis kam schon (der Aufrufer kann das für einen
  /// Wiederanlauf merken).
  bool get walkBreakHintGiven => _walkHintGiven;

  bool _initialised = false;
  int _lastKm = 0;
  Duration? _lastKmTime;
  int _lastIndex = 0;
  int _previewedIndex = -1;
  Duration? _aboveSince;
  bool _armed = true;
  Duration _lastTime = Duration.zero;
  bool _lastRunning = false;

  /// Der Puls liegt nach dem letzten Tick im Lauf (nicht in Pause) seit
  /// mindestens [pulseAnnounceMinOverrun] über der oberen Grenze des
  /// Abschnitts, im Fenster nach `pulseHintAllowed` (PAR-107). Unabhängig von
  /// den Schaltern und vom Gehpausen-Zustand; Grundlage des Hinweises auf der
  /// Live-Seite.
  bool get pulseOverrunSustained =>
      _lastRunning &&
      _aboveSince != null &&
      _lastTime - _aboveSince! >= pulseAnnounceMinOverrun;

  List<GuidanceEvent> onTick(GuidanceTick tick) {
    final t = tick.movingTime.isNegative ? Duration.zero : tick.movingTime;
    final pos = guidedPosition(segments, t);
    final km = _wholeKm(tick.distanceMeters);
    if (!_initialised) {
      _initialised = true;
      _lastKm = km;
      // Der Start des ersten Kilometers ist Zeit 0; danach unbekannt.
      _lastKmTime = km == 0 ? Duration.zero : null;
      _lastIndex = pos.index;
      if (_inPreviewWindow(pos)) _previewedIndex = pos.index;
      // Erster Tick: nichts nachsagen.
      return const [];
    }
    _lastTime = t;
    _lastRunning = tick.phase == RecordingPhase.running;
    if (!_lastRunning) return const [];

    final out = <GuidanceEvent>[];
    void emit(GuidanceEvent e) {
      if (switches.allows(e.kind)) out.add(e);
    }

    // Kilometer.
    if (km > _lastKm) {
      final single = km == _lastKm + 1 && _lastKmTime != null;
      emit(
        GuidanceEvent.kilometer(
          kilometer: km,
          time: t,
          duration: single ? t - _lastKmTime! : null,
        ),
      );
      _lastKm = km;
      _lastKmTime = t;
    }

    // Abschnittswechsel.
    var changed = false;
    if (pos.index > _lastIndex) {
      changed = true;
      _lastIndex = pos.index;
      _aboveSince = null;
      _armed = true;
      if (pos.finished) {
        emit(const GuidanceEvent.unitComplete());
      } else {
        emit(
          GuidanceEvent.segmentChange(index: pos.index, segment: pos.segment!),
        );
      }
    }

    // Vorankündigung.
    if (!changed && _inPreviewWindow(pos) && _previewedIndex != pos.index) {
      _previewedIndex = pos.index;
      emit(
        GuidanceEvent.segmentPreview(
          index: pos.index + 1,
          segment: pos.next!,
          until: pos.remaining,
        ),
      );
    }

    // Puls (PAR-107).
    _heartRate(tick, t, pos, emit);
    return out;
  }

  bool _inPreviewWindow(GuidedPosition pos) =>
      !pos.finished &&
      pos.next != null &&
      pos.remaining <= segmentPreviewLead &&
      Duration(seconds: pos.segment!.durationSeconds) >
          segmentPreviewMinSegment;

  int _wholeKm(double? meters) => meters == null || meters < 0
      ? _lastKm
      : (meters / guidanceKilometerMeters).floor();

  void _heartRate(
    GuidanceTick tick,
    Duration t,
    GuidedPosition pos,
    void Function(GuidanceEvent) emit,
  ) {
    final bpm = tick.heartRateBpm;
    final maxBpm = pos.target?.hrMaxBpm;
    final eligible = maxBpm != null && pulseHintAllowed(pos, t);
    if (bpm == null || !eligible) {
      _aboveSince = null;
      return;
    }
    if (bpm <= maxBpm) {
      _aboveSince = null;
      _armed = true;
      return;
    }
    _aboveSince ??= t;
    if (!_armed || t - _aboveSince! < pulseAnnounceMinOverrun) return;
    if (suppressHeartRateForWalkBreaks) {
      if (_walkHintGiven) return;
      if (switches.allows(GuidanceEventKind.walkBreakHint)) {
        _walkHintGiven = true;
        _armed = false;
        emit(const GuidanceEvent.walkBreakHint());
      }
      return;
    }
    if (switches.allows(GuidanceEventKind.heartRateAbove)) {
      _armed = false;
      emit(GuidanceEvent.heartRateAbove(bpm: bpm, maxBpm: maxBpm));
    }
  }
}
