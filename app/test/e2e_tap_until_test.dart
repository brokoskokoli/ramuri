import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../integration_test/support/e2e_support.dart';

// tapUntil wartet auf die Wirkung, statt nach festem Polster erneut zu tippen
// (ein zweiter Tipp nähme die verspätete Wirkung eines Umschalters zurück).
void main() {
  testWidgets('verspätete Wirkung eines Umschalters: nur ein Tipp', (t) async {
    var taps = 0;
    DateTime? first;
    await t.pumpWidget(
      MaterialApp(
        home: Center(
          child: TextButton(
            key: const Key('toggle'),
            onPressed: () {
              taps++;
              first ??= DateTime.now();
            },
            child: const Text('an'),
          ),
        ),
      ),
    );
    // Wirkt erst 700 ms nach dem ersten Tipp und nur bei ungeradem Zähler.
    bool wirkt() =>
        first != null &&
        taps.isOdd &&
        DateTime.now().difference(first!) >= const Duration(milliseconds: 700);
    await tapUntil(t, find.byKey(const Key('toggle')), wirkt, 'toggle');
    expect(taps, 1);
  });

  testWidgets('ohne Wirkung: zweiter Tipp, dann klare Meldung', (t) async {
    var taps = 0;
    await t.pumpWidget(
      MaterialApp(
        home: Center(
          child: TextButton(
            key: const Key('b'),
            onPressed: () => taps++,
            child: const Text('x'),
          ),
        ),
      ),
    );
    await expectLater(
      tapUntil(t, find.byKey(const Key('b')), () => false, 'wirkungslos'),
      throwsA(
        isA<TestFailure>().having(
          (e) => e.message,
          'message',
          'Tipp ohne Wirkung: wirkungslos',
        ),
      ),
    );
    expect(taps, 2);
  });
}
