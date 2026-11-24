part of 'plan_screen.dart';

/// Die gezeigte Woche: Titel mit Wochenzeit (und „ca.“ Kilometern), die
/// Hinweise der Woche und Montag bis Sonntag.
class _Week extends StatelessWidget {
  const _Week({
    required this.state,
    required this.monday,
    required this.today,
    required this.units,
    this.runs = const {},
    required this.onStep,
    required this.onOpen,
    this.onStart,
    this.hasError = false,
  });

  final PlanViewState state;
  final DateTime monday;
  final DateTime today;

  /// `null`, solange die Woche lädt.
  final List<PlanUnit>? units;

  /// Zugeordnete Läufe der erledigten Einheiten nach Kennung
  /// ([PlanController.doneRuns], FR-0171).
  final Map<int, PlanDoneRun> runs;

  /// Laden der Woche ist fehlgeschlagen (statt ewig zu laden).
  final bool hasError;
  final void Function(int direction) onStep;

  /// Tipp auf eine Karte; mit dem schon geladenen Lauf der erledigten
  /// Einheit (`null`: offen oder Lauf nicht lesbar).
  final void Function(PlanUnit unit, PlanDoneRun? run) onOpen;

  /// „Start“ an der heutigen offenen Einheit; `null`: kein Knopf.
  final void Function(PlanUnit unit)? onStart;

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
    // Begründungen der Regel der Abweichung (PAR-235) aus der letzten Fassung.
    final notes = planRunNotesFromSummary(state.version!.summary);
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
              note: switch (_unitOn(list, monday.add(Duration(days: d)))) {
                final u? => planRunNoteFor(u, notes),
                null => null,
              },
              runs: runs,
              dropped: dropped.any(
                (x) => planDay(x) == planDay(monday.add(Duration(days: d))),
              ),
              isToday: planDay(monday.add(Duration(days: d))) == planDay(today),
              onOpen: onOpen,
              onStart: onStart,
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
    this.note,
    this.runs = const {},
    required this.dropped,
    required this.isToday,
    required this.onOpen,
    required this.colors,
    this.onStart,
  });

  final DateTime day;
  final PlanUnit? unit;

  /// Begründung, wenn die Regel der Abweichung die Einheit geändert hat
  /// (PAR-235); nur an offenen Einheiten.
  final PlanRunNote? note;
  final Map<int, PlanDoneRun> runs;
  final bool dropped;
  final bool isToday;

  /// Tipp auf eine Karte; mit dem schon geladenen Lauf der erledigten
  /// Einheit (`null`: offen oder Lauf nicht lesbar).
  final void Function(PlanUnit unit, PlanDoneRun? run) onOpen;
  final RamuriColors colors;

  /// „Start“ (nur heute, offen, kein Ruhetag; wie im Design Plan.dc.html).
  final void Function(PlanUnit unit)? onStart;

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
    final canStart =
        isToday && !done && u.kind != PlanUnitKind.rest && onStart != null;
    final label = u.kind == PlanUnitKind.rest
        ? l.planRestDay
        : l.planUnitLine(
            planKindName(l, u.kind),
            planDurationText(l, u.minutes),
          );
    // Zweite Zeile: Zielsetzung der Art (FR-0142) als Kurzzeile ohne
    // Schlusspunkt, bei heute „· heute“ angehängt; ein Ruhetag mit Lauf hat
    // keine Zielsetzung.
    final purpose = u.kind == PlanUnitKind.rest
        ? null
        : planPurposeLine(l, u.kind);
    final subline = purpose == null
        ? (isToday ? l.planToday : null)
        : (isToday ? '$purpose · ${l.planToday}' : purpose);
    // Erledigt mit vorhandenem Lauf: oben der echte Lauf, darunter klein die
    // Vorgabe (FR-0171). Ohne Lauf (gelöscht, nicht lesbar) und beim Ruhetag
    // ([PlanController.doneRuns] lässt ihn aus) wie bisher die Vorgabe.
    final run = runs[u.runId];
    final formatter = AppSettingsScope.formatterOf(context);
    final runLine = run == null ? null : planDoneRunLine(l, formatter, run);
    final intensity = run == null ? null : planDoneIntensity(l, run);
    final planned = planPlannedLine(l, u);
    return RamuriCard(
      key: key,
      radius: 16,
      tone: isToday ? RamuriCardTone.panel : RamuriCardTone.surface,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      onTap: () => onOpen(u, run),
      child: Builder(
        builder: (context) {
          final t = Theme.of(context).textTheme;
          final cc = RamuriColors.of(context);
          final row = Row(
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
                    if (runLine != null) ...[
                      Wrap(
                        spacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            runLine,
                            key: const Key('plan_day_run'),
                            style: t.titleSmall,
                          ),
                          if (intensity != null)
                            Text(
                              intensity,
                              key: const Key('plan_day_run_intensity'),
                              style: t.labelMedium?.copyWith(color: cc.accent),
                            ),
                        ],
                      ),
                      Text(
                        planned,
                        key: const Key('plan_day_planned'),
                        style: t.bodySmall?.copyWith(color: cc.textMuted),
                      ),
                    ] else ...[
                      Text(label, style: t.titleSmall),
                      if (subline != null)
                        Text(
                          subline,
                          key: const Key('plan_day_purpose'),
                          style: t.bodySmall?.copyWith(color: cc.textMuted),
                        ),
                      if (note case final n?)
                        Text(
                          planRunNoteText(
                            l,
                            n,
                            (d) => DateFormat.EEEE(lang).format(d),
                          ),
                          key: const Key('plan_day_deviation'),
                          style: t.bodySmall?.copyWith(color: cc.accent),
                        ),
                    ],
                  ],
                ),
              ),
              if (canStart)
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: 8),
                  child: FilledButton(
                    key: const Key('plan_day_start'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(
                        RamuriTheme.minTarget,
                        RamuriTheme.minTarget,
                      ),
                    ),
                    onPressed: () => onStart!(u),
                    child: Text(
                      l.planDayStart,
                      semanticsLabel: l.planDayStartSemantics(label),
                    ),
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
          if (runLine == null) return row;
          // Vorleser: Tag, Lauf (mit Kennzeichen) und Vorgabe in einem Satz.
          return Semantics(
            key: const Key('plan_day_done_semantics'),
            label:
                '${DateFormat.EEEE(lang).format(day)}. '
                '${l.planDayDoneSemantics(intensity == null ? runLine : '$runLine, $intensity', planned)}',
            excludeSemantics: true,
            child: row,
          );
        },
      ),
    );
  }
}
