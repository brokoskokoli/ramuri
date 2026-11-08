import 'dart:typed_data';

import 'package:adapters/adapters.dart';
import 'package:core/core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../offload_scope.dart';
import '../map/miniature_service.dart';
import '../map/route_map_section.dart' show routeMapStyle;
import '../summary/run_charts.dart' show RoutePainter;

/// Größe der Miniatur im Verlauf (Seitenverhältnis wie das Bild 360 x 180).
const double runMiniatureWidth = 120;
const double runMiniatureHeight = 60;

/// Trägt die unsichtbare Karte, die gerade zu einer Miniatur aufgenommen wird: außerhalb des Bildschirms, aber
/// wirklich gemalt (kein `Offstage`, sonst gäbe es kein Bild). Zeigt nichts, solange kein Auftrag läuft.
class MiniatureHost extends StatelessWidget {
  const MiniatureHost({super.key, required this.service});

  final MiniatureService service;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<MiniatureJob?>(
      valueListenable: service.job,
      builder: (context, job, _) {
        if (job == null) return const SizedBox.shrink();
        return Positioned(
          left: -(thumbnailWidth + 100),
          top: 0,
          width: thumbnailWidth,
          height: thumbnailHeight,
          child: ExcludeSemantics(
            child: IgnorePointer(
              child: ThumbnailMap(
                key: const Key('miniature_host_map'),
                boundary: job.boundary,
                source: job.source,
                route: job.route,
                style: job.style,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Miniatur der Route eines Laufs (WP13 D): die Linie, direkt gemalt (kein Netz, kein Speicher), und mit
/// Einwilligung darüber das gespeicherte oder neu erzeugte Kartenbild. Nicht bedienbar. Die Route wird erst beim
/// Aufbau des Eintrags gelesen und nicht über den Eintrag hinaus gehalten; ein Lauf ohne Positionen (Laufband) bekommt
/// keine Miniatur.
class RunMiniature extends StatefulWidget {
  const RunMiniature({
    super.key,
    required this.session,
    required this.runId,
    this.service,
  });

  final StorageSession session;
  final int runId;

  /// Erzeugt die Kartenbilder; `null`: nur die Linie.
  final MiniatureService? service;

  @override
  State<RunMiniature> createState() => _RunMiniatureState();
}

enum _Load { loading, none, ready }

class _RunMiniatureState extends State<RunMiniature> {
  _Load _load = _Load.loading;
  List<List<RoutePoint>> _route = const [];
  Uint8List? _png;
  MiniatureTicket? _ticket;
  RouteMapStyle? _style;
  String? _variant;
  bool _started = false;
  int _epoch = 0;

  /// Das Kartenbild wurde wirklich gemalt (ein Bild kam an). Nur dann sagen Bedienungshilfe und Verlauf "Karte" und
  /// nennen die Quelle; ein Bild, das sich nicht darstellen lässt, zählt nicht (WP13 N5).
  bool _shown = false;
  bool _decodeRetried = false;

  @override
  void initState() {
    super.initState();
    widget.service?.addListener(_onService);
  }

  @override
  void didUpdateWidget(RunMiniature old) {
    super.didUpdateWidget(old);
    if (old.service != widget.service) {
      old.service?.removeListener(_onService);
      widget.service?.addListener(_onService);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final style = routeMapStyle(context);
    final variant = miniatureVariant(style);
    if (_variant != null && variant != _variant) _reset();
    _style = style;
    _variant = variant;
    if (!_started) {
      _started = true;
      _loadRoute();
    } else if (_load == _Load.ready) {
      _fetch();
    }
  }

  Future<void> _loadRoute() async {
    final offload = OffloadScope.of(context);
    List<List<RoutePoint>> route;
    try {
      route = await loadRunRoute(
        widget.session,
        widget.runId,
        offload: offload,
      );
    } on Object {
      route = const [];
    }
    if (!mounted) return;
    final has = route.any((p) => p.isNotEmpty);
    setState(() {
      _route = has ? route : const [];
      _load = has ? _Load.ready : _Load.none;
    });
    if (has) _fetch();
  }

  void _onService() {
    if (!mounted) return;
    final service = widget.service;
    if (service == null) return;
    if (!service.enabled) {
      _reset();
      setState(() {});
    } else if (_load == _Load.ready) {
      _fetch();
    }
  }

  /// Verwirft Bild und offenen Auftrag (Widerruf, anderes Aussehen).
  void _reset() {
    _epoch++;
    _ticket?.cancel();
    _ticket = null;
    _png = null;
    _setShown(false);
  }

  /// Meldet dem Dienst, ob dieser Eintrag sein Kartenbild zeigt; baut neu auf, wenn sich das ändert.
  void _setShown(bool value, {bool rebuild = true}) {
    if (_shown == value) return;
    _shown = value;
    widget.service?.imageShown(value);
    if (rebuild && mounted) setState(() {});
  }

  /// Das Bild kam nicht auf den Schirm (es ließ sich nicht entschlüsseln). Das Kartenbild zählt nicht, der Eintrag
  /// zeigt die Linie; das unlesbare Bild wird entfernt und einmal neu erzeugt (ohne Neuaufbau des Verlaufs).
  void _onImageError() {
    if (!mounted || _png == null) return;
    final service = widget.service;
    final style = _style;
    _png = null;
    _setShown(false, rebuild: false);
    setState(() {});
    if (service == null || style == null || _decodeRetried) return;
    _decodeRetried = true;
    service.discard(widget.runId, style).then((_) {
      if (mounted && _load == _Load.ready) _fetch();
    });
  }

  /// Oberkante auf dem Bildschirm, wenn der Eintrag gerade zu sehen ist, sonst `null`.
  double? _visibleTop() {
    if (!mounted) return null;
    final box = context.findRenderObject();
    final scrollable = Scrollable.maybeOf(context)?.context.findRenderObject();
    if (box is! RenderBox ||
        scrollable is! RenderBox ||
        !box.attached ||
        !scrollable.attached) {
      return null;
    }
    final tile = box.localToGlobal(Offset.zero) & box.size;
    final view = scrollable.localToGlobal(Offset.zero) & scrollable.size;
    return tile.overlaps(view) ? tile.top : null;
  }

  /// Gespeichertes Bild laden, sonst eines erzeugen lassen. Ohne Einwilligung geschieht nichts.
  Future<void> _fetch() async {
    final service = widget.service;
    final style = _style;
    if (service == null ||
        style == null ||
        !service.enabled ||
        _png != null ||
        _ticket != null) {
      return;
    }
    final epoch = ++_epoch;
    final stored = await service.stored(widget.runId, style);
    if (!mounted || epoch != _epoch) return;
    if (stored != null) {
      setState(() => _png = stored);
      return;
    }
    final ticket = service.request(
      widget.runId,
      _route,
      style,
      visibleTop: _visibleTop,
    );
    if (ticket == null) return;
    _ticket = ticket;
    final bytes = await ticket.result;
    if (!mounted || epoch != _epoch) return;
    _ticket = null;
    if (bytes != null && service.enabled) setState(() => _png = bytes);
  }

  @override
  void dispose() {
    widget.service?.removeListener(_onService);
    _ticket?.cancel();
    _setShown(false, rebuild: false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_load == _Load.none) return const SizedBox.shrink();
    final service = widget.service;
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    // Nur mit Einwilligung: Kartenbilder, die nach einem Widerruf noch liegen, werden nicht gezeigt.
    final png = (service?.enabled ?? false) ? _png : null;
    final attribution = service?.consent.services.attribution ?? '';
    final showsMap = png != null && _shown;
    final drawing = _load == _Load.ready
        ? CustomPaint(
            key: const Key('miniature_line'),
            painter: RoutePainter(
              route: _route,
              lineColor: scheme.primary,
              startColor: scheme.tertiary,
              endColor: scheme.error,
              padding: 8,
              strokeWidth: 2,
              markerRadius: 3,
            ),
          )
        : null;
    return SizedBox(
      width: runMiniatureWidth,
      child: Semantics(
        container: true,
        excludeSemantics: true,
        label: showsMap
            ? l10n.mapThumbSemantics(attribution)
            : l10n.mapThumbLineSemantics,
        child: SizedBox(
          height: runMiniatureHeight,
          width: runMiniatureWidth,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: ColoredBox(
              color: scheme.surfaceContainerHighest,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ?drawing,
                  if (png != null)
                    Image.memory(
                      png,
                      key: const Key('miniature_image'),
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      filterQuality: FilterQuality.medium,
                      frameBuilder: (_, child, frame, sync) {
                        if (frame != null || sync) {
                          WidgetsBinding.instance.addPostFrameCallback(
                            (_) => _setShown(true),
                          );
                        }
                        return child;
                      },
                      errorBuilder: (_, _, _) {
                        WidgetsBinding.instance.addPostFrameCallback(
                          (_) => _onImageError(),
                        );
                        return const SizedBox.shrink();
                      },
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
