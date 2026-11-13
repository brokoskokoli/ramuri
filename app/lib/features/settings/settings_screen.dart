import 'package:core/core.dart';
import 'package:flutter/material.dart';

import '../reminders/reminder_controller.dart';
import '../reminders/reminder_section.dart';
import '../../l10n/app_localizations.dart';
import '../map/map_consent_scope.dart';
import '../map/map_settings_card.dart';
import '../recalculation/recalculation_card.dart';
import '../recalculation/recalculation_controller.dart';
import '../../ui/ramuri_card.dart';
import '../../ui/section_heading.dart';
import 'app_settings.dart';
import 'guidance_section.dart';
import 'load_settings_section.dart';

/// Einstellungen: Einheit für Strecken (reine Anzeige) und die Neuberechnung.
/// Sensoren, Zonen, Berechtigungen und Daten liegen in der Übersicht.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.session,
    required this.recalculation,
    required this.clock,
  });

  final StorageSession session;
  final Clock clock;
  final RecalculationController recalculation;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  /// Die Karte der Neuberechnung steht oben in der Liste; eine lazy gebaute
  /// Liste kennt ihren Kontext außerhalb des Bildes nicht, daher wird der
  /// Anfang über die Position angesteuert (WP19 NB4).
  final ScrollController _scroll = ScrollController();

  StorageSession get session => widget.session;
  RecalculationController get recalculation => widget.recalculation;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _showOffer() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(
      0,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

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
    final map = MapConsentScope.of(context);
    final reminders = ReminderScope.maybeOf(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: ListView(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          RecalculationCard(controller: recalculation),
          LoadSettingsSection(
            session: session,
            recalculation: recalculation,
            onShowOffer: _showOffer,
          ),
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
          const SizedBox(height: 24),
          GuidanceSection(session: session, clock: widget.clock),
          if (reminders != null) ReminderSection(controller: reminders),
          if (map != null) ...[
            SectionHeading(l10n.mapSettingsTitle),
            const SizedBox(height: 12),
            MapSettingsCard(controller: map),
          ],
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
