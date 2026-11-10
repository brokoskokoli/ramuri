import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../ui/ui.dart';
import '../recalculation/recalculation_controller.dart';
import '../sensors/sensor_manager.dart';
import '../sensors/sensors_screen.dart';
import '../settings/app_settings.dart';
import 'live_run_view.dart';
import 'run_controller.dart';
import 'run_ports.dart';

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
    this.tickEvery = const Duration(seconds: 1),
    this.serialize,
    this.resumeRunId,
    this.sensors,
    this.recalculation,
    this.onFinished,
  });

  final StorageSession session;
  final Clock clock;
  final RunPorts ports;
  final PermissionStatusPort permissions;
  final Duration tickEvery;

  /// Sensorverwaltung für „Koppeln“ (FR-0011). Ohne sie fehlt der Knopf.
  final SensorManager? sensors;

  /// Für „Details“ nach dem Lauf; ohne sie fehlt der Knopf.
  final RecalculationController? recalculation;

  /// Setzt diesen unterbrochenen Lauf fort (FR-0193); das Start-Gate gilt.
  final int? resumeRunId;

  /// Siehe [RunController.serialize].
  final Future<void> Function(Future<void> Function() action)? serialize;

  /// Wird genau einmal mit der Nummer des Laufs gerufen, sobald er beendet
  /// und seine Berechnung abgeschlossen ist (WP22: Zuordnung zur gestarteten
  /// Plan-Einheit). Ein Lauf, der nicht beendet wird, meldet nichts.
  final void Function(int runId)? onFinished;

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
    unawaited(_loadCadence());
    _check(askUser: false, autoStart: !_preparing);
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
                const PreprocessingParameters.v4().positionMaxAccuracyMeters;
        _gpsStale?.cancel();
        _gpsStale = good
            ? Timer(const PreprocessingParameters.v4().gapMaxDuration, _gpsLost)
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
    final result = await RecordingStartGate(widget.ports.access)
        .check(askUser: askUser);
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
      _startGps();
      return;
    }
    _starting = true;
    final RunController controller;
    try {
      await _autoPauseLoaded;
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

  RunController _newController() {
    final controller = RunController(
      clock: widget.clock,
      storage: widget.session,
      location: widget.ports.location,
      sensors: widget.ports.heartRateRun?.call(),
      service: widget.ports.recordingService,
      cadence: widget.ports.cadence,
      resumeRunId: widget.resumeRunId,
      initialAutoPause: _preparing ? _autoPause : null,
      tickEvery: widget.tickEvery,
      serialize: widget.serialize,
    );
    final onFinished = widget.onFinished;
    if (onFinished != null) {
      var reported = false;
      controller.addListener(() {
        final id = controller.runId;
        if (reported ||
            id == null ||
            controller.phase != RecordingPhase.finished ||
            !controller.calculationSettled) {
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
    try {
      await widget.ports.requestActivityRecognition?.call();
    } catch (_) {
      // Ohne Berechtigung ist die Schrittfrequenz nicht verfügbar.
    }
  }

  Future<void> _retryStart() async {
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
            body: _explanation(l10n, l10n.runStartFailed, [
              FilledButton(
                key: const Key('run_start_retry'),
                onPressed: _retryStart,
                child: Text(l10n.notOpenableRetry),
              ),
            ]),
          );
        }
        return LiveRunView(
          controller: controller,
          formatter: AppSettingsScope.formatterOf(context),
          clock: widget.clock,
          recalculation: widget.recalculation,
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
    final actions = <Widget>[
      if (canAsk)
        FilledButton(
          key: const Key('run_block_ask'),
          onPressed: () => _check(askUser: true, autoStart: false),
          child: Text(l10n.runActionAsk),
        ),
      if (canOpenSettings)
        OutlinedButton(
          key: const Key('run_block_settings'),
          onPressed: () => widget.permissions.openSystemSettings(),
          child: Text(l10n.runActionSettings),
        ),
      // Ohne Abfrage lesen: nach Schalter oder Einstellungen genügt das.
      if (!canAsk)
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
              RamuriCard(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.startFreeTitle, style: text.titleMedium),
                    const SizedBox(height: 6),
                    Text(
                      l10n.startFreeBody,
                      style: text.bodySmall!.copyWith(height: 1.45),
                    ),
                  ],
                ),
              ),
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
                      RamuriReadinessRow(
                        icon: Icons.place_outlined,
                        title: l10n.startGps,
                        trailing: gps,
                      ),
                      ListenableBuilder(
                        listenable: widget.sensors ?? _noChange,
                        builder: (context, _) {
                          final connected =
                              widget.sensors?.connectedIds.isNotEmpty ?? false;
                          return RamuriReadinessRow(
                            icon: Icons.favorite_border,
                            title: l10n.startSensor,
                            subtitle: connected
                                ? l10n.startSensorConnected
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
                                  color: cadence == CadenceAvailability.noSensor
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
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            children: [
              RamuriStartButton(
                key: const Key('run_start_ready'),
                label: l10n.startGo,
                semanticLabel: l10n.startGoSemantics,
                onPressed: _ready
                    ? () => _check(askUser: false, autoStart: true)
                    : null,
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
