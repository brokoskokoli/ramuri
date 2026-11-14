import 'package:core/core.dart';
import 'package:flutter/material.dart';

import '../../ui/ui.dart';
import '../sensors/sensor_manager.dart';
import 'morning_measure_controller.dart';

/// Gurt-RR der Morgenmessung (WP33 Teil E, K61 Punkt 3): hält den
/// [MorningBeltRecorder] aus dem Kern, die aktive Pulsquelle der App und den
/// Hinweis „Pulsgurt verbunden“. Nur im Entwicklermodus passiert etwas; die
/// App wertet die RR nie aus.
class MorningBelt {
  MorningBelt({
    required Stream<HeartRateReading> readings,
    required this.connected,
    required this.developerMode,
  }) : _recorder = MorningBeltRecorder(
         readings: readings,
         developerMode: developerMode,
       );

  /// Die aktive Pulsquelle der App ([SensorManager.activeReadings]) und der
  /// Entwicklermodus der Einstellungen.
  factory MorningBelt.of(
    SensorManager sensors,
    SettingsStore settings,
    Clock clock,
  ) => MorningBelt(
    readings: sensors.activeReadings,
    connected: () => sensors.selector.activeId != null,
    developerMode: SettingsDeveloperModeStore(settings, clock).read,
  );

  final MorningBeltRecorder _recorder;

  /// Liefert gerade eine aktive Pulsquelle (Gurt) Werte?
  final bool Function() connected;
  final Future<bool> Function() developerMode;

  bool _developerOn = false;

  /// Liest den Entwicklermodus für den Hinweis; vor der ersten Ruhephase.
  Future<void> init() async {
    try {
      _developerOn = await developerMode();
    } on Object {
      _developerOn = false;
    }
  }

  /// Hinweis „Pulsgurt verbunden“ in Einstieg und Ruhephase: nur im Modus und
  /// mit aktiver Pulsquelle.
  bool get hintVisible => _developerOn && connected();

  /// Die gesammelten Pakete (nur im Modus und im Zeitfenster).
  List<RrPacket> get packets => _recorder.packets;

  /// Die Stellen im Ablauf der Messung (C2).
  MorningMeasureHooks get hooks => MorningMeasureHooks(
    onRestStarted: (at) => _recorder.onRestStarted(at),
    onMeasurementResumed: _recorder.onMeasurementResumed,
    onMeasurementEnded: _recorder.onMeasurementEnded,
  );

  Future<void> dispose() => _recorder.dispose();
}

/// Kleiner Hinweis im Design `morgen/Main` und `morgen/Ruhephase`.
class MorningBeltHint extends StatelessWidget {
  const MorningBeltHint({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = RamuriColors.of(context);
    return Container(
      key: const Key('morning_belt_hint'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.outline),
      ),
      child: Row(
        children: [
          Icon(Icons.monitor_heart_outlined, size: 18, color: c.action),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall!
                  .copyWith(color: c.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}
