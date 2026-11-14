import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import 'readiness_service.dart';

/// Platzhalter der Detailseite „Erholung“ (WP34 Teil D1); Teil D2 füllt sie
/// nach `design/screens/readiness/Detail.dc.html`. Die Texte stehen schon in
/// den ARB-Dateien (Präfix `readiness`).
class ReadinessDetailScreen extends StatelessWidget {
  const ReadinessDetailScreen({super.key, required this.snapshot});

  final ReadinessSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      key: const Key('readiness_detail'),
      appBar: AppBar(title: Text(l.recoveryTitle)),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Text(l.readinessDetailSoon),
      ),
    );
  }
}
