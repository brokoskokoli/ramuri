import 'package:core/core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../ui/ui.dart';
import '../plan/plan_texts.dart';

/// „Aus dem Plan“ (WP24 Teil E): zeigt in der Zusammenfassung, zu welcher
/// Plan-Einheit der Lauf zugeordnet ist (`plan_units.run_id`). Ohne Zuordnung
/// (und ohne ausstehende Wahl), ohne Plan oder bei einem Lesefehler bleibt die Stelle leer. Nur Anzeige.
class PlanOriginNote extends StatefulWidget {
  const PlanOriginNote({
    super.key,
    required this.session,
    required this.runId,
    this.pendingUnit,
  });

  final StorageSession session;
  final int runId;

  /// Die für diesen Lauf gewählte Einheit, solange die Zuordnung noch aussteht
  /// (sie geschieht erst nach dem Schließen des Laufs, `run_starter`). Gilt nur,
  /// wenn in der Datenbank noch keine Einheit dem Lauf zugeordnet ist.
  final PlanUnit? pendingUnit;

  @override
  State<PlanOriginNote> createState() => _PlanOriginNoteState();
}

class _PlanOriginNoteState extends State<PlanOriginNote> {
  late final Future<PlanUnit?> _unit = _find();

  /// Die Zuordnung liegt am Starttag des Laufs; ein Fenster von ±2 Tagen deckt
  /// jede Zeitzone ab, geprüft wird die Lauf-Kennung.
  Future<PlanUnit?> _find() async {
    final session = widget.session;
    if (session is! PlanStorage) return null;
    try {
      final run = await session.runs.get(widget.runId);
      if (run == null) return null;
      final day = warningDay(run.startedAt.toUtc());
      final units = await (session as PlanStorage).plans.unitsBetween(
        day.subtract(const Duration(days: 2)),
        day.add(const Duration(days: 2)),
      );
      for (final u in units) {
        if (u.runId == widget.runId) return u;
      }
    } on Object {
      // Nur die Anzeige fehlt.
    }
    return null;
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<PlanUnit?>(
    future: _unit,
    builder: (context, snap) {
      final unit = snap.data ?? widget.pendingUnit;
      if (unit == null) return const SizedBox.shrink();
      final l10n = AppLocalizations.of(context);
      final text = Theme.of(context).textTheme;
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: RamuriCard(
          key: const Key('sum_from_plan'),
          radius: 18,
          padding: const EdgeInsets.all(14),
          child: Semantics(
            container: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.guidedFromPlan, style: text.labelMedium),
                const SizedBox(height: 2),
                Text(
                  planUnitText(l10n, unit),
                  key: const Key('sum_from_plan_unit'),
                  style: text.titleSmall,
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
