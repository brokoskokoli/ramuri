import 'package:core/core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../offload_scope.dart';
import '../settings/app_settings.dart';
import 'fitness_section.dart';
import 'statistics_view.dart';

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
  });

  final StorageSession session;
  final Clock clock;

  /// Heutiger Kalendertag `JJJJ-MM-TT`; sonst der Ortstag der Uhr. Für Tests.
  final String? today;

  /// Einstieg zur Erklärung eines Werts; ohne ihn öffnet sich die Erklärung
  /// aus den gespeicherten Angaben ([showValueExplanation]).
  final ExplainValue? onExplain;

  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

enum _Kind { week, month, custom, run }

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
  _Kind _kind = _Kind.week;
  late String _anchor = _today;
  late String _from = _shift(_today, -6);
  late String _to = _today;
  int? _runId;

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

  void _reload() => setState(() => _future = _load());

  static DateTime _date(String day) => DateTime.parse('${day}T00:00:00Z');

  static String _shift(String day, int days) =>
      isoDay(_date(day).add(Duration(days: days)));

  StatisticsPeriod? _period(List<RunOverview> overviews) {
    switch (_kind) {
      case _Kind.week:
        return StatisticsPeriod.weekOf(_anchor);
      case _Kind.month:
        return StatisticsPeriod.monthOf(_anchor);
      case _Kind.custom:
        return StatisticsPeriod.custom(from: _from, to: _to);
      case _Kind.run:
        final id =
            _runId ?? (overviews.isEmpty ? null : overviews.first.run.id);
        return id == null ? null : StatisticsPeriod.singleRun(id);
    }
  }

  void _step(int direction) {
    setState(() {
      final d = _date(_anchor);
      _anchor = _kind == _Kind.week
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
        _from = day;
        if (_to.compareTo(day) < 0) _to = day;
      } else {
        _to = day;
        if (_from.compareTo(day) > 0) _from = day;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.statTitle)),
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

    Widget chip(_Kind kind, String key, String label) => ChoiceChip(
      key: Key(key),
      label: Text(label),
      selected: _kind == kind,
      onSelected: (_) => setState(() => _kind = kind),
    );

    final selector = switch (_kind) {
      _Kind.week || _Kind.month => Row(
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
              _kind == _Kind.week
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
      _Kind.custom => Wrap(
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
      _Kind.run =>
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
                onChanged: (id) => setState(() => _runId = id),
              ),
    };

    return ListView(
      key: const Key('stat_list'),
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            chip(_Kind.week, 'stat_kind_week', l10n.statKindWeek),
            chip(_Kind.month, 'stat_kind_month', l10n.statKindMonth),
            chip(_Kind.custom, 'stat_kind_custom', l10n.statKindCustom),
            chip(_Kind.run, 'stat_kind_run', l10n.statKindRun),
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
        const SizedBox(height: 16),
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
