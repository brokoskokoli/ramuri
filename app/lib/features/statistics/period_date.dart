import 'package:flutter/material.dart';

import '../settings/unit_format.dart' show asOfDateText;

/// Datum eines Zeitraums auf „Fortschritt“ (FR-0044): ohne Jahr, solange alle
/// Tage des Zeitraums im laufenden Jahr liegen; sonst mit Jahr im Format der
/// Sprache, wie bei „Stand“ (FR-0059). Gehört das Datum zu einem Zeitraum mit
/// Anfang und Ende, stehen beide in [span], damit beide Enden gleich aussehen.
String periodDateText(
  BuildContext context,
  DateTime day, {
  required int currentYear,
  Iterable<DateTime> span = const [],
}) {
  final withYear = [day, ...span].any((d) => d.year != currentYear);
  if (!withYear) return MaterialLocalizations.of(context).formatMediumDate(day);
  return asOfDateText(Localizations.localeOf(context).languageCode, day);
}
