import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// Startbildschirm, derzeit nur ein lokalisierter Text.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.appTitle)),
      body: Center(child: Text(l10n.homeWelcome)),
    );
  }
}
