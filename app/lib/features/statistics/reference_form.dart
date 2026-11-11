import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import '../../ui/ui.dart';
import '../settings/unit_format.dart';
import 'prediction_card.dart' show predictionDistanceName;

/// Eingabe einer Referenzleistung (FR-0129): Art Wettkampf oder Test, Distanz
/// (Vorwahl oder frei in der gewählten Einheit), Zeit, Datum. Geprüft wird mit
/// [ReferencePerformance.validate] aus `core`; ein Fehler steht als Text da,
/// nichts wird verschluckt. Gibt die Referenz zurück oder `null` bei Abbruch.
Future<ReferencePerformance?> showReferenceForm(
  BuildContext context, {
  required DateTime now,
  required UnitFormatter formatter,
}) => showDialog<ReferencePerformance>(
  context: context,
  builder: (_) => ReferenceFormDialog(now: now, formatter: formatter),
);

class ReferenceFormDialog extends StatefulWidget {
  const ReferenceFormDialog({
    super.key,
    required this.now,
    required this.formatter,
  });

  final DateTime now;
  final UnitFormatter formatter;

  @override
  State<ReferenceFormDialog> createState() => _ReferenceFormDialogState();
}

class _ReferenceFormDialogState extends State<ReferenceFormDialog> {
  static const _kinds = [ReferenceKind.race, ReferenceKind.test];

  ReferenceKind _kind = ReferenceKind.race;

  /// Vorwahl oder `null` für „Andere“.
  PredictionDistance? _preset = PredictionDistance.fiveKilometers;
  final _distance = TextEditingController();
  final _hours = TextEditingController();
  final _minutes = TextEditingController();
  final _seconds = TextEditingController();
  late DateTime _date = _today;
  String? _error;

  /// Betrifft [_error] die Zeit? Dann steht er direkt unter den Zeitfeldern.
  bool _timeError = false;

  DateTime get _today {
    final l = widget.now.toLocal();
    return DateTime(l.year, l.month, l.day);
  }

  @override
  void dispose() {
    _distance.dispose();
    _minutes.dispose();
    _hours.dispose();
    _seconds.dispose();
    super.dispose();
  }

  int _number(TextEditingController c) => int.tryParse(c.text.trim()) ?? 0;

  /// Distanz in Metern; `null`, wenn die freie Eingabe keine Zahl ist.
  double? _meters() {
    final preset = _preset;
    if (preset != null) return preset.meters;
    final v = double.tryParse(_distance.text.trim().replaceAll(',', '.'));
    if (v == null || !v.isFinite) return null;
    return widget.formatter.unit == DistanceUnit.miles
        ? v * DistanceUnit.metersPerMile
        : v * 1000;
  }

  void _save() {
    final l10n = AppLocalizations.of(context);
    final meters = _meters();
    if (meters == null) {
      setState(() {
        _error = l10n.predictionErrorDistanceMissing;
        _timeError = false;
      });
      return;
    }
    final seconds =
        _number(_hours) * 3600 + _number(_minutes) * 60 + _number(_seconds);
    final reference = ReferencePerformance(
      kind: _kind,
      distanceMeters: meters,
      seconds: seconds.toDouble(),
      date: _date,
      createdAt: widget.now,
    );
    const params = PredictionParameters();
    final problem = reference.validate(widget.now, params);
    if (problem != null) {
      setState(() {
        _timeError =
            problem == ReferenceProblem.nonPositiveTime ||
            problem == ReferenceProblem.paceOutOfRange;
        _error = switch (problem) {
          ReferenceProblem.distanceTooShort =>
            l10n.predictionErrorDistanceShort(
              widget.formatter.distance(params.minimumReferenceMeters),
            ),
          ReferenceProblem.nonPositiveTime => l10n.predictionErrorTime,
          ReferenceProblem.paceOutOfRange => l10n.predictionErrorPace(
            widget.formatter.pace(params.fastestReferencePaceSecondsPerKm),
            widget.formatter.pace(params.slowestReferencePaceSecondsPerKm),
          ),
          ReferenceProblem.dateInFuture => l10n.predictionErrorDate,
        };
      });
      return;
    }
    Navigator.pop(context, reference);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: _today,
    );
    if (picked != null && mounted) {
      setState(() => _date = DateTime(picked.year, picked.month, picked.day));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = RamuriColors.of(context);
    final theme = Theme.of(context).textTheme;
    final lang = Localizations.localeOf(context).languageCode;
    final unitLabel = widget.formatter.distanceLabel;

    String kindLabel(ReferenceKind k) => k == ReferenceKind.race
        ? l10n.predictionKindRace
        : l10n.predictionKindTest;

    Widget label(String text) => Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 6),
      child: Semantics(
        header: true,
        child: Text(
          text,
          style: theme.labelLarge!.copyWith(fontWeight: FontWeight.w800),
        ),
      ),
    );

    Widget timeField(String key, TextEditingController ctrl, String text) =>
        Expanded(
          child: TextField(
            key: Key(key),
            controller: ctrl,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(labelText: text),
          ),
        );

    Widget errorText() => Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Text(
        _error!,
        key: const Key('prediction_form_error'),
        style: theme.bodyMedium!.copyWith(color: c.danger),
      ),
    );

    return AlertDialog(
      key: const Key('prediction_form'),
      title: Text(l10n.predictionFormTitle),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          label(l10n.predictionFormKind),
          Wrap(
            spacing: 8,
            children: [
              for (final k in _kinds)
                RamuriChip(
                  key: Key('prediction_form_kind_${k.name}'),
                  label: kindLabel(k),
                  selected: _kind == k,
                  onPressed: () => setState(() => _kind = k),
                ),
            ],
          ),
          label(l10n.predictionFormDistance),
          Wrap(
            spacing: 8,
            children: [
              for (final d in PredictionDistance.values)
                RamuriChip(
                  key: Key('prediction_form_distance_${d.name}'),
                  label: predictionDistanceName(l10n, d),
                  selected: _preset == d,
                  onPressed: () => setState(() => _preset = d),
                ),
              RamuriChip(
                key: const Key('prediction_form_distance_other'),
                label: l10n.predictionFormDistanceOther,
                selected: _preset == null,
                onPressed: () => setState(() => _preset = null),
              ),
            ],
          ),
          if (_preset == null)
            TextField(
              key: const Key('prediction_form_distance_field'),
              controller: _distance,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: l10n.predictionFormDistanceField(unitLabel),
              ),
            ),
          label(l10n.predictionFormTime),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              timeField(
                'prediction_form_hours',
                _hours,
                l10n.predictionFormHours,
              ),
              const SizedBox(width: 8),
              timeField(
                'prediction_form_minutes',
                _minutes,
                l10n.predictionFormMinutes,
              ),
              const SizedBox(width: 8),
              timeField(
                'prediction_form_seconds',
                _seconds,
                l10n.predictionFormSeconds,
              ),
            ],
          ),
          if (_timeError) errorText(),
          label(l10n.predictionFormDate),
          OutlinedButton(
            key: const Key('prediction_form_date'),
            onPressed: _pickDate,
            child: Text(DateFormat.yMMMd(lang).format(_date)),
          ),
          if (_error != null && !_timeError) errorText(),
        ],
      ),
      actions: [
        TextButton(
          key: const Key('prediction_form_cancel'),
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.predictionCancel),
        ),
        TextButton(
          key: const Key('prediction_form_save'),
          onPressed: _save,
          child: Text(l10n.predictionFormSave),
        ),
      ],
    );
  }
}
