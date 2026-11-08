import 'dart:async';

import 'package:adapters/adapters.dart';
import 'package:core/core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'map_consent_controller.dart';

/// Höchstzahl gleichzeitiger Anfragen beim Erzeugen der Miniaturen (R008 Hinweis 6, Grenzen des Anbieters).
const int miniatureMaxParallel = 4;

/// Fassung der Miniatur: bei jeder Änderung an Größe oder Aussehen hochzählen, dann entstehen neue Bilder.
const String miniatureVersion = 'v1';

/// Die Variante einer Miniatur im Schlüssel: Fassung, Größe und die Farben der Karte. Die Karte ist in beiden Themen
/// hell ([style] ist heute vom Thema unabhängig), deshalb gibt es keinen eigenen Teil für hell und dunkel; hängt der
/// Stil einmal vom Thema ab, ändert sich die Variante von selbst und es entstehen getrennte Bilder.
String miniatureVariant(RouteMapStyle style) {
  int h(Color c) => c.toARGB32() & 0xFFFFFF;
  final colors = [
    style.lineColor,
    style.startColor,
    style.endColor,
    style.markerBorderColor,
    style.backgroundColor,
  ].map((c) => h(c).toRadixString(16).padLeft(6, '0')).join();
  return '$miniatureVersion-${thumbnailWidth.round()}x${thumbnailHeight.round()}-$colors';
}

/// Nimmt eine Karte auf; Tests setzen eine schnellere ein.
typedef MiniatureCapture = Future<Uint8List?> Function(
  GlobalKey boundary,
  MapGate gate, {
  bool Function()? cancelled,
  int? failuresBefore,
});

Future<Uint8List?> _defaultCapture(
  GlobalKey boundary,
  MapGate gate, {
  bool Function()? cancelled,
  int? failuresBefore,
}) => captureThumbnail(
  boundary,
  gate,
  cancelled: cancelled,
  failuresBefore: failuresBefore,
);

/// Nur für Tests: ersetzt die Aufnahme der Karte (ohne Rendern und Netz).
@visibleForTesting
MiniatureCapture? debugMiniatureCapture;

/// Auftrag für eine Miniatur. [result] liefert das PNG oder `null` (nicht erzeugt: Fehler, Abbruch, Widerruf).
class MiniatureTicket {
  MiniatureTicket._(
    this.runId,
    this.route,
    this.style,
    this._visibleTop,
    this._service,
  );

  final int runId;
  final List<List<RoutePoint>> route;
  final RouteMapStyle style;
  final double? Function() _visibleTop;
  final MiniatureService _service;
  final Completer<Uint8List?> _done = Completer<Uint8List?>();
  bool _cancelled = false;

  bool get cancelled => _cancelled;
  Future<Uint8List?> get result => _done.future;

  /// Nimmt den Auftrag zurück (wegscrollen). Läuft er schon, bricht die Erzeugung ab und nichts wird gespeichert.
  void cancel() => _service._cancel(this);
}

/// Die Karte, die gerade aufgenommen wird (für den unsichtbaren Träger).
class MiniatureJob {
  MiniatureJob(this.source, this.route, this.style);
  final MapTileSource source;
  final List<List<RoutePoint>> route;
  final RouteMapStyle style;
  final GlobalKey boundary = GlobalKey();
}

/// Erzeugt die Miniaturen des Verlaufs bei Bedarf (WP13 D, R008 Hinweis 5): strikt nacheinander, sichtbare Einträge
/// zuerst, ein Eintrag verlässt die Warteschlange, wenn er wegscrollt. Je Aufbau des Verlaufs eine Instanz: ein
/// Lauf, dessen Erzeugung scheiterte, wird erst beim nächsten Aufbau wieder versucht (kein Dauerversuch).
///
/// Ohne Einwilligung ([enabled] `false`) gibt es weder Anfragen noch Bilder aus dem Speicher: auch Kartenbilder, die
/// nach einem Widerruf noch liegen, werden nicht gezeigt.
class MiniatureService extends ChangeNotifier {
  MiniatureService({required this.consent, MiniatureCapture? capture})
    : _capture = capture ?? debugMiniatureCapture ?? _defaultCapture {
    consent.addListener(_onConsent);
    _removed = consent.removedRuns.listen(_onRemoved);
    _wasEnabled = enabled;
  }

  final MapConsentController consent;
  final MiniatureCapture _capture;
  late final StreamSubscription<int> _removed;

  MapThumbnailStore? get _store => consent.services.thumbnails;

  /// Einwilligung erteilt und ein Miniaturen-Speicher vorhanden.
  bool get enabled => consent.granted && _store != null;
  late bool _wasEnabled;

  /// Die Karte, die der unsichtbare Träger gerade malt.
  final ValueNotifier<MiniatureJob?> job = ValueNotifier<MiniatureJob?>(null);

  final List<MiniatureTicket> _queue = [];
  MiniatureTicket? _current;
  final Set<int> _failed = {};
  MapTileSource? _source;
  bool _sourceFailed = false;
  bool _running = false;
  bool _disposed = false;

  /// Für Tests: wie viele Aufträge liefen, und wie viele zugleich.
  int started = 0;
  int maxRunning = 0;
  int _runningNow = 0;

  /// Aufträge in der Warteschlange (ohne den laufenden).
  int get queued => _queue.length;

  /// Die gespeicherte Miniatur oder `null` (keine, keine Einwilligung, Speicher aus). Liest über den Hintergrund-
  /// Isolate des Speichers, nicht auf dem UI-Thread.
  Future<Uint8List?> stored(int runId, RouteMapStyle style) async {
    final store = _store;
    if (!enabled || store == null) return null;
    Uint8List? bytes;
    try {
      bytes = await store.read(thumbnailKey(miniatureVariant(style), runId));
    } catch (_) {
      return null;
    }
    return enabled ? bytes : null; // Widerruf während des Lesens
  }

  /// Bittet um eine Miniatur. `null`, wenn keine entstehen darf oder wird: keine Einwilligung, Quelle nicht zu
  /// öffnen, der Versuch für diesen Lauf in diesem Aufbau schon gescheitert. [visibleTop] gibt beim Auswählen die Oberkante des Eintrags auf dem
  /// Bildschirm, wenn er zu sehen ist, sonst `null`.
  MiniatureTicket? request(
    int runId,
    List<List<RoutePoint>> route,
    RouteMapStyle style, {
    required double? Function() visibleTop,
  }) {
    if (_disposed || !enabled || _sourceFailed || _failed.contains(runId)) {
      return null;
    }
    final t = MiniatureTicket._(runId, route, style, visibleTop, this);
    _queue.add(t);
    _pump();
    return t;
  }

  void _cancel(MiniatureTicket t) {
    t._cancelled = true;
    if (_queue.remove(t)) t._done.complete(null);
  }

  void _onRemoved(int runId) {
    for (final t in [..._queue, ?_current]) {
      if (t.runId == runId) _cancel(t);
    }
  }

  void _onConsent() {
    final now = enabled;
    if (_wasEnabled && !now) _stop();
    _wasEnabled = now;
    if (!_disposed) notifyListeners();
  }

  /// Widerruf: Warteschlange leer, laufende Aufnahme abbrechen, Quelle freigeben.
  void _stop() {
    for (final t in [..._queue, ?_current]) {
      _cancel(t);
    }
    job.value = null;
    _dropSource();
  }

  /// Sichtbare Einträge zuerst, der oberste voran; sonst der älteste Auftrag.
  MiniatureTicket? _next() {
    if (_queue.isEmpty) return null;
    MiniatureTicket? best;
    double? bestTop;
    for (final t in _queue) {
      final top = t._visibleTop();
      if (top != null && (bestTop == null || top < bestTop)) {
        best = t;
        bestTop = top;
      }
    }
    return best ?? _queue.first;
  }

  /// Wartezeit, bis aus dem Leerlauf der erste Auftrag gewählt wird: die Einträge melden sich nacheinander, so
  /// kann die Wahl "sichtbar zuerst, oberster voran" greifen.
  static const Duration collectDelay = Duration(milliseconds: 30);

  Future<void> _pump() async {
    if (_running) return;
    _running = true;
    try {
      await Future<void>.delayed(collectDelay);
      while (!_disposed) {
        final t = _next();
        if (t == null) break;
        _queue.remove(t);
        _current = t;
        _runningNow++;
        if (_runningNow > maxRunning) maxRunning = _runningNow;
        started++;
        try {
          await _run(t);
        } finally {
          _runningNow--;
          _current = null;
        }
      }
    } finally {
      _running = false;
    }
  }

  Future<MapTileSource?> _ensureSource() async {
    if (_source != null) return _source;
    if (_sourceFailed) return null;
    try {
      final s = await consent.openSource(maxParallel: miniatureMaxParallel);
      if (s == null) {
        _sourceFailed = true;
        return null;
      }
      if (_disposed || !enabled) {
        s.dispose();
        return null;
      }
      return _source = s;
    } catch (_) {
      _sourceFailed = true; // Netz oder Anbieter: Linie, erst der nächste Aufbau versucht es wieder
      return null;
    }
  }

  Future<void> _run(MiniatureTicket t) async {
    Uint8List? out;
    var attempted = false;
    try {
      final source = (enabled && !t.cancelled) ? await _ensureSource() : null;
      if (source != null && enabled && !t.cancelled) {
        attempted = true;
        final j = MiniatureJob(source, t.route, t.style);
        final failuresBefore = source.gate.failures;
        job.value = j;
        await WidgetsBinding.instance.endOfFrame;
        out = await _capture(
          j.boundary,
          source.gate,
          failuresBefore: failuresBefore,
          cancelled: () => t.cancelled || !enabled || _disposed,
        );
        final store = _store;
        if (out != null && !t.cancelled && enabled && store != null) {
          await store.write(
            thumbnailKey(miniatureVariant(t.style), t.runId),
            out,
          );
        } else {
          out = null;
        }
      }
    } catch (_) {
      out = null;
    } finally {
      if (!_disposed) job.value = null;
    }
    // Gescheitert (nicht abgebrochen): in diesem Aufbau nicht noch einmal.
    if (out == null && attempted && !t.cancelled) _failed.add(t.runId);
    if (!t._done.isCompleted) t._done.complete(out);
  }

  void _dropSource() {
    final s = _source;
    _source = null;
    if (s == null) return;
    // Der Träger malt die Karte noch bis zum nächsten Bild; erst danach freigeben.
    WidgetsBinding.instance.addPostFrameCallback((_) => s.dispose());
    WidgetsBinding.instance.scheduleFrame();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    consent.removeListener(_onConsent);
    _removed.cancel();
    for (final t in [..._queue, ?_current]) {
      _cancel(t);
    }
    job.value = null;
    _dropSource();
    job.dispose();
    super.dispose();
  }
}
