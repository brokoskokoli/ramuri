import 'package:core/core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../ui/ui.dart';
import '../reminders/reminder_controller.dart';

/// Tipps auf die Versionsnummer bis zum Entwicklermodus (FR-0217).
const int developerModeTaps = 10;

/// Ab dem wievielten Tipp die Rückmeldung mit dem Zähler erscheint.
const int developerModeCounterFrom = 7;

/// Seite „Über“ (FR-0217): Name, Version, Lizenzen. 10 Tipps auf die Version
/// schalten den Entwicklermodus ein (Zähler ab dem 7.); im Abschnitt Entwickler
/// schaltet ein Schalter ihn aus. Die Zählung gilt nur für diese Seite.
class AboutScreen extends StatefulWidget {
  const AboutScreen({
    super.key,
    required this.developerMode,
    required this.appVersion,
  });

  final DeveloperModeStore developerMode;

  /// Liefert die Versionsangabe; `null` = unbekannt.
  final Future<String?> Function() appVersion;

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  bool _on = false;
  int _taps = 0;
  String? _version;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // Modus und Version getrennt: Die Version kommt vom System und kann dauern.
    final on = await widget.developerMode.read();
    if (!mounted) return;
    setState(() => _on = on);
    final v = await widget.appVersion();
    if (!mounted) return;
    setState(() => _version = v);
  }

  Future<void> _tap() async {
    if (_on) return;
    final n = _taps + 1;
    if (n < developerModeTaps) {
      setState(() => _taps = n);
      return;
    }
    await widget.developerMode.set(true);
    if (!mounted) return;
    setState(() {
      _on = true;
      _taps = n;
    });
  }

  Future<void> _off(bool value) async {
    if (value) return;
    final reminders = ReminderScope.read(context);
    await widget.developerMode.set(false);
    // Ohne Erreichbarkeit der Morgenmessung gilt keine Morgen-Erinnerung mehr
    // (WP33 Teil D): eine geplante wird sofort gestrichen.
    try {
      await reminders?.syncMorning();
    } on Object {
      // Die nächste Synchronisierung holt es nach.
    }
    if (!mounted) return;
    setState(() {
      _on = false;
      _taps = 0;
    });
  }

  String? _toast(AppLocalizations l10n) {
    if (_on && _taps >= developerModeTaps) return l10n.devModeOn;
    if (!_on && _taps >= developerModeCounterFrom) {
      return l10n.devTapsLeft(developerModeTaps - _taps);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = RamuriColors.of(context);
    final theme = Theme.of(context).textTheme;
    final version = _version ?? l10n.devVersionUnknown;
    final toast = _toast(l10n);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.overviewAbout)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          RamuriCard(
            child: Column(
              children: [
                RamuriLogo(semanticLabel: l10n.appTitle),
                const SizedBox(height: 8),
                Semantics(
                  button: true,
                  label: l10n.devVersion(version),
                  excludeSemantics: true,
                  child: TextButton(
                    key: const Key('about_version'),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(48, 48),
                      foregroundColor: c.textMuted,
                    ),
                    onPressed: _tap,
                    child: Text(l10n.devVersion(version)),
                  ),
                ),
                if (_on)
                  Container(
                    key: const Key('about_dev_badge'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: c.actionSoft,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      l10n.devModeOn,
                      style: theme.labelMedium!.copyWith(color: c.text),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          RamuriCard(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: ListTile(
              key: const Key('about_licenses'),
              title: Text(l10n.overviewLicenses),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => showLicensePage(
                context: context,
                applicationName: l10n.appTitle,
                applicationVersion: _version,
              ),
            ),
          ),
          if (_on) ...[
            const SizedBox(height: 20),
            SectionHeading(l10n.devSection),
            const SizedBox(height: 8),
            RamuriCard(
              key: const Key('about_dev_section'),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: SwitchListTile(
                key: const Key('about_dev_switch'),
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.devSwitchTitle),
                subtitle: Text(
                  l10n.devSwitchBody,
                  style: theme.bodySmall!.copyWith(color: c.textMuted),
                ),
                value: _on,
                onChanged: _off,
              ),
            ),
          ],
          if (toast != null) ...[
            const SizedBox(height: 16),
            Center(
              child: Semantics(
                liveRegion: true,
                child: Container(
                  key: const Key('about_toast'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: c.panel,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Text(
                    toast,
                    style: theme.bodyMedium!.copyWith(color: c.onPanel),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
