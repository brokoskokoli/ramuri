import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../ui/ui.dart';
import '../plan/plan_started_unit.dart';
import '../../ui/format/plan_texts.dart';
import '../plan/plan_unit_screen.dart' show PlanSegmentRow;
import '../recalculation/recalculation_controller.dart';
import '../sensors/sensor_manager.dart';
import '../sensors/sensors_screen.dart';
import '../settings/app_settings.dart';
import '../history/manual_training_screen.dart';
import '../../ui/format/unit_format.dart';
import 'guided_segments.dart';
import 'live_run_view.dart';
import 'other_sport.dart';
import 'run_controller.dart';
import 'run_ports.dart';
import '../../ui/format/treadmill_units.dart';
import 'voice_texts.dart';
import '../../ui/format/other_sport_format.dart';

/// Ablauf „Lauf starten“: Seite „Lauf vorbereiten“ (FR-0210) mit Startprüfung
/// (FR-0195), Live-Bildschirm
/// (FR-0026, FR-0027, FR-0028 bis FR-0030) und einfache Abschlussansicht.
/// Die Zusammenfassung zeigt `RunSummaryBody` (WP10).
class RunFlowScreen extends StatefulWidget {
  const RunFlowScreen({
    super.key,
    required this.session,
    required this.clock,
    required this.ports,
    required this.permissions,
    required this.algorithms,
    this.tickEvery = const Duration(seconds: 1),
    this.serialize,
    this.resumeRunId,
    this.sensors,
    this.recalculation,
    this.onFinished,
    this.guidedSegments,
    this.plannedUnit,
    this.startPlanned = false,
    this.onGuidanceChosen,
  });

  final StorageSession session;
  final Clock clock;
  final RunPorts ports;
  final PermissionStatusPort permissions;
  final Duration tickEvery;

  /// Algorithmen-Registry der App (`AppDependencies.algorithms`) für die
  /// Werte nach dem Lauf.
  final AlgorithmLookup algorithms;

  /// Sensorverwaltung für „Koppeln“ (FR-0011). Ohne sie fehlt der Knopf.
  final SensorManager? sensors;

  /// Für „Details“ nach dem Lauf; ohne sie fehlt der Knopf.
  final RecalculationController? recalculation;

  /// Setzt diesen unterbrochenen Lauf fort (FR-0193); das Start-Gate gilt.
  final int? resumeRunId;

  /// Siehe [RunController.serialize].
  final Future<void> Function(Future<void> Function() action)? serialize;

  /// Wird genau einmal mit der Nummer des Laufs gerufen, sobald er beendet
  /// ist; seine Berechnung kann noch laufen (sie steht in [serialize] an).
  /// So geht die Meldung nicht verloren, wenn der Bildschirm vor dem Ende der
  /// Berechnung schließt (WP22: Zuordnung zur Plan-Einheit). Ein Lauf, der
  /// nicht beendet wird, meldet nichts.
  final void Function(int runId)? onFinished;

  /// Abschnitte der geführten Einheit eines neuen Laufs (WP24); `null`: freier
  /// Lauf. Die Seite „Lauf vorbereiten“ übergibt sie (Auftrag 3).
  final List<PlanSegment>? guidedSegments;

  /// Die offene Einheit von heute (WP24 Auftrag 3); `null` (kein Plan, Ruhetag,
  /// Warnsignal, schon gelaufen): nur „Freier Lauf“ ist wählbar. Gewählt wird
  /// die Einheit nicht von selbst, sondern über [startPlanned].
  final PlanUnit? plannedUnit;

  /// „Geplante Einheit“ ist beim Öffnen gewählt („Einheit starten“).
  final bool startPlanned;

  /// Wird mit „Los“ gerufen, wenn die Wahl von der beim Öffnen abweicht:
  /// die Einheit (geführt) oder `null` (frei). So merkt der Start die Einheit
  /// für die Zuordnung nach dem Lauf.
  final Future<void> Function(PlanUnit? unit)? onGuidanceChosen;

  @override
  State<RunFlowScreen> createState() => _RunFlowScreenState();
}

class _RunFlowScreenState extends State<RunFlowScreen>
    with WidgetsBindingObserver {
  RunController? _controller;
  StartBlock? _block;
  bool _checking = true;

  /// Die Prüfung besteht, aber der Lauf wartet auf das Tippen des Nutzers.
  bool _ready = false;

  /// Jede Prüfung bekommt eine Nummer; nur die jüngste zählt. So kann eine
  /// Antwort, die nach einer Neuerzeugung der Activity nie ankommt (oder
  /// `busy` ist), die Oberfläche nicht festhalten.
  int _generation = 0;

  /// Autopause der Seite (FR-0029, FR-0210): zuletzt gewählt, sonst aus.
  bool _autoPause = false;
  bool _autoPauseTouched = false;
  late Future<void> _autoPauseLoaded;

  /// Laufart der Seite (FR-0196): zuletzt gewählt, sonst GPS. Beim Fortsetzen
  /// gilt die Art des gespeicherten Laufs.
  RunMode _mode = RunMode.gps;
  bool _modeTouched = false;
  late Future<void> _modeLoaded;
  final _speedField = TextEditingController();
  final _inclineField = TextEditingController();

  bool get _treadmill => _mode == RunMode.treadmill;

  /// Andere Sportart (FR-0221): kein Standort, keine Kadenz, keine Führung;
  /// ein neuer Start braucht einen verbundenen Pulssensor.
  bool get _sportMode => _mode == RunMode.sport;

  /// Band und andere Sportart brauchen keinen Standort.
  bool get _noLocation => _mode != RunMode.gps;

  /// Gewählte Sportart (gemerkt, [otherSportSettingKey]); beim Fortsetzen die
  /// des gespeicherten Laufs.
  OtherSport _sport = defaultOtherSport;
  bool _sportTouched = false;

  /// Hinweis Wade/Achillessehne beim Start (1. bis 3. Seilspring-Einheit).
  bool _ropeHint = false;

  bool get _sensorConnected => widget.sensors?.connectedIds.isNotEmpty ?? false;

  /// Ein neuer Start einer anderen Sportart ohne Pulssensor ist gesperrt.
  bool get _sportLocked => _preparing && _sportMode && !_sensorConnected;

  /// „Geplante Einheit“ gewählt (nur mit [RunFlowScreen.plannedUnit]).
  bool _warningActive = false;
  late bool _planned = widget.startPlanned && widget.plannedUnit != null;

  /// Geführt nur bei einem Lauf; eine andere Sportart läuft immer frei.
  bool get _guided => _planned && !_sportMode;

  /// Hauptschalter „Ansagen“ (gemerkt, Vorgabe an) und das Schreiben davon.
  bool _voiceOn = true;
  bool _voiceTouched = false;
  late Future<void> _voiceLoaded;
  Future<void> _voiceSaved = Future.value();

  /// Eingaben des Bands (PAR-209, PAR-210): Los braucht eine gültige
  /// Geschwindigkeit; die Steigung ist freiwillig, aber wenn angegeben gültig.
  double? get _beltSpeed => TreadmillUnits.parseSpeed(_unit, _speedField.text);
  (bool, double?) get _incline =>
      TreadmillUnits.parseIncline(_inclineField.text);
  DistanceUnit get _unit => AppSettingsScope.of(context).distanceUnit;

  /// GPS-Zustand der Seite (FR-0210): Genauigkeit des letzten Punkts. Nur eine
  /// Anzeige; es wird nichts gespeichert und nie gesperrt. Der Strom läuft nur,
  /// solange die Seite bereit ist (Recht und Dienst vorhanden).
  StreamSubscription<LocationSample>? _gpsSub;
  bool _gpsGood = false;

  /// Bleibt ein Punkt länger als PAR-004 aus, gilt das Signal nicht mehr als gut.
  Timer? _gpsStale;

  /// Ein Start läuft (Abfragen im Startweg): Der Lebenszyklus prüft dann nicht
  /// neu, sonst verwirft er den Start beim Zurück vom Systemdialog.
  bool _starting = false;

  /// Quelle der Schrittfrequenz; `null`, solange sie noch nicht gelesen ist.
  CadenceAvailability? _cadenceAvailability;

  /// Fortsetzen (FR-0193) startet sofort, ein neuer Lauf wartet auf „Los“.
  bool get _preparing => widget.resumeRunId == null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Bekannte Pulssensoren verbinden sich still (nur mit erteilten Rechten).
    unawaited(_connectSensors());
    _autoPauseLoaded = _loadAutoPause();
    _modeLoaded = _loadMode();
    _voiceLoaded = _loadVoice();
    if (_preparing && widget.plannedUnit == null) unawaited(_loadWarning());
    unawaited(_loadCadence());
    if (!_preparing) unawaited(_loadResumedUnit());
    _check(askUser: false, autoStart: !_preparing);
  }

  /// Die Einheit, zu der der fortgesetzte Lauf gehört (Merker aus
  /// „Einheit starten“, [PlanStartedUnitStore]); nur für „Aus dem Plan“ in der
  /// Zusammenfassung, die Zuordnung in der Datenbank geschieht nach dem Schließen.
  PlanUnit? _resumedUnit;

  Future<void> _loadResumedUnit() async {
    try {
      final session = widget.session;
      final started = await PlanStartedUnitStore(
        session: session,
        clock: widget.clock,
      ).read();
      final run = await session.runs.get(widget.resumeRunId!);
      if (started == null ||
          run == null ||
          run.startedAt.isBefore(started.since)) {
        return;
      }
      final unit = await startedPlanUnit(session, started);
      // Wie die Zuordnung in der Datenbank: zuerst die gemerkte Kennung, bei
      // einer durch Neuberechnung ersetzten Einheit die offene des Tags.
      if (unit == null || !mounted) return;
      setState(() => _resumedUnit = unit);
    } on Object {
      // Nur die Anzeige fehlt.
    }
  }

  /// Fehler beim Lesen: Autopause aus (FR-0029).
  Future<void> _loadAutoPause() async {
    var value = false;
    try {
      value = await widget.session.settings.get(SettingKeys.autoPause) == '1';
    } on Object {
      value = false;
    }
    if (!mounted || _autoPauseTouched) return;
    setState(() => _autoPause = value);
  }

  /// Ein Warnsignal ist aktiv: Dann fehlt die Einheit wegen des Ruhetags, und
  /// der Satz sagt das statt „keine Einheit offen“. Fehler beim Lesen: wie ohne.
  Future<void> _loadWarning() async {
    var active = false;
    try {
      final s = widget.session;
      if (s is WarningStorage) {
        active = await (s as WarningStorage).warning.read() != null;
      }
    } on Object {
      active = false;
    }
    if (!mounted || !active) return;
    setState(() => _warningActive = true);
  }

  /// Fehler beim Lesen: Ansagen an (Vorgabe, FR-0031).
  Future<void> _loadVoice() async {
    var value = true;
    try {
      value = (await GuidanceSettings(widget.session.settings).load()).enabled;
    } on Object {
      value = true;
    }
    if (!mounted || _voiceTouched) return;
    setState(() => _voiceOn = value);
  }

  /// Merkt den Hauptschalter sofort; ein Speicherfehler ändert die Wahl nicht.
  void _setVoice(bool on) {
    setState(() {
      _voiceOn = on;
      _voiceTouched = true;
    });
    _voiceSaved = _voiceSaved.then((_) async {
      try {
        await widget.session.settings.set(
          SettingKeys.guidanceEnabled,
          on ? '1' : '0',
          at: widget.clock.now().toUtc(),
        );
      } on Object {
        // Nur das Merken scheitert.
      }
    });
  }

  /// Fehler beim Lesen: GPS (FR-0196). Fortsetzen liest die Art aus dem Lauf.
  Future<void> _loadMode() async {
    var value = RunMode.gps;
    try {
      final resume = widget.resumeRunId;
      if (resume != null) {
        final run = await widget.session.runs.get(resume);
        value = run?.mode ?? RunMode.gps;
        if (run?.sport != null) _sport = run!.sport!;
      } else {
        final saved = await widget.session.settings.get(SettingKeys.runMode);
        value = RunMode.fromWire(saved) ?? RunMode.gps;
        final sport = await loadOtherSport(widget.session.settings);
        if (!_sportTouched) _sport = sport;
        _ropeHint = await ropeHintBeforeStart(widget.session.runs);
      }
    } on Object {
      value = RunMode.gps;
    }
    if (!mounted || _modeTouched) return;
    _mode = value;
  }

  /// Merkt die Sportart dauerhaft; ein Speicherfehler ändert die Wahl nicht.
  Future<void> _setSport(OtherSport sport) async {
    if (sport == _sport) return;
    setState(() {
      _sport = sport;
      _sportTouched = true;
    });
    try {
      await widget.session.settings.set(
        otherSportSettingKey,
        sport.wire,
        at: widget.clock.now(),
      );
    } on Object {
      // Nur das Merken scheitert.
    }
  }

  Future<void> _openManualEntry() async {
    final now = widget.clock.now().toUtc();
    final today = isoDay(now.add(widget.clock.utcOffsetAt(now)));
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ManualTrainingScreen(
          service: SubjectiveService(
            session: widget.session,
            clock: widget.clock,
          ),
          today: today,
          initialKind: ManualTrainingKind.other,
        ),
      ),
    );
  }

  /// Merkt die Wahl dauerhaft (wie die Autopause); ein Speicherfehler ändert
  /// die Wahl nicht. Danach gilt die Prüfung der neuen Art.
  Future<void> _setMode(RunMode mode) async {
    if (mode == _mode) return;
    setState(() {
      _mode = mode;
      _modeTouched = true;
    });
    unawaited(_check(askUser: false, autoStart: false));
    try {
      await widget.session.settings.set(
        SettingKeys.runMode,
        mode.wire,
        at: widget.clock.now(),
      );
    } on Object {
      // Nur das Merken scheitert.
    }
  }

  Future<void> _loadCadence() async {
    CadenceAvailability a;
    try {
      a =
          await widget.ports.cadence?.availability() ??
          CadenceAvailability.noSensor;
    } on Object {
      a = CadenceAvailability.noSensor;
    }
    if (!mounted) return;
    setState(() => _cadenceAvailability = a);
  }

  /// Merkt die Wahl dauerhaft; ein Speicherfehler ändert die Wahl nicht.
  Future<void> _setAutoPause(bool enabled) async {
    setState(() {
      _autoPause = enabled;
      _autoPauseTouched = true;
    });
    try {
      await widget.session.settings.set(
        SettingKeys.autoPause,
        enabled ? '1' : '0',
        at: widget.clock.now(),
      );
    } on Object {
      // Nur das Merken scheitert; der nächste Lauf nutzt die Wahl trotzdem.
    }
  }

  Future<void> _pairSensors() async {
    final manager = widget.sensors;
    if (manager == null) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => SensorsScreen(manager: manager)),
    );
    if (!mounted) return;
    // Zurück auf dieser Seite; die Berechtigung kann sich geändert haben.
    unawaited(_loadCadence());
  }

  Future<void> _connectSensors() async {
    try {
      await widget.ports.connectSensors?.call();
    } catch (_) {
      // Ohne Sensor läuft der Lauf unverändert.
    }
  }

  /// Die App ist im Hintergrund: `_startGps` bleibt dann untätig.
  bool _inBackground = false;

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopGps();
    _speedField.dispose();
    _inclineField.dispose();
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Zurück aus Systemdialog oder Einstellungen: Stand neu lesen, ohne zu
    // fragen. Das ersetzt auch eine verlorene Antwort auf die Anfrage.
    // Im Hintergrund braucht die Anzeige keinen Strom; `resumed` startet ihn neu.
    if (state == AppLifecycleState.paused) _inBackground = true;
    if (state == AppLifecycleState.resumed) _inBackground = false;
    if (state == AppLifecycleState.paused && _controller == null) _stopGps();
    if (state == AppLifecycleState.resumed &&
        _controller == null &&
        !_starting) {
      _check(askUser: false, autoStart: false);
    }
  }

  /// Hört auf die Standortpunkte, nur um die Genauigkeit anzuzeigen. Die
  /// Punkte selbst werden weder gehalten noch geloggt.
  void _startGps() {
    // Eine Prüfung, die erst nach `paused` fertig wird, startet keinen Strom.
    if (_gpsSub != null || _inBackground) return;
    _gpsGood = false;
    _gpsSub = widget.ports.location.samples().listen(
      (sample) {
        final accuracy = sample.accuracyMeters;
        final good =
            accuracy != null &&
            accuracy >= 0 &&
            accuracy <=
                const PreprocessingParameters.v5().positionMaxAccuracyMeters;
        _gpsStale?.cancel();
        _gpsStale = good
            ? Timer(const PreprocessingParameters.v5().gapMaxDuration, _gpsLost)
            : null;
        if (good != _gpsGood && mounted) setState(() => _gpsGood = good);
      },
      onError: (Object _) {
        _gpsLost();
      },
    );
  }

  void _gpsLost() {
    _gpsStale?.cancel();
    _gpsStale = null;
    if (_gpsGood && mounted) setState(() => _gpsGood = false);
  }

  /// Beendet den Strom. Die Abmeldung geht sofort als Kanalnachricht hinaus,
  /// vor der Anmeldung des Laufs: Die Quelle kennt nur einen Zuhörer, und die
  /// Nachrichten eines Kanals bleiben in ihrer Reihenfolge. Darauf zu warten
  /// wäre nicht nötig.
  void _stopGps() {
    final sub = _gpsSub;
    _gpsSub = null;
    _gpsGood = false;
    _gpsStale?.cancel();
    _gpsStale = null;
    if (sub != null) unawaited(sub.cancel());
  }

  /// Nur der Weg von der Startschaltfläche der Startseite startet sofort. Nach
  /// einer Blockade, Einstellungen oder einer anderen App wartet der Lauf auf
  /// das Tippen: Minuten später soll er nicht von selbst beginnen.
  Future<void> _check({required bool askUser, required bool autoStart}) async {
    // Ein zweites „Los“ während des Starts tut nichts.
    if (autoStart && _starting) return;
    final gen = ++_generation;
    setState(() => _checking = true);
    await _modeLoaded;
    if (!mounted || gen != _generation) return;
    // Laufband und andere Sportart: kein Standort, weder Recht noch
    // GPS-Schalter (FR-0196, FR-0221). Das Recht für die Aktivität prüft der
    // Start (`startDenied`).
    final result = _noLocation
        ? const StartReadiness(null)
        : await RecordingStartGate(widget.ports.access).check(askUser: askUser);
    if (!mounted || gen != _generation) return;
    if (!result.canStart) {
      _stopGps();
      setState(() {
        _block = result.block;
        _ready = false;
        _checking = false;
      });
      return;
    }
    if (!autoStart) {
      setState(() {
        _block = null;
        _ready = true;
        _checking = false;
      });
      if (_noLocation) {
        _stopGps();
      } else {
        _startGps();
      }
      return;
    }
    // Andere Sportart neu: Ohne Pulssensor startet nichts (FR-0221).
    if (_sportLocked) {
      setState(() => _checking = false);
      return;
    }
    // Laufband neu: Ohne gültige Startgeschwindigkeit startet nichts.
    if (_preparing && _treadmill && (_beltSpeed == null || !_incline.$1)) {
      setState(() => _checking = false);
      return;
    }
    _starting = true;
    final RunController controller;
    try {
      await _autoPauseLoaded;
      await _voiceLoaded;
      await _voiceSaved;
      await _announceChoice();
      await _askNotifications();
      await _askActivityRecognition();
      if (!mounted || gen != _generation) return;
      _stopGps();
      controller = _newController();
    } finally {
      _starting = false;
    }
    setState(() {
      _controller = controller;
      _block = null;
      _ready = false;
      _checking = false;
    });
    await controller.start();
  }

  /// Meldet eine geänderte Wahl „Geplante Einheit“/„Freier Lauf“ dem Start
  /// (Merker für die Zuordnung); ein Fehler dort hält den Lauf nicht auf.
  /// Maßgeblich ist die Wahl, nicht die Führung: Eine andere Sportart über
  /// „Einheit starten“ läuft ohne Führung und bleibt der Einheit gemerkt
  /// (FR-0222).
  Future<void> _announceChoice() async {
    final unit = widget.plannedUnit;
    final callback = widget.onGuidanceChosen;
    if (!_preparing || callback == null) return;
    final initial = widget.startPlanned && unit != null;
    if (_planned == initial) return;
    try {
      await callback(_planned ? unit : null);
    } on Object {
      // Ohne Merker ordnet nur der normale Weg zu.
    }
  }

  /// Die Führung eines neuen Laufs: nur mit gewählter Einheit.
  List<PlanSegment>? get _segmentsForRun {
    if (!_preparing) return widget.guidedSegments;
    final unit = widget.plannedUnit;
    if (_sportMode) return null;
    if (_planned && unit != null) return guidedSegmentsOf(unit);
    return widget.guidedSegments;
  }

  RunController _newController() {
    final controller = RunController(
      clock: widget.clock,
      storage: widget.session,
      location: widget.ports.location,
      algorithms: widget.algorithms,
      sensors: widget.ports.heartRateRun?.call(),
      service: widget.ports.recordingService,
      cadence: widget.ports.cadence,
      resumeRunId: widget.resumeRunId,
      initialAutoPause: _preparing && !_noLocation ? _autoPause : null,
      mode: _mode,
      sport: _sportMode ? _sport : null,
      startBeltSpeedMetersPerSecond: _preparing && _treadmill
          ? _beltSpeed
          : null,
      startInclinePercent: _preparing && _treadmill ? _incline.$2 : null,
      tickEvery: widget.tickEvery,
      serialize: widget.serialize,
      voice: widget.ports.voice,
      voiceTexts: VoiceTexts(AppLocalizations.of(context)),
      guidedSegments: _segmentsForRun,
      guidedKind: _guided && _preparing ? widget.plannedUnit?.kind : null,
    );
    final onFinished = widget.onFinished;
    if (onFinished != null) {
      var reported = false;
      controller.addListener(() {
        final id = controller.runId;
        if (reported ||
            id == null ||
            controller.phase != RecordingPhase.finished) {
          return;
        }
        reported = true;
        onFinished(id);
      });
    }
    return controller;
  }

  /// ADR-0005 Punkt 2: fragen, aber nie blockieren (Ablehnung, Fehler, Abbruch).
  Future<void> _askNotifications() async {
    try {
      await widget.ports.requestNotifications?.call();
    } catch (_) {
      // Ohne Berechtigung läuft der Dienst, nur die Benachrichtigung fehlt.
    }
  }

  /// FR-0202: fragen, aber nie blockieren; ohne Recht fehlt nur die Schrittfrequenz.
  Future<void> _askActivityRecognition() async {
    // Andere Sportart: keine Schrittfrequenz, kein Recht nötig (FR-0221).
    if (_sportMode) return;
    try {
      await widget.ports.requestActivityRecognition?.call(_treadmill);
    } catch (_) {
      // Ohne Berechtigung ist die Schrittfrequenz nicht verfügbar.
    }
  }

  Future<void> _retryStart() async {
    // Nach dem Erteilen des Rechts fragt der Start nicht mehr, er prüft nur.
    await _askActivityRecognition();
    await _controller?.start();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final controller = _controller;
    if (controller == null) {
      return Scaffold(
        appBar: AppBar(
          title: Text(_preparing ? l10n.startTitle : l10n.homeStartRun),
        ),
        body: _preparing
            ? _prepareBody(context, l10n)
            : _checking
            ? _checkingBody(l10n)
            : _ready
            ? _readyBody(l10n)
            : _blockBody(l10n),
      );
    }
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (controller.startFailed) {
          return Scaffold(
            appBar: AppBar(title: Text(l10n.homeStartRun)),
            body: _explanation(
              l10n,
              !controller.startFailedResume
                  ? l10n.runStartFailed
                  : controller.startFailedService
                  ? l10n.treadmillStartFailedResume
                  : l10n.runResumeFailed,
              [
                FilledButton(
                  key: const Key('run_start_retry'),
                  onPressed: _retryStart,
                  child: Text(l10n.notOpenableRetry),
                ),
              ],
            ),
          );
        }
        if (controller.startDenied != null) {
          return Scaffold(
            appBar: AppBar(title: Text(l10n.homeStartRun)),
            body: _explanation(l10n, l10n.treadmillDeniedActivity, [
              FilledButton(
                key: const Key('treadmill_denied_retry'),
                onPressed: _retryStart,
                child: Text(l10n.runActionAsk),
              ),
              OutlinedButton(
                key: const Key('treadmill_denied_settings'),
                onPressed: () => widget.permissions.openSystemSettings(),
                child: Text(l10n.runActionSettings),
              ),
            ], blockKey: const Key('treadmill_denied')),
          );
        }
        return LiveRunView(
          controller: controller,
          formatter: AppSettingsScope.formatterOf(context),
          clock: widget.clock,
          recalculation: widget.recalculation,
          pendingPlanUnit: widget.resumeRunId == null
              ? (_guided ? widget.plannedUnit : null)
              : _resumedUnit,
        );
      },
    );
  }

  Widget _checkingBody(AppLocalizations l10n) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 16),
        Text(l10n.runChecking, key: const Key('run_checking')),
      ],
    ),
  );

  /// Prüfung bestanden: Der Start erfolgt erst mit dem Tippen, und zwar nach
  /// einer frischen Prüfung (der Stand kann sich inzwischen geändert haben).
  Widget _readyBody(AppLocalizations l10n) => Center(
    child: FilledButton(
      key: const Key('run_start_ready'),
      onPressed: () => _check(askUser: false, autoStart: true),
      child: Text(l10n.homeStartRun),
    ),
  );

  Widget _blockBody(AppLocalizations l10n) {
    final (text, actions, blockKey) = _blockParts(l10n);
    return _explanation(l10n, text, actions, blockKey: blockKey);
  }

  /// Grund der Sperre (FR-0195) mit den Knöpfen, die sie beheben können.
  (String, List<Widget>, Key) _blockParts(AppLocalizations l10n) {
    final block = _block ?? StartBlock.unknown;
    final text = switch (block) {
      StartBlock.permissionDenied => l10n.runBlockPermissionDenied,
      StartBlock.approximateOnly => l10n.runBlockApproximate,
      StartBlock.gpsOff => l10n.runBlockGpsOff,
      StartBlock.unknown => l10n.runBlockUnknown,
    };
    final canAsk =
        block == StartBlock.permissionDenied ||
        block == StartBlock.approximateOnly;
    final canOpenSettings = canAsk;
    // Standort aus: direkt zu den Standort-Einstellungen des Systems; die
    // Rückkehr in den Vordergrund prüft erneut (didChangeAppLifecycleState).
    final canOpenLocationSettings = block == StartBlock.gpsOff;
    final actions = <Widget>[
      if (canAsk)
        FilledButton(
          key: const Key('run_block_ask'),
          onPressed: () => _check(askUser: true, autoStart: false),
          child: Text(l10n.runActionAsk),
        ),
      if (canOpenLocationSettings)
        FilledButton(
          key: const Key('run_block_location_settings'),
          onPressed: () => widget.ports.access.openLocationSettings(),
          child: Text(l10n.runActionLocationSettings),
        ),
      if (canOpenSettings)
        OutlinedButton(
          key: const Key('run_block_settings'),
          onPressed: () => widget.permissions.openSystemSettings(),
          child: Text(l10n.runActionSettings),
        ),
      // Ohne Abfrage lesen: nach Schalter oder Einstellungen genügt das.
      if (!canAsk && !canOpenLocationSettings)
        FilledButton(
          key: const Key('run_block_recheck'),
          onPressed: () => _check(askUser: false, autoStart: false),
          child: Text(l10n.runActionRecheck),
        )
      else
        TextButton(
          key: const Key('run_block_recheck'),
          onPressed: () => _check(askUser: false, autoStart: false),
          child: Text(l10n.runActionRecheck),
        ),
    ];
    return (text, actions, Key('run_block_${block.name}'));
  }

  bool get _beltInputValid => _beltSpeed != null && _incline.$1;

  /// Wahl der Laufart (FR-0196): GPS oder Laufband, gemerkt wie die Autopause.
  Widget _modeCard(AppLocalizations l10n, TextTheme text) => RamuriCard(
    padding: const EdgeInsets.all(18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.treadmillModeTitle, style: text.titleMedium),
        const SizedBox(height: 10),
        SegmentedButton<RunMode>(
          key: const Key('treadmill_mode'),
          showSelectedIcon: false,
          segments: [
            ButtonSegment(
              value: RunMode.gps,
              label: Text(
                l10n.treadmillModeGps,
                key: const Key('treadmill_mode_gps'),
              ),
            ),
            ButtonSegment(
              value: RunMode.treadmill,
              label: Text(
                l10n.treadmillModeBelt,
                key: const Key('treadmill_mode_belt'),
              ),
            ),
            ButtonSegment(
              value: RunMode.sport,
              label: Text(
                l10n.otherSportMode,
                key: const Key('treadmill_mode_sport'),
              ),
            ),
          ],
          selected: {_mode},
          onSelectionChanged: (v) => _setMode(v.first),
        ),
      ],
    ),
  );

  /// Wahl der Sportart (FR-0221) mit dem Hinweis zum Brustgurt und, in den
  /// ersten Seilspring-Einheiten, zu Wade und Achillessehne.
  Widget _sportCard(AppLocalizations l10n, TextTheme text) => RamuriCard(
    key: const Key('other_sport_card'),
    padding: const EdgeInsets.all(18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.otherSportChoiceTitle, style: text.titleMedium),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final s in OtherSport.values)
              ChoiceChip(
                key: Key('other_sport_${s.wire}'),
                avatar: Icon(otherSportIcon(s), size: 18),
                label: Text(otherSportName(l10n, s)),
                selected: _sport == s,
                onSelected: (_) => _setSport(s),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          l10n.otherSportChestStrapHint,
          key: const Key('other_sport_chest_hint'),
          style: text.bodySmall,
        ),
        if (_sport == OtherSport.rope && _ropeHint) ...[
          const SizedBox(height: 6),
          Text(
            l10n.otherSportRopeHint,
            key: const Key('other_sport_rope_hint'),
            style: text.bodySmall,
          ),
        ],
      ],
    ),
  );

  /// Ohne Pulssensor: Grund der Sperre und der Weg zum Nachtrag (FR-0199).
  Widget _sportLockCard(AppLocalizations l10n, TextTheme text) => RamuriCard(
    padding: const EdgeInsets.all(18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.otherSportNeedsSensor,
          key: const Key('other_sport_needs_sensor'),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          key: const Key('other_sport_manual_entry'),
          onPressed: _openManualEntry,
          child: Text(l10n.otherSportManualEntry),
        ),
      ],
    ),
  );

  /// Umschalter „Geplante Einheit“ | „Freier Lauf“ (Design `Start`). Ohne
  /// offene Einheit ist die erste Wahl aus und ein Satz sagt warum; „Freier
  /// Lauf“ heißt keine Führung.
  Widget _guidedToggle(AppLocalizations l10n) {
    final hasUnit = widget.plannedUnit != null;
    final minimum = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
      tapTargetSize: MaterialTapTargetSize.padded,
    );
    return RamuriCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SegmentedButton<bool>(
            key: const Key('guided_toggle'),
            showSelectedIcon: false,
            style: minimum,
            segments: [
              ButtonSegment(
                value: true,
                enabled: hasUnit,
                label: Text(
                  l10n.guidedPlanned,
                  key: const Key('guided_toggle_plan'),
                ),
              ),
              ButtonSegment(
                value: false,
                label: Text(
                  l10n.guidedFree,
                  key: const Key('guided_toggle_free'),
                ),
              ),
            ],
            selected: {_planned},
            onSelectionChanged: (v) => setState(() => _planned = v.first),
          ),
          if (!hasUnit) ...[
            const SizedBox(height: 10),
            Text(
              _warningActive ? l10n.guidedNoUnitWarning : l10n.guidedNoUnit,
              key: const Key('guided_no_unit'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }

  Widget _freeCard(AppLocalizations l10n, TextTheme text) => RamuriCard(
    padding: const EdgeInsets.all(18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.startFreeTitle, style: text.titleMedium),
        const SizedBox(height: 6),
        Text(
          _sportMode
              ? l10n.otherSportBody
              : _treadmill
              ? l10n.treadmillBody
              : l10n.startFreeBody,
          style: text.bodySmall!.copyWith(height: 1.45),
        ),
      ],
    ),
  );

  /// Karte der Einheit: Art, Dauer, Ziel (Puls, wo bekannt) und die Abschnitte
  /// mit ihrer Zielintensität.
  Widget _plannedCard(AppLocalizations l10n, TextTheme text) {
    final unit = widget.plannedUnit!;
    final segments = guidedSegmentsOf(unit);
    final c = RamuriColors.of(context);
    final formatter = AppSettingsScope.formatterOf(context);
    final hr = segments
        .map((s) => s.intensity)
        .firstWhere(
          (t) => t?.hrMinBpm != null && t?.hrMaxBpm != null,
          orElse: () => null,
        );
    return RamuriCard(
      key: const Key('guided_card'),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            planKindName(l10n, unit.kind),
            key: const Key('guided_kind'),
            style: text.titleMedium,
          ),
          const SizedBox(height: 2),
          Text(
            planDurationText(l10n, unit.minutes),
            key: const Key('guided_duration'),
            style: text.bodyMedium,
          ),
          if (hr != null)
            Text(
              l10n.guidedTarget(
                l10n.planHeartRateRange(hr.hrMinBpm!, hr.hrMaxBpm!),
              ),
              key: const Key('guided_target'),
              style: text.bodySmall,
            ),
          const SizedBox(height: 12),
          for (final (i, g) in groupSegments(segments).indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Semantics(
                container: true,
                child: _segmentGroup(l10n, text, c, formatter, g, i),
              ),
            ),
        ],
      ),
    );
  }

  /// Ein Abschnitt als Zeile mit Zielen; eine wiederholte Folge in einer Zeile
  /// („8× 1 min Laufen · 2 min Gehen“), mit Zielen darunter, wo es welche gibt.
  Widget _segmentGroup(
    AppLocalizations l10n,
    TextTheme text,
    RamuriColors c,
    UnitFormatter formatter,
    SegmentGroup g,
    int i,
  ) {
    if (g.repeat == 1) {
      return PlanSegmentRow(
        key: Key('guided_segment_$i'),
        segment: g.segments.first,
        formatter: formatter,
        colors: c,
      );
    }
    final parts = g.segments
        .map(
          (s) =>
              '${planSegmentDuration(l10n, s.durationSeconds)} '
              '${planSegmentName(l10n, s.kind)}',
        )
        .join(' · ');
    return Column(
      key: Key('guided_segment_$i'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.guidedRepeat(g.repeat, parts),
                key: Key('guided_group_$i'),
                style: text.titleSmall,
              ),
            ),
            Text(
              planSegmentDuration(l10n, g.durationSeconds),
              style: text.labelMedium,
            ),
          ],
        ),
        if (g.segments.any((s) => s.intensity != null))
          for (final s in g.segments)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 12),
              child: PlanSegmentRow(
                segment: s,
                formatter: formatter,
                colors: c,
              ),
            ),
      ],
    );
  }

  /// Startgeschwindigkeit (Pflicht) und Steigung (freiwillig) des Bands.
  Widget _beltCard(AppLocalizations l10n, TextTheme text) {
    final unit = _unit;
    final unitLabel = unit == DistanceUnit.miles
        ? l10n.treadmillUnitMph
        : l10n.treadmillUnitKmh;
    final lang = Localizations.localeOf(context).languageCode;
    String t(int tenths) => TreadmillUnits.speedText(
      unit,
      TreadmillUnits.mpsFromDisplay(unit, tenths / 10),
      lang,
    );
    final min = t(TreadmillUnits.minTenths(unit));
    final max = t(TreadmillUnits.maxTenths(unit));
    final speedEmpty = _speedField.text.trim().isEmpty;
    final inclineOk = _incline.$1;
    const keyboard = TextInputType.numberWithOptions(decimal: true);
    return RamuriCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        children: [
          TextField(
            key: const Key('treadmill_start_speed'),
            controller: _speedField,
            keyboardType: keyboard,
            decoration: InputDecoration(
              labelText: l10n.treadmillSpeedLabel(unitLabel),
              helperText: l10n.treadmillSpeedHelper(min, max, unitLabel),
              errorText: speedEmpty || _beltSpeed != null
                  ? null
                  : l10n.treadmillSpeedError(min, max, unitLabel),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('treadmill_start_incline'),
            controller: _inclineField,
            keyboardType: keyboard,
            decoration: InputDecoration(
              labelText: l10n.treadmillInclineLabel,
              helperText: l10n.treadmillInclineHelper,
              errorText: inclineOk ? null : l10n.treadmillInclineError,
            ),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
    );
  }

  /// Seite „Lauf vorbereiten“ (FR-0210, Design `Start`). Der GPS-Zustand ist
  /// eine Anzeige; gesperrt wird nur nach FR-0195, dann steht der Grund da und
  /// „Los“ tut nichts.
  Widget _prepareBody(BuildContext context, AppLocalizations l10n) {
    final c = RamuriColors.of(context);
    final text = Theme.of(context).textTheme;
    final blocked = !_checking && !_ready;
    final cadence = _cadenceAvailability;
    final (blockText, blockActions, blockKey) = blocked
        ? _blockParts(l10n)
        : ('', const <Widget>[], const Key('run_explanation'));
    final gps = _checking
        ? Text(
            l10n.runChecking,
            key: const Key('run_checking'),
            style: text.labelMedium,
            textAlign: TextAlign.end,
          )
        : _ready
        ? _gpsGood
              ? Text(
                  l10n.startGpsGood,
                  key: const Key('start_gps_good'),
                  style: text.labelMedium!.copyWith(color: c.accent),
                  textAlign: TextAlign.end,
                )
              : Text(
                  l10n.startGpsSearching,
                  key: const Key('start_gps_searching'),
                  style: text.labelMedium,
                  textAlign: TextAlign.end,
                )
        : Text(
            l10n.startGpsBlocked,
            key: const Key('start_gps_blocked'),
            style: text.labelMedium!.copyWith(color: c.danger),
            textAlign: TextAlign.end,
          );
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            children: [
              if (blocked) ...[
                RamuriCard(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.runBlockTitle, style: text.titleMedium),
                      const SizedBox(height: 8),
                      Text(blockText, key: blockKey),
                      const SizedBox(height: 12),
                      for (final a in blockActions) ...[
                        a,
                        const SizedBox(height: 8),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 18),
              ],
              _modeCard(l10n, text),
              const SizedBox(height: 18),
              if (_treadmill) ...[
                _beltCard(l10n, text),
                const SizedBox(height: 18),
              ],
              if (_sportMode) ...[
                _sportCard(l10n, text),
                const SizedBox(height: 18),
                ListenableBuilder(
                  listenable: widget.sensors ?? _noChange,
                  builder: (context, _) => _sportLocked
                      ? Padding(
                          padding: const EdgeInsets.only(bottom: 18),
                          child: _sportLockCard(l10n, text),
                        )
                      : const SizedBox.shrink(),
                ),
              ] else ...[
                _guidedToggle(l10n),
                const SizedBox(height: 18),
              ],
              _guided ? _plannedCard(l10n, text) : _freeCard(l10n, text),
              const SizedBox(height: 18),
              Semantics(
                container: true,
                label: l10n.startReadiness,
                child: RamuriCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 6,
                  ),
                  child: Column(
                    children: [
                      if (!_noLocation)
                        RamuriReadinessRow(
                          icon: Icons.place_outlined,
                          title: l10n.startGps,
                          trailing: gps,
                        ),
                      ListenableBuilder(
                        listenable: widget.sensors ?? _noChange,
                        builder: (context, _) {
                          final connected = _sensorConnected;
                          return RamuriReadinessRow(
                            icon: Icons.favorite_border,
                            title: l10n.startSensor,
                            divider: !_sportMode,
                            subtitle: connected
                                ? l10n.startSensorConnected
                                : _sportMode
                                ? l10n.otherSportSensorRequired
                                : l10n.startSensorOptional,
                            muted: !connected,
                            trailing: widget.sensors == null
                                ? null
                                : TextButton(
                                    key: const Key('start_sensor_pair'),
                                    onPressed: _pairSensors,
                                    child: Text(l10n.startSensorPair),
                                  ),
                          );
                        },
                      ),
                      if (!_sportMode)
                        RamuriReadinessRow(
                          icon: Icons.directions_walk,
                          title: l10n.startCadence,
                          divider: false,
                          muted: cadence == CadenceAvailability.noSensor,
                          trailing: cadence == null
                              ? null
                              : Text(
                                  key: const Key('start_cadence_source'),
                                  switch (cadence) {
                                    CadenceAvailability.available =>
                                      l10n.startCadencePhone,
                                    CadenceAvailability.permissionDenied =>
                                      l10n.startCadenceAsk,
                                    CadenceAvailability.noSensor =>
                                      l10n.startCadenceNone,
                                  },
                                  style: text.labelMedium!.copyWith(
                                    color:
                                        cadence == CadenceAvailability.noSensor
                                        ? c.textMuted
                                        : c.accent,
                                  ),
                                  textAlign: TextAlign.end,
                                ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              if (!_noLocation)
                RamuriCard(
                  radius: 18,
                  padding: EdgeInsets.zero,
                  child: SwitchListTile(
                    key: const Key('start_autopause'),
                    title: Text(l10n.startAutoPause, style: text.labelMedium),
                    subtitle: Text(l10n.startAutoPauseHint),
                    value: _autoPause,
                    onChanged: _setAutoPause,
                  ),
                ),
              if (!_sportMode) ...[
                const SizedBox(height: 12),
                RamuriCard(
                  radius: 18,
                  padding: EdgeInsets.zero,
                  child: SwitchListTile(
                    key: const Key('guided_voice'),
                    title: Text(l10n.guidedVoiceTitle, style: text.labelMedium),
                    subtitle: Text(l10n.guidedVoiceHint),
                    value: _voiceOn,
                    onChanged: _setVoice,
                  ),
                ),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            children: [
              ListenableBuilder(
                listenable: widget.sensors ?? _noChange,
                builder: (context, _) => RamuriStartButton(
                  key: const Key('run_start_ready'),
                  label: l10n.startGo,
                  semanticLabel: l10n.startGoSemantics,
                  onPressed:
                      _ready &&
                          (!_treadmill || _beltInputValid) &&
                          !_sportLocked
                      ? () => _check(askUser: false, autoStart: true)
                      : null,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                l10n.startScreenOff,
                style: text.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ],
    );
  }

  static final Listenable _noChange = ChangeNotifier();

  Widget _explanation(
    AppLocalizations l10n,
    String text,
    List<Widget> actions, {
    Key? blockKey,
  }) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Text(l10n.runBlockTitle, style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 12),
      Text(text, key: blockKey ?? const Key('run_explanation')),
      const SizedBox(height: 16),
      for (final a in actions) ...[a, const SizedBox(height: 8)],
    ],
  );
}
