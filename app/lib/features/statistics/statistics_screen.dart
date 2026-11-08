import 'package:core/core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../offload_scope.dart';
import '../../ui/ui.dart';
import '../settings/app_settings.dart';
import 'fitness_section.dart';
import 'progress_header.dart';
import 'statistics_view.dart';
import 'statistics_view_state.dart';

/// Tippziel der Erklärung eines Werts. [valueKey] ist der Schlüssel des
/// gespeicherten Werts (`ComputedValue.key`), [runId] oder [day] sein Besitzer.
typedef ExplainValue = void Function(
  BuildContext context,
  String valueKey, {
  int? runId,
  String? day,
});

/// Statistik (FR-0043, FR-0044): Kennzahlen für eine Woche, einen Monat, einen
/// frei gewählten Zeitraum oder einen einzelnen Lauf, dazu die Fitnessanzeige
/// (FR-0081, FR-0084). Alle Läufe werden in wenigen gebündelten Abfragen
/// gelesen; die Summen rechnet `computePeriodStatistics`. Jede Kennzahl ist
/// berechnet oder „nicht verfügbar“ mit Grund (FR-0057).
class StatisticsScreen extends StatefulWidget {
  const StatisticsScreen({
    super.key,
    required this.session,
    required this.clock,
    this.today,
    this.onExplain,
    this.viewState,
  });

  final StorageSession session;
  final Clock clock;

  /// Heutiger Kalendertag `JJJJ-MM-TT`; sonst der Ortstag der Uhr. Für Tests.
  final String? today;

  /// Einstieg zur Erklärung eines Werts; ohne ihn öffnet sich die Erklärung
  /// aus den gespeicherten Angaben ([showValueExplanation]).
  final ExplainValue? onExplain;

  /// Auswahl und Scrollposition, die über Neuaufbauten (Tab-Wechsel) hinweg
  /// gehalten werden; ohne Angabe legt die Seite ein eigenes Objekt an. Die
  /// Daten lädt die Seite in jedem Fall bei jedem Aufbau neu.
  final StatisticsViewState? viewState;

  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _Data {
  _Data(this.overviews, this.fitness)
    : figures = [for (final o in overviews) o.toFigures()];
  final List<RunOverview> overviews;
  final FitnessOverview fitness;

  /// Einmal gebildet, nicht je Build (Review Teil C).
  final List<RunFigures> figures;
}

class _StatisticsScreenState extends State<StatisticsScreen> {
  late Future<_Data> _future = _load();
  late final StatisticsViewState _view =
      widget.viewState ?? StatisticsViewState();
  // Eine gemerkte Position hinter dem Ende des (inzwischen kürzeren) Inhalts
  // klemmt der Scrollbereich beim ersten Layout selbst (progress_page_test).
  late final ScrollController _scroll = ScrollController(
    initialScrollOffset: _view.scrollOffset,
  )..addListener(_rememberScroll);

  StatisticsKind get _kind => _view.kind;
  String get _anchor => _view.anchor!;
  String get _from => _view.from!;
  String get _to => _view.to!;

  @override
  void initState() {
    super.initState();
    _view.anchor ??= _today;
    _view.from ??= _shift(_today, -6);
    _view.to ??= _today;
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _rememberScroll() {
    if (_scroll.hasClients) _view.scrollOffset = _scroll.offset;
  }

  /// Heutiger Ortstag nach dem Versatz der Uhr (wie der Tag eines Laufendes).
  String get _today {
    final now = widget.clock.now().toUtc();
    return widget.today ?? isoDay(now.add(widget.clock.utcOffsetAt(now)));
  }

  Future<_Data> _load() async {
    final overviews = await RunOverviewService(
      session: widget.session,
      clock: widget.clock,
      offload: OffloadScope.of(context),
    ).load();
    final fitness = await FitnessOverviewService(session: widget.session)
        .load([for (final o in overviews) o.run]);
    return _Data(overviews, fitness);
  }

  // Block statt Pfeil: Ein Pfeil gäbe die Zuweisung (das Future) an setState
  // zurück, und setState weist das in Debug und Test mit einem Fehler ab.
  void _reload() => setState(() {
    _future = _load();
  });

  static DateTime _date(String day) => DateTime.parse('${day}T00:00:00Z');

  static String _shift(String day, int days) =>
      isoDay(_date(day).add(Duration(days: days)));

  StatisticsPeriod? _period(List<RunOverview> overviews) {
    switch (_kind) {
      case StatisticsKind.week:
        return StatisticsPeriod.weekOf(_anchor);
      case StatisticsKind.month:
        return StatisticsPeriod.monthOf(_anchor);
      case StatisticsKind.custom:
        return StatisticsPeriod.custom(from: _from, to: _to);
      case StatisticsKind.run:
        // Ein gemerkter Lauf kann inzwischen gelöscht sein: dann der neueste.
        final remembered = _view.runId;
        final id =
            remembered != null && overviews.any((o) => o.run.id == remembered)
            ? remembered
            : (overviews.isEmpty ? null : overviews.first.run.id);
        return id == null ? null : StatisticsPeriod.singleRun(id);
    }
  }

  void _step(int direction) {
    setState(() {
      final d = _date(_anchor);
      _view.anchor = _kind == StatisticsKind.week
          ? _shift(_anchor, 7 * direction)
          : isoDay(DateTime.utc(d.year, d.month + direction, 1));
    });
  }

  Future<void> _pick({required bool from}) async {
    final current = _date(from ? _from : _to);
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime.utc(2000),
      lastDate: DateTime.utc(2100),
    );
    if (picked == null || !mounted) return;
    // Ein Datum aus dem Datumsfenster ist ein lokaler Kalendertag; nur
    // Jahr, Monat, Tag zählen.
    final day = isoDay(DateTime.utc(picked.year, picked.month, picked.day));
    setState(() {
      if (from) {
        _view.from = day;
        if (_to.compareTo(day) < 0) _view.to = day;
      } else {
        _view.to = day;
        if (_from.compareTo(day) > 0) _view.from = day;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Ohne AppBar wie im Design; der Titel steht in der Liste (Fortschritt.dc).
    return Scaffold(
      body: FutureBuilder<_Data>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(l10n.statLoadFailed, key: const Key('stat_failed')),
                  TextButton(
                    key: const Key('stat_retry'),
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
          return _content(context, data);
        },
      ),
    );
  }

  Widget _content(BuildContext context, _Data data) {
    final l10n = AppLocalizations.of(context);
    final material = MaterialLocalizations.of(context);
    final formatter = AppSettingsScope.formatterOf(context);
    final period = _period(data.overviews);
    String dateText(String day) => material.formatMediumDate(_date(day));

    Widget chip(StatisticsKind kind, String key, String label) => RamuriChip(
      key: Key(key),
      label: label,
      selected: _kind == kind,
      onPressed: () => setState(() => _view.kind = kind),
    );

    final selector = switch (_kind) {
      StatisticsKind.week || StatisticsKind.month => Row(
        children: [
          IconButton(
            key: const Key('stat_prev'),
            tooltip: l10n.statPrev,
            icon: const Icon(Icons.chevron_left),
            onPressed: () => _step(-1),
          ),
          Expanded(
            child: Text(
              key: const Key('stat_period_label'),
              textAlign: TextAlign.center,
              _kind == StatisticsKind.week
                  ? l10n.statWeekLabel(
                      dateText(period!.firstDay!),
                      dateText(period.lastDay!),
                    )
                  : material.formatMonthYear(_date(period!.firstDay!)),
            ),
          ),
          IconButton(
            key: const Key('stat_next'),
            tooltip: l10n.statNext,
            icon: const Icon(Icons.chevron_right),
            onPressed: () => _step(1),
          ),
        ],
      ),
      StatisticsKind.custom => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton(
            key: const Key('stat_from'),
            onPressed: () => _pick(from: true),
            child: Text(l10n.statFrom(dateText(_from))),
          ),
          OutlinedButton(
            key: const Key('stat_to'),
            onPressed: () => _pick(from: false),
            child: Text(l10n.statTo(dateText(_to))),
          ),
        ],
      ),
      StatisticsKind.run =>
        data.overviews.isEmpty
            ? Text(l10n.statNoRunYet, key: const Key('stat_no_runs_at_all'))
            : DropdownButton<int>(
                key: const Key('stat_run_pick'),
                isExpanded: true,
                hint: Text(l10n.statPickRun),
                value: period!.runId,
                items: [
                  for (final o in data.overviews)
                    DropdownMenuItem(
                      value: o.run.id,
                      child: Text(runLabel(material, o.run), softWrap: true),
                    ),
                ],
                onChanged: (id) => setState(() => _view.runId = id),
              ),
    };

    final series = weeklyDistanceSeries(_today, data.figures);
    return SafeArea(
      bottom: false,
      child: SingleChildScrollView(
        key: const Key('stat_list'),
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(20, 28, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                l10n.homeProgress,
                key: const Key('progress_title'),
                style: RamuriType.of(context).pageTitle,
              ),
            ),
            const SizedBox(height: 14),
            WeekDistanceCard(series: series, formatter: formatter),
            const SizedBox(height: 14),
            Vo2ProgressCard(
              fitness: data.fitness,
              session: widget.session,
              onExplain: widget.onExplain,
            ),
            const SizedBox(height: 14),
            EfficiencyCard(fitness: data.fitness),
            const SizedBox(height: 28),
            SectionHeading(l10n.progressPeriodTitle),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                chip(StatisticsKind.week, 'stat_kind_week', l10n.statKindWeek),
                chip(
                  StatisticsKind.month,
                  'stat_kind_month',
                  l10n.statKindMonth,
                ),
                chip(
                  StatisticsKind.custom,
                  'stat_kind_custom',
                  l10n.statKindCustom,
                ),
                chip(StatisticsKind.run, 'stat_kind_run', l10n.statKindRun),
              ],
            ),
            const SizedBox(height: 8),
            selector,
            const SizedBox(height: 8),
            if (period != null)
              PeriodStatisticsView(
                key: ValueKey(period),
                period: period,
                overviews: data.overviews,
                figures: data.figures,
                formatter: formatter,
              ),
            const SizedBox(height: 6),
            FitnessSection(
              period: period,
              runsInPeriod: period == null
                  ? 0
                  : data.figures
                        .where((f) => period.contains(id: f.runId, day: f.day))
                        .length,
              fitness: data.fitness,
              session: widget.session,
              onExplain: widget.onExplain,
            ),
          ],
        ),
      ),
    );
  }
}

/// Beginn eines Laufs in der Ortszeit zum Laufende, für die Auswahl.
String runLabel(MaterialLocalizations material, StoredRun run) {
  final offset = run.endedUtcOffset;
  final start = offset == null
      ? run.startedAt.toLocal()
      : run.startedAt.toUtc().add(offset);
  return '${material.formatMediumDate(start)}, '
      '${material.formatTimeOfDay(TimeOfDay.fromDateTime(start))}';
}
