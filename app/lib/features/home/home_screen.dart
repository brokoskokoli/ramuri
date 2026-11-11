import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import '../../offload_scope.dart';
import '../../ui/ui.dart';
import '../history/run_detail_screen.dart';
import '../plan/plan_controller.dart';
import '../plan/plan_goal_form.dart';
import '../plan/plan_started_unit.dart';
import '../plan/plan_texts.dart';
import '../recalculation/recalculation_controller.dart';
import '../run/run_flow_screen.dart';
import '../run/run_ports.dart';
import '../sensors/sensor_manager.dart';
import '../settings/app_settings.dart';
import '../settings/unit_format.dart';
import 'data_changes.dart';
import 'overview_screen.dart';

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

  /// Ziel und Plan (nur lesen; geschrieben wird über das Zielformular und die
  /// Zuordnung).
  late final PlanController _plan = PlanController(
    session: widget.session,
    clock: widget.clock,
  );

  /// Der Ortstag, für den die Seite zuletzt geladen und gebaut wurde.
  late String _shownDay;

  @override
  void initState() {
    super.initState();
    _shownDay = _today;
    WidgetsBinding.instance.addObserver(this);
    _plan.addListener(_onPlan);
    _plan.reload();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _plan.removeListener(_onPlan);
    _plan.dispose();
    super.dispose();
  }

  void _onPlan() {
    if (mounted) setState(() {});
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
      _shownDay = _today;
      _future = _load();
    });
    _plan.reload();
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

  /// Lauf starten: frei ([unit] `null`) oder für die geplante Einheit. Der
  /// Lauf ist vorerst der normale Lauf (die Führung kommt mit WP24).
  ///
  /// „Einheit starten“ merkt die Einheit vorher in `settings`
  /// ([PlanStartedUnitStore]); so überlebt sie Absturz und Wiederaufnahme.
  /// Nach dem Schließen wird ein beendeter Lauf ihr zugeordnet, eingereiht
  /// hinter die Wertberechnung des Laufs (auch wenn „Fertig“ vor deren Ende
  /// getippt wurde). „Frei laufen“ löscht den Merker; ist am Starttag eine
  /// Einheit offen, fragt die App nach dem Ende, ob der Lauf zu ihr zählt.
  /// Termine ändern sich nie. Die Datenmeldung folgt erst nach der Zuordnung.
  Future<void> _startRun(BuildContext context, {PlanUnit? unit}) async {
    final day = _today;
    final unitId = unit?.id;
    final started = PlanStartedUnitStore(
      session: widget.session,
      clock: widget.clock,
    );
    try {
      if (unitId != null) {
        await started.remember(unitId, day);
      } else {
        await started.forget();
      }
    } on Object {
      // Ohne Merker ordnet nur der normale Weg zu (nach dem Schließen).
    }
    if (!context.mounted) return;
    // Die Hülle baut „Heute“ bei jeder Datenmeldung neu (neuer Zustand); die
    // Nachfrage und der Hinweis nach dem Lauf brauchen darum Navigator und
    // Messenger der App, nicht diesen Zustand.
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    int? finishedId;
    await navigator.push<void>(
      MaterialPageRoute(
        builder: (_) => RunFlowScreen(
          session: widget.session,
          clock: widget.clock,
          ports: widget.runPorts,
          permissions: widget.permissions,
          serialize: widget.recalculation.exclusive,
          sensors: widget.sensors,
          recalculation: widget.recalculation,
          onFinished: (runId) => finishedId = runId,
        ),
      ),
    );
    PlanActionResult? result;
    try {
      if (unitId != null) {
        result = await started.settle(
          serialize: widget.recalculation.exclusive,
          runId: finishedId,
          forgetWithoutRun: true,
        );
      } else if (finishedId != null) {
        result = await _askFreeRun(navigator, finishedId!, day);
      }
    } on Object {
      result = PlanActionResult.failed;
    }
    // Scheitert nur die Neuberechnung, ist der Lauf trotzdem zugeordnet.
    var assigned = false;
    if (result == PlanActionResult.failed) {
      try {
        assigned = await planRunAssignedOn(widget.session, day, finishedId);
      } on Object {
        assigned = false;
      }
    }
    if (result != null && navigator.mounted) {
      _showAssignResult(
        navigator.context,
        messenger,
        result,
        assigned: assigned,
      );
    }
    widget.changes.changed();
  }

  /// Nach „Frei laufen“: Ist am Ortstag [day] eine Einheit offen, fragt die
  /// App, ob der Lauf zu ihr zählt (Entscheidung des Maintainers
  /// 2026-11-10). Ja ordnet zu, Nein lässt die Einheit offen. `null`: keine
  /// Frage oder Nein.
  Future<PlanActionResult?> _askFreeRun(
    NavigatorState navigator,
    int runId,
    String day,
  ) async {
    final unit = await openPlanUnitOn(widget.session, day);
    if (unit == null || !navigator.mounted) return null;
    final yes = await showDialog<bool>(
      context: navigator.context,
      builder: (context) {
        final l = AppLocalizations.of(context);
        return AlertDialog(
          key: const Key('home_assign_ask'),
          title: Text(
            l.planTodayAskTitle,
            key: const Key('home_assign_ask_title'),
          ),
          content: Text(l.planTodayAskBody),
          actions: [
            TextButton(
              key: const Key('home_assign_no'),
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l.planTodayAskNo),
            ),
            FilledButton(
              key: const Key('home_assign_yes'),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l.planTodayAskYes),
            ),
          ],
        );
      },
    );
    if (yes != true) return null;
    return widget.recalculation.exclusive(
      () => assignRunToUnit(
        session: widget.session,
        clock: widget.clock,
        unitId: unit.id!,
        day: day,
        runId: runId,
      ),
    );
  }

  /// Ein Fehlschlag der Zuordnung bleibt nicht stumm: Der Lauf ist
  /// gespeichert, die Einheit bleibt offen (kein Fehlerinhalt nach außen).
  /// Ist der Lauf zugeordnet ([assigned]) und nur die Neuberechnung
  /// gescheitert, sagt der Hinweis genau das.
  static void _showAssignResult(
    BuildContext context,
    ScaffoldMessengerState messenger,
    PlanActionResult result, {
    bool assigned = false,
  }) {
    if (result == PlanActionResult.done ||
        result == PlanActionResult.savedNotPlanned) {
      return;
    }
    final l = AppLocalizations.of(context);
    messenger.showSnackBar(
      assigned
          ? SnackBar(
              key: const Key('home_assign_not_recalculated'),
              content: Text(l.planTodayAssignNotRecalculated),
            )
          : SnackBar(
              key: const Key('home_assign_failed'),
              content: Text(l.planTodayAssignFailed),
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
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l.planTodayTitle,
                      style: t.labelMedium?.copyWith(color: c.textMuted),
                    ),
                  ),
                  if (unit != null)
                    Text(
                      l.planUnitWeekPhase(
                        unit.weekIndex + 1,
                        planPhaseFull(l, unit.phase),
                      ),
                      key: const Key('home_today_week'),
                      style: t.labelMedium?.copyWith(color: c.textMuted),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              ...lines,
              const SizedBox(height: 18),
              if (open)
                Row(
                  children: [
                    Expanded(
                      child: RamuriPrimaryButton(
                        key: const Key('home_start_unit'),
                        icon: Icons.play_arrow_rounded,
                        label: l.planTodayStart,
                        onPressed: () => _startRun(context, unit: unit),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: free),
                  ],
                )
              else
                free,
            ],
          );
        },
      ),
    );
  }

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
        Row(
          children: [
            Expanded(child: Text(l.planWeekGoal, style: t.labelMedium)),
            Text(
              l.planWeekGoalProgress(
                planDurationText(l, doneMinutes),
                planDurationText(l, target),
              ),
              key: const Key('home_week_goal_time'),
              style: t.labelMedium,
            ),
          ],
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
    final week = StatisticsPeriod.weekOf(today);
    final inWeek = [
      for (final f in data.figures)
        if (week.contains(id: f.runId, day: f.day)) f,
    ];
    final stats = computePeriodStatistics(week, data.figures);
    final runDays = {for (final f in inWeek) f.day};
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
