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

/// Zustand einer Einheit im Kalender (FR-0172).
enum _DayState { planned, done, missed, rest, none }

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

  Future<List<PlanUnit>>? _units;
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

  Future<List<PlanUnit>> _load() {
    final (from, to) = _range;
    final key = '${_dayKey(from)}/${_dayKey(to)}';
    if (_units != null && _unitsKey == key) return _units!;
    _unitsKey = key;
    return _units = widget.controller
        .unitsBetween(from, to)
        .whenComplete(
          () => WidgetsBinding.instance.addPostFrameCallback(
            (_) => _restoreScroll(),
          ),
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

  _DayState _stateOf(DateTime day, PlanUnit? u) {
    if (u == null || (u.kind == PlanUnitKind.rest && u.runId == null)) {
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
    _DayState.rest => l.planRestDay,
    _DayState.none => null,
  };

  // ---------------------------------------------------------------------
  // Aktionen

  Future<void> _actions(PlanUnit u) async {
    final l = AppLocalizations.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final text = Theme.of(context).textTheme;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(
              key: const Key('calendar_actions'),
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(planUnitText(l, u), style: text.titleMedium),
                Text(
                  DateFormat.MMMMEEEEd(lang).format(u.day),
                  style: text.bodyMedium,
                ),
                const SizedBox(height: 12),
                RamuriSecondaryButton(
                  key: const Key('calendar_details'),
                  label: l.calendarDetails,
                  onPressed: () => Navigator.of(context).pop('details'),
                ),
                const SizedBox(height: 8),
                if (_movable(u))
                  RamuriPrimaryButton(
                    key: const Key('calendar_move'),
                    label: l.calendarMove,
                    onPressed: () => Navigator.of(context).pop('move'),
                  )
                else
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
    if (action == 'details') widget.onOpenUnit(u);
    if (action == 'move') await _move(u);
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
    final taken = {
      for (final x in await widget.controller.unitsBetween(today, last))
        if (x.id != u.id) planDay(x.day),
    };
    bool free(DateTime d) {
      final day = DateTime.utc(d.year, d.month, d.day);
      return day != planDay(u.day) && !taken.contains(day);
    }

    DateTime? initial;
    for (var d = today; !d.isAfter(last); d = d.add(const Duration(days: 1))) {
      if (free(d)) {
        initial = d;
        break;
      }
    }
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
    return checkPlanMove(
      units: await widget.controller.unitsBetween(from, to),
      unit: u,
      newDay: day,
      today: _today,
      weeklyCapSeconds: goal.weeklyCapSeconds,
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
          FutureBuilder<List<PlanUnit>>(
            key: ValueKey('calendar_${_view.month}_${_dayKey(from)}'),
            future: _load(),
            builder: (context, snap) {
              if (snap.hasError) {
                return Text(
                  l.planLoadFailed,
                  key: const Key('calendar_failed'),
                );
              }
              final units = snap.data;
              if (units == null) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final byDay = {for (final u in units) planDay(u.day): u};
              return _view.month
                  ? _monthGrid(l, from, to, byDay)
                  : _weekList(l, from, byDay);
            },
          ),
          const SizedBox(height: 12),
          _Legend(stateText: (s) => _stateText(l, s)!),
        ],
      ),
    );
  }

  Widget _weekList(
    AppLocalizations l,
    DateTime monday,
    Map<DateTime, PlanUnit> byDay,
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
              final state = _stateOf(day, u);
              final isToday = day == _today;
              final hasUnit =
                  state != _DayState.rest && state != _DayState.none;
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
                  onTap: hasUnit ? () => _actions(u!) : null,
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
                              child: Text(
                                title,
                                style: hasUnit
                                    ? t.titleSmall
                                    : t.bodyMedium?.copyWith(
                                        color: cc.textMuted,
                                      ),
                              ),
                            ),
                            if (hasUnit)
                              _StateMark(
                                state: state,
                                label: _stateText(l, state)!,
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
                  month,
                ),
              ),
          ],
        ),
      );
    }
    return Column(key: const Key('calendar_month'), children: rows);
  }

  Widget _monthCell(
    AppLocalizations l,
    DateTime day,
    Map<DateTime, PlanUnit> byDay,
    int month,
  ) {
    final lang = Localizations.localeOf(context).languageCode;
    final c = RamuriColors.of(context);
    final text = Theme.of(context).textTheme;
    final u = byDay[day];
    final state = _stateOf(day, u);
    final hasUnit = state != _DayState.rest && state != _DayState.none;
    final other = day.month != month;
    final isToday = day == _today;
    final stateLabel = _stateText(l, state);
    final semantics = [
      DateFormat.MMMMEEEEd(lang).format(day),
      if (hasUnit) planUnitText(l, u!),
      ?stateLabel,
    ].join(', ');
    return Semantics(
      button: hasUnit,
      label: semantics,
      excludeSemantics: true,
      child: InkWell(
        key: Key('calendar_day_${_dayKey(day)}'),
        borderRadius: BorderRadius.circular(12),
        onTap: hasUnit ? () => _actions(u!) : null,
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
                child: hasUnit
                    ? _StateMark(state: state, label: stateLabel!)
                    : null,
              ),
            ],
          ),
        ),
      ),
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
  const _Legend({required this.stateText});

  final String Function(_DayState) stateText;

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
        for (final s in [_DayState.planned, _DayState.done, _DayState.missed])
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _StateMark(state: s, label: stateText(s)),
              const SizedBox(width: 4),
              Text(stateText(s), style: style),
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

  Widget _line(String s, String key) => Padding(
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
}
