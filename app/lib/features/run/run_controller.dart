import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter/foundation.dart';

import '../sensors/run_heart_rate.dart';
import 'run_ports.dart';

/// Einordnung der Herzfrequenzzone für die Anzeige (FR-0026, OQ-0012).
enum LiveZoneKind { zone, belowZone1, noHeartRate, noBasis }

class LiveZone {
  const LiveZone(this.kind, {this.zone, this.aboveHint = false});

  final LiveZoneKind kind;

  /// 1-basiert, nur bei [LiveZoneKind.zone].
  final int? zone;

  /// Puls über 100 % der Reserve (FR-0062).
  final bool aboveHint;
}

/// Führt einen Lauf im Vordergrund: verbindet [RunRecorder] mit Standortquelle,
/// Pulsquelle und dem Anzeigetakt. Die Oberfläche liest nur [snapshot],
/// [preprocessing] und die abgeleiteten Getter.
///
/// Es gehen keine Messwerte in Logs; Fehler tragen nur ihre Art.
class RunController extends ChangeNotifier {
  RunController({
    required this.clock,
    required this.storage,
    required this.location,
    this.sensors,
    this.service,
    this.cadence,
    this.resumeRunId,
    this.initialAutoPause,
    this.mode = RunMode.gps,
    this.startBeltSpeedMetersPerSecond,
    this.startInclinePercent,
    this.tickEvery = const Duration(seconds: 1),
    this.serialize,
    RunRecorder? recorder,
  }) : _recorder =
           recorder ??
           RunRecorder(
             clock: clock,
             runs: storage.runs,
             rawData: storage.rawData,
             markers: storage.markers,
           ) {
    _snapshot = _recorder.snapshot();
  }

  final Clock clock;
  final StorageSession storage;
  final LocationSource location;

  /// Pulsquelle dieses Laufs aus der Sensorverwaltung; sie wird mit dem Ende
  /// des Laufs geschlossen. Ohne Quelle `null`.
  final RunHeartRate? sensors;
  final Duration tickEvery;

  /// Dienst, der den Prozess während des Laufs hält (WP08); `null` ohne Dienst.
  final RecordingServicePort? service;

  /// Schrittsensor des Telefons (FR-0202); `null` ohne Sensor-Anbindung.
  final CadenceSensor? cadence;

  /// Ist gesetzt, setzt [start] diesen unterbrochenen Lauf fort (FR-0193),
  /// statt einen neuen anzulegen.
  final int? resumeRunId;

  /// Die auf der Seite „Lauf vorbereiten“ gewählte Autopause (FR-0210). Sie
  /// gilt für diesen Lauf, auch wenn das Merken scheitert. `null`: der
  /// gemerkte Wert aus dem Speicher gilt (Fortsetzen, FR-0193).
  final bool? initialAutoPause;

  /// Art des neuen Laufs (FR-0196). Beim Fortsetzen gilt die gespeicherte Art
  /// des Laufs, nicht dieser Wert.
  final RunMode mode;

  /// Startgeschwindigkeit des Bands in m/s (Pflicht im Modus `treadmill`,
  /// FR-0196, K57) und optionale Steigung in %.
  final double? startBeltSpeedMetersPerSecond;
  final double? startInclinePercent;

  /// Reiht Schreiben von Werten hinter den Start und andere Neuberechnungen
  /// ein (siehe `RecalculationController.exclusive`); `null` = sofort.
  final Future<void> Function(Future<void> Function() action)? serialize;
  final RunRecorder _recorder;
  bool _calculationFailed = false;
  bool _calculationSettled = false;
  Future<void>? _calculation;

  Timer? _timer;
  StreamSubscription<LocationSample>? _locationSub;
  StreamSubscription<HeartRateReading>? _heartSub;
  StreamSubscription<CadenceReading>? _cadenceSub;
  CadenceAvailability? _cadenceAvailability;
  double? _cadence;
  Duration? _cadenceAt; // Monotonzeit des Empfangs
  bool _disposed = false;

  late RecordingSnapshot _snapshot;
  RunPreprocessing? _pre;
  bool _autoPause = false;
  bool _startFailed = false;
  bool _starting = false;
  bool _locationError = false;
  bool _serviceFailed = false;
  RecordingStartDeniedReason? _startDenied;
  bool _serviceWanted = false;
  bool _heartRateSeen = false;
  ResolvedHeartRate? _basis;
  FitnessParameters _fitness = const FitnessParameters.v4();

  RecordingSnapshot get snapshot => _snapshot;
  RunPreprocessing? get preprocessing => _pre;
  RecordingPhase get phase => _snapshot.phase;

  /// Gewünschter Stand der Autopause (auch vor dem Start gesetzt).
  bool get autoPause => _autoPause;

  /// Anlegen des Laufs scheiterte; ein erneuter [start] ist möglich.
  bool get startFailed => _startFailed;

  /// Der Laufbandlauf startete nicht, weil dem Dienst ein Recht fehlt (FR-0196,
  /// K57: ACTIVITY_RECOGNITION). Es wurde kein Lauf angelegt; ein erneuter
  /// [start] ist nach Erteilen des Rechts möglich. Sonst `null`.
  RecordingStartDeniedReason? get startDenied => _startDenied;

  /// Art des Laufs (nach dem Start die gespeicherte Art).
  RunMode get runMode =>
      _snapshot.phase == RecordingPhase.idle ? mode : _snapshot.mode;

  /// Ändert die Bandgeschwindigkeit (m/s) ab jetzt (FR-0196); gespeichert als
  /// Einstellung des Laufs. Gibt `false` zurück, wenn abgelehnt (kein
  /// Laufbandlauf, nicht aktiv, unzulässiger Wert).
  Future<bool> setBeltSpeed(double metersPerSecond) =>
      _belt(() => _recorder.setBeltSpeed(metersPerSecond));

  /// Ändert die Steigung (%) ab jetzt; `null` = nicht angegeben.
  Future<bool> setIncline(double? percent) =>
      _belt(() => _recorder.setIncline(percent));

  Future<bool> _belt(Future<CommandResult> Function() change) async {
    var ok = false;
    try {
      ok = await change() == CommandResult.ok;
    } on Object {
      ok = true; // Sitzung hat die Änderung; Speicherfehler in writeFailure
    }
    _update();
    return ok;
  }

  /// Die Standortquelle meldete einen Fehler und seitdem keinen Punkt mehr.
  bool get locationError => _locationError;

  /// Der Dienst konnte nicht starten. Der Lauf zeichnet weiter auf, aber nur,
  /// solange die App sichtbar ist; die Oberfläche weist darauf hin.
  bool get serviceFailed => _serviceFailed;

  /// Stand des Schrittsensors; `null`, solange er noch nicht geprüft ist oder
  /// es keinen Anschluss gibt. Ohne [CadenceAvailability.available] ist die
  /// Schrittfrequenz „nicht verfügbar“ und der Lauf läuft normal.
  CadenceAvailability? get cadenceAvailability => _cadenceAvailability;

  /// Aktuelle Schrittfrequenz (Schritte je Minute) oder `null`. Ein Wert, der
  /// länger als das Fenster des Schätzers zurückliegt, zählt nicht mehr (Stillstand).
  double? get cadenceStepsPerMinute {
    final at = _cadenceAt;
    if (_cadence == null || at == null) return null;
    return clock.monotonic() - at > CadenceEstimator.defaultWindow
        ? null
        : _cadence;
  }

  /// Von der Pulsquelle kam in diesem Lauf schon ein Wert.
  bool get heartRateSourceSeen => _heartRateSeen;

  /// Die Werte des beendeten Laufs konnten nicht berechnet werden. Der Lauf
  /// ist gespeichert; die Berechnung wird beim nächsten Start nachgeholt.
  /// Trägt keine Gesundheitsdaten.
  bool get calculationFailed => _calculationFailed;

  /// Id des angelegten Laufs, `null` vor dem Start.
  int? get runId => _recorder.runId;

  /// Das Beenden ist durch, einschließlich der Berechnung der Werte (auch wenn
  /// sie scheiterte): Die Zusammenfassung kann gelesen werden.
  bool get calculationSettled => _calculationSettled;

  /// Läuft die Berechnung nach dem Ende noch (für Tests und Abschluss).
  Future<void>? get calculation => _calculation;

  /// Art des letzten Speicherfehlers (nie Inhalte), `null` ohne Fehler.
  StorageFailure? get writeFailure => _recorder.lastWriteFailure;

  /// Mindestens ein akzeptierter Punkt liegt vor (Strecke bekannt).
  bool get hasFix => _snapshot.distanceMeters != null;

  LiveZone get zone {
    final bpm = _snapshot.heartRateBpm;
    if (bpm == null) return const LiveZone(LiveZoneKind.noHeartRate);
    final basis = _basis;
    if (basis == null) return const LiveZone(LiveZoneKind.noBasis);
    final r = const ReserveZones(reserve: HeartRateReserve())
        .zoneFor(basis.basis, bpm, _fitness);
    if (r is! FitnessAvailable<ReserveZonePlacement>) {
      return const LiveZone(LiveZoneKind.noBasis);
    }
    final p = r.value;
    return switch (p) {
      InReserveZone() => LiveZone(
        LiveZoneKind.zone,
        zone: p.zone,
        aboveHint: p.aboveHint,
      ),
      BelowReserveZone1() => const LiveZone(LiveZoneKind.belowZone1),
    };
  }

  /// Lädt Einstellungen und Profil, legt den Lauf an und beginnt, Punkte und
  /// Puls anzunehmen. Scheitert das Anlegen, bleibt [startFailed] gesetzt.
  Future<void> start() async {
    if (_starting || phase != RecordingPhase.idle) return;
    _starting = true;
    _startFailed = false;
    _startDenied = null;
    notifyListeners();
    try {
      final chosen = initialAutoPause;
      if (chosen != null) {
        _autoPause = chosen;
      } else {
        try {
          _autoPause = await storage.settings.get(SettingKeys.autoPause) == '1';
        } on Object {
          _autoPause = false;
        }
      }
      try {
        _fitness = await ReserveZoneSettings.loadParameters(storage.settings);
      } on Object {
        _fitness = const FitnessParameters.v4();
      }
      try {
        _basis = resolveHeartRate(
          await storage.profile.read(),
          currentYear: clock.now().year,
        );
      } on Object {
        _basis = null;
      }
      _recorder.setAutoPause(_autoPause);
      final resume = resumeRunId;
      var runMode = mode;
      if (resume != null) {
        try {
          runMode = (await storage.runs.get(resume))?.mode ?? RunMode.gps;
        } on Object {
          runMode = RunMode.gps;
        }
      }
      // Laufband: der Dienst zuerst, denn ohne sein Recht startet der Lauf
      // nicht (K57) und es soll kein leerer Lauf entstehen.
      if (runMode == RunMode.treadmill) {
        await _startService(runMode);
        if (_startDenied != null) return;
      }
      try {
        final r = resume == null
            ? await _recorder.start(
                mode: runMode,
                beltSpeedMetersPerSecond: startBeltSpeedMetersPerSecond,
                inclinePercent: startInclinePercent,
              )
            : await _recorder.restore(resume);
        if (r == CommandResult.rejected) {
          _startFailed = true;
          if (runMode == RunMode.treadmill) _stopService();
          return;
        }
      } on Object {
        _startFailed = true;
        if (runMode == RunMode.treadmill) _stopService();
        return;
      }
      // Das Laufband hat keine Positionen und braucht keinen Standort.
      if (runMode == RunMode.gps) {
        _locationSub = location.samples().listen(
          (s) {
            _locationError = false;
            _recorder.addPosition(s);
          },
          onError: (Object _) {
            _locationError = true;
            _update();
          },
        );
      }
      final hrStream = sensors?.readings;
      if (hrStream != null) {
        _heartSub = hrStream.listen((r) {
          if (!_heartRateSeen) _sensorConnected();
          _heartRateSeen = true;
          _recorder.addHeartRate(r);
        }, onError: (Object _) {});
      }
      _timer = Timer.periodic(tickEvery, (_) {
        _recorder.tick();
        _update();
      });
      unawaited(_startCadence());
      if (runMode == RunMode.gps) await _startService(runMode);
    } finally {
      _starting = false;
      _update();
    }
  }

  /// Startet den Dienst nach dem Anlegen des Laufs. Scheitert er, geht der Lauf
  /// nicht verloren: Er läuft im Vordergrund weiter und [serviceFailed] meldet es.
  Future<void> _startService(RunMode runMode) async {
    final s = service;
    if (s == null) return;
    _serviceWanted = true;
    try {
      await s.start(
        mode: runMode == RunMode.treadmill
            ? RecordingServiceMode.treadmill
            : RecordingServiceMode.gps,
      );
      _serviceFailed = false;
    } on RecordingStartDenied catch (e) {
      // Kein Lauf ohne das Recht (Laufband): eigener Zustand statt Fehler.
      _startDenied = e.reason;
      _serviceWanted = false;
      return;
    } on Object {
      _serviceFailed = true;
    }
    // Der Lauf endete oder der Controller wurde verworfen, während der Start lief.
    if (!_serviceWanted) _callStop(s);
  }

  /// Ein Sensor lieferte den ersten Wert: Der Dienst zieht `connectedDevice`
  /// nach, falls er ohne startete (BLUETOOTH_CONNECT erst im Lauf erteilt).
  void _sensorConnected() {
    final s = service;
    if (s == null || !_serviceWanted) return;
    unawaited(s.updateType().then((_) {}, onError: (Object _) {}));
  }

  /// FR-0202: ohne Berechtigung oder Sensor bleibt es bei „nicht verfügbar“.
  Future<void> _startCadence() async {
    final c = cadence;
    if (c == null) return;
    try {
      final a = await c.availability();
      if (_disposed || _timer == null) return;
      _cadenceAvailability = a;
      if (a == CadenceAvailability.available) {
        _cadenceSub = c.readings().listen(
          (r) {
            _cadence = r.stepsPerMinute;
            _cadenceAt = clock.monotonic();
            _update();
          },
          onError: (Object _) => _cadenceEnded(),
          onDone: _cadenceEnded,
        );
      }
    } on Object {
      _cadenceAvailability = CadenceAvailability.noSensor;
    }
    _update();
  }

  /// Der Schrittstrom endete von sich aus (Sensor oder Recht fiel weg): ab
  /// jetzt „nicht verfügbar“ statt eines Werts, der nur verfällt.
  void _cadenceEnded() {
    if (_disposed || _timer == null) return;
    // Der Strom ist nicht endgültig beendet, wenn der Port nach einem Fehler weiterliefert.
    unawaited(_cadenceSub?.cancel());
    _cadenceSub = null;
    _cadence = null;
    _cadenceAvailability = CadenceAvailability.noSensor;
    _update();
  }

  void _stopService() {
    final s = service;
    if (s == null || !_serviceWanted) return;
    _serviceWanted = false;
    _callStop(s);
  }

  void _callStop(RecordingServicePort s) =>
      unawaited(s.stop().then((_) {}, onError: (Object _) {}));

  Future<void> pause() => _command(_recorder.pause);
  Future<void> resume() => _command(_recorder.resume);
  Future<void> lap() => _command(_recorder.lap);

  Future<void> finish() async {
    await _command(_recorder.finish);
    if (phase == RecordingPhase.finished) {
      _stopInputs();
      final id = _recorder.runId;
      if (id != null && _calculation == null) {
        _calculation = _calculate(id);
        await _calculation;
      }
      _calculationSettled = true;
      _update();
    }
  }

  /// Berechnet nach erfolgreichem Ende die Werte des Laufs. Scheitert das, ist
  /// der Lauf trotzdem gespeichert ([calculationFailed], Merker für später).
  Future<void> _calculate(int runId) async {
    Future<void> run() async {
      // Nach dem tatsächlichen Zustand im Speicher entscheiden, nicht nach
      // einem früheren Schreibfehler im Lauf: ist der Lauf nicht als beendet
      // gespeichert, gibt es nichts zu berechnen.
      final stored = await storage.runs.get(runId);
      if (stored == null || stored.state != RunState.finished) return;
      await ValueCalculationService(
        session: storage,
        clock: clock,
      ).calculateAfterRunTracked(runId);
    }

    try {
      final s = serialize;
      await (s == null ? run() : s(run));
    } on Object {
      _calculationFailed = true;
    }
    _update();
  }

  Future<void> _command(Future<CommandResult> Function() run) async {
    try {
      await run();
    } on Object {
      // Der Zustand der Sitzung gilt; der Speicherfehler steht in
      // [writeFailure] und wird angezeigt.
    }
    _update();
  }

  void _stopInputs() {
    _timer?.cancel();
    _timer = null;
    unawaited(_locationSub?.cancel());
    _locationSub = null;
    unawaited(_heartSub?.cancel());
    _heartSub = null;
    unawaited(_cadenceSub?.cancel());
    _cadenceSub = null;
    sensors?.close();
    _stopService();
  }

  void _update() {
    if (_disposed) return;
    final o = _recorder.observe();
    _snapshot = o.snapshot;
    _pre = o.preprocessing;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _stopInputs();
    super.dispose();
  }
}
