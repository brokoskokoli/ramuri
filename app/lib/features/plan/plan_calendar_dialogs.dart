part of 'plan_calendar.dart';

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
