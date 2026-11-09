import 'package:core/core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../ui/ui.dart';
import '../summary/subjective_section.dart' show SubjectiveChoice, rpeWord;

/// Training nachtragen oder ändern (FR-0199): Datum (Standard heute, nie nach
/// heute), Art (Lauf / Sonstiges), Dauer in Minuten und RPE (Pflicht). Nichts
/// ist vorausgewählt außer Datum und Art. Gibt `true` zurück, wenn gespeichert
/// wurde. Inhalte stehen nie in Meldungen oder Logs.
class ManualTrainingScreen extends StatefulWidget {
  const ManualTrainingScreen({
    super.key,
    required this.service,
    required this.today,
    this.existing,
  });

  final SubjectiveService service;

  /// Heutiger Ortstag (`JJJJ-MM-TT`); spätere Tage sind nicht wählbar.
  final String today;
  final StoredManualTraining? existing;

  @override
  State<ManualTrainingScreen> createState() => _ManualTrainingScreenState();
}

class _ManualTrainingScreenState extends State<ManualTrainingScreen> {
  late DateTime _day;
  late ManualTrainingKind _kind;
  int? _rpe;
  final _minutes = TextEditingController();
  bool _submitted = false;
  bool _failed = false;
  bool _saving = false;

  DateTime get _todayDate => DateTime.parse('${widget.today}T00:00:00Z');

  @override
  void initState() {
    super.initState();
    final t = widget.existing?.training;
    _day = t?.day ?? _todayDate;
    _kind = t?.kind ?? ManualTrainingKind.run;
    _rpe = t?.rpe;
    if (t != null) _minutes.text = '${t.duration.inMinutes}';
  }

  @override
  void dispose() {
    _minutes.dispose();
    super.dispose();
  }

  /// Ganze Minuten über 0, sonst `null`.
  int? get _minutesValue {
    final n = int.tryParse(_minutes.text.trim());
    return n != null && n > 0 ? n : null;
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _day.isAfter(_todayDate) ? _todayDate : _day,
      firstDate: DateTime(_todayDate.year - 20),
      lastDate: _todayDate,
    );
    if (picked == null || !mounted) return;
    setState(() => _day = DateTime.utc(picked.year, picked.month, picked.day));
  }

  Future<void> _save() async {
    setState(() => _submitted = true);
    final minutes = _minutesValue;
    final rpe = _rpe;
    if (minutes == null || rpe == null || _saving) return;
    setState(() {
      _saving = true;
      _failed = false;
    });
    try {
      final training = ManualTraining(
        day: _day,
        kind: _kind,
        duration: Duration(minutes: minutes),
        rpe: rpe,
      );
      final existing = widget.existing;
      if (existing == null) {
        await widget.service.addTraining(training);
      } else {
        await widget.service.updateTraining(existing.id, training);
      }
      if (mounted) Navigator.of(context).pop(true);
    } on Object {
      // Weder Inhalte noch Ausnahmetext weitergeben.
      if (mounted) {
        setState(() {
          _saving = false;
          _failed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = RamuriColors.of(context);
    final text = Theme.of(context).textTheme;
    final material = MaterialLocalizations.of(context);
    final rpe = _rpe;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.existing == null ? l10n.manualAddTitle : l10n.manualEditTitle,
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          key: const Key('manual_form'),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: Text(l10n.manualDate, style: text.titleSmall),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: OutlinedButton.icon(
                  key: const Key('manual_date'),
                  onPressed: _pickDate,
                  icon: const Icon(Icons.calendar_today_outlined, size: 20),
                  label: Text(material.formatMediumDate(_day)),
                ),
              ),
              const SizedBox(height: 20),
              Semantics(
                header: true,
                child: Text(l10n.manualKind, style: text.titleSmall),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  SubjectiveChoice(
                    key: const Key('manual_kind_run'),
                    label: l10n.manualKindRun,
                    selected: _kind == ManualTrainingKind.run,
                    onTap: () => setState(() => _kind = ManualTrainingKind.run),
                  ),
                  SubjectiveChoice(
                    key: const Key('manual_kind_other'),
                    label: l10n.manualKindOther,
                    selected: _kind == ManualTrainingKind.other,
                    onTap: () =>
                        setState(() => _kind = ManualTrainingKind.other),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              TextField(
                key: const Key('manual_minutes'),
                controller: _minutes,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: l10n.manualDuration,
                  errorText: _submitted && _minutesValue == null
                      ? l10n.manualDurationError
                      : null,
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 12,
                runSpacing: 2,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Semantics(
                    header: true,
                    child: Text(l10n.manualRpeTitle, style: text.titleSmall),
                  ),
                  Text(
                    rpe == null
                        ? l10n.subjectiveRpeNone
                        : l10n.subjectiveRpeSelected(rpe, rpeWord(l10n, rpe)),
                    key: const Key('manual_rpe_label'),
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
                      key: Key('manual_rpe_$n'),
                      label: '$n',
                      semanticLabel: '$n, ${rpeWord(l10n, n)}',
                      selected: rpe == n,
                      round: false,
                      onTap: () => setState(() => _rpe = rpe == n ? null : n),
                    ),
                ],
              ),
              if (_submitted && rpe == null) ...[
                const SizedBox(height: 8),
                Text(
                  l10n.manualRpeError,
                  key: const Key('manual_rpe_error'),
                  style: text.bodySmall?.copyWith(color: c.danger),
                ),
              ],
              if (_failed) ...[
                const SizedBox(height: 12),
                Text(
                  l10n.manualSaveFailed,
                  key: const Key('manual_save_failed'),
                  style: text.bodySmall?.copyWith(color: c.danger),
                ),
              ],
              const SizedBox(height: 24),
              RamuriPrimaryButton(
                key: const Key('manual_save'),
                label: l10n.manualSave,
                onPressed: _saving ? null : _save,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
