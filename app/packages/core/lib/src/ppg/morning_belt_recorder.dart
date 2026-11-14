import 'dart:async';

import '../../ports/heart_rate_sensor.dart';
import '../preprocessing/measurement.dart' show RrPacket;

/// Sammelt für die Morgenmessung die Gurt-RR der aktiven Pulsquelle (WP33
/// Teil E, K61 Punkt 3): nur im Entwicklermodus, je Messung genau deren Ablauf:
/// von Beginn der Ruhephase (bei übersprungener Ruhe ab Beginn der Messung, bei
/// „Noch einmal messen“ ab dessen Beginn) bis Ende der Aufnahme; Pakete der
/// vorherigen Aufnahme gehören nie dazu. Nur vom ersten Quellgerät, je BLE-Paket mit Empfangszeit roh (1/1024 s). Ohne Gurt
/// oder ohne Modus bleibt [packets] leer. Der Aufrufer speichert die Pakete
/// erst mit einer gespeicherten Messung; sonst gehen sie mit [dispose]
/// verloren (keine verwaisten RR). Keine Werte in Logs.
class MorningBeltRecorder {
  MorningBeltRecorder({required this.readings, required this.developerMode});

  /// Werte der aktiven Pulsquelle (nur dieses eine Gerät).
  final Stream<HeartRateReading> readings;

  /// Ist der Entwicklermodus an? Wird zu Beginn der Ruhephase gelesen.
  final Future<bool> Function() developerMode;

  final _packets = <RrPacket>[];

  /// Kennung des ersten Quellgeräts, nur zum Filtern im Speicher.
  String? _source;
  StreamSubscription<HeartRateReading>? _sub;
  DateTime? _from;
  DateTime? _to;
  bool _disposed = false;

  /// Bisher gesammelte Pakete in Empfangsreihenfolge (Kopie).
  List<RrPacket> get packets => List.unmodifiable(_packets);

  /// Die Ruhephase beginnt: das Fenster öffnet sich bei [at].
  Future<void> onRestStarted(DateTime at) async {
    _openWindow(at);
    await _sub?.cancel();
    _sub = null;
    bool on;
    try {
      on = await developerMode();
    } on Object {
      on = false;
    }
    if (!on || _disposed || _from != at) return;
    _sub = readings.listen(_onReading, onError: (Object _) {});
  }

  /// Eine neue Aufnahme beginnt bei [at] („Noch einmal messen“ nach
  /// verworfener Messung oder Messung nach übersprungener Ruhe): das Fenster
  /// öffnet sich neu, Pakete der vorherigen Aufnahme und der Lücke davor
  /// gehören nicht dazu.
  void onMeasurementStarted(DateTime at) => _openWindow(at);

  void _openWindow(DateTime at) {
    _packets.clear();
    _source = null;
    _to = null;
    _from = at;
  }

  /// Die Aufnahme ist zu Ende: das Fenster schließt sich bei [at].
  void onMeasurementEnded(DateTime at) => _to = at;

  void _onReading(HeartRateReading r) {
    final from = _from;
    if (from == null || r.rrIntervals.isEmpty) return;
    if (r.time.isBefore(from)) return;
    // Nur ein Gerät: wechselt die aktive Quelle (Failover), fallen die
    // Pakete des anderen weg.
    _source ??= r.deviceId;
    if (r.deviceId != _source) return;
    final packet = RrPacket(
      time: r.time,
      source: r.deviceId,
      intervals: List.unmodifiable(r.rrIntervals),
    );
    final to = _to;
    if (to != null && r.time.isAfter(to)) return;
    _packets.add(packet);
  }

  /// Die Messung ist beendet: das Abo endet, es kommen keine Pakete mehr dazu.
  /// Die gesammelten [packets] bleiben für „Speichern erneut versuchen“
  /// erhalten.
  Future<void> stop() async {
    final s = _sub;
    _sub = null;
    await s?.cancel();
  }

  Future<void> dispose() async {
    _disposed = true;
    final s = _sub;
    _sub = null;
    _packets.clear();
    await s?.cancel();
  }
}
