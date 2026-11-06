import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app_dependencies.dart';
import 'features/home/ready_root.dart';
import 'features/storage/storage_gate.dart';
import 'l10n/app_localizations.dart';

/// Wurzel-Widget. Die Gerätesprache bestimmt die Sprache: Deutsch und Englisch
/// werden unterstützt, jede andere Gerätesprache zeigt Englisch (NFR-0006,
/// OQ-0067).
class RunningApp extends StatelessWidget {
  const RunningApp({super.key, required this.dependencies});

  final AppDependencies dependencies;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      theme: ThemeData(colorSchemeSeed: Colors.teal),
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
        readyBuilder: (context, session) =>
            ReadyRoot(session: session, clock: dependencies.clock),
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
