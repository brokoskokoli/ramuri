part of 'plan_calendar.dart';

extension _PlanCalendarViews on _PlanCalendarState {
  /// Einheitliche Breite der Datumsspalte: die breiteste Beschriftung der
  /// Woche bei der eingestellten Schriftgröße, höchstens 30 % der Breite
  /// (darüber bricht das Datum um, der Titel behält Platz).
  double _dateColumnWidth(List<String> labels, TextStyle? style) {
    final scaler = MediaQuery.textScalerOf(context);
    final dir = Directionality.of(context);
    var w = 0.0;
    for (final label in labels) {
      final p = TextPainter(
        text: TextSpan(text: label, style: style),
        textDirection: dir,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      if (p.width > w) w = p.width;
      p.dispose();
    }
    final cap = MediaQuery.sizeOf(context).width * 0.3;
    return (w.ceilToDouble() + 1).clamp(0, cap).toDouble();
  }

  Widget _weekList(
    AppLocalizations l,
    DateTime monday,
    Map<DateTime, PlanUnit> byDay,
    Set<DateTime> free,
  ) {
    final lang = Localizations.localeOf(context).languageCode;
    final dateWidth = _dateColumnWidth([
      for (var i = 0; i < 7; i++)
        DateFormat.MEd(lang).format(monday.add(Duration(days: i))),
    ], Theme.of(context).textTheme.labelMedium);
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
                              width: dateWidth,
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
