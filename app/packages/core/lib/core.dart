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
export 'src/preprocessing/geo.dart';
export 'src/preprocessing/heart_rate_processor.dart';
export 'src/preprocessing/latest_value_index.dart';
export 'src/preprocessing/measurement.dart';
export 'src/preprocessing/motion_segments.dart';
export 'src/preprocessing/movement_time_processor.dart';
export 'src/preprocessing/pace.dart';
export 'src/preprocessing/pace_processor.dart';
export 'src/preprocessing/position_processor.dart';
export 'src/preprocessing/preprocessing_parameters.dart';
export 'src/preprocessing/run_preprocessor.dart';
export 'src/preprocessing/section_quality.dart';
export 'src/preprocessing/settling_processor.dart';

/// Name des Pakets, nur damit das Paket auflösbar und testbar ist.
const String corePackageName = 'core';
