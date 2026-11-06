import '../../ports/clock.dart';
import '../../ports/storage_profile.dart';
import 'heart_rate_resolution.dart';
import 'profile_parameters.dart';
import 'profile_validation.dart';

/// Ergebnis von [ProfileService.save].
class ProfileSaveResult {
  const ProfileSaveResult({required this.saved, required this.validation});

  /// Das Profil wurde gespeichert (nur ohne Ablehnung).
  final bool saved;
  final ProfileValidation validation;
}

/// Profil laden, prüfen, speichern (FR-0002) über den Port [ProfileStore].
/// Alle Felder dürfen leer sein; ein leeres Profil sperrt nichts.
class ProfileService {
  ProfileService(this._store, this._clock, {ProfileParameters? parameters})
    : _params = parameters ?? const ProfileParameters.v3();

  final ProfileStore _store;
  final Clock _clock;
  final ProfileParameters _params;

  int get _year => _clock.now().year;

  Future<ProfileRecord> load() => _store.read();

  /// Prüft [profile] und speichert es nur ohne Ablehnung (PAR-016 bis
  /// PAR-018). Bei Ablehnung bleibt das gespeicherte Profil unverändert.
  Future<ProfileSaveResult> save(ProfileRecord profile) async {
    final v = validateProfileInput(
      profile,
      currentYear: _year,
      params: _params,
    );
    if (!v.canSave) return ProfileSaveResult(saved: false, validation: v);
    await _store.save(profile);
    return ProfileSaveResult(saved: true, validation: v);
  }

  /// HFmax und abhängige Werte des gespeicherten Profils.
  Future<ResolvedHeartRate> resolve({int? externalRestingBpm}) async =>
      resolveHeartRate(
        await _store.read(),
        currentYear: _year,
        externalRestingBpm: externalRestingBpm,
      );
}
