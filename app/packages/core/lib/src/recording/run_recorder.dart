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

/// Höchstzahl Zeilen je Transaktion (ADR-0005 Punkt 5, Startwert R005: eine
/// Zeile). Sie gilt für Position, Höhe und Puls zusammen; ein Messpunkt mit
/// Höhe sind also zwei Transaktionen. Die endgültige Größe legt WP08 fest.
const int rawBatchRows = 1;

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
  Future<int>? _lossGap;
  Future<int>? _pauseGap;

  final List<RawPosition> _positions = [];
  final List<RawAltitude> _altitudes = [];
  final List<RawHeartRate> _heartRates = [];

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
  Future<CommandResult> start() async {
    if (_starting || _session.phase != RecordingPhase.idle) {
      return CommandResult.rejected;
    }
    _starting = true;
    try {
      final run = await _runs.create(startedAt: _clock.now());
      _runId = run.id;
      _session.start();
      _processEvents();
      return CommandResult.ok;
    } finally {
      _starting = false;
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
    await _write(() async {
      await _flush();
      await _runs.setState(_runId!, RunState.finished, endedAt: endedAt);
    });
    return r;
  }

  /// Nimmt einen Standortpunkt an. Gespeichert wird, was die Sitzung annimmt
  /// (auch in der erkannten Pause); in der manuellen Pause und nach dem Ende
  /// nichts. Fehlende Werte bleiben `null`; nicht endliche Werte werden zu
  /// `null`, ein nicht endlicher Ort wird nicht gespeichert.
  Intake addPosition(LocationSample s) {
    final intake = _session.addPosition(s);
    _processEvents();
    if (intake != Intake.processed) return intake;
    if (s.latitude.isFinite && s.longitude.isFinite) {
      _positions.add(
        RawPosition(
          time: s.time,
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
          time: s.time,
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
      RawHeartRate(time: r.time, source: r.deviceId, bpm: r.beatsPerMinute),
    );
    _flushIfFull();
    return intake;
  }

  /// Prüft die GPS-Lücke gegen die Uhr (Anzeigetakt des Hosts).
  void tick() {
    _session.tick();
    _processEvents();
  }

  RecordingSnapshot snapshot() {
    final s = _session.snapshot();
    _processEvents();
    return s;
  }

  RunPreprocessing? preprocessing() => _session.preprocessing();

  /// Wartet, bis alles bisher Angenommene geschrieben ist (oder gescheitert).
  Future<void> flush() => _write(_flush);

  // ------------------------------------------------------------- intern

  static double? _finite(double? v) => v != null && v.isFinite ? v : null;

  int get _pendingRows =>
      _positions.length + _altitudes.length + _heartRates.length;

  void _flushIfFull() {
    if (_pendingRows >= _batchRows) {
      unawaited(_write(_flush).catchError((Object _) {}));
    }
  }

  /// Schreibt den Puffer in Stapeln von höchstens `batchRows` Zeilen (je
  /// Kanal in Reihenfolge). Läuft nur in der Warteschlange.
  Future<void> _flush() async {
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
      );
      try {
        await _raw.append(_runId!, batch);
      } on StorageException catch (e) {
        if (e.failure == StorageFailure.failed) {
          // Wiederholbar: vor die neueren Werte zurück, Reihenfolge bleibt.
          _positions.insertAll(0, batch.positions);
          _altitudes.insertAll(0, batch.altitudes);
          _heartRates.insertAll(0, batch.heartRates);
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

  Future<int> _openGap(RunGapKind kind, DateTime start) {
    final id = Completer<int>();
    final runId = _runId!;
    unawaited(
      _write(
        () async => id.complete(await _markers.openGap(runId, kind, start)),
      ).catchError((Object e, StackTrace st) => id.completeError(e, st)),
    );
    // Fehler hier meldet schon _write über lastWriteFailure.
    id.future.ignore();
    return id.future;
  }

  void _closeGap(Future<int>? gap, DateTime end) {
    if (gap == null) return;
    unawaited(
      _write(() async => _markers.closeGap(await gap, end))
          .catchError((Object _) {}),
    );
  }
}
