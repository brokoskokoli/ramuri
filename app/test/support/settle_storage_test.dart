// Helfer zum Warten in Widget-Tests: Ende am Ereignis, Obergrenze, Meldung.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'settle_storage.dart';

Matcher _failsWith(List<String> parts) => throwsA(
  isA<TestFailure>().having(
    (e) => e.message,
    'message',
    allOf([for (final p in parts) contains(p)]),
  ),
);

/// Eine Animation ohne Ende: Es ist immer ein Frame geplant.
const _endless = MaterialApp(home: Center(child: CircularProgressIndicator()));

void main() {
  group('settleStorage', () {
    testWidgets('Bedingung sofort erfüllt: 0 Frames, die Uhr steht', (
      tester,
    ) async {
      await tester.pumpWidget(const SizedBox());
      var frames = 0;
      final n = await settleStorage(
        tester,
        until: () => true,
        onFrame: () => frames++,
      );
      expect(n, 0);
      expect(frames, 0);
    });

    testWidgets('endet im Frame, in dem die Bedingung gilt', (tester) async {
      await tester.pumpWidget(const SizedBox());
      var frames = 0;
      final n = await settleStorage(
        tester,
        until: () => frames >= 3,
        onFrame: () => frames++,
      );
      expect(n, 3);
      expect(frames, 3);
    });

    testWidgets('Bedingung erst im letzten erlaubten Frame: kein Fehler', (
      tester,
    ) async {
      await tester.pumpWidget(const SizedBox());
      var frames = 0;
      final n = await settleStorage(
        tester,
        until: () => frames >= 5,
        onFrame: () => frames++,
        maxFrames: 5,
      );
      expect(n, 5);
    });

    testWidgets(
      'Bedingung nie erfüllt: Fehler nach genau maxFrames Frames, mit Ziel',
      (tester) async {
        await tester.pumpWidget(const SizedBox());
        var frames = 0;
        await expectLater(
          settleStorage(
            tester,
            until: () => false,
            onFrame: () => frames++,
            what: 'Wert gespeichert',
            maxFrames: 7,
          ),
          _failsWith(['„Wert gespeichert“', 'nach 7 Frames', '16 ms']),
        );
        expect(frames, 7);
      },
    );

    testWidgets('ohne Bedingung, Oberfläche ruhig: nach einem Frame fertig', (
      tester,
    ) async {
      await tester.pumpWidget(const SizedBox());
      expect(await settleStorage(tester), 1);
    });

    testWidgets('ohne Bedingung, Animation ohne Ende: Fehler mit Grund', (
      tester,
    ) async {
      await tester.pumpWidget(_endless);
      await expectLater(
        settleStorage(tester, what: 'Liste geladen', maxFrames: 10),
        _failsWith(['„Liste geladen“', 'nach 10 Frames', 'weiter Frames']),
      );
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('Speicherereignis über die Test-Uhr: endet danach', (
      tester,
    ) async {
      await tester.pumpWidget(const SizedBox());
      var saved = false;
      Timer(const Duration(milliseconds: 100), () => saved = true);
      final n = await settleStorage(
        tester,
        until: () => saved,
        what: 'gespeichert',
      );
      expect(saved, isTrue);
      expect(n, inInclusiveRange(6, 8), reason: '100 ms zu je 16 ms');
    });
  });

  group('settleReal', () {
    testWidgets('Bedingung sofort erfüllt: 0 Frames', (tester) async {
      await tester.pumpWidget(const SizedBox());
      var frames = 0;
      final n = await settleReal(
        tester,
        until: () => true,
        onFrame: () => frames++,
        what: 'x',
      );
      expect(n, 0);
      expect(frames, 0);
    });

    testWidgets('wartet auf Arbeit außerhalb der Test-Uhr (echter Zeitgeber)', (
      tester,
    ) async {
      await tester.pumpWidget(const SizedBox());
      var done = false;
      await tester.runAsync(() async {
        Timer(const Duration(milliseconds: 30), () => done = true);
      });
      final n = await settleReal(
        tester,
        until: () => done,
        what: 'echte Arbeit fertig',
      );
      expect(done, isTrue);
      expect(n, greaterThanOrEqualTo(1));
    });

    testWidgets('Bedingung erst im letzten erlaubten Frame: kein Fehler', (
      tester,
    ) async {
      await tester.pumpWidget(const SizedBox());
      var frames = 0;
      final n = await settleReal(
        tester,
        until: () => frames >= 4,
        onFrame: () => frames++,
        what: 'x',
        realSlice: Duration.zero,
        maxFrames: 4,
      );
      expect(n, 4);
    });

    testWidgets(
      'Bedingung nie erfüllt: Fehler nach genau maxFrames Frames, mit Ziel',
      (tester) async {
        await tester.pumpWidget(const SizedBox());
        var frames = 0;
        await expectLater(
          settleReal(
            tester,
            until: () => false,
            onFrame: () => frames++,
            what: 'Quelle offen',
            realSlice: Duration.zero,
            maxFrames: 6,
          ),
          _failsWith(['settleReal', '„Quelle offen“', 'nach 6 Frames']),
        );
        expect(frames, 6);
      },
    );
  });

  group('observeFrames', () {
    testWidgets('genau so viele Frames, die Test-Uhr rückt je Frame vor', (
      tester,
    ) async {
      await tester.pumpWidget(const SizedBox());
      final seen = <int>[];
      var fired = false;
      Timer(const Duration(milliseconds: 150), () => fired = true);
      await observeFrames(
        tester,
        3,
        frame: const Duration(milliseconds: 50),
        onFrame: seen.add,
      );
      expect(seen, [0, 1, 2]);
      expect(fired, isTrue, reason: '3 × 50 ms Testzeit');
    });
  });
}
