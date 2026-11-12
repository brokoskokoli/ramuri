import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';

import '../reminders/reminder_controller.dart';
import '../../l10n/app_localizations.dart';
import '../../offload_scope.dart';
import '../../ui/ui.dart';
import '../settings/app_settings.dart';
import 'plan_calendar.dart';
import 'plan_change_card.dart';
import 'plan_controller.dart';
import 'plan_data_reader.dart';
import 'plan_goal_form.dart';
import 'plan_page_view_state.dart';
import 'plan_texts.dart';
import 'plan_unit_screen.dart';

part 'plan_screen_goal.dart';
part 'plan_screen_week.dart';
part 'plan_screen_warning.dart';

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
    this.onStartUnit,
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

  /// „Start“ an der heutigen offenen Einheit: derselbe Weg wie „Einheit
  /// starten“ auf „Heute“ (Merker, Zuordnung nach dem Lauf, `RunStarter`).
  /// Ohne Angabe kein Knopf.
  final Future<void> Function(BuildContext context, PlanUnit unit)? onStartUnit;

  @override
  State<PlanScreen> createState() => _PlanScreenState();
}

class _PlanScreenState extends State<PlanScreen> {
  late final PlanController _controller =
      widget.controller ??
      PlanController(
        session: widget.session,
        clock: widget.clock,
        // FR-0174: Termine, Arten und Ziel ändern die Erinnerungen.
        onChanged: () => ReminderScope.read(context)?.sync(),
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

  bool _recalculating = false;

  /// „Neu berechnen“ (Auslöser `manual`, bei geändertem Ziel `goalChange`)
  /// nach Rückfrage: rechnet ab heute neu; bestätigte Termine und erledigte
  /// Einheiten bleiben (ADR-0010), andere Einheiten können Tag und Inhalt
  /// ändern. Abbrechen ändert nichts. Ergebnis oder Fehler steht danach als
  /// Meldung da.
  Future<void> _recalculate() async {
    if (_recalculating) return;
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _recalculating = true);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('plan_recalculate_dialog'),
        title: Text(l.planRecalculateConfirmTitle),
        scrollable: true,
        content: Text(l.planRecalculateConfirmText),
        actions: [
          TextButton(
            key: const Key('plan_recalculate_cancel'),
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l.planFormCancel),
          ),
          FilledButton(
            key: const Key('plan_recalculate_confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l.planRecalculateConfirm),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (ok != true) {
      setState(() => _recalculating = false);
      return;
    }
    final result = await _controller.recalculate();
    if (!mounted) return;
    setState(() => _recalculating = false);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          key: const Key('plan_recalculated'),
          content: Text(
            result == PlanActionResult.done
                ? l.planRecalculateDone
                : l.planRecalculateFailed,
          ),
        ),
      );
  }

  bool _busy = false;

  /// „Beschwerden melden“ (FR-0203) nach Rückfrage; Abbrechen ändert nichts.
  Future<void> _reportWarning() async {
    if (_busy) return;
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('plan_warning_dialog'),
        title: Text(l.planWarnReportTitle),
        scrollable: true,
        content: Text(l.planWarnReportText),
        actions: [
          TextButton(
            key: const Key('plan_warning_cancel'),
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l.planFormCancel),
          ),
          FilledButton(
            key: const Key('plan_warning_confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l.planWarnReportConfirm),
          ),
        ],
      ),
    );
    if (!mounted || ok != true) return;
    setState(() => _busy = true);
    final result = await _controller.reportWarning();
    if (!mounted) return;
    setState(() => _busy = false);
    _snack(
      messenger,
      'plan_warning_reported',
      result == PlanActionResult.done ? l.planWarnReported : l.planWarnFailed,
    );
  }

  /// „Meldung aufheben“ (FR-0203): die Meldung endet nur durch den Nutzer.
  Future<void> _liftWarning() async {
    if (_busy) return;
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    final result = await _controller.liftWarning();
    if (!mounted) return;
    setState(() => _busy = false);
    _snack(
      messenger,
      'plan_warning_lifted',
      result == PlanActionResult.done ? l.planWarnLifted : l.planWarnFailed,
    );
  }

  /// Nachfrage nach PAR-200 (Karte und Menü). Ist die Wochenzeit schon am
  /// Regler, fragt die App, ob das Ziel steigt; geändert wird nur nach
  /// Bestätigung (Zielformular).
  Future<void> _answerFeedback(PlanFeedback answer) async {
    if (_busy) return;
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    final out = await _controller.answerFeedback(answer);
    if (!mounted) return;
    setState(() => _busy = false);
    if (out.result != PlanActionResult.done) {
      _snack(messenger, 'plan_feedback_failed', l.planFeedbackFailed);
      return;
    }
    if (out.raiseGoalSignal) {
      final yes = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          key: const Key('plan_feedback_raise_dialog'),
          title: Text(l.planFeedbackRaiseTitle),
          scrollable: true,
          content: Text(l.planFeedbackRaiseText),
          actions: [
            TextButton(
              key: const Key('plan_feedback_raise_no'),
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l.planFeedbackRaiseNo),
            ),
            FilledButton(
              key: const Key('plan_feedback_raise_yes'),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l.planFeedbackRaiseYes),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (yes == true) await _openGoalForm(_controller.state.goal);
      return;
    }
    final changed = answer != PlanFeedback.fits;
    _snack(
      messenger,
      'plan_feedback_done',
      changed ? l.planFeedbackChanged : l.planFeedbackSame,
    );
  }

  void _snack(ScaffoldMessengerState m, String key, String text) => m
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(key: Key(key), content: Text(text)));

  /// Nachfrage jederzeit aus dem Menü (PAR-200): dieselbe Karte als Blatt.
  Future<void> _showFeedbackSheet() async {
    final answer = await showModalBottomSheet<PlanFeedback>(
      context: context,
      showDragHandle: true,
      builder: (context) => Padding(
        key: const Key('plan_feedback_sheet'),
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: _FeedbackCard(onAnswer: (a) => Navigator.of(context).pop(a)),
      ),
    );
    if (answer != null && mounted) await _answerFeedback(answer);
  }

  Future<void> _startUnit(PlanUnit unit) async {
    final start = widget.onStartUnit;
    if (start == null) return;
    await start(context, unit);
    if (mounted) await _controller.reload();
  }

  /// Verlauf der Änderungen (FR-0170); wer ihn öffnet, hat die Karte gesehen.
  Future<void> _openHistory() async {
    final notice = _controller.state.changeNotice;
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        builder: (_) => PlanHistoryScreen(load: _controller.changeHistory),
      ),
    );
    if (!mounted || notice == null) return;
    await _controller.markChangeSeen(notice.planId);
  }

  /// „Verstanden“ auf der Karte „Plan angepasst“.
  Future<void> _seeChange(PlanChangeNotice notice) async {
    if (_busy) return;
    setState(() => _busy = true);
    await _controller.markChangeSeen(notice.planId);
    if (!mounted) return;
    setState(() => _busy = false);
  }

  /// Vorschlag „Woche wiederholen“ (PAR-140) annehmen oder ablehnen.
  Future<void> _answerWalkRepeat(bool accept) async {
    if (_busy) return;
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final session =
        _controller.state.walkRunProposal?.suggestion.scope ==
        WalkRunRepeatScope.session;
    setState(() => _busy = true);
    final result = accept
        ? await _controller.acceptWalkRunRepeat()
        : await _controller.declineWalkRunRepeat();
    if (!mounted) return;
    setState(() => _busy = false);
    if (!accept && result == PlanActionResult.done) return;
    _snack(
      messenger,
      'plan_walk_repeat_result',
      result == PlanActionResult.done
          ? (session ? l.planWalkRepeatSessionDone : l.planWalkRepeatDone)
          : l.planWalkRepeatFailed,
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
              Flexible(
                child: TextButton.icon(
                  key: const Key('plan_open_calendar'),
                  onPressed: () => setState(() => _view.calendarOpen = true),
                  icon: const Icon(Icons.calendar_month_rounded),
                  label: Text(l.calendarOpen),
                ),
              ),
              PopupMenuButton<String>(
                key: const Key('plan_menu'),
                tooltip: MaterialLocalizations.of(context).showMenuTooltip,
                enabled: !_busy,
                onSelected: (v) {
                  if (v == 'report') _reportWarning();
                  if (v == 'feedback') _showFeedbackSheet();
                  if (v == 'history') _openHistory();
                },
                itemBuilder: (context) => [
                  if (s.warning == null)
                    PopupMenuItem(
                      key: const Key('plan_menu_report'),
                      value: 'report',
                      height: RamuriTheme.minTarget,
                      child: Text(l.planWarnReport),
                    ),
                  PopupMenuItem(
                    key: const Key('plan_menu_feedback'),
                    value: 'feedback',
                    height: RamuriTheme.minTarget,
                    child: Text(l.planFeedbackMenu),
                  ),
                  PopupMenuItem(
                    key: const Key('plan_menu_history'),
                    value: 'history',
                    height: RamuriTheme.minTarget,
                    child: Text(l.planHistoryOpen),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (s.warning != null) ...[
            _WarningBanner(
              state: s,
              today: _today,
              onLift: _busy ? null : _liftWarning,
            ),
            const SizedBox(height: 10),
          ],
          if (s.changeNotice case final notice?) ...[
            PlanChangeCard(
              notice: notice,
              onSeen: _busy ? null : () => _seeChange(notice),
              onHistory: _openHistory,
            ),
            const SizedBox(height: 10),
          ],
          if (s.walkRunProposal case final proposal?) ...[
            PlanWalkRepeatCard(
              proposal: proposal,
              onAccept: _busy ? null : () => _answerWalkRepeat(true),
              onDecline: _busy ? null : () => _answerWalkRepeat(false),
            ),
            const SizedBox(height: 10),
          ],
          _GoalCard(
            state: s,
            today: _today,
            onEdit: () => _openGoalForm(s.goal),
            onRecalculate: _recalculating ? null : _recalculate,
          ),
          for (final h in global) ...[const SizedBox(height: 10), h],
          if (s.feedbackDue) ...[
            const SizedBox(height: 10),
            _FeedbackCard(onAnswer: _busy ? null : _answerFeedback),
          ],
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
              onStart: widget.onStartUnit == null ? null : _startUnit,
            ),
          ),
        ],
      ),
    );
  }
}
