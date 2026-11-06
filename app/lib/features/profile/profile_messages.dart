import 'package:core/core.dart';

import '../../l10n/app_localizations.dart';

/// Text zu einer Meldung aus `core` (PAR-016 bis PAR-018, OQ-0065). Die
/// Grenzen kommen aus [ProfileParameters], nicht aus dem Text.
String profileIssueText(
  AppLocalizations l10n,
  ProfileIssue issue, {
  ProfileParameters params = const ProfileParameters.v4(),
}) => switch (issue.code) {
  ProfileIssueCode.notPositive => l10n.profileNotPositive,
  ProfileIssueCode.maxHrOutOfRange => l10n.profileMaxHrOutOfRange(
    params.maxHrRejectBelowBpm,
    params.maxHrRejectAboveBpm,
  ),
  ProfileIssueCode.maxHrDeviatesFromEstimate => l10n.profileMaxHrDeviates(
    params.maxHrHintDeviationBpm,
  ),
  ProfileIssueCode.restHrOutOfRange => l10n.profileRestHrOutOfRange(
    params.restHrRejectBelowBpm,
    params.restHrRejectAboveBpm,
  ),
  ProfileIssueCode.restHrUnusual => l10n.profileRestHrUnusual(
    params.restHrHintBelowBpm,
    params.restHrHintAboveBpm,
  ),
  ProfileIssueCode.maxNotAboveResting => l10n.profileMaxNotAboveResting,
};
