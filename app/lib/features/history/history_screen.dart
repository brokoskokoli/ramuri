import 'package:core/core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../offload_scope.dart';
import '../map/map_consent_controller.dart';
import '../map/map_consent_scope.dart';
import '../map/miniature_service.dart';
import '../recalculation/recalculation_controller.dart';
import '../run/live_run_view.dart' show formatClock;
import '../settings/app_settings.dart';
import '../settings/unit_format.dart';
import '../storage/deletion.dart';
import 'run_detail_screen.dart';
import 'run_miniature.dart';

/// Trainingshistorie (FR-0040, ACC-04): jeder beendete Lauf mit Strecke,
/// Dauer, Pace und, soweit vorhanden, Puls. Fehlendes steht als „nicht
/// verfügbar“, nie als 0. Gelesen wird in einer gebündelten Abfrage
/// ([RunOverviewService]). Löschen hängt an jedem Eintrag
/// ([confirmAndDeleteRun]).
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({
    super.key,
    required this.session,
    required this.clock,
    required this.recalculation,
  });

  final StorageSession session;
  final Clock clock;
  final RecalculationController recalculation;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  late Future<List<RunOverview>> _future = _load();

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

  Future<List<RunOverview>> _load() => RunOverviewService(
    session: widget.session,
    clock: widget.clock,
    offload: OffloadScope.of(context),
  ).load();

  void _reload() {
    setState(() {
      _future = _load();
    });
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
    return Scaffold(
      appBar: AppBar(title: Text(l10n.histTitle)),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(child: _list(l10n, formatter)),
                if (_miniatures != null) MiniatureHost(service: _miniatures!),
              ],
            ),
          ),
          if (_miniatures != null) _AttributionFooter(service: _miniatures!),
        ],
      ),
    );
  }

  Widget _list(AppLocalizations l10n, UnitFormatter formatter) {
    return FutureBuilder<List<RunOverview>>(
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
        final runs = snapshot.data;
        if (runs == null) {
          return const Center(child: CircularProgressIndicator());
        }
        if (runs.isEmpty) {
          return Center(
            child: Text(l10n.histEmpty, key: const Key('history_empty')),
          );
        }
        return ListView.builder(
          key: const PageStorageKey<String>('history_list'),
          itemCount: runs.length,
          itemBuilder: (context, i) => _RunTile(
            key: ValueKey(runs[i].run.id),
            overview: runs[i],
            formatter: formatter,
            session: widget.session,
            miniatures: _miniatures,
            onDelete: _delete,
            onOpen: _open,
          ),
        );
      },
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
    final id = overview.run.id;
    final start = _start;
    final pace = overview.averagePaceSecondsPerKm;
    final bpm = overview.averageHeartRateBpm;
    final tile = ListTile(
      key: Key('history_run_$id'),
      title: Text(
        '${material.formatMediumDate(start)}, '
        '${material.formatTimeOfDay(TimeOfDay.fromDateTime(start))}',
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            overview.distanceMeters == null
                ? l10n.runUnavailable
                : formatter.distance(overview.distanceMeters),
            key: Key('history_distance_$id'),
          ),
          Text(
            overview.totalTime == null
                ? l10n.histRowTimeNone
                : l10n.histRowTime(formatClock(overview.totalTime)),
            key: Key('history_time_$id'),
          ),
          Text(
            '${l10n.runAvgPace}: '
            '${pace == null ? l10n.runUnavailable : formatter.pace(pace)}',
            key: Key('history_pace_$id'),
          ),
          if (overview.readFailed)
            Text(l10n.histRowReadFailed, key: Key('history_failed_$id')),
          Text(
            bpm == null
                ? l10n.histRowNoHeartRate
                : l10n.histRowHeartRate(bpm.round()),
            key: Key('history_hr_$id'),
          ),
        ],
      ),
      isThreeLine: true,
      onTap: () => onOpen(id),
      trailing: IconButton(
        key: Key('history_delete_$id'),
        tooltip: l10n.histDeleteRun,
        icon: const Icon(Icons.delete_outline),
        onPressed: () => onDelete(id),
      ),
    );
    // Die Miniatur steht neben dem Eintrag, nicht als `leading`: ListTile begrenzt dessen Höhe, die Quellenangabe
    // unter dem Bild brauchte mehr.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onOpen(id),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 0, 8),
            child: RunMiniature(
              key: Key('history_miniature_$id'),
              session: session,
              runId: id,
              service: miniatures,
            ),
          ),
        ),
        Expanded(child: tile),
      ],
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
