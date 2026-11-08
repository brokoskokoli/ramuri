import 'package:core/core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../export/run_export_action.dart';
import '../map/map_consent_scope.dart';
import '../recalculation/recalculation_controller.dart';
import '../settings/app_settings.dart';
import '../storage/deletion.dart';
import '../summary/run_summary_body.dart';
import 'run_detail_page.dart';

/// Detailansicht eines Laufs (FR-0041, FR-0042, FR-0211) nach `Detail.dc.html`:
/// Lauf laden ([RunSummaryBody]), Inhalt in [RunDetailPage]. Exportieren
/// ([RunExportAction]) und Löschen sind in der Kopfzeile; nach dem Löschen
/// schließt die Ansicht mit `true`.
class RunDetailScreen extends StatelessWidget {
  const RunDetailScreen({
    super.key,
    required this.session,
    required this.clock,
    required this.recalculation,
    required this.runId,
  });

  final StorageSession session;
  final Clock clock;
  final RecalculationController recalculation;
  final int runId;

  Future<void> _delete(BuildContext context) async {
    final navigator = Navigator.of(context);
    final result = await confirmAndDeleteRun(
      context,
      session,
      clock,
      runId,
      serialize: recalculation.exclusive,
      onDeleted: MapConsentScope.of(context)?.deleteRunThumbnails,
    );
    if (result == DeletionResult.deleted ||
        result == DeletionResult.deletedNotErased) {
      navigator.pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final formatter = AppSettingsScope.formatterOf(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.detTitle),
        actions: [
          RunExportAction(session: session, runId: runId),
          IconButton(
            key: const Key('detail_delete'),
            tooltip: l10n.histDeleteRun,
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _delete(context),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: RunSummaryBody(
          key: ValueKey(runId),
          session: session,
          clock: clock,
          runId: runId,
          splitUnitMeters: formatter.unit == DistanceUnit.miles
              ? mileMeters
              : kilometerMeters,
          fallback: () => [Text(l10n.detLoadFailed)],
          contentBuilder: (context, summary, detail, splits) => RunDetailPage(
            summary: summary,
            detail: detail,
            splits: splits,
            formatter: formatter,
            session: session,
            runId: runId,
          ),
        ),
      ),
    );
  }
}
