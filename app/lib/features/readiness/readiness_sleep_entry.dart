import 'package:core/core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../ui/ui.dart';
import '../measure/morning_result_view.dart' show morningSleepLabels;

/// Speichert die Schlafstufe an der Morgenmessung (`null` löscht sie).
typedef ReadinessSleepSave = Future<void> Function(SleepBand? band);

/// Blatt „Schlaf angeben“ von der Detailseite der Erholung (PAR-164K): dieselben
/// Stufen wie in der Morgenmessung; dieselbe Stufe noch einmal wählt ab. Jede
/// Auswahl wird sofort gespeichert. Liefert, ob etwas gespeichert wurde.
Future<bool> showReadinessSleepSheet(
  BuildContext context, {
  required SleepBand? initial,
  required ReadinessSleepSave save,
}) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => ReadinessSleepSheet(initial: initial, save: save),
  );
  return saved ?? false;
}

class ReadinessSleepSheet extends StatefulWidget {
  const ReadinessSleepSheet({
    super.key,
    required this.initial,
    required this.save,
  });

  final SleepBand? initial;
  final ReadinessSleepSave save;

  @override
  State<ReadinessSleepSheet> createState() => _ReadinessSleepSheetState();
}

class _ReadinessSleepSheetState extends State<ReadinessSleepSheet> {
  late SleepBand? _selected = widget.initial;
  bool _saving = false;
  bool _failed = false;
  bool _saved = false;

  Future<void> _tap(SleepBand b) async {
    if (_saving) return;
    final next = _selected == b ? null : b;
    setState(() {
      _saving = true;
      _failed = false;
    });
    try {
      await widget.save(next);
      if (!mounted) return;
      setState(() {
        _selected = next;
        _saved = true;
      });
    } on Object {
      if (!mounted) return;
      setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final c = RamuriColors.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        key: const Key('readiness_sleep_sheet'),
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l.morningSleepTitle, style: theme.textTheme.titleMedium),
            Text(l.morningSleepHint, style: theme.textTheme.bodySmall),
            const SizedBox(height: 12),
            Semantics(
              container: true,
              label: l.morningSleepTitle,
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final b in SleepBand.values)
                    Semantics(
                      inMutuallyExclusiveGroup: true,
                      checked: _selected == b,
                      button: true,
                      excludeSemantics: true,
                      label:
                          '${morningSleepLabels[b.index]} ${l.morningSleepUnit}',
                      onTap: () => _tap(b),
                      child: InkWell(
                        key: Key('readiness_sleep_${b.code}'),
                        borderRadius: BorderRadius.circular(14),
                        onTap: _saving ? null : () => _tap(b),
                        child: Container(
                          constraints: const BoxConstraints(
                            minHeight: RamuriTheme.minTarget,
                            minWidth: RamuriTheme.minTarget + 16,
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            color: _selected == b ? c.tint : null,
                            border: Border.all(
                              color: _selected == b ? c.accent : c.outline,
                            ),
                          ),
                          child: Text(
                            morningSleepLabels[b.index],
                            style: theme.textTheme.labelMedium,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(l.morningSleepUnit, style: theme.textTheme.labelSmall),
            if (_failed) ...[
              const SizedBox(height: 6),
              Text(
                l.morningSleepFailed,
                key: const Key('readiness_sleep_failed'),
                style: theme.textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                key: const Key('readiness_sleep_done'),
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, RamuriTheme.minTarget),
                ),
                onPressed: () => Navigator.of(context).pop(_saved),
                child: Text(l.readinessSleepSheetDone),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
