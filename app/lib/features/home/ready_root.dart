import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter/material.dart';

import '../reminders/reminder_controller.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/ui.dart';
import '../health/health_connect_controller.dart';
import '../health/health_connect_scope.dart';
import '../map/map_consent_controller.dart';
import '../map/map_consent_scope.dart';
import '../map/map_services.dart';
import '../plan/plan_started_unit.dart';
import '../recalculation/recalculation_controller.dart';
import '../storage/deletion.dart';
import '../sensors/sensor_manager.dart';
import '../settings/app_settings.dart';
import '../run/run_flow_screen.dart';
import '../run/run_ports.dart';
import '../health/health_connect_screen.dart';
import '../setup/setup_screen.dart';
import 'app_shell.dart';
import 'data_changes.dart';
import 'welcome_screen.dart';

/// Wurzel nach dem Öffnen des Speichers: lädt die Einstellungen, bietet beim
/// ersten Start Willkommen (FR-0207) und die Einrichtung an (FR-0001) und
/// zeigt danach die Startseite.
class ReadyRoot extends StatefulWidget {
  const ReadyRoot({
    super.key,
    required this.session,
    required this.clock,
    required this.permissions,
    required this.runPorts,
    required this.sensors,
    required this.welcome,
    this.map,
    this.mapHolder,
    this.healthConnect,
    this.healthHolder,
  });

  /// Kartenanbieter (WP13); `null`: nicht verdrahtet, dann gibt es keinen Kartencontroller.
  final MapServices? map;

  /// Wo der Controller dieser Sitzung für Seiten über dem Navigator abgelegt wird.
  final MapConsentHolder? mapHolder;

  /// Health Connect (WP32); `null`: nicht verdrahtet, dann gibt es keinen Controller und keinen Import.
  final HealthConnectPort? healthConnect;

  /// Wo der Controller dieser Sitzung für Seiten über dem Navigator abgelegt wird.
  final HealthConnectHolder? healthHolder;

  /// Merker über der Sitzung: Willkommen wurde in diesem Prozess bestätigt.
  final WelcomeFlag welcome;
  final StorageSession session;
  final PermissionStatusPort permissions;
  final RunPorts runPorts;
  final SensorManager sensors;
  final Clock clock;

  @override
  State<ReadyRoot> createState() => _ReadyRootState();
}

class _ReadyRootState extends State<ReadyRoot> {
  late Future<AppSettings> _settings;
  late final RecalculationService _recalculationService;
  late final RecalculationController _recalculation;
  late final RunRecovery _recovery;
  final DataChanges _changes = DataChanges();
  MapConsentController? _mapConsent;
  HealthConnectController? _health;

  /// Fertig, sobald Willkommen nicht (mehr) im Weg ist; der Dialog zum
  /// unterbrochenen Lauf wartet darauf und überdeckt Willkommen nicht.
  final Completer<void> _welcomeResolved = Completer<void>();

  @override
  void initState() {
    super.initState();
    // Dienste für die Neuberechnung (FR-0006): eine Instanz je Sitzung; beim
    // Start wird ein offenes Angebot gelesen.
    _recalculationService = RecalculationService(
      session: widget.session,
      clock: widget.clock,
      calculation: ValueCalculationService(
        session: widget.session,
        clock: widget.clock,
      ),
    );
    _recalculation = RecalculationController(
      _recalculationService,
      onStart: () => completePendingValueRefresh(widget.session, widget.clock),
      onDataChanged: _changes.changed,
    );
    _recalculation.start();
    // Nur der Speicher wird angebunden; der Sensor bleibt unberührt.
    widget.sensors
        .attachStore(widget.session.devices)
        .catchError((Object _) {});
    _recovery = RunRecovery(
      clock: widget.clock,
      runs: widget.session.runs,
      rawData: widget.session.rawData,
      markers: widget.session.markers,
    );
    // Nur lesen, nie fragen: Gefragt wird beim ersten Öffnen einer Karte (ADR-0009 Punkt 3).
    final map = widget.map;
    if (map != null) {
      _mapConsent = MapConsentController(
        store: widget.session.consents,
        clock: widget.clock,
        services: map,
      );
      widget.mapHolder?.bind(_mapConsent!);
    }
    // Health Connect (WP32): Controller der Sitzung; der Import beim App-Start folgt nach der Einrichtung.
    final hc = widget.healthConnect;
    final session = widget.session;
    if (hc != null && session is HealthStorage) {
      _health = HealthConnectController(
        port: hc,
        store: (session as HealthStorage).health,
        settings: session.settings,
        consentStore: session.consents,
        clock: widget.clock,
      );
      widget.healthHolder?.bind(_health!);
    }
    _loadSettings();
    _importWhenSetupDone();
    // Einmal je Start nach der Storage-Freigabe (FR-0193).
    WidgetsBinding.instance.addPostFrameCallback((_) => _offerRecovery());
  }

  AppSettings? _importSettings;
  VoidCallback? _importListener;

  /// Import beim App-Start erst nach abgeschlossener Einrichtung: nicht in der Einrichtung und nicht vor einer
  /// Wiederherstellung (die eine neue Sitzung und damit eine neue Wurzel bringt).
  Future<void> _importWhenSetupDone() async {
    final health = _health;
    if (health == null) return;
    try {
      final settings = await _settings;
      if (!mounted) return;
      if (!settings.setupDone) {
        final done = Completer<void>();
        void listener() {
          if (settings.setupDone && !done.isCompleted) done.complete();
        }

        _importSettings = settings;
        _importListener = listener;
        settings.addListener(listener);
        await done.future;
      }
    } on Object {
      return;
    }
    if (!mounted) return;
    await health.importThenLoad(HealthImportTrigger.appStart);
    // SEC-0007: Offene Löschfragen (Recht fehlt, Health Connect weg) beim Öffnen der App, nicht nur auf der Seite.
    if (mounted) {
      await askOpenHealthQuestions(context, health, skipDeferred: true);
    }
  }

  /// Bietet einen unterbrochenen Lauf an, solange es einen gibt und kein
  /// Dienst läuft; ohne Frist und ohne Neustart von selbst. Das Angebot kehrt
  /// wieder, bis der Lauf beendet ist (auch nach Rückkehr aus dem Lauf oder
  /// nach einem Fehler beim Speichern).
  Future<void> _offerRecovery() async {
    while (mounted) {
      final StoredRun? run;
      try {
        final service = widget.runPorts.recordingService;
        run = await _recovery.pending(
          serviceRunning: service != null && await service.isRunning(),
        );
        // Erst Einstellungen und Willkommen abwarten: der Dialog überdeckt
        // den Willkommensbildschirm nicht.
        await _settings;
        await _welcomeResolved.future;
      } on Object {
        return;
      }
      if (!mounted) return;
      if (run == null) {
        await _settleStartedUnit();
        return;
      }
      var clockBehind = false;
      try {
        clockBehind = await _recovery.clockBehind(run);
      } on Object {
        // Der Hinweis ist nur eine Zugabe; ohne ihn bleibt der Dialog gleich.
      }
      if (!mounted) return;
      final resume = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          final l10n = AppLocalizations.of(context);
          return AlertDialog(
            key: const Key('recover_dialog'),
            title: Text(l10n.recoverTitle),
            content: Text(
              clockBehind
                  ? '${l10n.recoverBody}\n\n${l10n.recoverClockBehind}'
                  : l10n.recoverBody,
            ),
            actions: [
              TextButton(
                key: const Key('recover_save'),
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(l10n.recoverSave),
              ),
              FilledButton(
                key: const Key('recover_resume'),
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(l10n.recoverResume),
              ),
            ],
          );
        },
      );
      if (!mounted || resume == null) return;
      if (resume) {
        await Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) => RunFlowScreen(
              session: widget.session,
              clock: widget.clock,
              ports: widget.runPorts,
              permissions: widget.permissions,
              serialize: _recalculation.exclusive,
              resumeRunId: run!.id,
              recalculation: _recalculation,
            ),
          ),
        );
        _changes.changed();
        // Zurück aus dem Lauf-Bildschirm: Wurde der Lauf beendet oder läuft
        // der Dienst, bietet `pending` nichts mehr an; blieb er offen (etwa
        // Fortsetzen ohne Standortrecht, FR-0195), kommt das Angebot wieder.
        continue;
      }
      // Scheitert das Speichern, wird erneut angeboten: Der Nutzer muss
      // speichern können, ohne dass der Prozess endet.
      await _saveRecovered(run.id);
    }
  }

  /// Kein unterbrochener Lauf (mehr): Gehört ein beendeter Lauf zu einer
  /// über „Einheit starten“ gestarteten Einheit (nach Wiederaufnahme, nach
  /// dem Speichern hier oder nach einem Ende der App zwischen Lauf-Ende und
  /// Zuordnung), wird er ihr jetzt zugeordnet (WP22). Ein Fehler hier holt der
  /// nächste Start nach; der Merker bleibt dann stehen.
  Future<void> _settleStartedUnit() async {
    try {
      final result = await PlanStartedUnitStore(
        session: widget.session,
        clock: widget.clock,
      ).settle(serialize: _recalculation.exclusive);
      if (result != null) _changes.changed();
    } on Object {
      // Siehe oben.
    }
  }

  Future<bool> _saveRecovered(int runId) async {
    final messenger = ScaffoldMessenger.of(context);
    final failed = AppLocalizations.of(context).recoverSaveFailed;
    try {
      final saved = await _recovery.saveFinished(runId);
      if (saved != null) {
        _changes.changed();
        // Die Werte des Laufs wie nach einem normalen Ende (FR-0006); ein
        // Fehler hier holt der nächste Start nach.
        await _recalculation.exclusive(() async {
          await ValueCalculationService(
            session: widget.session,
            clock: widget.clock,
          ).calculateAfterRunTracked(runId);
        });
      }
      return true;
    } on Object {
      messenger.showSnackBar(SnackBar(content: Text(failed)));
      return false;
    }
  }

  /// Erinnerungen (FR-0174): Sitzung und Texte der App-Sprache anbinden; jede
  /// gemeldete Datenänderung (Lauf, Neuberechnung, Zuordnung) plant neu.
  ReminderController? _reminders;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reminders = ReminderScope.read(context);
    if (reminders != null && !identical(reminders, _reminders)) {
      _reminders = reminders;
      reminders.attach(widget.session);
      _changes.addListener(reminders.sync);
    }
    reminders?.texts = AppReminderTexts(
      AppLocalizations.of(context),
      MaterialLocalizations.of(context),
      use24h: MediaQuery.alwaysUse24HourFormatOf(context),
    );
  }

  @override
  void dispose() {
    final reminders = _reminders;
    if (reminders != null) {
      _changes.removeListener(reminders.sync);
      reminders.detach(widget.session);
    }
    final mapConsent = _mapConsent;
    if (mapConsent != null) {
      widget.mapHolder?.unbind(mapConsent);
      mapConsent.dispose();
    }
    final waiting = _importListener;
    if (waiting != null) _importSettings?.removeListener(waiting);
    final health = _health;
    if (health != null) {
      widget.healthHolder?.unbind(health);
      health.dispose();
    }
    _recalculation.dispose();
    _recalculationService.dispose();
    _changes.dispose();
    super.dispose();
  }

  void _loadSettings() {
    // Der Halter im Scope über dem Navigator bekommt die Einstellungen, bevor
    // diese Seite sie zeigt; so sehen auch per Navigator.push geöffnete Seiten
    // sie.
    final holder = AppSettingsScope.holderOf(context);
    _settings = AppSettings.load(widget.session.settings, widget.clock).then((
      s,
    ) {
      holder.attach(s);
      // Wer die Einrichtung abgeschlossen hat, sieht Willkommen nie wieder,
      // auch nicht in einer neuen Sitzung nach einem Import.
      if (s.setupDone) widget.welcome.confirmed = true;
      if (widget.welcome.confirmed && !_welcomeResolved.isCompleted) {
        _welcomeResolved.complete();
      }
      return s;
    });
  }

  void _confirmWelcome() {
    setState(() => widget.welcome.confirmed = true);
    if (!_welcomeResolved.isCompleted) _welcomeResolved.complete();
  }

  Future<void> _finishSetup(AppSettings settings) async {
    final messenger = ScaffoldMessenger.of(context);
    final failed = AppLocalizations.of(context).settingsSaveFailed;
    try {
      await settings.markSetupDone();
    } on StorageException {
      messenger.showSnackBar(SnackBar(content: Text(failed)));
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<AppSettings>(
    future: _settings,
    builder: (context, snapshot) {
      final l10n = AppLocalizations.of(context);
      if (snapshot.hasError) {
        return Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(l10n.settingsLoadFailed, textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  RamuriSecondaryButton(
                    key: const Key('settings_load_retry'),
                    onPressed: () => setState(_loadSettings),
                    label: l10n.notOpenableRetry,
                  ),
                ],
              ),
            ),
          ),
        );
      }
      final settings = snapshot.data;
      if (settings == null) {
        return const RamuriDarkScope(
          child: Scaffold(body: Center(child: CircularProgressIndicator())),
        );
      }
      return ListenableBuilder(
        listenable: settings,
        builder: (context, _) => settings.setupDone
            ? AppShell(
                session: widget.session,
                clock: widget.clock,
                permissions: widget.permissions,
                recalculation: _recalculation,
                runPorts: widget.runPorts,
                sensors: widget.sensors,
                changes: _changes,
              )
            : !widget.welcome.confirmed
            ? WelcomeScreen(onStart: _confirmWelcome)
            : SetupScreen(
                session: widget.session,
                clock: widget.clock,
                onFinished: () => _finishSetup(settings),
                serialize: _recalculation.exclusive,
              ),
      );
    },
  );
}
