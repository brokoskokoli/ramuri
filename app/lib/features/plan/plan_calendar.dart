import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import '../../ui/ui.dart';
import 'plan_controller.dart';
import 'plan_page_view_state.dart';
import 'plan_texts.dart';

part 'plan_calendar_actions.dart';
part 'plan_calendar_dialogs.dart';
part 'plan_calendar_views.dart';

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
}
