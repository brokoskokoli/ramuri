import '../../ports/storage_profile.dart';
import 'profile_parameters.dart';

/// Profilfelder, an denen eine Meldung hängt.
enum ProfileField {
  birthYear,
  bodyWeight,
  bodyHeight,
  restingHeartRate,
  maxHeartRate,
}

/// Grund einer Meldung; die Oberfläche (WP05 Teil B) ordnet Texte zu.
enum ProfileIssueCode {
  /// Geburtsjahr, Gewicht oder Größe nicht positiv oder keine endliche Zahl
  /// (OQ-0065).
  notPositive,

  /// PAR-016: HFmax außerhalb des Bereichs.
  maxHrOutOfRange,

  /// PAR-016: HFmax weicht stark von der Näherung ab (nur Hinweis).
  maxHrDeviatesFromEstimate,

  /// PAR-017: Ruhepuls außerhalb des Bereichs.
  restHrOutOfRange,

  /// PAR-017: Ruhepuls im Randbereich (nur Hinweis).
  restHrUnusual,

  /// PAR-018: eingegebene HFmax ist nicht größer als der eingegebene Ruhepuls.
  maxNotAboveResting,
}

enum ProfileIssueSeverity {
  /// Eingabe wird nicht gespeichert.
  rejected,

  /// Eingabe wird gespeichert, die Oberfläche zeigt einen Hinweis.
  hint,
}

class ProfileIssue {
  const ProfileIssue(this.field, this.code, this.severity);

  final ProfileField field;
  final ProfileIssueCode code;
  final ProfileIssueSeverity severity;

  @override
  String toString() => 'ProfileIssue($field, $code, $severity)';
}

class ProfileValidation {
  const ProfileValidation(this.issues);

  final List<ProfileIssue> issues;

  Iterable<ProfileIssue> get rejections =>
      issues.where((i) => i.severity == ProfileIssueSeverity.rejected);

  Iterable<ProfileIssue> get hints =>
      issues.where((i) => i.severity == ProfileIssueSeverity.hint);

  /// Speichern erlaubt: keine Ablehnung (Hinweise sind erlaubt).
  bool get canSave => rejections.isEmpty;
}

/// Alter in ganzen Jahren aus dem Geburtsjahr; `null`, wenn unbekannt oder
/// nicht positiv (ein Geburtsjahr in der Zukunft ergibt kein Alter).
int? ageFromBirthYear(int? birthYear, int currentYear) {
  if (birthYear == null) return null;
  final age = currentYear - birthYear;
  return age > 0 ? age : null;
}

/// Näherung `208 − 0,7 · Alter` (FR-0004), auf ganze bpm gerundet (halbe
/// nach oben). `null` ohne Alter oder wenn das Ergebnis nicht positiv ist.
int? approximateMaxHeartRate(int? age) {
  if (age == null || age <= 0) return null;
  final tenths =
      ProfileParameters.approxBaseTenths -
      ProfileParameters.approxPerYearTenths * age;
  if (tenths <= 0) return null;
  return (tenths + 5) ~/ 10;
}

bool _positive(num? v) => v == null || (v.isFinite && v > 0);

/// Prüft ein Profil nach OQ-0065, PAR-016, PAR-017 und PAR-018 (nur die
/// Eingaben im Profil untereinander; Konflikte mit Näherung oder anderen
/// Quellen löst die Auflösung, PAR-018 Satz 2). PAR-019 verhindert nichts.
ProfileValidation validateProfileInput(
  ProfileRecord p, {
  required int currentYear,
  ProfileParameters params = const ProfileParameters.v3(),
}) {
  final issues = <ProfileIssue>[];
  void add(ProfileField f, ProfileIssueCode c, ProfileIssueSeverity s) =>
      issues.add(ProfileIssue(f, c, s));
  const rejected = ProfileIssueSeverity.rejected;
  const hint = ProfileIssueSeverity.hint;

  // Das Geburtsjahr wird statt des Alters gespeichert; „Alter nur positiv“
  // (OQ-0065) heißt: Geburtsjahr vor dem Stichtagsjahr.
  final birthYear = p.birthYear;
  if (!_positive(birthYear) ||
      (birthYear != null && ageFromBirthYear(birthYear, currentYear) == null)) {
    add(ProfileField.birthYear, ProfileIssueCode.notPositive, rejected);
  }
  if (!_positive(p.bodyWeightKg)) {
    add(ProfileField.bodyWeight, ProfileIssueCode.notPositive, rejected);
  }
  if (!_positive(p.bodyHeightMeters)) {
    add(ProfileField.bodyHeight, ProfileIssueCode.notPositive, rejected);
  }

  final max = p.maxHeartRateBpm;
  var maxInRange = false;
  if (max != null) {
    if (max < params.maxHrRejectBelowBpm || max > params.maxHrRejectAboveBpm) {
      add(
        ProfileField.maxHeartRate,
        ProfileIssueCode.maxHrOutOfRange,
        rejected,
      );
    } else {
      maxInRange = true;
      final approx = approximateMaxHeartRateTenths(
        ageFromBirthYear(p.birthYear, currentYear),
      );
      if (approx != null) {
        final dev = (max * 10 - approx).abs();
        if (dev > params.maxHrHintDeviationBpm * 10) {
          add(
            ProfileField.maxHeartRate,
            ProfileIssueCode.maxHrDeviatesFromEstimate,
            hint,
          );
        }
      }
    }
  }

  final rest = p.restingHeartRateBpm;
  var restInRange = false;
  if (rest != null) {
    if (rest < params.restHrRejectBelowBpm ||
        rest > params.restHrRejectAboveBpm) {
      add(
        ProfileField.restingHeartRate,
        ProfileIssueCode.restHrOutOfRange,
        rejected,
      );
    } else {
      restInRange = true;
      if (rest < params.restHrHintBelowBpm ||
          rest > params.restHrHintAboveBpm) {
        add(
          ProfileField.restingHeartRate,
          ProfileIssueCode.restHrUnusual,
          hint,
        );
      }
    }
  }

  // PAR-018: beide Werte sind Eingaben im Profil, also nicht speichern.
  if (maxInRange && restInRange && max! <= rest!) {
    add(
      ProfileField.maxHeartRate,
      ProfileIssueCode.maxNotAboveResting,
      rejected,
    );
  }
  return ProfileValidation(issues);
}

/// Näherung in Zehntel bpm (ohne Rundung), nur für den Abweichungshinweis.
int? approximateMaxHeartRateTenths(int? age) {
  if (age == null || age <= 0) return null;
  return ProfileParameters.approxBaseTenths -
      ProfileParameters.approxPerYearTenths * age;
}
