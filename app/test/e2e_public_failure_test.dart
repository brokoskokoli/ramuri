import 'package:flutter_test/flutter_test.dart';

import '../integration_test/support/e2e_support.dart';

// Die Fehlermeldung im oeffentlichen CI-Log darf keine Werte tragen (SEC-0001..0010).
void main() {
  test('fail(...): Text mit Schluessel bleibt, nur die erste Zeile', () {
    expect(
      publicFailure(TestFailure('nach 40 s nicht erreicht: Plan leer\nzweite')),
      'nach 40 s nicht erreicht: Plan leer',
    );
  });

  // Echte TestFailure aus expect(...), nicht ein nachgebautes Format.
  TestFailure real(void Function() f) {
    try {
      f();
    } on TestFailure catch (e) {
      return e;
    }
    throw StateError('expect hat nicht gefehlt');
  }

  test('expect: nur der Grund, nie Expected/Actual', () {
    final failure = real(() => expect(60, 190, reason: 'Profil gespeichert'));
    expect(failure.message, contains('Expected: <190>'));
    final out = publicFailure(failure);
    expect(out, 'expect: Profil gespeichert');
    expect(out, isNot(contains('190')));
    expect(out, isNot(contains('60')));
  });

  test('expect: mehrzeiliges Actual/Which, Grund bleibt', () {
    final failure = real(
      () => expect('geheim\nzwei\ndrei', 'x', reason: 'Text stimmt'),
    );
    expect(failure.message, contains('zwei'));
    final out = publicFailure(failure);
    expect(out, 'expect: Text stimmt');
    expect(out, isNot(contains('geheim')));
    expect(out, isNot(contains('zwei')));
  });

  test('expect ohne Grund: kein Wert', () {
    expect(publicFailure(real(() => expect(60, 190))), 'expect: ohne Grund');
  });

  test('andere Fehler: nur der Typ', () {
    expect(publicFailure(StateError('Wert 190')), 'StateError');
  });
}
