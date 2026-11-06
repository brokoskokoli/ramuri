import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter/foundation.dart';

import 'run_heart_rate.dart';

/// Zustand der Verbindung zu einem Gerät.
enum SensorLinkState {
  /// Nicht verbunden (bewusst getrennt oder noch nie verbunden).
  idle,

  /// Verbindung wird aufgebaut.
  connecting,

  /// Verbunden; Werte kommen.
  connected,

  /// Verbindung abgebrochen (FR-0017); die App verbindet dasselbe Gerät neu.
  reconnecting,
}

/// Hinweis zur Sensorverwaltung (FR-0035): nie ein Absturz.
enum SensorProblem {
  /// Bluetooth-Rechte fehlen oder wurden verweigert.
  permissionDenied,

  /// Suche oder Verbindung nicht möglich (Bluetooth aus oder nicht verfügbar).
  bluetoothUnavailable,

  /// Das Gerät ließ sich nicht verbinden.
  connectFailed,
}

/// Ein Gerät aus Suche oder Speicher mit seinem Live-Stand.
class SensorEntry {
  const SensorEntry({
    required this.id,
    this.name,
    this.known = false,
    this.preferred = false,
    this.state = SensorLinkState.idle,
    this.bpm,
    this.batteryPercent,
  });

  final String id;
  final String? name;
  final bool known;
  final bool preferred;
  final SensorLinkState state;

  /// Letzter Pulswert; nur bei verbundenem Gerät, sonst `null`.
  final int? bpm;

  /// Nur wenn das Gerät einen Akkustand gemeldet hat (FR-0016).
  final int? batteryPercent;
}

/// App-weiter Sensordienst (WP07 Teil C): hält die Verbindungen, speist den
/// [HeartRateSourceSelector], kennt Puls und Batterie, speichert bekannte
/// Geräte und das bevorzugte Gerät.
///
/// Beim Erzeugen und beim Anbinden des Speichers wird der Sensor nicht
/// angefasst; Rechte werden erst bei [startScan] und [connect] angefragt
/// (ADR-0006 Punkt 3).
class SensorManager extends ChangeNotifier {
  SensorManager({
    required this.sensor,
    required this.clock,
    this.requestPermissions,
    this.reconnectDelay = defaultReconnectDelay,
    this.bluetoothAvailable,
    this.bluetoothGranted,
  });

  /// Pause zwischen dem Ende eines Verbindungsversuchs und dem nächsten
  /// (Vorschlag, OQ-0064). Der Takt ist länger: Ein Versuch zu einem Gerät
  /// außer Reichweite endet erst nach dem `connectTimeout` des Adapters
  /// (60 s), real also etwa 65 s je Runde.
  static const defaultReconnectDelay = Duration(seconds: 5);

  final HeartRateSensor sensor;
  final Clock clock;

  /// Fragt die Bluetooth-Rechte; `null`, wenn der Sensor keine braucht.
  final Future<void> Function()? requestPermissions;

  /// Pause zwischen zwei Versuchen, dasselbe Gerät neu zu verbinden (OQ-0064);
  /// die Dauer des Versuchs selbst kommt dazu, siehe [defaultReconnectDelay].
  final Duration reconnectDelay;

  /// Fragt, ob Bluetooth an ist; `null`, wenn der Sensor es nicht weiß. Damit
  /// wird ein gescheitertes Verbinden bei ausgeschaltetem Bluetooth als
  /// solches gemeldet (FR-0035).
  final Future<bool> Function()? bluetoothAvailable;

  /// Liest nur, ob die Bluetooth-Rechte schon erteilt sind (keine Abfrage beim
  /// Nutzer). `null`: nicht lesbar; dann gilt der Sensor als rechtefrei, wenn
  /// [requestPermissions] `null` ist (Test-Sensor), sonst als nicht erteilt.
  final Future<bool> Function()? bluetoothGranted;

  /// App-weite Quellenwahl außerhalb eines Laufs (Anzeige in der Verwaltung,
  /// Bevorzugung). Sie wird nie gesperrt oder geschlossen. Jeder Lauf bekommt
  /// über [beginRun] einen eigenen Selector.
  final HeartRateSourceSelector selector = HeartRateSourceSelector();

  final _runs = <RunHeartRate>[];

  KnownDeviceStore? _store;
  List<KnownDevice> _known = const [];
  final _found = <String, String?>{};
  final _conns = <String, _Conn>{};
  final _readings = StreamController<HeartRateReading>.broadcast();
  StreamSubscription<HeartRateDevice>? _scanSub;
  bool _scanning = false;
  SensorProblem? _problem;
  bool _permitted = false;
  bool _disposed = false;

  /// Werte der aktiven Quelle (nur dieses eine Gerät, FR-0019).
  Stream<HeartRateReading> get activeReadings => _readings.stream;

  /// Beginnt die Pulsquelle eines Laufs (WP07 Teil D): eigener, sofort
  /// gesperrter Selector aus den jetzt verbundenen Geräten. Er fasst den Sensor
  /// nicht an und fragt keine Rechte ab. [RunHeartRate.close] beendet ihn.
  RunHeartRate beginRun() {
    final run = RunHeartRate.start(this);
    _runs.add(run);
    return run;
  }

  /// Anzahl der noch offenen Läufe (nur für Tests: Leck in `_runs`).
  @visibleForTesting
  int get openRuns => _runs.length;

  /// Vom Lauf beim Schließen aufgerufen.
  void endRun(RunHeartRate run) => _runs.remove(run);

  /// Ein gewolltes Gerät verbindet gerade neu oder wartet auf den nächsten
  /// Versuch (nach Abbruch, FR-0017).
  bool get isRecovering => _conns.values.any(
    (c) => c.wanted && c.state == SensorLinkState.reconnecting,
  );

  bool get scanning => _scanning;
  SensorProblem? get problem => _problem;

  /// Kennungen der verbundenen Geräte.
  Set<String> get connectedIds => {
    for (final e in _conns.entries)
      if (e.value.state == SensorLinkState.connected) e.key,
  };

  /// Bekannte Geräte (nach Hinzufügen sortiert).
  List<SensorEntry> get knownEntries => [
    for (final k in _known) _entry(k.deviceId),
  ];

  /// Gefundene, noch unbekannte Geräte.
  List<SensorEntry> get foundEntries => [
    for (final id in _found.keys)
      if (!_known.any((k) => k.deviceId == id)) _entry(id),
  ];

  SensorEntry _entry(String id) {
    KnownDevice? k;
    for (final d in _known) {
      if (d.deviceId == id) k = d;
    }
    final c = _conns[id];
    final live = c?.state == SensorLinkState.connected;
    return SensorEntry(
      id: id,
      name: k?.displayName ?? _found[id],
      known: k != null,
      preferred: k?.isPreferred ?? false,
      state: c?.state ?? SensorLinkState.idle,
      bpm: live ? c!.bpm : null,
      batteryPercent: live ? c!.battery : null,
    );
  }

  /// Bindet den Speicher an und lädt bekannte Geräte und Bevorzugung. Der
  /// Sensor bleibt unberührt.
  Future<void> attachStore(KnownDeviceStore store) async {
    _store = store;
    await reloadKnown();
  }

  Future<void> reloadKnown() async {
    final store = _store;
    if (store == null) return;
    final list = await store.list();
    if (_disposed) return;
    _known = list;
    // Gerät ohne Eintrag (Speicher gelöscht): trennen und nicht neu verbinden.
    // Ein Gerät, das gerade erst verbindet (noch ohne Abo), ist ausgenommen.
    for (final id in _conns.keys.toList()) {
      final c = _conns[id]!;
      final pending = c.sub == null && c.state == SensorLinkState.connecting;
      if (!pending && !list.any((k) => k.deviceId == id)) disconnect(id);
    }
    String? pref;
    for (final k in list) {
      if (k.isPreferred) pref = k.deviceId;
    }
    selector.preferredId = pref;
    _notify();
  }

  /// Sucht Geräte. Fragt zuerst die Rechte ab; ohne sie oder bei
  /// ausgeschaltetem Bluetooth bleibt ein Hinweis in [problem].
  Future<void> startScan() async {
    if (_scanning) return;
    _problem = null;
    _found.clear();
    _scanning = true;
    _notify();
    if (!await _ensurePermissions()) {
      _scanning = false;
      _notify();
      return;
    }
    if (_disposed || !_scanning) return;
    try {
      _scanSub = sensor.scan().listen(
        (d) {
          _found[d.id] = d.name;
          _notify();
        },
        onError: (Object _) {
          _problem = SensorProblem.bluetoothUnavailable;
          _stopScanState();
        },
        onDone: _stopScanState,
      );
    } catch (_) {
      _problem = SensorProblem.bluetoothUnavailable;
      _stopScanState();
    }
  }

  void stopScan() {
    if (!_scanning) return;
    _stopScanState();
  }

  void _stopScanState() {
    _scanSub?.cancel();
    _scanSub = null;
    _scanning = false;
    _notify();
  }

  Future<bool> _ensurePermissions() async {
    final request = requestPermissions;
    if (request == null || _permitted) return true;
    try {
      await request();
      _permitted = true;
      return true;
    } catch (_) {
      _problem = SensorProblem.permissionDenied;
      return false;
    }
  }

  bool _autoConnecting = false;

  /// Verbindet alle bekannten, nicht verbundenen Geräte, aber nur, wenn die
  /// Bluetooth-Rechte schon erteilt sind und Bluetooth an ist (Auftrag Teil E,
  /// beim Öffnen des Lauf-Bildschirms). Fragt nie nach Rechten, zeigt nie einen
  /// Hinweis und wirft nie: ohne Rechte oder mit Bluetooth aus passiert nichts.
  /// Die Neuverbinden-Regeln gelten danach wie bei manuellem Verbinden.
  Future<void> connectKnown() async {
    if (_autoConnecting || _disposed || _known.isEmpty) return;
    _autoConnecting = true;
    try {
      if (!await _hasPermissions()) return;
      final available = bluetoothAvailable;
      if (available != null && !await available()) return;
      if (_disposed) return;
      // Rechte sind da: connect darf nicht mehr nachfragen.
      _permitted = true;
      for (final k in List.of(_known)) {
        final c = _conns[k.deviceId];
        if (c != null && c.state != SensorLinkState.idle) continue;
        if (_disposed) return;
        await connect(k.deviceId, name: k.displayName);
      }
    } catch (_) {
      // Stilles Verbinden: Fehler zeigt höchstens die Verwaltung.
    } finally {
      _autoConnecting = false;
    }
  }

  Future<bool> _hasPermissions() async {
    if (_permitted) return true;
    final read = bluetoothGranted;
    if (read == null) return requestPermissions == null;
    try {
      return await read();
    } catch (_) {
      return false;
    }
  }

  /// Merkt das Gerät als bekannt (FR-0013) und verbindet es.
  Future<void> connect(String id, {String? name}) async {
    final existing = _conns[id];
    if (existing != null && existing.state != SensorLinkState.idle) return;
    _problem = null;
    // Vor dem ersten await als verbindend markieren: ein Doppeltipp startet
    // keinen zweiten Versuch.
    final c = existing ?? (_conns[id] = _Conn());
    c.state = SensorLinkState.connecting;
    _notify();
    try {
      if (!await _ensurePermissions()) {
        _abortPending(c);
        return;
      }
      if (_disposed) return;
      final store = _store;
      if (store != null) {
        await store.upsert(
          id,
          displayName: name ?? _found[id],
          at: clock.now(),
        );
        await reloadKnown();
      }
    } catch (_) {
      _abortPending(c);
      rethrow;
    }
    // Währenddessen getrennt: nicht doch noch verbinden.
    if (_disposed || c.state != SensorLinkState.connecting) return;
    _open(c, id);
  }

  void _abortPending(_Conn c) {
    if (c.sub == null && c.state == SensorLinkState.connecting) {
      c.state = SensorLinkState.idle;
    }
    _notify();
  }

  void _open(_Conn c, String id) {
    c
      ..wanted = true
      ..state = c.everConnected
          ? SensorLinkState.reconnecting
          : SensorLinkState.connecting
      ..timer?.cancel();
    c.timer = null;
    c.sub?.cancel();
    late final StreamSubscription<HeartRateEvent> sub;
    sub = sensor
        .connect(id)
        .listen(
          (e) => _onEvent(c, id, e),
          onError: (Object _) => _onFailure(c, id, sub),
          onDone: () => _onEnded(c, id, sub),
        );
    c.sub = sub;
    _notify();
  }

  void _onEvent(_Conn c, String id, HeartRateEvent e) {
    if (e is HeartRateConnected) {
      c
        ..state = SensorLinkState.connected
        ..everConnected = true
        ..bpm = null
        ..battery = null;
    } else if (e is HeartRateReading) {
      c.bpm = e.beatsPerMinute;
    } else if (e is HeartRateBattery) {
      c.battery = e.percent;
    } else if (e is HeartRateDisconnected) {
      if (e.lost) {
        _lost(c, id, alreadyReported: true);
      }
      return _feed(e);
    }
    _feed(e);
  }

  void _feed(HeartRateEvent e) {
    final r = selector.handle(e, clock.now());
    if (r != null && !_readings.isClosed) _readings.add(r);
    _feedRuns(e);
    _notify();
  }

  void _feedRuns(HeartRateEvent e) {
    for (final run in List.of(_runs)) {
      run.handle(e);
    }
  }

  /// Verbindung verloren (Strom meldete es oder endete ohne Abschluss).
  void _lost(_Conn c, String id, {required bool alreadyReported}) {
    final wasLive = c.state == SensorLinkState.connected;
    c.bpm = null;
    c.battery = null;
    c.sub?.cancel();
    c.sub = null;
    if (!c.wanted) {
      c.state = SensorLinkState.idle;
      return;
    }
    if (wasLive && !alreadyReported) {
      final lost = HeartRateDisconnected(id, lost: true);
      selector.handle(lost, clock.now());
      _feedRuns(lost);
    }
    c.state = SensorLinkState.reconnecting;
    c.timer?.cancel();
    c.timer = Timer(reconnectDelay, () {
      if (_disposed || !c.wanted) return;
      _open(c, id);
    });
  }

  void _onFailure(_Conn c, String id, StreamSubscription<void> sub) {
    if (!identical(c.sub, sub)) return;
    if (c.everConnected) {
      _lost(c, id, alreadyReported: false);
    } else {
      c
        ..wanted = false
        ..state = SensorLinkState.idle
        ..sub = null;
      _problem = SensorProblem.connectFailed;
      unawaited(_refineConnectProblem());
    }
    _notify();
  }

  /// Ist Bluetooth aus, ist das der Grund des Scheiterns, nicht die Nähe.
  Future<void> _refineConnectProblem() async {
    final check = bluetoothAvailable;
    if (check == null) return;
    try {
      if (await check()) return;
    } catch (_) {
      return;
    }
    if (_disposed || _problem != SensorProblem.connectFailed) return;
    _problem = SensorProblem.bluetoothUnavailable;
    _notify();
  }

  void _onEnded(_Conn c, String id, StreamSubscription<void> sub) {
    if (!identical(c.sub, sub)) return;
    if (c.state == SensorLinkState.connected ||
        c.state == SensorLinkState.reconnecting) {
      _lost(c, id, alreadyReported: false);
    } else {
      c
        ..state = SensorLinkState.idle
        ..wanted = false
        ..sub = null;
    }
    _notify();
  }

  /// Trennt bewusst (FR-0012): danach keine Werte, kein Neuverbinden.
  void disconnect(String id) {
    final c = _conns[id];
    if (c == null || !c.wanted && c.state == SensorLinkState.idle) return;
    final wasLive = c.state == SensorLinkState.connected;
    c
      ..wanted = false
      ..timer?.cancel();
    c.timer = null;
    final sub = c.sub;
    c.sub = null;
    c
      ..state = SensorLinkState.idle
      ..bpm = null
      ..battery = null
      ..everConnected = false;
    unawaited(sub?.cancel());
    if (wasLive) _feed(HeartRateDisconnected(id));
    _notify();
  }

  /// Macht das Gerät zum bevorzugten oder hebt die Festlegung auf (FR-0014).
  Future<void> setPreferred(String? id) async {
    final store = _store;
    if (store == null) return;
    await store.setPreferred(id);
    await reloadKnown();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _scanSub?.cancel();
    for (final c in _conns.values) {
      c.wanted = false;
      c.timer?.cancel();
      c.sub?.cancel();
    }
    for (final run in List.of(_runs)) {
      run.close();
    }
    _readings.close();
    super.dispose();
  }
}

class _Conn {
  SensorLinkState state = SensorLinkState.idle;
  bool wanted = false;
  bool everConnected = false;
  int? bpm;
  int? battery;
  StreamSubscription<HeartRateEvent>? sub;
  Timer? timer;
}
