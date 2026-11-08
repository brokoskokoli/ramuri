import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import '../../offload_scope.dart';
import '../../ui/ui.dart';
import '../map/map_consent_controller.dart';
import '../map/map_consent_scope.dart';
import '../map/miniature_service.dart';
import '../recalculation/recalculation_controller.dart';
import '../run/live_run_view.dart' show formatClock;
import '../settings/app_settings.dart';
import '../settings/unit_format.dart';
import '../storage/deletion.dart';
import 'history_view_state.dart';
import 'run_detail_screen.dart';
import 'run_miniature.dart';

/// Verlauf (FR-0040, FR-0212, ACC-04): Zeitraum Woche/Monat/Jahr/Alle mit den
/// Summen der Statistik, darunter die Läufe des Zeitraums nach Wochen gruppiert,
/// je Lauf mit Miniatur, Strecke, Dauer, Pace und, soweit vorhanden, Puls.
/// Fehlendes steht als „nicht verfügbar“, nie als 0. Gelesen wird in einer
/// gebündelten Abfrage ([RunOverviewService]), gerechnet wird nichts neu
/// ([historyTotals], [groupByWeek]). Löschen hängt an jedem Eintrag
/// ([confirmAndDeleteRun]).
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({
    super.key,
    required this.session,
    required this.clock,
    required this.recalculation,
    this.viewState,
  });

  final StorageSession session;
  final Clock clock;
  final RecalculationController recalculation;

  /// Zeitraum, der Neuaufbauten (Tab-Wechsel) überlebt; ohne Angabe legt die
  /// Seite ein eigenes Objekt an. Die Daten lädt sie in jedem Fall neu.
  final HistoryViewState? viewState;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _Data {
  _Data(this.overviews) : figures = [for (final o in overviews) o.toFigures()];
  final List<RunOverview> overviews;

  /// Einmal gebildet, nicht je Build.
  final List<RunFigures> figures;
}

class _HistoryScreenState extends State<HistoryScreen> {
  late Future<_Data> _future = _load();
  late final HistoryViewState _view = widget.viewState ?? HistoryViewState();

  /// Erzeugt die Kartenbilder der Miniaturen; je Aufbau des Verlaufs eine Instanz (ein gescheiterter Versuch wird
  /// erst beim nächsten Aufbau wiederholt). `null` ohne verdrahteten Kartenanbieter.
  MiniatureService? _miniatures;
  MapConsentController? _consent;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final consent = MapConsentScope.of(context);
    final current = ModalRoute.of(context)?.isCurrent ?? true;
    if (!identical(consent, _consent)) {
      _miniatures?.dispose();
      _consent = consent;
      _miniatures = consent == null ? null : MiniatureService(consent: consent);
    }
    // Verdeckte Route (etwa das Detail eines Laufs darüber): keine Aufnahme, nichts Veraltetes speichern (S6).
    _miniatures?.routeCurrent = current;
  }

  @override
  void dispose() {
    _miniatures?.dispose();
    super.dispose();
  }

  Future<_Data> _load() async => _Data(
    await RunOverviewService(
      session: widget.session,
      clock: widget.clock,
      offload: OffloadScope.of(context),
    ).load(),
  );

  void _reload() {
    setState(() {
      _future = _load();
    });
  }

  /// Heutiger Ortstag nach dem Versatz der Uhr (wie in der Statistik).
  String get _today {
    final now = widget.clock.now().toUtc();
    return isoDay(now.add(widget.clock.utcOffsetAt(now)));
  }

  Future<void> _delete(int runId) async {
    final result = await confirmAndDeleteRun(
      context,
      widget.session,
      widget.clock,
      runId,
      serialize: widget.recalculation.exclusive,
      onDeleted: _consent?.deleteRunThumbnails,
    );
    if (!mounted) return;
    if (result == DeletionResult.deleted ||
        result == DeletionResult.deletedNotErased) {
      _reload();
    }
  }

  Future<void> _open(int runId) async {
    final deleted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => RunDetailScreen(
          session: widget.session,
          clock: widget.clock,
          recalculation: widget.recalculation,
          runId: runId,
        ),
      ),
    );
    if (mounted && deleted == true) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final formatter = AppSettingsScope.formatterOf(context);
    // Ohne AppBar wie im Design; der Titel steht in der Liste (Verlauf.dc).
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(child: _body(l10n, formatter)),
                  if (_miniatures != null) MiniatureHost(service: _miniatures!),
                ],
              ),
            ),
            if (_miniatures != null) _AttributionFooter(service: _miniatures!),
          ],
        ),
      ),
    );
  }

  static const EdgeInsets _pagePadding = EdgeInsets.fromLTRB(20, 28, 20, 16);

  Widget _title(AppLocalizations l10n) => Semantics(
    header: true,
    child: Text(
      l10n.histTitle,
      key: const Key('history_title'),
      style: RamuriType.of(context).pageTitle,
    ),
  );

  Widget _body(AppLocalizations l10n, UnitFormatter formatter) {
    return FutureBuilder<_Data>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(l10n.histLoadFailed, key: const Key('history_failed')),
                TextButton(
                  key: const Key('history_retry'),
                  onPressed: _reload,
                  child: Text(l10n.notOpenableRetry),
                ),
              ],
            ),
          );
        }
        final data = snapshot.data;
        if (data == null) {
          return const Center(child: CircularProgressIndicator());
        }
        if (data.overviews.isEmpty) {
          return Padding(
            padding: _pagePadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _title(l10n),
                Expanded(
                  child: Center(
                    child: Text(
                      l10n.histEmpty,
                      key: const Key('history_empty'),
                    ),
                  ),
                ),
              ],
            ),
          );
        }
        return _list(l10n, formatter, data);
      },
    );
  }

  Widget _list(AppLocalizations l10n, UnitFormatter formatter, _Data data) {
    final range = _view.range;
    final today = _today;
    final totals = historyTotals(range, today, data.figures);
    final period = totals.period;
    final inRange = [
      for (final o in data.overviews)
        if (period.contains(id: o.run.id, day: dayOfRun(o.run))) o,
    ];
    final groups = groupByWeek<RunOverview>(
      inRange,
      today,
      dayOf: (o) => dayOfRun(o.run),
      endedAtOf: (o) => o.run.endedAt!,
    );
    final rows = <Widget Function(BuildContext)>[
      (_) => _title(l10n),
      (_) => const SizedBox(height: 14),
      (_) => RamuriSegmentedToggle<HistoryRange>(
        key: const Key('history_range'),
        expanded: true,
        style: RamuriSegmentedStyle.soft,
        semanticLabel: l10n.histRangeLabel,
        selected: range,
        onChanged: (r) => setState(() => _view.range = r),
        segments: [
          RamuriSegment(value: HistoryRange.week, label: l10n.statKindWeek),
          RamuriSegment(value: HistoryRange.month, label: l10n.statKindMonth),
          RamuriSegment(value: HistoryRange.year, label: l10n.histRangeYear),
          RamuriSegment(value: HistoryRange.all, label: l10n.histRangeAll),
        ],
      ),
      (_) => const SizedBox(height: 14),
      if (totals.runCount == 0)
        (_) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 32),
          child: Column(
            children: [
              Text(
                l10n.histEmptyRange,
                key: const Key('history_empty_range'),
                textAlign: TextAlign.center,
              ),
              // Läufe in anderen Zeiträumen (z. B. nach einem Archiv-Import):
              // ein Tipp führt zu „Alle“, der Umschalter bleibt stehen.
              if (data.overviews.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(l10n.histEmptyOtherRuns, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                RamuriSecondaryButton(
                  key: const Key('history_show_all'),
                  label: l10n.histEmptyShowAll,
                  onPressed: () =>
                      setState(() => _view.range = HistoryRange.all),
                ),
              ],
            ],
          ),
        )
      else ...[
        (_) => _TotalsPanel(totals: totals, formatter: formatter),
        for (final g in groups) ...[
          (_) => Padding(
            padding: const EdgeInsets.only(top: 18, bottom: 8),
            child: SectionHeading(_weekTitle(l10n, g, today), eyebrow: true),
          ),
          for (final o in g.items)
            (_) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _RunTile(
                key: ValueKey(o.run.id),
                overview: o,
                formatter: formatter,
                session: widget.session,
                miniatures: _miniatures,
                onDelete: _delete,
                onOpen: _open,
              ),
            ),
        ],
      ],
    ];
    return ListView.builder(
      // Je Zeitraum eine eigene Position: ein Wechsel beginnt oben, die Rückkehr
      // aus einem anderen Tab findet die Stelle wieder (PageStorage der Route).
      key: PageStorageKey<String>('history_list_${range.name}'),
      padding: _pagePadding,
      itemCount: rows.length,
      itemBuilder: (context, i) => rows[i](context),
    );
  }

  /// „Diese Woche“, „Letzte Woche“, sonst Anfang und Ende der Woche; das Jahr
  /// steht nur, wenn die Woche nicht im Jahr von heute beginnt.
  String _weekTitle(
    AppLocalizations l10n,
    WeekGroup<RunOverview> g,
    String today,
  ) {
    switch (g.kind) {
      case WeekGroupKind.thisWeek:
        return l10n.histThisWeek;
      case WeekGroupKind.lastWeek:
        return l10n.histLastWeek;
      case WeekGroupKind.dated:
        final lang = Localizations.localeOf(context).languageCode;
        final from = DateTime.parse('${g.week.firstDay}T00:00:00Z');
        final to = DateTime.parse('${g.week.lastDay}T00:00:00Z');
        final sameYear =
            g.week.firstDay!.substring(0, 4) == today.substring(0, 4);
        final f = sameYear ? DateFormat.MMMd(lang) : DateFormat.yMMMd(lang);
        return l10n.histWeekRange(f.format(from), f.format(to));
    }
  }
}

/// Summen über der Liste (Läufe, Strecke, Zeit) auf dem dunklen Feld; nur
/// Anzeige der Werte aus [HistoryTotals]. Fehlt die Strecke oder Zeit aller
/// Läufe, steht „nicht verfügbar“, nie 0.
class _TotalsPanel extends StatelessWidget {
  const _TotalsPanel({required this.totals, required this.formatter});

  final HistoryTotals totals;
  final UnitFormatter formatter;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final distance = totals.distanceMeters;
    final time = totals.totalTime;
    return RamuriCard(
      tone: RamuriCardTone.panel,
      child: Builder(
        builder: (context) => Wrap(
          spacing: 20,
          runSpacing: 10,
          children: [
            _TotalsItem(
              valueKey: const Key('history_total_runs'),
              label: l10n.statRuns,
              value: '${totals.runCount}',
            ),
            _TotalsItem(
              valueKey: const Key('history_total_distance'),
              label: l10n.runDistance,
              value: distance == null
                  ? l10n.runUnavailable
                  : formatter.distance(distance),
              isText: distance == null,
            ),
            _TotalsItem(
              valueKey: const Key('history_total_time'),
              label: l10n.runTime,
              value: time == null ? l10n.runUnavailable : formatClock(time),
              isText: time == null,
            ),
          ],
        ),
      ),
    );
  }
}

class _TotalsItem extends StatelessWidget {
  const _TotalsItem({
    required this.valueKey,
    required this.label,
    required this.value,
    this.isText = false,
  });

  final Key valueKey;
  final String label;
  final String value;

  /// Ein Satz („nicht verfügbar“) statt einer Zahl: in der Schrift des Fließtexts.
  final bool isText;

  @override
  Widget build(BuildContext context) {
    final c = RamuriColors.of(context);
    final type = RamuriType.of(context);
    final text = Theme.of(context).textTheme;
    // Die Einheit ("km", "mi") bleibt in kleiner Schrift an der Zahl.
    final cut = isText ? -1 : value.lastIndexOf(' ');
    return Semantics(
      container: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: text.labelSmall?.copyWith(color: c.onPanelMuted)),
          Text.rich(
            key: valueKey,
            TextSpan(
              children: [
                TextSpan(
                  text: cut < 0 ? value : value.substring(0, cut),
                  style: isText
                      ? text.titleSmall?.copyWith(color: c.onPanel)
                      : type.value.copyWith(color: c.onPanel),
                ),
                if (cut >= 0)
                  TextSpan(
                    text: ' ${value.substring(cut + 1)}',
                    style: type.unit.copyWith(color: c.onPanelMuted),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RunTile extends StatelessWidget {
  const _RunTile({
    super.key,
    required this.overview,
    required this.formatter,
    required this.session,
    required this.miniatures,
    required this.onDelete,
    required this.onOpen,
  });

  final RunOverview overview;
  final UnitFormatter formatter;
  final StorageSession session;
  final MiniatureService? miniatures;
  final Future<void> Function(int runId) onDelete;
  final Future<void> Function(int runId) onOpen;

  /// Beginn in der Ortszeit zum Laufende (Versatz des Laufs), sonst in der
  /// Ortszeit des Geräts.
  DateTime get _start {
    final run = overview.run;
    final offset = run.endedUtcOffset;
    return offset == null
        ? run.startedAt.toLocal()
        : run.startedAt.toUtc().add(offset);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final material = MaterialLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final id = overview.run.id;
    final start = _start;
    final pace = overview.averagePaceSecondsPerKm;
    final bpm = overview.averageHeartRateBpm;
    final time = overview.totalTime;
    final miniature = RunMiniature(
      key: Key('history_miniature_$id'),
      session: session,
      runId: id,
      service: miniatures,
    );
    final delete = IconButton(
      key: Key('history_delete_$id'),
      tooltip: l10n.histDeleteRun,
      icon: const Icon(Icons.delete_outline),
      onPressed: () => onDelete(id),
    );
    final texts = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${material.formatMediumDate(start)}, '
          '${material.formatTimeOfDay(TimeOfDay.fromDateTime(start))}',
          key: Key('history_date_$id'),
          style: text.titleSmall,
        ),
        const SizedBox(height: 3),
        Wrap(
          spacing: 10,
          children: [
            Text(
              overview.distanceMeters == null
                  ? l10n.runUnavailable
                  : formatter.distance(overview.distanceMeters),
              key: Key('history_distance_$id'),
              style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            Text(
              time == null ? l10n.runUnavailable : formatClock(time),
              key: Key('history_time_$id'),
              style: text.bodyMedium,
            ),
            Text(
              pace == null
                  ? l10n.runUnavailable
                  : unbreakableUnit(formatter.pace(pace)),
              key: Key('history_pace_$id'),
              style: text.bodyMedium,
            ),
          ],
        ),
        if (overview.readFailed)
          Text(
            l10n.histRowReadFailed,
            key: Key('history_failed_$id'),
            style: text.bodySmall,
          ),
        Text(
          bpm == null
              ? l10n.histRowNoHeartRate
              : l10n.histRowHeartRate(bpm.round()),
          key: Key('history_hr_$id'),
          style: text.bodySmall,
        ),
      ],
    );
    // Große Schrift: Bild und Löschen stehen über dem Text, der so die ganze
    // Breite hat (die Miniatur ist 120 dp breit, schmale Displays haben 360).
    final large = MediaQuery.textScalerOf(context).scale(16) / 16 > 1.15;
    return RamuriCard(
      key: Key('history_run_$id'),
      radius: 20,
      padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
      onTap: () => onOpen(id),
      child: large
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [miniature, const Spacer(), delete],
                ),
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: texts,
                ),
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                miniature,
                const SizedBox(width: 12),
                Expanded(child: texts),
                delete,
              ],
            ),
    );
  }
}

/// Die Quelle der Kartenbilder, einmal vollständig unter der Liste (FR-0204 "jede Karte nennt die Quelle"; WP13 N5).
/// Nur sichtbar, solange mindestens ein Kartenbild zu sehen ist; nie abgeschnitten, bricht bei Bedarf um.
class _AttributionFooter extends StatelessWidget {
  const _AttributionFooter({required this.service});

  final MiniatureService service;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: service.shownImages,
      builder: (context, shown, _) {
        final source = service.consent.services.attribution;
        if (shown <= 0 || !service.enabled || source.isEmpty) {
          return const SizedBox.shrink();
        }
        final theme = Theme.of(context);
        return SizedBox(
          width: double.infinity,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Text(
              AppLocalizations.of(context).mapHistoryAttribution(source),
              key: const Key('history_attribution'),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        );
      },
    );
  }
}
