import 'package:core/core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../ui/ui.dart';
import '../export/run_export_action.dart';
import '../settings/unit_format.dart';
import '../summary/kilometer_table.dart';
import '../summary/run_charts.dart';
import '../summary/run_summary_body.dart' show clockText;
import '../summary/run_summary_page.dart';
import '../transparency/value_explanation_screen.dart';

/// Inhalt der Detailansicht eines Laufs nach dem Screen `Detail.dc.html`
/// (FR-0041, FR-0042, FR-0211): Route mit Umschalter und Kilometermarken,
/// Strecke und Zeiten, Pace und Puls in einem Diagramm, Höhenprofil mit
/// Anstieg und Gefälle, Kilometertabelle, danach die Kacheln, Zonen, Belastung,
/// Einordnung, VO₂max, Runden, Hinweise und Quellen wie in der Zusammenfassung
/// ([RunSummaryPage]). Nicht Verfügbares steht als „nicht verfügbar“ oder „–“,
/// nie als 0. Die Ansicht ändert keine Daten; Exportieren ist der Knopf am Ende, Löschen
/// sitzt in der Kopfzeile des Screens.
class RunDetailPage extends StatelessWidget {
  const RunDetailPage({
    super.key,
    required this.summary,
    required this.detail,
    required this.splits,
    required this.formatter,
    required this.session,
    required this.runId,
  });

  final RunSummary summary;
  final RunDetailData detail;

  /// Kilometerwerte in der Einheit der Einstellungen; `null`, wenn sie fehlen.
  final KilometerSplits? splits;
  final UnitFormatter formatter;
  final StorageSession session;
  final int runId;

  /// Beginn in der Ortszeit zum Laufende (Versatz des Laufs), sonst in der
  /// Ortszeit des Geräts.
  DateTime get _start {
    final run = summary.run;
    final offset = run.endedUtcOffset;
    return offset == null
        ? run.startedAt.toLocal()
        : run.startedAt.toUtc().add(offset);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final material = MaterialLocalizations.of(context);
    final start = _start;
    // Die Zusammenfassung liefert die gemeinsamen Abschnitte.
    final base = RunSummaryPage(
      summary: summary,
      detail: detail,
      formatter: formatter,
      session: session,
      runId: runId,
    );
    const gap = SizedBox(height: 16);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.detailStarted(
            '${material.formatMediumDate(start)}, '
            '${material.formatTimeOfDay(TimeOfDay.fromDateTime(start))}',
          ),
          key: const Key('detail_started'),
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 8),
        _route(context, l10n),
        gap,
        _card(
          SectionHeading(l10n.detailPaceHeart),
          RunPaceHeartChart(data: detail, formatter: formatter),
        ),
        gap,
        _altitude(context, l10n),
        gap,
        _splits(l10n),
        gap,
        RamuriTileGrid(children: base.tiles(l10n)),
        base.explain(context, 'sum_explain_trimp', trimpRunValueKey),
        gap,
        base.zones(context, l10n),
        gap,
        base.compare(context, l10n),
        gap,
        base.laps(context, l10n),
        base.notes(context, l10n),
        base.explain(
          context,
          'sum_explain_sources',
          runSourcesKey,
          label: l10n.explSourcesButton,
        ),
        gap,
        RunExportAction(session: session, runId: runId),
      ],
    );
  }

  Widget _card(Widget heading, Widget body) => RamuriCard(
    radius: 22,
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [heading, const SizedBox(height: 10), body],
    ),
  );

  /// Route (Karte oder Zeichnung, mit Kilometermarken) und darunter Strecke und
  /// die beiden Zeiten.
  Widget _route(BuildContext context, AppLocalizations l10n) {
    final f = summary.figures;
    final type = RamuriType.of(context);
    final text = Theme.of(context).textTheme;
    Widget stat(String id, String label, String value) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: text.labelMedium),
        Text(value, key: Key(id), style: type.valueSmall),
      ],
    );
    return RamuriCard(
      radius: 24,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RunRouteSection(
            route: detail.route,
            marks: splits?.marks ?? const [],
            markUnitLabel: formatter.distanceLabel,
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 24,
            runSpacing: 8,
            children: [
              stat(
                'run_distance',
                l10n.runDistance,
                f.distanceMeters == null
                    ? l10n.runUnavailable
                    : formatter.distance(f.distanceMeters),
              ),
              stat(
                'run_moving_time',
                l10n.runMovingTime,
                clockText(l10n, f.movingTime),
              ),
              stat('run_time', l10n.sumTotalTime, clockText(l10n, f.totalTime)),
            ],
          ),
        ],
      ),
    );
  }

  /// Höhenprofil mit Anstieg und Gefälle in der Kopfzeile.
  Widget _altitude(BuildContext context, AppLocalizations l10n) {
    final text = Theme.of(context).textTheme;
    final up = summary.ascentMeters;
    final down = summary.descentMeters;
    return _card(
      Wrap(
        spacing: 14,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Semantics(
            header: true,
            child: Text(l10n.summaryElevation, style: text.titleSmall),
          ),
          if (up != null && down != null)
            Semantics(
              container: true,
              label: l10n.detailElevationSummary(
                formatter.elevation(up),
                formatter.elevation(down),
              ),
              excludeSemantics: true,
              child: Wrap(
                spacing: 12,
                children: [
                  Text(
                    '+${formatter.elevation(up)}',
                    key: const Key('detail_ascent'),
                    style: text.titleSmall,
                  ),
                  Text(
                    '−${formatter.elevation(down)}',
                    key: const Key('detail_descent'),
                    style: text.titleSmall,
                  ),
                ],
              ),
            ),
        ],
      ),
      RunAltitudeChart(data: detail, formatter: formatter),
    );
  }

  Widget _splits(AppLocalizations l10n) {
    final s = splits;
    return _card(
      SectionHeading(
        formatter.unit == DistanceUnit.miles
            ? l10n.detailSplitsMi
            : l10n.detailSplitsKm,
      ),
      s == null
          ? Text(l10n.detailSplitsNone, key: const Key('detail_km_none'))
          : KilometerTable(splits: s, formatter: formatter),
    );
  }
}
