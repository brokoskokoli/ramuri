import 'package:adapters/adapters.dart';
import 'package:core/core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../ui/ui.dart';
import 'map_consent_controller.dart';
import 'map_consent_scope.dart';

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
/// Einwilligung, ohne Netz, bei Fehlern des Anbieters und solange die Karte lädt.
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

class _RouteMapSectionState extends State<RouteMapSection> {
  MapConsentController? _consent;
  MapTileSource? _source;
  bool _started = false;
  _View _view = _View.map;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = MapConsentScope.of(context);
    if (identical(next, _consent)) return;
    _consent?.removeListener(_onConsent);
    _consent = next;
    next?.addListener(_onConsent);
    _closeSource();
    _started = false;
    _maybeStart();
  }

  bool get _hasRoute => widget.route.any((p) => p.isNotEmpty);

  void _maybeStart() {
    final c = _consent;
    if (_started || c == null || !_hasRoute) return;
    if (c.status == MapConsentStatus.declined) return;
    _started = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _open(c));
  }

  Future<void> _open(MapConsentController c) async {
    if (!mounted || !identical(c, _consent)) return;
    final yes = await c.ensureAsked(context);
    if (!yes || !mounted || !identical(c, _consent)) return;
    MapTileSource? source;
    try {
      source = await c.openSource();
    } on MapSourceUnavailable {
      source = null; // Anbieter nicht erreichbar: bei der Linie bleiben.
    } catch (_) {
      source = null;
    }
    if (source == null) return;
    if (!mounted || !identical(c, _consent) || !c.granted) {
      source.dispose();
      return;
    }
    setState(() => _source = source);
  }

  /// Widerruf bei offener Karte: Quelle freigeben, zurück zur Linie. Die Anfragen enden schon am Tor.
  void _onConsent() {
    if (!mounted) return;
    if (_consent?.granted != true && _source != null) {
      setState(_closeSource);
    }
  }

  void _closeSource() {
    _source?.dispose();
    _source = null;
  }

  @override
  void dispose() {
    _consent?.removeListener(_onConsent);
    _closeSource();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final source = _source;
    final canToggle = source != null && (_consent?.granted ?? false);
    final showMap = canToggle && _view == _View.map;
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
