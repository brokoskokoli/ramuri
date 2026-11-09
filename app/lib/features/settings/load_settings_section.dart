import 'package:core/core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../ui/ramuri_buttons.dart';
import '../../ui/ramuri_card.dart';
import '../../ui/ramuri_colors.dart';
import '../../ui/section_heading.dart';
import '../profile/profile_screen.dart';
import '../recalculation/recalculation_controller.dart';

/// Belastungsprofil und Zusage „alles erfasst“ in den Einstellungen (WP19,
/// FR-0197, FR-0103). Das Profil wechselt nie sofort: die Wahl startet die
/// Neuberechnung ([RecalculationController.requestLoadProfile]), das Angebot
/// erscheint in der Karte der Neuberechnung. Bis zur Bestätigung zeigt die
/// Seite das aktive und das gewählte Profil getrennt; lehnt der Nutzer ab,
/// verfällt die Wahl und die Anzeige folgt dem Controller.
class LoadSettingsSection extends StatefulWidget {
  const LoadSettingsSection({
    super.key,
    required this.session,
    required this.recalculation,
  });

  final StorageSession session;
  final RecalculationController recalculation;

  @override
  State<LoadSettingsSection> createState() => _LoadSettingsSectionState();
}

class _Snapshot {
  const _Snapshot({
    required this.active,
    required this.chosen,
    required this.banister,
    required this.allRecorded,
  });

  final LoadProfile active;

  /// Gewählt, aber unbestätigt; `null` ohne offene Wahl.
  final LoadProfile? chosen;
  final LoadProfileResolution banister;
  final bool allRecorded;
}

class _LoadSettingsSectionState extends State<LoadSettingsSection> {
  _Snapshot? _state;
  bool _failed = false;
  int _seq = 0;

  RecalculationService get _service => widget.recalculation.service;

  @override
  void initState() {
    super.initState();
    widget.recalculation.addListener(_reload);
    _reload();
  }

  @override
  void dispose() {
    widget.recalculation.removeListener(_reload);
    super.dispose();
  }

  Future<void> _reload() async {
    final seq = ++_seq;
    try {
      final store = widget.session.settings;
      final next = _Snapshot(
        active: await LoadSettings.activeProfile(store),
        chosen: await LoadSettings.pendingProfile(store),
        banister: await _service.loadProfileResolution(LoadProfile.banister),
        allRecorded: await LoadSettings.allRecorded(store),
      );
      if (!mounted || seq != _seq) return;
      setState(() {
        _state = next;
        _failed = false;
      });
    } on Object {
      // Keine Gesundheitsdaten in der Meldung: nur der Zustand.
      if (!mounted || seq != _seq) return;
      setState(() => _failed = true);
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    try {
      await action();
    } on LoadProfileNotApplicableException {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.loadSettingsNotApplicable)),
      );
    } on StorageException {
      messenger.showSnackBar(SnackBar(content: Text(l10n.settingsSaveFailed)));
    }
    await _reload();
  }

  void _openProfile() {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ProfileScreen(
          session: widget.session,
          clock: _service.clock,
          recalculation: widget.recalculation,
        ),
      ),
    );
  }

  static String _name(AppLocalizations l10n, LoadProfile p) => switch (p) {
    LoadProfile.edwards => l10n.loadProfileNameEdwards,
    LoadProfile.banister => l10n.loadProfileNameBanister,
  };

  static String _reason(
    AppLocalizations l10n,
    LoadProfileIssue i,
  ) => switch (i) {
    LoadProfileIssue.missingRestingHeartRate => l10n.loadSettingsReasonResting,
    LoadProfileIssue.heartRateReserveUnusable => l10n.loadSettingsReasonReserve,
    LoadProfileIssue.missingCoefficients => l10n.loadSettingsReasonCoefficients,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final s = _state;
    final busy = widget.recalculation.busy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeading(l10n.loadSettingsTitle),
        const SizedBox(height: 12),
        RamuriCard(
          key: const Key('load_settings'),
          child: s == null
              ? Text(_failed ? l10n.settingsLoadFailed : l10n.loadLoading)
              : _content(context, l10n, s, busy),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _content(
    BuildContext context,
    AppLocalizations l10n,
    _Snapshot s,
    bool busy,
  ) {
    final c = RamuriColors.of(context);
    final shown = s.chosen ?? s.active;
    final banisterOk = s.banister.applicable;
    final reasons = [for (final i in s.banister.issues) _reason(l10n, i)];
    final banisterActive = s.active == LoadProfile.banister;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.loadSettingsIntro),
        const SizedBox(height: 12),
        Semantics(
          container: true,
          child: Column(
            children: [
              _ProfileOption(
                key: const Key('load_profile_edwards'),
                label: l10n.loadProfileNameEdwards,
                hint: l10n.loadSettingsEdwardsHint,
                selected: shown == LoadProfile.edwards,
                enabled: !busy,
                onTap: () => _run(
                  () => widget.recalculation.requestLoadProfile(
                    LoadProfile.edwards,
                  ),
                ),
              ),
              _ProfileOption(
                key: const Key('load_profile_banister'),
                label: l10n.loadProfileNameBanister,
                hint: l10n.loadSettingsBanisterHint,
                selected: shown == LoadProfile.banister,
                enabled: banisterOk && !busy,
                onTap: () => _run(
                  () => widget.recalculation.requestLoadProfile(
                    LoadProfile.banister,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          l10n.loadSettingsActive(_name(l10n, s.active)),
          key: const Key('load_active'),
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        if (s.chosen != null && s.chosen != s.active)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              l10n.loadSettingsChosen(_name(l10n, s.chosen!)),
              key: const Key('load_chosen'),
              style: TextStyle(color: c.textMuted),
            ),
          ),
        if (!banisterOk) ...[
          const SizedBox(height: 12),
          Text(
            banisterActive
                ? l10n.loadSettingsBanisterBroken
                : l10n.loadSettingsBanisterBlocked,
            key: const Key('load_banister_blocked'),
          ),
          for (final r in reasons)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('• $r', key: const Key('load_banister_reason')),
            ),
          const SizedBox(height: 8),
          RamuriSecondaryButton(
            key: const Key('load_open_profile'),
            onPressed: busy ? null : _openProfile,
            label: l10n.loadSettingsOpenProfile,
          ),
        ],
        const SizedBox(height: 16),
        SwitchListTile(
          key: const Key('load_all_recorded'),
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.loadSettingsAllRecordedTitle),
          subtitle: Text(l10n.loadSettingsAllRecordedExplain),
          value: s.allRecorded,
          onChanged: busy
              ? null
              : (v) => _run(() => widget.recalculation.setAllRecorded(v)),
        ),
      ],
    );
  }
}

/// Eine Zeile der Profilwahl: Auswahlkreis, Name, Hinweis; mindestens 48 dp,
/// als Teil einer Gruppe mit Auswahl und Aktivierung für Screenreader.
class _ProfileOption extends StatelessWidget {
  const _ProfileOption({
    super.key,
    required this.label,
    required this.hint,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final String hint;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = RamuriColors.of(context);
    final color = enabled ? c.text : c.textSoft;
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      enabled: enabled,
      label: '$label. $hint',
      excludeSemantics: true,
      onTap: enabled ? onTap : null,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: selected && enabled ? c.accent : color,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: Theme.of(context).textTheme.bodyLarge
                            ?.copyWith(color: color),
                      ),
                      Text(hint, style: TextStyle(color: c.textMuted)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
