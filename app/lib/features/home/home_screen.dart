import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import '../../offload_scope.dart';
import '../../ui/ui.dart';
import '../history/run_detail_screen.dart';
import '../recalculation/recalculation_controller.dart';
import '../run/run_flow_screen.dart';
import '../run/run_ports.dart';
import '../sensors/sensor_manager.dart';
import '../settings/app_settings.dart';
import '../settings/unit_format.dart';
import 'data_changes.dart';
import 'overview_screen.dart';

/// Bereich „Heute“ in der Hülle ([AppShell]) nach FR-0209, Fassung Phase 1:
/// Logo, Datum, Profil-Symbol, „Frei laufen“, die Woche Montag bis Sonntag
/// mit Laufhaken und Kilometersumme und der letzte Lauf. Gebaut wird er erst,
/// wenn der Speicher bereit ist ([session] ist die offene Sitzung) und die
/// Ersteinrichtung erledigt oder übersprungen ist. Die Hülle baut ihn bei
/// jeder Datenmeldung ([DataChanges]) neu; dabei lädt er neu.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.session,
    required this.clock,
    required this.permissions,
    required this.recalculation,
    required this.runPorts,
    required this.sensors,
    required this.changes,
  });

  final StorageSession session;
  final PermissionStatusPort permissions;
  final RunPorts runPorts;
  final SensorManager sensors;
  final Clock clock;
  final RecalculationController recalculation;
  final DataChanges changes;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

/// Geladene Läufe: dieselbe Quelle und dieselben Kennzahlen wie die Statistik.
class _Data {
  _Data(this.overviews) : figures = [for (final o in overviews) o.toFigures()];
  final List<RunOverview> overviews;
  final List<RunFigures> figures;
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  late Future<_Data> _future = _load();

  /// Der Ortstag, für den die Seite zuletzt geladen und gebaut wurde.
  late String _shownDay;

  @override
  void initState() {
    super.initState();
    _shownDay = _today;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Bleibt der Prozess über Mitternacht am Leben, steht beim Fortsetzen noch
  /// der alte Tag (Datum, Heute-Kreis, Woche, Summe): bei einem anderen Tag
  /// lädt die Seite neu (FR-0209).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _today != _shownDay) _reload();
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
      _shownDay = _today;
      _future = _load();
    });
  }

  /// Heutiger Ortstag nach dem Versatz der Uhr (wie in der Statistik).
  String get _today {
    final now = widget.clock.now().toUtc();
    return isoDay(now.add(widget.clock.utcOffsetAt(now)));
  }

  static DateTime _date(String day) => DateTime.parse('${day}T00:00:00Z');

  /// Legt [page] über die Hülle (Root-Navigator, Vollbild) und meldet danach
  /// mögliche Änderungen der Daten.
  Future<void> _push(BuildContext context, WidgetBuilder page) async {
    await Navigator.of(context).push<void>(MaterialPageRoute(builder: page));
    widget.changes.changed();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context).textTheme;
    final c = RamuriColors.of(context);
    return Scaffold(
      key: const Key('home_screen'),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 16),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: RamuriLogo(semanticLabel: l10n.appTitle),
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        DateFormat.MMMMEEEEd(
                          Localizations.localeOf(context).toString(),
                        ).format(_date(_today)),
                        key: const Key('home_date'),
                        style: theme.labelMedium!.copyWith(color: c.textMuted),
                      ),
                      Semantics(
                        header: true,
                        child: Text(l10n.homeToday, style: theme.headlineLarge),
                      ),
                    ],
                  ),
                ),
                _ProfileButton(
                  tooltip: l10n.homeOverview,
                  onPressed: () => _push(
                    context,
                    (_) => OverviewScreen(
                      session: widget.session,
                      clock: widget.clock,
                      permissions: widget.permissions,
                      recalculation: widget.recalculation,
                      sensors: widget.sensors,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Der Zugang ist ohne Profil und ohne Freigaben offen (FR-0001,
            // CON-0007); nur der Standort wird geprüft (FR-0195).
            RamuriCard(
              tone: RamuriCardTone.panel,
              radius: 28,
              padding: const EdgeInsets.all(22),
              child: SizedBox(
                width: double.infinity,
                child: RamuriPrimaryButton(
                  key: const Key('home_start_run'),
                  icon: Icons.play_arrow_rounded,
                  label: l10n.homeStartRun,
                  onPressed: () => _push(
                    context,
                    (_) => RunFlowScreen(
                      session: widget.session,
                      clock: widget.clock,
                      ports: widget.runPorts,
                      permissions: widget.permissions,
                      serialize: widget.recalculation.exclusive,
                      sensors: widget.sensors,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            FutureBuilder<_Data>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Column(
                    children: [
                      Text(
                        l10n.statLoadFailed,
                        key: const Key('home_failed'),
                        textAlign: TextAlign.center,
                      ),
                      TextButton(
                        key: const Key('home_retry'),
                        onPressed: _reload,
                        child: Text(l10n.notOpenableRetry),
                      ),
                    ],
                  );
                }
                final data = snapshot.data;
                if (data == null) {
                  return const Center(child: CircularProgressIndicator());
                }
                return _content(context, data);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _content(BuildContext context, _Data data) {
    final l10n = AppLocalizations.of(context);
    final c = RamuriColors.of(context);
    final material = MaterialLocalizations.of(context);
    final formatter = AppSettingsScope.formatterOf(context);
    if (data.overviews.isEmpty) {
      return RamuriCard(
        child: Text(l10n.homeEmpty, key: const Key('home_empty')),
      );
    }
    final today = _today;
    // Dieselbe Woche und dieselbe Summe wie die Wochenstatistik (FR-0044).
    final week = StatisticsPeriod.weekOf(today);
    final inWeek = [
      for (final f in data.figures)
        if (week.contains(id: f.runId, day: f.day)) f,
    ];
    final stats = computePeriodStatistics(week, data.figures);
    final runDays = {for (final f in inWeek) f.day};
    final km = stats.runCount == 0
        ? formatter.distance(0)
        : formatter.distance(stats.distanceMeters.value);
    final last = data.overviews.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RamuriCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionHeading(
                l10n.homeWeekTitle,
                trailing: Text(
                  km,
                  key: const Key('home_week_km'),
                  // Zahl fett in Sora wie im Design.
                  style: Theme.of(context).textTheme.titleSmall!.copyWith(
                    fontFamily: ramuriHeadingFamily,
                    fontWeight: FontWeight.w700,
                    color: c.text,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              // Wie in der Statistik: Fehlt bei einem Lauf die Strecke, ist die
              // Summe nur ein Teil und sagt es.
              if (stats.distanceMeters.isPartial)
                Text(
                  l10n.statPartial(
                    stats.distanceMeters.runsWithValue,
                    stats.distanceMeters.runsTotal,
                  ),
                  key: const Key('home_week_partial'),
                  style: Theme.of(context).textTheme.labelSmall!
                      .copyWith(color: c.textMuted),
                ),
              const SizedBox(height: 14),
              RamuriWeekStrip(
                key: const Key('home_week'),
                days: [
                  for (var i = 0; i < DateTime.daysPerWeek; i++)
                    _weekDay(material, l10n, week.firstDay!, i, today, runDays),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _LastRun(
          overview: last,
          formatter: formatter,
          onTap: () => _push(
            context,
            (_) => RunDetailScreen(
              session: widget.session,
              clock: widget.clock,
              recalculation: widget.recalculation,
              runId: last.run.id,
            ),
          ),
        ),
      ],
    );
  }

  /// Kurzer und langer Name eines Wochentags aus der Datumsausgabe der
  /// Plattform (Deutsch und Englisch nennen den Wochentag vor dem ersten
  /// Komma): „Mo.“ wird zu „Mo“.
  RamuriWeekDay _weekDay(
    MaterialLocalizations material,
    AppLocalizations l10n,
    String firstDay,
    int index,
    String today,
    Set<String> runDays,
  ) {
    final day = isoDay(_date(firstDay).add(Duration(days: index)));
    final date = _date(day);
    String head(String text) => text.split(',').first.trim();
    final short = head(material.formatMediumDate(date)).replaceAll('.', '');
    final long = head(material.formatFullDate(date));
    final done = runDays.contains(day);
    return RamuriWeekDay(
      label: short,
      semanticLabel: done
          ? l10n.homeWeekDayRun(long)
          : l10n.homeWeekDayNone(long),
      done: done,
      today: day == today,
      future: day.compareTo(today) > 0,
    );
  }
}

class _ProfileButton extends StatelessWidget {
  const _ProfileButton({required this.tooltip, required this.onPressed});

  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = RamuriColors.of(context);
    return IconButton(
      key: const Key('home_overview'),
      tooltip: tooltip,
      constraints: const BoxConstraints.tightFor(width: 48, height: 48),
      style: IconButton.styleFrom(
        backgroundColor: c.surface,
        side: BorderSide(color: c.outline),
      ),
      icon: const Icon(Icons.person_outline_rounded),
      onPressed: onPressed,
    );
  }
}

/// Der letzte Lauf mit Sprung in seine Detailansicht (wie im Verlauf).
class _LastRun extends StatelessWidget {
  const _LastRun({
    required this.overview,
    required this.formatter,
    required this.onTap,
  });

  final RunOverview overview;
  final UnitFormatter formatter;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final material = MaterialLocalizations.of(context);
    final c = RamuriColors.of(context);
    final theme = Theme.of(context).textTheme;
    final day = DateTime.parse('${dayOfRun(overview.run)}T00:00:00Z');
    final pace = overview.averagePaceSecondsPerKm;
    return RamuriCard(
      key: const Key('home_last_run'),
      radius: 20,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      onTap: onTap,
      child: Row(
        children: [
          // Statisches Symbol-Kästchen wie im Design.
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: c.tint,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(Icons.timeline_rounded, color: c.accent),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.homeLastRun(material.formatMediumDate(day)),
                  style: theme.labelSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  '${formatter.distance(overview.distanceMeters)} · '
                  '${formatter.pace(pace)}',
                  key: const Key('home_last_run_values'),
                  style: theme.titleMedium,
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: c.textMuted),
        ],
      ),
    );
  }
}
