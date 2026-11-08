import 'package:core/core.dart';

import '../../l10n/app_localizations.dart';

/// Text der Qualitätsstufe eines Werts (FR-0053). Die eine Quelle für die
/// Erklärungsseite und die Fortschrittsseite. Die Stufe ist eine interne
/// Einteilung, keine Genauigkeitsangabe (FR-0054).
String qualityStageText(AppLocalizations l10n, ValueQuality quality) =>
    switch (quality) {
      ValueQuality.provisional => l10n.explQualityProvisional,
      ValueQuality.sufficient => l10n.explQualitySufficient,
      ValueQuality.good => l10n.explQualityGood,
      ValueQuality.undeterminable => l10n.explQualityUndeterminable,
    };
