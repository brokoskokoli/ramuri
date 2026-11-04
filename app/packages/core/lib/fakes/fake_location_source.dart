import 'dart:async';

import '../ports/location.dart';

/// Standortquelle, die Punkte und Ausfälle auf Anweisung liefert.
class FakeLocationSource implements LocationSource {
  final _controller = StreamController<LocationSample>.broadcast();

  @override
  Stream<LocationSample> samples() => _controller.stream;

  bool get hasListeners => _controller.hasListener;

  void emit(LocationSample s) => _controller.add(s);

  void fail(Object error) => _controller.addError(error);
}
