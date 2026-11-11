part of 'plan_calendar.dart';

extension _PlanCalendarActions on _PlanCalendarState {
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
}
