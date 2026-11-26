import 'package:core/core.dart';

import '../../l10n/app_localizations.dart';

/// Grund aus der Profilbasis (Ruhepuls, HFmax): Die Rechnung prüft die Basis
/// vor den Pulswerten. Einzige Liste dieser Gründe; die Anzeige nennt bei einem
/// Lauf ohne Puls statt ihrer den fehlenden Puls (FR-0057, FR-0055).
bool isProfileBasisReason(UnavailableReason reason) => switch (reason) {
  UnavailableReason.missingMaxHeartRate ||
  UnavailableReason.missingRestingHeartRate ||
  UnavailableReason.maxNotAboveResting ||
  UnavailableReason.reserveTooSmall => true,
  _ => false,
};

/// Text zu einem Grund, warum ein Fitnesswert fehlt (FR-0068). Jeder Grund hat
/// einen eigenen Text; fehlende Profilwerte weisen auf das Profil hin
/// (FR-0055). Hatte der Lauf keinen Puls ([hasHeartRate] false), nennt auch ein
/// Grund aus der Profilbasis den fehlenden Puls (FR-0057,
/// [isProfileBasisReason]).
String reasonText(
  AppLocalizations l10n,
  UnavailableReason reason, {
  bool hasHeartRate = true,
}) => !hasHeartRate && isProfileBasisReason(reason)
    ? l10n.sumNoHeartRate
    : switch (reason) {
        UnavailableReason.missingMaxHeartRate ||
        UnavailableReason.missingRestingHeartRate ||
        UnavailableReason.maxNotAboveResting ||
        UnavailableReason.reserveTooSmall ||
        UnavailableReason.missingLoadCoefficients => l10n.runZoneNoBasis,
        UnavailableReason.noHeartRate => l10n.sumNoHeartRate,
        UnavailableReason.insufficientCoverage => l10n.sumCoverageLow,
        UnavailableReason.noMovingTime => l10n.statReasonNoMoving,
        UnavailableReason.insufficientData => l10n.statReasonInsufficient,
        UnavailableReason.noValidSection => l10n.statReasonNoSection,
        UnavailableReason.allEstimatesImplausible => l10n.statReasonImplausible,
        UnavailableReason.spreadTooHigh => l10n.statReasonSpread,
        UnavailableReason.currentWindowTooSmall => l10n.statReasonCurrentWindow,
        UnavailableReason.referenceWindowTooSmall =>
          l10n.statReasonReferenceWindow,
      };
