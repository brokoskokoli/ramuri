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

  test('expect: nur der Grund, nie Expected/Actual', () {
    final m =
        'Expected: <190>\n  Actual: <60>\n   Which: differs\nReason: Profil gespeichert';
    final out = publicFailure(TestFailure(m));
    expect(out, 'expect: Profil gespeichert');
    expect(out, isNot(contains('190')));
    expect(out, isNot(contains('60')));
  });

  test('andere Fehler: nur der Typ', () {
    expect(publicFailure(StateError('Wert 190')), 'StateError');
  });
}
