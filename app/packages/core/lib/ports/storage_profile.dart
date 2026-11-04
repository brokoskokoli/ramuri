import 'storage.dart';

/// Gespeicherte Profilfelder, alle leer lassbar (FR-0002). Einheiten SI:
/// Gewicht in kg, Größe in Metern. `trainingDaysMask`: Montag = Bit 0 bis
/// Sonntag = Bit 6. Die Plausibilität prüft WP05, nicht der Speicher (der
/// verlangt nur positive Zahlen bei Geburtsjahr, Gewicht, Größe).
class ProfileRecord {
  const ProfileRecord({
    this.birthYear,
    this.bodyWeightKg,
    this.bodyHeightMeters,
    this.restingHeartRateBpm,
    this.maxHeartRateBpm,
    this.weeklyRunMinutes,
    this.trainingDaysMask,
    this.usualTrainingMinutes,
  });

  final int? birthYear;
  final double? bodyWeightKg;
  final double? bodyHeightMeters;
  final int? restingHeartRateBpm;
  final int? maxHeartRateBpm;
  final int? weeklyRunMinutes;
  final int? trainingDaysMask;
  final int? usualTrainingMinutes;
}

/// Regel des Speichers (CHECK der Tabelle): nur positive Zahlen bei
/// Geburtsjahr, Gewicht und Größe, Maske 0 bis 127. Sonst `rejected`; Fake und
/// Adapter nutzen dieselbe Prüfung.
void validateProfile(ProfileRecord p) {
  final ok =
      (p.birthYear ?? 1) > 0 &&
      (p.bodyWeightKg ?? 1) > 0 &&
      (p.bodyHeightMeters ?? 1) > 0 &&
      (p.trainingDaysMask ?? 0) >= 0 &&
      (p.trainingDaysMask ?? 0) <= 127;
  if (!ok) throw const StorageException(StorageFailure.rejected);
}

/// Profil: eine Zeile je Installation.
abstract interface class ProfileStore {
  /// Leeres Profil, solange nichts gespeichert ist.
  Future<ProfileRecord> read();

  /// Ersetzt das ganze Profil (nicht gesetzte Felder werden leer).
  Future<void> save(ProfileRecord profile);
}
