// ignore_for_file: prefer_initializing_formals
import 'dart:math' as math;

import '../../ports/clock.dart';
import '../../ports/heart_rate_sensor.dart';
import '../../ports/location.dart';
import '../../ports/storage_raw.dart';
import '../../ports/storage_runs.dart';
import '../preprocessing/gap_moving_time.dart';
import '../preprocessing/measurement.dart';
import '../preprocessing/movement_time_processor.dart';
import '../preprocessing/preprocessing_parameters.dart';
import '../preprocessing/run_preprocessor.dart';
import 'treadmill.dart';

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
    required this.positionLossMovingTime,
    required this.standstillDetected,
    required this.laps,
    required this.gaps,
    this.mode = RunMode.gps,
    this.beltSpeedMetersPerSecond,
    this.inclinePercent,
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

  /// Bewegungszeit innerhalb der GPS-Lücken (`movingTimeInPositionGaps`):
  /// läuft in [movingTime] mit, trägt aber keine gemessene Strecke. Im
  /// Stillstand (erkannte Pause) zählt eine Lücke nicht zur Bewegungszeit.
  /// Die Lücken folgen der Messzeit (Punktzeit, K18), die Marker in [gaps]
  /// der Uhrzeit des Eintreffens; bei verspäteten Punkten weichen beide
  /// ab. Für die Pace (K20) gilt die Messzeit.
  final Duration positionLossMovingTime;

  /// Stillstand erkannt (PAR-014, PAR-015), unabhängig von der Einstellung.
  final bool standstillDetected;
  final List<RecordedLap> laps;
  final List<RecordedGap> gaps;

  /// Art des Laufs (FR-0196). Im Modus `treadmill` ist [distanceMeters] das
  /// Integral der eingestellten Bandgeschwindigkeit über die aktive Zeit und
  /// [movingTime] die aktive Zeit mit Geschwindigkeit über 0.
  final RunMode mode;

  /// Aktuell eingestellte Bandgeschwindigkeit (m/s); nur im Laufbandmodus.
  final double? beltSpeedMetersPerSecond;

  /// Aktuell eingestellte Steigung (%); `null` = nicht angegeben oder GPS-Lauf.
  final double? inclinePercent;
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

  // Laufbandmodus (FR-0196, K57): Einstellungen in zeitlicher Reihenfolge,
  // Zeit ab Laufbeginn. Eine Einstellung gilt ab ihrem Zeitpunkt bis zur
  // nächsten.
  RunMode _mode = RunMode.gps;
  final List<BeltSetting> _belts = [];

  RunMode get mode => _mode;
  bool get _treadmill => _mode == RunMode.treadmill;

  /// Alle Einstellungen des Bands seit dem Start (auch die wiederhergestellten),
  /// in der Reihenfolge ihres Entstehens. Der Host speichert neue Einträge.
  List<BeltSetting> get beltSettings => List.unmodifiable(_belts);

  RecordingPhase get phase => _phase;
  bool get autoPauseEnabled => _autoPause && !_treadmill;
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

  /// Startet die Aufzeichnung. Im Modus `treadmill` ist die Startgeschwindigkeit
  /// ([beltSpeedMetersPerSecond], m/s, Pflicht) die erste Einstellung ab dem
  /// Start; ohne sie oder mit einem unzulässigen Wert wird abgelehnt.
  CommandResult start({
    RunMode mode = RunMode.gps,
    double? beltSpeedMetersPerSecond,
    double? inclinePercent,
  }) {
    if (_phase != RecordingPhase.idle) return CommandResult.rejected;
    final first = mode == RunMode.treadmill
        ? BeltSetting(
            offset: Duration.zero,
            speedMetersPerSecond: beltSpeedMetersPerSecond ?? double.nan,
            inclinePercent: inclinePercent,
          )
        : null;
    if (first != null && !isStorableBeltSetting(first)) {
      return CommandResult.rejected;
    }
    _mode = mode;
    if (first != null) _belts.add(first);
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

  /// Stellt eine unterbrochene Aufzeichnung wieder her (FR-0193): spielt die
  /// gespeicherten Werte in zeitlicher Reihenfolge durch die Vorverarbeitung
  /// (wie die Neuberechnung, `RunAnalysis`) und läuft ab [resumeAt] weiter.
  /// [gaps] enthält die Lücke `interruption` bis [resumeAt] schon; sie wirkt
  /// wie eine Pause: Es entsteht kein Segment über sie (keine geschätzte
  /// Strecke) und ihre Zeit zählt zur Gesamtzeit, nicht zur Bewegungszeit.
  /// Alle Lücken müssen geschlossen sein. Nur im Zustand `idle`; erzeugt keine
  /// Ereignisse, denn alles Wiederhergestellte steht schon im Speicher.
  ///
  /// Im Modus `treadmill` ([mode]) kommen Geschwindigkeit und Steigung aus
  /// `raw.beltSettings`; die Strecke ergibt sich wie im Lauf (die Unterbrechung
  /// zählt nicht). Ohne gespeicherte Einstellung gilt Geschwindigkeit 0.
  CommandResult restore({
    RunMode mode = RunMode.gps,
    required DateTime startedAt,
    required StoredRawData raw,
    required List<StoredGap> gaps,
    required List<StoredLap> laps,
    required DateTime resumeAt,
  }) {
    if (_phase != RecordingPhase.idle) return CommandResult.rejected;
    final pre = RunPreprocessor(start: startedAt, parameters: parameters);
    _mode = mode;
    if (_treadmill) {
      final sorted = [for (final b in raw.beltSettings) b]
        ..sort((a, b) {
          final c = a.value.offset.compareTo(b.value.offset);
          return c != 0 ? c : a.id.compareTo(b.id);
        });
      _belts.addAll(sorted.map((b) => b.value));
    }
    _startedAt = startedAt; // für die Rundenzeiten unten
    final events = <({DateTime at, int rank, void Function() apply})>[];
    void add(DateTime at, int rank, void Function() apply) =>
        events.add((at: at, rank: rank, apply: apply));
    for (final g in gaps) {
      final end = g.end ?? resumeAt;
      switch (g.kind) {
        case RunGapKind.manualPause:
        case RunGapKind.interruption:
          add(g.start, 2, () => pre.pause(g.start));
          add(end, 0, () => pre.resume(end));
        case RunGapKind.positionLoss:
        case RunGapKind.heartRateLoss:
          break;
      }
      _gaps.add(RecordedGap(kind: g.kind, start: g.start, end: end));
    }
    var lastMark = startedAt;
    var lastMarkMoving = Duration.zero;
    for (final l in laps) {
      add(l.markedAt, 1, () {
        final moving = _movingAt(pre, l.markedAt);
        _laps.add(
          RecordedLap(
            index: l.index,
            markedAt: l.markedAt,
            lapTime: l.lapTime,
            movingTime: moving - lastMarkMoving,
          ),
        );
        lastMark = l.markedAt;
        lastMarkMoving = moving;
      });
    }
    DateTime? lastPoint;
    for (final r in raw.positions) {
      add(r.value.time, 1, () => pre.addPosition(r.value));
      if (lastPoint == null || r.value.time.isAfter(lastPoint)) {
        lastPoint = r.value.time;
      }
    }
    for (final r in raw.heartRates) {
      add(r.value.time, 1, () => pre.addHeartRate(r.value));
    }
    for (final r in raw.altitudes) {
      add(r.value.time, 1, () => pre.addAltitude(r.value));
    }
    for (final r in raw.steps) {
      add(r.value.time, 1, () => pre.addSteps(r.value));
    }
    // Dart-Sortierung ist nicht stabil: Reihenfolge der Einfügung als Schlüssel.
    final indexed = [for (var i = 0; i < events.length; i++) (i, events[i])]
      ..sort((a, b) {
        final c = a.$2.at.compareTo(b.$2.at);
        if (c != 0) return c;
        final r = a.$2.rank.compareTo(b.$2.rank);
        return r != 0 ? r : a.$1.compareTo(b.$1);
      });
    for (final e in indexed) {
      e.$2.apply();
    }
    _pre = pre;
    _startedAt = startedAt;
    _activeSince = resumeAt;
    _gapRef = resumeAt;
    _lastMark = lastMark;
    _lastMarkMoving = lastMarkMoving;
    _lastPointTime = lastPoint;
    _phase = RecordingPhase.running;
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
    final moving = _movingAt(_pre!, now);
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
    // Das Laufband hat keine Positionen (FR-0196): nichts annehmen, nichts
    // speichern, keine Lücke, keine Autopause.
    if (_treadmill) {
      return _phase == RecordingPhase.finished
          ? Intake.ignoredFinished
          : Intake.ignoredNotActive;
    }
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
      RawHeartRate(
        time: r.time,
        source: r.deviceId,
        bpm: r.beatsPerMinute,
        contact: r.contact,
      ),
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
    final belt = _treadmill ? _beltTotals(now) : null;
    final snapshot = RecordingSnapshot(
      mode: _mode,
      beltSpeedMetersPerSecond: _treadmill
          ? _belts.lastOrNull?.speedMetersPerSecond ?? 0
          : null,
      inclinePercent: _treadmill ? _belts.lastOrNull?.inclinePercent : null,
      phase: _phase,
      autoPauseEnabled: autoPauseEnabled,
      startedAt: _startedAt,
      endedAt: _endedAt,
      totalTime: r.movement.totalTime,
      movingTime: belt?.moving ?? r.movement.movingTime,
      distanceMeters: belt?.meters ?? r.position.distanceMeters,
      heartRateBpm: _phase == RecordingPhase.finished
          ? null
          : pre.heartRateAt(now).value?.bpm,
      positionLost: _lossOpen,
      positionLossMovingTime: _treadmill
          ? Duration.zero
          : movingTimeInPositionGaps(r),
      standstillDetected:
          !_treadmill &&
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

  /// Ändert die Bandgeschwindigkeit (m/s) ab jetzt (FR-0196). Auch in der
  /// Pause möglich (gilt ab dem Zeitpunkt der Änderung, zählt aber erst nach
  /// dem Weiterlaufen). Abgelehnt: kein Laufbandlauf, nicht gestartet oder
  /// beendet, unzulässiger Wert.
  CommandResult setBeltSpeed(double metersPerSecond) =>
      _addBelt(metersPerSecond, null, keepSpeed: false);

  /// Ändert die Steigung (%) ab jetzt; `null` = nicht angegeben.
  CommandResult setIncline(double? percent) =>
      _addBelt(null, percent, keepSpeed: true);

  CommandResult _addBelt(
    double? speed,
    double? incline, {
    required bool keepSpeed,
  }) {
    if (!_treadmill || !(_active || _phase == RecordingPhase.paused)) {
      return CommandResult.rejected;
    }
    // Ohne Vorgänger (nach dem Wiederanlauf ohne gespeicherte Einstellung):
    // Geschwindigkeit 0 bzw. die angegebene, Steigung nur wenn angegeben.
    final cur = _belts.lastOrNull;
    final next = BeltSetting(
      offset: _offsetNow(),
      speedMetersPerSecond: keepSpeed
          ? (cur?.speedMetersPerSecond ?? 0)
          : speed!,
      inclinePercent: keepSpeed ? incline : cur?.inclinePercent,
    );
    if (!isStorableBeltSetting(next)) return CommandResult.rejected;
    if (cur != null &&
        next.speedMetersPerSecond == cur.speedMetersPerSecond &&
        next.inclinePercent == cur.inclinePercent) {
      return CommandResult.ok; // keine Änderung, keine Zeile
    }
    _belts.add(next);
    return CommandResult.ok;
  }

  /// Lebenszeichen im Laufbandmodus: hängt die aktuelle Einstellung
  /// unverändert mit dem jetzigen Offset erneut an (Strecke und Bewegungszeit
  /// bleiben gleich). Nur im aktiven Lauf mit vorhandener Einstellung.
  CommandResult beltHeartbeat() {
    final cur = _belts.lastOrNull;
    if (!_treadmill || !_active || cur == null) return CommandResult.rejected;
    _belts.add(
      BeltSetting(
        offset: _offsetNow(),
        speedMetersPerSecond: cur.speedMetersPerSecond,
        inclinePercent: cur.inclinePercent,
      ),
    );
    return CommandResult.ok;
  }

  /// Zeit ab Laufbeginn; springt die Uhr zurück, bleibt die Reihenfolge der
  /// Einstellungen erhalten (nie vor der letzten).
  Duration _offsetNow() {
    final off = _clock.now().difference(_startedAt!);
    final last = _belts.lastOrNull?.offset ?? Duration.zero;
    return off < last ? last : off;
  }

  /// Bewegungszeit bis [at] für Runden: im Laufbandmodus die Bandzeit.
  Duration _movingAt(RunPreprocessor pre, DateTime at) => _treadmill
      ? _beltTotals(at).moving
      : pre.result(at: at).movement.movingTime;

  /// Strecke und Bewegungszeit des Bands bis [to] (FR-0196): Integral der
  /// eingestellten Geschwindigkeit über die aktive Zeit, also ohne manuelle
  /// Pausen und ohne die Unterbrechung nach einem Absturz. Zeit mit
  /// Geschwindigkeit 0 zählt nicht als Bewegungszeit.
  ({double meters, Duration moving}) _beltTotals(DateTime to) {
    final start = _startedAt!;
    final pauses = [
      for (final g in _gaps)
        if (g.kind == RunGapKind.manualPause ||
            g.kind == RunGapKind.interruption)
          (g.start, g.end ?? to),
    ];
    var meters = 0.0;
    var movingUs = 0;
    for (var i = 0; i < _belts.length; i++) {
      final b = _belts[i];
      var a = start.add(b.offset);
      var e = i + 1 < _belts.length ? start.add(_belts[i + 1].offset) : to;
      if (e.isAfter(to)) e = to;
      if (!e.isAfter(a)) continue;
      var us = e.difference(a).inMicroseconds;
      for (final (ps, pe) in pauses) {
        final lo = ps.isAfter(a) ? ps : a;
        final hi = pe.isBefore(e) ? pe : e;
        if (hi.isAfter(lo)) us -= hi.difference(lo).inMicroseconds;
      }
      if (b.speedMetersPerSecond > 0) {
        meters += b.speedMetersPerSecond * us / Duration.microsecondsPerSecond;
        movingUs += us;
      }
    }
    return (meters: meters, moving: Duration(microseconds: movingUs));
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

  // PAR-004: Lücke ab "länger als" gapMaxDuration; löst nie eine Pause aus.
  void _checkLoss(DateTime now) {
    final ref = _gapRef;
    if (_treadmill || _lossOpen || ref == null) return;
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
