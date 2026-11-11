import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import '../../ui/ui.dart';
import 'plan_controller.dart';
import 'plan_page_view_state.dart';
import 'plan_texts.dart';

/// Kalender des Plans (FR-0171 bis FR-0173, FR-0175 bis FR-0178, WP22
/// Teil E): Wochen- und Monatsübersicht mit geplanten, erledigten (Lauf
/// zugeordnet) und ausgefallenen Einheiten und Ruhetagen. Eine künftige
/// offene Einheit lässt sich verschieben; die Prüfung ([checkPlanMove],
/// PAR-060) zeigt Konflikte und Alternativtage. Der Termin ändert sich nur
/// über „Verschieben“ im Bestätigungsdialog ([PlanController.confirmMove],
/// FR-0176, OQ-0011).
class PlanCalendar extends StatefulWidget {
  const PlanCalendar({
    super.key,
    required this.controller,
    required this.clock,
    required this.viewState,
    required this.onClose,
    required this.onOpenUnit,
  });

  final PlanController controller;
  final Clock clock;

  /// Zeitraum und Scrollposition über Tab-Wechsel.
  final PlanCalendarViewState viewState;
  final VoidCallback onClose;
  final void Function(PlanUnit unit) onOpenUnit;

  @override
  State<PlanCalendar> createState() => _PlanCalendarState();
}

/// Zustand eines Tags im Kalender (FR-0172): [free] ist ein absolvierter
/// Lauf ohne Einheit (FR-0171), nie ein Ruhetag.
enum _DayState { planned, done, missed, free, rest, none }

/// Einheiten und beendete Läufe des gezeigten Zeitraums.
class _CalendarData {
  const _CalendarData(this.units, this.runs);
  final List<PlanUnit> units;
  final List<PlanCalendarRun> runs;

  Map<DateTime, PlanUnit> get byDay => {
    for (final u in units) planDay(u.day): u,
  };

  /// Tage mit einem Lauf, der keiner Einheit des Zeitraums zugeordnet ist.
  Set<DateTime> get freeRunDays {
    final assigned = {
      for (final u in units)
        if (u.runId != null) u.runId,
    };
    return {
      for (final r in runs)
        if (!assigned.contains(r.id)) r.day,
    };
  }
}

String _dayKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

DateTime _mondayOf(DateTime d) {
  final x = planDay(d);
  return x.subtract(Duration(days: x.weekday - DateTime.monday));
}

class _PlanCalendarState extends State<PlanCalendar> {
  PlanCalendarViewState get _view => widget.viewState;
  late final ScrollController _scroll = ScrollController(
    initialScrollOffset: _view.scrollOffset,
  )..addListener(_rememberScroll);
  // Die gemerkte Position, vor dem ersten Bild festgehalten: Solange die
  // Einheiten laden, ist die Liste kurz und die Lage wird begrenzt; nach dem
  // Laden wird sie einmal wieder angesteuert, außer der Nutzer scrollte.
  late final double _restoreTarget;
  bool _userScrolled = false;

  Future<_CalendarData>? _units;
  String? _unitsKey;

  @override
  void initState() {
    super.initState();
    _restoreTarget = _view.scrollOffset;
    widget.controller.addListener(_onState);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onState);
    _scroll.dispose();
    super.dispose();
  }

  void _onState() {
    if (!mounted) return;
    setState(() => _units = null);
  }

  void _rememberScroll() {
    if (_scroll.hasClients) _view.scrollOffset = _scroll.offset;
  }

  void _restoreScroll() {
    if (!mounted || _userScrolled || !_scroll.hasClients) return;
    final target = _restoreTarget.clamp(0.0, _scroll.position.maxScrollExtent);
    if (target != _scroll.offset) _scroll.jumpTo(target);
  }

  DateTime get _today => calendarDay(widget.clock.now());

  /// Erster Ortstag des Plans (Montag der Ankerwoche).
  DateTime? get _first {
    final v = widget.controller.state.version;
    return v == null ? null : _mondayOf(v.inputs.anchor);
  }

  /// Letzter Ortstag des Plans (Sonntag der letzten Planwoche).
  DateTime? get _last {
    final weeks = widget.controller.state.hints?.weeks;
    if (weeks == null || weeks.isEmpty) return null;
    return _mondayOf(weeks.last.start).add(const Duration(days: 6));
  }

  bool _inPlan(DateTime d) {
    final f = _first, l = _last;
    return (f == null || !d.isBefore(f)) && (l == null || !d.isAfter(l));
  }

  DateTime get _monthStart {
    final t = _today;
    return DateTime.utc(t.year, t.month + _view.monthOffset, 1);
  }

  /// Gezeigter Zeitraum (Monat: ganze Wochen um den Monat).
  (DateTime, DateTime) get _range {
    if (!_view.month) {
      final m = _mondayOf(_today).add(Duration(days: 7 * _view.weekOffset));
      return (m, m.add(const Duration(days: 6)));
    }
    final start = _monthStart;
    final end = DateTime.utc(start.year, start.month + 1, 0);
    return (_mondayOf(start), _mondayOf(end).add(const Duration(days: 6)));
  }

  bool get _canBack {
    final f = _first;
    return f == null || _range.$1.isAfter(f);
  }

  bool get _canForward {
    final l = _last;
    return l == null || _range.$2.isBefore(l);
  }

  Future<_CalendarData> _read(DateTime from, DateTime to) async {
    final units = await widget.controller.unitsBetween(from, to);
    final runs = await widget.controller.runsBetween(from, to);
    return _CalendarData(units, runs);
  }

  Future<_CalendarData> _load() {
    final (from, to) = _range;
    final key = '${_dayKey(from)}/${_dayKey(to)}';
    if (_units != null && _unitsKey == key) return _units!;
    _unitsKey = key;
    return _units = _read(from, to).whenComplete(
      () =>
          WidgetsBinding.instance.addPostFrameCallback((_) => _restoreScroll()),
    );
  }

  void _step(int direction) => setState(() {
    if (_view.month) {
      _view.monthOffset += direction;
    } else {
      _view.weekOffset += direction;
    }
  });

  void _setMonth(bool month) => setState(() => _view.month = month);

  _DayState _stateOf(DateTime day, PlanUnit? u, {bool freeRun = false}) {
    if (u == null || (u.kind == PlanUnitKind.rest && u.runId == null)) {
      if (freeRun) return _DayState.free;
      return _inPlan(day) ? _DayState.rest : _DayState.none;
    }
    if (u.runId != null) return _DayState.done;
    if (planDay(u.day).isBefore(_today)) return _DayState.missed;
    return _DayState.planned;
  }

  bool _movable(PlanUnit u) =>
      u.id != null && u.runId == null && !planDay(u.day).isBefore(_today);

  String? _stateText(AppLocalizations l, _DayState s) => switch (s) {
    _DayState.planned => l.calendarStatePlanned,
    _DayState.done => l.calendarStateDone,
    _DayState.missed => l.calendarStateMissed,
    _DayState.free => l.calendarFreeRun,
    _DayState.rest => l.planRestDay,
    _DayState.none => null,
  };

  // ---------------------------------------------------------------------
  // Aktionen

  /// Vom Nutzer festgelegter Ruhetag ohne Lauf ([PlanUnit.isRestDay]).
  bool _userRest(PlanUnit? u) => u != null && u.isRestDay && u.runId == null;

  /// Ersetzbar: verschiebbar und weder Ruhetag noch Geh-Lauf
  /// ([checkPlanReplace] sperrt diese ohnehin).
  bool _replaceable(PlanUnit u) =>
      _movable(u) &&
      u.kind != PlanUnitKind.rest &&
      u.kind != PlanUnitKind.walkRun;

  /// Künftiger Tag im Plan ohne Einheit oder mit einer nicht festgelegten
  /// Ruhe-Einheit ohne Lauf: kann Ruhetag werden (auch von der App
  /// erzeugte Ruhetage, Schutz vor der Neuberechnung, OQ-0011).
  bool _freeFutureDay(DateTime day, PlanUnit? u) =>
      (u == null ||
          (u.kind == PlanUnitKind.rest && !u.pinned && u.runId == null)) &&
      !day.isBefore(_today) &&
      _inPlan(day);

  /// Ob ein Tag ein Blatt mit Aktionen hat.
  bool _hasActions(DateTime day, PlanUnit? u, _DayState state) {
    if (state == _DayState.planned ||
        state == _DayState.done ||
        state == _DayState.missed) {
      return true;
    }
    if (state != _DayState.rest) return false;
    return (_userRest(u) && !day.isBefore(_today)) || _freeFutureDay(day, u);
  }

  Future<void> _actions(DateTime day, PlanUnit? u) async {
    final l = AppLocalizations.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final unit = u != null && u.kind != PlanUnitKind.rest ? u : null;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final text = Theme.of(context).textTheme;
        void pop(String a) => Navigator.of(context).pop(a);
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(
              key: const Key('calendar_actions'),
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  unit != null ? planUnitText(l, unit) : l.planRestDay,
                  style: text.titleMedium,
                ),
                Text(
                  DateFormat.MMMMEEEEd(lang).format(day),
                  style: text.bodyMedium,
                ),
                const SizedBox(height: 12),
                if (unit != null) ...[
                  RamuriSecondaryButton(
                    key: const Key('calendar_details'),
                    label: l.calendarDetails,
                    onPressed: () => pop('details'),
                  ),
                  const SizedBox(height: 8),
                  if (_movable(unit)) ...[
                    RamuriPrimaryButton(
                      key: const Key('calendar_move'),
                      label: l.calendarMove,
                      onPressed: () => pop('move'),
                    ),
                    if (_replaceable(unit)) ...[
                      const SizedBox(height: 8),
                      RamuriSecondaryButton(
                        key: const Key('calendar_replace'),
                        label: l.calendarReplace,
                        onPressed: () => pop('replace'),
                      ),
                    ],
                    const SizedBox(height: 8),
                    RamuriSecondaryButton(
                      key: const Key('calendar_rest_set'),
                      label: l.calendarRestSet,
                      onPressed: () => pop('rest'),
                    ),
                  ] else
                    Text(
                      l.calendarFrozen,
                      key: const Key('calendar_frozen'),
                      style: text.bodySmall,
                    ),
                ] else if (_userRest(u) && !day.isBefore(_today))
                  RamuriSecondaryButton(
                    key: const Key('calendar_rest_clear'),
                    label: l.calendarRestClear,
                    onPressed: () => pop('clear'),
                  )
                else if (_freeFutureDay(day, u))
                  RamuriSecondaryButton(
                    key: const Key('calendar_rest_set'),
                    label: l.calendarRestSet,
                    onPressed: () => pop('rest'),
                  )
                else
                  // Ruhe-Einheit mit Lauf oder vergangen: nichts änderbar.
                  Text(
                    l.calendarFrozen,
                    key: const Key('calendar_frozen'),
                    style: text.bodySmall,
                  ),
              ],
            ),
          ),
        );
      },
    );
    if (!mounted) return;
    switch (action) {
      case 'details':
        widget.onOpenUnit(unit!);
      case 'move':
        await _move(unit!);
      case 'replace':
        await _replace(unit!);
      case 'rest':
        await _setRest(day);
      case 'clear':
        await _clearRest(day);
    }
  }

  void _showResult(ScaffoldMessengerState messenger, String message) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          key: const Key('calendar_change_result'),
          content: Text(message),
        ),
      );
  }

  /// Eine gescheiterte Prüfung zeigt der Dialog wie eine fehlende
  /// (`null`: Hinweis, Bestätigen gesperrt); der Inhalt des Fehlers wird nie
  /// gezeigt.
  static Future<T?> _orNull<T>(Future<T?> check) =>
      check.then<T?>((c) => c, onError: (Object _) => null);

  /// Ersetzen (FR-0173): Art wählen, Prüfung ansehen, bestätigen. Ohne
  /// Bestätigung bleibt die Einheit.
  Future<void> _replace(PlanUnit u) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final kind = await showDialog<PlanUnitKind>(
      context: context,
      builder: (_) => _ReplaceDialog(
        unit: u,
        check: (k) => _orNull(widget.controller.checkReplace(u, k)),
      ),
    );
    if (kind == null || !mounted) return;
    final result = await widget.controller.replaceUnit(u.id!, kind);
    _showResult(
      messenger,
      result == PlanActionResult.done
          ? l.calendarReplaced
          : l.calendarReplaceRejected,
    );
  }

  /// Ruhetag festlegen: Prüfung (Alternativtage für eine Einheit auf dem
  /// Tag), bestätigen. Ohne Bestätigung bleibt der Plan.
  Future<void> _setRest(DateTime day) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final choice = await showDialog<_RestChoice>(
      context: context,
      builder: (_) => _RestDayDialog(
        day: day,
        check: () => _orNull(widget.controller.checkRestDay(day)),
      ),
    );
    if (choice == null || !mounted) return;
    final result = await widget.controller.setRestDay(
      day,
      expectedUnitId: choice.unitId,
      moveUnitTo: choice.moveTo,
    );
    _showResult(
      messenger,
      result == PlanActionResult.done
          ? l.calendarRestSaved
          : l.calendarRestRejected,
    );
  }

  /// Ruhetag aufheben nach Bestätigung (OQ-0011).
  Future<void> _clearRest(DateTime day) async {
    final l = AppLocalizations.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('calendar_rest_clear_dialog'),
        title: Text(l.calendarRestClearTitle),
        scrollable: true,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.calendarRestClearText(DateFormat.MMMMEEEEd(lang).format(day)),
            ),
            const SizedBox(height: 8),
            Text(
              l.calendarChangeOnlyAfterConfirm,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          TextButton(
            key: const Key('calendar_rest_clear_cancel'),
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l.calendarMoveCancel),
          ),
          FilledButton(
            key: const Key('calendar_rest_clear_confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l.calendarRestClear),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final result = await widget.controller.clearRestDay(day);
    _showResult(
      messenger,
      result == PlanActionResult.done
          ? l.calendarRestCleared
          : l.calendarRestClearRejected,
    );
  }

  /// Verschieben: Tag wählen, prüfen, bestätigen. Ohne Bestätigung bleibt
  /// der Termin (FR-0176).
  Future<void> _move(PlanUnit u) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final goal = widget.controller.state.goal;
    if (goal == null) return;
    final today = _today;
    final last = _last ?? today.add(const Duration(days: 365));
    if (last.isBefore(today)) return;
    final List<PlanUnit> stored;
    try {
      stored = await widget.controller.unitsBetween(today, last);
    } on Object {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            key: const Key('calendar_move_result'),
            content: Text(l.calendarMoveRejected),
          ),
        );
      }
      return;
    }
    final taken = {
      for (final x in stored)
        if (x.id != u.id) planDay(x.day),
    };
    bool free(DateTime d) {
      final day = DateTime.utc(d.year, d.month, d.day);
      return day != planDay(u.day) && !taken.contains(day);
    }

    // Der Dialog beginnt beim nächsten freien Tag nach der Einheit (nicht
    // ab heute, E2E API 36); gibt es danach keinen, beim ersten ab heute.
    DateTime? firstFree(DateTime from) {
      for (var d = from; !d.isAfter(last); d = d.add(const Duration(days: 1))) {
        if (free(d)) return d;
      }
      return null;
    }

    final unitDay = planDay(u.day);
    final initial =
        (unitDay.isBefore(today) ? null : firstFree(unitDay)) ??
        firstFree(today);
    if (!mounted) return;
    if (initial == null) {
      messenger.showSnackBar(SnackBar(content: Text(l.calendarMoveDayTaken)));
      return;
    }
    DateTime local(DateTime d) => DateTime(d.year, d.month, d.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: local(initial),
      firstDate: local(today),
      lastDate: local(last),
      selectableDayPredicate: free,
    );
    if (picked == null || !mounted) return;
    final day = await showDialog<DateTime>(
      context: context,
      builder: (_) => _MoveDialog(
        unit: u,
        initialDay: DateTime.utc(picked.year, picked.month, picked.day),
        check: (d) => _check(u, d, goal),
      ),
    );
    if (day == null || !mounted) return;
    final result = await widget.controller.confirmMove(u.id!, day);
    messenger.showSnackBar(
      SnackBar(
        key: const Key('calendar_move_result'),
        content: Text(
          result == PlanActionResult.done
              ? l.calendarMoved
              : l.calendarMoveRejected,
        ),
      ),
    );
  }

  Future<PlanMoveCheck> _check(
    PlanUnit u,
    DateTime day,
    TrainingGoal goal,
  ) async {
    final a = planDay(u.day), b = planDay(day);
    final from = _mondayOf(a.isBefore(b) ? a : b)
        .subtract(const Duration(days: 7));
    final to = _mondayOf(a.isBefore(b) ? b : a).add(const Duration(days: 13));
    final data = await _read(from, to);
    return checkPlanMove(
      units: data.units,
      unit: u,
      newDay: day,
      today: _today,
      weeklyCapSeconds: goal.weeklyCapSeconds,
      completedIntensiveDays: [
        for (final r in data.runs)
          if (r.intensive) r.day,
      ],
      runDays: goal.runDays,
      parameters: widget.controller.parameters,
    );
  }

  // ---------------------------------------------------------------------
  // Aufbau

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final lang = Localizations.localeOf(context).languageCode;
    final (from, to) = _range;
    final period = _view.month
        ? DateFormat.yMMMM(lang).format(_monthStart)
        : '${DateFormat.MMMd(lang).format(from)} – '
              '${DateFormat.MMMd(lang).format(to)}';
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n is UserScrollNotification &&
            n.direction != ScrollDirection.idle) {
          _userScrolled = true;
        }
        return false;
      },
      child: ListView(
        key: const Key('calendar_list'),
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(12, 16, 12, 16),
        children: [
          Row(
            children: [
              IconButton(
                key: const Key('calendar_close'),
                tooltip: l.calendarClose,
                onPressed: widget.onClose,
                icon: const Icon(Icons.arrow_back_rounded),
              ),
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    l.calendarTitle,
                    key: const Key('calendar_title'),
                    style: RamuriType.of(context).pageTitle,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                  value: false,
                  label: Text(
                    l.calendarWeek,
                    key: const Key('calendar_mode_week'),
                  ),
                ),
                ButtonSegment(
                  value: true,
                  label: Text(
                    l.calendarMonth,
                    key: const Key('calendar_mode_month'),
                  ),
                ),
              ],
              selected: {_view.month},
              onSelectionChanged: (s) => _setMonth(s.first),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              IconButton(
                key: const Key('calendar_previous'),
                tooltip: l.calendarPrevious,
                onPressed: _canBack ? () => _step(-1) : null,
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              Expanded(
                child: Text(
                  period,
                  key: const Key('calendar_period'),
                  textAlign: TextAlign.center,
                  style: text.titleSmall,
                ),
              ),
              IconButton(
                key: const Key('calendar_next'),
                tooltip: l.calendarNext,
                onPressed: _canForward ? () => _step(1) : null,
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FutureBuilder<_CalendarData>(
            key: ValueKey('calendar_${_view.month}_${_dayKey(from)}'),
            future: _load(),
            builder: (context, snap) {
              if (snap.hasError) {
                return Text(
                  l.planLoadFailed,
                  key: const Key('calendar_failed'),
                );
              }
              final data = snap.data;
              if (data == null) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final byDay = data.byDay;
              final free = data.freeRunDays;
              return _view.month
                  ? _monthGrid(l, from, to, byDay, free)
                  : _weekList(l, from, byDay, free);
            },
          ),
          const SizedBox(height: 12),
          _Legend(
            stateText: (s) => _stateText(l, s)!,
            fixed: [
              (_restFixedIcon, '${l.planRestDay}, ${l.calendarRestFixedMark}'),
              (_replacedIcon, l.calendarReplacedMark),
            ],
          ),
        ],
      ),
    );
  }

  Widget _weekList(
    AppLocalizations l,
    DateTime monday,
    Map<DateTime, PlanUnit> byDay,
    Set<DateTime> free,
  ) {
    final lang = Localizations.localeOf(context).languageCode;
    return Column(
      key: const Key('calendar_week'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < 7; i++)
          Builder(
            builder: (context) {
              final day = monday.add(Duration(days: i));
              final u = byDay[day];
              final freeRun = free.contains(day);
              final state = _stateOf(day, u, freeRun: freeRun);
              final isToday = day == _today;
              final hasUnit =
                  state != _DayState.rest &&
                  state != _DayState.none &&
                  state != _DayState.free;
              // Ein Lauf ohne Einheit neben einer Einheit: eigene Zeile.
              final extraRun = freeRun && state != _DayState.free;
              final title = hasUnit
                  ? planUnitText(l, u!)
                  : (_stateText(l, state) ?? '');
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: RamuriCard(
                  key: Key('calendar_day_${_dayKey(day)}'),
                  radius: 16,
                  tone: isToday ? RamuriCardTone.panel : RamuriCardTone.surface,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  onTap: _hasActions(day, u, state)
                      ? () => _actions(day, u)
                      : null,
                  child: Builder(
                    builder: (context) {
                      final t = Theme.of(context).textTheme;
                      final cc = RamuriColors.of(context);
                      return ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 24),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 64,
                              child: Text(
                                DateFormat.MEd(lang).format(day),
                                style: t.labelMedium?.copyWith(
                                  color: isToday ? cc.accent : cc.textMuted,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title,
                                    style: hasUnit
                                        ? t.titleSmall
                                        : state == _DayState.free
                                        ? t.bodyMedium
                                        : t.bodyMedium?.copyWith(
                                            color: cc.textMuted,
                                          ),
                                  ),
                                  if (hasUnit && u!.fixed.keepsKind)
                                    _FixedMark(
                                      key: Key(
                                        'calendar_replaced_${_dayKey(day)}',
                                      ),
                                      icon: _replacedIcon,
                                      label: l.calendarReplacedMark,
                                    ),
                                  if (state == _DayState.rest && _userRest(u))
                                    _FixedMark(
                                      key: Key(
                                        'calendar_rest_fixed_${_dayKey(day)}',
                                      ),
                                      icon: _restFixedIcon,
                                      label: l.calendarRestFixedMark,
                                    ),
                                  if (extraRun)
                                    Text(
                                      l.calendarFreeRun,
                                      key: Key(
                                        'calendar_free_run_${_dayKey(day)}',
                                      ),
                                      style: t.bodySmall,
                                    ),
                                ],
                              ),
                            ),
                            if (hasUnit || state == _DayState.free)
                              _StateMark(
                                state: state,
                                label: state == _DayState.free
                                    ? l.calendarStateDone
                                    : _stateText(l, state)!,
                                showLabel: true,
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _monthGrid(
    AppLocalizations l,
    DateTime from,
    DateTime to,
    Map<DateTime, PlanUnit> byDay,
    Set<DateTime> free,
  ) {
    final lang = Localizations.localeOf(context).languageCode;
    final c = RamuriColors.of(context);
    final text = Theme.of(context).textTheme;
    final month = _monthStart.month;
    final days = to.difference(from).inDays + 1;
    final rows = <Widget>[
      Row(
        children: [
          for (var i = 0; i < 7; i++)
            Expanded(
              child: Center(
                child: ExcludeSemantics(
                  child: Text(
                    DateFormat.E(lang).format(from.add(Duration(days: i))),
                    style: text.labelSmall?.copyWith(color: c.textMuted),
                  ),
                ),
              ),
            ),
        ],
      ),
    ];
    for (var w = 0; w < days ~/ 7; w++) {
      rows.add(
        Row(
          children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                child: _monthCell(
                  l,
                  from.add(Duration(days: 7 * w + i)),
                  byDay,
                  free,
                  month,
                ),
              ),
          ],
        ),
      );
    }
    // Mindestens 48 dp je Tag; auf sehr schmalen Bildschirmen seitlich
    // scrollbar statt kleinerer Tippflächen.
    return LayoutBuilder(
      builder: (context, constraints) {
        const minWidth = 7 * 48.0;
        final grid = Column(key: const Key('calendar_month'), children: rows);
        if (constraints.maxWidth >= minWidth) return grid;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(width: minWidth, child: grid),
        );
      },
    );
  }

  Widget _monthCell(
    AppLocalizations l,
    DateTime day,
    Map<DateTime, PlanUnit> byDay,
    Set<DateTime> free,
    int month,
  ) {
    final lang = Localizations.localeOf(context).languageCode;
    final c = RamuriColors.of(context);
    final text = Theme.of(context).textTheme;
    final u = byDay[day];
    final freeRun = free.contains(day);
    final state = _stateOf(day, u, freeRun: freeRun);
    final hasUnit =
        state != _DayState.rest &&
        state != _DayState.none &&
        state != _DayState.free;
    final marked = hasUnit || state == _DayState.free;
    final other = day.month != month;
    final isToday = day == _today;
    final stateLabel = _stateText(l, state);
    final actions = _hasActions(day, u, state);
    final replaced = hasUnit && u!.fixed.keepsKind;
    final restFixed = state == _DayState.rest && _userRest(u);
    final semantics = [
      DateFormat.MMMMEEEEd(lang).format(day),
      if (hasUnit) planUnitText(l, u!),
      ?stateLabel,
      if (replaced) l.calendarReplacedMark,
      if (restFixed) l.calendarRestFixedMark,
      if (freeRun && state != _DayState.free) l.calendarFreeRun,
    ].join(', ');
    // Jeder Tag ein eigener Knoten, auch ohne Einheit (sonst verschmelzen
    // Tage ohne Aktion mit Nachbarn).
    return Semantics(
      container: true,
      button: actions,
      label: semantics,
      excludeSemantics: true,
      child: InkWell(
        key: Key('calendar_day_${_dayKey(day)}'),
        borderRadius: BorderRadius.circular(12),
        onTap: actions ? () => _actions(day, u) : null,
        child: Container(
          height: 56,
          margin: const EdgeInsets.all(1),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: isToday ? Border.all(color: c.accent, width: 1.5) : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '${day.day}',
                style: text.labelMedium?.copyWith(
                  color: other ? c.textSoft : c.text,
                ),
              ),
              const SizedBox(height: 4),
              SizedBox(
                height: 18,
                child: restFixed
                    ? Icon(
                        _restFixedIcon,
                        key: Key('calendar_rest_fixed_${_dayKey(day)}'),
                        size: 16,
                        color: c.textMuted,
                      )
                    : marked
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _StateMark(state: state, label: stateLabel!),
                          if (replaced)
                            Icon(
                              _replacedIcon,
                              key: Key('calendar_replaced_${_dayKey(day)}'),
                              size: 14,
                              color: c.accent,
                            ),
                        ],
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Zeichen der Festlegungen des Nutzers: Ruhetag festgelegt, Art ersetzt.
const IconData _restFixedIcon = Icons.push_pin_outlined;
const IconData _replacedIcon = Icons.swap_horiz_rounded;

/// Zeile „von dir festgelegt“ / „Art von dir ersetzt“ in der Wochenansicht.
class _FixedMark extends StatelessWidget {
  const _FixedMark({super.key, required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = RamuriColors.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: c.accent),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: c.textMuted),
          ),
        ),
      ],
    );
  }
}

/// Zeichen eines Zustands (FR-0172): geplant (Ring), erledigt (Haken),
/// ausgefallen (Kreuz). Unterscheidbar auch ohne Farbe.
class _StateMark extends StatelessWidget {
  const _StateMark({
    required this.state,
    required this.label,
    this.showLabel = false,
  });

  final _DayState state;
  final String label;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final c = RamuriColors.of(context);
    final (icon, color) = switch (state) {
      _DayState.done => (Icons.check_circle_rounded, c.action),
      _DayState.free => (Icons.check_circle_outline_rounded, c.action),
      _DayState.missed => (Icons.cancel_outlined, c.textMuted),
      _ => (Icons.radio_button_unchecked_rounded, c.accent),
    };
    final mark = Icon(icon, size: 18, color: color);
    if (!showLabel) return mark;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        mark,
        const SizedBox(width: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall
              ?.copyWith(color: c.textMuted),
        ),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.stateText, this.fixed = const []});

  final String Function(_DayState) stateText;

  /// Zeichen der Festlegungen des Nutzers mit Beschriftung.
  final List<(IconData, String)> fixed;

  @override
  Widget build(BuildContext context) {
    final c = RamuriColors.of(context);
    final style = Theme.of(context).textTheme.labelSmall
        ?.copyWith(color: c.textMuted);
    return Wrap(
      key: const Key('calendar_legend'),
      alignment: WrapAlignment.center,
      spacing: 16,
      runSpacing: 4,
      children: [
        for (final s in [
          _DayState.planned,
          _DayState.done,
          _DayState.missed,
          _DayState.free,
        ])
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _StateMark(state: s, label: stateText(s)),
              const SizedBox(width: 4),
              Flexible(child: Text(stateText(s), style: style)),
            ],
          ),
        for (final (icon, label) in fixed)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: c.accent),
              const SizedBox(width: 4),
              Flexible(child: Text(label, style: style)),
            ],
          ),
      ],
    );
  }
}

/// Bestätigungsdialog des Verschiebens: zeigt die Prüfung (Konflikt,
/// Regler, Alternativen) und gibt nur bei „Verschieben“ den Tag zurück.
class _MoveDialog extends StatefulWidget {
  const _MoveDialog({
    required this.unit,
    required this.initialDay,
    required this.check,
  });

  final PlanUnit unit;
  final DateTime initialDay;
  final Future<PlanMoveCheck> Function(DateTime day) check;

  @override
  State<_MoveDialog> createState() => _MoveDialogState();
}

class _MoveDialogState extends State<_MoveDialog> {
  late DateTime _day = widget.initialDay;
  late Future<PlanMoveCheck> _result = widget.check(_day);

  void _choose(DateTime d) => setState(() {
    _day = d;
    _result = widget.check(d);
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    String day(DateTime d) => DateFormat.MMMEd(lang).format(d);
    return FutureBuilder<PlanMoveCheck>(
      future: _result,
      builder: (context, snap) {
        final c = snap.data;
        final text = Theme.of(context).textTheme;
        final ready = c != null && c.day == planDay(_day);
        final warn = ready && (c.hasSpacingConflict || c.overRegulator);
        return AlertDialog(
          key: const Key('calendar_move_dialog'),
          title: Text(l.calendarMoveTitle),
          scrollable: true,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l.calendarMoveFromTo(
                  planUnitText(l, widget.unit),
                  day(widget.unit.day),
                  day(_day),
                ),
                key: const Key('calendar_move_from_to'),
                style: text.bodyLarge,
              ),
              const SizedBox(height: 8),
              Text(l.calendarMoveOnlyAfterConfirm, style: text.bodySmall),
              if (snap.hasError)
                Text(l.calendarMoveRejected)
              else if (!ready)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Center(child: CircularProgressIndicator()),
                )
              else ...[
                if (c.blocked == PlanMoveBlock.dayTaken)
                  _line(l.calendarMoveDayTaken, 'calendar_move_taken')
                else if (c.blocked != null)
                  _line(l.calendarMoveRejected, 'calendar_move_blocked'),
                for (final d in c.spacingDays)
                  _line(
                    l.calendarMoveConflict(day(d)),
                    'calendar_move_conflict_${_dayKey(d)}',
                  ),
                if (c.allowed && c.endsHardReplacement)
                  _line(
                    l.calendarMoveEndsHardReplacement,
                    'calendar_move_ends_hard_replacement',
                  ),
                if (c.overRegulator)
                  _line(
                    l.calendarMoveRegulator(
                      planDurationText(l, c.weekMinutes),
                      planDurationText(l, c.weekCapMinutes),
                    ),
                    'calendar_move_regulator',
                  ),
                if (warn && c.alternatives.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    l.calendarMoveAlternatives,
                    key: const Key('calendar_move_alternatives'),
                    style: text.bodySmall,
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final d in c.alternatives)
                        ActionChip(
                          key: Key('calendar_alternative_${_dayKey(d)}'),
                          label: Text(day(d)),
                          onPressed: () => _choose(d),
                        ),
                    ],
                  ),
                ] else if (warn)
                  _line(
                    l.calendarMoveNoAlternative,
                    'calendar_move_no_alternative',
                  ),
              ],
            ],
          ),
          actions: [
            TextButton(
              key: const Key('calendar_move_cancel'),
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l.calendarMoveCancel),
            ),
            FilledButton(
              key: const Key('calendar_move_confirm'),
              onPressed: ready && c.allowed
                  ? () => Navigator.of(context).pop(planDay(_day))
                  : null,
              child: Text(
                warn ? l.calendarMoveConfirmAnyway : l.calendarMoveConfirm,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _line(String s, String key) => _hint(context, s, key);
}

/// Hinweiszeile in den Dialogen des Kalenders.
Widget _hint(BuildContext context, String s, String key) => Padding(
  padding: const EdgeInsets.only(top: 10),
  child: Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(
        Icons.info_outline_rounded,
        size: 18,
        color: RamuriColors.of(context).accent,
      ),
      const SizedBox(width: 8),
      Expanded(child: Text(s, key: Key(key))),
    ],
  ),
);

/// Bestätigungsdialog des Ersetzens (FR-0173): Art wählen, Prüfung
/// ([PlanController.checkReplace]) mit neuer Dauer und Hinweisen (Abstand
/// PAR-059/PAR-060, zweite harte Einheit PAR-198) ansehen; gibt nur bei
/// „Ersetzen“ die Art zurück.
class _ReplaceDialog extends StatefulWidget {
  const _ReplaceDialog({required this.unit, required this.check});

  final PlanUnit unit;
  final Future<PlanReplaceCheck?> Function(PlanUnitKind kind) check;

  @override
  State<_ReplaceDialog> createState() => _ReplaceDialogState();
}

class _ReplaceDialogState extends State<_ReplaceDialog> {
  PlanUnitKind? _kind;
  Future<PlanReplaceCheck?>? _result;

  void _choose(PlanUnitKind k) => setState(() {
    _kind = k;
    _result = widget.check(k);
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    String day(DateTime d) => DateFormat.MMMEd(lang).format(d);
    return FutureBuilder<PlanReplaceCheck?>(
      future: _result,
      builder: (context, snap) {
        final text = Theme.of(context).textTheme;
        final done =
            _result != null && snap.connectionState == ConnectionState.done;
        final c = done && !snap.hasError ? snap.data : null;
        final ready = c != null && c.kind == _kind;
        final warn = ready && (c.hasSpacingConflict || c.hasSecondHard);
        return AlertDialog(
          key: const Key('calendar_replace_dialog'),
          title: Text(l.calendarReplaceTitle),
          scrollable: true,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l.calendarReplaceIntro(
                  planUnitText(l, widget.unit),
                  day(widget.unit.day),
                ),
                style: text.bodyLarge,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final k in planReplaceKinds)
                    if (k != widget.unit.kind)
                      ChoiceChip(
                        key: Key('calendar_replace_kind_${k.name}'),
                        label: Text(planKindName(l, k)),
                        selected: _kind == k,
                        onSelected: (_) => _choose(k),
                      ),
                ],
              ),
              if (_result != null && !done)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (done && !ready)
                _hint(context, l.calendarCheckFailed, 'calendar_check_failed')
              else if (ready) ...[
                if (c.blocked == PlanReplaceBlock.exceedsMaxSession)
                  _hint(
                    context,
                    l.calendarReplaceTooLong,
                    'calendar_replace_blocked',
                  )
                else if (c.blocked != null)
                  _hint(
                    context,
                    l.calendarReplaceBlocked,
                    'calendar_replace_blocked',
                  )
                else
                  _hint(
                    context,
                    l.calendarReplaceNew(planUnitText(l, c.unit!)),
                    'calendar_replace_new',
                  ),
                for (final d in c.spacingDays)
                  _hint(
                    context,
                    l.calendarMoveConflict(day(d)),
                    'calendar_replace_conflict_${_dayKey(d)}',
                  ),
                for (final d in c.otherHardDays)
                  _hint(
                    context,
                    l.calendarReplaceSecondHard(day(d)),
                    'calendar_replace_second_hard_${_dayKey(d)}',
                  ),
                // Eine lockere Einheit wird hart: Die Neuberechnung macht die
                // andere harte Einheit der Woche zum lockeren Lauf (PAR-198).
                if (c.hasSecondHard)
                  _hint(
                    context,
                    l.calendarReplaceOtherHardEasy,
                    'calendar_replace_other_hard_easy',
                  ),
              ],
              const SizedBox(height: 12),
              Text(l.calendarReplaceKeeps, style: text.bodySmall),
              Text(l.calendarChangeOnlyAfterConfirm, style: text.bodySmall),
            ],
          ),
          actions: [
            TextButton(
              key: const Key('calendar_replace_cancel'),
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l.calendarMoveCancel),
            ),
            FilledButton(
              key: const Key('calendar_replace_confirm'),
              onPressed: ready && c.allowed
                  ? () => Navigator.of(context).pop(c.kind)
                  : null,
              child: Text(
                warn
                    ? l.calendarReplaceConfirmAnyway
                    : l.calendarReplaceConfirm,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Auswahl im Ruhetag-Dialog: Zieltag der Einheit oder `null` (entfällt
/// bzw. keine Einheit auf dem Tag).
class _RestChoice {
  const _RestChoice(this.moveTo, this.unitId);
  final DateTime? moveTo;

  /// Die Einheit, die der Dialog auf dem Tag gezeigt hat (`null`: frei).
  final int? unitId;
}

/// Bestätigungsdialog „Ruhetag festlegen“: Prüfung
/// ([PlanController.checkRestDay]); liegt eine Einheit auf dem Tag, wählt
/// der Nutzer einen Alternativtag derselben Woche, ohne passenden Tag
/// entfällt sie. Gibt nur bei „Ruhetag festlegen“ eine Auswahl zurück.
class _RestDayDialog extends StatefulWidget {
  const _RestDayDialog({required this.day, required this.check});

  final DateTime day;
  final Future<PlanRestDayCheck?> Function() check;

  @override
  State<_RestDayDialog> createState() => _RestDayDialogState();
}

class _RestDayDialogState extends State<_RestDayDialog> {
  late final Future<PlanRestDayCheck?> _result = widget.check();
  DateTime? _moveTo;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    String day(DateTime d) => DateFormat.MMMEd(lang).format(d);
    return FutureBuilder<PlanRestDayCheck?>(
      future: _result,
      builder: (context, snap) {
        final text = Theme.of(context).textTheme;
        final done = snap.connectionState == ConnectionState.done;
        final c = done && !snap.hasError ? snap.data : null;
        final alternatives = c?.alternatives ?? const <DateTime>[];
        final moveTo = c?.unit == null || alternatives.isEmpty
            ? null
            : (_moveTo ?? alternatives.first);
        return AlertDialog(
          key: const Key('calendar_rest_dialog'),
          title: Text(l.calendarRestTitle),
          scrollable: true,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l.calendarRestIntro(
                  DateFormat.MMMMEEEEd(lang).format(widget.day),
                ),
                style: text.bodyLarge,
              ),
              if (!done)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (c == null)
                _hint(context, l.calendarCheckFailed, 'calendar_check_failed')
              else if (c.blocked != null)
                _hint(context, l.calendarRestBlocked, 'calendar_rest_blocked')
              else if (c.unit != null && alternatives.isEmpty)
                _hint(
                  context,
                  l.calendarRestUnitDrops(planUnitText(l, c.unit!)),
                  'calendar_rest_unit_drops',
                )
              else if (c.unit != null) ...[
                _hint(
                  context,
                  l.calendarRestUnitMoves(planUnitText(l, c.unit!)),
                  'calendar_rest_unit_moves',
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final d in alternatives)
                      ChoiceChip(
                        key: Key('calendar_rest_alternative_${_dayKey(d)}'),
                        label: Text(day(d)),
                        selected: d == moveTo,
                        onSelected: (_) => setState(() => _moveTo = d),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              Text(l.calendarChangeOnlyAfterConfirm, style: text.bodySmall),
            ],
          ),
          actions: [
            TextButton(
              key: const Key('calendar_rest_cancel'),
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l.calendarMoveCancel),
            ),
            FilledButton(
              key: const Key('calendar_rest_confirm'),
              onPressed: c != null && c.allowed
                  ? () =>
                        Navigator.of(context)
                            .pop(_RestChoice(moveTo, c.expectedUnitId))
                  : null,
              child: Text(l.calendarRestConfirm),
            ),
          ],
        );
      },
    );
  }
}
