import '../../ports/health_import.dart';
import 'health_types.dart';

/// Phase von Health Connect (`SleepSessionRecord.STAGE_TYPE_*`) auf [SleepStageKind] (PAR-166: Schlafzeit zählt nur
/// SLEEPING, LIGHT, DEEP und REM). 0 UNKNOWN und unbekannte Werte sind [SleepStageKind.other] und zählen nicht;
/// 1 AWAKE, 3 OUT_OF_BED und 7 AWAKE_IN_BED sind [SleepStageKind.awake].
SleepStageKind sleepStageKindFromHealthConnect(int stage) => switch (stage) {
  1 || 3 || 7 => SleepStageKind.awake,
  2 => SleepStageKind.sleeping,
  4 => SleepStageKind.light,
  5 => SleepStageKind.deep,
  6 => SleepStageKind.rem,
  _ => SleepStageKind.other,
};

/// Gespeicherte Schlafsitzung (Art `sleep`) als Eingabe der Aufbereitung.
SleepSession sleepSessionOf(HealthRecord r) => SleepSession(
  origin: r.origin,
  start: r.start,
  end: r.end,
  stages: [
    for (final st in r.stages)
      SleepStage(
        kind: sleepStageKindFromHealthConnect(st.stage),
        start: st.start,
        end: st.end,
      ),
  ],
);
