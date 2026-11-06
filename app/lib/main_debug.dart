import 'package:flutter/widgets.dart';

import 'app.dart';
import 'app_dependencies.dart';
import 'debug/debug_test_sensor.dart';
import 'system_clock.dart';

/// Debug-Einstiegspunkt mit Test-Sensor (WP07): `flutter run -t lib/main_debug.dart`.
///
/// Der Release-Build startet `main.dart` und erreicht diese Datei nie; so
/// landet der Test-Sensor nicht im APK (belegt am Artefakt, siehe WP07).
void main() {
  runApp(
    RunningApp(
      dependencies: AppDependencies.create(
        heartRateSensor: DebugTestSensor(const SystemClock()),
      ),
    ),
  );
}
