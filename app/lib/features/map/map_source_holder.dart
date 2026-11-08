import 'dart:async';

import 'package:adapters/adapters.dart';
import 'package:flutter/widgets.dart';

import 'map_consent_controller.dart';

/// Hält die Kachelquelle einer Karte für eine Seite (WP13 N1c, M5): Frage beim ersten Bedarf, Öffnen, Prüfung der
/// Einwilligung **nach** dem Öffnen, Schließen bei Widerruf oder Ende und der Rückfallstand, wenn die Kacheln
/// scheitern (M1). Die Zusammenfassung ([RouteMapSection]) und die Live-Seite haben diese Logik früher je für sich
/// gebaut; jetzt sagen sie nur noch, ob die Karte gebraucht wird ([setWanted]), und bauen das Widget aus [usable].
///
/// Das Tor bleibt die harte Grenze (jede Anfrage prüft die Einwilligung neu); der Halter sorgt dafür, dass nach
/// Widerruf keine Quelle offen bleibt und eine Quelle, die erst nach dem Widerruf fertig wird, sofort freigegeben wird.
class MapSourceHolder extends ChangeNotifier {
  /// [askContext] liefert den Kontext für die Frage, oder `null`, wenn die Seite nicht mehr im Baum steht.
  MapSourceHolder({required this.askContext});

  final BuildContext? Function() askContext;
  MapConsentController? _consent;
  MapTileSource? _source;
  bool _wanted = false;
  bool _started = false;
  bool _opening = false;
  bool _disposed = false;
  int _epoch = 0;

  /// Die offene Quelle, auch wenn die Kacheln scheitern.
  MapTileSource? get source => _source;

  /// Die Quelle, wenn die Karte gezeigt werden darf: Einwilligung erteilt, Quelle offen, Kacheln nicht gescheitert.
  /// Sonst `null`: die Seite zeigt die Linie, ohne Umschalter und ohne Quellenangabe.
  MapTileSource? get usable {
    final s = _source;
    if (s == null || _consent?.granted != true || s.tilesFailed.value) {
      return null;
    }
    return s;
  }

  /// Verbindet den Halter mit der Einwilligung der Sitzung (bei jedem Wechsel des Controllers neu). Löst keine
  /// Benachrichtigung aus: Der Aufrufer baut ohnehin neu.
  void bind(MapConsentController? consent) {
    if (identical(consent, _consent)) return;
    _consent?.removeListener(_onConsent);
    _closeSource();
    _epoch++;
    _started = false;
    _opening = false;
    _consent = consent;
    consent?.addListener(_onConsent);
    _maybeStart();
  }

  /// Sagt, ob die Karte gebraucht wird (Route vorhanden, Seite sichtbar und im Vordergrund). Mit `true` beginnt
  /// das Öffnen (und die Frage, falls nötig); eine Quelle, deren Kacheln scheiterten, versucht es neu.
  void setWanted(bool wanted) {
    final was = _wanted;
    _wanted = wanted;
    if (!wanted || was) return;
    final s = _source;
    if (s != null && s.tilesFailed.value) s.retryTiles();
    // Ein gescheitertes Öffnen (Anbieter nicht erreichbar) wird bei jedem neuen Bedarf einmal wiederholt (N5); die Frage
    // stellt der Controller nicht erneut nach "Nicht jetzt".
    if (s == null && !_opening) _started = false;
    _maybeStart();
  }

  void _maybeStart() {
    final c = _consent;
    if (_disposed || !_wanted || _started || _opening || c == null) return;
    if (c.status == MapConsentStatus.declined) return;
    _started = true;
    _opening = true;
    final epoch = _epoch;
    WidgetsBinding.instance.addPostFrameCallback((_) => _open(c, epoch));
    // Ohne ein geplantes Bild (Aufruf aus einem Hörer) bliebe der Rückruf liegen.
    WidgetsBinding.instance.scheduleFrame();
  }

  Future<void> _open(MapConsentController c, int epoch) async {
    bool stale() => _disposed || epoch != _epoch;
    try {
      if (stale()) return;
      final context = askContext();
      if (context == null) return;
      final yes = await c.ensureAsked(context);
      if (!yes || stale()) return;
      MapTileSource? source;
      try {
        source = await c.openSource();
      } catch (_) {
        source = null; // Anbieter nicht erreichbar: bei der Linie bleiben.
      }
      if (source == null) return;
      // Prüfung nach dem Öffnen: ein Widerruf während des Öffnens gibt die Quelle sofort wieder frei.
      if (stale() || !c.granted) {
        source.dispose();
        return;
      }
      _source = source;
      source.tilesFailed.addListener(_onTiles);
      notifyListeners();
    } finally {
      if (!stale()) _opening = false;
    }
  }

  void _onTiles() {
    if (!_disposed) notifyListeners();
  }

  void _onConsent() {
    if (_disposed) return;
    final c = _consent;
    if (c == null) return;
    if (!c.granted) {
      _started = false; // nach einem erneuten Erteilen neu öffnen
      if (_source != null) {
        _closeSource();
        notifyListeners();
      }
    } else if (_source == null && !_opening) {
      _started = false;
    }
    if (_source == null) _maybeStart();
  }

  void _closeSource() {
    final s = _source;
    _source = null;
    s?.tilesFailed.removeListener(_onTiles);
    s?.dispose();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _consent?.removeListener(_onConsent);
    _closeSource();
    super.dispose();
  }
}
