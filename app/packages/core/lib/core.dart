/// Fachlogik ohne Flutter (reines Dart), Ports und ihre Fakes.
library;

export 'fakes/fake_cadence_sensor.dart';
export 'fakes/fake_clock.dart';
export 'fakes/fake_health_connect.dart';
export 'fakes/fake_heart_rate_sensor.dart';
export 'fakes/fake_key_store.dart';
export 'fakes/fake_location_source.dart';
export 'fakes/fake_recording_service.dart';
export 'fakes/fake_storage.dart';
export 'ports/cadence_sensor.dart';
export 'ports/clock.dart';
export 'ports/health_connect.dart';
export 'ports/heart_rate_sensor.dart';
export 'ports/key_store.dart';
export 'ports/location.dart';
export 'ports/recording_service.dart';
export 'ports/storage.dart';

/// Name des Pakets, nur damit das Paket auflösbar und testbar ist.
const String corePackageName = 'core';
