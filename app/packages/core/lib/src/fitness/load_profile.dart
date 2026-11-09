import 'banister_trimp.dart';
import 'edwards_trimp.dart';
import 'heart_rate_basis.dart';

/// Belastungsprofil (FR-0197): welches TRIMP-Modell die Tageslast rechnet.
/// Start ist [edwards].
enum LoadProfile {
  edwards,
  banister;

  /// Gespeicherter Name; unbekannt oder `null` -> [edwards] (Start).
  static LoadProfile fromStorage(String? value) => values.firstWhere(
    (p) => p.name == value,
    orElse: () => LoadProfile.edwards,
  );
}

/// Warum ein Profil nicht anwendbar ist.
enum LoadProfileIssue { missingRestingHeartRate, missingCoefficients }

/// Ergebnis der Profilauflösung: entweder ein [model] oder die [issues].
/// Es gibt keinen stillen Wechsel auf ein anderes Profil (FR-0197, OQ-0053):
/// Ist das gewählte Profil nicht anwendbar, steht das hier und die App zeigt
/// es an.
class LoadProfileResolution {
  const LoadProfileResolution._(this.profile, this.model, this.issues);

  final LoadProfile profile;

  /// Das anzuwendende Modell, `null` bei nicht anwendbarem Profil.
  final LoadModel? model;
  final List<LoadProfileIssue> issues;

  bool get applicable => model != null;
}

/// Wählt das Modell zum [requested] Profil. Edwards ist immer anwendbar (die
/// HFmax-Prüfung macht das Modell selbst). Banister nur mit Ruhepuls UND
/// Koeffizientenangabe, sonst nicht anwendbar mit den fehlenden Angaben.
LoadProfileResolution resolveLoadProfile({
  required LoadProfile requested,
  required HeartRateBasis basis,
  required LoadCoefficients? coefficients,
}) {
  switch (requested) {
    case LoadProfile.edwards:
      return const LoadProfileResolution._(
        LoadProfile.edwards,
        EdwardsTrimp(),
        [],
      );
    case LoadProfile.banister:
      final issues = [
        if (basis.usableRestingBpm == null)
          LoadProfileIssue.missingRestingHeartRate,
        if (coefficients == null) LoadProfileIssue.missingCoefficients,
      ];
      if (issues.isNotEmpty) {
        return LoadProfileResolution._(LoadProfile.banister, null, issues);
      }
      return LoadProfileResolution._(
        LoadProfile.banister,
        BanisterTrimp(coefficients!),
        const [],
      );
  }
}
