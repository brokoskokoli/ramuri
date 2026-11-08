import 'package:core/core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../recalculation/recalculation_card.dart';
import '../recalculation/recalculation_controller.dart';
import '../../ui/ramuri_card.dart';
import '../../ui/section_heading.dart';
import 'app_settings.dart';

/// Einstellungen: Einheit für Strecken (reine Anzeige) und die Neuberechnung.
/// Sensoren, Zonen, Berechtigungen und Daten liegen in der Übersicht.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.session,
    required this.recalculation,
  });

  final StorageSession session;
  final RecalculationController recalculation;

  @override
  Widget build(BuildContext context) {
    // Während der Neuberechnung bleibt die Seite stehen (Sperre).
    return ListenableBuilder(
      listenable: recalculation,
      builder: (context, _) {
        final busy = recalculation.busy;
        return PopScope(canPop: !busy, child: _body(context, busy));
      },
    );
  }

  Widget _body(BuildContext context, bool busy) {
    final l10n = AppLocalizations.of(context);
    final settings = AppSettingsScope.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          RecalculationCard(controller: recalculation),
          SectionHeading(l10n.settingsUnits),
          const SizedBox(height: 12),
          RamuriCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SegmentedButton<DistanceUnit>(
                  key: const Key('settings_unit'),
                  segments: [
                    ButtonSegment(
                      value: DistanceUnit.kilometers,
                      label: Text(l10n.settingsUnitKm),
                    ),
                    ButtonSegment(
                      value: DistanceUnit.miles,
                      label: Text(l10n.settingsUnitMi),
                    ),
                  ],
                  selected: {settings.distanceUnit},
                  onSelectionChanged: busy
                      ? null
                      : (s) => _change(context, settings, s.first),
                ),
                const SizedBox(height: 12),
                Text(l10n.settingsUnitNote),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _change(
    BuildContext context,
    AppSettings settings,
    DistanceUnit unit,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final failed = AppLocalizations.of(context).settingsSaveFailed;
    try {
      await settings.setDistanceUnit(unit);
    } on StorageException {
      messenger.showSnackBar(SnackBar(content: Text(failed)));
    }
  }
}
