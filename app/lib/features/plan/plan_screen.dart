import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import '../../offload_scope.dart';
import '../../ui/ui.dart';
import '../settings/app_settings.dart';
import 'plan_calendar.dart';
import 'plan_controller.dart';
import 'plan_data_reader.dart';
import 'plan_goal_form.dart';
import 'plan_page_view_state.dart';
import 'plan_texts.dart';
import 'plan_unit_screen.dart';

/// Plan-Seite (FR-0208, WP22 Teil B) nach `design/screens/Plan.dc.html`:
/// Zielkarte mit Phasenbalken (Kurzformen, OQ-0077) und Einschätzung
/// (PAR-206), Hinweise zum Plan als ruhige Zeilen, die Woche mit ihren
/// Einheiten (Wochenziel als Zeit, Kilometer nur als „ca.“). Ohne Plan der
/// leere Zustand mit „Ziel anlegen“.
///
/// Die Seite rechnet nicht: Sie zeigt den Stand des [PlanController].
class PlanScreen extends StatefulWidget {
  const PlanScreen({
    super.key,
    required this.session,
    required this.clock,
    this.viewState,
    this.onCreateGoal,
    this.controller,
  });

  final StorageSession session;
  final Clock clock;

  /// Gezeigte Woche und Scrollposition über Tab-Wechsel; ohne Angabe legt die
  /// Seite ein eigenes Objekt an.
  final PlanPageViewState? viewState;

  /// Ersetzt den Einstieg „Ziel anlegen“ im leeren Zustand; ohne Angabe
  /// öffnet die Seite das Zielformular ([PlanGoalFormScreen]).
  final VoidCallback? onCreateGoal;

  /// Für Tests: ein vorhandener Controller; die Seite ruft dann `open()`,
  /// gibt ihn aber nicht frei. Ohne: die Seite legt ihren eigenen an.
  final PlanController? controller;

  @override
  State<PlanScreen> createState() => _PlanScreenState();
}

class _PlanScreenState extends State<PlanScreen> {
  late final PlanController _controller =
      widget.controller ??
      PlanController(
        session: widget.session,
        clock: widget.clock,
        reader: PlanDataReader(
          session: widget.session,
          clock: widget.clock,
          offload: OffloadScope.of(context),
        ),
      );
  late final PlanPageViewState _view = widget.viewState ?? PlanPageViewState();
  late final ScrollController _scroll = ScrollController(
    initialScrollOffset: _view.scrollOffset,
  )..addListener(_rememberScroll);

  // Die gemerkte Position; die Woche einer anderen Woche lädt nach dem ersten
  // Bild und verlängert die Seite, dann wird sie einmal wieder angesteuert,
  // außer der Nutzer hat inzwischen selbst gescrollt (wie Fortschritt).
  // Vor dem ersten Bild festgehalten (wie im Kalender): Der Scroll-Listener
  // überschreibt die gemerkte Lage, solange die Seite noch kurz ist.
  late final double _restoreTarget;
  bool _userScrolled = false;

  Future<List<PlanUnit>>? _weekFuture;
  int? _weekFutureOffset;

  @override
  void initState() {
    super.initState();
    _restoreTarget = _view.scrollOffset;
    _controller.addListener(_onState);
    _controller.open();
  }

  @override
  void dispose() {
    _controller.removeListener(_onState);
    if (widget.controller == null) _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onState() {
    if (!mounted) return;
    setState(() {
      _weekFuture = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _restoreScroll());
  }

  void _rememberScroll() {
    if (_scroll.hasClients) _view.scrollOffset = _scroll.offset;
  }

  bool _onScrollNotification(ScrollNotification n) {
    if (n is UserScrollNotification && n.direction != ScrollDirection.idle) {
      _userScrolled = true;
    }
    return false;
  }

  void _restoreScroll() {
    if (!mounted || _userScrolled || !_scroll.hasClients) return;
    final max = _scroll.position.maxScrollExtent;
    final target = _restoreTarget.clamp(0.0, max);
    if (target != _scroll.offset) _scroll.jumpTo(target);
  }

  DateTime get _today => calendarDay(widget.clock.now());

  DateTime _monday(int offset) {
    final t = _today;
    return t.subtract(Duration(days: t.weekday - 1 - 7 * offset));
  }

  void _step(int direction) {
    setState(() {
      _view.weekOffset += direction;
      _weekFuture = null;
    });
  }

  /// Einheiten der gezeigten Woche: diese Woche aus dem Stand, andere über
  /// den Kalender des Controllers.
  Future<List<PlanUnit>> _weekUnits(PlanViewState s) {
    final offset = _view.weekOffset;
    if (offset == 0) return Future.value(s.weekUnits);
    if (_weekFuture != null && _weekFutureOffset == offset) {
      return _weekFuture!;
    }
    final monday = _monday(offset);
    _weekFutureOffset = offset;
    return _weekFuture = _controller
        .unitsBetween(monday, monday.add(const Duration(days: 6)))
        .whenComplete(
          () => WidgetsBinding.instance.addPostFrameCallback(
            (_) => _restoreScroll(),
          ),
        );
  }

  /// Zielformular zum Anlegen (ohne [initial]) oder Ändern (vorbelegt,
  /// PAR-203). Das Ergebnis des Speicherns steht danach als Meldung da.
  Future<void> _openGoalForm([TrainingGoal? initial]) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final result = await Navigator.of(context, rootNavigator: true)
        .push<PlanActionResult>(
          MaterialPageRoute(
            builder: (_) => PlanGoalFormScreen(
              controller: _controller,
              session: widget.session,
              clock: widget.clock,
              initial: initial,
            ),
          ),
        );
    if (!mounted || result == null) return;
    messenger.showSnackBar(
      SnackBar(
        key: const Key('plan_goal_saved'),
        content: Text(
          result == PlanActionResult.savedNotPlanned
              ? l.planGoalSavedNotPlanned
              : l.planGoalSaved,
        ),
      ),
    );
  }

  void _openUnit(PlanUnit unit) {
    Navigator.of(
      context,
      rootNavigator: true,
    ).push(MaterialPageRoute<void>(builder: (_) => PlanUnitScreen(unit: unit)));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final s = _controller.state;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: switch (s.phase) {
          PlanLoadPhase.loading => const Center(
            child: CircularProgressIndicator(),
          ),
          PlanLoadPhase.failed => Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                l.planLoadFailed,
                key: const Key('plan_failed'),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          PlanLoadPhase.ready =>
            s.hasPlan && s.goal != null
                ? (_view.calendarOpen
                      ? PlanCalendar(
                          controller: _controller,
                          clock: widget.clock,
                          viewState: _view.calendar,
                          onClose: () =>
                              setState(() => _view.calendarOpen = false),
                          onOpenUnit: _openUnit,
                        )
                      : _plan(l, s))
                : _empty(l),
        },
      ),
    );
  }

  static const EdgeInsets _pagePadding = EdgeInsets.fromLTRB(20, 28, 20, 16);

  Widget _title(AppLocalizations l) => Semantics(
    header: true,
    child: Text(
      l.planTitle,
      key: const Key('plan_title'),
      style: RamuriType.of(context).pageTitle,
    ),
  );

  Widget _empty(AppLocalizations l) {
    final text = Theme.of(context).textTheme;
    return ListView(
      key: const Key('plan_empty'),
      padding: _pagePadding,
      children: [
        _title(l),
        const SizedBox(height: 14),
        RamuriCard(
          tone: RamuriCardTone.accent,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.planEmptyTitle, style: text.headlineSmall),
              const SizedBox(height: 6),
              Text(l.planEmptyText, style: text.bodyMedium),
              const SizedBox(height: 14),
              RamuriPrimaryButton(
                key: const Key('plan_create_goal'),
                label: l.planEmptyCreateGoal,
                onPressed: widget.onCreateGoal ?? _openGoalForm,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _plan(AppLocalizations l, PlanViewState s) {
    final hints = s.hints;
    final lang = Localizations.localeOf(context).languageCode;
    String day(DateTime d) => DateFormat.MMMEd(lang).format(d);
    final global = <Widget>[
      if (s.ruleVersionPending)
        _Hint(key: const Key('plan_hint_rule_version'), l.planHintRuleVersion),
      if (hints != null) ...[
        for (var i = 0; i < hints.pinnedConflicts.length; i++)
          _Hint(
            key: Key('plan_hint_conflict_$i'),
            planConflictText(l, hints.pinnedConflicts[i], day),
          ),
        if (planHardFitText(l, hints.hardFit) case final t?)
          _Hint(key: const Key('plan_hint_hard_fit'), t),
        if (hints.walkRunNoWeekFits)
          _Hint(
            key: const Key('plan_hint_walk_run_no_week'),
            l.planHintWalkRunNoWeek,
          )
        else if (hints.walkRunStaysAtWeek case final w?)
          _Hint(
            key: const Key('plan_hint_walk_run_stays'),
            l.planHintWalkRunStays(w + 1),
          ),
        // PAR-115: vor dem Geh-Lauf-Plan.
        if (hints.allUnits.any((u) => u.kind == PlanUnitKind.walkRun))
          _Hint(
            key: const Key('plan_hint_walk_run_care'),
            l.planHintWalkRunCare,
          ),
      ],
    ];
    return NotificationListener<ScrollNotification>(
      onNotification: _onScrollNotification,
      child: ListView(
        key: const Key('plan_list'),
        controller: _scroll,
        padding: _pagePadding,
        children: [
          Row(
            children: [
              Expanded(child: _title(l)),
              TextButton.icon(
                key: const Key('plan_open_calendar'),
                onPressed: () => setState(() => _view.calendarOpen = true),
                icon: const Icon(Icons.calendar_month_rounded),
                label: Text(l.calendarOpen),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _GoalCard(
            state: s,
            today: _today,
            onEdit: () => _openGoalForm(s.goal),
          ),
          for (final h in global) ...[const SizedBox(height: 10), h],
          const SizedBox(height: 16),
          FutureBuilder<List<PlanUnit>>(
            key: ValueKey('plan_week_${_view.weekOffset}'),
            future: _weekUnits(s),
            builder: (context, snap) => _Week(
              state: s,
              monday: _monday(_view.weekOffset),
              today: _today,
              units: snap.data,
              hasError: snap.hasError,
              onStep: _step,
              onOpen: _openUnit,
            ),
          ),
        ],
      ),
    );
  }
}

/// Ruhige Hinweiszeile (kein Alarm): Symbol und kleiner Text.
class _Hint extends StatelessWidget {
  const _Hint(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = RamuriColors.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1, right: 10),
          child: Icon(Icons.info_outline_rounded, size: 18, color: c.accent),
        ),
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.bodySmall),
        ),
      ],
    );
  }
}

/// Zielkarte: Ziel, Datum, Phasenbalken und Einschätzung mit Grundlage.
class _GoalCard extends StatelessWidget {
  const _GoalCard({
    required this.state,
    required this.today,
    required this.onEdit,
  });

  final PlanViewState state;
  final DateTime today;

  /// Einstieg „Ziel ändern“ (PAR-203).
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = RamuriColors.of(context);
    final text = Theme.of(context).textTheme;
    final lang = Localizations.localeOf(context).languageCode;
    final goal = state.goal!;
    final distance = goal.distance;
    final title = switch (goal.type) {
      GoalType.open => l.planGoalOpen,
      GoalType.distance => l.planGoalDistance(
        distance == null ? '' : planDistanceName(l, distance),
      ),
      GoalType.time => l.planGoalTime(
        distance == null ? '' : planDistanceName(l, distance),
        planGoalTimeText(l, goal.targetSeconds ?? 0),
      ),
    };
    final date = goal.targetDate;
    final weeksLeft = date == null
        ? null
        : (planDay(date).difference(planDay(today)).inDays ~/ 7).clamp(
            0,
            1 << 20,
          );
    return RamuriCard(
      key: const Key('plan_goal_card'),
      tone: RamuriCardTone.accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.planGoalEyebrow.toUpperCase(),
            style: RamuriType.of(context).eyebrow,
          ),
          const SizedBox(height: 2),
          Text(
            title,
            key: const Key('plan_goal_title'),
            style: text.headlineSmall,
          ),
          if (date != null)
            Text(
              l.planGoalDateLeft(
                DateFormat.yMMMd(lang).format(date),
                weeksLeft!,
              ),
              style: text.labelMedium?.copyWith(color: c.textLabel),
            ),
          if (state.hints?.weeks case final weeks? when weeks.isNotEmpty) ...[
            const SizedBox(height: 12),
            _PhaseBar(weeks: weeks, today: today),
          ],
          ..._assessment(context, l),
          const SizedBox(height: 4),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              key: const Key('plan_edit_goal'),
              onPressed: onEdit,
              icon: const Icon(Icons.edit_rounded, size: 18),
              label: Text(l.planEditGoal),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _assessment(BuildContext context, AppLocalizations l) {
    final a = state.assessment;
    if (a == null) return const [];
    final c = RamuriColors.of(context);
    final text = Theme.of(context).textTheme;
    final lang = Localizations.localeOf(context).languageCode;
    String main;
    String basis;
    String? extra;
    final texts = planAssessmentTexts(
      l,
      a,
      (d) => DateFormat.yMMMd(lang).format(d),
    );
    if (texts != null) {
      (:main, :extra, :basis) = texts;
    } else {
      // Nur Einheiten bis heute: künftige Tage der Woche sind noch kein
      // Rückstand („0 von 3“ am Montag).
      final runDays = state.weekUnits
          .where(
            (u) =>
                u.kind != PlanUnitKind.rest &&
                !planDay(u.day).isAfter(planDay(today)),
          )
          .toList();
      main = l.planAssessRegularity(
        runDays.where((u) => u.runId != null).length,
        runDays.length,
      );
      basis = l.planAssessBasisRegularity;
    }
    return [
      const SizedBox(height: 12),
      Text(
        main,
        key: const Key('plan_assessment'),
        style: text.labelMedium?.copyWith(color: c.accent),
      ),
      if (a.regulatorTooLow)
        Text(
          l.planAssessRegulator,
          key: const Key('plan_assessment_regulator'),
          style: text.bodySmall?.copyWith(color: c.textLabel),
        ),
      if (extra != null)
        Text(extra, style: text.bodySmall?.copyWith(color: c.textLabel)),
      Text(
        basis,
        key: const Key('plan_assessment_basis'),
        style: text.bodySmall?.copyWith(color: c.textLabel),
      ),
    ];
  }
}

/// Phasenbalken: je Phase ein Stück nach Zahl der Wochen, darunter die
/// Kurzform (OQ-0077); die Beschreibung für Screenreader nennt den vollen
/// Namen und die Woche.
class _PhaseBar extends StatelessWidget {
  const _PhaseBar({required this.weeks, required this.today});

  final List<PlanWeek> weeks;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = RamuriColors.of(context);
    final groups = <(PlanPhase, int, int)>[]; // Phase, erste Woche, Zahl
    for (var i = 0; i < weeks.length; i++) {
      if (groups.isNotEmpty && groups.last.$1 == weeks[i].phase) {
        final g = groups.removeLast();
        groups.add((g.$1, g.$2, g.$3 + 1));
      } else {
        groups.add((weeks[i].phase, i, 1));
      }
    }
    final t = planDay(today);
    var current = weeks.lastIndexWhere((w) => !planDay(w.start).isAfter(t));
    if (current < 0) current = 0;
    final total = weeks.length;
    // Schmale Phasen bekommen genug Platz für ihre Kurzform.
    final minFlex = (total / 6).ceil();
    int flex(int n) => n < minFlex ? minFlex : n;
    final now = groups.firstWhere(
      (g) => current >= g.$2 && current < g.$2 + g.$3,
      orElse: () => groups.last,
    );
    return Semantics(
      key: const Key('plan_phase_bar'),
      label: l.planPhaseSemantics(planPhaseFull(l, now.$1), current + 1, total),
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              for (var i = 0; i < groups.length; i++) ...[
                if (i > 0) const SizedBox(width: 4),
                Expanded(
                  flex: flex(groups[i].$3),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(5),
                    child: SizedBox(
                      height: 10,
                      child: LinearProgressIndicator(
                        value: _fill(groups[i], current),
                        backgroundColor: c.surface,
                        color: c.text,
                        minHeight: 10,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              for (var i = 0; i < groups.length; i++) ...[
                if (i > 0) const SizedBox(width: 4),
                Expanded(
                  flex: flex(groups[i].$3),
                  child: Text(
                    planPhaseShort(l, groups[i].$1),
                    key: Key('plan_phase_${groups[i].$1.name}'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall
                        ?.copyWith(color: c.textLabel),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  static double _fill((PlanPhase, int, int) g, int current) {
    if (current >= g.$2 + g.$3) return 1;
    if (current < g.$2) return 0;
    return (current - g.$2 + 1) / g.$3;
  }
}

/// Die gezeigte Woche: Titel mit Wochenzeit (und „ca.“ Kilometern), die
/// Hinweise der Woche und Montag bis Sonntag.
class _Week extends StatelessWidget {
  const _Week({
    required this.state,
    required this.monday,
    required this.today,
    required this.units,
    required this.onStep,
    required this.onOpen,
    this.hasError = false,
  });

  final PlanViewState state;
  final DateTime monday;
  final DateTime today;

  /// `null`, solange die Woche lädt.
  final List<PlanUnit>? units;

  /// Laden der Woche ist fehlgeschlagen (statt ewig zu laden).
  final bool hasError;
  final void Function(int direction) onStep;
  final void Function(PlanUnit unit) onOpen;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = RamuriColors.of(context);
    final text = Theme.of(context).textTheme;
    final lang = Localizations.localeOf(context).languageCode;
    final formatter = AppSettingsScope.formatterOf(context);
    final hints = state.hints;
    final weeks = hints?.weeks ?? const <PlanWeek>[];
    final anchor = state.version!.inputs.anchor;
    // Nummer ab dem Anker; die Wochen der Rechnung beginnen aber mit der
    // Woche von „heute“, darum über den Montag suchen.
    final index = planDay(monday).difference(planDay(anchor)).inDays ~/ 7;
    final week = planWeekOf(weeks, monday);
    final inPlan = week != null;
    final list = units ?? const <PlanUnit>[];
    final runUnits = [
      for (final u in list)
        if (u.kind != PlanUnitKind.rest) u,
    ];
    final minutes =
        week?.minutes ?? runUnits.fold<int>(0, (a, u) => a + u.minutes);
    // Kilometer nur als „ca.“ und nur mit bekanntem lockerem Tempo.
    final approx = planApproxMeters(state.version!.inputs, minutes);
    final sunday = monday.add(const Duration(days: 6));
    final range =
        '${DateFormat.MMMd(lang).format(monday)} – '
        '${DateFormat.MMMd(lang).format(sunday)}';
    final summary = [
      range,
      if (minutes > 0) planDurationText(l, minutes),
      if (approx != null)
        l.planWeekApprox(
          '${formatter.unit.distanceFromMeters(approx).round()} '
          '${formatter.distanceLabel}',
        ),
    ].join(' · ');

    final dropped = hints?.droppedDaysByWeek[index] ?? const <DateTime>[];
    final unplaced = hints?.unplacedByWeek[index] ?? 0;
    final omission = hints?.hardOmissions[index];
    final weekHints = <Widget>[
      if (dropped.isNotEmpty)
        _Hint(
          key: const Key('plan_hint_dropped'),
          l.planHintDropped(dropped.length),
        ),
      if (unplaced > 0)
        _Hint(
          key: const Key('plan_hint_unplaced'),
          l.planHintUnplaced(unplaced),
        ),
      if (omission != null)
        _Hint(
          key: const Key('plan_hint_hard_omission'),
          planHardOmissionText(l, omission),
        ),
    ];
    final first = weeks.isEmpty ? null : planDay(weeks.first.start);
    final last = weeks.isEmpty ? null : planDay(weeks.last.start);
    final canBack = first == null || planDay(monday).isAfter(first);
    final canForward = last == null || planDay(monday).isBefore(last);

    return Column(
      key: const Key('plan_week'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton(
              key: const Key('plan_week_previous'),
              tooltip: l.planWeekPrevious,
              onPressed: canBack ? () => onStep(-1) : null,
              icon: const Icon(Icons.chevron_left_rounded),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    inPlan ? l.planWeekTitle(index + 1) : l.planWeekThis,
                    key: const Key('plan_week_title'),
                    style: text.titleSmall,
                  ),
                  Text(
                    summary,
                    key: const Key('plan_week_summary'),
                    style: text.labelSmall,
                  ),
                ],
              ),
            ),
            IconButton(
              key: const Key('plan_week_next'),
              tooltip: l.planWeekNext,
              onPressed: canForward ? () => onStep(1) : null,
              icon: const Icon(Icons.chevron_right_rounded),
            ),
          ],
        ),
        for (final h in weekHints) ...[const SizedBox(height: 8), h],
        const SizedBox(height: 10),
        if (hasError)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              l.planLoadFailed,
              key: const Key('plan_week_failed'),
              style: text.bodyMedium,
            ),
          )
        else if (units == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          )
        else
          for (var d = 0; d < 7; d++) ...[
            if (d > 0) const SizedBox(height: 8),
            _Day(
              day: monday.add(Duration(days: d)),
              unit: _unitOn(list, monday.add(Duration(days: d))),
              dropped: dropped.any(
                (x) => planDay(x) == planDay(monday.add(Duration(days: d))),
              ),
              isToday: planDay(monday.add(Duration(days: d))) == planDay(today),
              onOpen: onOpen,
              colors: c,
            ),
          ],
      ],
    );
  }

  static PlanUnit? _unitOn(List<PlanUnit> units, DateTime day) {
    for (final u in units) {
      if (planDay(u.day) == planDay(day)) return u;
    }
    return null;
  }
}

class _Day extends StatelessWidget {
  const _Day({
    required this.day,
    required this.unit,
    required this.dropped,
    required this.isToday,
    required this.onOpen,
    required this.colors,
  });

  final DateTime day;
  final PlanUnit? unit;
  final bool dropped;
  final bool isToday;
  final void Function(PlanUnit unit) onOpen;
  final RamuriColors colors;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final lang = Localizations.localeOf(context).languageCode;
    final c = colors;
    final key = Key(
      'plan_day_${day.year}-${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}',
    );
    final weekday = SizedBox(
      width: 36,
      child: Text(
        DateFormat.E(lang).format(day),
        style: text.labelMedium?.copyWith(
          color: isToday && unit != null ? c.accent : c.textMuted,
        ),
      ),
    );
    final u = unit;
    if (u == null || u.kind == PlanUnitKind.rest && u.runId == null) {
      return Padding(
        key: key,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          children: [
            weekday,
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                dropped ? l.planDayDropped : l.planRestDay,
                style: text.bodyMedium?.copyWith(color: c.textMuted),
              ),
            ),
            if (isToday) Text(l.planToday, style: text.labelSmall),
          ],
        ),
      );
    }
    final done = u.runId != null;
    final label = u.kind == PlanUnitKind.rest
        ? l.planRestDay
        : l.planUnitLine(
            planKindName(l, u.kind),
            planDurationText(l, u.minutes),
          );
    return RamuriCard(
      key: key,
      radius: 16,
      tone: isToday ? RamuriCardTone.panel : RamuriCardTone.surface,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      onTap: () => onOpen(u),
      child: Builder(
        builder: (context) {
          final t = Theme.of(context).textTheme;
          final cc = RamuriColors.of(context);
          return Row(
            children: [
              SizedBox(
                width: 36,
                child: Text(
                  DateFormat.E(lang).format(day),
                  style: t.labelMedium?.copyWith(
                    color: isToday ? cc.accent : cc.textMuted,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: t.titleSmall),
                    if (isToday) Text(l.planToday, style: t.labelSmall),
                  ],
                ),
              ),
              if (done)
                Semantics(
                  label: l.planUnitDone,
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: cc.action,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.check_rounded,
                      size: 16,
                      color: cc.onAction,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
