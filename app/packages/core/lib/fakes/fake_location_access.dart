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
  int requestCount = 0;

  @override
  Future<LocationAccess> access() async {
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
  Future<bool> gpsEnabled() async => gps;
}
