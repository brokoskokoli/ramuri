import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app_dependencies.dart';
import 'features/home/home_screen.dart';
import 'l10n/app_localizations.dart';

/// Wurzel-Widget. Die Gerätesprache bestimmt die Sprache; für nicht
/// unterstützte Sprachen gilt die Standardauflösung von Flutter (erste
/// unterstützte Sprache, hier Deutsch).
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
      home: const HomeScreen(),
    );
  }
}
