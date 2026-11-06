import 'package:core/core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../recalculation/recalculation_controller.dart';
import '../settings/app_settings.dart';
import '../setup/setup_screen.dart';
import 'home_screen.dart';

/// Wurzel nach dem Öffnen des Speichers: lädt die Einstellungen, bietet beim
/// ersten Start die Einrichtung an (FR-0001) und zeigt danach die Startseite.
class ReadyRoot extends StatefulWidget {
  const ReadyRoot({
    super.key,
    required this.session,
    required this.clock,
    required this.permissions,
  });

  final StorageSession session;
  final PermissionStatusPort permissions;
  final Clock clock;

  @override
  State<ReadyRoot> createState() => _ReadyRootState();
}

class _ReadyRootState extends State<ReadyRoot> {
  late Future<AppSettings> _settings;
  late final RecalculationService _recalculationService;
  late final RecalculationController _recalculation;

  @override
  void initState() {
    super.initState();
    // Dienste für die Neuberechnung (FR-0006): eine Instanz je Sitzung; beim
    // Start wird ein offenes Angebot gelesen.
    _recalculationService = RecalculationService(
      session: widget.session,
      clock: widget.clock,
      calculation: ValueCalculationService(
        session: widget.session,
        clock: widget.clock,
      ),
    );
    _recalculation = RecalculationController(_recalculationService);
    _recalculation.start();
    _loadSettings();
  }

  @override
  void dispose() {
    _recalculation.dispose();
    _recalculationService.dispose();
    super.dispose();
  }

  void _loadSettings() {
    // Der Halter im Scope über dem Navigator bekommt die Einstellungen, bevor
    // diese Seite sie zeigt; so sehen auch per Navigator.push geöffnete Seiten
    // sie.
    final holder = AppSettingsScope.holderOf(context);
    _settings = AppSettings.load(widget.session.settings, widget.clock).then((
      s,
    ) {
      holder.attach(s);
      return s;
    });
  }

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
        return Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(l10n.settingsLoadFailed),
                TextButton(
                  key: const Key('settings_load_retry'),
                  onPressed: () => setState(_loadSettings),
                  child: Text(l10n.notOpenableRetry),
                ),
              ],
            ),
          ),
        );
      }
      final settings = snapshot.data;
      if (settings == null) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      return ListenableBuilder(
        listenable: settings,
        builder: (context, _) => settings.setupDone
            ? HomeScreen(
                session: widget.session,
                clock: widget.clock,
                permissions: widget.permissions,
                recalculation: _recalculation,
              )
            : SetupScreen(
                session: widget.session,
                clock: widget.clock,
                onFinished: () => _finishSetup(settings),
              ),
      );
    },
  );
}
