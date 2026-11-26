import 'package:core/core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// Andere Sportart mit Puls (FR-0221): Namen, Symbole und die Unterschätzung
/// der Belastung für die Anzeige.

String otherSportName(AppLocalizations l10n, OtherSport sport) =>
    switch (sport) {
      OtherSport.rope => l10n.otherSportRope,
      OtherSport.cycling => l10n.otherSportCycling,
      OtherSport.rowing => l10n.otherSportRowing,
      OtherSport.other => l10n.otherSportOther,
    };

IconData otherSportIcon(OtherSport sport) => switch (sport) {
  OtherSport.rope => Icons.sports_gymnastics,
  OtherSport.cycling => Icons.directions_bike,
  OtherSport.rowing => Icons.rowing,
  OtherSport.other => Icons.sports,
};

/// Rad und Rudern: Die Belastung aus dem Pulsbereich vom Laufen ist eher
/// unterschätzt (Hinweis in Zusammenfassung und Detail).
bool otherSportUnderestimated(OtherSport? sport) =>
    sport == OtherSport.cycling || sport == OtherSport.rowing;
