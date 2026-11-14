import 'dart:async';

import '../../ports/heart_rate_sensor.dart';
import '../preprocessing/measurement.dart' show RrPacket;

/// Sammelt für die Morgenmessung die Gurt-RR der aktiven Pulsquelle (WP33
/// Teil E, K61 Punkt 3): nur im Entwicklermodus, von Beginn der Ruhephase bis
/// Ende der Messung (bei „Noch einmal messen“ durchgehend bis Ende der
/// Wiederholung, ohne Lücke), nur vom ersten Quellgerät, je BLE-Paket mit Empfangszeit roh (1/1024 s). Ohne Gurt
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

  /// Pakete nach dem Ende einer Aufnahme: kommen bei „Noch einmal“ dazu,
  /// sonst gehen sie verloren.
  final _tail = <RrPacket>[];

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
    _packets.clear();
    _tail.clear();
    _source = null;
    _to = null;
    _from = at;
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

  /// „Noch einmal messen“ nach verworfener Messung: das Fenster läuft ohne
  /// Lücke weiter, auch die Pakete seit dem Ende gehören dazu.
  void onMeasurementResumed() {
    _packets.addAll(_tail);
    _tail.clear();
    _to = null;
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
    (to != null && r.time.isAfter(to) ? _tail : _packets).add(packet);
  }

  Future<void> dispose() async {
    _disposed = true;
    final s = _sub;
    _sub = null;
    _packets.clear();
    _tail.clear();
    await s?.cancel();
  }
}
