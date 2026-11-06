import '../ports/permission_status.dart';

/// Fake: Stand frei setzbar, zählt die Aufrufe der Systemeinstellungen.
class FakePermissionStatus implements PermissionStatusPort {
  FakePermissionStatus([Map<AppPermission, PermissionState>? initial])
    : states = {
        for (final p in AppPermission.values) p: PermissionState.denied,
        ...?initial,
      };

  Map<AppPermission, PermissionState> states;
  int openSettingsCount = 0;
  bool failStatus = false;

  @override
  Future<Map<AppPermission, PermissionState>> status() async {
    if (failStatus) throw StateError('Stand nicht lesbar');
    return Map.of(states);
  }

  @override
  Future<void> openSystemSettings() async => openSettingsCount++;
}
