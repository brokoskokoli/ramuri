import 'package:core/core.dart';

/// Echte Uhr für den Produktivbetrieb (Tests setzen `FakeClock` ein).
class SystemClock implements Clock {
  const SystemClock();

  @override
  DateTime now() => DateTime.now().toUtc();
}
