import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../measure/morning_entry.dart';
import '../../l10n/app_localizations.dart';
import '../../offload_scope.dart';
import '../../ui/ui.dart';
import '../health/health_connect_scope.dart';
import '../health/health_connect_screen.dart';
import '../history/run_detail_screen.dart';
import '../plan/plan_change_card.dart';
import '../plan/plan_controller.dart';
import '../plan/plan_goal_form.dart';
import '../plan/plan_adapt_recommendation.dart';
import '../plan/plan_recovery_trigger.dart';
import '../plan/plan_started_unit.dart';
import '../../ui/format/plan_texts.dart';
import '../plan/plan_underload_card.dart';
import '../recalculation/recalculation_controller.dart';
import '../run/run_ports.dart';
import '../measure/morning_belt.dart';
import '../sensors/sensor_manager.dart';
import '../settings/app_settings.dart';
import '../../ui/format/unit_format.dart';
import '../../data_changes.dart';
import '../readiness/readiness_card.dart';
import '../readiness/readiness_detail_screen.dart' show ReadinessActions;
import '../measure/resting_measure_launcher.dart' show PpgCameraScope;
import '../readiness/readiness_service.dart';
import '../readiness/readiness_today.dart';
import 'home_recovery.dart';
import 'home_start_row.dart';
import 'overview_screen.dart';
import 'run_starter.dart';
import '../plan/plan_done_texts.dart';

/// Bereich „Heute“ in der Hülle ([AppShell]) nach FR-0209: Logo, Datum,
/// Profil-Symbol, „Frei laufen“, die Woche Montag bis Sonntag mit Laufhaken
/// und Kilometersumme und der letzte Lauf. Mit Plan (Phase 2, WP22 Teil D)
/// zusätzlich die Karte „Heute geplant“ mit „Einheit starten“ und das
/// Wochenziel als Zeit; ohne Plan der Einstieg „Ziel anlegen“. Ein Lauf aus
/// „Einheit starten“ wird nach dem Beenden dieser Einheit zugeordnet
/// ([PlanStartedUnitStore]); nach „Frei laufen“ fragt die App, wenn heute
/// eine Einheit offen ist. Gebaut wird er erst,
/// wenn der Speicher bereit ist ([session] ist die offene Sitzung) und die
/// Ersteinrichtung erledigt oder übersprungen ist. Die Hülle baut ihn bei
/// jeder Datenmeldung ([DataChanges]) neu; dabei lädt er neu.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.session,
    required this.clock,
    required this.permissions,
    required this.recalculation,
    required this.runPorts,
    required this.sensors,
    required this.changes,
  });

  final StorageSession session;
  final PermissionStatusPort permissions;
  final RunPorts runPorts;
  final SensorManager sensors;
  final Clock clock;
  final RecalculationController recalculation;
  final DataChanges changes;

  /// Nur für Tests: umhüllt das Ergebnis jedes Ladelaufs der Erholung;
  /// [call] zählt die Läufe einer Seite ab 1. Gerechnet wird mit dem Stand
  /// beim Start des Laufs, der Haken kann nur die Übergabe des Ergebnisses
  /// verzögern (Reihenfolge der Läufe prüfen). In Release-Builds ohne Wirkung.
  @visibleForTesting
  static Future<ReadinessSnapshot?> Function(
    int call,
    Future<ReadinessSnapshot?> load,
  )?
  debugWrapReadiness;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

/// Geladene Läufe: dieselbe Quelle und dieselben Kennzahlen wie die Statistik.
class _Data {
  _Data(this.overviews) : figures = [for (final o in overviews) o.toFigures()];
  final List<RunOverview> overviews;
  final List<RunFigures> figures;
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  late Future<_Data> _future = _load();

  /// Hinweis des Tages und Pausenfrage (WP23 D2); Fehler bleiben still, die
  /// Karten fehlen dann. Beim Öffnen und bei [_reload] erst nach der Prüfung
  /// beim Öffnen geladen ([_openPlan]), damit es nur einen Stand gibt.
  late Future<HomeHints> _hints;

  /// Erholung der erweiterten Stufe (WP34 D1); `null` bei Fehler, dann gilt
  /// die Basisstufe.
  late Future<ReadinessSnapshot?> _readiness = _loadReadiness();

  /// Angezeigter Stand der Karten über der Startkarte: Hinweise, Erholung und
  /// der Planstand, zu dem sie gehören. Im State gehalten und erst ersetzt,
  /// wenn ein neuer Stand vollständig geladen ist ([_renewCards]); bis dahin
  /// bleiben die bisherigen Karten stehen. `null` nur vor dem ersten Laden.
  ({HomeHints hints, ReadinessSnapshot? readiness, PlanViewState plan})?
  _shownCards;

  /// Lauf von [_renewCards]; nur der neueste darf [_shownCards] setzen.
  int _cardsRun = 0;
  bool _busy = false;

  /// Neu laden der Hinweise und/oder der Erholung; ohne Angabe nur den
  /// Planstand der Karten erneuern. Im `setState` aufrufen. Der neue Stand
  /// ersetzt den angezeigten erst, wenn Hinweise und Erholung da sind –
  /// Planstand und Hinweise wechseln so im selben Frame.
  void _renewCards({bool hints = false, bool readiness = false}) {
    if (hints) _hints = _loadHints();
    if (readiness) _readiness = _loadReadiness();
    final run = ++_cardsRun;
    Future.wait<Object?>([_hints, _readiness]).then((v) {
      if (!mounted || run != _cardsRun) return;
      setState(() {
        _shownCards = (
          hints: v[0]! as HomeHints,
          readiness: v[1] as ReadinessSnapshot?,
          plan: _plan.state,
        );
      });
    });
  }

  /// Neu laden der Morgenkarte mit der Seite (Entwicklermodus, heutige Messung).
  int _morningEpoch = 0;

  /// Ziel und Plan (nur lesen; geschrieben wird über das Zielformular und die
  /// Zuordnung).
  late final PlanController _plan = PlanController(
    session: widget.session,
    clock: widget.clock,
    // Wie die Plan-Seite: die Wochenprüfung beim Öffnen nimmt den Wert von
    // heute über PAR-173 auf (FR-0158, nur bei „adaptiv“).
    readinessToday: planReadinessSource(
      () => loadReadinessToday(
        session: widget.session,
        clock: widget.clock,
        recalculation: widget.recalculation.service,
      ),
    ),
    // Zuordnung beim Öffnen hinter der Wertberechnung (PAR-231); ohne
    // Datenmeldung danach, sonst lüde die Seite neu und öffnete erneut.
    exclusive: widget.recalculation.serialized,
  );

  /// Der Ortstag, für den die Seite zuletzt geladen und gebaut wurde.
  late String _shownDay;

  @override
  void initState() {
    super.initState();
    _shownDay = _today;
    WidgetsBinding.instance.addObserver(this);
    _plan.addListener(_onPlan);
    // Health Connect (WP32): beim Öffnen von Heute importieren; die Sperre hält der Dienst.
    _importHealth();
    // Wie die Plan-Seite: wöchentliche Prüfung beim Öffnen (FR-0158), dann
    // laden; derselbe Aufruf, keine zweite Fassung der Prüfung. Die Hinweise
    // lädt erst der Stand danach (PAR-202), einmal.
    _hints = _openPlan();
    _renewCards();
  }

  /// Import beim Öffnen von „Heute“ und danach offene Löschfragen (SEC-0007); Fehler bleiben still.
  Future<void> _importHealth() async {
    final health = HealthConnectScope.of(context);
    if (health == null) return;
    await health.importThenLoad(HealthImportTrigger.todayOpened);
    // Neue Importdaten zählen sofort für die Erholung.
    if (mounted) {
      setState(() {
        _renewCards(readiness: true);
      });
    }
    if (mounted) {
      await askOpenHealthQuestions(context, health, skipDeferred: true);
      // Eine Antwort auf die Löschfrage widerruft die Einwilligung: die
      // Erholung darf danach keine Werte dieser Art mehr zeigen (SEC-0007).
      if (mounted) {
        setState(() {
          _renewCards(readiness: true);
        });
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _plan.removeListener(_onPlan);
    _plan.dispose();
    super.dispose();
  }

  /// Neuer Planstand: Startkarte sofort, die Karten darüber mit den
  /// geladenen Hinweisen. Während einer Aktion ([_busy]) erneuert die Aktion
  /// die Karten selbst, wenn auch die Hinweise neu geladen sind; sonst fiele
  /// z. B. die Erinnerung einen Frame vor der Warnsignal-Karte weg.
  void _onPlan() {
    if (!mounted) return;
    setState(() {
      if (!_busy) _renewCards();
    });
  }

  /// Bleibt der Prozess über Mitternacht am Leben, steht beim Fortsetzen noch
  /// der alte Tag (Datum, Heute-Kreis, Woche, Summe): bei einem anderen Tag
  /// lädt die Seite neu (FR-0209).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _today != _shownDay) _reload();
  }

  Future<_Data> _load() async => _Data(
    await RunOverviewService(
      session: widget.session,
      clock: widget.clock,
      offload: OffloadScope.of(context),
    ).load(),
  );

  void _reload() {
    setState(() {
      _morningEpoch++;
      _shownDay = _today;
      _future = _load();
      _hints = _openPlan();
      _renewCards(readiness: true);
    });
  }

  /// Prüfung beim Öffnen; danach die Hinweise laden, weil sie vom Plan
  /// abhängen (der Neustart zur Pause ändert den Text, PAR-202). `open`
  /// fängt seine Fehler selbst ab.
  Future<HomeHints> _openPlan() async {
    await _plan.open();
    return _loadHints();
  }

  Future<HomeHints> _loadHints() => HomeHints.load(
    widget.session,
    widget.clock,
  ).catchError((Object _) => const HomeHints());

  /// Gezählte Ladeläufe der Erholung (nur für [HomeScreen.debugWrapReadiness]).
  int _readinessCalls = 0;

  Future<ReadinessSnapshot?> _loadReadiness() {
    final load = loadReadinessToday(
      session: widget.session,
      clock: widget.clock,
      recalculation: widget.recalculation.service,
    );
    final wrap = HomeScreen.debugWrapReadiness;
    if (kReleaseMode || wrap == null) return load;
    return wrap(++_readinessCalls, load);
  }

  /// Wege zum Nachholen auf der Detailseite der Erholung (FR-0111): die
  /// Morgenmessung über ihren vorhandenen Einstieg (nur mit Kamera) und die
  /// Schlafangabe an der Morgenmessung (PAR-164K). Danach laden Karte und
  /// Morgenkarte neu.
  ReadinessActions _readinessActions(BuildContext context) {
    final session = widget.session;
    final camera = PpgCameraScope.maybeOf(context) != null;
    // Die Detailseite liegt über der Hülle (Root-Navigator), außerhalb des
    // Scopes der Sitzung: den Auslöser darum hier mitgeben.
    final recovery = PlanRecoveryScope.maybeOf(context);
    return ReadinessActions(
      reload: _loadReadiness,
      startMorning: camera && session is MorningStorage
          ? (context) => openMorningMeasurement(
              context,
              session: session,
              clock: widget.clock,
              recovery: recovery,
              belt: MorningBelt.of(
                widget.sensors,
                session.settings,
                widget.clock,
              ),
            )
          : null,
      // Nach jeder gespeicherten Schlafstufe (setzen, ändern, abwählen) den
      // Plan von heute prüfen wie nach der Morgenmessung (FR-0157,
      // PAR-164K). Die Prüfung läuft ohne Warten auf die Anzeige; scheitert
      // das Speichern, läuft sie nicht.
      saveSleep: session is MorningStorage
          ? (entry, band) async {
              await saveReadinessSleep(
                (session as MorningStorage).morning,
                entry,
                band,
              );
              if (recovery != null) unawaited(recovery.recheck());
            }
          : null,
      changed: () {
        if (!mounted) return;
        setState(() {
          _morningEpoch++;
          _renewCards(readiness: true);
        });
      },
    );
  }

  void _reloadHints() {
    if (!mounted) return;
    setState(() {
      _renewCards(hints: true);
    });
  }

  void _snack(String key, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(key: Key(key), content: Text(message)));
  }

  /// Pausenfrage beantworten (PAR-202); „Ja“ startet den Plan neu.
  Future<void> _answerPause(bool paused) async {
    if (_busy) return;
    final l = AppLocalizations.of(context);
    setState(() => _busy = true);
    final r = await _plan.answerPause(paused);
    if (!mounted) return;
    setState(() => _busy = false);
    if (r != PlanActionResult.done) {
      _snack('home_pause_failed', l.homePauseFailed);
    } else if (paused) {
      widget.changes.changed();
    }
    _reloadHints();
  }

  Future<void> _liftWarning() async {
    if (_busy) return;
    final l = AppLocalizations.of(context);
    setState(() => _busy = true);
    final r = await _plan.liftWarning();
    if (!mounted) return;
    setState(() => _busy = false);
    _snack(
      'home_warning_lifted',
      r == PlanActionResult.done ? l.planWarnLifted : l.planWarnFailed,
    );
    _reloadHints();
  }

  /// Hinweis bzw. Frage der Unterforderung (PAR-236) beantworten.
  Future<void> _underload(
    Future<void> Function(PlanUnderloadActions a) action,
  ) async {
    if (_busy) return;
    setState(() => _busy = true);
    await action(
      PlanUnderloadActions(
        controller: _plan,
        session: widget.session,
        clock: widget.clock,
        recalculation: widget.recalculation,
      ),
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _renewCards();
    });
  }

  Future<void> _seeChange(PlanChangeNotice notice) async {
    if (_busy) return;
    setState(() => _busy = true);
    await _plan.markChangeSeen(notice.planId);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _renewCards();
    });
  }

  Future<void> _openHistory() async {
    final notice = _plan.state.changeNotice;
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        builder: (_) => PlanHistoryScreen(load: _plan.changeHistory),
      ),
    );
    if (!mounted || notice == null) return;
    await _plan.markChangeSeen(notice.planId);
  }

  /// „Locker laufen“: die heutige Einheit nach Bestätigung durch einen
  /// lockeren Lauf ersetzen (Ersetzen aus WP22); ohne Bestätigung bleibt der
  /// Plan.
  Future<void> _easyRun(PlanUnit unit) async {
    if (_busy) return;
    final l = AppLocalizations.of(context);
    PlanReplaceCheck? check;
    try {
      check = await _plan.checkReplace(unit, PlanUnitKind.easy);
    } on Object {
      check = null;
    }
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => EasyRunDialog(check: check),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    final r = await _plan.replaceUnit(unit.id!, PlanUnitKind.easy);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _renewCards();
    });
    _snack(
      'home_easy_result',
      r == PlanActionResult.done
          ? l.calendarReplaced
          : l.calendarReplaceRejected,
    );
    widget.changes.changed();
  }

  /// Karten über der Startkarte: Hinweis „Erholung“ (nur mit Auslöser),
  /// Pausenfrage, Erinnerung unter Warnsignal und „Plan angepasst“.
  Widget _cards(BuildContext context) {
    // Erst anzeigen, wenn alles da ist: sonst springt die Karte von der Basis
    // zur erweiterten Stufe. Danach bleibt der bisherige Stand stehen, bis der
    // neue geladen ist (kein Frame ohne Karte).
    final shown = _shownCards;
    if (shown == null) return const SizedBox.shrink();
    final hints = shown.hints;
    final readiness = shown.readiness;
    final s = shown.plan;
    final extended = readiness != null && readiness.extended;
    final ready = s.phase == PlanLoadPhase.ready;
    final unit = ready && s.hasPlan ? _unitToday(s) : null;
    final canEasy =
        unit != null &&
        unit.id != null &&
        unit.kind != PlanUnitKind.rest &&
        unit.kind != PlanUnitKind.easy &&
        unit.runId == null;
    final card = hints.card;
    final pause = hints.pause;
    final notice = ready ? s.changeNotice : null;
    final reminder = ready && s.warning != null && s.warningReminderDue
        ? planDay(_date(_today))
              .difference(planDay(s.warning!.reportedOn))
              .inDays
        : null;
    // Warnsignal vor jeder Einschätzung (FR-0203, PAR-173); andere Hinweise
    // der Basisstufe folgen der Einschätzung.
    final warning = card != null && card.code == HintCode.warning;
    Widget hintCard(bool basis) => RecoveryCardView(
      card: card!,
      basisStage: basis,
      onEasyRun: card.action == HintAction.easyRun && canEasy && !_busy
          ? () => _easyRun(unit)
          : null,
      onNewStart: card.action == HintAction.newStart && s.goal != null && !_busy
          ? () => _newStart(s.goal!)
          : null,
    );
    final children = <Widget>[
      if (card != null && (warning || !extended)) hintCard(!extended),
      if (extended)
        ReadinessCard(
          snapshot: readiness,
          warning: warning,
          actions: _readinessActions(context),
        ),
      // Bei „fix“ nur eine Empfehlung unter der Karte „Erholung“, der Plan
      // bleibt (FR-0216, PAR-173); nicht unter Warnsignal (FR-0203 vorn).
      if (extended &&
          ready &&
          s.warning == null &&
          readiness.today != null &&
          recoveryRecommendsEasy(
            mode: s.adaptation,
            readiness: PlanReadinessDay.of(readiness.today!, readiness.result),
            unit: unit,
            today: _date(_today),
          ))
        PlanAdaptRecommendation(
          onEasyRun: unit!.id != null && !_busy ? () => _easyRun(unit) : null,
        ),
      if (card != null && !warning && extended) hintCard(false),
      if (pause != null)
        PauseQuestionCard(
          question: pause,
          onAnswer: _busy ? null : _answerPause,
        ),
      if (reminder != null)
        WarningReminderCard(
          days: reminder,
          onLift: _busy ? null : _liftWarning,
        ),
      if (notice != null)
        PlanChangeCard(
          notice: notice,
          onSeen: _busy ? null : () => _seeChange(notice),
          onHistory: _openHistory,
        ),
      if (ready ? s.underloadPrompt : null case final prompt?)
        PlanUnderloadCard(
          prompt: prompt,
          onCheckHrMax: _busy
              ? null
              : () => _underload((a) => a.checkHrMax(context)),
          onHintFine: _busy
              ? null
              : () => _underload((a) => a.hintFine(context)),
          onAnswer: _busy
              ? null
              : (yes) => _underload((a) => a.answer(context, yes)),
        ),
    ];
    if (children.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            children[i],
          ],
        ],
      ),
    );
  }

  /// Heutiger Ortstag nach dem Versatz der Uhr (wie in der Statistik).
  String get _today {
    final now = widget.clock.now().toUtc();
    return isoDay(now.add(widget.clock.utcOffsetAt(now)));
  }

  static DateTime _date(String day) => DateTime.parse('${day}T00:00:00Z');

  /// Legt [page] über die Hülle (Root-Navigator, Vollbild) und meldet danach
  /// mögliche Änderungen der Daten.
  Future<void> _push(BuildContext context, WidgetBuilder page) async {
    await Navigator.of(context).push<void>(MaterialPageRoute(builder: page));
    widget.changes.changed();
  }

  /// Lauf starten: frei ([unit] `null`) oder für die geplante Einheit
  /// ([RunStarter], derselbe Weg wie „Start“ auf der Plan-Seite).
  Future<void> _startRun(BuildContext context, {PlanUnit? unit}) => RunStarter(
    session: widget.session,
    clock: widget.clock,
    permissions: widget.permissions,
    recalculation: widget.recalculation,
    runPorts: widget.runPorts,
    sensors: widget.sensors,
    changes: widget.changes,
  ).start(context, unit: unit);

  /// Gingen erfasste Läufe in die Fassung ein (Pace, Wochenzeit)? Nur dann
  /// nennt „Worauf beruht das?“ sie.
  bool _planUsesRuns(PlanViewState s) {
    final i = s.version?.inputs;
    return i != null && (i.easyRunCount > 0 || i.lastWeekMinutes != null);
  }

  /// Neuer Einstieg nach langer Pause (PAR-181): das Zielformular fragt den
  /// Stand neu (PAR-192); Speichern startet den Plan neu.
  Future<void> _newStart(TrainingGoal goal) async {
    if (_busy) return;
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    final result = await Navigator.of(context, rootNavigator: true)
        .push<PlanActionResult>(
          MaterialPageRoute(
            builder: (_) => PlanGoalFormScreen(
              controller: _plan,
              session: widget.session,
              clock: widget.clock,
              initial: goal,
              newStart: true,
            ),
          ),
        );
    if (!mounted) return;
    setState(() => _busy = false);
    await _plan.reload();
    _reloadHints();
    if (result == null) return;
    widget.changes.changed();
    messenger.showSnackBar(
      SnackBar(
        key: const Key('home_new_start_saved'),
        content: Text(
          result == PlanActionResult.savedNotPlanned
              ? l.planGoalSavedNotPlanned
              : l.planGoalSaved,
        ),
      ),
    );
  }

  /// Zielformular aus Teil C (Anlegen); danach lädt der Plan neu.
  Future<void> _createGoal(BuildContext context) async {
    await Navigator.of(context, rootNavigator: true).push<PlanActionResult>(
      MaterialPageRoute(
        builder: (_) => PlanGoalFormScreen(
          controller: _plan,
          session: widget.session,
          clock: widget.clock,
        ),
      ),
    );
    if (!mounted) return;
    await _plan.reload();
  }

  /// Heute liegt in einer Woche des Plans (ab dem Anker der Fassung bis zum
  /// Ende der letzten Planwoche). Die Wochen der Rechnung beginnen mit der
  /// Woche von „heute“ ([GeneratedPlan.weeks]), nicht mit dem Anker: das Ende
  /// steht darum am Montag der letzten Woche, nicht an ihrer Zahl.
  bool _inPlan(PlanViewState s) {
    final day = _date(_today);
    final anchor = planDay(s.version!.inputs.anchor);
    if (day.isBefore(anchor)) return false;
    final weeks = s.hints?.weeks ?? const <PlanWeek>[];
    if (weeks.isEmpty) return false;
    return day.isBefore(planDay(weeks.last.start).add(const Duration(days: 7)));
  }

  /// Die Einheit von heute aus der Woche des Plans, sonst `null`.
  PlanUnit? _unitToday(PlanViewState s) {
    final today = _today;
    for (final u in s.weekUnits) {
      if (isoDay(u.day) == today) return u;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context).textTheme;
    final c = RamuriColors.of(context);
    return Scaffold(
      key: const Key('home_screen'),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 16),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: RamuriLogo(semanticLabel: l10n.appTitle),
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        DateFormat.MMMMEEEEd(
                          Localizations.localeOf(context).toString(),
                        ).format(_date(_today)),
                        key: const Key('home_date'),
                        style: theme.labelMedium!.copyWith(color: c.textMuted),
                      ),
                      Semantics(
                        header: true,
                        child: Text(l10n.homeToday, style: theme.headlineLarge),
                      ),
                    ],
                  ),
                ),
                _ProfileButton(
                  tooltip: l10n.homeOverview,
                  onPressed: () => _push(
                    context,
                    (_) => OverviewScreen(
                      session: widget.session,
                      clock: widget.clock,
                      permissions: widget.permissions,
                      recalculation: widget.recalculation,
                      sensors: widget.sensors,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _cards(context),
            // Morgenmessung (FR-0215): nur wenn erreichbar (Entwicklermodus
            // oder bestandene Validierung); sonst baut die Karte nichts.
            MorningCard(
              key: ValueKey('morning_card_$_morningEpoch'),
              session: widget.session,
              clock: widget.clock,
              beltFactory: () => MorningBelt.of(
                widget.sensors,
                widget.session.settings,
                widget.clock,
              ),
            ),
            // Der Zugang ist ohne Profil und ohne Freigaben offen (FR-0001,
            // CON-0007); nur der Standort wird geprüft (FR-0195).
            _startCard(context, l10n),
            const SizedBox(height: 16),
            FutureBuilder<_Data>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Column(
                    children: [
                      Text(
                        l10n.statLoadFailed,
                        key: const Key('home_failed'),
                        textAlign: TextAlign.center,
                      ),
                      TextButton(
                        key: const Key('home_retry'),
                        onPressed: _reload,
                        child: Text(l10n.notOpenableRetry),
                      ),
                    ],
                  );
                }
                final data = snapshot.data;
                if (data == null) {
                  return const Center(child: CircularProgressIndicator());
                }
                return _content(context, data);
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Karte oben: ohne Plan „Frei laufen“ (und ohne Ziel „Ziel anlegen“),
  /// mit Plan „Heute geplant“ (FR-0209, WP22 Teil D).
  Widget _startCard(BuildContext context, AppLocalizations l10n) {
    final s = _plan.state;
    final ready = s.phase == PlanLoadPhase.ready;
    if (ready && s.hasPlan) return _todayCard(context, l10n, s);
    return RamuriCard(
      tone: RamuriCardTone.panel,
      radius: 28,
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RamuriPrimaryButton(
            key: const Key('home_start_run'),
            icon: Icons.play_arrow_rounded,
            label: l10n.homeStartRun,
            onPressed: () => _startRun(context),
          ),
          if (ready && s.goal == null) ...[
            const SizedBox(height: 12),
            RamuriSecondaryButton(
              key: const Key('home_create_goal'),
              icon: Icons.flag_outlined,
              label: l10n.planEmptyCreateGoal,
              onPressed: () => _createGoal(context),
            ),
          ],
        ],
      ),
    );
  }

  /// „Heute geplant“: Einheit mit Dauer, Ziel und Grundlage, „Einheit
  /// starten“ und „Frei laufen“. Ruhetag, erledigte oder keine Einheit:
  /// ein Satz und nur „Frei laufen“.
  Widget _todayCard(BuildContext context, AppLocalizations l, PlanViewState s) {
    final unit = _unitToday(s);
    final open =
        unit != null && unit.kind != PlanUnitKind.rest && unit.runId == null;
    final formatter = AppSettingsScope.formatterOf(context);
    return RamuriCard(
      key: const Key('home_today_plan'),
      tone: RamuriCardTone.panel,
      radius: 28,
      padding: const EdgeInsets.all(22),
      child: Builder(
        builder: (context) {
          final t = Theme.of(context).textTheme;
          final c = RamuriColors.of(context);
          final lines = <Widget>[];
          if (unit == null && !_inPlan(s)) {
            lines.add(Text(l.planTodayNone, key: const Key('home_today_none')));
          } else if (unit == null) {
            // Tag ohne Einheit innerhalb des Plans: Ruhetag wie auf der
            // Plan-Seite.
            lines.add(Text(l.planTodayRest, key: const Key('home_today_rest')));
          } else if (unit.runId != null) {
            lines.add(
              Text(
                unit.kind == PlanUnitKind.rest
                    ? l.planRestDay
                    : planKindName(l, unit.kind),
                style: t.titleLarge,
              ),
            );
            lines.add(Text(l.planTodayDone, key: const Key('home_today_done')));
            // Bewegungszeit und Strecke des zugeordneten Laufs (FR-0171) aus
            // den schon geladenen Läufen; ein Ruhetag mit Lauf bleibt ohne.
            final runId = unit.runId;
            if (unit.kind != PlanUnitKind.rest) {
              lines.add(
                FutureBuilder<_Data>(
                  future: _future,
                  builder: (context, snap) {
                    for (final o in snap.data?.overviews ?? <RunOverview>[]) {
                      if (o.run.id != runId || o.readFailed) continue;
                      return Text(
                        planDoneRunLine(l, formatter, PlanDoneRun.of(o)),
                        key: const Key('home_today_done_run'),
                        style: t.bodyMedium,
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
              );
            }
          } else if (!open) {
            lines.add(Text(l.planTodayRest, key: const Key('home_today_rest')));
          } else {
            final approx = planApproxMeters(s.version!.inputs, unit.minutes);
            String? basis;
            for (final seg in unit.segments) {
              basis ??= planBasisText(l, seg.intensity?.basisCode);
            }
            lines.addAll([
              Text(
                planKindName(l, unit.kind),
                key: const Key('home_today_unit'),
                style: t.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                [
                  planDurationText(l, unit.minutes),
                  if (approx != null)
                    l.planWeekApprox(
                      '${formatter.unit.distanceFromMeters(approx).round()} '
                      '${formatter.distanceLabel}',
                    ),
                ].join(' · '),
                key: const Key('home_today_duration'),
                style: t.bodyMedium,
              ),
              const SizedBox(height: 6),
              Text(
                planKindPurpose(l, unit.kind),
                key: const Key('home_today_purpose'),
                style: t.bodySmall?.copyWith(color: c.textMuted),
              ),
              if (basis != null)
                Text(
                  l.planBasisLine(basis),
                  key: const Key('home_today_basis'),
                  style: t.bodySmall?.copyWith(color: c.textMuted),
                ),
              if (trainingBasisLines(l, unit, withRuns: _planUsesRuns(s))
                  case final lines?)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton(
                    key: const Key('home_today_why'),
                    onPressed: () => showBasisDialog(context, lines),
                    child: Text(l.recoveryBasis),
                  ),
                ),
            ]);
          }
          final free = open
              ? RamuriSecondaryButton(
                  key: const Key('home_start_run'),
                  label: l.homeStartRun,
                  onPressed: () => _startRun(context),
                )
              : RamuriPrimaryButton(
                  key: const Key('home_start_run'),
                  icon: Icons.play_arrow_rounded,
                  label: l.homeStartRun,
                  onPressed: () => _startRun(context),
                );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _headerLine(
                Text(
                  l.planTodayTitle,
                  key: const Key('home_today_title'),
                  style: t.labelMedium?.copyWith(color: c.textMuted),
                ),
                unit == null
                    ? null
                    : Text(
                        l.planUnitWeekPhase(
                          unit.weekIndex + 1,
                          planPhaseFull(l, unit.phase),
                        ),
                        key: const Key('home_today_week'),
                        style: t.labelMedium?.copyWith(color: c.textMuted),
                      ),
              ),
              const SizedBox(height: 10),
              ...lines,
              const SizedBox(height: 18),
              if (open)
                HomeStartRow(
                  key: const Key('home_start_row'),
                  primary: RamuriPrimaryButton(
                    key: const Key('home_start_unit'),
                    icon: Icons.play_arrow_rounded,
                    label: l.planTodayStart,
                    onPressed: () => _startRun(context, unit: unit),
                  ),
                  secondary: free,
                )
              else
                free,
            ],
          );
        },
      ),
    );
  }

  /// Kopfzeile aus [title] links und [value] rechtsbündig (FR-0205): passen
  /// beide nicht in eine Zeile, steht [value] linksbündig darunter und darf
  /// selbst umbrechen – kein Überlauf, nichts abgeschnitten.
  static Widget _headerLine(Widget title, Widget? value) => SizedBox(
    width: double.infinity,
    child: Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 2,
      children: [title, ?value],
    ),
  );

  /// Wochenziel als Zeit (FR-0148): gelaufene Zeit dieser Woche gegen die
  /// Wochenzeit des Plans, Kilometer nur als „ca.“. `null` ohne Plan.
  Widget? _weekGoal(BuildContext context, AppLocalizations l, Duration done) {
    final s = _plan.state;
    if (s.phase != PlanLoadPhase.ready || !s.hasPlan) return null;
    final day = _date(_today);
    final monday = day.subtract(Duration(days: day.weekday - 1));
    final target = planWeekMinutes(
      hints: s.hints,
      monday: monday,
      units: s.weekUnits,
    );
    if (target <= 0) return null;
    final c = RamuriColors.of(context);
    final t = Theme.of(context).textTheme;
    final formatter = AppSettingsScope.formatterOf(context);
    final doneMinutes = done.inMinutes;
    final approx = planApproxMeters(s.version!.inputs, target);
    return Column(
      key: const Key('home_week_goal'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _headerLine(
          Text(
            l.planWeekGoal,
            key: const Key('home_week_goal_title'),
            style: t.labelMedium,
          ),
          Text(
            l.planWeekGoalProgress(
              planDurationText(l, doneMinutes),
              planDurationText(l, target),
            ),
            key: const Key('home_week_goal_time'),
            style: t.labelMedium,
          ),
        ),
        if (approx != null)
          Text(
            l.planWeekApprox(
              '${formatter.unit.distanceFromMeters(approx).round()} '
              '${formatter.distanceLabel}',
            ),
            key: const Key('home_week_goal_km'),
            style: t.labelSmall?.copyWith(color: c.textMuted),
          ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            key: const Key('home_week_goal_bar'),
            value: (doneMinutes / target).clamp(0, 1).toDouble(),
            minHeight: 6,
            color: c.action,
            backgroundColor: c.tint,
          ),
        ),
      ],
    );
  }

  Widget _content(BuildContext context, _Data data) {
    final l10n = AppLocalizations.of(context);
    final c = RamuriColors.of(context);
    final material = MaterialLocalizations.of(context);
    final formatter = AppSettingsScope.formatterOf(context);
    if (data.overviews.isEmpty) {
      final goal = _weekGoal(context, l10n, Duration.zero);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RamuriCard(child: Text(l10n.homeEmpty, key: const Key('home_empty'))),
          if (goal != null) ...[
            const SizedBox(height: 16),
            RamuriCard(child: goal),
          ],
        ],
      );
    }
    final today = _today;
    // Dieselbe Woche und dieselbe Summe wie die Wochenstatistik (FR-0044).
    // Strecke, Trainingstage und Wochenziel zählen nur Läufe: Eine
    // Sporteinheit zählt für den Plan nur, wenn sie eine Einheit ersetzt
    // (DEC-0056), und hat keine Strecke (FR-0221).
    final week = StatisticsPeriod.weekOf(today);
    final stats = computePeriodStatistics(week, data.figures);
    final runDays = {for (final f in stats.runs) f.day};
    final km = stats.runCount == 0
        ? formatter.distance(0)
        : formatter.distance(stats.distanceMeters.value);
    final last = data.overviews.first;
    final goal = _weekGoal(
      context,
      l10n,
      stats.movingTime.value ?? Duration.zero,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RamuriCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionHeading(
                l10n.homeWeekTitle,
                trailing: Text(
                  km,
                  key: const Key('home_week_km'),
                  // Zahl fett in Sora wie im Design.
                  style: Theme.of(context).textTheme.titleSmall!.copyWith(
                    fontFamily: ramuriHeadingFamily,
                    fontWeight: FontWeight.w700,
                    color: c.text,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              // Wie in der Statistik: Fehlt bei einem Lauf die Strecke, ist die
              // Summe nur ein Teil und sagt es.
              if (stats.distanceMeters.isPartial)
                Text(
                  l10n.statPartial(
                    stats.distanceMeters.runsWithValue,
                    stats.distanceMeters.runsTotal,
                  ),
                  key: const Key('home_week_partial'),
                  style: Theme.of(context).textTheme.labelSmall!
                      .copyWith(color: c.textMuted),
                ),
              const SizedBox(height: 14),
              RamuriWeekStrip(
                key: const Key('home_week'),
                days: [
                  for (var i = 0; i < DateTime.daysPerWeek; i++)
                    _weekDay(material, l10n, week.firstDay!, i, today, runDays),
                ],
              ),
              if (goal != null) ...[const SizedBox(height: 16), goal],
            ],
          ),
        ),
        const SizedBox(height: 16),
        _LastRun(
          overview: last,
          formatter: formatter,
          onTap: () => _push(
            context,
            (_) => RunDetailScreen(
              session: widget.session,
              clock: widget.clock,
              recalculation: widget.recalculation,
              runId: last.run.id,
            ),
          ),
        ),
      ],
    );
  }

  /// Kurzer und langer Name eines Wochentags aus der Datumsausgabe der
  /// Plattform (Deutsch und Englisch nennen den Wochentag vor dem ersten
  /// Komma): „Mo.“ wird zu „Mo“.
  RamuriWeekDay _weekDay(
    MaterialLocalizations material,
    AppLocalizations l10n,
    String firstDay,
    int index,
    String today,
    Set<String> runDays,
  ) {
    final day = isoDay(_date(firstDay).add(Duration(days: index)));
    final date = _date(day);
    String head(String text) => text.split(',').first.trim();
    final short = head(material.formatMediumDate(date)).replaceAll('.', '');
    final long = head(material.formatFullDate(date));
    final done = runDays.contains(day);
    return RamuriWeekDay(
      label: short,
      semanticLabel: done
          ? l10n.homeWeekDayRun(long)
          : l10n.homeWeekDayNone(long),
      done: done,
      today: day == today,
      future: day.compareTo(today) > 0,
    );
  }
}

class _ProfileButton extends StatelessWidget {
  const _ProfileButton({required this.tooltip, required this.onPressed});

  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = RamuriColors.of(context);
    return IconButton(
      key: const Key('home_overview'),
      tooltip: tooltip,
      constraints: const BoxConstraints.tightFor(width: 48, height: 48),
      style: IconButton.styleFrom(
        backgroundColor: c.surface,
        side: BorderSide(color: c.outline),
      ),
      icon: const Icon(Icons.person_outline_rounded),
      onPressed: onPressed,
    );
  }
}

/// Der letzte Lauf mit Sprung in seine Detailansicht (wie im Verlauf).
class _LastRun extends StatelessWidget {
  const _LastRun({
    required this.overview,
    required this.formatter,
    required this.onTap,
  });

  final RunOverview overview;
  final UnitFormatter formatter;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final material = MaterialLocalizations.of(context);
    final c = RamuriColors.of(context);
    final theme = Theme.of(context).textTheme;
    final day = DateTime.parse('${dayOfRun(overview.run)}T00:00:00Z');
    final pace = overview.averagePaceSecondsPerKm;
    return RamuriCard(
      key: const Key('home_last_run'),
      radius: 20,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      onTap: onTap,
      child: Row(
        children: [
          // Statisches Symbol-Kästchen wie im Design.
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: c.tint,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(Icons.timeline_rounded, color: c.accent),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.homeLastRun(material.formatMediumDate(day)),
                  style: theme.labelSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  '${formatter.distance(overview.distanceMeters)} · '
                  '${formatter.pace(pace)}',
                  key: const Key('home_last_run_values'),
                  style: theme.titleMedium,
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: c.textMuted),
        ],
      ),
    );
  }
}
