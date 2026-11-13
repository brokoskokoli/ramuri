import 'package:core/core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../ui/ui.dart';

/// Die drei Einzelschalter der Ansagen (FR-0031, WP24 Festlegung 10): je
/// Kilometer, Pulsbereich, Abschnittswechsel. Der Hauptschalter steht auf der
/// Seite „Lauf vorbereiten“. Vorgabe: alle an; ein Speicherfehler lässt den
/// Schalter auf dem alten Stand.
class GuidanceSection extends StatefulWidget {
  const GuidanceSection({
    super.key,
    required this.session,
    required this.clock,
  });

  final StorageSession session;
  final Clock clock;

  @override
  State<GuidanceSection> createState() => _GuidanceSectionState();
}

class _GuidanceSectionState extends State<GuidanceSection> {
  GuidanceSwitches _s = const GuidanceSwitches();

  GuidanceSettings get _store => GuidanceSettings(widget.session.settings);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = await _store.load();
      if (mounted) setState(() => _s = s);
    } on Object {
      // Ohne Lesen bleiben die Vorgaben (alle an).
    }
  }

  /// Schreibt nur den Schlüssel des geänderten Schalters (der Hauptschalter
  /// von „Lauf vorbereiten“ bleibt unberührt).
  Future<void> _set(String key, GuidanceSwitches next, bool value) async {
    final before = _s;
    setState(() => _s = next);
    try {
      await widget.session.settings.set(
        key,
        value ? '1' : '0',
        at: widget.clock.now().toUtc(),
      );
    } on Object {
      if (mounted) setState(() => _s = before);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    Widget row(String key, String title, bool value, ValueChanged<bool> on) =>
        SwitchListTile(
          key: Key(key),
          title: Text(title),
          value: value,
          onChanged: on,
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeading(l10n.guidedSettingsTitle),
        const SizedBox(height: 12),
        RamuriCard(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              row(
                'guided_set_kilometer',
                l10n.guidedSettingsKilometer,
                _s.kilometer,
                (v) =>
                    _set(SettingKeys.guidanceKilometer, _copy(kilometer: v), v),
              ),
              row(
                'guided_set_heart_rate',
                l10n.guidedSettingsHeartRate,
                _s.heartRate,
                (v) =>
                    _set(SettingKeys.guidanceHeartRate, _copy(heartRate: v), v),
              ),
              row(
                'guided_set_segments',
                l10n.guidedSettingsSegments,
                _s.segments,
                (v) =>
                    _set(SettingKeys.guidanceSegments, _copy(segments: v), v),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Text(
                  l10n.guidedSettingsNote,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  GuidanceSwitches _copy({bool? kilometer, bool? heartRate, bool? segments}) =>
      GuidanceSwitches(
        enabled: _s.enabled,
        kilometer: kilometer ?? _s.kilometer,
        heartRate: heartRate ?? _s.heartRate,
        segments: segments ?? _s.segments,
      );
}
