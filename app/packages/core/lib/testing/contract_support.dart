import '../core.dart';

/// Verletzung des Speichervertrags; der Testlauf zeigt sie als Fehler.
class ContractViolation implements Exception {
  ContractViolation(this.message);
  final String message;

  @override
  String toString() => 'ContractViolation: $message';
}

String _text(Object? o) =>
    o is Iterable ? '[${o.map(_text).join(', ')}]' : '$o';

void expectEq(Object? actual, Object? expected, String what) {
  if (_text(actual) != _text(expected)) {
    throw ContractViolation(
      '$what: erwartet ${_text(expected)}, war ${_text(actual)}',
    );
  }
}

void expectTrue(bool ok, String what) {
  if (!ok) throw ContractViolation(what);
}

/// Erwartet eine [StorageException] mit genau dieser Art.
Future<void> expectFails(
  Future<Object?> Function() f,
  StorageFailure failure,
  String what,
) async {
  try {
    await f();
  } on StorageException catch (e) {
    expectEq(e.failure, failure, '$what (Art des Fehlers)');
    return;
  }
  throw ContractViolation('$what: keine Ausnahme, erwartet $failure');
}

/// Eine Prüfung gegen eine frische, leere Speicherdatei.
class StorageContractCase {
  const StorageContractCase(this.name, this.run);
  final String name;
  final Future<void> Function(StorageContractHarness h) run;
}

/// Zugang des Aufrufers zu einer frischen Speicherdatei.
class StorageContractHarness {
  StorageContractHarness({required this.open});

  /// Öffnet die Datei (mit demselben Schlüssel); mehrmals aufrufbar.
  final Future<StorageSession> Function() open;
}

final DateTime t0 = DateTime.utc(2030, 1, 1, 12);

/// Zeit mit Mikrosekunden, damit Abschneiden auffällt.
DateTime at(int seconds, [int micros = 0]) =>
    t0.add(Duration(seconds: seconds, microseconds: micros));

String us(DateTime? t) => '${t?.microsecondsSinceEpoch}/${t?.isUtc}';
