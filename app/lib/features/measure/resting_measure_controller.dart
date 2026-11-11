import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:core/core.dart';
import 'package:flutter/foundation.dart';

/// Vorgabe, Mindest- und Höchstdauer der Ruhephase in Minuten (FR-0214: Vorgabe
/// 5 min, Länge einstellbar; Bereich 1 bis 15 min laut Auftrag WP27).
const int restingDefaultRestMinutes = 5;
const int restingMinRestMinutes = 1;
const int restingMaxRestMinutes = 15;

/// Länge der Pulskurve in Sekunden (Entwurf „Pulskurve, letzte 5 s“).
const double restingCurveSeconds = 5.0;

/// Mindestabstand der Zwischenauswertungen für den laufenden Puls in Sekunden
/// Sensorzeit. Nur die Aktualisierungsrate der Anzeige, keine Schwelle der
/// Auswertung.
const double restingLiveIntervalSeconds = 1.0;

/// Länge des gleitenden Fensters der Zwischenauswertung in Sekunden Sensorzeit
/// (nur die Anzeige des laufenden Pulses; keine Schwelle der Auswertung). Das
/// Endergebnis wertet das volle Messfenster aus. Begrenzt die Rechenzeit je
/// Zwischenauswertung, die sonst mit der Messdauer wächst.
const double restingLiveWindowSeconds = 12.0;

/// Wanduhr-Frist in Sekunden, nach der ein Strom ohne jedes Bild als
/// unterbrochen gilt. Die Bildlücke selbst zählt allein in Sensorzeit
/// ([ppgMaxFrameGapSeconds]); die Wanduhr fängt nur ab, dass gar keine Bilder
/// mehr kommen, und ist deshalb großzügig: Sie darf nicht schon bei kurzen
/// Verzögerungen der App (Garbage Collection, Last) anschlagen.
const double restingNoImageTimeoutSeconds = 3.0;

/// Wanduhr-Frist in Sekunden vom Abonnieren des Kamerastroms bis zum
/// Ereignis „gestartet“ (oder dem ersten Bild). Kamera öffnen und Blitz
/// einschalten können auf manchen Geräten länger dauern als eine Bildlücke.
const double restingStartTimeoutSeconds = 5.0;

/// Ein Abstand der Wächter-Prüfungen über dieser Dauer (Wanduhr) gilt als
/// Stillstand der Ereignisschleife der App, nicht als Bildlücke.
const double restingStallToleranceSeconds = 1.0;

/// Ablaufphase der Ruhepuls-Messung (FR-0214).
enum RestingMeasurePhase {
  /// Haltung und Ruhephase wählen.
  entry,

  /// Ruhephase läuft (noch keine Kamera, kein Kamera-Recht).
  resting,

  /// Kamera-Recht wird angefragt, Kamera startet.
  starting,

  /// Bilder werden gesammelt (inklusive Einschwingen und Auswertung am Ende).
  measuring,

  /// Messung ausgewertet: Wert oder kein Wert.
  result,

  /// Beendet ohne Ergebnis, Kamera gestoppt; Grund in [RestingMeasureController.stopCause].
  stopped,

  /// Wert ins Profil übernommen.
  adopted,

  /// Wert verworfen.
  discarded,
}

/// Grund eines Abbruchs ohne Ergebnis.
enum RestingStopCause {
  userCancelled,
  background,
  permissionDenied,
  noCamera,
  noFlash,
  busy,
  disconnected,
  frameRate,
  cameraError,

  /// Messung unterbrochen: länger als [ppgMaxFrameGapSeconds] kein Bild.
  interrupted,
}

/// Hinweis während der Messung. Nur das, was die Auswertung in `core` als Grund
/// liefert (kein Hinweis auf „zu fest“, „verrutscht“ oder „zu dunkel“: dafür
/// gibt es in `core` keine Regel).
enum RestingLiveHint { weakSignal, flatSignal, disturbances }

/// Ergebnis einer ausgewerteten Messung.
class RestingMeasureResult {
  const RestingMeasureResult({
    required this.measurement,
    required this.measuredAt,
    required this.posture,
    required this.restElapsed,
  });

  final PpgMeasurement measurement;

  /// UTC, Ende der Messung.
  final DateTime measuredAt;
  final RestingPosture posture;

  /// Dauer der Ruhephase davor; `null` bei sofortiger Messung.
  final Duration? restElapsed;

  /// Ganzzahliger Puls; `null`: kein Wert (nur bei „unbrauchbar“).
  int? get bpm => measurement.hasResult ? measurement.bpm!.round() : null;
  bool get hasValue => bpm != null;
  PpgQuality get quality => measurement.quality;
  List<PpgQualityReason> get reasons => measurement.reasons;
}

/// Rückmeldung am Ende der Ruhephase (Ton oder Vibration), von der Oberfläche
/// bereitgestellt.
abstract interface class RestingMeasureSignal {
  Future<void> restEnded();
}

/// Auswertung der gesammelten Bilder; Vorgabe ist [evaluatePpg] auf einem
/// eigenen Isolate (Eingabe und Ergebnis nur Zahlen und Aufzählungen), damit
/// die Oberfläche nicht stillsteht.
typedef PpgEvaluate = Future<PpgMeasurement> Function(
  List<PpgFrame> frames,
  PpgWindow window,
);

Future<PpgMeasurement> _evaluateInIsolate(
  List<PpgFrame> frames,
  PpgWindow window,
) => Isolate.run(() => evaluatePpg(frames, window: window));

/// Steuert den Ablauf der Ruhepuls-Messung mit der Kamera (FR-0214) ohne
/// Widgets: Einstieg, Ruhephase, Messung, Ergebnis, Übernahme. Alles Rechnen
/// liegt in `core` ([evaluatePpg]); hier steht nur Zustand und Reihenfolge.
/// Das Kamera-Recht wird erst bei Messbeginn angefragt. Bilder bleiben im
/// Speicher und werden am Ende verworfen; es gibt keine Werte in Logs.
class RestingMeasureController extends ChangeNotifier {
  RestingMeasureController({
    required this.camera,
    required this.profile,
    required this.settings,
    required this.clock,
    this.signal,
    PpgEvaluate? evaluate,
    this.autoTick = true,
  }) : _evaluate = evaluate ?? _evaluateInIsolate;

  final PpgCamera camera;

  /// Speichert den übernommenen Ruhepuls; für die Neuberechnung der Zonen die
  /// Fassung mit Benachrichtigung der Neuberechnung übergeben (wie das Profil).
  final ProfileService profile;
  final SettingsStore settings;
  final Clock clock;
  final RestingMeasureSignal? signal;
  final PpgEvaluate _evaluate;

  /// Sekundentakt der Ruhephase; Tests schalten ihn aus und rufen [tick] selbst.
  final bool autoTick;

  RestingMeasurePhase _phase = RestingMeasurePhase.entry;
  RestingPosture _posture = RestingPosture.sitting;
  int _restMinutes = restingDefaultRestMinutes;
  Duration? _restStart;
  Duration? _restElapsed;
  Duration _restRemaining = Duration.zero;
  bool _pendingStart = false;
  bool _foreground = true;
  bool _disposed = false;
  Timer? _ticker;
  Timer? _gapTimer;
  Duration? _lastImageAt;
  Duration? _lastCheckAt;
  bool _cameraStarted = false;
  double? _lastImageT;

  int _run = 0;
  StreamSubscription<PpgCameraEvent>? _sub;
  final List<PpgFrame> _frames = [];
  double _elapsed = 0;
  bool _evaluating = false;
  int? _livePulse;
  PpgQuality? _liveQuality;
  RestingLiveHint? _liveHint;
  List<double> _curve = const [];
  double _lastLiveT = double.negativeInfinity;
  bool _liveBusy = false;

  RestingMeasureResult? _result;
  RestingStopCause? _stopCause;
  int? _previousRestingBpm;
  RestingHrOrigin? _previousOrigin;
  bool _adopting = false;
  ProfileValidation? _adoptRejection;
  bool _adoptFailed = false;
  bool _originMissing = false;

  RestingMeasurePhase get phase => _phase;
  RestingPosture get posture => _posture;
  int get restMinutes => _restMinutes;

  /// Restzeit der Ruhephase (Sekundentakt über [tick]).
  Duration get restRemaining => _restRemaining;

  /// Die Ruhephase ist um, die Messung wartet auf die Rückkehr in die App.
  bool get waitingForForeground => _pendingStart;

  /// Sekunden Sensorzeit seit Aufnahmebeginn (Uhr der Messung, läuft auch bei
  /// schlechtem Signal weiter).
  double get elapsedSeconds => _elapsed;

  /// Das Einschwingen (vor dem Messfenster) läuft noch.
  bool get settling => _elapsed < ppgStandardWindow.start;

  /// Fortschritt des Messfensters von 0 bis 1.
  double get progress {
    final w = ppgStandardWindow;
    return ((_elapsed - w.start) / (w.end - w.start)).clamp(0.0, 1.0);
  }

  /// Die Messzeit ist um, die Auswertung läuft.
  bool get evaluating => _evaluating;

  /// Laufender Puls (ganzzahlig) aus der Auswertung in `core`; `null`, solange
  /// sie keinen liefert.
  int? get livePulse => _livePulse;
  PpgQuality? get liveQuality => _liveQuality;
  RestingLiveHint? get liveHint => _liveHint;

  /// Rohkurve der letzten [restingCurveSeconds] (Rot, Mittelwert abgezogen,
  /// invertiert: Puls nach oben). Nicht die gefilterte Kurve der Auswertung.
  List<double> get curve => _curve;

  RestingMeasureResult? get result => _result;
  RestingStopCause? get stopCause => _stopCause;

  /// Bisheriger Ruhepuls im Profil und, falls mit der Kamera gemessen, dessen
  /// Herkunft (Stand beim Ergebnis); `null` Herkunft heißt „von Hand“.
  int? get previousRestingBpm => _previousRestingBpm;
  RestingHrOrigin? get previousOrigin => _previousOrigin;

  /// Die Prüfung des Profils hat die Übernahme abgelehnt (Wert außerhalb des
  /// Bereichs); es wurde nichts gespeichert.
  ProfileValidation? get adoptRejection => _adoptRejection;

  /// Speichern des Werts scheiterte; nichts wurde übernommen, erneut möglich.
  bool get adoptFailed => _adoptFailed;

  /// Der Wert ist übernommen, aber die Herkunft (Haltung, Zeitpunkt, Quelle)
  /// konnte nicht gespeichert werden; er gilt dann als von Hand eingetragen.
  bool get originMissing => _originMissing;
  bool get adopting => _adopting;

  /// „Noch einmal“: nur ohne Wert (kein Wert, oder Abbruch durch Kamera oder
  /// Hintergrund, nicht aber bei fehlendem Recht, fehlender Kamera oder
  /// fehlendem Blitz und nicht nach eigenem Abbruch). Ohne neue Ruhephase.
  bool get canRetry => switch (_phase) {
    RestingMeasurePhase.result => !(_result?.hasValue ?? true),
    RestingMeasurePhase.stopped => switch (_stopCause) {
      RestingStopCause.background ||
      RestingStopCause.busy ||
      RestingStopCause.disconnected ||
      RestingStopCause.frameRate ||
      RestingStopCause.cameraError ||
      RestingStopCause.interrupted => true,
      _ => false,
    },
    _ => false,
  };

  bool get canAdopt =>
      _phase == RestingMeasurePhase.result &&
      (_result?.hasValue ?? false) &&
      !_adopting;

  // Einstieg ---------------------------------------------------------------

  void setPosture(RestingPosture p) {
    if (_phase != RestingMeasurePhase.entry) return;
    _posture = p;
    _notify();
  }

  void setRestMinutes(int minutes) {
    if (_phase != RestingMeasurePhase.entry) return;
    _restMinutes = minutes.clamp(restingMinRestMinutes, restingMaxRestMinutes);
    _notify();
  }

  /// Startet die Ruhephase. Noch keine Kamera und kein Kamera-Recht.
  void startRest() {
    if (_phase != RestingMeasurePhase.entry) return;
    _phase = RestingMeasurePhase.resting;
    _restStart = clock.monotonic();
    _restRemaining = Duration(minutes: _restMinutes);
    if (autoTick) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) => tick());
    }
    _notify();
  }

  /// Misst sofort, ohne Ruhephase.
  Future<void> startNow() async {
    if (_phase != RestingMeasurePhase.entry) return;
    await _begin(restElapsed: null);
  }

  /// Beendet die Ruhephase vorzeitig und misst („Ich bin schon entspannt“).
  Future<void> skipRest() async {
    if (_phase != RestingMeasurePhase.resting) return;
    final elapsed = clock.monotonic() - _restStart!;
    _stopTicker();
    _pendingStart = false;
    await _begin(restElapsed: elapsed);
  }

  /// Aktualisiert die Restzeit; am Ende gibt es das Signal, danach beginnt die
  /// Messung (in einer Sitzung im Hintergrund erst bei der Rückkehr).
  void tick() {
    if (_phase != RestingMeasurePhase.resting || _pendingStart) return;
    final total = Duration(minutes: _restMinutes);
    final left = total - (clock.monotonic() - _restStart!);
    if (left > Duration.zero) {
      _restRemaining = left;
      _notify();
      return;
    }
    _restRemaining = Duration.zero;
    _stopTicker();
    final s = signal;
    if (s != null) {
      unawaited(s.restEnded().catchError((_) {}));
    }
    if (!_foreground) {
      _pendingStart = true;
      _notify();
      return;
    }
    unawaited(_begin(restElapsed: total));
  }

  // Messung ----------------------------------------------------------------

  /// Wanduhr-Wächter gegen einen Strom ohne Bilder (läuft ab dem Abonnieren
  /// im Viertelsekundentakt; Tests rufen es selbst): kein „gestartet“ binnen
  /// [restingStartTimeoutSeconds] ist ein Kamerafehler, danach länger als
  /// [restingNoImageTimeoutSeconds] kein Bild eine Unterbrechung. Die
  /// Bildlücke zwischen zwei Bildern prüft [_onFrame] in Sensorzeit. Ein
  /// langer Abstand zur vorigen Prüfung ist ein Stillstand der App: Die Frist
  /// beginnt dann neu, weil wartende Bilder erst nach der Prüfung eintreffen.
  void checkFrameGap() {
    final last = _lastImageAt;
    if (_phase != RestingMeasurePhase.measuring ||
        _evaluating ||
        last == null) {
      return;
    }
    final now = clock.monotonic();
    final prevCheck = _lastCheckAt;
    _lastCheckAt = now;
    if (prevCheck != null &&
        (now - prevCheck).inMicroseconds > restingStallToleranceSeconds * 1e6) {
      _lastImageAt = now;
      return;
    }
    final limit = _cameraStarted
        ? restingNoImageTimeoutSeconds
        : restingStartTimeoutSeconds;
    if ((now - last).inMicroseconds > limit * 1e6) {
      unawaited(
        _fail(
          _run,
          _cameraStarted
              ? RestingStopCause.interrupted
              : RestingStopCause.cameraError,
        ),
      );
    }
  }

  Future<void> _begin({required Duration? restElapsed}) async {
    // Genau ein Start gleichzeitig: Doppelantippen, Retry während der Anfrage.
    if (_phase == RestingMeasurePhase.starting ||
        _phase == RestingMeasurePhase.measuring) {
      return;
    }
    _restElapsed = restElapsed;
    _resetMeasurement();
    _stopCause = null;
    _result = null;
    _phase = RestingMeasurePhase.starting;
    final run = ++_run;
    _notify();

    PpgCameraAvailability a;
    try {
      a = await camera.requestPermission();
    } catch (_) {
      if (run != _run) return;
      await _fail(run, RestingStopCause.cameraError);
      return;
    }
    if (run != _run) return;
    if (!_foreground) {
      await _fail(run, RestingStopCause.background);
      return;
    }
    if (a != PpgCameraAvailability.available) {
      await _fail(run, _causeOfAvailability(a));
      return;
    }
    _phase = RestingMeasurePhase.measuring;
    _notify();
    // Die Startfrist läuft ab dem Abonnieren, auch wenn „gestartet“ ausbleibt.
    _lastImageAt = clock.monotonic();
    if (autoTick) {
      _lastCheckAt = _lastImageAt;
      _gapTimer = Timer.periodic(
        const Duration(milliseconds: 250),
        (_) => checkFrameGap(),
      );
    }
    _sub = camera.start().listen(
      (e) => _onEvent(run, e),
      onError: (Object _) =>
          unawaited(_fail(run, RestingStopCause.cameraError)),
      onDone: () => unawaited(_fail(run, RestingStopCause.cameraError)),
    );
  }

  void _resetMeasurement() {
    _frames.clear();
    _lastImageAt = null;
    _lastCheckAt = null;
    _cameraStarted = false;
    _lastImageT = null;
    _elapsed = 0;
    _evaluating = false;
    _livePulse = null;
    _liveQuality = null;
    _liveHint = null;
    _curve = const [];
    _lastLiveT = double.negativeInfinity;
    _liveBusy = false;
    _previousRestingBpm = null;
    _previousOrigin = null;
    _adoptRejection = null;
    _adoptFailed = false;
    _originMissing = false;
  }

  void _onEvent(int run, PpgCameraEvent e) {
    if (run != _run || _phase != RestingMeasurePhase.measuring || _evaluating) {
      return;
    }
    switch (e) {
      case PpgCameraStarted():
        _cameraStarted = true;
        _lastImageAt = clock.monotonic();
      case PpgCameraExposureLocked():
        break;
      case PpgCameraStopped(:final reason):
        unawaited(_fail(run, _causeOfReason(reason)));
      case PpgCameraFrame(:final frame):
        _onFrame(run, frame);
    }
  }

  void _onFrame(int run, PpgFrame f) {
    final w = ppgStandardWindow;
    final prevT = _lastImageT;
    _cameraStarted = true;
    _lastImageAt = clock.monotonic();
    _lastImageT = f.t;
    if (prevT != null && f.t - prevT > ppgMaxFrameGapSeconds) {
      unawaited(_fail(run, RestingStopCause.interrupted));
      return;
    }
    if (f.t <= w.dataEnd) _frames.add(f);
    _elapsed = f.t;
    _curve = _recentCurve();
    if (f.t >= w.dataEnd) {
      unawaited(_finish(run));
      return;
    }
    if (f.t > w.start &&
        !_liveBusy &&
        f.t - _lastLiveT >= restingLiveIntervalSeconds) {
      unawaited(_liveUpdate(run, f.t));
    }
    _notify();
  }

  List<double> _recentCurve() {
    final from = _elapsed - restingCurveSeconds;
    final recent = [
      for (final f in _frames.reversed.takeWhile((f) => f.t >= from)) f.r,
    ].reversed.toList();
    if (recent.isEmpty) return const [];
    final mean = recent.reduce((a, b) => a + b) / recent.length;
    return [for (final v in recent) mean - v];
  }

  Future<void> _liveUpdate(int run, double t) async {
    _liveBusy = true;
    _lastLiveT = t;
    final w = ppgStandardWindow;
    // Gleitendes Fenster der letzten [restingLiveWindowSeconds]; der Vorlauf
    // für das Filter (Abstand filterStart zu start) bleibt wie im Standard.
    final lead = w.start - w.filterStart;
    final start = math.max(w.start, t - restingLiveWindowSeconds);
    final window = PpgWindow(
      filterStart: start - lead,
      start: start,
      end: math.min(t, w.end),
      dataEnd: math.min(t, w.dataEnd),
    );
    try {
      final m = await _evaluate([
        for (final f in _frames)
          if (f.t >= window.filterStart) f,
      ], window);
      if (run != _run || _phase != RestingMeasurePhase.measuring) return;
      _livePulse = m.hasResult ? m.bpm!.round() : null;
      _liveQuality = m.quality;
      _liveHint = _hintOf(m);
      _notify();
    } catch (_) {
      // Die Zwischenauswertung ist nur Anzeige; die Messung läuft weiter.
    } finally {
      _liveBusy = false;
    }
  }

  RestingLiveHint? _hintOf(PpgMeasurement m) {
    if (m.quality != PpgQuality.unusable) return null;
    if (m.reasons.contains(PpgQualityReason.flatSignal)) {
      return RestingLiveHint.flatSignal;
    }
    if (m.reasons.contains(PpgQualityReason.weakSignal)) {
      return RestingLiveHint.weakSignal;
    }
    if (m.reasons.contains(PpgQualityReason.tooManyDisturbances)) {
      return RestingLiveHint.disturbances;
    }
    return null; // zu wenige Daten: noch kein Hinweis
  }

  Future<void> _finish(int run) async {
    _evaluating = true;
    _notify();
    await _releaseCamera();
    final frames = List.of(_frames);
    final PpgMeasurement m;
    try {
      m = await _evaluate(frames, ppgStandardWindow);
    } catch (_) {
      if (run == _run) await _fail(run, RestingStopCause.cameraError);
      return;
    }
    if (run != _run) return;
    _frames.clear();
    _curve = const [];
    final result = RestingMeasureResult(
      measurement: m,
      measuredAt: clock.now().toUtc(),
      posture: _posture,
      restElapsed: _restElapsed,
    );
    try {
      _previousRestingBpm = (await profile.load()).restingHeartRateBpm;
      _previousOrigin = await RestingHrOrigin.read(settings);
    } catch (_) {
      _previousRestingBpm = null;
      _previousOrigin = null;
    }
    if (run != _run) return;
    _evaluating = false;
    _result = result;
    _phase = RestingMeasurePhase.result;
    _notify();
  }

  Future<void> _releaseCamera() async {
    _gapTimer?.cancel();
    _gapTimer = null;
    final sub = _sub;
    _sub = null;
    await sub?.cancel();
    try {
      await camera.stop();
    } catch (_) {
      // Die Kamera ist ohnehin abbestellt; ein Fehler beim Stoppen ändert den Ausgang nicht.
    }
  }

  Future<void> _fail(int run, RestingStopCause cause) async {
    if (run != _run) return;
    _run++;
    _stopTicker();
    await _releaseCamera();
    _frames.clear();
    _curve = const [];
    _evaluating = false;
    _stopCause = cause;
    _phase = RestingMeasurePhase.stopped;
    _notify();
  }

  /// Bricht Ruhephase, Anfrage oder Messung ab: Kamera gestoppt, Endzustand
  /// [RestingMeasurePhase.stopped] mit [RestingStopCause.userCancelled].
  Future<void> cancel() async {
    switch (_phase) {
      case RestingMeasurePhase.resting:
      case RestingMeasurePhase.starting:
      case RestingMeasurePhase.measuring:
        _pendingStart = false;
        await _fail(_run, RestingStopCause.userCancelled);
      default:
        return;
    }
  }

  /// „Noch einmal“ (siehe [canRetry]): neue Messung, keine neue Ruhephase.
  Future<void> retry() async {
    if (!canRetry) return;
    await _begin(restElapsed: _restElapsed);
  }

  // Lebenszyklus -----------------------------------------------------------

  /// Die App ging in den Hintergrund. Eine laufende Anfrage oder Messung endet
  /// mit Grund; die Ruhephase läuft weiter (Bildschirmsperre beim Liegen).
  Future<void> onBackground() async {
    _foreground = false;
    if (_phase == RestingMeasurePhase.starting ||
        _phase == RestingMeasurePhase.measuring) {
      await _fail(_run, RestingStopCause.background);
    }
  }

  /// Die App ist wieder vorn; war die Ruhephase inzwischen um, beginnt die Messung.
  Future<void> onForeground() async {
    _foreground = true;
    if (_pendingStart && _phase == RestingMeasurePhase.resting) {
      _pendingStart = false;
      await _begin(restElapsed: Duration(minutes: _restMinutes));
    }
  }

  // Ergebnis ---------------------------------------------------------------

  /// Übernimmt den Wert ins Profil wie eine manuelle Eingabe (Prüfung,
  /// Neuberechnung über das übergebene [profile]) und speichert danach
  /// Haltung, Zeitpunkt und Quelle. Nur auf diesen Aufruf, nie von selbst.
  /// Liefert `true` bei Erfolg.
  Future<bool> adopt() async {
    if (!canAdopt) return false;
    final r = _result!;
    _adopting = true;
    _adoptRejection = null;
    _adoptFailed = false;
    _originMissing = false;
    _notify();
    try {
      final p = await profile.load();
      final saved = await profile.save(
        ProfileRecord(
          birthYear: p.birthYear,
          bodyWeightKg: p.bodyWeightKg,
          bodyHeightMeters: p.bodyHeightMeters,
          restingHeartRateBpm: r.bpm,
          maxHeartRateBpm: p.maxHeartRateBpm,
          weeklyRunMinutes: p.weeklyRunMinutes,
          trainingDaysMask: p.trainingDaysMask,
          usualTrainingMinutes: p.usualTrainingMinutes,
        ),
      );
      if (!saved.saved) {
        _adoptRejection = saved.validation;
        return false;
      }
      // Der Wert steht jetzt im Profil (save hat eine ältere Herkunft schon
      // vorher entfernt). Scheitert nur die Herkunft, gilt der Wert als
      // übernommen, aber von Hand: nie eine Kamera-Herkunft ohne diesen Wert.
      _phase = RestingMeasurePhase.adopted;
      try {
        await RestingHrOrigin(
          posture: r.posture,
          measuredAt: r.measuredAt,
        ).write(settings, at: clock.now());
      } catch (_) {
        _originMissing = true;
      }
      return true;
    } catch (_) {
      _adoptFailed = true;
      return false;
    } finally {
      _adopting = false;
      _notify();
    }
  }

  /// Verwirft einen Wert, ohne etwas zu speichern.
  void discard() {
    if (_phase != RestingMeasurePhase.result || !(_result?.hasValue ?? false)) {
      return;
    }
    _phase = RestingMeasurePhase.discarded;
    _notify();
  }

  // Hilfen -----------------------------------------------------------------

  static RestingStopCause _causeOfAvailability(PpgCameraAvailability a) =>
      switch (a) {
        PpgCameraAvailability.permissionDenied =>
          RestingStopCause.permissionDenied,
        PpgCameraAvailability.noCamera => RestingStopCause.noCamera,
        PpgCameraAvailability.noFlash => RestingStopCause.noFlash,
        PpgCameraAvailability.available => RestingStopCause.cameraError,
      };

  static RestingStopCause _causeOfReason(PpgCameraStopReason r) => switch (r) {
    PpgCameraStopReason.permissionDenied => RestingStopCause.permissionDenied,
    PpgCameraStopReason.noCamera => RestingStopCause.noCamera,
    PpgCameraStopReason.noFlash => RestingStopCause.noFlash,
    PpgCameraStopReason.busy => RestingStopCause.busy,
    PpgCameraStopReason.disconnected => RestingStopCause.disconnected,
    PpgCameraStopReason.frameRate => RestingStopCause.frameRate,
    PpgCameraStopReason.background => RestingStopCause.background,
    PpgCameraStopReason.error => RestingStopCause.cameraError,
  };

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    final running =
        _phase == RestingMeasurePhase.starting ||
        _phase == RestingMeasurePhase.measuring;
    _run++;
    _stopTicker();
    _gapTimer?.cancel();
    final sub = _sub;
    _sub = null;
    unawaited(sub?.cancel());
    if (running) unawaited(camera.stop().catchError((_) {}));
    _frames.clear();
    super.dispose();
  }
}
