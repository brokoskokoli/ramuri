import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter/foundation.dart';

import 'sensor_manager.dart';

/// Stand der Pulsquelle im Lauf, für die Anzeige.
enum RunSensorStatus {
  /// Kein Sensor verbunden und in diesem Lauf noch keiner aktiv.
  none,

  /// Eine Quelle liefert Werte.
  connected,

  /// Keine aktive Quelle, die App verbindet neu (FR-0017).
  reconnecting,

  /// Keine aktive Quelle mehr, kein Neuverbinden läuft (bewusst getrennt).
  lost,
}

/// Pulsquelle genau eines Laufs (WP07 Teil D): ein eigener
/// [HeartRateSourceSelector], beim Start aus den verbundenen Geräten und der
/// aktuellen Quelle des Dienstes angelegt und sofort gesperrt. Er kennt kein
/// Zurückspringen zum bevorzugten Gerät (FR-0018). [close] beendet den Lauf;
/// der app-weite Selector des [SensorManager] bleibt davon unberührt.
class RunHeartRate extends ChangeNotifier {
  RunHeartRate.start(this._manager)
    : _selector = HeartRateSourceSelector(
        preferredId: _manager.selector.preferredId,
      ) {
    final now = _manager.clock.now();
    // Erst sperren, dann bestücken: Das bevorzugte Gerät darf die laufende
    // Quelle nicht verdrängen. Die aktive Quelle kommt zuerst.
    _selector.lock(now);
    final active = _manager.selector.activeId;
    final connected = _manager.selector.connectedIds;
    final order = [
      ?active,
      for (final id in connected)
        if (id != active) id,
    ];
    for (final id in order) {
      _selector.handle(HeartRateConnected(id), now);
    }
  }

  final SensorManager _manager;
  final HeartRateSourceSelector _selector;
  final _readings = StreamController<HeartRateReading>.broadcast();
  bool _closed = false;
  bool _lossSeen = false;

  /// Werte der aktiven Quelle (nur dieses eine Gerät, FR-0019).
  Stream<HeartRateReading> get readings => _readings.stream;

  String? get activeId => _selector.activeId;

  /// Abschnitte und Wechsel des Laufs (FR-0020).
  List<HeartRateSourceSegment> get segments => _selector.segments;
  List<SourceSwitch> get switches => _selector.switches;

  /// Die aktive Quelle ist in diesem Lauf mindestens einmal abgebrochen.
  bool get lossSeen => _lossSeen;

  /// Verbundene Geräte, aus denen der Nutzer die Quelle wählen kann.
  List<SensorEntry> get devices => [
    for (final e in [..._manager.knownEntries, ..._manager.foundEntries])
      if (_selector.connectedIds.contains(e.id)) e,
  ];

  /// Bewusst manager-weit (WP07-Review D, Befund 6): Ein Gerät, das schon vor
  /// dem Lauf verbunden war und noch neu verbindet, wird bei Erfolg Quelle
  /// dieses Laufs; „verbindet neu“ ist dann wahr, auch ohne Abschnitt.
  RunSensorStatus get status {
    if (_selector.activeId != null) return RunSensorStatus.connected;
    if (_manager.isRecovering) return RunSensorStatus.reconnecting;
    return _selector.segments.isEmpty
        ? RunSensorStatus.none
        : RunSensorStatus.lost;
  }

  /// Anzeigename der aktiven Quelle, `null` ohne Quelle.
  SensorEntry? get activeEntry {
    final id = _selector.activeId;
    if (id == null) return null;
    for (final e in devices) {
      if (e.id == id) return e;
    }
    return null;
  }

  /// Wechselt von Hand zu einem verbundenen Gerät (FR-0018). Die Aufzeichnung
  /// läuft weiter; es gibt nur einen neuen Abschnitt.
  bool select(String deviceId) {
    if (_closed) return false;
    final ok = _selector.select(deviceId, _manager.clock.now());
    if (ok) notifyListeners();
    return ok;
  }

  /// Vom [SensorManager] aufgerufen, sonst nicht.
  void handle(HeartRateEvent e) {
    if (_closed) return;
    if (e is HeartRateDisconnected &&
        e.lost &&
        e.deviceId == _selector.activeId) {
      _lossSeen = true;
    }
    final r = _selector.handle(e, _manager.clock.now());
    if (r != null) _readings.add(r);
    notifyListeners();
  }

  /// Ende des Laufs: schließt den offenen Abschnitt, danach kommen keine
  /// Werte mehr.
  void close() {
    if (_closed) return;
    _closed = true;
    _selector.close(_manager.clock.now());
    _manager.endRun(this);
    unawaited(_readings.close());
    notifyListeners();
  }
}
