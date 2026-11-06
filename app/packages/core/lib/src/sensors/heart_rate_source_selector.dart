import '../../ports/heart_rate_sensor.dart';

/// Warum die Quelle wechselte.
enum SourceSwitchReason {
  /// Der Nutzer wählte ein anderes verbundenes Gerät (FR-0018).
  manual,

  /// Die bisherige Quelle brach ab oder wurde getrennt (FR-0017, FR-0018).
  lost,
}

/// Ein Wechsel der Quelle. [from] ist die zuletzt aktive Quelle, auch wenn
/// zwischendurch keine aktiv war (Abbruch ohne weiteres Gerät).
class SourceSwitch {
  const SourceSwitch({
    required this.at,
    required this.from,
    required this.to,
    required this.reason,
  });

  final DateTime at;
  final String from;
  final String to;
  final SourceSwitchReason reason;
}

/// Zeitabschnitt, in dem [deviceId] die Quelle war. [end] ist `null`,
/// solange der Abschnitt läuft. Zeit außerhalb aller Abschnitte hat keine
/// Quelle, also keinen Wert (FR-0017, FR-0056).
class HeartRateSourceSegment {
  const HeartRateSourceSegment(this.deviceId, this.start, [this.end]);

  final String deviceId;
  final DateTime start;
  final DateTime? end;

  bool covers(DateTime t) =>
      !t.isBefore(start) && (end == null || t.isBefore(end!));
}

/// Wählt aus den Ereignissen mehrerer verbundener Sensoren genau eine Quelle
/// (FR-0017 bis FR-0020, OQ-0018, OQ-0037, OQ-0064).
///
/// Regeln:
/// - Hat keine Quelle, wird das bevorzugte Gerät gewählt, wenn es verbunden
///   ist, sonst das am längsten verbundene.
/// - Eine aktive Quelle bleibt, bis der Nutzer wechselt ([select]) oder sie
///   abbricht. Auch wenn das bevorzugte Gerät später verbunden wird, gibt es
///   keinen Rückwechsel.
/// - Nach einem Abbruch folgt das bevorzugte, sonst das am längsten
///   verbundene andere Gerät. Kommt später dasselbe Gerät wieder, ist das
///   kein Wechsel ([switches] bleibt unverändert).
/// - Werte anderer Geräte werden nicht durchgereicht: keine Vermischung.
class HeartRateSourceSelector {
  HeartRateSourceSelector({this.preferredId});

  /// Bevorzugtes Gerät. Ändern wechselt die laufende Quelle nicht.
  String? preferredId;

  String? _active;
  String? _lastActive;

  /// Verbundene Geräte in der Reihenfolge des Verbindens.
  final List<String> _connected = [];
  final Map<String, int> _battery = {};
  final List<HeartRateSourceSegment> _segments = [];
  final List<SourceSwitch> _switches = [];

  /// Aktuelle Quelle, `null` ohne Quelle.
  String? get activeId => _active;

  Set<String> get connectedIds => Set.unmodifiable(_connected);

  /// Alle Abschnitte in zeitlicher Reihenfolge (der letzte kann offen sein).
  List<HeartRateSourceSegment> get segments => List.unmodifiable(_segments);

  /// Quellwechsel; Neuverbinden desselben Geräts steht nicht darin.
  List<SourceSwitch> get switches => List.unmodifiable(_switches);

  /// Letzter Akkustand des Geräts, `null` ohne gemeldeten Wert (FR-0016).
  int? batteryOf(String deviceId) => _battery[deviceId];

  /// Quellgerät zum Zeitpunkt [t], `null` ohne Quelle (nicht verfügbar).
  String? sourceAt(DateTime t) {
    for (final s in _segments.reversed) {
      if (s.covers(t)) return s.deviceId;
    }
    return null;
  }

  /// Verarbeitet ein Ereignis zum Zeitpunkt [at]. Gibt den Messwert zurück,
  /// wenn er von der aktiven Quelle stammt, sonst `null`.
  HeartRateReading? handle(HeartRateEvent e, DateTime at) {
    switch (e) {
      case HeartRateConnected():
        _onConnected(e.deviceId, at);
      case HeartRateDisconnected():
        _onDisconnected(e.deviceId, at);
      case HeartRateBattery():
        if (_connected.contains(e.deviceId)) _battery[e.deviceId] = e.percent;
      case HeartRateReading():
        if (e.deviceId == _active) return e;
    }
    return null;
  }

  /// Der Nutzer wählt [deviceId] als Quelle. Nur ein verbundenes Gerät ist
  /// möglich; sonst `false`.
  bool select(String deviceId, DateTime at) {
    if (!_connected.contains(deviceId)) return false;
    if (deviceId != _active) _activate(deviceId, at, SourceSwitchReason.manual);
    return true;
  }

  /// Beendet den offenen Abschnitt (Ende des Laufs).
  void close(DateTime at) => _closeSegment(at);

  void _onConnected(String id, DateTime at) {
    if (_connected.contains(id)) return;
    _connected.add(id);
    if (_active == null) _activate(_pick(), at, SourceSwitchReason.lost);
  }

  void _onDisconnected(String id, DateTime at) {
    if (!_connected.remove(id)) return;
    _battery.remove(id);
    if (id != _active) return;
    _closeSegment(at);
    _active = null;
    if (_connected.isNotEmpty) {
      _activate(_pick(), at, SourceSwitchReason.lost);
    }
  }

  /// Bevorzugtes verbundenes Gerät, sonst das am längsten verbundene.
  String _pick() =>
      _connected.contains(preferredId) ? preferredId! : _connected.first;

  void _activate(String id, DateTime at, SourceSwitchReason reason) {
    final previous = _lastActive;
    _closeSegment(at);
    _active = id;
    _segments.add(HeartRateSourceSegment(id, at));
    // Erste Quelle und dasselbe Gerät nach einem Abbruch ohne Ersatz
    // (OQ-0064) sind kein Quellwechsel.
    if (previous != null && id != previous) {
      _switches.add(
        SourceSwitch(at: at, from: previous, to: id, reason: reason),
      );
    }
    _lastActive = id;
  }

  void _closeSegment(DateTime at) {
    if (_segments.isEmpty || _segments.last.end != null) return;
    final s = _segments.removeLast();
    _segments.add(HeartRateSourceSegment(s.deviceId, s.start, at));
  }
}
