import '../../l10n/app_localizations.dart';
import '../../ui/format/plan_texts.dart';
import '../../ui/format/unit_format.dart';
import 'plan_controller.dart' show PlanDoneRun;

/// Texte einer erledigten Einheit aus dem zugeordneten Lauf ([PlanDoneRun]);
/// die übrigen Texte der Plan-Seite stehen in `ui/format/plan_texts.dart`.

/// Erste Zeile einer erledigten Einheit (FR-0171): Bewegungszeit und Strecke
/// des zugeordneten Laufs im gewählten Maß, etwa „52 min · 9,1 km“; beim
/// Laufband die Strecke des Bands und „Laufband“ wie in der Laufliste
/// (FR-0196). Fehlende Werte stehen als „–“.
String planDoneRunLine(
  AppLocalizations l,
  UnitFormatter formatter,
  PlanDoneRun run,
) {
  final moving = run.movingTime;
  return [
    moving == null
        ? UnitFormatter.noValue
        : planDurationText(l, (moving.inSeconds / 60).round()),
    formatter.distanceShort(run.distanceMeters),
    if (run.treadmill) l.treadmillHistoryBadge,
  ].join(' · ');
}

/// Kennzeichen „locker“ oder „intensiv“ nach PAR-058; `null` ohne Puls und
/// RPE (FR-0171).
String? planDoneIntensity(AppLocalizations l, PlanDoneRun run) =>
    switch (run.intensive) {
      true => l.planRunIntensive,
      false => l.planRunEasy,
      null => null,
    };
