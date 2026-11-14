/// Schlafphasenart (Health Connect: SLEEPING, LIGHT, DEEP, REM zählen als
/// Schlaf, PAR-166).
enum SleepStageKind {
  sleeping,
  light,
  deep,
  rem,
  awake,
  other;

  bool get countsAsSleep =>
      this == sleeping || this == light || this == deep || this == rem;
}

class SleepStage {
  const SleepStage({
    required this.kind,
    required this.start,
    required this.end,
  });

  final SleepStageKind kind;
  final DateTime start;
  final DateTime end;
}

/// Schlafsitzung einer Quell-App; [stages] leer oder fehlend heißt „ohne
/// Phasen“.
class SleepSession {
  const SleepSession({
    required this.origin,
    required this.start,
    required this.end,
    this.stages = const [],
  });

  final String origin;
  final DateTime start;
  final DateTime end;
  final List<SleepStage> stages;

  Duration get duration => end.difference(start);
  bool get hasStages => stages.isNotEmpty;
}

/// Einzelwert (RMSSD in ms oder Ruhepuls in bpm) mit Zeit und Quell-App.
class HealthSample {
  const HealthSample({
    required this.time,
    required this.value,
    required this.origin,
  });

  final DateTime time;
  final double value;
  final String origin;
}

/// Kennung von Verfahren und Version eines Ergebnisses (NFR-0001).
class HealthMethod {
  const HealthMethod(this.method, this.methodVersion, this.parameterVersion);

  final String method;
  final int methodVersion;
  final int parameterVersion;
}

/// Schlafzeit eines Tages (PAR-166).
class SleepSummary {
  const SleepSummary({
    required this.method,
    required this.origin,
    required this.sessionDuration,
    required this.sleepDuration,
    required this.isEstimate,
    required this.efficiencyPercent,
  });

  final HealthMethod method;
  final String origin;
  final Duration sessionDuration;

  /// Summe der Schlafphasen, bei [isEstimate] die Sitzungsdauer.
  final Duration sleepDuration;

  /// Phasen fehlen oder decken unter 90 % ab: Dauer ist geschätzt.
  final bool isEstimate;

  /// Null, wenn [isEstimate].
  final double? efficiencyPercent;
}

/// Tageswert je Quell-App (HRV oder Ruhepuls).
class HealthDailyValue {
  const HealthDailyValue({
    required this.method,
    required this.origin,
    required this.value,
    required this.sampleCount,
    required this.isFallback,
  });

  final HealthMethod method;
  final String origin;

  /// Median der gültigen Einträge.
  final double value;
  final int sampleCount;

  /// Nur HRV: Wert stammt aus den 60 min nach der Hauptschlafphase
  /// (PAR-160), der Tag ist zu markieren.
  final bool isFallback;
}
