import 'package:core/core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../ui/ui.dart';
import '../profile/profile_screen.dart';
import '../recalculation/recalculation_controller.dart';
import 'plan_controller.dart';

/// Hinweis bzw. Frage der Unterforderung (PAR-236) auf der Plan-Seite und
/// auf „Heute“. Hinweis: „HFmax prüfen“ (öffnet das Profil) oder „Passt so“;
/// Frage: „Ja, steigern“ oder „Nein“. Ohne Antwort bleibt die Karte, und
/// nichts ändert sich.
class PlanUnderloadCard extends StatelessWidget {
  const PlanUnderloadCard({
    super.key = const Key('plan_underload_card'),
    required this.prompt,
    required this.onCheckHrMax,
    required this.onHintFine,
    required this.onAnswer,
  });

  final PlanUnderloadPrompt prompt;

  /// „HFmax prüfen“; `null`, solange eine Aktion läuft.
  final VoidCallback? onCheckHrMax;

  /// „Passt so“; `null`, solange eine Aktion läuft.
  final VoidCallback? onHintFine;

  /// „Ja, steigern“ (`true`) oder „Nein“ (`false`); `null`, solange eine
  /// Aktion läuft.
  final ValueChanged<bool>? onAnswer;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final hint = prompt == PlanUnderloadPrompt.hint;
    final answer = onAnswer;
    return RamuriCard(
      tone: RamuriCardTone.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            hint ? l.planUnderloadHintText : l.planUnderloadQuestionText,
            key: Key(hint ? 'plan_underload_hint' : 'plan_underload_question'),
            style: text.bodyMedium,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(
                key: Key(hint ? 'plan_underload_check' : 'plan_underload_yes'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, RamuriTheme.minTarget),
                ),
                onPressed: hint
                    ? onCheckHrMax
                    : answer == null
                    ? null
                    : () => answer(true),
                child: Text(
                  hint ? l.planUnderloadHintCheck : l.planUnderloadQuestionYes,
                ),
              ),
              OutlinedButton(
                key: Key(hint ? 'plan_underload_fine' : 'plan_underload_no'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, RamuriTheme.minTarget),
                ),
                onPressed: hint
                    ? onHintFine
                    : answer == null
                    ? null
                    : () => answer(false),
                child: Text(
                  hint ? l.planUnderloadHintFine : l.planUnderloadQuestionNo,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Aktionen der Karte [PlanUnderloadCard], gemeinsam für Plan-Seite und
/// „Heute“. Eine gescheiterte Antwort meldet eine Snackbar; die Karte bleibt.
class PlanUnderloadActions {
  const PlanUnderloadActions({
    required this.controller,
    required this.session,
    required this.clock,
    required this.recalculation,
  });

  final PlanController controller;
  final StorageSession session;
  final Clock clock;

  /// Für die Neuberechnung nach „Ja, steigern“ (exklusiv) und das Profil;
  /// ohne: „HFmax prüfen“ schließt nur den Hinweis.
  final RecalculationController? recalculation;

  /// „HFmax prüfen“: Hinweis beantwortet, dann das Profil mit dem Feld HFmax
  /// im Fokus. Eine Änderung der HFmax dort startet die Zählung neu.
  Future<void> checkHrMax(BuildContext context) async {
    final ok = await _hint(context);
    final recalc = recalculation;
    if (!ok || recalc == null || !context.mounted) return;
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        builder: (_) => ProfileScreen(
          session: session,
          clock: clock,
          recalculation: recalc,
          focusMaxHeartRate: true,
        ),
      ),
    );
  }

  /// „Passt so“.
  Future<void> hintFine(BuildContext context) => _hint(context);

  /// „Ja, steigern“ ([raise]) oder „Nein“. Ja rechnet exklusiv mit dem
  /// Neuberechnungsdienst.
  Future<void> answer(BuildContext context, bool raise) async {
    final messenger = ScaffoldMessenger.of(context);
    final l = AppLocalizations.of(context);
    final recalc = recalculation;
    final r = raise && recalc != null
        ? await recalc.exclusive(() => controller.answerUnderloadQuestion(true))
        : await controller.answerUnderloadQuestion(raise);
    if (r != PlanActionResult.done) _failed(messenger, l);
  }

  Future<bool> _hint(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final l = AppLocalizations.of(context);
    final r = await controller.answerUnderloadHint();
    if (r != PlanActionResult.done) _failed(messenger, l);
    return r == PlanActionResult.done;
  }

  static void _failed(ScaffoldMessengerState m, AppLocalizations l) => m
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        key: const Key('plan_underload_failed'),
        content: Text(l.planUnderloadFailed),
      ),
    );
}
