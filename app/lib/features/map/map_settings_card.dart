import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import '../../ui/ui.dart';
import 'map_consent_controller.dart';

/// Eintrag "Karte" in den Einstellungen: Stand, Erteilen und Widerrufen, Größe des Kartenspeichers, Quellenangabe.
/// Nach dem Widerruf fragt er, ob der Kartenspeicher gelöscht wird (SEC-0007).
class MapSettingsCard extends StatefulWidget {
  const MapSettingsCard({super.key, required this.controller});

  final MapConsentController controller;

  @override
  State<MapSettingsCard> createState() => _MapSettingsCardState();
}

class _MapSettingsCardState extends State<MapSettingsCard> {
  Future<int?>? _size;

  @override
  void initState() {
    super.initState();
    _size = widget.controller.ready.then(
      (_) => widget.controller.cacheSizeBytes(),
    );
  }

  void _refreshSize() {
    final size = widget.controller.cacheSizeBytes();
    setState(() {
      _size = size;
    });
  }

  String _format(BuildContext context, int bytes) {
    final locale = Localizations.localeOf(context).toString();
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${NumberFormat('0.#', locale).format(bytes / 1024)} kB';
    }
    return '${NumberFormat('0.#', locale).format(bytes / (1024 * 1024))} MB';
  }

  Future<void> _grant() async {
    final messenger = ScaffoldMessenger.of(context);
    final failed = AppLocalizations.of(context).mapGrantFailed;
    if (!await widget.controller.grant()) {
      messenger.showSnackBar(SnackBar(content: Text(failed)));
    }
  }

  Future<void> _revoke() async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    final result = await widget.controller.revoke();
    if (result.saveFailed) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.mapRevokeSaveFailed)));
    }
    if (!result.askDeleteCache || !mounted) return;
    final delete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('map_delete_dialog'),
        title: Text(l10n.mapDeleteTitle),
        content: Text(l10n.mapDeleteBody),
        actions: [
          TextButton(
            key: const Key('map_delete_keep'),
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.mapDeleteKeep),
          ),
          FilledButton(
            key: const Key('map_delete_confirm'),
            style: ramuriDangerFilledStyle(context),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.mapDeleteConfirm),
          ),
        ],
      ),
    );
    if (delete == true) await _delete(messenger, l10n.mapDeleteFailed);
  }

  Future<void> _delete(ScaffoldMessengerState messenger, String failed) async {
    if (!await widget.controller.deleteCache()) {
      messenger.showSnackBar(SnackBar(content: Text(failed)));
    }
    if (mounted) _refreshSize();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = widget.controller;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final granted = c.status == MapConsentStatus.granted;
        return RamuriCard(
          key: const Key('map_settings'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(switch (c.status) {
                MapConsentStatus.granted => l10n.mapStatusGranted,
                MapConsentStatus.declined => l10n.mapStatusDeclined,
                MapConsentStatus.neverAsked => l10n.mapStatusNeverAsked,
              }, key: const Key('map_status')),
              const SizedBox(height: 12),
              granted
                  ? RamuriSecondaryButton(
                      key: const Key('map_revoke'),
                      label: l10n.mapRevokeAction,
                      onPressed: _revoke,
                    )
                  : RamuriPrimaryButton(
                      key: const Key('map_grant'),
                      label: l10n.mapGrantAction,
                      onPressed: _grant,
                    ),
              const SizedBox(height: 12),
              FutureBuilder<int?>(
                future: _size,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const SizedBox.shrink();
                  }
                  final bytes = snap.data;
                  return Text(
                    bytes == null
                        ? l10n.mapCacheSizeUnknown
                        : l10n.mapCacheSize(_format(context, bytes)),
                    key: const Key('map_cache_size'),
                  );
                },
              ),
              if (c.services.attribution.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  l10n.mapSourceLine(c.services.attribution),
                  key: const Key('map_source'),
                ),
              ],
              const SizedBox(height: 8),
              TextButton(
                key: const Key('map_cache_delete'),
                onPressed: () => _delete(
                  ScaffoldMessenger.of(context),
                  l10n.mapDeleteFailed,
                ),
                child: Text(l10n.mapCacheDeleteAction),
              ),
            ],
          ),
        );
      },
    );
  }
}
