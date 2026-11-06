import 'package:core/core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../settings/app_settings.dart';
import '../setup/setup_screen.dart';
import 'home_screen.dart';

/// Wurzel nach dem Öffnen des Speichers: lädt die Einstellungen, bietet beim
/// ersten Start die Einrichtung an (FR-0001) und zeigt danach die Startseite.
class ReadyRoot extends StatefulWidget {
  const ReadyRoot({super.key, required this.session, required this.clock});

  final StorageSession session;
  final Clock clock;

  @override
  State<ReadyRoot> createState() => _ReadyRootState();
}

class _ReadyRootState extends State<ReadyRoot> {
  late final Future<AppSettings> _settings = AppSettings.load(
    widget.session.settings,
    widget.clock,
  );

  Future<void> _finishSetup(AppSettings settings) async {
    final messenger = ScaffoldMessenger.of(context);
    final failed = AppLocalizations.of(context).settingsSaveFailed;
    try {
      await settings.markSetupDone();
    } on StorageException {
      messenger.showSnackBar(SnackBar(content: Text(failed)));
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<AppSettings>(
    future: _settings,
    builder: (context, snapshot) {
      final l10n = AppLocalizations.of(context);
      if (snapshot.hasError) {
        return Scaffold(body: Center(child: Text(l10n.notOpenableOpenFailed)));
      }
      final settings = snapshot.data;
      if (settings == null) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      return AppSettingsScope(
        settings: settings,
        child: ListenableBuilder(
          listenable: settings,
          builder: (context, _) => settings.setupDone
              ? HomeScreen(session: widget.session, clock: widget.clock)
              : SetupScreen(
                  session: widget.session,
                  clock: widget.clock,
                  onFinished: () => _finishSetup(settings),
                ),
        ),
      );
    },
  );
}
