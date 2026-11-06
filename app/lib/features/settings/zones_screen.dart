import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import 'app_settings.dart';

/// Zoneneditor (FR-0061): sechs gemeinsame Grenzen in ganzen Prozent der
/// Herzfrequenzreserve; Zone n reicht von Grenze n bis Grenze n+1, damit gibt
/// es keine Lücken (OQ-0065). Die Einteilung ist eine Näherung (FR-0064).
class ZonesScreen extends StatefulWidget {
  const ZonesScreen({super.key});

  @override
  State<ZonesScreen> createState() => _ZonesScreenState();
}

class _ZonesScreenState extends State<ZonesScreen> {
  final _controllers = [
    for (final v in ReserveZoneSettings.defaultPercents)
      TextEditingController(text: '$v'),
  ];
  String? _error;
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    AppSettingsScope.of(context).loadZoneBounds().then(_show);
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _show(List<int> percents) {
    if (!mounted) return;
    setState(() {
      for (var i = 0; i < _controllers.length; i++) {
        _controllers[i].text = '${percents[i]}';
      }
      _error = null;
    });
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final settings = AppSettingsScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final values = [for (final c in _controllers) int.tryParse(c.text.trim())];
    final bad = values.indexOf(null);
    if (bad >= 0) {
      setState(() => _error = l10n.zonesNotNumber(bad + 1));
      return;
    }
    try {
      await settings.saveZoneBounds(values.cast<int>());
      if (!mounted) return;
      setState(() => _error = null);
      messenger.showSnackBar(SnackBar(content: Text(l10n.zonesSaved)));
    } on ZoneBoundsException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = switch (e.problem) {
          ZoneBoundsProblem.outOfRange => l10n.zonesOutOfRange(e.index + 1),
          _ => l10n.zonesNotAscending(e.index + 1),
        };
      });
    } on StorageException {
      messenger.showSnackBar(SnackBar(content: Text(l10n.settingsSaveFailed)));
    }
  }

  Future<void> _reset() async {
    final l10n = AppLocalizations.of(context);
    final settings = AppSettingsScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await settings.resetZoneBounds();
      _show(ReserveZoneSettings.defaultPercents);
      messenger.showSnackBar(SnackBar(content: Text(l10n.zonesResetDone)));
    } on StorageException {
      messenger.showSnackBar(SnackBar(content: Text(l10n.settingsSaveFailed)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.zonesTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(l10n.zonesNote, key: const Key('zones_note')),
          const SizedBox(height: 16),
          for (var i = 0; i < _controllers.length; i++) ...[
            TextField(
              key: Key('zone_bound_$i'),
              controller: _controllers[i],
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: i < 5
                    ? l10n.zonesLowerField(i + 1)
                    : l10n.zonesUpperField,
                suffixText: '%',
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (_error != null)
            Text(
              _error!,
              key: const Key('zones_error'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          const SizedBox(height: 8),
          FilledButton(
            key: const Key('zones_save'),
            onPressed: _save,
            child: Text(l10n.zonesSave),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            key: const Key('zones_reset'),
            onPressed: _reset,
            child: Text(l10n.zonesReset),
          ),
        ],
      ),
    );
  }
}
