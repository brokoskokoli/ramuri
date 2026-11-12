import 'package:core/core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../ui/ui.dart';
import '../plan/plan_texts.dart';
import '../summary/subjective_section.dart' show wellbeingWord;

/// Was die Karten auf „Heute“ über Hinweise brauchen (WP23 D2): der
/// Erholungshinweis des Tages (`null` = Karte ausgeblendet) und die offene
/// Pausenfrage.
class HomeHints {
  const HomeHints({this.card, this.pause});

  final RecoveryCard? card;
  final PauseQuestion? pause;

  static Future<HomeHints> load(StorageSession session, Clock clock) async {
    final service = HintService(session: session, clock: clock);
    final card = await service.recoveryCard();
    final pause = await service.pauseQuestion();
    return HomeHints(card: card, pause: pause);
  }
}

/// Der Text zum Hinweis (PAR-178 bis PAR-183, FR-0203): nur Beschreibung der
/// Daten und eine Empfehlung, nie eine Zahl oder ein Zustand.
String recoveryHintText(AppLocalizations l, Hint hint) {
  int n(EvidenceKey k) => (hint.evidenceOf(k) as num?)?.round() ?? 0;
  return switch (hint.code) {
    HintCode.warning => l.planWarnBannerText,
    HintCode.shortInterval => l.recoveryShortInterval(
      n(EvidenceKey.lastIntensiveDaysAgo),
    ),
    HintCode.steepIncrease => l.recoverySteepIncrease,
    HintCode.pause || HintCode.longPause =>
      hint.evidenceOf(EvidenceKey.planRestarted) != true
          // Der Plan blieb (z. B. Geh-Lauf-Abfolge): keine Aussage über ihn.
          ? l.recoveryPauseKept(n(EvidenceKey.daysSinceTraining))
          : hint.code == HintCode.pause
          ? l.recoveryPause(n(EvidenceKey.daysSinceTraining))
          : l.recoveryLongPause(n(EvidenceKey.daysSinceTraining)),
    HintCode.effortAbovePlan => l.recoveryEffort,
    HintCode.lowWellbeing => l.recoveryLowWellbeing,
  };
}

/// Die Belege zu „Worauf beruht das?“ als Zeilen (FR-0181): nur, was in den
/// Daten steht.
List<String> recoveryBasisLines(
  BuildContext context,
  AppLocalizations l,
  Hint hint,
) {
  final material = MaterialLocalizations.of(context);
  Object? ev(EvidenceKey k) => hint.evidenceOf(k);
  int n(EvidenceKey k) => (ev(k) as num?)?.round() ?? 0;
  String date(EvidenceKey k) => material.formatMediumDate(ev(k)! as DateTime);
  final lines = <String>[];
  void confirmations() {
    if (ev(EvidenceKey.allRecorded) == true) {
      lines.add(l.recoveryEvAllRecorded);
    }
    if (ev(EvidenceKey.pauseConfirmed) == true) {
      lines.add(l.recoveryEvPauseConfirmed);
    }
  }

  switch (hint.code) {
    case HintCode.warning:
      lines.add(l.recoveryEvWarning(date(EvidenceKey.warningReportedOn)));
    case HintCode.shortInterval:
      final kind = ev(EvidenceKey.plannedKind);
      if (kind is String) {
        lines.add(
          l.recoveryEvPlanned(
            planKindName(l, PlanUnitKind.values.byName(kind)),
          ),
        );
      }
      lines.add(
        l.recoveryEvLastIntensive(
          n(EvidenceKey.lastIntensiveDaysAgo),
          n(EvidenceKey.lastIntensiveRpe),
        ),
      );
    case HintCode.steepIncrease:
      lines
        ..add(
          l.recoveryEvIncrease(
            n(EvidenceKey.activeMinutes7d),
            n(EvidenceKey.weeklyAverageMinutes21d),
          ),
        )
        ..add(l.recoveryEvDataDays(n(EvidenceKey.daysOfData)));
      confirmations();
    case HintCode.pause || HintCode.longPause:
      lines.add(l.recoveryEvLastTraining(date(EvidenceKey.lastTrainingDay)));
      confirmations();
    case HintCode.effortAbovePlan:
      lines.add(
        l.recoveryEvEffort(
          n(EvidenceKey.easyRunsConsidered),
          n(EvidenceKey.easyRunsAboveRpe),
        ),
      );
    case HintCode.lowWellbeing:
      final w = n(EvidenceKey.wellbeing);
      lines.add(
        l.recoveryEvWellbeing(
          wellbeingWord(l, w),
          n(EvidenceKey.wellbeingDaysAgo),
        ),
      );
  }
  return lines;
}

/// Karte „Erholung“ in der Optik des Designs (Karte, Überschrift in Akzent,
/// Text, Link „Worauf beruht das?“), aber nur mit Texthinweis: keine Zahl, kein
/// Ring, kein Zustand (FR-0107, PAR-184). Das Modell ist `null` ohne
/// Auslöser; dann gibt es die Karte nicht.
class RecoveryCardView extends StatelessWidget {
  const RecoveryCardView({super.key, required this.card, this.onEasyRun});

  final RecoveryCard card;

  /// Knopf „Locker laufen“ (nur Hinweise mit Aktion, mit heute offener
  /// Einheit); `null` ohne Knopf.
  final VoidCallback? onEasyRun;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = Theme.of(context).textTheme;
    final c = RamuriColors.of(context);
    return RamuriCard(
      key: const Key('home_recovery_card'),
      radius: 24,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(
              l.recoveryTitle.toUpperCase(),
              style: t.labelMedium?.copyWith(
                color: c.textLabel,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            recoveryHintText(l, card.hint),
            key: const Key('home_recovery_text'),
            style: t.bodyMedium,
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: [
              if (onEasyRun != null)
                FilledButton(
                  key: const Key('home_recovery_easy'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, RamuriTheme.minTarget),
                  ),
                  onPressed: onEasyRun,
                  child: Text(l.recoveryEasyRun),
                ),
              TextButton(
                key: const Key('home_recovery_basis'),
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, RamuriTheme.minTarget),
                ),
                onPressed: () => showRecoveryBasis(context, card),
                child: Text(l.recoveryBasis),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// „Worauf beruht das?“: die Datenbelege des Hinweises.
Future<void> showRecoveryBasis(BuildContext context, RecoveryCard card) {
  final l = AppLocalizations.of(context);
  return showBasisDialog(context, recoveryBasisLines(context, l, card.hint));
}

/// Die Belege zur heutigen Einheit (FR-0179, FR-0180): nur die geplante
/// Einheit aus dem Plan; `null`, wenn es keine Erklärung gibt (Ruhetag, keine
/// Einheit). Belastungswerte stehen hier nicht, weil Heute sie nicht lädt.
List<String>? trainingBasisLines(AppLocalizations l, PlanUnit? unit) {
  final e = explainTrainingRecommendation(plannedUnit: unit);
  if (e == null) return null;
  final kind = PlanUnitKind.values.byName(
    e.evidenceOf(EvidenceKey.plannedKind)! as String,
  );
  return [l.homeTodayBasisText(planKindName(l, kind))];
}

/// Dialog mit den Belegen als Zeilen.
Future<void> showBasisDialog(BuildContext context, List<String> lines) {
  final l = AppLocalizations.of(context);
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      key: const Key('home_recovery_basis_dialog'),
      title: Text(l.recoveryBasis),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < lines.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(lines[i], key: Key('home_recovery_basis_$i')),
            ),
        ],
      ),
      actions: [
        TextButton(
          key: const Key('home_recovery_basis_close'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.recoveryBasisClose),
        ),
      ],
    ),
  );
}

/// Pausenfrage (PAR-202): ab 7 Tagen ohne erfasstes Training, außer bei der
/// Zusage „alles erfasst“. „Ja“ startet den Plan ruhiger neu, „Nein“ ändert
/// nichts; ohne Antwort bleibt alles, wie es ist.
class PauseQuestionCard extends StatelessWidget {
  const PauseQuestionCard({
    super.key,
    required this.question,
    required this.onAnswer,
  });

  final PauseQuestion question;

  /// `null`, solange eine Aktion läuft.
  final ValueChanged<bool>? onAnswer;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = Theme.of(context).textTheme;
    Widget button(String key, String label, bool answer) => OutlinedButton(
      key: Key(key),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, RamuriTheme.minTarget),
      ),
      onPressed: onAnswer == null ? null : () => onAnswer!(answer),
      child: Text(label),
    );
    return RamuriCard(
      key: const Key('home_pause_card'),
      radius: 24,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(l.homePauseTitle, style: t.titleSmall),
          ),
          const SizedBox(height: 4),
          Text(
            l.homePauseText(question.daysSinceTraining),
            key: const Key('home_pause_text'),
            style: t.bodyMedium,
          ),
          const SizedBox(height: 4),
          Text(l.homePauseNote, style: t.bodySmall),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              button('home_pause_yes', l.homePauseYes, true),
              button('home_pause_no', l.homePauseNo, false),
            ],
          ),
        ],
      ),
    );
  }
}

/// Erinnerung nach 7 Tagen unter Warnsignal (FR-0203, nur Karte, keine
/// Benachrichtigung).
class WarningReminderCard extends StatelessWidget {
  const WarningReminderCard({
    super.key,
    required this.days,
    required this.onLift,
  });

  final int days;

  /// `null`, solange eine Aktion läuft.
  final VoidCallback? onLift;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = Theme.of(context).textTheme;
    return RamuriCard(
      key: const Key('home_warning_reminder'),
      radius: 24,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(l.homeWarnReminderTitle, style: t.titleSmall),
          ),
          const SizedBox(height: 4),
          Text(l.planWarnReminder(days), style: t.bodyMedium),
          const SizedBox(height: 6),
          TextButton(
            key: const Key('home_warning_lift'),
            style: TextButton.styleFrom(
              minimumSize: const Size(0, RamuriTheme.minTarget),
            ),
            onPressed: onLift,
            child: Text(l.planWarnLift),
          ),
        ],
      ),
    );
  }
}

/// Bestätigung für „Locker laufen“: das Ersetzen der heutigen Einheit aus
/// WP22 ([PlanController.checkReplace]) mit neuer Dauer; der Plan ändert sich
/// erst nach „Ersetzen“. [check] `null` (Prüfung gescheitert): Hinweis,
/// Bestätigen gesperrt.
class EasyRunDialog extends StatelessWidget {
  const EasyRunDialog({super.key, required this.check});

  final PlanReplaceCheck? check;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = Theme.of(context).textTheme;
    final c = check;
    final allowed = c != null && c.allowed;
    final String message;
    if (c == null) {
      message = l.calendarCheckFailed;
    } else if (c.blocked != null) {
      message = l.calendarReplaceBlocked;
    } else {
      message = l.calendarReplaceNew(planUnitText(l, c.unit!));
    }
    return AlertDialog(
      key: const Key('home_easy_dialog'),
      title: Text(l.calendarReplaceTitle),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message, key: const Key('home_easy_message')),
          const SizedBox(height: 12),
          Text(l.calendarReplaceKeeps, style: t.bodySmall),
          Text(l.calendarChangeOnlyAfterConfirm, style: t.bodySmall),
        ],
      ),
      actions: [
        TextButton(
          key: const Key('home_easy_cancel'),
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l.calendarMoveCancel),
        ),
        FilledButton(
          key: const Key('home_easy_confirm'),
          onPressed: allowed ? () => Navigator.of(context).pop(true) : null,
          child: Text(l.calendarReplaceConfirm),
        ),
      ],
    );
  }
}
