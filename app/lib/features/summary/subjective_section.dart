import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../ui/ui.dart';
import '../run/live_run_view.dart' show formatClock;

/// Wort zur RPE-Stufe (PAR-105).
String rpeWord(AppLocalizations l10n, int rpe) => switch (rpe) {
  0 => l10n.subjectiveRpe0,
  1 => l10n.subjectiveRpe1,
  2 => l10n.subjectiveRpe2,
  3 => l10n.subjectiveRpe3,
  4 => l10n.subjectiveRpe4,
  5 => l10n.subjectiveRpe5,
  6 => l10n.subjectiveRpe6,
  7 => l10n.subjectiveRpe7,
  8 => l10n.subjectiveRpe8,
  9 => l10n.subjectiveRpe9,
  10 => l10n.subjectiveRpe10,
  _ => throw RangeError.range(rpe, rpeMin, rpeMax),
};

/// Wort zur Befindensstufe 1 bis 5.
String wellbeingWord(AppLocalizations l10n, int level) => switch (level) {
  1 => l10n.subjectiveWellbeing1,
  2 => l10n.subjectiveWellbeing2,
  3 => l10n.subjectiveWellbeing3,
  4 => l10n.subjectiveWellbeing4,
  5 => l10n.subjectiveWellbeing5,
  _ => throw RangeError.range(level, wellbeingMin, wellbeingMax),
};

/// Angaben zum Lauf (FR-0038) nach `Summary.dc.html`: Anstrengung 0 bis 10,
/// Befinden in fünf Stufen, Beschwerden mit der Frage nach dem Warnsignal und
/// eine Notiz. Nichts ist vorausgewählt; erneutes Tippen hebt eine Wahl auf.
/// Jede Änderung wird sofort gespeichert, die Texte beim Verlassen des Felds
/// und beim Schließen der Ansicht (auch vor „Fertig“). Mit [showSrpe] steht
/// darunter der sRPE-Wert (FR-0095), getrennt von TRIMP (FR-0096). Inhalte
/// stehen nie in Meldungen oder Logs.
class SubjectiveSection extends StatefulWidget {
  const SubjectiveSection({
    super.key,
    required this.service,
    required this.runId,
    this.showSrpe = false,
    this.onWarning,
  });

  final SubjectiveService service;
  final int runId;
  final bool showSrpe;

  /// Antwort „ja“ auf die Warnfrage: meldet das Warnsignal (FR-0203, WP23);
  /// wird nach dem Speichern der Antwort gerufen. Ohne Wert nur speichern.
  final Future<void> Function(bool yes)? onWarning;

  @override
  State<SubjectiveSection> createState() => _SubjectiveSectionState();
}

class _SubjectiveSectionState extends State<SubjectiveSection> {
  final _complaints = TextEditingController();
  final _note = TextEditingController();
  final _complaintsFocus = FocusNode();
  final _noteFocus = FocusNode();

  bool _loaded = false;

  /// Lesen der gespeicherten Angaben ist gescheitert: Die Felder bleiben
  /// gesperrt, damit nichts Gespeichertes überschrieben wird (fail-closed).
  bool _loadFailed = false;
  bool _failed = false;
  bool _complaintsOpen = false;
  int? _rpe;
  int? _wellbeing;
  WarningAnswer? _warning;
  SrpeLoad? _srpe;

  /// Texte, die noch nicht gespeichert sind.
  bool _complaintsDirty = false;
  bool _noteDirty = false;

  /// Ob die Ansicht oben liegt (nicht von einer Detailansicht verdeckt).
  bool? _wasCurrent;

  /// Speichern der Reihe nach: Die letzte Änderung gewinnt.
  Future<void> _queue = Future.value();

  @override
  void initState() {
    super.initState();
    _complaintsFocus.addListener(_flushOnBlur);
    _noteFocus.addListener(_flushOnBlur);
    unawaited(_load());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Eine Detailansicht über dieser Ansicht kann dieselben Angaben ändern.
    // Beim Verdecken die offenen Texte sichern, beim Zurückkehren neu laden,
    // damit weder ein veralteter Stand angezeigt noch gespeichert wird.
    final current = ModalRoute.of(context)?.isCurrent ?? true;
    final was = _wasCurrent;
    _wasCurrent = current;
    if (was == null || was == current) return;
    if (!current) {
      _saveDirtyTexts();
    } else if (_loaded) {
      unawaited(_reload());
    }
  }

  Future<void> _reload() async {
    await _queue;
    if (!mounted) return;
    await _load();
  }

  Future<void> _load() async {
    try {
      final stored = await widget.service.read(widget.runId);
      if (!mounted) return;
      final s = stored?.subjective;
      setState(() {
        _rpe = s?.rpe;
        _wellbeing = s?.wellbeing;
        _warning = s?.warningAnswer;
        _srpe = stored?.srpe;
        // Ungespeicherte Eingabe im Feld nicht überfahren.
        // Nur bei geändertem Text setzen: Der Setter setzt sonst die Auswahl
        // zurück, und der Cursor im fokussierten Feld ginge verloren.
        if (!_complaintsDirty) _setText(_complaints, s?.complaints ?? '');
        if (!_noteDirty) _setText(_note, s?.note ?? '');
        _complaintsOpen = _complaintsOpen || _complaints.text.isNotEmpty;
        _loaded = true;
        _loadFailed = false;
      });
    } on Object {
      // Keine Inhalte in Meldungen.
      if (!mounted) return;
      setState(() {
        _loaded = true;
        _loadFailed = true;
      });
    }
  }

  static void _setText(TextEditingController c, String text) {
    if (c.text != text) c.text = text;
  }

  Future<void> _retryLoad() {
    setState(() => _loaded = false);
    return _load();
  }

  @override
  void dispose() {
    _complaintsFocus.removeListener(_flushOnBlur);
    _noteFocus.removeListener(_flushOnBlur);
    // Tippen und sofort „Fertig“: Der Text wird mit dem Schließen gespeichert.
    // Ein Fehler dabei lässt sich nicht mehr anzeigen (bekannte Grenze).
    _saveDirtyTexts();
    _complaints.dispose();
    _note.dispose();
    _complaintsFocus.dispose();
    _noteFocus.dispose();
    super.dispose();
  }

  void _flushOnBlur() {
    if (!_complaintsFocus.hasFocus && !_noteFocus.hasFocus) _saveDirtyTexts();
  }

  void _saveDirtyTexts() {
    final fields = <_Field>{
      if (_complaintsDirty) ..._complaintsFields,
      if (_noteDirty) _Field.note,
    };
    if (fields.isNotEmpty && !_loadFailed) unawaited(_save(fields));
  }

  static const _complaintsFields = {_Field.complaints, _Field.warning};

  RunSubjective _current() => RunSubjective(
    rpe: _rpe,
    wellbeing: _wellbeing,
    complaints: _complaints.text,
    // Die Antwort gilt nur mit Beschwerden (das Modell setzt sie sonst zurück).
    warningAnswer: _warning,
    note: _note.text,
  );

  /// Speichert nur die geänderten [fields]: Der gespeicherte Satz wird beim
  /// Schreiben gelesen, die übrigen Felder bleiben, wie sie dort stehen (auch
  /// wenn eine andere Ansicht sie inzwischen geändert hat). Geschrieben wird
  /// der Reihe nach.
  Future<void> _save(Set<_Field> fields) {
    final local = _current();
    if (fields.contains(_Field.complaints)) _complaintsDirty = false;
    if (fields.contains(_Field.note)) _noteDirty = false;
    final service = widget.service;
    final runId = widget.runId;
    final wantSrpe = widget.showSrpe;
    return _queue = _queue.then((_) async {
      try {
        final base =
            (await service.read(runId))?.subjective ?? RunSubjective.empty;
        await service.save(
          runId,
          RunSubjective(
            rpe: fields.contains(_Field.rpe) ? local.rpe : base.rpe,
            wellbeing: fields.contains(_Field.wellbeing)
                ? local.wellbeing
                : base.wellbeing,
            complaints: fields.contains(_Field.complaints)
                ? local.complaints
                : base.complaints,
            warningAnswer: fields.contains(_Field.warning)
                ? local.warningAnswer
                : base.warningAnswer,
            note: fields.contains(_Field.note) ? local.note : base.note,
          ),
        );
        final stored = wantSrpe ? await service.read(runId) : null;
        if (!mounted) return;
        setState(() {
          _failed = false;
          if (wantSrpe) _srpe = stored?.srpe;
        });
      } on Object {
        // Weder Inhalte noch Ausnahmetext weitergeben.
        if (mounted) setState(() => _failed = true);
      }
    });
  }

  void _pickRpe(int n) {
    setState(() => _rpe = _rpe == n ? null : n);
    unawaited(_save({_Field.rpe}));
  }

  void _pickWellbeing(int n) {
    setState(() => _wellbeing = _wellbeing == n ? null : n);
    unawaited(_save({_Field.wellbeing}));
  }

  void _pickWarning(WarningAnswer a) {
    final was = _warning;
    setState(() => _warning = was == a ? null : a);
    final saved = _save({_Field.warning});
    final hook = widget.onWarning;
    final yes = _warning == WarningAnswer.yes;
    // „ja“ meldet, die Rücknahme (nein oder abwählen) hebt ein von diesem
    // Lauf gesetztes Warnsignal wieder auf (Fehltipp).
    if (hook != null && (yes || was == WarningAnswer.yes)) {
      unawaited(
        saved.then((_) async {
          try {
            await hook(yes);
          } on Object {
            // Weder Inhalte noch Ausnahmetext weitergeben.
            if (mounted) setState(() => _failed = true);
          }
        }),
      );
    } else {
      unawaited(saved);
    }
  }

  void _toggleComplaints() {
    setState(() => _complaintsOpen = !_complaintsOpen);
    if (_complaintsOpen) _complaintsFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = RamuriColors.of(context);
    final text = Theme.of(context).textTheme;
    final rpe = _rpe;
    final hasComplaints = _complaints.text.trim().isNotEmpty;
    return RamuriCard(
      radius: 22,
      padding: const EdgeInsets.all(16),
      child: !_loaded
          ? const SizedBox(key: Key('subjective_loading'), height: 48)
          : _loadFailed
          ? _loadFailedBlock(l10n, text, c)
          : Column(
              key: const Key('subjective_section'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        l10n.subjectiveRpeTitle,
                        style: text.titleSmall,
                      ),
                    ),
                    Text(
                      rpe == null
                          ? l10n.subjectiveRpeNone
                          : l10n.subjectiveRpeSelected(rpe, rpeWord(l10n, rpe)),
                      key: const Key('subjective_rpe_label'),
                      style: text.labelLarge?.copyWith(color: c.accent),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (var n = rpeMin; n <= rpeMax; n++)
                      SubjectiveChoice(
                        key: Key('subjective_rpe_$n'),
                        label: '$n',
                        semanticLabel: '$n, ${rpeWord(l10n, n)}',
                        selected: rpe == n,
                        round: false,
                        onTap: () => _pickRpe(n),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Semantics(
                  header: true,
                  child: Text(
                    l10n.subjectiveWellbeingTitle,
                    style: text.titleSmall,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (var n = wellbeingMin; n <= wellbeingMax; n++)
                      SubjectiveChoice(
                        key: Key('subjective_wellbeing_$n'),
                        label: wellbeingWord(l10n, n),
                        selected: _wellbeing == n,
                        onTap: () => _pickWellbeing(n),
                      ),
                    SubjectiveChoice(
                      key: const Key('subjective_complaints_button'),
                      label: l10n.subjectiveComplaintsButton,
                      selected: _complaintsOpen,
                      dashed: !_complaintsOpen,
                      onTap: _toggleComplaints,
                    ),
                  ],
                ),
                if (_complaintsOpen) ...[
                  const SizedBox(height: 12),
                  TextField(
                    key: const Key('subjective_complaints'),
                    controller: _complaints,
                    focusNode: _complaintsFocus,
                    minLines: 2,
                    maxLines: 4,
                    textInputAction: TextInputAction.newline,
                    keyboardType: TextInputType.multiline,
                    decoration: InputDecoration(
                      labelText: l10n.subjectiveComplaintsLabel,
                      hintText: l10n.subjectiveComplaintsHint,
                    ),
                    onChanged: (_) => setState(() => _complaintsDirty = true),
                    onTapOutside: (_) => _complaintsFocus.unfocus(),
                  ),
                  if (hasComplaints) ...[
                    const SizedBox(height: 12),
                    Semantics(
                      header: true,
                      child: Text(
                        l10n.subjectiveWarnQuestion,
                        key: const Key('subjective_warn_question'),
                        style: text.titleSmall,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        SubjectiveChoice(
                          key: const Key('subjective_warn_yes'),
                          label: l10n.subjectiveWarnYes,
                          selected: _warning == WarningAnswer.yes,
                          onTap: () => _pickWarning(WarningAnswer.yes),
                        ),
                        SubjectiveChoice(
                          key: const Key('subjective_warn_no'),
                          label: l10n.subjectiveWarnNo,
                          selected: _warning == WarningAnswer.no,
                          onTap: () => _pickWarning(WarningAnswer.no),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(l10n.subjectiveWarnNote, style: text.bodySmall),
                  ],
                ],
                const SizedBox(height: 16),
                TextField(
                  key: const Key('subjective_note'),
                  controller: _note,
                  focusNode: _noteFocus,
                  minLines: 2,
                  maxLines: 5,
                  keyboardType: TextInputType.multiline,
                  decoration: InputDecoration(
                    labelText: l10n.subjectiveNoteLabel,
                    hintText: l10n.subjectiveNoteHint,
                  ),
                  onChanged: (_) => _noteDirty = true,
                  onTapOutside: (_) => _noteFocus.unfocus(),
                ),
                if (_failed) ...[
                  const SizedBox(height: 8),
                  Text(
                    l10n.subjectiveSaveFailed,
                    key: const Key('subjective_save_failed'),
                    style: text.bodySmall?.copyWith(color: c.danger),
                  ),
                ],
                if (widget.showSrpe) ...[
                  const SizedBox(height: 16),
                  _srpeBlock(context, l10n),
                ],
              ],
            ),
    );
  }

  /// Lesen gescheitert: kein Eingabefeld, nur Hinweis und erneuter Versuch.
  Widget _loadFailedBlock(
    AppLocalizations l10n,
    TextTheme text,
    RamuriColors c,
  ) {
    return Column(
      key: const Key('subjective_load_failed'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.subjectiveLoadFailed,
          style: text.bodyMedium?.copyWith(color: c.danger),
        ),
        const SizedBox(height: 8),
        TextButton(
          key: const Key('subjective_load_retry'),
          style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
          onPressed: _retryLoad,
          child: Text(l10n.subjectiveLoadRetry),
        ),
      ],
    );
  }

  /// sRPE getrennt von TRIMP; ohne RPE kein Wert (nie 0).
  Widget _srpeBlock(BuildContext context, AppLocalizations l10n) {
    final text = Theme.of(context).textTheme;
    final srpe = _srpe;
    return Column(
      key: const Key('subjective_srpe'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(l10n.subjectiveSrpeTitle, style: text.titleSmall),
        ),
        const SizedBox(height: 4),
        if (srpe == null || _rpe == null)
          Text(
            l10n.subjectiveSrpeNone,
            key: const Key('subjective_srpe_none'),
            style: text.bodyMedium,
          )
        else ...[
          Text(
            l10n.subjectiveSrpeValue(srpe.points.round().toString()),
            key: const Key('subjective_srpe_value'),
            style: text.titleMedium,
          ),
          Text(
            l10n.subjectiveSrpeBasis(formatClock(srpe.duration), srpe.rpe),
            key: const Key('subjective_srpe_basis'),
            style: text.bodySmall,
          ),
          Text(l10n.subjectiveSrpeEstimate, style: text.bodySmall),
        ],
      ],
    );
  }
}

enum _Field { rpe, wellbeing, complaints, warning, note }

/// Wahltaste, mindestens 48 dp, als Taste mit Zustand „ausgewählt“.
class SubjectiveChoice extends StatelessWidget {
  const SubjectiveChoice({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.semanticLabel,
    this.round = true,
    this.dashed = false,
  });

  final String label;
  final String? semanticLabel;
  final bool selected;
  final bool round;
  final bool dashed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = RamuriColors.of(context);
    final text = Theme.of(context).textTheme;
    final radius = BorderRadius.circular(round ? 24 : 14);
    return Semantics(
      button: true,
      selected: selected,
      label: semanticLabel ?? label,
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: selected ? c.tint : (dashed ? c.field.withAlpha(0) : c.field),
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(
            color: selected ? c.accent : c.outline,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: 48, minWidth: 48),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: round ? 16 : 0),
              child: Center(
                widthFactor: 1,
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: text.labelLarge?.copyWith(color: c.text),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
