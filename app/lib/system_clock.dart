import 'package:core/core.dart';

/// Echte Uhr für den Produktivbetrieb (Tests setzen `FakeClock` ein).
class SystemClock implements Clock {
  const SystemClock();

  @override
  DateTime now() => DateTime.now().toUtc();

  static final Stopwatch _mono = Stopwatch()..start();

  @override
  Duration monotonic() => _mono.elapsed;

  @override
  Duration utcOffsetAt(DateTime at) {
    final o = at.toUtc().toLocal().timeZoneOffset;
    return Duration(seconds: o.inSeconds);
  }
}
