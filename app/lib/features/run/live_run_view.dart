import 'package:core/core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../ui/ui.dart';
import '../settings/unit_format.dart';
import '../history/run_detail_screen.dart';
import '../recalculation/recalculation_controller.dart';
import '../summary/run_summary_body.dart';
import '../summary/run_summary_page.dart';
import '../summary/warning_entry.dart';
import 'live_map_page.dart';
import 'live_run_values.dart';
import 'run_controller.dart';

/// Zeit als `h:mm:ss`, unter einer Stunde `m:ss`; `null` ergibt „–“.
String formatClock(Duration? d) {
  if (d == null || d.isNegative) return UnitFormatter.noValue;
  final s = d.inSeconds;
  final h = s ~/ 3600;
  final mm = ((s % 3600) ~/ 60).toString().padLeft(2, '0');
  final ss = (s % 60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$mm:$ss' : '${s ~/ 60}:$ss';
}

/// Durchschnittspace in Sekunden je Kilometer aus Bewegungszeit und Strecke;
/// `null`, solange eines von beiden fehlt oder die Strecke 0 ist. Zeit in
/// GPS-Lücken zählt nicht mit, soweit sie in der Bewegungszeit liegt: Sie hat
/// keine gemessene Strecke und würde den Schnitt sonst zu langsam machen. Eine
/// Lücke im erkannten Stillstand steckt nicht in der Bewegungszeit und wird
/// darum nicht abgezogen. Die Spec
/// schweigt dazu (Entscheidung des Coders, WP10 abstimmen).
double? averagePaceSecondsPerKm(RecordingSnapshot s) {
  final moving = s.movingTime;
  final d = s.distanceMeters;
  if (moving == null || d == null || d <= 0) return null;
  final t = moving - s.positionLossMovingTime;
  if (t <= Duration.zero) return null;
  return t.inMicroseconds / 1e6 / (d / 1000);
}

/// Aktuelle Pace als Text (Werte-Seite und Blatt der Kartenseite).
String livePaceText(
  RunController controller,
  UnitFormatter formatter,
  AppLocalizations l10n,
) {
  switch (controller.preprocessing?.pace.livePace) {
    case PaceValue(:final secondsPerKm):
      return formatter.pace(secondsPerKm);
    case PaceStandstill():
      return UnitFormatter.noValue; // OQ-0037
    case PaceNoData() || null:
      return l10n.runNoDataYet;
  }
}

/// Live-Bildschirm und Abschlussansicht eines Laufs.
class LiveRunView extends StatelessWidget {
  const LiveRunView({
    super.key,
    required this.controller,
    required this.formatter,
    this.clock,
    this.recalculation,
  });

  final RunController controller;
  final UnitFormatter formatter;

  /// Uhr für die Zusammenfassung nach dem Lauf; ohne sie zeigt die
  /// Abschlussansicht nur die Werte der Aufzeichnung.
  final Clock? clock;

  /// Für „Details“ nach dem Lauf; ohne sie fehlt der Knopf.
  final RecalculationController? recalculation;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = RamuriColors.of(context);
    final finished = controller.phase == RecordingPhase.finished;
    final paused = controller.phase == RecordingPhase.paused;
    return _BackAsk(
      controller: controller,
      finished: finished,
      onFinishBack: () => _confirmFinish(context),
      child: Scaffold(
        // Design „Live“: Minzgrund im Lauf, grauer Grund in der Pause.
        backgroundColor: finished
            ? null
            : paused
            ? c.segmentTrack
            : c.accentPanel,
        body: SafeArea(
          child: finished
              ? _valuesPage(context, l10n, finished)
              : _LiveRunPager(
                  values: _valuesPage(context, l10n, finished),
                  controller: controller,
                  formatter: formatter,
                ),
        ),
      ),
    );
  }

  /// Die Werte-Seite: Meldungen, Werte und unten die Knöpfe. Beim Wischen zur Karte bleibt sie unberührt.
  Widget _valuesPage(
    BuildContext context,
    AppLocalizations l10n,
    bool finished,
  ) {
    return Column(
      children: [
        Expanded(
          child: ListView(
            // Oben Platz für die Reiter Werte/Karte, die über der Seite schweben.
            padding: EdgeInsets.fromLTRB(16, finished ? 16 : 72, 16, 16),
            children: finished
                ? [
                    _title(context, l10n),
                    ..._banners(context, l10n),
                    ..._body(l10n),
                  ]
                : [LiveValues(controller: controller, formatter: formatter)],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: finished
              ? _doneButtons(context, l10n)
              : _controls(context, l10n),
        ),
      ],
    );
  }

  /// Überschrift der Abschlussseite.
  Widget _title(BuildContext context, AppLocalizations l10n) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Semantics(
      header: true,
      child: Text(l10n.runDoneTitle, style: RamuriType.of(context).pageTitle),
    ),
  );

  /// „Fertig“ schließt nur die Seite und ändert keine Daten; „Details“ öffnet
  /// die Detailansicht des Laufs. Wurde der Lauf dort gelöscht, schließt auch
  /// diese Seite.
  Widget _doneButtons(BuildContext context, AppLocalizations l10n) {
    final c = RamuriColors.of(context);
    final id = controller.runId;
    final clock = this.clock;
    final recalculation = this.recalculation;
    final canOpen = id != null && clock != null && recalculation != null;
    return Row(
      children: [
        Expanded(
          child: FilledButton(
            key: const Key('run_done_close'),
            style: FilledButton.styleFrom(
              backgroundColor: c.action,
              foregroundColor: c.onAction,
              minimumSize: const Size(0, 58),
              shape: const StadiumBorder(),
              textStyle: Theme.of(context).textTheme.labelLarge,
            ),
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.runDoneClose),
          ),
        ),
        if (canOpen) ...[
          const SizedBox(width: 10),
          OutlinedButton(
            key: const Key('run_done_details'),
            style: OutlinedButton.styleFrom(
              foregroundColor: c.text,
              side: BorderSide(color: c.outline),
              minimumSize: const Size(0, 58),
              padding: const EdgeInsets.symmetric(horizontal: 22),
              shape: const StadiumBorder(),
              textStyle: Theme.of(context).textTheme.labelLarge,
            ),
            onPressed: () async {
              final navigator = Navigator.of(context);
              final deleted = await navigator.push<bool>(
                MaterialPageRoute(
                  builder: (_) => RunDetailScreen(
                    session: controller.storage,
                    clock: clock,
                    recalculation: recalculation,
                    runId: id,
                  ),
                ),
              );
              if (deleted == true && navigator.mounted) navigator.pop();
            },
            child: Text(l10n.summaryDetails),
          ),
        ],
      ],
    );
  }

  /// Nach dem Ende die Zusammenfassung (FR-0037), sobald die Berechnung durch
  /// ist; sonst (und bei Fehlern beim Lesen) die Werte der Aufzeichnung.
  List<Widget> _body(AppLocalizations l10n) {
    final id = controller.runId;
    final clock = this.clock;
    if (id == null || clock == null) return _metrics(l10n);
    if (!controller.calculationSettled) {
      return [
        const SizedBox(height: 24),
        const Center(child: CircularProgressIndicator()),
        const SizedBox(height: 12),
        Center(child: Text(l10n.sumLoading, key: const Key('sum_loading'))),
      ];
    }
    return [
      RunSummaryBody(
        key: ValueKey(id),
        session: controller.storage,
        clock: clock,
        runId: id,
        fallback: () => _metrics(l10n),
        contentBuilder: (context, summary, detail, _) => RunSummaryPage(
          summary: summary,
          detail: detail,
          formatter: formatter,
          session: controller.storage,
          runId: id,
          subjective: SubjectiveService(
            session: controller.storage,
            clock: clock,
          ),
          onWarningYes: warningEntry(
            session: controller.storage,
            clock: clock,
            runId: id,
          ),
        ),
      ),
    ];
  }

  /// Hinweis der Abschlussansicht; die Hinweise im Lauf zeigt [LiveValues].
  List<Widget> _banners(BuildContext context, AppLocalizations l10n) {
    final failed = controller.writeFailure != null;
    return [
      LiveBanner(
        Text(
          failed ? l10n.runDoneSaveProblem : l10n.runDoneSaved,
          key: const Key('run_done_status'),
        ),
        error: failed,
      ),
      // Abstand wie zwischen den Blöcken der Zusammenfassung.
      const SizedBox(height: 16),
    ];
  }

  /// Werte der Abschlussansicht ohne Zusammenfassung (Fallback); Teil C
  /// ersetzt sie.
  List<Widget> _metrics(AppLocalizations l10n) {
    final s = controller.snapshot;
    final pre = controller.preprocessing;
    final na = l10n.runUnavailable;
    final avg = averagePaceSecondsPerKm(s);
    final ascent = pre?.altitude.ascentMeters;
    final gapCount = s.gaps
        .where((g) => g.kind == RunGapKind.positionLoss)
        .length;

    return [
      _Metric('run_time', l10n.runTime, formatClock(s.totalTime), big: true),
      _Metric(
        'run_distance',
        l10n.runDistance,
        s.distanceMeters == null
            ? l10n.runNoDataYet
            : formatter.distance(s.distanceMeters),
        big: true,
      ),
      _Metric('run_moving_time', l10n.runMovingTime, formatClock(s.movingTime)),
      _Metric(
        'run_avg_pace',
        l10n.runAvgPace,
        avg == null ? l10n.runNoDataYet : formatter.pace(avg),
      ),
      if (gapCount > 0)
        _Metric('run_gaps', l10n.runGps, l10n.runGpsGaps(gapCount)),
      _Metric(
        'run_ascent',
        l10n.runAscent,
        ascent == null ? na : formatter.elevation(ascent),
      ),
      // FR-0202: Wert nur mit Berechtigung und Sensor, sonst „nicht verfügbar“.
      _Metric('run_cadence', l10n.runCadence, switch ((
        controller.cadenceAvailability,
        controller.cadenceStepsPerMinute,
      )) {
        (CadenceAvailability.available, final spm?) => l10n.runSpm(spm.round()),
        (CadenceAvailability.available, null) => l10n.runNoDataYet,
        _ => na,
      }),
      const SizedBox(height: 8),
      LiveLaps(laps: s.laps),
    ];
  }

  /// Läuft: Runde und Pause. Pausiert: Weiter und Beenden (FR-0028), die
  /// Runde ist in der Pause gesperrt und entfällt.
  Widget _controls(BuildContext context, AppLocalizations l10n) {
    final paused = controller.phase == RecordingPhase.paused;
    final c = RamuriColors.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final mainBackground = dark ? c.action : c.panel;
    final mainForeground = dark ? c.onAction : c.action;
    if (!paused) {
      // Auf sehr schmalen Schirmen (320 dp) etwas kleiner statt Überlauf.
      return FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            LiveRoundButton(
              key: const Key('run_lap'),
              semanticLabel: l10n.runLap,
              size: 68,
              background: c.surface,
              foreground: c.text,
              icon: Icons.flag_outlined,
              iconSize: 26,
              onPressed: controller.lap,
            ),
            const SizedBox(width: 28),
            LiveRoundButton(
              key: const Key('run_pause'),
              semanticLabel: l10n.runPause,
              size: 104,
              background: mainBackground,
              foreground: mainForeground,
              icon: Icons.pause_rounded,
              iconSize: 36,
              onPressed: controller.pause,
            ),
            const SizedBox(width: 28),
            const SizedBox(width: 68),
          ],
        ),
      );
    }
    ButtonStyle pill(Color background, Color foreground) =>
        FilledButton.styleFrom(
          backgroundColor: background,
          foregroundColor: foreground,
          minimumSize: const Size(0, 64),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          shape: const StadiumBorder(),
          textStyle: Theme.of(context).textTheme.labelLarge,
        );
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            key: const Key('run_resume'),
            style: pill(mainBackground, mainForeground),
            onPressed: controller.resume,
            icon: const Icon(Icons.play_arrow_rounded, size: 22),
            label: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(l10n.liveResume, maxLines: 1, softWrap: false),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton.icon(
            key: const Key('run_finish'),
            style: pill(c.surface, c.text),
            onPressed: () => _confirmFinish(context),
            icon: const Icon(Icons.stop_rounded, size: 22),
            label: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(l10n.runFinish, maxLines: 1, softWrap: false),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _confirmFinish(BuildContext context) async {
    // FR-0028: Beenden nur im pausierten Zustand.
    if (controller.phase != RecordingPhase.paused) return;
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.runFinishTitle),
        content: Text(l10n.runFinishBody),
        actions: [
          TextButton(
            key: const Key('run_finish_cancel'),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.runFinishCancel),
          ),
          FilledButton(
            key: const Key('run_finish_confirm'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.runFinishConfirm),
          ),
        ],
      ),
    );
    if (ok == true) await controller.finish();
  }
}

bool _isRunning(RecordingPhase p) =>
    p == RecordingPhase.running || p == RecordingPhase.autoPaused;

/// Zurück-Taste des Lauf-Bildschirms (FR-0028, OQ-0076). Abgeschlossen: normales
/// Schließen. Pausiert: Rückfrage zum Beenden. Laufend (auch Autopause): „Lauf
/// pausieren?“. Ohne Antwort, bei „Weiterlaufen“, außerhalb des Dialogs und bei
/// erneutem Zurück geht kein Befehl an die Aufzeichnung.
class _BackAsk extends StatefulWidget {
  const _BackAsk({
    required this.controller,
    required this.finished,
    required this.onFinishBack,
    required this.child,
  });

  final RunController controller;
  final bool finished;
  final VoidCallback onFinishBack;
  final Widget child;

  @override
  State<_BackAsk> createState() => _BackAskState();
}

class _BackAskState extends State<_BackAsk> {
  bool _asking = false;

  Future<void> _askPause() async {
    // Schreibfenster nach „Pausieren“: Der Dialog ist zu, die Phase noch
    // „laufend“; ein Zurück dort öffnet keine zweite Rückfrage. (Zwei Zurück im
    // selben Takt verwirft schon der Navigator, dafür braucht es den Wächter nicht.)
    if (_asking) return;
    _asking = true;
    final controller = widget.controller;
    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => _PauseAskDialog(controller: controller),
      );
      // Wechselte der Zustand während der Rückfrage (Pause, Ende), wirkt die
      // Antwort nicht mehr; sie führt nie zu einem falschen Befehl.
      if (ok == true && _isRunning(controller.phase)) {
        await controller.pause();
      }
    } finally {
      _asking = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: widget.finished,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        final phase = widget.controller.phase;
        if (phase == RecordingPhase.paused) {
          widget.onFinishBack();
        } else if (_isRunning(phase)) {
          _askPause();
        }
      },
      child: widget.child,
    );
  }
}

/// „Lauf pausieren?“. Endet der Lauf oder wird er pausiert, während der Dialog
/// offen ist, schließt er sich ohne Antwort.
class _PauseAskDialog extends StatefulWidget {
  const _PauseAskDialog({required this.controller});

  final RunController controller;

  @override
  State<_PauseAskDialog> createState() => _PauseAskDialogState();
}

class _PauseAskDialogState extends State<_PauseAskDialog> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  // Nach der Antwort läuft die Schließanimation noch, der Zuhörer hängt aber
  // noch am Controller: nur eine noch aktive Route wird geschlossen, sonst
  // träfe pop() die Seite darunter.
  void _changed() {
    if (!mounted || _isRunning(widget.controller.phase)) return;
    final route = ModalRoute.of(context);
    if (route != null && route.isActive) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.runPauseAskTitle),
      actions: [
        TextButton(
          key: const Key('run_pause_ask_stay'),
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.runPauseAskStay),
        ),
        FilledButton(
          key: const Key('run_pause_ask_confirm'),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.runPauseAskConfirm),
        ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric(this.id, this.label, this.value, {this.big = false});

  final String id;
  final String label;
  final String value;
  final bool big;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(flex: 2, child: Text(label, style: theme.bodyMedium)),
          Expanded(
            flex: 3,
            child: Text(
              value,
              key: Key(id),
              textAlign: TextAlign.end,
              style: big ? theme.headlineSmall : theme.titleMedium,
            ),
          ),
        ],
      ),
    );
  }
}

/// Die zwei Seiten des laufenden Lauf-Bildschirms: Werte (erste) und Karte (zweite), dazu die Reiter. Der Seitenwechsel
/// ändert nichts am Zustand des Laufs; beide Seiten lesen nur den [RunController].
///
/// Wischen und Verschieben: Auf der Werte-Seite wischt ein Zug nach links zur Karte. Auf der Karte gehört ein Finger
/// der Karte (Verschieben): ihre Gestenerkennung gewinnt gegen die der Seite (belegt im Test, langsamer und schneller
/// Zug). Zurück geht es mit dem Reiter, mit einem Wisch auf dem Blatt oder vom linken Rand der Karte (eigener
/// Streifen in [LiveMapPage]).
class _LiveRunPager extends StatefulWidget {
  const _LiveRunPager({
    required this.values,
    required this.controller,
    required this.formatter,
  });

  final Widget values;
  final RunController controller;
  final UnitFormatter formatter;

  @override
  State<_LiveRunPager> createState() => _LiveRunPagerState();
}

class _LiveRunPagerState extends State<_LiveRunPager> {
  final PageController _pages = PageController();
  int _page = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _go(int page) {
    _pages.animateToPage(
      page,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Stack(
      children: [
        PageView(
          key: const Key('run_pages'),
          controller: _pages,
          allowImplicitScrolling: true, // die Karte behält Quelle und Zustand, auch wenn sie nicht zu sehen ist
          onPageChanged: (p) => setState(() => _page = p),
          children: [
            widget.values,
            LiveMapPage(
              key: const Key('run_page_map'),
              controller: widget.controller,
              formatter: widget.formatter,
              visible: _page == 1,
              onBack: () => _go(0),
            ),
          ],
        ),
        Positioned(
          left: 16,
          top: 16,
          child: _Tabs(
            semanticLabel: l10n.mapTabsSemantics,
            labels: [l10n.mapTabValues, l10n.mapViewMap],
            selected: _page,
            onSelected: _go,
          ),
        ),
      ],
    );
  }
}

/// Reiter Werte/Karte (`LiveKarte.dc.html`): weiße Kapsel, der gewählte Reiter dunkel mit Minze.
class _Tabs extends StatelessWidget {
  const _Tabs({
    required this.semanticLabel,
    required this.labels,
    required this.selected,
    required this.onSelected,
  });

  final String semanticLabel;
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final c = RamuriColors.of(context);
    final text = Theme.of(context).textTheme;
    return Semantics(
      container: true,
      label: semanticLabel,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(22),
          boxShadow: const [
            BoxShadow(
              color: RamuriMapColors.floatingShadow,
              blurRadius: 10,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < labels.length; i++) ...[
                if (i > 0) const SizedBox(width: 4),
                Semantics(
                  button: true,
                  selected: i == selected,
                  child: GestureDetector(
                    key: Key('run_tab_$i'),
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onSelected(i),
                    // Tippfläche 48 dp (FR-0205); sichtbar bleiben 40 dp.
                    child: SizedBox(
                      height: 48,
                      child: Center(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: i == selected ? c.panel : null,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: SizedBox(
                            height: 40,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              child: Center(
                                child: Text(
                                  labels[i],
                                  style: text.labelLarge?.copyWith(
                                    color: i == selected ? c.action : c.text,
                                    fontWeight: i == selected
                                        ? FontWeight.w800
                                        : FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
