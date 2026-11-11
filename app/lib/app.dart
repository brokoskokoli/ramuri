import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app_dependencies.dart';
import 'features/reminders/reminder_controller.dart';
import 'features/archive/archive_scope.dart';
import 'features/export/file_handoff_scope.dart';
import 'features/home/ready_root.dart';
import 'features/map/map_consent_scope.dart';
import 'features/measure/resting_measure_launcher.dart';
import 'features/home/welcome_screen.dart';
import 'features/settings/app_settings.dart';
import 'features/storage/storage_gate.dart';
import 'l10n/app_localizations.dart';
import 'offload_scope.dart';
import 'ui/ui.dart';

/// Wurzel-Widget. Die Gerätesprache bestimmt die Sprache: Deutsch und Englisch
/// werden unterstützt, jede andere Gerätesprache zeigt Englisch (NFR-0006,
/// OQ-0067).
class RunningApp extends StatefulWidget {
  const RunningApp({super.key, required this.dependencies});

  final AppDependencies dependencies;

  @override
  State<RunningApp> createState() => _RunningAppState();
}

class _RunningAppState extends State<RunningApp> {
  final AppSettingsHolder _settings = AppSettingsHolder();

  /// Über der Sitzung: ReadyRoot entsteht je Sitzung neu (FR-0207).
  final WelcomeFlag _welcome = WelcomeFlag();

  /// Kartencontroller der aktuellen Sitzung, über dem Navigator (Einstellungen, Karten).
  final MapConsentHolder _map = MapConsentHolder();

  /// Erinnerungen (FR-0174), über den Sitzungen; ReadyRoot bindet die Sitzung an.
  late final ReminderController _reminders = ReminderController(
    scheduler: dependencies.reminders,
    clock: dependencies.clock,
    debugAdd: dependencies.reminderDebug,
  );

  @override
  void dispose() {
    _settings.dispose();
    _reminders.dispose();
    super.dispose();
  }

  AppDependencies get dependencies => widget.dependencies;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      // Scope über dem Navigator: auch normal geöffnete Seiten sehen die
      // Einstellungen.
      builder: (context, child) => OffloadScope(
        offload: dependencies.offload,
        child: FileHandoffScope(
          handoff: dependencies.fileHandoff,
          child: ArchiveScope(
            export: dependencies.archiveExport,
            restore: dependencies.archiveRestore,
            verify: dependencies.archiveVerify,
            start: dependencies.storageStart,
            // Ohne Region behält Flutter den letzten Stil; Heute hat keine
            // App-Leiste. Tiefere Regionen (Dunkel-Fläche, App-Leisten) gehen
            // vor.
            child: AnnotatedRegion<SystemUiOverlayStyle>(
              value: ramuriOverlayStyle(Theme.of(context).brightness),
              child: MapConsentScope(
                holder: _map,
                child: PpgCameraScope(
                  camera: dependencies.ppgCamera,
                  child: AppSettingsScope(
                    holder: _settings,
                    child: ReminderScope(controller: _reminders, child: child!),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      theme: RamuriTheme.light,
      darkTheme: RamuriTheme.dark,
      themeMode: ThemeMode.system,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      localeResolutionCallback: resolveAppLocale,
      home: StorageGate(
        controller: dependencies.storageStart,
        readyBuilder: (context, session) => ReadyRoot(
          // Eine neue Sitzung (nach dem Import) baut alles neu auf:
          // Einstellungen, Sensoren, Verlauf.
          key: ObjectKey(session),
          session: session,
          clock: dependencies.clock,
          permissions: dependencies.permissions,
          runPorts: dependencies.runPorts,
          sensors: dependencies.sensors,
          welcome: _welcome,
          map: dependencies.map,
          mapHolder: _map,
        ),
      ),
    );
  }
}

/// Sprache der App: de oder en nach Sprachcode der Gerätesprache, sonst
/// Englisch (OQ-0067). Sind mehrere Gerätesprachen gesetzt, entscheidet die
/// bevorzugte (erste); eine unbekannte erste Sprache führt nicht zu einer
/// späteren unterstützten.
Locale resolveAppLocale(Locale? device, Iterable<Locale> supported) {
  const fallback = Locale('en');
  if (device == null) return fallback;
  for (final s in supported) {
    if (s.languageCode == device.languageCode) return s;
  }
  return fallback;
}
