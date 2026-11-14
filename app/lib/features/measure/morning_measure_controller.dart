import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter/foundation.dart';

import 'device_info.dart';
import 'morning_trend_logic.dart';
import 'resting_measure_controller.dart';

/// Stellen im Ablauf der Morgenmessung, an denen Teil E (Gurt-RR, WP33) die
/// Zeitfenster markiert: Die Gurt-RR gehört von [onRestStarted] bis
/// [onMeasurementEnded] zur Messung. Beide Rückrufe bekommen die Zeit (UTC).
/// Teil C setzt sie nicht; ohne Rückruf passiert nichts.
class MorningMeasureHooks {
  const MorningMeasureHooks({this.onRestStarted, this.onMeasurementEnded});

  /// Die Ruhephase beginnt (einmal je Ablauf, nicht bei „Noch einmal“).
  final void Function(DateTime at)? onRestStarted;

  /// Die Aufnahme der Messung ist zu Ende (auch bei „Noch einmal“ erneut).
  final void Function(DateTime at)? onMeasurementEnded;
}

/// Wie die Messung am Ende zu werten ist (Design `Ergebnis`).
enum MorningOutcome {
  /// Noch kein Ergebnis oder es wird gerade gespeichert.
  pending,

  /// Gespeichert, Signal gut.
  good,

  /// Gespeichert, nur der Ruhepuls zählt (Signal eingeschränkt oder RMSSD
  /// nicht verwertbar).
  limited,

  /// Gespeichert, aber außerhalb des Morgenfensters: zählt nicht.
  outsideWindow,

  /// Gespeichert, aber heute zählt schon eine frühere Messung.
  notCounted,

  /// Verworfen: zu ungenau, nichts gespeichert.
  unusable,

  /// Speichern fehlgeschlagen.
  saveFailed,
}

/// Ablauf der Morgenmessung (FR-0215, PAR-160K): Haltung (liegend als Vorgabe),
/// feste Ruhephase von [morningRestSeconds], Messung mit dem unveränderten
/// Verfahren aus WP27 ([RestingMeasureController] als [engine]), Speichern
/// über [MorningStore], freiwillige Schlafstufe. Gespeichert wird jede
/// Messung mit Puls (auch außerhalb des Fensters, dann ohne Wirkung auf die
/// Reihe); verworfen wird „unbrauchbar“. Keine Werte in Logs.
class MorningMeasureController extends ChangeNotifier {
  MorningMeasureController({
    required PpgCamera camera,
    required this.store,
    required this.windowStore,
    required this.clock,
    required this.device,
    this.hooks = const MorningMeasureHooks(),
    RestingMeasureSignal? signal,
    PpgEvaluate? evaluate,
    bool autoTick = true,
    this.validationState = ppgValidationState,
    this.marksFor,
  }) : engine = RestingMeasureController(
         camera: camera,
         clock: clock,
         signal: signal,
         evaluate: evaluate,
         autoTick: autoTick,
       ) {
    engine.setPosture(RestingPosture.lying);
    engine.setRestMinutes(morningRestSeconds ~/ 60);
    _lastPhase = engine.phase;
    engine.addListener(_onEngine);
  }

  /// Die Messung selbst (Ruhephase, Kamera, Auswertung), unverändert aus WP27.
  final RestingMeasureController engine;
  final MorningStore store;
  final MorningWindowStore windowStore;
  final Clock clock;
  final DeviceInfoReader device;
  final MorningMeasureHooks hooks;

  /// Markierungen (nach K-1) für RMSSD des Ergebnisses; `null` ohne Quelle.
  final Future<MorningTrendMarks> Function(RestingPosture posture)? marksFor;

  /// Validierungsstand für das Merkmal „vor der Validierung gemessen“.
  final Map<ValidationQuantity, ValidationState> validationState;

  late RestingMeasurePhase _lastPhase;
  DateTime? _measureStartedAt;
  bool _disposed = false;
  int _generation = 0;

  MorningOutcome _outcome = MorningOutcome.pending;
  MorningMeasurement? _stored;
  int? _storedId;
  MorningTrendMarks? _marks;
  bool _sleepFailed = false;
  bool _savingSleep = false;
  MorningWindow _window = MorningWindow.standard;

  MorningOutcome get outcome => _outcome;

  /// Markierungen für das Ergebnis (ohne Modus nach der Freischaltung); sonst `null`.
  MorningTrendMarks? get marks => _marks;

  /// Die gespeicherte Messung (mit Schlafstufe, sobald gewählt); sonst `null`.
  MorningMeasurement? get stored => _stored;

  /// Das Morgenfenster, mit dem bewertet wurde (für den Hinweistext).
  MorningWindow get window => _window;
  bool get sleepFailed => _sleepFailed;
  bool get savingSleep => _savingSleep;
  SleepBand? get sleepBand => _stored?.sleepBand;

  /// Zeitpunkt der gespeicherten Messung (UTC) und ihr Versatz.
  DateTime? get measuredAt => _stored?.measuredAt;

  /// „Noch einmal messen“ nur bei verworfener Messung (zu ungenau), ohne
  /// neue Ruhephase; sonst nie (Wiederholung nur bei zu schlechter Qualität).
  bool get canRepeat =>
      _outcome == MorningOutcome.unusable &&
      engine.phase == RestingMeasurePhase.result;

  Future<void> repeat() async {
    if (!canRepeat) return;
    await engine.retry(force: true);
  }

  /// Speichern erneut versuchen (nach [MorningOutcome.saveFailed]).
  Future<void> retrySave() async {
    if (_outcome != MorningOutcome.saveFailed) return;
    await _handleResult();
  }

  void _onEngine() {
    final phase = engine.phase;
    final prev = _lastPhase;
    _lastPhase = phase;
    if (phase != prev) {
      switch (phase) {
        case RestingMeasurePhase.resting:
          hooks.onRestStarted?.call(clock.now().toUtc());
        case RestingMeasurePhase.measuring:
          if (prev == RestingMeasurePhase.starting) {
            _measureStartedAt = clock.now().toUtc();
          }
        case RestingMeasurePhase.result:
          hooks.onMeasurementEnded?.call(clock.now().toUtc());
          _outcome = MorningOutcome.pending;
          _stored = null;
          _storedId = null;
          unawaited(_handleResult());
        case RestingMeasurePhase.starting:
          _outcome = MorningOutcome.pending;
          _stored = null;
          _storedId = null;
        default:
      }
    }
    _notify();
  }

  Future<void> _handleResult() async {
    final r = engine.result;
    if (r == null) return;
    final gen = ++_generation;
    final started = _measureStartedAt ?? r.measuredAt;
    try {
      final info = await device();
      _window = await windowStore.read();
      final m = buildMorningMeasurement(
        result: r.measurement,
        measuredAt: started,
        utcOffset: clock.utcOffsetAt(started),
        posture: r.posture,
        deviceManufacturer: info.manufacturer,
        deviceModel: info.model,
        window: _window,
        validationState: validationState,
      );
      if (m == null) {
        if (gen != _generation) return;
        _outcome = MorningOutcome.unusable;
        _notify();
        return;
      }
      final before = [for (final e in await store.list()) e.value];
      final counts =
          !m.outsideWindow &&
          morningRepeatAllowed(
            before,
            nowUtc: m.measuredAt,
            utcOffset: m.utcOffset,
            series: MorningSeriesKey(
              m.posture,
              m.deviceManufacturer,
              m.deviceModel,
            ),
          );
      final id = await store.add(m);
      if (gen != _generation) return;
      _marks = null;
      try {
        _marks = await marksFor?.call(m.posture);
      } catch (_) {
        // Markierung ist Zugabe; ohne sie bleibt das Ergebnis gespeichert.
      }
      if (gen != _generation) return;
      _stored = m;
      _storedId = id;
      _outcome = m.outsideWindow
          ? MorningOutcome.outsideWindow
          : !counts
          ? MorningOutcome.notCounted
          : m.quality == PpgQuality.good && m.rmssdMs != null
          ? MorningOutcome.good
          : MorningOutcome.limited;
    } catch (_) {
      if (gen != _generation) return;
      _outcome = MorningOutcome.saveFailed;
    }
    _notify();
  }

  /// Trägt die Schlafstufe nach; dieselbe Stufe noch einmal wählt sie ab.
  Future<void> setSleepBand(SleepBand band) async {
    final id = _storedId;
    final m = _stored;
    if (id == null || m == null || _savingSleep) return;
    final next = m.sleepBand == band ? null : band;
    _savingSleep = true;
    _sleepFailed = false;
    _notify();
    try {
      await store.setSleepBand(id, next);
      _stored = MorningMeasurement(
        measuredAt: m.measuredAt,
        utcOffset: m.utcOffset,
        posture: m.posture,
        deviceManufacturer: m.deviceManufacturer,
        deviceModel: m.deviceModel,
        method: m.method,
        methodVersion: m.methodVersion,
        quality: m.quality,
        restingHrBpm: m.restingHrBpm,
        rmssdMs: m.rmssdMs,
        timingNoiseMs: m.timingNoiseMs,
        sleepBand: next,
        cameraIntervalsMs: m.cameraIntervalsMs,
        beforeValidation: m.beforeValidation,
        outsideWindow: m.outsideWindow,
      );
    } catch (_) {
      _sleepFailed = true;
    } finally {
      _savingSleep = false;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    engine.removeListener(_onEngine);
    engine.dispose();
    super.dispose();
  }
}
