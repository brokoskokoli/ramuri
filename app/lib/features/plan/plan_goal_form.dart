import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import '../../ui/ui.dart';
import '../settings/app_settings.dart';
import '../statistics/prediction_card.dart';
import '../statistics/reference_form.dart';
import 'plan_controller.dart';
import 'plan_texts.dart';

/// Werte des Reglers im Formular. Keine PAR setzt Grenzen oder einen
/// Startwert für den Regler (PAR-196 nennt nur „entspannt bis anspruchsvoll,
/// in Stunden je Woche“; Lücke aus wp21-b1 Punkt 1). Vorschlag, im Bericht
/// gemeldet; ein gespeicherter Wert außerhalb erweitert die Spanne.
abstract final class PlanGoalFormDefaults {
  /// Untere Grenze des Reglers in Stunden je Woche.
  static const double regulatorMinHours = 1;

  /// Obere Grenze des Reglers in Stunden je Woche.
  static const double regulatorMaxHours = 10;

  /// Schritt des Reglers in Stunden.
  static const double regulatorStepHours = 0.5;

  /// Startwert beim Anlegen ohne gespeichertes Ziel.
  static const double regulatorStartHours = 4;
}

/// Zielformular (FR-0136, PAR-192, PAR-196, PAR-203): Ziel, Zieldatum,
/// Lauftage, maximale Zeit je Einheit, Stand (entfällt mit vorhandenen
/// Läufen), Regler, Schalter „harte Einheit“, bisherige Wettkampfzeiten
/// (Referenz, FR-0129, Eingabe aus WP20). Vor dem Speichern steht die
/// Einschätzung (PAR-206, mit Angebot eines Datums), vor einem Geh-Lauf-Plan
/// der Hinweis aus PAR-115 zum Bestätigen. Gibt das Ergebnis von
/// [PlanController.saveGoal] zurück (`done` oder `savedNotPlanned`); bei
/// Ablehnung oder Fehler bleibt das Formular mit einer Meldung offen.
///
/// Gerechnet und geprüft wird in `core` ([TrainingGoal.validate],
/// [assessGoal] über [PlanController.checkGoal]); „heute“ ist der Ortstag der
/// [clock].
class PlanGoalFormScreen extends StatefulWidget {
  const PlanGoalFormScreen({
    super.key,
    required this.controller,
    required this.session,
    required this.clock,
    this.initial,
  });

  final PlanController controller;
  final StorageSession session;
  final Clock clock;

  /// Das gespeicherte Ziel beim Ändern (vorbelegt), `null` beim Anlegen.
  final TrainingGoal? initial;

  @override
  State<PlanGoalFormScreen> createState() => _PlanGoalFormScreenState();
}

class _PlanGoalFormScreenState extends State<PlanGoalFormScreen> {
  GoalType _type = GoalType.distance;
  GoalDistance? _distance = GoalDistance.fiveKilometers;
  final _hours = TextEditingController();
  final _minutes = TextEditingController();
  final _seconds = TextEditingController();
  DateTime? _date;
  Set<int> _days = {};
  final _maxSession = TextEditingController();
  final _weekly = TextEditingController();
  ContinuousRun30 _can30 = ContinuousRun30.unknown;
  double _capHours = PlanGoalFormDefaults.regulatorStartHours;
  bool _hard = TrainingGoal.defaultHardSession(GoalType.distance);
  bool _hardTouched = false;

  /// Stand aus Läufen (Sekunden je Woche); mit Läufen entfällt die Frage.
  double? _runsStand;
  bool _loading = true;
  ReferencePerformance? _reference;
  // Gespeicherte, aber unbrauchbare Referenz (nur Anzeige, K49).
  ReferencePerformance? _unusedReference;

  /// Die Einschätzung samt genau dem Entwurf, der eingeschätzt wurde;
  /// gespeichert wird dieser Entwurf.
  ({TrainingGoal draft, GoalDraftCheck check})? _check;

  /// Zählt Änderungen an den Feldern; eine Einschätzung, während der sich
  /// etwas geändert hat, ist veraltet und wird verworfen.
  int _generation = 0;
  bool _busy = false;
  String? _error;

  /// Das Problem der letzten Prüfung; Felder zeigen ihren Fehler selbst
  /// (E2E API 36: Minuten je Einheit nicht nur über dem Knopf).
  GoalProblem? _problem;

  bool get _editing => widget.initial != null;
  DateTime get _today => calendarDay(widget.clock.now());

  @override
  void initState() {
    super.initState();
    final g = widget.initial;
    if (g != null) {
      _type = g.type;
      _distance = g.distance ?? GoalDistance.fiveKilometers;
      if (g.targetSeconds case final s?) {
        final t = s.round();
        _hours.text = '${t ~/ 3600}';
        _minutes.text = '${t % 3600 ~/ 60}';
        _seconds.text = '${t % 60}';
      }
      _date = g.targetDate;
      _days = {...g.runDays};
      _maxSession.text = _minutesText(g.maxSessionSeconds);
      if (g.currentWeeklySeconds case final w?) {
        _weekly.text = _minutesText(w);
      }
      _can30 = g.canRun30;
      _capHours = g.weeklyCapSeconds / 3600;
      _hard = g.hardSessionEnabled;
      _hardTouched = true;
    }
    for (final c in [_hours, _minutes, _seconds, _maxSession, _weekly]) {
      c.addListener(_changed);
    }
    _load();
  }

  static String _minutesText(double seconds) {
    final m = seconds / 60;
    return m == m.roundToDouble() ? '${m.round()}' : m.toStringAsFixed(1);
  }

  Future<void> _load() async {
    double? stand;
    ReferencePerformance? reference;
    ProfileRecord? profile;
    try {
      stand = await widget.controller.standFromRuns();
    } on Object {
      stand = null; // Ohne lesbare Läufe gilt die Angabe im Formular.
    }
    try {
      reference = await (widget.session as PredictionStorage).prediction
          .activeReference();
    } on Object {
      reference = null;
    }
    final unused = reference == null ? await _unusedReferenceOf() : null;
    if (!_editing) {
      try {
        profile = await widget.session.profile.read();
      } on Object {
        profile = null;
      }
    }
    if (!mounted) return;
    setState(() {
      _runsStand = stand;
      _reference = reference;
      _unusedReference = unused;
      // OQ-0038: Werte aus dem Profil vorausfüllen, für den Plan gilt der
      // Wert am Ziel.
      if (profile != null) {
        final mask = profile.trainingDaysMask;
        if (mask != null) {
          _days = {
            for (var i = 0; i < 7; i++)
              if (mask & (1 << i) != 0) i + 1,
          };
        }
        if (profile.usualTrainingMinutes case final m?) {
          _maxSession.text = '$m';
        }
        if (profile.weeklyRunMinutes case final m?) _weekly.text = '$m';
      }
      _loading = false;
    });
  }

  @override
  void dispose() {
    for (final c in [_hours, _minutes, _seconds, _maxSession, _weekly]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Jede Änderung verwirft die Einschätzung: Gespeichert wird nur, was
  /// vorher eingeschätzt wurde.
  void _changed() => _set(() {});

  void _set(VoidCallback f) => setState(() {
    f();
    _generation++;
    _check = null;
    _error = null;
    _problem = null;
  });

  double? _number(TextEditingController c) {
    final t = c.text.trim().replaceAll(',', '.');
    if (t.isEmpty) return null;
    return double.tryParse(t) ?? double.nan;
  }

  bool get _standFromRuns => _runsStand != null;

  /// Das Ziel aus den Feldern; ein unlesbares Feld wird zu `nan`, damit
  /// [TrainingGoal.validate] es ablehnt.
  TrainingGoal _draft() {
    final type = _type;
    double? target;
    if (type == GoalType.time) {
      final parts = [_hours, _minutes, _seconds].map(_number).toList();
      if (parts.any((p) => p != null)) {
        target =
            (parts[0] ?? 0) * 3600 + (parts[1] ?? 0) * 60 + (parts[2] ?? 0);
      }
    }
    final initial = widget.initial;
    final weekly = _number(_weekly);
    return TrainingGoal(
      type: type,
      distance: type == GoalType.open ? null : _distance,
      targetSeconds: target,
      targetDate: type == GoalType.open ? null : _date,
      runDays: {..._days},
      maxSessionSeconds: (_number(_maxSession) ?? double.nan) * 60,
      weeklyCapSeconds: _capHours * 3600,
      createdAt: initial?.createdAt ?? widget.clock.now(),
      hardSessionEnabled: _hard,
      // Beim Ändern bleibt der Stand des Ziels (PAR-203 nennt ihn nicht; die
      // Rechnung behält Start und Geh-Lauf der letzten Fassung). Beim Anlegen
      // entfällt die Frage mit Läufen (PAR-192).
      currentWeeklySeconds: initial != null
          ? initial.currentWeeklySeconds
          : _standFromRuns
          ? null
          : (weekly == null ? null : weekly * 60),
      canRun30: initial != null
          ? initial.canRun30
          : _standFromRuns
          ? ContinuousRun30.unknown
          : (weekly == null ? _can30 : ContinuousRun30.unknown),
    );
  }

  String _problemText(AppLocalizations l, GoalProblem p) => switch (p) {
    GoalProblem.distanceMissing => l.planFormErrorDistance,
    GoalProblem.targetTimeMissing ||
    GoalProblem.targetTimeInvalid => l.planFormErrorTime,
    GoalProblem.targetDateInPast => l.planFormErrorDatePast,
    GoalProblem.runDaysEmpty ||
    GoalProblem.runDayInvalid ||
    GoalProblem.runDaysTooMany => l.planFormErrorRunDays,
    GoalProblem.maxSessionInvalid => l.planFormErrorMaxSession,
    GoalProblem.currentWeeklyInvalid => l.planFormErrorWeekly,
    GoalProblem.standMissing => l.planFormErrorStand,
    GoalProblem.distanceNotAllowed ||
    GoalProblem.targetTimeNotAllowed ||
    GoalProblem.targetDateNotAllowed ||
    GoalProblem.weeklyCapInvalid => l.planFormErrorInvalid,
  };

  /// Prüft die Angaben (mit heute) und holt die Einschätzung (PAR-206).
  Future<void> _assess() async {
    final l = AppLocalizations.of(context);
    final draft = _draft();
    // Der Stand ist nur beim Anlegen ohne Läufe gefragt (PAR-192).
    final problem = draft.validate(_today, null, !_editing && !_standFromRuns);
    if (problem != null) {
      setState(() {
        _error = _problemText(l, problem);
        _problem = problem;
      });
      return;
    }
    final generation = _generation;
    setState(() => _busy = true);
    GoalDraftCheck? check;
    try {
      check = await widget.controller.checkGoal(draft);
    } on Object {
      check = null;
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      // Während der Rechnung geändert: Das Ergebnis passt nicht mehr zu den
      // Feldern und wird verworfen.
      if (generation != _generation) return;
      _check = check == null ? null : (draft: draft, check: check);
      _error = check == null ? l.planFormAssessFailed : null;
    });
  }

  /// Speichert nach der Einschätzung; vor einem Geh-Lauf-Plan erst nach
  /// Bestätigung des Hinweises aus PAR-115.
  Future<void> _save() async {
    final l = AppLocalizations.of(context);
    final checked = _check;
    if (checked == null) return;
    if (checked.check.walkRun && !await _confirmCare(l)) return;
    if (!mounted) return;
    setState(() => _busy = true);
    final result = await widget.controller.saveGoal(checked.draft);
    if (!mounted) return;
    switch (result) {
      case PlanActionResult.done:
      case PlanActionResult.savedNotPlanned:
        Navigator.of(context).pop(result);
      case PlanActionResult.rejected:
        setState(() {
          _busy = false;
          _error = l.planFormSaveRejected;
        });
      case PlanActionResult.notFound:
      case PlanActionResult.failed:
        setState(() {
          _busy = false;
          _error = l.planFormSaveFailed;
        });
    }
  }

  /// Löst den Fokus vor einem Dialog. Sonst gibt der Navigator beim Schließen
  /// den Fokus an das zuletzt bearbeitete Feld zurück, und die Tastatur geht
  /// auf (E2E API 36).
  void _releaseFocus() => FocusManager.instance.primaryFocus?.unfocus();

  Future<bool> _confirmCare(AppLocalizations l) async {
    _releaseFocus();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('plan_form_care'),
        title: Text(l.planFormCareTitle),
        content: Text(l.planHintWalkRunCare),
        actions: [
          TextButton(
            key: const Key('plan_form_care_cancel'),
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l.planFormCancel),
          ),
          FilledButton(
            key: const Key('plan_form_care_confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l.planFormCareConfirm),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _pickDate() async {
    final t = _today;
    final first = DateTime(t.year, t.month, t.day);
    final current = _date;
    final initial = current == null || calendarDay(current).isBefore(t)
        ? first
        : DateTime(current.year, current.month, current.day);
    _releaseFocus();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: DateTime(t.year + 5, 12, 31),
    );
    if (picked != null && mounted) {
      _set(() => _date = DateTime.utc(picked.year, picked.month, picked.day));
    }
  }

  /// Die jüngste gespeicherte Referenz, wenn keine gilt (nur zur Anzeige).
  Future<ReferencePerformance?> _unusedReferenceOf() async {
    try {
      final all = await (widget.session as PredictionStorage).prediction
          .references();
      return newestReference(all.map((s) => s.reference));
    } on Object {
      return null;
    }
  }

  Future<void> _addReference() async {
    final l = AppLocalizations.of(context);
    _releaseFocus();
    final reference = await showReferenceForm(
      context,
      now: widget.clock.now(),
      formatter: AppSettingsScope.formatterOf(context),
    );
    if (reference == null || !mounted) return;
    final store = (widget.session as PredictionStorage).prediction;
    try {
      await store.addReference(reference);
      final active = await store.activeReference();
      final unused = active == null ? await _unusedReferenceOf() : null;
      if (!mounted) return;
      // Die Referenz geht in die Einschätzung eines Zeitziels ein.
      _set(() {
        _reference = active;
        _unusedReference = unused;
      });
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.planFormReferenceFailed)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              key: const Key('plan_form'),
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    _editing ? l.planFormTitleEdit : l.planFormTitleNew,
                    key: const Key('plan_form_title'),
                    style: RamuriType.of(context).pageTitle,
                  ),
                ),
                const SizedBox(height: 16),
                ..._goalSection(l),
                ..._planSection(l),
                ..._standSection(l),
                ..._referenceSection(l),
                ..._resultSection(l),
              ],
            ),
    );
  }

  List<Widget> _goalSection(AppLocalizations l) {
    final lang = Localizations.localeOf(context).languageCode;
    return [
      SectionHeading(l.planFormType),
      const SizedBox(height: 8),
      RamuriSegmentedToggle<GoalType>(
        key: const Key('plan_form_type'),
        expanded: true,
        segments: [
          RamuriSegment(
            value: GoalType.distance,
            label: l.planFormTypeDistance,
          ),
          RamuriSegment(value: GoalType.time, label: l.planFormTypeTime),
          RamuriSegment(value: GoalType.open, label: l.planFormTypeOpen),
        ],
        selected: _type,
        onChanged: (t) => _set(() {
          _type = t;
          // PAR-198: Standard nur beim Anlegen und solange nicht umgeschaltet.
          if (!_hardTouched) _hard = TrainingGoal.defaultHardSession(t);
        }),
      ),
      if (_type != GoalType.open) ...[
        const SizedBox(height: 16),
        SectionHeading(l.planFormDistance),
        const SizedBox(height: 8),
        RamuriSegmentedToggle<GoalDistance>(
          key: const Key('plan_form_distance'),
          expanded: true,
          segments: [
            for (final d in GoalDistance.values)
              RamuriSegment(value: d, label: planDistanceName(l, d)),
          ],
          selected: _distance ?? GoalDistance.fiveKilometers,
          onChanged: (d) => _set(() => _distance = d),
        ),
      ],
      if (_type == GoalType.time) ...[
        const SizedBox(height: 16),
        SectionHeading(l.planFormTargetTime),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _numberField('plan_form_hours', _hours, l.planFormHours),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _numberField(
                'plan_form_minutes',
                _minutes,
                l.planFormMinutes,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _numberField(
                'plan_form_seconds',
                _seconds,
                l.planFormSeconds,
              ),
            ),
          ],
        ),
        // Fehler am Feld (wie Minuten je Einheit), unter den drei Zeitfeldern.
        if (_problem == GoalProblem.targetTimeMissing ||
            _problem == GoalProblem.targetTimeInvalid)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 12),
            child: Text(
              l.planFormErrorTime,
              key: const Key('plan_form_time_error'),
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
      if (_type != GoalType.open) ...[
        const SizedBox(height: 16),
        SectionHeading(l.planFormDate),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: Text(
                _date == null
                    ? l.planFormDateNone
                    : DateFormat.yMMMd(lang).format(_date!),
                key: const Key('plan_form_date'),
              ),
            ),
            TextButton(
              key: const Key('plan_form_date_pick'),
              onPressed: _pickDate,
              child: Text(l.planFormDatePick),
            ),
            if (_date != null)
              IconButton(
                key: const Key('plan_form_date_clear'),
                tooltip: l.planFormDateClear,
                onPressed: () => _set(() => _date = null),
                icon: const Icon(Icons.close_rounded),
              ),
          ],
        ),
      ],
    ];
  }

  List<Widget> _planSection(AppLocalizations l) {
    final text = Theme.of(context).textTheme;
    final c = RamuriColors.of(context);
    final dayNames = [
      l.weekdayMon,
      l.weekdayTue,
      l.weekdayWed,
      l.weekdayThu,
      l.weekdayFri,
      l.weekdaySat,
      l.weekdaySun,
    ];
    final min = _capHours < PlanGoalFormDefaults.regulatorMinHours
        ? _capHours
        : PlanGoalFormDefaults.regulatorMinHours;
    final max = _capHours > PlanGoalFormDefaults.regulatorMaxHours
        ? _capHours
        : PlanGoalFormDefaults.regulatorMaxHours;
    final lang = Localizations.localeOf(context).languageCode;
    final hours = NumberFormat('0.#', lang).format(_capHours);
    return [
      const SizedBox(height: 16),
      SectionHeading(l.planFormRunDays),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          for (var i = 0; i < 7; i++)
            FilterChip(
              key: Key('plan_form_day_${i + 1}'),
              label: Text(dayNames[i]),
              selected: _days.contains(i + 1),
              onSelected: (on) => _set(() {
                _days = on ? ({..._days, i + 1}) : ({..._days}..remove(i + 1));
              }),
            ),
        ],
      ),
      const SizedBox(height: 16),
      _numberField(
        'plan_form_max_session',
        _maxSession,
        l.planFormMaxSession,
        errorText: _problem == GoalProblem.maxSessionInvalid
            ? l.planFormErrorMaxSession
            : null,
      ),
      const SizedBox(height: 16),
      SectionHeading(l.planFormRegulator),
      Text(
        l.planFormRegulatorValue(hours),
        key: const Key('plan_form_regulator_value'),
        style: text.titleSmall,
      ),
      Slider(
        key: const Key('plan_form_regulator'),
        min: min,
        max: max,
        value: _capHours,
        label: l.planFormRegulatorValue(hours),
        semanticFormatterCallback: (_) => l.planFormRegulatorValue(hours),
        onChanged: (v) => _set(
          () => _capHours =
              (v / PlanGoalFormDefaults.regulatorStepHours).round() *
              PlanGoalFormDefaults.regulatorStepHours,
        ),
      ),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            l.planFormRegulatorRelaxed,
            style: text.bodySmall?.copyWith(color: c.textLabel),
          ),
          Text(
            l.planFormRegulatorDemanding,
            style: text.bodySmall?.copyWith(color: c.textLabel),
          ),
        ],
      ),
      const SizedBox(height: 8),
      SwitchListTile(
        key: const Key('plan_form_hard'),
        contentPadding: EdgeInsets.zero,
        title: Text(l.planFormHard),
        subtitle: Text(l.planFormHardText),
        value: _hard,
        onChanged: (v) => _set(() {
          _hard = v;
          _hardTouched = true;
        }),
      ),
    ];
  }

  List<Widget> _standSection(AppLocalizations l) {
    final text = Theme.of(context).textTheme;
    final runs = _runsStand;
    final initial = widget.initial;
    return [
      const SizedBox(height: 16),
      SectionHeading(l.planFormStand),
      const SizedBox(height: 8),
      // Beim Ändern nur Anzeige: Der Stand bleibt (PAR-203 nennt ihn nicht).
      if (initial != null) ...[
        Text(
          switch ((initial.currentWeeklySeconds, initial.canRun30)) {
            (final w?, _) => l.planFormStandKeptWeekly((w / 60).round()),
            (null, ContinuousRun30.yes) => l.planFormStandKeptYes,
            (null, ContinuousRun30.no) => l.planFormStandKeptNo,
            (null, ContinuousRun30.unknown) => l.planFormStandKeptRuns,
          },
          key: const Key('plan_form_stand_kept'),
          style: text.bodyMedium,
        ),
        Text(
          l.planFormStandKeptNote,
          style: text.bodySmall?.copyWith(
            color: RamuriColors.of(context).textLabel,
          ),
        ),
      ] else if (runs != null)
        Text(
          l.planFormStandFromRuns((runs / 60).round()),
          key: const Key('plan_form_stand_runs'),
          style: text.bodyMedium,
        )
      else ...[
        _numberField(
          'plan_form_weekly',
          _weekly,
          l.planFormWeekly,
          errorText: _problem == GoalProblem.currentWeeklyInvalid
              ? l.planFormErrorWeekly
              : null,
        ),
        if (_weekly.text.trim().isEmpty) ...[
          const SizedBox(height: 12),
          Text(l.planFormCan30, style: text.bodyMedium),
          const SizedBox(height: 8),
          RamuriSegmentedToggle<ContinuousRun30>(
            key: const Key('plan_form_can30'),
            segments: [
              RamuriSegment(value: ContinuousRun30.yes, label: l.planFormYes),
              RamuriSegment(value: ContinuousRun30.no, label: l.planFormNo),
            ],
            selected: _can30,
            onChanged: (v) => _set(() => _can30 = v),
          ),
        ],
      ],
    ];
  }

  List<Widget> _referenceSection(AppLocalizations l) {
    final text = Theme.of(context).textTheme;
    final lang = Localizations.localeOf(context).languageCode;
    final ref = _reference;
    final unused = _unusedReference;
    final unusedProblem = ref == null && unused != null
        ? unused.validate(widget.clock.now(), const PredictionParameters())
        : null;
    final formatter = AppSettingsScope.formatterOf(context);
    return [
      const SizedBox(height: 16),
      SectionHeading(l.planFormReferences),
      const SizedBox(height: 4),
      Text(
        ref == null
            ? (unused != null && unusedProblem != null
                  // Keine Referenz gilt, aber eine ist gespeichert (K49).
                  ? l.planReferenceInvalid(
                      l.predictionReferenceLine(
                        predictionKindText(l, unused.kind),
                        formatter.distance(unused.distanceMeters),
                        clockTimeText(unused.seconds),
                        DateFormat.yMMMd(lang).format(unused.date),
                      ),
                      referenceProblemText(l, unusedProblem, formatter),
                    )
                  : l.planFormReferenceNone)
            : l.planFormReferenceActive(
                formatter.distance(ref.distanceMeters),
                planGoalTimeText(l, ref.seconds),
                DateFormat.yMMMd(lang).format(ref.date),
              ),
        key: const Key('plan_form_reference'),
        style: text.bodyMedium,
      ),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton.icon(
          key: const Key('plan_form_reference_add'),
          onPressed: _addReference,
          icon: const Icon(Icons.add_rounded),
          label: Text(l.planFormReferenceAdd),
        ),
      ),
    ];
  }

  List<Widget> _resultSection(AppLocalizations l) {
    final c = RamuriColors.of(context);
    final text = Theme.of(context).textTheme;
    final lang = Localizations.localeOf(context).languageCode;
    final checked = _check;
    final widgets = <Widget>[const SizedBox(height: 16)];
    if (checked != null) {
      final a = checked.check.assessment;
      final texts = planAssessmentTexts(
        l,
        a,
        (d) => DateFormat.yMMMd(lang).format(d),
      );
      final offer = a.fitsFrom;
      widgets.add(
        RamuriCard(
          key: const Key('plan_form_assessment'),
          tone: RamuriCardTone.accent,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l.planFormAssessment.toUpperCase(),
                style: RamuriType.of(context).eyebrow,
              ),
              const SizedBox(height: 4),
              if (texts == null)
                Text(
                  checked.draft.type == GoalType.open
                      ? l.planFormAssessOpen
                      : l.planFormAssessNoDate,
                  key: const Key('plan_form_assessment_regularity'),
                  style: text.bodyMedium,
                )
              else ...[
                Text(
                  texts.main,
                  key: const Key('plan_form_assessment_main'),
                  style: text.labelLarge?.copyWith(color: c.accent),
                ),
                if (a.regulatorTooLow)
                  Text(
                    l.planAssessRegulator,
                    key: const Key('plan_form_assessment_regulator'),
                    style: text.bodySmall?.copyWith(color: c.textLabel),
                  ),
                if (texts.extra case final e?)
                  Text(e, style: text.bodySmall?.copyWith(color: c.textLabel)),
                Text(
                  texts.basis,
                  key: const Key('plan_form_assessment_basis'),
                  style: text.bodySmall?.copyWith(color: c.textLabel),
                ),
              ],
              // PAR-206: „mit Angebot dieses Datums“.
              if (offer != null && _type != GoalType.open)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton(
                    key: const Key('plan_form_accept_date'),
                    onPressed: _busy
                        ? null
                        : () {
                            _set(() => _date = offer);
                            _assess();
                          },
                    child: Text(
                      l.planFormAcceptDate(
                        DateFormat.yMMMd(lang).format(offer),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
      widgets.add(const SizedBox(height: 12));
    }
    if (_error case final e?) {
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            e,
            key: const Key('plan_form_error'),
            style: text.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.error,
            ),
          ),
        ),
      );
    }
    widgets.add(
      SizedBox(
        width: double.infinity,
        child: checked == null
            ? RamuriPrimaryButton(
                key: const Key('plan_form_check'),
                label: l.planFormCheck,
                onPressed: _busy ? null : _assess,
              )
            : RamuriPrimaryButton(
                key: const Key('plan_form_save'),
                label: l.planFormSave,
                onPressed: _busy ? null : _save,
              ),
      ),
    );
    return widgets;
  }

  Widget _numberField(
    String key,
    TextEditingController c,
    String label, {
    String? errorText,
  }) => TextField(
    key: Key(key),
    controller: c,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
    decoration: InputDecoration(labelText: label, errorText: errorText),
  );
}
