import 'package:core/core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../plan/plan_texts.dart';
import 'plan_origin_note.dart';

/// Beginn eines Laufs in der Ortszeit zum Laufende (Versatz des Laufs), sonst
/// in der Ortszeit des Geräts – wie in der Historie.
DateTime runLocalStart(StoredRun run) {
  final offset = run.endedUtcOffset;
  return offset == null
      ? run.startedAt.toLocal()
      : run.startedAt.toUtc().add(offset);
}

/// Kopf der Zusammenfassung nach dem Lauf (Design `Summary.dc.html`, FR-0037):
/// „Datum · Uhrzeit“ des Starts und, wenn der Lauf zu einer Einheit des Plans
/// gehört, deren Art. Überschrift der Seite für Bedienungshilfen.
class RunSummaryHeader extends StatefulWidget {
  const RunSummaryHeader({
    super.key,
    required this.run,
    required this.session,
    this.pendingUnit,
  });

  final StoredRun run;
  final StorageSession session;

  /// Gewählte Einheit, deren Zuordnung noch aussteht (wie [PlanOriginNote]).
  final PlanUnit? pendingUnit;

  @override
  State<RunSummaryHeader> createState() => _RunSummaryHeaderState();
}

class _RunSummaryHeaderState extends State<RunSummaryHeader> {
  late final Future<PlanUnit?> _unit = planUnitOfRun(
    widget.session,
    widget.run.id,
  );

  @override
  Widget build(BuildContext context) => FutureBuilder<PlanUnit?>(
    future: _unit,
    builder: (context, snap) {
      final l10n = AppLocalizations.of(context);
      final material = MaterialLocalizations.of(context);
      final start = runLocalStart(widget.run);
      final unit = snap.data ?? widget.pendingUnit;
      final parts = [
        material.formatMediumDate(start),
        material.formatTimeOfDay(TimeOfDay.fromDateTime(start)),
        if (unit != null) planKindName(l10n, unit.kind),
      ];
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Semantics(
          header: true,
          child: Text(
            parts.join(' · '),
            key: const Key('sum_header'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
      );
    },
  );
}
