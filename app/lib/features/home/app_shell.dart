import 'package:core/core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../history/history_screen.dart';
import '../history/history_view_state.dart';
import '../plan/plan_page_view_state.dart';
import '../plan/plan_screen.dart';
import '../readiness/readiness_today.dart';
import '../recalculation/recalculation_controller.dart';
import '../run/run_ports.dart';
import '../sensors/sensor_manager.dart';
import '../statistics/statistics_screen.dart';
import '../statistics/statistics_view_state.dart';
import 'data_changes.dart';
import 'home_screen.dart';
import 'overview_screen.dart';
import 'run_starter.dart';

/// Hülle mit der unteren Navigation (FR-0208): Heute, Plan, Verlauf,
/// Fortschritt und ganz rechts Profil (die Übersicht wie hinter dem
/// Profil-Symbol auf „Heute“).
/// Lauf, Lauf vorbereiten, Detail und Zusammenfassung werden über den
/// Root-Navigator gelegt und decken die Leiste damit ab (Vollbild). Ebenso die
/// Unterseiten der Übersicht (Einstellungen, Sensoren, Daten, Über …), gleich
/// ob die Übersicht als Bereich oder über das Symbol geöffnet wurde.
///
/// Der gewählte Bereich wird bei jedem Wechsel und bei jeder Meldung von
/// [changes] neu aufgebaut (kein `IndexedStack`), damit nichts Veraltetes
/// stehen bleibt. Die Daten werden dabei frisch geladen; die Auswahl des
/// Zeitraums und die Scrollposition von Fortschritt und die gezeigte Woche und
/// Scrollposition von Plan hält die Hülle in je einem Zustandsobjekt über den
/// Neuaufbau hinweg.
class AppShell extends StatefulWidget {
  const AppShell({
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
  State<AppShell> createState() => _AppShellState();
}

class _Tab {
  const _Tab(this.id, this.key, this.icon, this.label);

  final String id;
  final Key key;
  final IconData icon;
  final String Function(AppLocalizations) label;
}

class _AppShellState extends State<AppShell> {
  // Ab Phase 2 steht „Plan“ an zweiter Stelle (FR-0208).
  static const _tabs = [
    _Tab('today', Key('home_today'), Icons.home_rounded, _today),
    _Tab('plan', Key('home_plan'), Icons.calendar_month_rounded, _plan),
    _Tab(
      'history',
      Key('home_history'),
      Icons.format_list_bulleted_rounded,
      _history,
    ),
    _Tab(
      'progress',
      Key('home_statistics'),
      Icons.show_chart_rounded,
      _progress,
    ),
    _Tab(
      'profile',
      Key('home_profile_tab'),
      Icons.person_outline_rounded,
      _profile,
    ),
  ];

  static String _today(AppLocalizations l) => l.homeToday;
  static String _plan(AppLocalizations l) => l.homePlan;
  static String _history(AppLocalizations l) => l.homeHistory;
  static String _progress(AppLocalizations l) => l.homeProgress;
  static String _profile(AppLocalizations l) => l.homeProfileTab;

  int _index = 0;

  /// Zeitraumwahl und Scrollposition von Fortschritt über Tab-Wechsel.
  final StatisticsViewState _progressState = StatisticsViewState();

  /// Zeitraum des Verlaufs über Tab-Wechsel.
  final HistoryViewState _historyState = HistoryViewState();

  /// Gezeigte Woche und Scrollposition des Plans über Tab-Wechsel.
  final PlanPageViewState _planState = PlanPageViewState();

  Widget _body(String id) {
    switch (id) {
      case 'plan':
        return PlanScreen(
          session: widget.session,
          clock: widget.clock,
          viewState: _planState,
          readinessToday: (day) async {
            final r = await loadReadinessToday(
              session: widget.session,
              clock: widget.clock,
              recalculation: widget.recalculation.service,
            );
            return r == null ? null : PlanReadinessDay.of(day, r.result);
          },
          onStartUnit: (context, unit) => RunStarter(
            session: widget.session,
            clock: widget.clock,
            permissions: widget.permissions,
            recalculation: widget.recalculation,
            runPorts: widget.runPorts,
            sensors: widget.sensors,
            changes: widget.changes,
          ).start(context, unit: unit),
        );
      case 'history':
        return HistoryScreen(
          session: widget.session,
          clock: widget.clock,
          recalculation: widget.recalculation,
          viewState: _historyState,
        );
      case 'progress':
        return StatisticsScreen(
          session: widget.session,
          clock: widget.clock,
          recalculation: widget.recalculation,
          viewState: _progressState,
          changes: widget.changes,
        );
      case 'profile':
        return OverviewScreen(
          session: widget.session,
          clock: widget.clock,
          permissions: widget.permissions,
          recalculation: widget.recalculation,
          sensors: widget.sensors,
        );
      default:
        return HomeScreen(
          session: widget.session,
          clock: widget.clock,
          permissions: widget.permissions,
          recalculation: widget.recalculation,
          runPorts: widget.runPorts,
          sensors: widget.sensors,
          changes: widget.changes,
        );
    }
  }

  /// Größter Schriftfaktor, bei dem die längste Beschriftung der Leiste
  /// (fett wie im gewählten Bereich) in einer Zeile in ihren Eintrag passt.
  /// Bei fünf Einträgen und großer Schrift wäre etwa „Fortschritt“ sonst
  /// umgebrochen und abgeschnitten (FR-0208); passt alles, bleibt der
  /// Schriftfaktor des Systems unverändert.
  double _labelScaleLimit(
    BuildContext context,
    AppLocalizations l10n,
    double width,
  ) {
    final style = Theme.of(context).navigationBarTheme.labelTextStyle
        ?.resolve({WidgetState.selected});
    final size = style?.fontSize;
    if (size == null || !width.isFinite) return double.infinity;
    final scaler = MediaQuery.textScalerOf(context);
    // Etwas Rand zum Nachbarn, damit sich die Wörter nicht berühren.
    final slot = width / _tabs.length - 8;
    var widest = 0.0;
    for (final t in _tabs) {
      final painter = TextPainter(
        text: TextSpan(text: t.label(l10n), style: style),
        textDirection: Directionality.of(context),
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      if (painter.width > widest) widest = painter.width;
      painter.dispose();
    }
    if (widest <= slot) return double.infinity;
    return scaler.scale(size) / size * slot / widest;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: widget.changes,
      builder: (context, _) => PopScope(
        // Zurück: aus Plan, Verlauf, Fortschritt und Profil zu Heute, von
        // Heute aus der App.
        canPop: _index == 0,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          // Zurück aus dem Kalender führt zur Plan-Seite.
          setState(() {
            if (_tabs[_index].id == 'plan' && _planState.calendarOpen) {
              _planState.calendarOpen = false;
            } else {
              _index = 0;
            }
          });
        },
        child: Scaffold(
          body: KeyedSubtree(
            key: ValueKey('${_tabs[_index].id}-${widget.changes.revision}'),
            child: _body(_tabs[_index].id),
          ),
          bottomNavigationBar: LayoutBuilder(
            builder: (context, constraints) =>
                MediaQuery.withClampedTextScaling(
                  maxScaleFactor: _labelScaleLimit(
                    context,
                    l10n,
                    constraints.maxWidth,
                  ),
                  child: NavigationBar(
                    selectedIndex: _index,
                    onDestinationSelected: (i) {
                      if (i != _index) setState(() => _index = i);
                    },
                    destinations: [
                      for (final t in _tabs)
                        NavigationDestination(
                          key: t.key,
                          icon: Icon(t.icon),
                          label: t.label(l10n),
                        ),
                    ],
                  ),
                ),
          ),
        ),
      ),
    );
  }
}
