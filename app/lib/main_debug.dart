import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'app.dart';
import 'app_dependencies.dart';
import 'debug/debug_test_ppg_camera.dart';
import 'debug/debug_test_sensor.dart';
import 'system_clock.dart';
import 'ui/font_licenses.dart';

/// Debug-Einstiegspunkt mit Test-Sensor (WP07) und Fake-Kamera (WP27): `flutter run -t lib/main_debug.dart`.
///
/// Der Release-Build startet `main.dart`. Auch `-t lib/main_debug.dart` im
/// Release bricht ab; `kReleaseMode` ist eine Konstante, der Compiler entfernt
/// damit den Rest (belegt am Artefakt, siehe WP07).
void main() {
  if (kReleaseMode) throw StateError('main_debug nur im Debug-Build');
  registerFontLicenses();
  runApp(
    RunningApp(
      dependencies: AppDependencies.create(
        heartRateSensor: DebugTestSensor(const SystemClock()),
        ppgCamera: DebugTestPpgCamera(),
      ),
    ),
  );
}
