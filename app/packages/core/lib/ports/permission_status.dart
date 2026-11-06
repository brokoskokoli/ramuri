/// Android-Berechtigungen, deren Stand die App anzeigt (SEC-0007).
enum AppPermission { location, bluetooth, activityRecognition }

enum PermissionState {
  granted,
  denied,

  /// Der Stand ließ sich nicht ermitteln.
  unknown,
}

/// Port: Stand der Berechtigungen lesen und den Weg in die Systemeinstellungen
/// öffnen. Die App fordert hier nichts an; der Widerruf geschieht im System.
abstract interface class PermissionStatusPort {
  /// Aktueller Stand je Berechtigung. Jede [AppPermission] kommt vor.
  Future<Map<AppPermission, PermissionState>> status();

  /// Öffnet die Systemeinstellungen dieser App.
  Future<void> openSystemSettings();
}
