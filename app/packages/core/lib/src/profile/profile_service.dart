import '../../ports/clock.dart';
import '../../ports/storage_profile.dart';
import '../../ports/storage_settings.dart';
import 'heart_rate_resolution.dart';
import 'profile_parameters.dart';
import 'profile_validation.dart';
import 'resting_hr_origin.dart';

/// Einstellungsschlüssel: Zeitpunkt (UTC, ISO 8601) der letzten Änderung der
/// wirksamen HFmax (eingetragen oder aus dem Geburtsjahr genähert). Kein
/// Gesundheitswert; nach einer Änderung beginnt die Zählung der
/// Unterforderung neu (PAR-236).
const String profileHrMaxChangedAtKey = 'profile.hr_max_changed_at';

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
  /// Mit [settings] entfernt jedes Speichern, das den Ruhepuls ändert, dessen
  /// Kamera-Herkunft (Haltung, Zeitpunkt, Quelle; FR-0214, ADR-0011 Punkt 8),
  /// und jedes Speichern, das die wirksame HFmax ändert, setzt
  /// [profileHrMaxChangedAtKey].
  ProfileService(
    this._store,
    this._clock, {
    ProfileParameters? parameters,
    this.settings,
  }) : _params = parameters ?? const ProfileParameters.v5();

  final ProfileStore _store;
  final Clock _clock;
  final ProfileParameters _params;
  final SettingsStore? settings;

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
    final settings = this.settings;
    final before = settings == null ? null : await _store.read();
    // Zuerst die Herkunft entfernen, dann den Wert speichern: Scheitert eines
    // der beiden, bleibt nie ein neuer Wert mit der Herkunft des alten stehen
    // (schlimmstenfalls fehlt die Herkunft zu einem unveränderten Wert).
    if (settings != null &&
        before!.restingHeartRateBpm != profile.restingHeartRateBpm) {
      await RestingHrOrigin.clear(settings, at: _clock.now());
    }
    await _store.save(profile);
    if (settings != null && _maxBpm(before!) != _maxBpm(profile)) {
      await settings.set(
        profileHrMaxChangedAtKey,
        _clock.now().toUtc().toIso8601String(),
        at: _clock.now(),
      );
    }
    return ProfileSaveResult(saved: true, validation: v);
  }

  int? _maxBpm(ProfileRecord p) =>
      resolveHeartRate(p, currentYear: _year).basis.maxBpm;

  /// HFmax und abhängige Werte des gespeicherten Profils.
  Future<ResolvedHeartRate> resolve({int? externalRestingBpm}) async =>
      resolveHeartRate(
        await _store.read(),
        currentYear: _year,
        externalRestingBpm: externalRestingBpm,
      );
}
