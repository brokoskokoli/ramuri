import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import '../../ui/ui.dart';
import '../../ui/format/unit_format.dart';
import 'prediction_card.dart' show clockTimeText;

/// Liest die beendeten Läufe (Lauf-Übersicht mit Distanz und Bewegungszeit).
typedef ReferenceRunLoader = Future<List<PredictionRun>> Function();

/// Lader für „Aus einem Lauf übernehmen“ (FR-0129) aus der Lauf-Übersicht
/// (Distanz, Bewegungszeit, RPE); Tempowerte braucht die Liste nicht. Der
/// Aufrufer liest [offload] vor dem ersten `await` (`OffloadScope.of`).
ReferenceRunLoader storedReferenceRuns({
  required StorageSession session,
  required Clock clock,
  required Offload offload,
}) =>
    () => PredictionRunReader(
      session: session,
      clock: clock,
      offload: offload,
    ).load(withPaceSamples: false);

/// Wahl eines gespeicherten Laufs als Referenz (FR-0129): beendete Läufe ab
/// 3 km der letzten 12 Wochen ([referenceRunChoices]), neueste zuerst, je
/// Zeile Datum, Distanz, Zeit, Tempo und Anstrengung (falls angegeben).
///
/// Ist der gewählte Lauf nicht als hart angegeben (RPE unter 8 oder keine
/// Angabe, [isHardEnoughForReference]), fragt die App vor dem Übernehmen nach
/// (FR-0131). Gibt den Lauf zurück oder `null` bei Abbruch.
Future<PredictionRun?> showReferenceRunPicker(
  BuildContext context, {
  required DateTime now,
  required UnitFormatter formatter,
  required ReferenceRunLoader loadRuns,
  PredictionParameters parameters = const PredictionParameters(),
}) => showDialog<PredictionRun>(
  context: context,
  builder: (_) => ReferenceRunPickerDialog(
    now: now,
    formatter: formatter,
    loadRuns: loadRuns,
    parameters: parameters,
  ),
);

class ReferenceRunPickerDialog extends StatefulWidget {
  const ReferenceRunPickerDialog({
    super.key,
    required this.now,
    required this.formatter,
    required this.loadRuns,
    this.parameters = const PredictionParameters(),
  });

  final DateTime now;
  final UnitFormatter formatter;
  final ReferenceRunLoader loadRuns;
  final PredictionParameters parameters;

  @override
  State<ReferenceRunPickerDialog> createState() =>
      _ReferenceRunPickerDialogState();
}

class _ReferenceRunPickerDialogState extends State<ReferenceRunPickerDialog> {
  late final Future<List<PredictionRun>> _runs = _load();

  Future<List<PredictionRun>> _load() async => referenceRunChoices(
    runs: await widget.loadRuns(),
    now: widget.now,
    parameters: widget.parameters,
  );

  Future<void> _choose(PredictionRun run) async {
    if (!isHardEnoughForReference(run, widget.parameters)) {
      final sure = await showDialog<bool>(
        context: context,
        builder: (context) {
          final l10n = AppLocalizations.of(context);
          return AlertDialog(
            key: const Key('reference_run_loose'),
            title: Text(l10n.referenceLooseTitle),
            scrollable: true,
            content: Text(l10n.referenceLooseBody),
            actions: [
              TextButton(
                key: const Key('reference_run_loose_cancel'),
                onPressed: () => Navigator.pop(context, false),
                child: Text(l10n.predictionCancel),
              ),
              TextButton(
                key: const Key('reference_run_loose_confirm'),
                onPressed: () => Navigator.pop(context, true),
                child: Text(l10n.referenceLooseConfirm),
              ),
            ],
          );
        },
      );
      if (sure != true || !mounted) return;
    }
    Navigator.pop(context, run);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = RamuriColors.of(context);
    final theme = Theme.of(context).textTheme;
    final lang = Localizations.localeOf(context).languageCode;
    final f = widget.formatter;
    final minimum = f.distance(widget.parameters.suggestionMinimumMeters);
    final weeks = widget.parameters.runPickerWindowDays ~/ 7;

    Widget row(int index, PredictionRun run) {
      final meters = run.distanceMeters!;
      final rpe = run.rpe;
      return InkWell(
        key: Key('reference_run_$index'),
        onTap: () => _choose(run),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: RamuriTheme.minTarget),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  DateFormat.yMMMd(lang).format(run.date),
                  style: theme.labelLarge!.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  l10n.referenceRunRow(
                    f.distance(meters),
                    clockTimeText(run.movingSeconds),
                    f.pace(run.movingSeconds / (meters / 1000)),
                  ),
                  key: Key('reference_run_${index}_text'),
                  style: theme.bodyMedium,
                ),
                Text(
                  rpe == null
                      ? l10n.referenceRunRpeNone
                      : l10n.referenceRunRpe(rpe),
                  key: Key('reference_run_${index}_rpe'),
                  style: theme.bodySmall!.copyWith(color: c.textMuted),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return AlertDialog(
      key: const Key('reference_run_picker'),
      title: Text(l10n.referenceRunPickerTitle),
      scrollable: true,
      content: FutureBuilder<List<PredictionRun>>(
        future: _runs,
        builder: (context, snap) {
          if (snap.hasError) {
            // Nie den Inhalt des Fehlers zeigen (Gesundheitsdaten).
            return Text(
              l10n.referenceRunPickerFailed,
              key: const Key('reference_run_failed'),
              style: theme.bodyMedium!.copyWith(color: c.danger),
            );
          }
          final runs = snap.data;
          if (runs == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (runs.isEmpty) {
            return Text(
              l10n.referenceRunPickerEmpty(minimum, weeks),
              key: const Key('reference_run_empty'),
              style: theme.bodyMedium,
            );
          }
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.referenceRunPickerScope(minimum, weeks),
                style: theme.bodySmall!.copyWith(color: c.textMuted),
              ),
              for (var i = 0; i < runs.length; i++) row(i, runs[i]),
            ],
          );
        },
      ),
      actions: [
        TextButton(
          key: const Key('reference_run_cancel'),
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.predictionCancel),
        ),
      ],
    );
  }
}
