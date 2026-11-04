import 'package:core/core.dart';

import 'support.dart';

RawAltitude alt(
  num sec,
  double meters, {
  double? va = 5,
  MeasurementState state = MeasurementState.present,
}) => RawAltitude(
  time: at(sec),
  source: 'test',
  meters: meters,
  verticalAccuracyMeters: va,
  state: state,
);
