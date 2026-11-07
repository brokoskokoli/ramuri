import 'package:core/core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../archive/archive_import_action.dart';
import '../archive/archive_wiring.dart';
import '../profile/profile_form.dart';

/// Ersteinrichtung beim ersten Start (FR-0001, OQ-0010): Profilformular, das
/// sich überspringen lässt. Keine Pflichtangabe. [onFinished] markiert die
/// Einrichtung als erledigt (auch beim Überspringen).
class SetupScreen extends StatefulWidget {
  const SetupScreen({
    super.key,
    required this.session,
    required this.clock,
    required this.onFinished,
    required this.serialize,
  });

  /// In der App `RecalculationController.exclusive` (Archiv-Import).
  final SerializeAction serialize;

  final StorageSession session;
  final Clock clock;
  final Future<void> Function() onFinished;

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  bool _savedWithHints = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.setupTitle),
        actions: [
          TextButton(
            key: const Key('setup_skip'),
            onPressed: widget.onFinished,
            child: Text(l10n.setupSkip),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(l10n.setupIntro),
          const SizedBox(height: 16),
          // Neues Gerät: Daten aus einem Archiv holen (FR-0198, Vertrag 4.6).
          // Hier ist die App noch leer; der Import übernimmt auch die
          // Einstellungen und das Profil und beendet die Einrichtung.
          ArchiveImportAction(
            session: widget.session,
            serialize: widget.serialize,
            buttonKey: const Key('setup_restore'),
            label: l10n.setupRestoreAction,
            prepare: (fresh) async {
              if (await fresh.settings.get(SettingKeys.setupDone) != '1') {
                await fresh.settings.set(
                  SettingKeys.setupDone,
                  '1',
                  at: widget.clock.now(),
                );
              }
            },
          ),
          const SizedBox(height: 16),
          ProfileForm(
            service: ProfileService(widget.session.profile, widget.clock),
            clock: widget.clock,
            onSaved: (v) {
              // Mit Hinweisen bleibt das Formular stehen, damit der Nutzer sie
              // sieht; sonst geht es direkt weiter.
              if (v.hints.isEmpty) {
                widget.onFinished();
              } else {
                setState(() => _savedWithHints = true);
              }
            },
          ),
          if (_savedWithHints) ...[
            const SizedBox(height: 12),
            OutlinedButton(
              key: const Key('setup_continue'),
              onPressed: widget.onFinished,
              child: Text(l10n.setupContinue),
            ),
          ],
        ],
      ),
    );
  }
}
