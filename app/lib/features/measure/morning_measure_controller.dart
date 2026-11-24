import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter/foundation.dart';

import 'device_info.dart';
import 'morning_belt.dart';
import 'resting_measure_controller.dart';

/// Stellen im Ablauf der Morgenmessung, an denen Teil E (Gurt-RR, WP33) die
/// Zeitfenster markiert: Die Gurt-RR gehört von [onRestStarted] bis
/// [onMeasurementEnded] zur Messung. Beide Rückrufe bekommen die Zeit (UTC).
/// Teil C setzt sie nicht; ohne Rückruf passiert nichts.
class MorningMeasureHooks {
  const MorningMeasureHooks({
    this.onRestStarted,
    this.onMeasurementStarted,
    this.onMeasurementEnded,
  });

  /// Die Ruhephase beginnt (einmal je Aufnahme mit Ruhephase, also auch bei
  /// „Noch einmal messen“, das wieder mit der Ruhephase beginnt).
  final void Function(DateTime at)? onRestStarted;

  /// Eine neue Aufnahme beginnt ohne vorangehende Ruhephase: die Messung nach
  /// übersprungener Ruhe.
  final void Function(DateTime at)? onMeasurementStarted;

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

  /// Gespeichert, aber heute zählt in der Reihe schon eine andere Messung
  /// (wählbar über [MorningMeasureController.chooseInstead]).
  notCounted,

  /// Verworfen: zu ungenau, nichts gespeichert.
  unusable,

  /// Speichern fehlgeschlagen.
  saveFailed,
}

/// Ablauf der Morgenmessung (FR-0215, PAR-160K, K66): Haltung (liegend als
/// Vorgabe), Ruhephase von [morningRestSeconds] (überspringbar, [skipRest]),
/// Aufnahme bis 120 s mit Fenstersuche ([RestingMeasureController] als
/// [engine] mit `searchWindow`: Ende, sobald ein 60-s-Fenster „gut“ erreicht,
/// Ergebnis das beste Fenster), Speichern über [MorningStore], freiwillige
/// Schlafstufe. Gespeichert wird jede Messung mit Puls (auch außerhalb des
/// Fensters, dann ohne Wirkung auf die Reihe) mit Fenster und Vermerk
/// „übersprungen“; „unbrauchbar“ wird verworfen, im Entwicklermodus (K68)
/// aber gespeichert, dann auch mit dem Kamera-Rohsignal (K70). Keine Werte in
/// Logs.
class MorningMeasureController extends ChangeNotifier {
  MorningMeasureController({
    required PpgCamera camera,
    required this.store,
    required this.windowStore,
    required this.clock,
    required this.device,
    this.hooks = const MorningMeasureHooks(),
    this.belt,
    RestingMeasureSignal? signal,
    PpgEvaluate? evaluate,
    PpgBestEvaluate? evaluateBest,
    PpgRecordingCheckRun? check,
    this.developerMode,
    Future<PpgCameraRef?> Function()? cameraChoice,
    Future<({Set<PpgCameraDiagnostic> diagnostics, bool ispFrames})> Function()?
    cameraDiagnostics,
    bool autoTick = true,
    this.validationState = ppgValidationState,
    this.marksFor,
  }) : engine = RestingMeasureController(
         camera: camera,
         clock: clock,
         signal: signal,
         evaluate: evaluate,
         evaluateBest: evaluateBest,
         check: check,
         searchWindow: true,
         cameraChoice: cameraChoice,
         cameraDiagnostics: cameraDiagnostics,
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

  /// Gurt-RR (nur Entwicklermodus); `null` ohne Quelle. Die Stellen des
  /// Ablaufs ruft der Controller selbst auf, die Pakete gehen mit der
  /// gespeicherten Messung in den Speicher.
  final MorningBelt? belt;

  /// Entwicklermodus der Einstellungen (wird beim Speichern gelesen); `null`
  /// oder Fehler heißt aus. Nur im Modus werden unbrauchbare Messungen und das
  /// Rohsignal gespeichert (K68, K70).
  final Future<bool> Function()? developerMode;

  /// Hinweis „Pulsgurt verbunden“ zeigen (Einstieg, Ruhephase).
  bool get beltHint => belt?.hintVisible ?? false;

  /// Markierungen (nach K-1) für RMSSD des Ergebnisses; `null` ohne Quelle.
  final Future<MorningTrendMarks> Function(RestingPosture posture)? marksFor;

  /// Validierungsstand für das Merkmal „vor der Validierung gemessen“.
  final Map<ValidationQuantity, ValidationState> validationState;

  late RestingMeasurePhase _lastPhase;
  DateTime? _measureStartedAt;

  /// Die Ruhe wurde übersprungen; die Messung beginnt dann neu (Gurt-Fenster).
  bool _restSkipping = false;
  bool _disposed = false;
  int _generation = 0;

  MorningOutcome _outcome = MorningOutcome.pending;
  MorningMeasurement? _stored;
  int? _storedId;
  MorningTrendMarks? _marks;
  bool _sleepFailed = false;
  bool _savingSleep = false;
  bool _choosing = false;
  bool _chooseFailed = false;
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

  /// Die Wahl als gültige Messung wird gerade gespeichert.
  bool get choosing => _choosing;

  /// Die Wahl ließ sich nicht speichern; die Wahl bleibt, wie sie war.
  bool get chooseFailed => _chooseFailed;
  SleepBand? get sleepBand => _stored?.sleepBand;

  /// Zeitpunkt der gespeicherten Messung (UTC) und ihr Versatz.
  DateTime? get measuredAt => _stored?.measuredAt;

  /// „Noch einmal messen“ (FR-0215, Entscheidung des Maintainers
  /// 2026-11-21): im Morgenfenster nach jeder Messung (gut, eingeschränkt,
  /// zählt nicht, unbrauchbar), außerhalb des Fensters nur nach einer
  /// unbrauchbaren; nach fehlgeschlagenem Speichern nicht („Erneut
  /// speichern“).
  bool get canRepeat =>
      engine.phase == RestingMeasurePhase.result &&
      switch (_outcome) {
        MorningOutcome.unusable ||
        MorningOutcome.good ||
        MorningOutcome.limited ||
        MorningOutcome.notCounted => true,
        _ => false,
      };

  /// Beendet die Ruhephase sofort und startet die Messung; der Vermerk
  /// „übersprungen nach s“ kommt an die Messung.
  Future<void> skipRest() => engine.skipRest();

  /// Neuer Ablauf wie beim ersten Start: Einstieg mit der zuletzt gewählten
  /// Haltung, dann die normale Ruhephase ([morningRestSeconds], überspringbar
  /// mit Vermerk, PAR-160K). Ob die neue Messung zählt, regelt
  /// [countingMorningMeasurements].
  Future<void> repeat() async {
    if (!canRepeat) return;
    engine.restart();
  }

  /// „Diese Messung stattdessen verwenden“ ([MorningOutcome.notCounted]):
  /// wählt die gespeicherte Messung als gültige des Tages
  /// ([MorningStore.choose]); danach ist das Ergebnis zählend (gut bzw.
  /// eingeschränkt). Scheitert das Speichern, bleibt alles, wie es war.
  Future<void> chooseInstead() async {
    final id = _storedId;
    if (_outcome != MorningOutcome.notCounted || id == null || _choosing) {
      return;
    }
    final gen = _generation;
    _choosing = true;
    _chooseFailed = false;
    _notify();
    try {
      await store.choose(id);
      final all = await store.list();
      final self = all.firstWhere((e) => e.id == id).value;
      if (gen != _generation) return;
      _stored = self;
      _outcome = _outcomeOf(all.map((e) => e.value), self);
    } catch (_) {
      if (gen != _generation) return;
      _chooseFailed = true;
    } finally {
      _choosing = false;
      _notify();
    }
  }

  /// Ergebnis der gespeicherten Messung [self] nach der Regel der zählenden
  /// Messungen ([countingMorningMeasurements]) über alle gespeicherten
  /// Messungen [all] (einschließlich [self]).
  static MorningOutcome _outcomeOf(
    Iterable<MorningMeasurement> all,
    MorningMeasurement self,
  ) {
    if (self.outsideWindow) return MorningOutcome.outsideWindow;
    final counting = countingMorningMeasurements(all);
    if (!counting.any((c) => identical(c, self))) {
      return MorningOutcome.notCounted;
    }
    return self.quality == PpgQuality.good && self.rmssdMs != null
        ? MorningOutcome.good
        : MorningOutcome.limited;
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
          final at = clock.now().toUtc();
          hooks.onRestStarted?.call(at);
          belt?.hooks.onRestStarted?.call(at);
        case RestingMeasurePhase.measuring:
          if (prev == RestingMeasurePhase.starting) {
            _measureStartedAt = clock.now().toUtc();
            if (_restSkipping) {
              _restSkipping = false;
              hooks.onMeasurementStarted?.call(_measureStartedAt!);
              belt?.hooks.onMeasurementStarted?.call(_measureStartedAt!);
            }
          }
        case RestingMeasurePhase.result:
          final at = clock.now().toUtc();
          hooks.onMeasurementEnded?.call(at);
          belt?.hooks.onMeasurementEnded?.call(at);
          _outcome = MorningOutcome.pending;
          _stored = null;
          _storedId = null;
          unawaited(_handleResult());
        case RestingMeasurePhase.starting:
          _restSkipping =
              prev == RestingMeasurePhase.resting && engine.restSkipped;
          _outcome = MorningOutcome.pending;
          _stored = null;
          _storedId = null;
        case RestingMeasurePhase.entry:
          // „Noch einmal messen“: neuer Ablauf; das Ergebnis der vorigen
          // Messung gehört nicht mehr zur Seite.
          _generation++;
          _measureStartedAt = null;
          _restSkipping = false;
          _outcome = MorningOutcome.pending;
          _stored = null;
          _storedId = null;
          _marks = null;
          _sleepFailed = false;
          _chooseFailed = false;
          _choosing = false;
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
      var dev = false;
      try {
        dev = await developerMode?.call() ?? false;
      } catch (_) {
        dev = false;
      }
      final m = buildMorningMeasurement(
        result: r.measurement,
        measuredAt: started,
        utcOffset: clock.utcOffsetAt(started),
        posture: r.posture,
        deviceManufacturer: info.manufacturer,
        deviceModel: info.model,
        window: _window,
        validationState: validationState,
        windowStartS: r.windowStartSeconds,
        windowEndS: r.windowEndSeconds,
        restSkippedAfterS: r.restSkippedAfter == null
            ? null
            : r.restSkippedAfter!.inMilliseconds / 1000,
        keepUnusable: dev,
      );
      if (m == null) {
        if (gen != _generation) return;
        _outcome = MorningOutcome.unusable;
        _notify();
        return;
      }
      final raw = dev
          ? buildMorningRawSignal(
              r.frames,
              details: r.cameraDetails,
              camera: r.camera,
              cameras: r.camera == null ? const [] : await _cameraList(),
              ispFrames: r.ispFrames,
              diagnostics: r.cameraDiagnostics,
              awbVariant: r.awbVariant,
            )
          : null;
      if (!m.isUsable) {
        // Unbrauchbar (nur im Entwicklermodus gespeichert, K68): zählt nirgends,
        // die Messung gilt wie verworfen („Noch einmal“). Scheitert das
        // Speichern, ändert das am Ergebnis nichts.
        try {
          await store.add(
            m,
            beltPackets: belt?.packets ?? const [],
            rawSignal: raw,
          );
        } catch (_) {
          // Zugabe für die Auswertung; kein Fehlerzustand für die Messung.
        }
        if (gen != _generation) return;
        _outcome = MorningOutcome.unusable;
        _notify();
        return;
      }
      // Gültige Messung: der Recorder sammelt nicht weiter (Puffer wächst
      // sonst, solange die Ergebnisseite offen ist); „Noch einmal messen“
      // startet ihn mit der Ruhephase neu.
      unawaited(belt?.stop());
      final before = [for (final e in await store.list()) e.value];
      final id = await store.add(
        m,
        beltPackets: belt?.packets ?? const [],
        rawSignal: raw,
      );
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
      // Ob sie zählt, folgt aus der Regel über alle gespeicherten Messungen
      // samt dieser (PAR-160K), nicht aus einer eigenen Prüfung.
      _outcome = _outcomeOf([...before, m], m);
    } catch (_) {
      if (gen != _generation) return;
      // Auch ohne gültige Messung sammelt der Recorder nicht weiter; die Pakete
      // bleiben für „Erneut speichern“.
      unawaited(belt?.stop());
      _outcome = MorningOutcome.saveFailed;
    }
    _notify();
  }

  /// Kameraliste für die Brennweite der verwendeten Kamera (FR-0220); ein
  /// Fehler lässt sie nur unbekannt, die Messung wird trotzdem gespeichert.
  Future<List<PpgCameraInfo>> _cameraList() async {
    try {
      return await engine.camera.cameras();
    } catch (_) {
      return const [];
    }
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
        windowStartS: m.windowStartS,
        windowEndS: m.windowEndS,
        restSkippedAfterS: m.restSkippedAfterS,
        unusableReason: m.unusableReason,
        chosen: m.chosen,
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
