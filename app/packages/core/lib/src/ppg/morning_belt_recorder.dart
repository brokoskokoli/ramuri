import 'dart:async';

import '../../ports/heart_rate_sensor.dart';
import '../preprocessing/measurement.dart' show RrPacket;

/// Sammelt für die Morgenmessung die Gurt-RR der aktiven Pulsquelle (WP33
/// Teil E, K61 Punkt 3): nur im Entwicklermodus, von Beginn der Ruhephase bis
/// Ende der Messung, je BLE-Paket mit Empfangszeit roh (1/1024 s). Ohne Gurt
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
  StreamSubscription<HeartRateReading>? _sub;
  DateTime? _from;
  DateTime? _to;
  bool _disposed = false;

  /// Bisher gesammelte Pakete in Empfangsreihenfolge (Kopie).
  List<RrPacket> get packets => List.unmodifiable(_packets);

  /// Die Ruhephase beginnt: das Fenster öffnet sich bei [at].
  Future<void> onRestStarted(DateTime at) async {
    _packets.clear();
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

  /// „Noch einmal messen“ nach verworfener Messung: das Fenster ist wieder
  /// offen (die Zeit dazwischen ist nicht Teil davon).
  void onMeasurementResumed() => _to = null;

  /// Die Aufnahme ist zu Ende: das Fenster schließt sich bei [at].
  void onMeasurementEnded(DateTime at) => _to = at;

  void _onReading(HeartRateReading r) {
    final from = _from;
    if (from == null || r.rrIntervals.isEmpty) return;
    if (r.time.isBefore(from)) return;
    final to = _to;
    if (to != null && r.time.isAfter(to)) return;
    _packets.add(
      RrPacket(
        time: r.time,
        source: r.deviceId,
        intervals: List.unmodifiable(r.rrIntervals),
      ),
    );
  }

  Future<void> dispose() async {
    _disposed = true;
    final s = _sub;
    _sub = null;
    _packets.clear();
    await s?.cancel();
  }
}
