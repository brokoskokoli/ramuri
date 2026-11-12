// ignore_for_file: prefer_initializing_formals
import 'dart:async';

import '../../ports/clock.dart';
import '../../ports/heart_rate_sensor.dart';
import '../../ports/location.dart';
import '../../ports/storage.dart';
import '../../ports/storage_raw.dart';
import '../../ports/storage_runs.dart';
import '../preprocessing/measurement.dart';
import '../preprocessing/run_preprocessor.dart';
import 'recording_session.dart';
import 'run_recovery.dart';
import 'treadmill.dart';

/// Höchstzahl Zeilen je Transaktion (ADR-0005 Punkt 5; R005: eine Zeile, WP08
/// bestätigt). Sie gilt für Position, Höhe und Puls zusammen; ein Messpunkt mit
/// Höhe sind also zwei Transaktionen. Mit `synchronous = FULL` (WP02) bleibt
/// bei einem Kill höchstens die laufende Zeile aus.
const int rawBatchRows = 1;

/// Abstand der Lebenszeichen im Laufbandmodus: die aktuelle Einstellung wird
/// unverändert erneut angehängt (FR-0193/FR-0196).
const Duration beltHeartbeatInterval = Duration(seconds: 30);

/// Verbindet [RecordingSession] mit dem Speicherzugriff (WP06 Teil C).
///
/// Die Sitzung entscheidet sofort und synchron; alle Schreibvorgänge laufen
/// danach in genau der Reihenfolge der Aufrufe durch eine einzige Warteschlange.
/// Damit gilt ohne weitere Sperre:
/// - `append` (prüft den Laufzustand nicht) kommt nie nach dem Zustand
///   `finished`: Werte nach `finish()` weist die Sitzung ab, Werte davor
///   werden vor dem Zustandswechsel geschrieben.
/// - Pause und Fortsetzen während eines laufenden Schreibens werden nach ihm
///   und in ihrer Reihenfolge geschrieben.
///
/// Schreibt der Speicher nicht, bleibt der Arbeitsspeicher die Wahrheit der
/// Anzeige; [lastWriteFailure] meldet den Fehler. Ein Stapel mit `failed` wird
/// mit dem nächsten Schreiben erneut versucht, ein abgelehnter (`rejected`,
/// `notFound`) wird verworfen, weil er nie gelingen kann.
class RunRecorder {
  RunRecorder({
    required Clock clock,
    required RunStore runs,
    required RawDataStore rawData,
    required RunMarkerStore markers,
    RecordingSession? session,
    String positionSource = 'gps',
    int batchRows = rawBatchRows,
  }) : _clock = clock,
       _runs = runs,
       _raw = rawData,
       _markers = markers,
       _session = session ?? RecordingSession(clock: clock),
       _source = positionSource,
       _batchRows = batchRows < 1 ? 1 : batchRows;

  final Clock _clock;
  final RunStore _runs;
  final RawDataStore _raw;
  final RunMarkerStore _markers;
  final RecordingSession _session;
  final String _source;
  final int _batchRows;

  int? _runId;
  bool _starting = false;
  Future<void> _tail = Future<void>.value();
  int _eventCursor = 0;
  _GapRecord? _lossGap;
  _GapRecord? _pauseGap;

  /// Lückenmarken, die im Speicher noch nicht vollständig (geöffnet und, falls
  /// beendet, geschlossen) stehen; sie werden mit dem nächsten Schreiben
  /// nachgeholt wie die Rohwerte.
  final List<_GapRecord> _unsyncedGaps = [];

  final List<RawPosition> _positions = [];
  final List<RawAltitude> _altitudes = [];
  final List<RawHeartRate> _heartRates = [];
  final List<RrPacket> _rrPackets = [];
  int _beltCursor = 0; // Einstellungen der Sitzung, die schon im Puffer sind
  final List<BeltSetting> _belts = [];
  DateTime? _lastBeltAt; // letztes Anhängen einer Einstellung (Lebenszeichen)

  StorageFailure? _lastWriteFailure;

  /// Id des Laufs im Speicher; `null` vor dem Start.
  int? get runId => _runId;
  RecordingPhase get phase => _session.phase;

  /// Art des letzten fehlgeschlagenen Schreibvorgangs (nie Inhalte).
  StorageFailure? get lastWriteFailure => _lastWriteFailure;

  void setAutoPause(bool enabled) {
    _session.setAutoPause(enabled);
    _processEvents();
  }

  /// Legt den Lauf (Zustand `active`) an und startet die Sitzung. Scheitert
  /// das Anlegen, wirft der Aufruf die [StorageException] und die Sitzung
  /// bleibt ungestartet; ein erneuter Aufruf ist möglich. Die Startzeit des
  /// Laufs im Speicher ist die Uhr beim Anlegen, die der Sitzung die Uhr
  /// unmittelbar danach (gleich bei fester Uhr).
  /// Startet den Lauf. Im Modus `treadmill` ist die Startgeschwindigkeit
  /// ([beltSpeedMetersPerSecond], m/s) Pflicht; ohne sie oder mit einem
  /// unzulässigen Wert wird abgelehnt, bevor ein Lauf angelegt wird.
  Future<CommandResult> start({
    RunMode mode = RunMode.gps,
    double? beltSpeedMetersPerSecond,
    double? inclinePercent,
  }) async {
    if (_starting || _session.phase != RecordingPhase.idle) {
      return CommandResult.rejected;
    }
    _starting = true;
    try {
      if (mode == RunMode.treadmill &&
          !isStorableBeltSetting(
            BeltSetting(
              offset: Duration.zero,
              speedMetersPerSecond: beltSpeedMetersPerSecond ?? double.nan,
              inclinePercent: inclinePercent,
            ),
          )) {
        return CommandResult.rejected;
      }
      final run = await _runs.create(startedAt: _clock.now(), mode: mode);
      _runId = run.id;
      final r = _session.start(
        mode: mode,
        beltSpeedMetersPerSecond: beltSpeedMetersPerSecond,
        inclinePercent: inclinePercent,
      );
      if (r == CommandResult.rejected) return r;
      _processEvents();
      _takeBelts();
      if (_belts.isNotEmpty) {
        // Die erste Einstellung ist Pflicht (K57): erst melden, wenn der
        // Versuch beendet ist. Scheitert das Speichern, läuft der Lauf weiter:
        // der Fehler steht in lastWriteFailure, die Zeile bleibt im Puffer
        // (failed) und kommt mit dem nächsten Flush.
        try {
          await _write(_flush);
        } on StorageException {
          // gemerkt in _lastWriteFailure
        }
      }
      return CommandResult.ok;
    } finally {
      _starting = false;
    }
  }

  /// Setzt einen unterbrochenen Lauf fort (FR-0193): derselbe Lauf, die Zeit
  /// vom letzten gespeicherten Zeitpunkt bis jetzt ist die Lücke
  /// `interruption`. Offene Lücken (Pause, GPS) werden am letzten Zeitpunkt
  /// geschlossen, ein pausierter Lauf wird wieder `active`. Liegt die Uhr vor
  /// dem letzten Zeitpunkt (Uhr zurück), ist die Lücke leer (Anfang = Ende)
  /// und Punkte gelten erst, wenn die Uhr ihn überschreitet; die Lücke wird
  /// nie negativ. Gespeichert wird zuerst, die Sitzung danach: scheitert das
  /// Schreiben, bleibt der Lauf unverändert fortsetzbar.
  Future<CommandResult> restore(int runId) async {
    if (_starting || _session.phase != RecordingPhase.idle) {
      return CommandResult.rejected;
    }
    _starting = true;
    try {
      final run = await _runs.get(runId);
      if (run == null || run.state == RunState.finished) {
        return CommandResult.rejected;
      }
      final raw0 = await _raw.read(runId);
      final gaps0 = await _markers.gaps(runId);
      final laps = await _markers.laps(runId);
      final last = lastRecordedTime(run, raw0, gaps0, laps);
      final now = _clock.now();
      final resumeAt = now.isBefore(last) ? last : now;
      for (final g in gaps0) {
        if (g.end == null) await _markers.closeGap(g.id, last);
      }
      final id = await _markers.openGap(runId, RunGapKind.interruption, last);
      await _markers.closeGap(id, resumeAt);
      if (run.state == RunState.paused) {
        await _runs.setState(runId, RunState.active);
      }
      final gaps = await _markers.gaps(runId);
      final r = _session.restore(
        mode: run.mode,
        startedAt: run.startedAt,
        raw: raw0,
        gaps: gaps,
        laps: laps,
        resumeAt: resumeAt,
      );
      if (r == CommandResult.ok) {
        _runId = runId;
        _eventCursor = _session.events.length;
        _beltCursor = _session.beltSettings.length; // schon gespeichert
        _lastBeltAt = now;
      }
      return r;
    } finally {
      _starting = false;
    }
  }

  /// Ändert die Bandgeschwindigkeit (m/s) ab jetzt und speichert die Änderung.
  Future<CommandResult> setBeltSpeed(double metersPerSecond) =>
      _belt(() => _session.setBeltSpeed(metersPerSecond));

  /// Ändert die Steigung (%) ab jetzt; `null` = nicht angegeben.
  Future<CommandResult> setIncline(double? percent) =>
      _belt(() => _session.setIncline(percent));

  Future<CommandResult> _belt(CommandResult Function() change) async {
    final r = change();
    if (r == CommandResult.rejected) return r;
    _takeBelts();
    // Sofort schreiben (die Änderung ist selten und bestimmt die Strecke).
    await _write(_flush);
    return r;
  }

  void _takeBelts() {
    final all = _session.beltSettings;
    while (_beltCursor < all.length) {
      _belts.add(all[_beltCursor++]);
      _lastBeltAt = _clock.now();
    }
  }

  Future<CommandResult> pause() async {
    final r = _session.pause();
    if (r == CommandResult.rejected) return r;
    _processEvents();
    await _write(() async {
      await _flush();
      await _runs.setState(_runId!, RunState.paused);
    });
    return r;
  }

  Future<CommandResult> resume() async {
    final r = _session.resume();
    if (r == CommandResult.rejected) return r;
    _processEvents();
    await _write(() => _runs.setState(_runId!, RunState.active));
    return r;
  }

  Future<CommandResult> lap() async {
    final r = _session.lap();
    if (r == CommandResult.rejected) return r;
    _processEvents();
    final lap = _session.snapshot().laps.last.toStored();
    await _write(() async {
      await _flush();
      await _markers.addLap(_runId!, lap);
    });
    return r;
  }

  /// Beendet den Lauf. Alles, was die Sitzung vorher angenommen hat, wird
  /// geschrieben, bevor der Lauf `finished` wird.
  Future<CommandResult> finish() async {
    final r = _session.finish();
    if (r == CommandResult.rejected) return r;
    _processEvents();
    final endedAt = _session.snapshot().endedAt!;
    // Lokaler Versatz am Laufende (für den lokalen Kalendertag der Tageswerte),
    // über die Uhr, in ganzen Sekunden.
    final offset = Duration(seconds: _clock.utcOffsetAt(endedAt).inSeconds);
    await _write(() async {
      await _flush();
      await _runs.setState(
        _runId!,
        RunState.finished,
        endedAt: endedAt,
        endedUtcOffset: offset,
      );
    });
    return r;
  }

  /// Nimmt einen Standortpunkt an. Gespeichert wird, was die Sitzung annimmt
  /// (auch in der erkannten und in der manuellen Pause, dort ohne Einfluss auf
  /// die Auswertung; die Lücke `manualPause` kennzeichnet sie); vor dem Start
  /// und nach dem Ende nichts. Die Zeit ist die ausgerichtete Uhrzeit. Fehlende Werte bleiben `null`; nicht endliche Werte werden zu
  /// `null`, ein nicht endlicher Ort wird nicht gespeichert.
  Intake addPosition(LocationSample s) {
    final intake = _session.addPosition(s);
    _processEvents();
    if (intake != Intake.processed && intake != Intake.recordedWhilePaused) {
      return intake;
    }
    // Gleiche Zeitbasis wie Lauf, Lücken und Runden (Uhr, Empfang minus Alter).
    final time = _session.lastPointTime!;
    if (s.latitude.isFinite && s.longitude.isFinite) {
      _positions.add(
        RawPosition(
          time: time,
          source: _source,
          latitude: s.latitude,
          longitude: s.longitude,
          accuracyMeters: _finite(s.accuracyMeters),
          speedMetersPerSecond: _finite(s.speedMetersPerSecond),
          speedAccuracyMetersPerSecond: _finite(s.speedAccuracyMetersPerSecond),
          verticalAccuracyMeters: _finite(s.verticalAccuracyMeters),
        ),
      );
    }
    final alt = s.altitudeMeters;
    if (alt != null && alt.isFinite) {
      _altitudes.add(
        RawAltitude(
          time: time,
          source: _source,
          meters: alt,
          verticalAccuracyMeters: _finite(s.verticalAccuracyMeters),
        ),
      );
    }
    _flushIfFull();
    return intake;
  }

  Intake addHeartRate(HeartRateReading r) {
    final intake = _session.addHeartRate(r);
    _processEvents();
    if (intake != Intake.processed) return intake;
    _heartRates.add(
      RawHeartRate(
        time: r.time,
        source: r.deviceId,
        bpm: r.beatsPerMinute,
        contact: r.contact,
      ),
    );
    // RR (FR-0213): nur gespeichert, nie ausgewertet. Derselbe Weg und Puffer
    // wie der Puls; ohne RR kein Paket. Herkunft = Gerät des Readings.
    if (r.rrIntervals.isNotEmpty) {
      _rrPackets.add(
        RrPacket(
          time: r.time,
          source: r.deviceId,
          intervals: List.unmodifiable(r.rrIntervals),
        ),
      );
    }
    _flushIfFull();
    return intake;
  }

  /// Prüft die GPS-Lücke gegen die Uhr (Anzeigetakt des Hosts).
  void tick() {
    _session.tick();
    _processEvents();
    _beltHeartbeat();
  }

  /// Im Laufbandmodus alle [beltHeartbeatInterval] die aktuelle Einstellung
  /// erneut anhängen, damit der letzte belegte Zeitpunkt nach einem Absturz
  /// nahe am Ende liegt (die Strecke bleibt bis dahin erhalten).
  void _beltHeartbeat() {
    if (_runId == null) return;
    final now = _clock.now();
    final since = _lastBeltAt;
    if (since == null || now.difference(since) < beltHeartbeatInterval) return;
    if (_session.beltHeartbeat() == CommandResult.rejected) return;
    _takeBelts();
    unawaited(_write(_flush).catchError((Object _) {}));
  }

  RecordingSnapshot snapshot() => observe().snapshot;

  /// Stand und Vorverarbeitung aus einem Aufbau (siehe
  /// [RecordingSession.observe]).
  ({RecordingSnapshot snapshot, RunPreprocessing? preprocessing}) observe() {
    final o = _session.observe();
    _processEvents();
    return o;
  }

  RunPreprocessing? preprocessing() => _session.preprocessing();

  /// Wartet, bis alles bisher Angenommene geschrieben ist (oder gescheitert).
  Future<void> flush() => _write(_flush);

  // ------------------------------------------------------------- intern

  static double? _finite(double? v) => v != null && v.isFinite ? v : null;

  int get _pendingRows =>
      _positions.length +
      _altitudes.length +
      _heartRates.length +
      _rrPackets.length +
      _belts.length;

  void _flushIfFull() {
    if (_pendingRows >= _batchRows) {
      unawaited(_write(_flush).catchError((Object _) {}));
    }
  }

  /// Schreibt den Puffer in Stapeln von höchstens `batchRows` Zeilen (je
  /// Kanal in Reihenfolge). Läuft nur in der Warteschlange.
  Future<void> _flush() async {
    await _syncGaps();
    while (_pendingRows > 0) {
      var room = _batchRows;
      List<T> take<T>(List<T> from) {
        final n = room < from.length ? room : from.length;
        room -= n;
        final out = from.sublist(0, n);
        from.removeRange(0, n);
        return out;
      }

      final batch = RawBatch(
        positions: take(_positions),
        altitudes: take(_altitudes),
        heartRates: take(_heartRates),
        rrPackets: take(_rrPackets),
        beltSettings: take(_belts),
      );
      try {
        await _raw.append(_runId!, batch);
      } on StorageException catch (e) {
        if (e.failure == StorageFailure.failed) {
          // Wiederholbar: vor die neueren Werte zurück, Reihenfolge bleibt.
          _positions.insertAll(0, batch.positions);
          _altitudes.insertAll(0, batch.altitudes);
          _heartRates.insertAll(0, batch.heartRates);
          _rrPackets.insertAll(0, batch.rrPackets);
          _belts.insertAll(0, batch.beltSettings);
        }
        rethrow;
      }
    }
  }

  /// Hängt einen Schreibvorgang an die Warteschlange. Fehler werden gemerkt
  /// und dem Aufrufer gemeldet, stoppen die Warteschlange aber nicht.
  Future<void> _write(Future<void> Function() op) {
    final done = Completer<void>();
    _tail = _tail.then((_) async {
      try {
        await op();
        done.complete();
      } on StorageException catch (e, st) {
        _lastWriteFailure = e.failure;
        done.completeError(e, st);
      } catch (e, st) {
        _lastWriteFailure = StorageFailure.failed;
        done.completeError(e, st);
      }
    });
    return done.future;
  }

  /// Überträgt neue Ereignisse der Sitzung in Lücken des Speichers (FR-0194).
  /// Die Autopause hat im Speicher keine Stelle (kein [RunGapKind]); sie wird
  /// nicht gespeichert.
  void _processEvents() {
    final events = _session.events;
    while (_eventCursor < events.length) {
      final e = events[_eventCursor++];
      switch (e.kind) {
        case RecordingEventKind.positionLossStarted:
          _lossGap = _openGap(RunGapKind.positionLoss, e.time);
        case RecordingEventKind.positionLossEnded:
          _closeGap(_lossGap, e.time);
          _lossGap = null;
        case RecordingEventKind.manualPaused:
          _pauseGap = _openGap(RunGapKind.manualPause, e.time);
        case RecordingEventKind.resumed:
        case RecordingEventKind.finished:
          // Ende aus der manuellen Pause schließt sie ohne eigenes Ereignis.
          _closeGap(_pauseGap, e.time);
          _pauseGap = null;
        case RecordingEventKind.started:
        case RecordingEventKind.autoPauseStarted:
        case RecordingEventKind.autoPauseEnded:
        case RecordingEventKind.lap:
          break;
      }
    }
  }

  _GapRecord _openGap(RunGapKind kind, DateTime start) {
    final gap = _GapRecord(_runId!, kind, start);
    _unsyncedGaps.add(gap);
    // Fehler meldet schon _write über lastWriteFailure.
    unawaited(_write(() => _syncGap(gap)).catchError((Object _) {}));
    return gap;
  }

  void _closeGap(_GapRecord? gap, DateTime end) {
    if (gap == null) return;
    gap.end = end;
    unawaited(_write(() => _syncGap(gap)).catchError((Object _) {}));
  }

  /// Bringt eine Lückenmarke auf den Stand der Sitzung: öffnen, falls noch
  /// nicht geschehen, und schließen, falls sie beendet ist. Scheitert ein
  /// Schritt mit `failed`, bleibt die Marke in [_unsyncedGaps] und wird beim
  /// nächsten Schreiben wiederholt; ein abgelehnter Schritt kann nie gelingen.
  Future<void> _syncGap(_GapRecord gap) async {
    if (gap.rejected) return;
    try {
      gap.id ??= await _markers.openGap(gap.runId, gap.kind, gap.start);
      final end = gap.end;
      if (end != null && !gap.closed) {
        await _markers.closeGap(gap.id!, end);
        gap.closed = true;
      }
    } on StorageException catch (e) {
      if (e.failure != StorageFailure.failed) {
        gap.rejected = true;
        _unsyncedGaps.remove(gap);
      }
      rethrow;
    }
    if (gap.end != null) _unsyncedGaps.remove(gap);
  }

  Future<void> _syncGaps() async {
    for (final gap in List.of(_unsyncedGaps)) {
      await _syncGap(gap);
    }
  }
}

/// Lücke im Arbeitsspeicher mit dem Stand ihrer Speicherung.
class _GapRecord {
  _GapRecord(this.runId, this.kind, this.start);
  final int runId;
  final RunGapKind kind;
  final DateTime start;
  DateTime? end;
  int? id;
  bool closed = false;

  /// Das Öffnen wurde abgelehnt: die Marke kann nie gespeichert werden.
  bool rejected = false;
}
