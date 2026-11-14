import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import '../../offload_scope.dart';
import '../../ui/ui.dart';
import '../health/imported_exercise_screen.dart';
import '../map/map_consent_controller.dart';
import '../map/map_consent_scope.dart';
import '../map/miniature_service.dart';
import '../recalculation/recalculation_controller.dart';
import '../run/live_run_view.dart' show formatClock;
import '../settings/app_settings.dart';
import '../settings/unit_format.dart';
import '../storage/deletion.dart';
import 'history_view_state.dart';
import 'manual_training_screen.dart';
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
  _Data(this.overviews, this.trainings, this.imported)
    : figures = [for (final o in overviews) o.toFigures()];
  final List<RunOverview> overviews;

  /// Nachgetragene Trainings (FR-0199). Sie liegen nicht in `runs` und fließen
  /// darum in keine Summe, Statistik, Bestwerte oder VO₂max ein.
  final List<StoredManualTraining> trainings;

  /// Aus Health Connect importierte Einheiten (K62 F2): nur Anzeige mit Quelle,
  /// in keiner Summe und keiner Berechnung, bis sie als Nachtrag übernommen sind.
  final List<HealthRecord> imported;

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

  SubjectiveService get _subjective =>
      SubjectiveService(session: widget.session, clock: widget.clock);

  Future<_Data> _load() async {
    final offload = OffloadScope.of(context);
    final overviews = await RunOverviewService(
      session: widget.session,
      clock: widget.clock,
      offload: offload,
    ).load();
    final session = widget.session;
    var imported = const <HealthRecord>[];
    if (session is HealthStorage) {
      try {
        imported = await (session as HealthStorage).health.exercises(
          DateTime.utc(2000),
          DateTime.utc(2200),
        );
      } on Object {
        // Ohne Inhalt: der Verlauf zeigt dann nur die eigenen Einträge.
      }
    }
    return _Data(overviews, await _subjective.trainings(), imported);
  }

  Future<void> _openImported(HealthRecord e) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ImportedExerciseScreen(
          exercise: e,
          session: widget.session,
          clock: widget.clock,
          today: _today,
        ),
      ),
    );
    if (mounted) _reload();
  }

  Future<void> _editTraining([StoredManualTraining? existing]) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ManualTrainingScreen(
          service: _subjective,
          today: _today,
          existing: existing,
        ),
      ),
    );
    if (mounted && saved == true) _reload();
  }

  Future<void> _deleteTraining(StoredManualTraining t) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.manualDeleteTitle),
        content: Text(l10n.manualDeleteBody),
        actions: [
          TextButton(
            autofocus: true,
            key: const Key('manual_delete_cancel'),
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.manualDeleteCancel),
          ),
          FilledButton(
            key: const Key('manual_delete_confirm'),
            style: ramuriDangerFilledStyle(context),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.manualDeleteConfirm),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _subjective.deleteTraining(t.id);
    } on Object {
      // Ohne Inhalt melden.
      messenger?.showSnackBar(SnackBar(content: Text(l10n.manualDeleteFailed)));
      return;
    }
    if (mounted) _reload();
  }

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

  /// Titel mit „Training nachtragen“ als Knopf in derselben Zeile (kostet keine
  /// zusätzliche Höhe in der Liste).
  Widget _title(AppLocalizations l10n) => Row(
    children: [
      Expanded(
        child: Semantics(
          header: true,
          child: Text(
            l10n.histTitle,
            key: const Key('history_title'),
            style: RamuriType.of(context).pageTitle,
          ),
        ),
      ),
      IconButton(
        key: const Key('manual_add'),
        tooltip: l10n.manualAdd,
        icon: const Icon(Icons.add),
        onPressed: _editTraining,
      ),
    ],
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
        if (data.overviews.isEmpty &&
            data.trainings.isEmpty &&
            data.imported.isEmpty) {
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
    final adopted = adoptedHcIds(data.trainings);
    final entries = <_Entry>[
      for (final o in inRange) _RunEntry(o),
      for (final t in data.trainings)
        // „Alle“ reicht nur über die Lauftage; ein Training vor dem ersten Lauf
        // gehört trotzdem dazu.
        if (range == HistoryRange.all ||
            period.contains(id: -1, day: t.training.isoDay))
          _TrainingEntry(t),
      for (final e in data.imported)
        if (range == HistoryRange.all ||
            period.contains(
              id: -1,
              day: isoDay(importedExerciseLocalStart(e, widget.clock)),
            ))
          _ImportedEntry(
            e,
            importedExerciseLocalStart(e, widget.clock),
            adopted.contains(e.id),
          ),
    ];
    final groups = groupByWeek<_Entry>(
      entries,
      today,
      dayOf: (e) => e.day,
      endedAtOf: (e) => e.sortKey,
    );
    final rows = <Widget Function(BuildContext)>[
      (_) => _title(l10n),
      (_) => const SizedBox(height: 14),
      (_) => RamuriSegmentedToggle<HistoryRange>(
        key: const Key('history_range'),
        expanded: true,
        style: RamuriSegmentedStyle.dark,
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
      if (entries.isEmpty)
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
        if (totals.runCount > 0)
          (_) => _TotalsPanel(totals: totals, formatter: formatter),
        if (entries.any((e) => e is _ImportedEntry))
          (_) => Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              l10n.healthHistTotalsNote,
              key: const Key('health_hist_totals_note'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        for (final g in groups) ...[
          (_) => Padding(
            padding: const EdgeInsets.only(top: 18, bottom: 8),
            child: SectionHeading(_weekTitle(l10n, g, today), eyebrow: true),
          ),
          for (final e in g.items)
            (_) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: switch (e) {
                _RunEntry(:final overview) => _RunTile(
                  key: ValueKey(overview.run.id),
                  overview: overview,
                  formatter: formatter,
                  session: widget.session,
                  miniatures: _miniatures,
                  onDelete: _delete,
                  onOpen: _open,
                ),
                _ImportedEntry(:final exercise, :final adopted) =>
                  _ImportedTile(
                    key: ValueKey('hc_${exercise.id}'),
                    exercise: exercise,
                    localStart: e.sortKey,
                    adopted: adopted,
                    onOpen: _openImported,
                  ),
                _TrainingEntry(:final training) => _TrainingTile(
                  key: ValueKey('manual_${training.id}'),
                  stored: training,
                  onEdit: _editTraining,
                  onDelete: _deleteTraining,
                ),
              },
            ),
        ],
      ],
    ];
    return ListView.builder(
      // Je Zeitraum eine eigene Position: ein Wechsel beginnt oben, die Rückkehr
      // aus einem anderen Tab findet die Stelle wieder (PageStorage der Route).
      // Die Sitzung gehört zum Schlüssel: Nach einem Archiv-Import beginnt die
      // Liste oben, nicht an der Stelle der alten Daten.
      key: PageStorageKey<(StorageSession, String)>((
        widget.session,
        'history_list_${range.name}',
      )),
      padding: _pagePadding,
      itemCount: rows.length,
      itemBuilder: (context, i) => rows[i](context),
    );
  }

  /// „Diese Woche“, „Letzte Woche“, sonst Anfang und Ende der Woche; das Jahr
  /// steht nur, wenn die Woche nicht im Jahr von heute beginnt.
  String _weekTitle(AppLocalizations l10n, WeekGroup<_Entry> g, String today) {
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

/// Eintrag der Liste: Lauf oder nachgetragenes Training, nach Tag einsortiert.
sealed class _Entry {
  String get day;

  /// Ordnung innerhalb der Woche (neuester zuerst): Ortszeit des Laufendes,
  /// bei Trainings der Beginn ihres Tages (unter den Läufen desselben Tages).
  DateTime get sortKey;
}

class _RunEntry extends _Entry {
  _RunEntry(this.overview);
  final RunOverview overview;

  @override
  String get day => dayOfRun(overview.run);

  @override
  DateTime get sortKey {
    final run = overview.run;
    return run.endedAt!.toUtc().add(run.endedUtcOffset ?? Duration.zero);
  }
}

class _TrainingEntry extends _Entry {
  _TrainingEntry(this.training);
  final StoredManualTraining training;

  @override
  String get day => training.training.isoDay;

  @override
  DateTime get sortKey => training.training.day;
}

/// Aus Health Connect importierte Einheit: nur Anzeige, zählt nirgends mit.
class _ImportedEntry extends _Entry {
  _ImportedEntry(this.exercise, this.localStart, this.adopted);
  final HealthRecord exercise;
  final DateTime localStart;

  /// Schon als Nachtrag übernommen (dann zählt der Nachtrag, nicht diese Zeile).
  final bool adopted;

  @override
  String get day => isoDay(localStart);

  @override
  DateTime get sortKey => localStart;
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
    final belt = overview.run.mode == RunMode.treadmill;
    // Bandlauf: keine Karte, keine Miniatur, kein leerer Platz (FR-0196).
    final miniature = belt
        ? const SizedBox.shrink()
        : RunMiniature(
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
        if (belt)
          Text(
            l10n.treadmillHistoryBadge,
            key: Key('history_treadmill_$id'),
            style: text.labelMedium,
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
              semanticsLabel: pace == null ? null : formatter.pace(pace),
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
              : unitTogether(
                  l10n.histRowHeartRate(bpm.round()),
                  l10n.liveUnitBpm,
                ),
          semanticsLabel: bpm == null
              ? null
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
                  children: [if (!belt) miniature, const Spacer(), delete],
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
                if (!belt) ...[miniature, const SizedBox(width: 12)],
                Expanded(child: texts),
                delete,
              ],
            ),
    );
  }
}

/// Nachgetragenes Training (FR-0199): deutlich gekennzeichnet, ohne Karte,
/// Distanz und Pace. Belastung: sRPE-Punkte als Schätzung mit Grundlage; die
/// Umrechnung nach PAR-086 gibt es noch nicht, die Belastung ist „nicht
/// bewertet“. Tippen ändert, der Papierkorb löscht (mit Rückfrage).
class _TrainingTile extends StatelessWidget {
  const _TrainingTile({
    super.key,
    required this.stored,
    required this.onEdit,
    required this.onDelete,
  });

  final StoredManualTraining stored;
  final Future<void> Function(StoredManualTraining) onEdit;
  final Future<void> Function(StoredManualTraining) onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final material = MaterialLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final id = stored.id;
    final t = stored.training;
    final srpe = t.srpe;
    final minutes = (t.duration.inSeconds / 60).round().toString();
    final kind = t.kind == ManualTrainingKind.run
        ? l10n.manualKindRun
        : l10n.manualKindOther;
    return RamuriCard(
      key: Key('manual_training_$id'),
      radius: 20,
      padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
      onTap: () => onEdit(stored),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    RamuriBadge(l10n.manualBadge),
                    Text(
                      kind,
                      key: Key('manual_kind_$id'),
                      style: text.titleSmall,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  material.formatMediumDate(t.day),
                  key: Key('manual_date_$id'),
                  style: text.titleSmall,
                ),
                const SizedBox(height: 3),
                Wrap(
                  spacing: 10,
                  children: [
                    Text(
                      l10n.manualRowDuration(minutes),
                      key: Key('manual_duration_$id'),
                      style: text.bodyMedium,
                    ),
                    Text(
                      l10n.manualRowRpe(t.rpe),
                      key: Key('manual_rpe_$id'),
                      style: text.bodyMedium,
                    ),
                  ],
                ),
                Text(
                  l10n.manualRowSrpe(srpe.points.round().toString()),
                  key: Key('manual_srpe_$id'),
                  style: text.bodyMedium,
                ),
                Text(
                  l10n.manualRowBasis(formatClock(t.duration), t.rpe),
                  key: Key('manual_basis_$id'),
                  style: text.bodySmall,
                ),
                Text(
                  l10n.manualRowNotRated,
                  key: Key('manual_not_rated_$id'),
                  style: text.bodySmall,
                ),
                Text(l10n.manualRowNoMap, style: text.bodySmall),
              ],
            ),
          ),
          IconButton(
            key: Key('manual_delete_$id'),
            tooltip: l10n.manualDeleteTooltip,
            icon: const Icon(Icons.delete_outline),
            onPressed: () => onDelete(stored),
          ),
        ],
      ),
    );
  }
}

/// Importierte Einheit im Verlauf: gekennzeichnet „aus Health Connect“ mit der
/// Quell-App; gestrichelt wie im Design, damit sie nicht wie ein eigener Lauf
/// wirkt. Tippen öffnet das Detail (Pulskurve, Übernehmen).
class _ImportedTile extends StatelessWidget {
  const _ImportedTile({
    super.key,
    required this.exercise,
    required this.localStart,
    required this.adopted,
    required this.onOpen,
  });

  final HealthRecord exercise;
  final DateTime localStart;
  final bool adopted;
  final Future<void> Function(HealthRecord) onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final material = MaterialLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final id = exercise.id;
    final kind = importedExerciseKindText(l10n, exercise);
    final minutes = exerciseMinutes(exercise);
    final when =
        '${material.formatMediumDate(localStart)}, '
        '${material.formatTimeOfDay(TimeOfDay.fromDateTime(localStart))}';
    return Semantics(
      container: true,
      button: true,
      excludeSemantics: true,
      onTap: () => onOpen(exercise),
      label:
          '${l10n.healthHistSemantics(kind, when, exercise.origin)}'
          '${adopted ? ', ${l10n.healthHistTaken}' : ''}',
      child: RamuriCard(
        key: Key('health_exercise_$id'),
        radius: 20,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        onTap: () => onOpen(exercise),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                RamuriBadge(l10n.healthHistBadge),
                Text(kind, style: text.titleSmall),
                if (adopted)
                  Text(
                    l10n.healthHistTaken,
                    key: Key('health_exercise_taken_$id'),
                    style: text.labelLarge,
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(when, style: text.titleSmall),
            const SizedBox(height: 3),
            Text(
              l10n.manualRowDuration('$minutes'),
              key: Key('health_exercise_duration_$id'),
              style: text.bodyMedium,
            ),
            Text(
              l10n.healthHistSource(exercise.origin),
              key: Key('health_exercise_source_$id'),
              style: text.bodySmall,
            ),
          ],
        ),
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
