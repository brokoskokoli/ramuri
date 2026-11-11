part of 'plan_screen.dart';

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
    required this.onRecalculate,
  });

  final PlanViewState state;
  final DateTime today;

  /// Einstieg „Ziel ändern“ (PAR-203).
  final VoidCallback onEdit;

  /// „Neu berechnen“ (`manual`); `null`, solange eine Rechnung läuft.
  final VoidCallback? onRecalculate;

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
          Wrap(
            spacing: 4,
            children: [
              TextButton.icon(
                key: const Key('plan_edit_goal'),
                onPressed: onEdit,
                icon: const Icon(Icons.edit_rounded, size: 18),
                label: Text(l.planEditGoal),
              ),
              TextButton.icon(
                key: const Key('plan_recalculate'),
                onPressed: onRecalculate,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text(l.planRecalculate),
              ),
            ],
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
    String? main;
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
      // Rückstand („0 von 3“ am Montag). War bis heute keine Einheit fällig,
      // entfällt die Zeile („0 von 0“, E2E API 36); die Grundlage bleibt.
      final runDays = state.weekUnits
          .where(
            (u) =>
                u.kind != PlanUnitKind.rest &&
                !planDay(u.day).isAfter(planDay(today)),
          )
          .toList();
      main = runDays.isEmpty
          ? null
          : l.planAssessRegularity(
              runDays.where((u) => u.runId != null).length,
              runDays.length,
            );
      basis = l.planAssessBasisRegularity;
    }
    return [
      const SizedBox(height: 12),
      if (main != null)
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
    // Die Wochen der Rechnung beginnen mit der Woche von „heute“; die Nummer
    // für den Screenreader zählt wie der Wochenkopf ab dem Anker.
    final week =
        planWeekOf(weeks, t.subtract(Duration(days: t.weekday - 1))) ??
        weeks[current];
    final now = groups.firstWhere(
      (g) => current >= g.$2 && current < g.$2 + g.$3,
      orElse: () => groups.last,
    );
    final style = Theme.of(context).textTheme.labelSmall
        ?.copyWith(color: c.textLabel);
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    Widget bar(int i) => ClipRRect(
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
    );
    Widget label(int i) => Text(
      planPhaseShort(l, groups[i].$1),
      key: Key('plan_phase_${groups[i].$1.name}'),
      maxLines: 1,
      softWrap: false,
      style: style,
    );
    return Semantics(
      key: const Key('plan_phase_bar'),
      label: l.planPhaseSemantics(
        planPhaseFull(l, now.$1),
        week.index + 1,
        weeks.last.index + 1,
      ),
      excludeSemantics: true,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Jede Kurzform (OQ-0077) ganz lesbar, auch bei schmaler Phase und
          // großer Schrift: Stücke mindestens so breit wie ihre Beschriftung,
          // der Rest nach Zahl der Wochen. Passt das nicht in die Breite,
          // stehen die Beschriftungen nebeneinander unter dem Balken.
          final needed = [
            for (var i = 0; i < groups.length; i++)
              (TextPainter(
                    text: TextSpan(
                      text: planPhaseShort(l, groups[i].$1),
                      style: style,
                    ),
                    textDirection: direction,
                    textScaler: scaler,
                    maxLines: 1,
                  )..layout()).width.ceilToDouble() +
                  1,
          ];
          final widths = _segmentWidths(
            needed,
            [for (final g in groups) g.$3],
            // Etwas Luft gegen Rundung beim Aufsummieren.
            constraints.maxWidth - _gap * (groups.length - 1) - 1,
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  for (var i = 0; i < groups.length; i++) ...[
                    if (i > 0) const SizedBox(width: _gap),
                    if (widths == null)
                      Expanded(flex: groups[i].$3, child: bar(i))
                    else
                      SizedBox(width: widths[i], child: bar(i)),
                  ],
                ],
              ),
              const SizedBox(height: 6),
              if (widths == null)
                Wrap(
                  spacing: 12,
                  children: [for (var i = 0; i < groups.length; i++) label(i)],
                )
              else
                Row(
                  children: [
                    for (var i = 0; i < groups.length; i++) ...[
                      if (i > 0) const SizedBox(width: _gap),
                      SizedBox(width: widths[i], child: label(i)),
                    ],
                  ],
                ),
            ],
          );
        },
      ),
    );
  }

  static const double _gap = 4;

  /// Breiten der Stücke: nach Zahl der Wochen ([weeks]), aber mindestens
  /// [needed]. `null`, wenn die Beschriftungen zusammen nicht in [available]
  /// passen.
  static List<double>? _segmentWidths(
    List<double> needed,
    List<int> weeks,
    double available,
  ) {
    if (needed.fold<double>(0, (a, b) => a + b) > available) return null;
    final fixed = List<bool>.filled(needed.length, false);
    while (true) {
      var freeWeeks = 0;
      var freeSpace = available;
      for (var i = 0; i < needed.length; i++) {
        if (fixed[i]) {
          freeSpace -= needed[i];
        } else {
          freeWeeks += weeks[i];
        }
      }
      var changed = false;
      for (var i = 0; i < needed.length; i++) {
        if (!fixed[i] && freeSpace * weeks[i] / freeWeeks < needed[i]) {
          fixed[i] = true;
          changed = true;
        }
      }
      if (!changed) {
        return [
          for (var i = 0; i < needed.length; i++)
            fixed[i] ? needed[i] : freeSpace * weeks[i] / freeWeeks,
        ];
      }
    }
  }

  static double _fill((PlanPhase, int, int) g, int current) {
    if (current >= g.$2 + g.$3) return 1;
    if (current < g.$2) return 0;
    return (current - g.$2 + 1) / g.$3;
  }
}
