import 'package:core/core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// Stand der Android-Berechtigungen und Weg in die Systemeinstellungen
/// (SEC-0007). Die App fordert hier nichts an.
class PermissionsScreen extends StatefulWidget {
  const PermissionsScreen({super.key, required this.permissions});

  final PermissionStatusPort permissions;

  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends State<PermissionsScreen>
    with WidgetsBindingObserver {
  Map<AppPermission, PermissionState>? _status;
  Set<AppPermission> _requested = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Nach der Rückkehr aus den Systemeinstellungen neu lesen.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    Map<AppPermission, PermissionState> status;
    try {
      status = await widget.permissions.status();
    } catch (_) {
      status = {
        for (final p in AppPermission.values) p: PermissionState.unknown,
      };
    }
    // Nur angeforderte Berechtigungen anzeigen. Ist das Manifest nicht lesbar,
    // lieber alle (mit ihrem Stand) zeigen als eine fälschlich leere Seite.
    Set<AppPermission> requested;
    try {
      requested = await widget.permissions.requested();
    } catch (_) {
      requested = {...AppPermission.values};
    }
    if (mounted) {
      setState(() {
        _status = status;
        _requested = requested;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final status = _status;
    final names = {
      AppPermission.location: l10n.permissionLocation,
      AppPermission.bluetooth: l10n.permissionBluetooth,
      AppPermission.activityRecognition: l10n.permissionActivity,
    };
    String label(PermissionState s) => switch (s) {
      PermissionState.granted => l10n.permissionGranted,
      PermissionState.denied => l10n.permissionDenied,
      PermissionState.unknown => l10n.permissionUnknown,
    };
    return Scaffold(
      appBar: AppBar(title: Text(l10n.permissionsTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(l10n.permissionsBody),
          const SizedBox(height: 16),
          if (status == null)
            const Center(child: CircularProgressIndicator())
          else if (_requested.isEmpty)
            Text(l10n.permissionsNone, key: const Key('permissions_none'))
          else
            for (final p in AppPermission.values.where(_requested.contains))
              ListTile(
                key: Key('permission_${p.name}'),
                title: Text(names[p]!),
                trailing: Text(label(status[p] ?? PermissionState.unknown)),
              ),
          const SizedBox(height: 16),
          OutlinedButton(
            key: const Key('permissions_open_settings'),
            onPressed: () => widget.permissions.openSystemSettings(),
            child: Text(l10n.permissionsOpenSettings),
          ),
        ],
      ),
    );
  }
}
