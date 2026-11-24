import 'package:core/core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../ui/ui.dart';
import 'developer_settings_screen.dart';

/// Tipps auf die Versionsnummer bis zum Entwicklermodus (FR-0217).
const int developerModeTaps = 10;

/// Ab dem wievielten Tipp die Rückmeldung mit dem Zähler erscheint.
const int developerModeCounterFrom = 7;

/// Seite „Über“ (FR-0217): Name, Version, Lizenzen. 10 Tipps auf die Version
/// schalten den Entwicklermodus ein (Zähler ab dem 7.); dann führt ein Verweis
/// zu den Entwicklereinstellungen ([DeveloperSettingsScreen]), wo ein Schalter
/// ihn wieder ausschaltet. Die Zählung gilt nur für diese Seite.
class AboutScreen extends StatefulWidget {
  const AboutScreen({
    super.key,
    required this.developerMode,
    required this.appVersion,
    this.morning,
    this.clock,
    this.ppgCamera,
    this.cameraChoice,
    this.cameraDiagnostics,
  });

  final DeveloperModeStore developerMode;

  /// Weitergereicht an die Entwicklereinstellungen (Messpaare, Kamerawahl).
  final MorningStore? morning;

  final PpgCamera? ppgCamera;
  final PpgCameraChoiceStore? cameraChoice;
  final PpgCameraDiagnosticsStore? cameraDiagnostics;

  final DateTime Function()? clock;

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

  /// Öffnet die Entwicklereinstellungen; danach gilt der Modus, der dort
  /// gespeichert ist (dort ausgeschaltet → Hinweis weg, Zählung neu).
  Future<void> _openDeveloperSettings() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => DeveloperSettingsScreen(
          developerMode: widget.developerMode,
          morning: widget.morning,
          clock: widget.clock,
          ppgCamera: widget.ppgCamera,
          cameraChoice: widget.cameraChoice,
          cameraDiagnostics: widget.cameraDiagnostics,
        ),
      ),
    );
    final on = await widget.developerMode.read();
    if (!mounted || on == _on) return;
    setState(() {
      _on = on;
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
            const SizedBox(height: 12),
            RamuriCard(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: ListTile(
                key: const Key('about_dev_link'),
                leading: const Icon(Icons.developer_mode_outlined),
                title: Text(l10n.devSettingsOpen),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: _openDeveloperSettings,
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
