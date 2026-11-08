import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../ui/ui.dart';

/// Die Frage beim ersten Öffnen einer Karte (ADR-0009 Punkt 3). Kurz; die Einzelheiten klappen auf. `true`: "Karte
/// laden"; `false` oder `null`: "Nicht jetzt" (oder zurück).
Future<bool?> showMapConsentDialog(BuildContext context) => showDialog<bool>(
  context: context,
  builder: (_) => const MapConsentDialog(),
);

class MapConsentDialog extends StatelessWidget {
  const MapConsentDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    return AlertDialog(
      key: const Key('map_consent_dialog'),
      title: Text(l10n.mapConsentTitle),
      scrollable: true,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l10n.mapConsentBody, style: text.bodyMedium),
          const SizedBox(height: 12),
          Text(l10n.mapConsentBody2, style: text.bodyMedium),
          ExpansionTile(
            key: const Key('map_consent_more'),
            // Ohne Trennlinien: Die Zeile steht im Dialog.
            shape: const RoundedRectangleBorder(),
            collapsedShape: const RoundedRectangleBorder(),
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: 8),
            title: Text(l10n.mapConsentMore),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: [Text(l10n.mapConsentMoreBody, style: text.bodyMedium)],
          ),
        ],
      ),
      actions: [
        RamuriSecondaryButton(
          key: const Key('map_consent_not_now'),
          label: l10n.mapConsentNotNow,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        RamuriPrimaryButton(
          key: const Key('map_consent_load'),
          label: l10n.mapConsentLoad,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    );
  }
}
