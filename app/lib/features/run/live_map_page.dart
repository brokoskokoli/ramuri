import 'package:adapters/adapters.dart';
import 'package:core/core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../ui/ui.dart';
import '../map/map_consent_scope.dart';
import '../map/map_source_holder.dart';
import '../settings/unit_format.dart';
import '../summary/run_charts.dart' show RoutePainter;
import 'live_run_values.dart' show splitUnit;
import 'live_run_view.dart'
    show formatClock, livePaceText, averagePaceSecondsPerKm;
import 'run_controller.dart';

/// Höchstzahl der Punkte, die die Karte zeichnet (nur Anzeige; die Daten bleiben unverändert).
const int liveMapMaxPoints = 600;

/// Nur für Tests: wie oft die Strecke der Kartenseite neu berechnet wurde.
@visibleForTesting
int liveMapRouteBuilds = 0;

/// Farben der Live-Karte (`LiveKarte.dc.html`): schwarze Linie, weißer Start, Glutpunkt als Position. Das
/// Kartenmaterial ist hell, auch im dunklen Theme; die Farben stammen darum aus der hellen Palette.
RouteMapStyle liveMapStyle(BuildContext context) {
  const c = RamuriColors.light;
  return RouteMapStyle(
    lineColor: c.text,
    startColor: c.surface,
    endColor: c.emberDot,
    positionColor: c.emberDot,
    markerBorderColor: c.text,
    backgroundColor: c.track,
    attributionBackground: RamuriMapColors.attributionScrim,
    attributionForeground: c.text,
    attributionTextStyle: Theme.of(context).textTheme.labelSmall,
    lineWidth: 6,
    markerRadius: 7,
    markerBorderWidth: 3,
  );
}

/// Zweite Seite des Lauf-Bildschirms (WP13 C, FR-0204): Karte, die der Position folgt, mit der bisherigen Strecke,
/// unten ein Blatt mit den wichtigsten Werten und Pause. Die Seite liest nur den Stand des [RunController]; die
/// Aufzeichnung kennt sie nicht (ADR-0005).
///
/// Gezeichnet wird nur, solange die Seite sichtbar ([visible]) und die App im Vordergrund ist: sonst gibt es keine
/// Karte, keine Kachelanfrage und keine Neuberechnung der Strecke; beim Zurückkehren holt der erste Bau auf. Die
/// Einwilligung wird erst gefragt, wenn die Seite zum ersten Mal sichtbar ist. Ohne Einwilligung, Netz oder bei
/// Fehlern zeigt die Seite die Linie ohne Karte mit der Position und demselben Blatt.
class LiveMapPage extends StatefulWidget {
  const LiveMapPage({
    super.key,
    required this.controller,
    required this.formatter,
    required this.visible,
    required this.onBack,
  });

  final RunController controller;
  final UnitFormatter formatter;
  final bool visible;

  /// Wisch vom linken Rand: zurück zur Werte-Seite.
  final VoidCallback onBack;

  @override
  State<LiveMapPage> createState() => _LiveMapPageState();
}

class _LiveMapPageState extends State<LiveMapPage> with WidgetsBindingObserver {
  late final MapSourceHolder _holder = MapSourceHolder(
    askContext: () => mounted ? context : null,
  )..addListener(_onHolder);
  bool _foreground = true;
  bool _following = true;
  List<List<RoutePoint>> _route = const [];
  Object? _routeKey;

  bool get _active => widget.visible && _foreground;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final life = WidgetsBinding.instance.lifecycleState;
    _foreground = life == null || life == AppLifecycleState.resumed;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _holder.bind(MapConsentScope.of(context));
    _holder.setWanted(_active);
  }

  @override
  void didUpdateWidget(LiveMapPage old) {
    super.didUpdateWidget(old);
    if (old.visible && !widget.visible) _following = true;
    _holder.setWanted(_active);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final fg = state == AppLifecycleState.resumed;
    if (fg == _foreground) return;
    setState(() {
      _foreground = fg;
      if (!fg) _following = true; // Die Karte wird beim Zurückkehren neu auf die Position gesetzt.
    });
    _holder.setWanted(_active);
  }

  void _onHolder() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _holder.dispose();
    super.dispose();
  }

  /// Strecke aus den akzeptierten Positionen, an Pausen und Lücken geteilt und für die Anzeige ausgedünnt. Rechnet
  /// nur bei Änderung neu und nur, solange die Seite aktiv ist (beim Zurückkehren einmal aufholen).
  void _refreshRoute() {
    final pre = widget.controller.preprocessing;
    if (pre == null) return;
    final pauses = [
      for (final g in widget.controller.snapshot.gaps)
        if (g.kind == RunGapKind.manualPause)
          TimeSpan(start: g.start, end: g.end ?? DateTime.utc(9999)),
    ];
    final key = (
      pre.position.acceptedPoints.length,
      pre.position.gaps.length,
      pre.pace.segments.length,
      pauses.length,
      pauses.isNotEmpty && pauses.last.end.year == 9999,
    );
    if (key == _routeKey) return;
    _routeKey = key;
    liveMapRouteBuilds++;
    _route = buildLiveRoute(pre, pauses: pauses, maxPoints: liveMapMaxPoints);
  }

  RoutePoint? get _position {
    for (final part in _route.reversed) {
      if (part.isNotEmpty) return part.last;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = RamuriColors.of(context);
    if (_active) _refreshRoute();
    final position = _position;
    final style = liveMapStyle(context);
    final source = _holder.usable;
    final mapShown = _active && source != null && position != null;

    Widget body;
    if (!_active) {
      body = ColoredBox(color: style.backgroundColor);
    } else if (mapShown) {
      body = Semantics(
        container: true,
        label: l10n.mapLiveSemantics(source.attribution),
        excludeSemantics: true,
        child: LiveRouteMap(
          key: const Key('live_route_map'),
          source: source,
          route: _route,
          position: position,
          following: _following,
          onUserMove: () => setState(() => _following = false),
          style: style,
        ),
      );
    } else {
      body = _LineFallback(route: _route, style: style);
    }

    return Column(
      children: [
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              body,
              Positioned(
                right: 16,
                top: 16 + 8,
                child: _GpsChip(controller: widget.controller),
              ),
              if (mapShown && !_following)
                Positioned(
                  right: 16,
                  bottom: 40,
                  child: _FloatingButton(
                    key: const Key('live_map_center'),
                    semanticLabel: l10n.mapCenter,
                    icon: Icons.my_location_outlined,
                    onPressed: () => setState(() => _following = true),
                  ),
                ),
              // Wisch vom Rand zurück zur Werte-Seite; die Karte selbst nimmt Ein-Finger-Züge für das Verschieben.
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: 24,
                child: GestureDetector(
                  key: const Key('live_map_edge'),
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragEnd: (d) {
                    if ((d.primaryVelocity ?? 0) > 150) widget.onBack();
                  },
                ),
              ),
            ],
          ),
        ),
        _Sheet(
          controller: widget.controller,
          formatter: widget.formatter,
          colors: colors,
        ),
      ],
    );
  }
}

/// Linie ohne Kartenhintergrund mit Position (ohne Einwilligung, ohne Netz, bei Fehlern, vor der Quelle).
class _LineFallback extends StatelessWidget {
  const _LineFallback({required this.route, required this.style});

  final List<List<RoutePoint>> route;
  final RouteMapStyle style;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final parts = route.where((p) => p.length >= 2).length;
    final has = route.any((p) => p.isNotEmpty);
    return ColoredBox(
      color: style.backgroundColor,
      child: has
          ? Semantics(
              container: true,
              label: l10n.mapLiveLineSemantics(parts),
              excludeSemantics: true,
              child: Padding(
                padding: const EdgeInsets.only(top: 72),
                child: CustomPaint(
                  key: const Key('live_map_line'),
                  size: Size.infinite,
                  painter: RoutePainter(
                    route: route,
                    lineColor: style.lineColor,
                    startColor: style.startColor,
                    endColor: style.positionColor ?? style.endColor,
                  ),
                ),
              ),
            )
          : Center(
              child: Text(
                l10n.mapWaitingPosition,
                key: const Key('live_map_waiting'),
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: RamuriColors.light.text),
              ),
            ),
    );
  }
}

class _GpsChip extends StatelessWidget {
  const _GpsChip({required this.controller});
  final RunController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = RamuriColors.of(context);
    final s = controller.snapshot;
    final text = controller.locationError
        ? l10n.runGpsError
        : s.positionLost
        ? l10n.runGpsLost
        : controller.hasFix
        ? l10n.runGpsOk
        : l10n.runGpsSearching;
    final good =
        !controller.locationError && !s.positionLost && controller.hasFix;
    return DecoratedBox(
      key: const Key('live_map_gps'),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: RamuriMapColors.floatingShadow,
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: good ? c.accent : c.danger,
                shape: BoxShape.circle,
              ),
              child: const SizedBox.square(dimension: 8),
            ),
            const SizedBox(width: 6),
            Text(
              text,
              style: Theme.of(context).textTheme.labelMedium
                  ?.copyWith(color: c.text, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

class _FloatingButton extends StatelessWidget {
  const _FloatingButton({
    super.key,
    required this.semanticLabel,
    required this.icon,
    required this.onPressed,
  });

  final String semanticLabel;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = RamuriColors.of(context);
    return Semantics(
      button: true,
      label: semanticLabel,
      excludeSemantics: true,
      child: Material(
        color: c.surface,
        shape: const CircleBorder(),
        elevation: 3,
        shadowColor: RamuriMapColors.floatingShadow,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox.square(
            dimension: 48,
            child: Icon(icon, size: 22, color: c.text),
          ),
        ),
      ),
    );
  }
}

/// Blatt unter der Karte: Zeit und Strecke groß, drei Werte, Runde und Pause (`LiveKarte.dc.html`).
class _Sheet extends StatelessWidget {
  const _Sheet({
    required this.controller,
    required this.formatter,
    required this.colors,
  });

  final RunController controller;
  final UnitFormatter formatter;
  final RamuriColors colors;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final label = dark ? colors.textMuted : RamuriMapColors.sheetLabelLight;
    final handle = dark
        ? colors.outlineStrong
        : RamuriMapColors.sheetHandleLight;
    final s = controller.snapshot;
    final text = Theme.of(context).textTheme;
    final avg = averagePaceSecondsPerKm(s);
    final bpm = s.heartRateBpm;
    final zone = controller.zone;
    final zoneNo = zone.kind == LiveZoneKind.zone ? zone.zone : null;
    final paused = controller.phase == RecordingPhase.paused;

    Widget big(Key key, String title, String value, {bool end = false}) =>
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: end ? Alignment.bottomRight : Alignment.bottomLeft,
            child: Column(
              crossAxisAlignment: end
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: text.labelMedium?.copyWith(
                    color: label,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  value,
                  key: key,
                  maxLines: 1,
                  style: RamuriType.of(context).sheetValue,
                ),
              ],
            ),
          ),
        );

    // Die Einheit steht in der Beschriftung (zweizeilig erlaubt), die Zahl
    // darunter ohne Einheit; sie schrumpft nur, wenn sie nicht passt, und
    // steht unten, damit die Zahlen einer Reihe auf einer Höhe stehen.
    Widget tile(Key key, String title, String value, [String? unit]) =>
        Expanded(
          child: Semantics(
            container: true,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text.rich(
                      labelWithUnit(title, unit),
                      style: text.labelSmall?.copyWith(
                        color: colors.textMuted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        value,
                        key: key,
                        maxLines: 1,
                        softWrap: false,
                        style: text.titleLarge?.copyWith(color: colors.text),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );

    (String, String?) paceOf(String shown) =>
        splitUnit(shown, formatter.paceLabel);
    final (paceValue, paceUnit) = paceOf(
      livePaceText(controller, formatter, l10n),
    );
    final (avgValue, avgUnit) = avg == null
        ? (l10n.runNoDataYet, null)
        : paceOf(formatter.pace(avg));

    return DecoratedBox(
      key: const Key('live_map_sheet'),
      decoration: BoxDecoration(
        color: colors.accentPanel,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: handle,
                  borderRadius: BorderRadius.circular(3),
                ),
                child: const SizedBox(width: 40, height: 5),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  big(
                    const Key('live_map_time'),
                    l10n.runTime,
                    formatClock(s.totalTime),
                  ),
                  big(
                    const Key('live_map_distance'),
                    l10n.runDistance,
                    s.distanceMeters == null
                        ? l10n.runNoDataYet
                        : formatter.distance(s.distanceMeters),
                    end: true,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    tile(
                      const Key('live_map_pace'),
                      l10n.runPace,
                      paceValue,
                      paceUnit,
                    ),
                    const SizedBox(width: 8),
                    tile(
                      const Key('live_map_avg_pace'),
                      l10n.runAvgPace,
                      avgValue,
                      avgUnit,
                    ),
                    const SizedBox(width: 8),
                    tile(
                      const Key('live_map_hr'),
                      zoneNo == null
                          ? l10n.runHeartRate
                          : '${l10n.runHeartRate} · Z$zoneNo',
                      bpm == null ? UnitFormatter.noValue : '$bpm',
                      bpm == null ? null : l10n.liveUnitBpm,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  LiveRoundButton(
                    key: const Key('live_map_lap'),
                    semanticLabel: l10n.runLap,
                    size: 60,
                    background: colors.surface,
                    foreground: colors.text,
                    icon: Icons.flag_outlined,
                    onPressed: paused ? null : controller.lap,
                  ),
                  const SizedBox(width: 24),
                  LiveRoundButton(
                    key: Key(paused ? 'live_map_resume' : 'live_map_pause'),
                    semanticLabel: paused ? l10n.runResume : l10n.runPause,
                    size: 84,
                    background: dark ? colors.action : colors.panel,
                    foreground: dark ? colors.onAction : colors.action,
                    icon: paused
                        ? Icons.play_arrow_rounded
                        : Icons.pause_rounded,
                    iconSize: 36,
                    onPressed: paused ? controller.resume : controller.pause,
                  ),
                  const SizedBox(width: 24),
                  const SizedBox(width: 60),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Runder Knopf der Lauf-Seiten (Werte und Karte).
class LiveRoundButton extends StatelessWidget {
  const LiveRoundButton({
    super.key,
    required this.semanticLabel,
    required this.size,
    required this.background,
    required this.foreground,
    required this.icon,
    required this.onPressed,
    this.iconSize = 24,
  });

  final String semanticLabel;
  final double size;
  final Color background;
  final Color foreground;
  final IconData icon;
  final double iconSize;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: semanticLabel,
      onTap: onPressed,
      excludeSemantics: true,
      child: Opacity(
        opacity: onPressed == null ? 0.4 : 1,
        child: Material(
          color: background,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: SizedBox.square(
              dimension: size,
              child: Icon(icon, size: iconSize, color: foreground),
            ),
          ),
        ),
      ),
    );
  }
}
