/// Port zu Health Connect (ADR-0007, WP32 Teil A): nur Lesen, je Datenart getrennt. Reine Schnittstelle ohne Logik;
/// Einwilligung und Import liegen in `src/health/health_import.dart`. Der Port liegt in `core`, damit der Import ohne
/// Flutter testbar ist; der Adapter in `adapters` implementiert ihn.
library;

/// Die sechs Datenarten aus ADR-0007 Punkt 2; [key] ist der Wert im Kanal (`HealthKind` in `HealthConnectLogic.kt`).
enum HealthDataKind {
  exercise('exercise'),
  heartRate('heart_rate'),
  restingHeartRate('resting_heart_rate'),
  hrvRmssd('hrv_rmssd'),
  sleep('sleep'),
  vo2Max('vo2_max');

  const HealthDataKind(this.key);
  final String key;
}

/// Zustand von Health Connect auf dem Gerät (`getSdkStatus`).
enum HealthSdkStatus { available, updateRequired, unavailable }

/// Fehlercodes des Adapters; sie tragen nie Inhalte.
enum HealthReadError {
  permissionMissing,
  badArguments,
  rateLimited,
  unavailable,
  busy,
  other,
}

class HealthReadException implements Exception {
  const HealthReadException(this.error);
  final HealthReadError error;

  @override
  String toString() => 'HealthReadException(${error.name})';
}

/// Ein Datensatz in der Form des Kanals. [id] ist die Health-Connect-ID, [origin] das Paket der Quell-App
/// (`metadata.dataOrigin.packageName`), Zeiten sind UTC. Je Art liegen die Werte so:
/// Ruhepuls, HRV und VO₂max in [value] und [unit]; Pulsverlauf in [samples]; Schlaf in [stages]; Trainingseinheit in
/// [exerciseType] (Zahl von Health Connect).
class HealthRecord {
  const HealthRecord({
    required this.kind,
    required this.id,
    required this.origin,
    required this.start,
    required this.end,
    this.offsetSeconds,
    this.value,
    this.unit,
    this.exerciseType,
    this.samples = const [],
    this.stages = const [],
  });

  final HealthDataKind kind;
  final String id;
  final String origin;
  final DateTime start;
  final DateTime end;
  final int? offsetSeconds;
  final double? value;
  final String? unit;
  final int? exerciseType;
  final List<HealthHeartRateSample> samples;
  final List<HealthSleepStage> stages;
}

class HealthHeartRateSample {
  const HealthHeartRateSample(this.time, this.beatsPerMinute);
  final DateTime time;
  final int beatsPerMinute;
}

/// [stage] ist der Wert `SleepSessionRecord.STAGE_TYPE_*` von Health Connect.
class HealthSleepStage {
  const HealthSleepStage(this.start, this.end, this.stage);
  final DateTime start;
  final DateTime end;
  final int stage;
}

class HealthPage {
  const HealthPage(this.records, this.nextToken);
  final List<HealthRecord> records;

  /// Null, wenn es keine weitere Seite gibt.
  final String? nextToken;
}

abstract interface class HealthConnectPort {
  Future<HealthSdkStatus> sdkStatus();

  /// Die Arten, deren Leserecht Health Connect jetzt erteilt hat.
  Future<Set<HealthDataKind>> grantedKinds();

  /// Zeigt den Berechtigungsdialog von Health Connect für [kinds]; liefert die danach erteilten Arten.
  Future<Set<HealthDataKind>> requestPermissions(Set<HealthDataKind> kinds);

  /// Öffnet die Installationsseite von Health Connect im Play Store (ohne Netzzugriff der App). `false`, wenn sich
  /// nichts öffnen ließ; wirft nie.
  Future<bool> openInstall();

  /// Liest eine Seite einer Art im Zeitfenster [from, to]. Fehlt das Recht dieser Art, wirft der Adapter
  /// [HealthReadError.permissionMissing] und liest nichts. Pulsverlauf nur für Fenster bis 24 h.
  Future<HealthPage> readPage({
    required HealthDataKind kind,
    required DateTime from,
    required DateTime to,
    String? pageToken,
    int? pageSize,
  });
}
