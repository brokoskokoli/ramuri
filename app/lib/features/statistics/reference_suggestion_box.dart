import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import '../../ui/ui.dart';
import '../settings/unit_format.dart';
import 'prediction_card.dart' show clockTimeText;

/// Vorschlag eines Laufs als Referenz (PAR-185, FR-0131) mit „Als Referenz
/// übernehmen“ und „Ablehnen“. Übernommen wird nur über [onAccept], also nur
/// auf Bestätigung des Nutzers. Prognosekarte und Zielformular zeigen ihn
/// gleich; die Schlüssel beginnen mit [keyPrefix].
class ReferenceSuggestionBox extends StatelessWidget {
  const ReferenceSuggestionBox({
    super.key,
    required this.suggestion,
    required this.formatter,
    required this.onAccept,
    required this.onReject,
    this.keyPrefix = 'prediction_suggestion',
  });

  final ReferenceSuggestion suggestion;
  final UnitFormatter formatter;

  /// `null` sperrt den Knopf (eine Änderung läuft).
  final VoidCallback? onAccept;
  final VoidCallback? onReject;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = RamuriColors.of(context);
    final theme = Theme.of(context).textTheme;
    final lang = Localizations.localeOf(context).languageCode;
    final s = suggestion;
    return DecoratedBox(
      key: Key(keyPrefix),
      decoration: BoxDecoration(
        color: c.tint,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text(
                l10n.predictionSuggestionTitle,
                style: theme.labelLarge!.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              l10n.predictionSuggestionBody(
                DateFormat.yMMMd(lang).format(s.run.date),
                formatter.distance(s.run.distanceMeters),
                clockTimeText(s.run.movingSeconds),
              ),
              key: Key('${keyPrefix}_text'),
              style: theme.bodyMedium,
            ),
            for (final b in s.branches)
              Text(switch (b) {
                SuggestionBranch.hardAndSteady => l10n.predictionSuggestionHard,
                SuggestionBranch.beatsReference =>
                  l10n.predictionSuggestionBeats,
              }, style: theme.bodySmall!.copyWith(color: c.textMuted)),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              children: [
                SuggestionAction(
                  key: Key('${keyPrefix}_accept'),
                  label: l10n.predictionSuggestionAccept,
                  onPressed: onAccept,
                ),
                SuggestionAction(
                  key: Key('${keyPrefix}_reject'),
                  label: l10n.predictionSuggestionReject,
                  onPressed: onReject,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Textknopf der Prognosekarte (Vorschlag, Eintragen, Löschen).
class SuggestionAction extends StatelessWidget {
  const SuggestionAction({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    // Vordergrund aus dem Textknopf-Theme (`accent`): `action` ist für dunkle
    // Flächen und gefüllte Knöpfe, auf der hellen Karte unlesbar.
    return TextButton(
      style: TextButton.styleFrom(
        minimumSize: const Size(0, RamuriTheme.minTarget),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        textStyle: RamuriType.of(context).link,
      ),
      onPressed: onPressed,
      child: Text(label),
    );
  }
}
