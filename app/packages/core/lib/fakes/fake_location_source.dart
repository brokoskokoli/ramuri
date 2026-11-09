import 'dart:async';

import '../ports/location.dart';

/// Standortquelle, die Punkte und Ausfälle auf Anweisung liefert.
class FakeLocationSource implements LocationSource {
  final _controller = StreamController<LocationSample>.broadcast();
  int _listeners = 0;
  int _peak = 0;

  @override
  Stream<LocationSample> samples() => Stream.multi((c) {
    _listeners++;
    if (_listeners > _peak) _peak = _listeners;
    final sub = _controller.stream.listen(c.add, onError: c.addError);
    c.onCancel = () {
      _listeners--;
      unawaited(sub.cancel());
    };
  }, isBroadcast: true);

  bool get hasListeners => _listeners > 0;

  /// Höchste Zahl gleichzeitiger Zuhörer (die echte Quelle kennt nur einen).
  int get peakListeners => _peak;

  void emit(LocationSample s) => _controller.add(s);

  void fail(Object error) => _controller.addError(error);
}
