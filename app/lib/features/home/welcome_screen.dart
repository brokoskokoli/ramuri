import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../ui/ui.dart';

/// Merker, ob der Willkommensbildschirm in diesem Prozess schon bestätigt
/// wurde (FR-0207). Er liegt über der Sitzung (in `RunningApp`), weil
/// `ReadyRoot` je Sitzung neu entsteht, etwa nach einem Import aus der
/// Ersteinrichtung. Er wird nicht gespeichert: Nach einem Neustart mitten in
/// der Einrichtung darf der Bildschirm wiederkommen.
class WelcomeFlag {
  bool confirmed = false;
}

/// Willkommen vor der Ersteinrichtung (FR-0207): feste Dunkel-Fläche mit
/// Logo, Satz, „Los geht's“ und Hinweis. Kein Text über „Daten“, die
/// Aussage gilt nur für die Läufe (OQ-0075).
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key, required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return RamuriDarkScope(
      child: Builder(
        builder: (context) {
          final theme = Theme.of(context).textTheme;
          return SafeArea(
            key: const Key('welcome_screen'),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 40, 24, 36),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Spacer(),
                  Center(
                    child: RamuriLogo(
                      semanticLabel: l10n.appTitle,
                      style: RamuriLogoStyle.stackedOnDark,
                    ),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    l10n.welcomeTagline,
                    key: const Key('welcome_tagline'),
                    textAlign: TextAlign.center,
                    style: theme.titleLarge!.copyWith(height: 1.35),
                  ),
                  const Spacer(),
                  RamuriPrimaryButton(
                    key: const Key('welcome_start'),
                    label: l10n.welcomeStart,
                    onPressed: onStart,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    l10n.welcomeNote,
                    key: const Key('welcome_note'),
                    textAlign: TextAlign.center,
                    style: theme.bodySmall,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
