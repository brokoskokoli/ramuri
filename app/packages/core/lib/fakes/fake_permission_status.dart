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

  /// Im Manifest angeforderte Berechtigungen (Standard: alle).
  Set<AppPermission> requestedSet = {...AppPermission.values};
  bool failRequested = false;

  @override
  Future<Set<AppPermission>> requested() async {
    if (failRequested) throw StateError('Manifest nicht lesbar');
    return Set.of(requestedSet);
  }

  @override
  Future<Map<AppPermission, PermissionState>> status() async {
    if (failStatus) throw StateError('Stand nicht lesbar');
    return Map.of(states);
  }

  @override
  Future<void> openSystemSettings() async => openSettingsCount++;
}
