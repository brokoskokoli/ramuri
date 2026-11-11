part of 'plan_screen.dart';

/// Banner „Beschwerden gemeldet“ (FR-0203): fester Text ohne Diagnose, Knopf
/// „Meldung aufheben“; nach 7 Tagen zusätzlich die Erinnerung (nur Karte).
class _WarningBanner extends StatelessWidget {
  const _WarningBanner({
    required this.state,
    required this.today,
    required this.onLift,
  });

  final PlanViewState state;
  final DateTime today;

  /// `null`, solange eine Aktion läuft.
  final VoidCallback? onLift;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final c = RamuriColors.of(context);
    final reported = state.warning!.reportedOn;
    final days = planDay(today).difference(planDay(reported)).inDays;
    return RamuriCard(
      key: const Key('plan_warning_banner'),
      tone: RamuriCardTone.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.planWarnBannerText, style: text.bodyMedium),
          if (state.warningReminderDue) ...[
            const SizedBox(height: 10),
            Text(
              l.planWarnReminder(days),
              key: const Key('plan_warning_reminder'),
              style: text.bodySmall?.copyWith(color: c.textLabel),
            ),
          ],
          const SizedBox(height: 6),
          TextButton(
            key: const Key('plan_warning_lift'),
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

/// Nachfrage nach PAR-200 als Karte: zu leicht, passt, zu schwer. Ohne
/// Antwort bleibt die Karte und nichts ändert sich.
class _FeedbackCard extends StatelessWidget {
  const _FeedbackCard({required this.onAnswer});

  /// `null`, solange eine Aktion läuft.
  final ValueChanged<PlanFeedback>? onAnswer;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    Widget button(String key, String label, PlanFeedback a) => OutlinedButton(
      key: Key(key),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, RamuriTheme.minTarget),
      ),
      onPressed: onAnswer == null ? null : () => onAnswer!(a),
      child: Text(label),
    );
    return RamuriCard(
      key: const Key('plan_feedback_card'),
      tone: RamuriCardTone.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(l.planFeedbackTitle, style: text.titleSmall),
          ),
          const SizedBox(height: 4),
          Text(l.planFeedbackText, style: text.bodySmall),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              button(
                'plan_feedback_too_easy',
                l.planFeedbackTooEasy,
                PlanFeedback.tooEasy,
              ),
              button(
                'plan_feedback_fits',
                l.planFeedbackFits,
                PlanFeedback.fits,
              ),
              button(
                'plan_feedback_too_hard',
                l.planFeedbackTooHard,
                PlanFeedback.tooHard,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
