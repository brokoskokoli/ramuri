import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import '../../ui/ui.dart';

/// Ein Satz Grund einer Fassung (FR-0170, FR-0180) aus Auslöser und
/// Grund-Code ([Explanation.code]) und gespeicherten Daten. Den Anteil der
/// Wochenzeit nennt der Satz nur, wenn diese Fassung den Anker selbst gesetzt
/// hat (sonst wäre der Wert von einer früheren Woche).
String planChangeReasonText(
  AppLocalizations l,
  Explanation e,
  PlanVersionRecord v,
) {
  switch (e.code) {
    case 'warning':
      return l.planChangeReasonWarning;
    case 'warningLifted':
      return l.planChangeReasonWarningLifted;
    case 'weekly':
      final share = _ownShare(v);
      return share == null
          ? l.planChangeReasonWeekly
          : l.planChangeReasonWeeklyShare((share * 100).round());
    case 'feedback':
      return l.planChangeReasonFeedback;
    case 'pause':
      return l.planChangeReasonPause;
    case 'goalChange':
      return l.planChangeReasonGoalChange;
    case 'manual':
      return l.planChangeReasonManual;
    case 'run':
      return l.planChangeReasonRun;
    case 'ruleVersion':
      return l.planChangeReasonRuleVersion;
    case walkRunRepeatReason:
      return l.planChangeReasonWalkRepeat;
    case 'create':
      return l.planChangeReasonCreate;
    default:
      // Zieländerung mit Wochenbewertung (NB8 6): `goalChange,<Gründe>`.
      const prefix = 'goalChange,';
      if (e.code.startsWith(prefix)) {
        final weekly = _weeklyReasons(l, e.code.substring(prefix.length), v);
        if (weekly != null) {
          return '${l.planChangeReasonGoalChange} $weekly';
        }
        return l.planChangeReasonGoalChange;
      }
      // Regelversion mit Wochenbewertung (NB6 1): `ruleVersion,<Gründe>`.
      const ruleVersionPrefix = 'ruleVersion,';
      if (e.code.startsWith(ruleVersionPrefix)) {
        final weekly = _weeklyReasons(
          l,
          e.code.substring(ruleVersionPrefix.length),
          v,
        );
        if (weekly != null) return weekly;
      }
      return _weeklyReasons(l, e.code, v) ?? l.planChangeReasonOther;
  }
}

/// Gründe der Wochenprüfung (PAR-201): kommagetrennte Codes
/// ([WeekAdjustmentReason]), je ein Satz; der Anteil steht nur dabei, wenn
/// diese Fassung ihn trägt. `null`, wenn der Code keiner davon ist.
String? _weeklyReasons(AppLocalizations l, String code, PlanVersionRecord v) {
  final names = {for (final r in WeekAdjustmentReason.values) r.name: r};
  final parts = code.split(',');
  if (parts.isEmpty || !parts.every(names.containsKey)) return null;
  final reasons = {for (final p in parts) names[p]!};
  final share = _ownShare(v);
  final percent = share == null ? null : (share * 100).round();
  return [
    if (reasons.contains(WeekAdjustmentReason.repeatWeek))
      percent == null
          ? l.planChangeReasonRepeatWeek
          : l.planChangeReasonRepeatWeekShare(percent),
    if (reasons.contains(WeekAdjustmentReason.noIncrease))
      percent == null
          ? l.planChangeReasonNoIncrease
          : l.planChangeReasonNoIncreaseShare(percent),
    if (reasons.contains(WeekAdjustmentReason.fatigue))
      l.planChangeReasonFatigue,
  ].join(' ');
}

double? _ownShare(PlanVersionRecord v) {
  try {
    final i = v.inputs;
    final share = i.achievedShare;
    final d = v.validFrom;
    final monday = d.subtract(Duration(days: d.weekday - DateTime.monday));
    return share != null && i.anchor == monday ? share : null;
  } on Object {
    return null;
  }
}

/// Karte „Plan angepasst“ (PAR-204, FR-0170): ein Satz Grund, nur bei größerer
/// Änderung und bis zum „Verstanden“. Sie verschiebt keinen Termin (OQ-0011).
/// Gedacht für „Plan“ und „Heute“.
class PlanChangeCard extends StatelessWidget {
  const PlanChangeCard({
    super.key = const Key('plan_change_card'),
    required this.notice,
    required this.onSeen,
    this.onHistory,
  });

  final PlanChangeNotice notice;

  /// `null`, solange eine Aktion läuft.
  final VoidCallback? onSeen;

  /// Öffnet den Verlauf; ohne: kein Knopf.
  final VoidCallback? onHistory;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final style = TextButton.styleFrom(
      minimumSize: const Size(0, RamuriTheme.minTarget),
    );
    return RamuriCard(
      tone: RamuriCardTone.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(l.planChangeTitle, style: text.titleSmall),
          ),
          const SizedBox(height: 4),
          Text(
            planChangeReasonText(l, notice.explanation, notice.version),
            key: const Key('plan_change_reason'),
            style: text.bodyMedium,
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: [
              TextButton(
                key: const Key('plan_change_seen'),
                style: style,
                onPressed: onSeen,
                child: Text(l.planChangeSeen),
              ),
              if (onHistory != null)
                TextButton(
                  key: const Key('plan_change_history'),
                  style: style,
                  onPressed: onHistory,
                  child: Text(l.planChangeHistory),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Vorschlag „Woche wiederholen“ (PAR-140) an der Geh-Lauf-Woche. Die App
/// fragt, der Nutzer entscheidet.
class PlanWalkRepeatCard extends StatelessWidget {
  const PlanWalkRepeatCard({
    super.key = const Key('plan_walk_repeat_card'),
    required this.proposal,
    required this.onAccept,
    required this.onDecline,
  });

  final WalkRunWeekProposal proposal;

  /// `null`, solange eine Aktion läuft.
  final VoidCallback? onAccept;
  final VoidCallback? onDecline;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    // Vor Woche 5, Lauf 3 gilt der Vorschlag nur Lauf 2 (PAR-140).
    final session = proposal.suggestion.scope == WalkRunRepeatScope.session;
    return RamuriCard(
      tone: RamuriCardTone.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(
              session ? l.planWalkRepeatSessionTitle : l.planWalkRepeatTitle,
              style: text.titleSmall,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            session
                ? l.planWalkRepeatSessionText(proposal.programWeek + 1)
                : l.planWalkRepeatText(
                    proposal.programWeek + 1,
                    proposal.doneCount,
                    proposal.sessionCount,
                  ),
            style: text.bodyMedium,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(
                key: const Key('plan_walk_repeat_yes'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, RamuriTheme.minTarget),
                ),
                onPressed: onAccept,
                child: Text(
                  session ? l.planWalkRepeatSessionYes : l.planWalkRepeatYes,
                ),
              ),
              OutlinedButton(
                key: const Key('plan_walk_repeat_no'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, RamuriTheme.minTarget),
                ),
                onPressed: onDecline,
                child: Text(l.planWalkRepeatNo),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Verlauf der Änderungen (FR-0170): alle Fassungen, neueste zuerst; größere
/// sind gekennzeichnet, kleinere stehen nur hier. Vollbild über der
/// Navigation.
class PlanHistoryScreen extends StatelessWidget {
  const PlanHistoryScreen({super.key, required this.load});

  final Future<List<PlanVersionRecord>> Function() load;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(),
      body: FutureBuilder<List<PlanVersionRecord>>(
        future: load(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  l.planHistoryFailed,
                  key: const Key('plan_history_failed'),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          final list = snap.data;
          if (list == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView(
            key: const Key('plan_history'),
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            children: [
              Semantics(
                header: true,
                child: Text(
                  l.planHistoryTitle,
                  style: RamuriType.of(context).pageTitle,
                ),
              ),
              const SizedBox(height: 14),
              for (final v in list.reversed) ...[
                _HistoryRow(version: v, text: text),
                const SizedBox(height: 10),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.version, required this.text});

  final PlanVersionRecord version;
  final TextTheme text;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = RamuriColors.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final s = version.summary;
    final count = s['changedUnitCount'];
    final head = s['headline'];
    String? weekTime;
    if (head is Map && head['oldMinutes'] is int && head['newMinutes'] is int) {
      weekTime = l.planChangeWeekTime(
        head['oldMinutes'] as int,
        head['newMinutes'] as int,
      );
    }
    final larger = isLargerPlanChange(version);
    return RamuriCard(
      key: Key('plan_history_${version.id}'),
      tone: RamuriCardTone.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            DateFormat.yMMMMEEEEd(lang).format(version.validFrom),
            style: text.titleSmall,
          ),
          const SizedBox(height: 2),
          Text(
            planChangeReasonText(l, explainPlanChange(version), version),
            style: text.bodyMedium,
          ),
          if (version.trigger != PlanTrigger.create) ...[
            if (weekTime != null)
              Text(
                weekTime,
                style: text.bodySmall?.copyWith(color: c.textLabel),
              ),
            if (count is int && count > 0)
              Text(
                l.planHistoryUnits(count),
                style: text.bodySmall?.copyWith(color: c.textLabel),
              ),
          ],
          if (larger)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                l.planHistoryLarger,
                key: Key('plan_history_larger_${version.id}'),
                style: text.labelMedium,
              ),
            ),
        ],
      ),
    );
  }
}
