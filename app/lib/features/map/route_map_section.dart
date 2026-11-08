import 'package:adapters/adapters.dart';
import 'package:core/core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../ui/ui.dart';
import 'map_consent_scope.dart';
import 'map_source_holder.dart';

/// Farben der Routenkarte aus dem App-Theme. Das Kartenmaterial (OpenFreeMap "liberty") ist hell, auch im dunklen
/// Theme; Linie und Marken nehmen deshalb die Farben der hellen Palette, damit sie auf dem Kartengrund lesbar bleiben.
RouteMapStyle routeMapStyle(BuildContext context) {
  const c = RamuriColors.light;
  return RouteMapStyle(
    lineColor: c.accent,
    startColor: c.action,
    endColor: c.danger,
    markerBorderColor: c.text,
    backgroundColor: c.track,
    attributionBackground: RamuriMapColors.attributionScrim,
    attributionForeground: c.text,
    attributionTextStyle: Theme.of(context).textTheme.labelSmall,
  );
}

/// Route eines Laufs als Karte oder als Linie (FR-0204). Die Hülle um das Kernwidget [RouteMap]: sie holt beim
/// ersten Öffnen die Einwilligung ([MapConsentController.ensureAsked]), öffnet die Kachelquelle, gibt sie beim
/// Entfernen oder Widerruf wieder frei und fällt auf die Zeichnung ([lineBuilder] mit `map == null`) zurück: ohne
/// Einwilligung, ohne Netz, bei Fehlern des Anbieters (auch wenn alle Kacheln scheitern) und solange die Karte lädt.
///
/// Mit Einwilligung und geöffneter Quelle schaltet ein Umschalter zwischen Linie und Karte; sonst gibt es ihn nicht.
class RouteMapSection extends StatefulWidget {
  const RouteMapSection({
    super.key,
    required this.route,
    required this.lineBuilder,
  });

  final List<List<RoutePoint>> route;

  /// Baut die Zeichnung der Route; mit [map] an der Stelle der Zeichnung die Karte, [style] sind dann deren Farben.
  final Widget Function(BuildContext context, Widget? map, RouteMapStyle? style)
  lineBuilder;

  @override
  State<RouteMapSection> createState() => _RouteMapSectionState();
}

enum _View { line, map }

class _RouteMapSectionState extends State<RouteMapSection>
    with WidgetsBindingObserver {
  late final MapSourceHolder _holder = MapSourceHolder(
    askContext: () => mounted ? context : null,
  )..addListener(_onHolder);
  _View _view = _View.map;
  bool _foreground = true;
  bool _routeCurrent = true;

  /// Pause (ADR-0009 Punkt 5, nur im Vordergrund): App im Hintergrund oder Route verdeckt. Dann baut die Hülle die
  /// Karte nicht, es gibt keine Kachelanfragen (auch keine Wiederholungen der Bibliothek); die Quelle bleibt offen.
  bool get _paused => !_foreground || !_routeCurrent;

  @override
  void initState() {
    super.initState();
    final life = WidgetsBinding.instance.lifecycleState;
    _foreground = life == null || life == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final fg = state == AppLifecycleState.resumed;
    if (fg == _foreground) return;
    setState(() => _foreground = fg);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _routeCurrent = ModalRoute.of(context)?.isCurrent ?? true;
    _holder.bind(MapConsentScope.of(context));
    _holder.setWanted(_hasRoute);
  }

  @override
  void didUpdateWidget(RouteMapSection old) {
    super.didUpdateWidget(old);
    _holder.setWanted(_hasRoute);
  }

  bool get _hasRoute => widget.route.any((p) => p.isNotEmpty);

  void _onHolder() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _holder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final source = _holder.usable;
    final canToggle = source != null;
    final showMap = canToggle && _view == _View.map && !_paused;
    final style = routeMapStyle(context);
    Widget? map;
    if (showMap) {
      final parts = widget.route.where((p) => p.length >= 2).length;
      map = Semantics(
        container: true,
        label: l10n.mapRouteSemantics(parts, source.attribution),
        excludeSemantics: true,
        child: RouteMap(
          key: const Key('route_map'),
          source: source,
          route: widget.route,
          style: style,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (canToggle)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: RamuriSegmentedToggle<_View>(
              key: const Key('route_view_toggle'),
              expanded: true,
              semanticLabel: l10n.mapViewToggle,
              selected: _view,
              onChanged: (v) => setState(() => _view = v),
              segments: [
                RamuriSegment(value: _View.line, label: l10n.mapViewLine),
                RamuriSegment(value: _View.map, label: l10n.mapViewMap),
              ],
            ),
          ),
        widget.lineBuilder(context, map, showMap ? style : null),
      ],
    );
  }
}
