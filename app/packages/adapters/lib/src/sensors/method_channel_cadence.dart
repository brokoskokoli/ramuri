import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter/services.dart';

/// Kanalnamen zu `StepSensor.kt`; dieselben Zeichenketten stehen dort
/// (ein Test prüft das).
const String stepSensorChannelName = 'ramuri/step_sensor';
const String stepStreamChannelName = 'ramuri/step_stream';

/// [CadenceSensor] über den Schrittsensor des Telefons (eigener Kotlin-Code,
/// prozessweit an der Engine). Kotlin meldet nur Schrittzeitpunkte; die
/// Frequenz rechnet [CadenceEstimator]. Ohne Berechtigung oder Sensor ist der
/// Strom leer, nie ein Fehler (FR-0202: der Lauf geht normal weiter).
class MethodChannelCadenceSensor implements CadenceSensor {
  MethodChannelCadenceSensor({MethodChannel? method, EventChannel? events})
    : _method = method ?? const MethodChannel(stepSensorChannelName),
      _events = events ?? const EventChannel(stepStreamChannelName);

  final MethodChannel _method;
  final EventChannel _events;

  @override
  Future<CadenceAvailability> availability() async {
    try {
      return switch (await _method.invokeMethod<String>('availability')) {
        'available' => CadenceAvailability.available,
        'permission_denied' => CadenceAvailability.permissionDenied,
        _ => CadenceAvailability.noSensor,
      };
    } on PlatformException {
      return CadenceAvailability.noSensor;
    } on MissingPluginException {
      return CadenceAvailability.noSensor;
    }
  }

  /// Bewusst kein `async*`: Abbestellen eines Generators wirkt erst am
  /// nächsten `yield`, der Sensor bliebe im Stillstand angemeldet.
  @override
  Stream<CadenceReading> readings() {
    final estimator = CadenceEstimator();
    // Schritte seit dem letzten Wert (auch die ohne Frequenz), damit der
    // Zähler des Laufs keinen Schritt verliert.
    var pending = 0;
    StreamSubscription<dynamic>? sub;
    var cancelled = false;
    late final StreamController<CadenceReading> out;
    out = StreamController<CadenceReading>(
      onListen: () async {
        if (await availability() != CadenceAvailability.available ||
            cancelled) {
          await out.close();
          return;
        }
        sub = _events.receiveBroadcastStream().listen(
          (event) {
            final ms = event is Map ? event['timeMs'] : null;
            final mono = event is Map ? event['elapsedMs'] : null;
            if (ms is! int || mono is! int) return;
            final time = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
            final elapsed = Duration(milliseconds: mono);
            // Abstände nur auf der Monotonzeit: die Wanduhr kann zurückspringen.
            final before = estimator.accepted;
            final spm = estimator.add(elapsed);
            pending += estimator.accepted - before;
            if (spm != null && pending > 0) {
              out.add(CadenceReading(time, spm, elapsed, steps: pending));
              pending = 0;
            }
          },
          // Sensor oder Recht fiel weg: der Strom endet, der Lauf geht weiter.
          onError: (Object _) => out.close(),
          onDone: out.close,
        );
      },
      onCancel: () {
        cancelled = true;
        return sub?.cancel();
      },
    );
    return out.stream;
  }
}
