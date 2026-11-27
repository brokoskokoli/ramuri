import 'dart:async';

import '../ports/location_access.dart';

/// Fake: Stand frei setzbar. [onRequest] ist der Stand nach dem Dialog.
class FakeLocationAccess implements LocationAccessPort {
  FakeLocationAccess({
    this.current = LocationAccess.precise,
    this.onRequest,
    this.gps = true,
  });

  LocationAccess current;

  /// Stand nach `request()`; `null` lässt ihn unverändert (Dialog abgelehnt).
  LocationAccess? onRequest;
  bool gps;
  bool fail = false;

  /// Antwort von [access] bzw. [gpsEnabled] bleibt aus (verlorene Antwort des
  /// Plattformkanals).
  bool accessNeverAnswers = false;
  bool gpsNeverAnswers = false;
  int requestCount = 0;

  /// Aufrufe von [openLocationSettings]; [settingsOpen] ist deren Antwort.
  int openSettingsCount = 0;
  bool settingsOpen = true;

  @override
  Future<LocationAccess> access() async {
    if (accessNeverAnswers) return Completer<LocationAccess>().future;
    if (fail) throw StateError('Stand nicht lesbar');
    return current;
  }

  @override
  Future<LocationAccess> request() async {
    requestCount++;
    if (onRequest != null) current = onRequest!;
    return current;
  }

  @override
  Future<bool> gpsEnabled() async {
    if (gpsNeverAnswers) return Completer<bool>().future;
    return gps;
  }

  @override
  Future<bool> openLocationSettings() async {
    openSettingsCount++;
    return settingsOpen;
  }
}
