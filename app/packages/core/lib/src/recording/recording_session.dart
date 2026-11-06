// ignore_for_file: prefer_initializing_formals
import 'dart:math' as math;

import '../../ports/clock.dart';
import '../../ports/heart_rate_sensor.dart';
import '../../ports/location.dart';
import '../../ports/storage_runs.dart';
import '../preprocessing/measurement.dart';
import '../preprocessing/movement_time_processor.dart';
import '../preprocessing/preprocessing_parameters.dart';
import '../preprocessing/run_preprocessor.dart';

/// Zustand der Aufzeichnung (FR-0028, FR-0029).
///
/// [autoPaused] ist die erkannte Pause bei eingeschalteter Autopause, getrennt
/// von der manuellen [paused], damit die Fortsetzungserkennung weiterläuft.
enum RecordingPhase { idle, running, autoPaused, paused, finished }

/// Antwort auf einen Befehl. Ein ungültiger Übergang ändert nichts.
enum CommandResult { ok, rejected }

/// Was mit einem eingehenden Messwert geschah.
enum Intake {
  /// An die Vorverarbeitung gegeben (sie kann ihn noch verwerfen).
  processed,

  /// Lauf nicht gestartet, nichts geschah.
  ignoredNotActive,

  /// Manuelle Pause: der Punkt zählt nicht zu Strecke, Bewegungszeit, Tempo
  /// und Runden und erreicht die Vorverarbeitung nicht; er soll aber als
  /// Rohwert gespeichert werden (sein Zustand ergibt sich aus der Lücke
  /// `manualPause`, die seine Zeit umfasst).
  recordedWhilePaused,

  /// Lauf beendet: der Wert wird verworfen (auch bei Rennen mit dem Stopp).
  ignoredFinished,

  /// Zeitstempel liegt vor Start bzw. Fortsetzen (nachgelieferter Altwert) oder
  /// nicht nach dem letzten angenommenen Punkt (Uhr sprang zurück).
  ignoredStale,
}

enum RecordingEventKind {
  started,
  manualPaused,
  resumed,
  autoPauseStarted,
  autoPauseEnded,
  lap,
  positionLossStarted,
  positionLossEnded,
  finished,
}

class RecordingEvent {
  const RecordingEvent(this.kind, this.time);
  final RecordingEventKind kind;
  final DateTime time;
}

/// Runde (FR-0030). [lapTime] ist Gesamtzeit seit der letzten Marke, also mit
/// Pausen; [movingTime] ist der Bewegungsanteil davon.
class RecordedLap {
  const RecordedLap({
    required this.index,
    required this.markedAt,
    required this.lapTime,
    required this.movingTime,
  });
  final int index;
  final DateTime markedAt;
  final Duration lapTime;
  final Duration movingTime;

  StoredLap toStored() =>
      StoredLap(index: index, markedAt: markedAt, lapTime: lapTime);
}

/// Pause oder GPS-Lücke; [end] ist `null`, solange sie offen ist.
class RecordedGap {
  const RecordedGap({required this.kind, required this.start, this.end});
  final RunGapKind kind;
  final DateTime start;
  final DateTime? end;
}

/// Stand der Sitzung. Fehlende Werte sind `null`, nie 0.
class RecordingSnapshot {
  const RecordingSnapshot({
    required this.phase,
    required this.autoPauseEnabled,
    required this.startedAt,
    required this.endedAt,
    required this.totalTime,
    required this.movingTime,
    required this.distanceMeters,
    required this.heartRateBpm,
    required this.positionLost,
    required this.positionLossTime,
    required this.positionLossMovingTime,
    required this.standstillDetected,
    required this.laps,
    required this.gaps,
  });

  final RecordingPhase phase;
  final bool autoPauseEnabled;
  final DateTime? startedAt;
  final DateTime? endedAt;

  /// Mit allen Pausen (FR-0052); vor dem Start null.
  final Duration? totalTime;
  final Duration? movingTime;

  /// Nur gemessene Strecke; `null`, solange kein Punkt akzeptiert wurde.
  final double? distanceMeters;

  /// Letzter Puls innerhalb der Einzellücke (PAR-010), sonst `null`.
  final int? heartRateBpm;

  /// Länger als PAR-004 ohne akzeptierte Position (nur im aktiven Lauf).
  final bool positionLost;

  /// Summe der GPS-Lücken bis jetzt (eine offene zählt bis jetzt). Diese Zeit
  /// läuft in [movingTime] mit, trägt aber keine gemessene Strecke.
  final Duration positionLossTime;

  /// Der Teil von [positionLossTime], der in [movingTime] enthalten ist. Im
  /// Stillstand (erkannte Pause) zählt eine Lücke nicht zur Bewegungszeit.
  final Duration positionLossMovingTime;

  /// Stillstand erkannt (PAR-014, PAR-015), unabhängig von der Einstellung.
  final bool standstillDetected;
  final List<RecordedLap> laps;
  final List<RecordedGap> gaps;
}

/// Aufzeichnungssitzung ohne Flutter und ohne Host (ADR-0005 Punkt 3).
///
/// Reine Schrittform: Befehle und Messwerte kommen von außen, die Uhr nur über
/// den Port. Keine Speicherung (Teil C), keine Streams (Dienst, WP08).
/// Thread-Annahme: ein Isolate ruft sequenziell auf.
class RecordingSession {
  RecordingSession({
    required Clock clock,
    this.parameters = const PreprocessingParameters.v4(),
    bool autoPause = false,
    this.positionSource = 'gps',
  }) : _clock = clock,
       _autoPause = autoPause;

  final Clock _clock;
  final PreprocessingParameters parameters;
  final String positionSource;

  bool _autoPause;
  RecordingPhase _phase = RecordingPhase.idle;
  RunPreprocessor? _pre;
  DateTime? _startedAt;
  DateTime? _endedAt;
  DateTime? _activeSince;

  // Zeitbasis (Review 2, Blocker 1): Die Systemuhr führt Start, Pausen,
  // Lücken und Anzeige. Ein Punkt wird datiert mit Uhr beim Empfang minus
  // Alter ([LocationSample.ageMs], Monotonuhr des Geräts); fehlt das Alter,
  // gilt die Empfangszeit. Die GPS-Uhrzeit des Punkts geht nirgends ein, ein
  // Vergleich mit der Systemuhr entfällt also. Gespeichert wird dieselbe Zeit.

  /// Bezugspunkt der Lückenprüfung in Empfangszeit (letzter akzeptierter Punkt
  /// bzw. Beginn des Abschnitts) und offene Lücke.
  DateTime? _gapRef;
  bool _lossOpen = false;
  DateTime? _lossStart;

  /// Zeit des letzten angenommenen (auch in der Pause gespeicherten) Punkts.
  DateTime? _lastPointTime;

  DateTime? _lastMark;
  Duration _lastMarkMoving = Duration.zero;
  RunPreprocessing? _finalResult;
  final List<RecordedLap> _laps = [];
  final List<RecordedGap> _gaps = [];
  final List<RecordingEvent> _events = [];

  RecordingPhase get phase => _phase;
  bool get autoPauseEnabled => _autoPause;
  List<RecordingEvent> get events => List.unmodifiable(_events);
  bool get _active =>
      _phase == RecordingPhase.running || _phase == RecordingPhase.autoPaused;

  /// Schaltet die Autopause (Standard aus, OQ-0065). Beim Ausschalten in der
  /// erkannten Pause geht der Lauf sofort weiter.
  void setAutoPause(bool enabled) {
    if (_autoPause == enabled) return;
    _autoPause = enabled;
    final pre = _pre;
    if (!_active || pre == null) return;
    final now = _clock.now();
    if (!enabled && _phase == RecordingPhase.autoPaused) {
      _phase = RecordingPhase.running;
      _emit(RecordingEventKind.autoPauseEnded, now);
    } else if (enabled &&
        pre.autoPauseState == AutoPauseState.standstillPause) {
      _phase = RecordingPhase.autoPaused;
      _emit(RecordingEventKind.autoPauseStarted, now);
    }
  }

  CommandResult start() {
    if (_phase != RecordingPhase.idle) return CommandResult.rejected;
    final now = _clock.now();
    _startedAt = now;
    _activeSince = now;
    _gapRef = now;
    _lastMark = now;
    _pre = RunPreprocessor(start: now, parameters: parameters);
    _phase = RecordingPhase.running;
    _emit(RecordingEventKind.started, now);
    return CommandResult.ok;
  }

  /// Manuelle Pause; auch aus der erkannten Pause (manuell gewinnt).
  CommandResult pause() {
    if (!_active) return CommandResult.rejected;
    final now = _clock.now();
    _checkLoss(now);
    _closeLoss(now);
    if (_phase == RecordingPhase.autoPaused) {
      _emit(RecordingEventKind.autoPauseEnded, now);
    }
    _pre!.pause(now);
    _phase = RecordingPhase.paused;
    _gaps.add(RecordedGap(kind: RunGapKind.manualPause, start: now));
    _emit(RecordingEventKind.manualPaused, now);
    return CommandResult.ok;
  }

  CommandResult resume() {
    if (_phase != RecordingPhase.paused) return CommandResult.rejected;
    final now = _clock.now();
    _pre!.resume(now);
    _closeManualGap(now);
    _phase = RecordingPhase.running;
    _activeSince = now;
    _gapRef = now; // Pausenzeit ist keine GPS-Lücke
    _emit(RecordingEventKind.resumed, now);
    return CommandResult.ok;
  }

  /// Runde markieren. Bei manueller Pause abgelehnt (Entscheidung, Spec
  /// schweigt): Eine Marke ohne laufende Aufzeichnung hätte keine Position.
  /// In der erkannten Pause erlaubt, der Lauf ist dort noch aktiv.
  CommandResult lap() {
    if (!_active) return CommandResult.rejected;
    final now = _clock.now();
    final moving = _pre!.result(at: now).movement.movingTime;
    final lap = RecordedLap(
      index: _laps.length + 1,
      markedAt: now,
      lapTime: now.difference(_lastMark!),
      movingTime: moving - _lastMarkMoving,
    );
    _laps.add(lap);
    _lastMark = now;
    _lastMarkMoving = moving;
    _emit(RecordingEventKind.lap, now);
    return CommandResult.ok;
  }

  /// Beendet den Lauf aus Lauf und beiden Pausen. Danach ändert nichts mehr
  /// den Stand.
  CommandResult finish() {
    if (_phase == RecordingPhase.idle || _phase == RecordingPhase.finished) {
      return CommandResult.rejected;
    }
    final now = _clock.now();
    if (_active) {
      _checkLoss(now);
      _closeLoss(now);
    }
    if (_phase == RecordingPhase.autoPaused) {
      _emit(RecordingEventKind.autoPauseEnded, now);
    }
    if (_phase == RecordingPhase.paused) _closeManualGap(now);
    _finalResult = _pre!.result(at: now);
    _endedAt = now;
    _phase = RecordingPhase.finished;
    _emit(RecordingEventKind.finished, now);
    return CommandResult.ok;
  }

  /// Zeit des zuletzt von [addPosition] angenommenen Punkts (Uhrbasis).
  DateTime? get lastPointTime => _lastPointTime;

  Intake addPosition(LocationSample s) {
    final now = _clock.now();
    final age = Duration(milliseconds: math.max(0, s.ageMs ?? 0));
    final time = now.subtract(age);
    // Springt die Uhr zurück, ist ein Punkt älter als der letzte angenommene:
    // verworfen, bis die Zeit wieder vorn liegt (Verlust ≤ Sprungdauer).
    final last = _lastPointTime;
    if (_phase == RecordingPhase.paused) {
      if (time.isBefore(_gaps.last.start)) return Intake.ignoredStale;
      if (last != null && !time.isAfter(last)) return Intake.ignoredStale;
      _lastPointTime = time;
      return Intake.recordedWhilePaused;
    }
    final gate = _gate(time);
    if (gate != null) return gate;
    if (last != null && !time.isAfter(last)) return Intake.ignoredStale;
    _lastPointTime = time;
    final pre = _pre!;
    final raw = RawPosition(
      time: time,
      source: positionSource,
      latitude: s.latitude,
      longitude: s.longitude,
      accuracyMeters: s.accuracyMeters,
      speedMetersPerSecond: s.speedMetersPerSecond,
      speedAccuracyMetersPerSecond: s.speedAccuracyMetersPerSecond,
      verticalAccuracyMeters: s.verticalAccuracyMeters,
    );
    _checkLoss(now);
    final r = pre.addPosition(raw);
    if (r.accepted) {
      // Neu verankert: der Übergang ist eine Lücke, auch wenn sie kürzer ist
      // als PAR-004 (noch nicht als Verlust erkannt).
      if (r.reanchored && !_lossOpen && _gapRef != null) _openLoss(_gapRef!);
      // Messzeit, wie die Punkte: die Lücke endet am schließenden Punkt.
      _closeLoss(time);
      _gapRef = time;
    }
    final alt = s.altitudeMeters;
    // Unbedingt weitergeben: ob die Höhe zählt, entscheidet RunPreprocessor
    // (gleiche Regel wie bei der Neuberechnung aus den Rohdaten).
    if (alt != null && alt.isFinite) {
      pre.addAltitude(
        RawAltitude(
          time: time,
          source: positionSource,
          meters: alt,
          verticalAccuracyMeters: s.verticalAccuracyMeters,
        ),
      );
    }
    _syncAutoPause(time);
    return Intake.processed;
  }

  Intake addHeartRate(HeartRateReading r) {
    final gate = _gate(r.time);
    if (gate != null) return gate;
    _pre!.addHeartRate(
      RawHeartRate(time: r.time, source: r.deviceId, bpm: r.beatsPerMinute),
    );
    return Intake.processed;
  }

  /// Prüft die GPS-Lücke gegen die Uhr, wenn keine Punkte kommen. Der Host ruft
  /// es regelmäßig (etwa mit dem Anzeigetakt) auf.
  void tick() {
    if (_active) _checkLoss(_clock.now());
  }

  /// Stand jetzt (nach dem Ende: eingefroren auf das Ende).
  RecordingSnapshot snapshot() => observe().snapshot;

  /// Stand und Vorverarbeitung aus einem Aufbau (O(n) je Aufruf, darum für die
  /// Anzeige je Takt nur einmal) und zu derselben Uhrablesung.
  ({RecordingSnapshot snapshot, RunPreprocessing? preprocessing}) observe() {
    final pre = _pre;
    if (pre == null) {
      return (
        preprocessing: null,
        snapshot: RecordingSnapshot(
          phase: _phase,
          autoPauseEnabled: _autoPause,
          startedAt: null,
          endedAt: null,
          totalTime: null,
          movingTime: null,
          distanceMeters: null,
          heartRateBpm: null,
          positionLost: false,
          positionLossTime: Duration.zero,
          positionLossMovingTime: Duration.zero,
          standstillDetected: false,
          laps: const [],
          gaps: const [],
        ),
      );
    }
    final now = _endedAt ?? _clock.now();
    if (_active) _checkLoss(now);
    final r = _finalResult ?? pre.result(at: now);
    final snapshot = RecordingSnapshot(
      phase: _phase,
      autoPauseEnabled: _autoPause,
      startedAt: _startedAt,
      endedAt: _endedAt,
      totalTime: r.movement.totalTime,
      movingTime: r.movement.movingTime,
      distanceMeters: r.position.distanceMeters,
      heartRateBpm: _phase == RecordingPhase.finished
          ? null
          : pre.heartRateAt(now).value?.bpm,
      positionLost: _lossOpen,
      positionLossTime: _lossTime(now),
      positionLossMovingTime: _lossMovingTime(now, r.movement.movingIntervals),
      standstillDetected:
          r.movement.autoPauseState == AutoPauseState.standstillPause,
      laps: List.unmodifiable(_laps),
      gaps: List.unmodifiable(_gaps),
    );
    return (snapshot: snapshot, preprocessing: r);
  }

  /// Vollständige Vorverarbeitung (Tempo, Höhe, Qualität) für Anzeige und
  /// Speicherung; nach dem Ende der eingefrorene Stand.
  RunPreprocessing? preprocessing() {
    final pre = _pre;
    if (pre == null) return null;
    return _finalResult ?? pre.result(at: _clock.now());
  }

  Intake? _gate(DateTime t) {
    switch (_phase) {
      case RecordingPhase.finished:
        return Intake.ignoredFinished;
      case RecordingPhase.idle:
      case RecordingPhase.paused:
        return Intake.ignoredNotActive;
      case RecordingPhase.running:
      case RecordingPhase.autoPaused:
        return t.isBefore(_activeSince!) ? Intake.ignoredStale : null;
    }
  }

  void _syncAutoPause(DateTime sampleTime) {
    final standing = _pre!.autoPauseState == AutoPauseState.standstillPause;
    if (!_autoPause) return;
    if (standing && _phase == RecordingPhase.running) {
      _phase = RecordingPhase.autoPaused;
      final spans = _pre!.result(at: sampleTime).movement.movingIntervals;
      _emit(
        RecordingEventKind.autoPauseStarted,
        spans.isEmpty ? sampleTime : spans.last.end,
      );
    } else if (!standing && _phase == RecordingPhase.autoPaused) {
      _phase = RecordingPhase.running;
      final resumes = _pre!.result(at: sampleTime).movement.resumedAt;
      _emit(
        RecordingEventKind.autoPauseEnded,
        resumes.isEmpty ? sampleTime : resumes.last,
      );
    }
  }

  Duration _lossTime(DateTime now) {
    var sum = Duration.zero;
    for (final g in _gaps) {
      if (g.kind != RunGapKind.positionLoss) continue;
      sum += (g.end ?? now).difference(g.start);
    }
    return sum;
  }

  /// Schnittmenge der GPS-Lücken mit den Bewegungsintervallen.
  Duration _lossMovingTime(DateTime now, List<TimeSpan> moving) {
    var sum = Duration.zero;
    for (final g in _gaps) {
      if (g.kind != RunGapKind.positionLoss) continue;
      final gStart = g.start;
      final gEnd = g.end ?? now;
      for (final m in moving) {
        final from = m.start.isAfter(gStart) ? m.start : gStart;
        final to = m.end.isBefore(gEnd) ? m.end : gEnd;
        if (to.isAfter(from)) sum += to.difference(from);
      }
    }
    return sum;
  }

  // PAR-004: Lücke ab "länger als" gapMaxDuration; löst nie eine Pause aus.
  void _checkLoss(DateTime now) {
    final ref = _gapRef;
    if (_lossOpen || ref == null) return;
    if (now.difference(ref) > parameters.gapMaxDuration) {
      _openLoss(ref);
    }
  }

  void _openLoss(DateTime ref) {
    _lossOpen = true;
    _lossStart = ref;
    _gaps.add(RecordedGap(kind: RunGapKind.positionLoss, start: ref));
    _emit(RecordingEventKind.positionLossStarted, ref);
  }

  void _closeLoss(DateTime end) {
    if (!_lossOpen) return;
    _lossOpen = false;
    final i = _gaps.lastIndexWhere(
      (g) => g.kind == RunGapKind.positionLoss && g.end == null,
    );
    _gaps[i] = RecordedGap(
      kind: RunGapKind.positionLoss,
      start: _lossStart!,
      end: end,
    );
    _emit(RecordingEventKind.positionLossEnded, end);
  }

  void _closeManualGap(DateTime end) {
    final i = _gaps.lastIndexWhere(
      (g) => g.kind == RunGapKind.manualPause && g.end == null,
    );
    _gaps[i] = RecordedGap(
      kind: RunGapKind.manualPause,
      start: _gaps[i].start,
      end: end,
    );
  }

  void _emit(RecordingEventKind k, DateTime t) =>
      _events.add(RecordingEvent(k, t));
}
