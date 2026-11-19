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

  testWidgets('hittable: leerer Finder liefert false und wirft nicht', (
    t,
  ) async {
    await t.pumpWidget(const MaterialApp(home: SizedBox()));
    expect(hittable(t, find.byKey(const Key('fehlt'))), isFalse);
  });

  testWidgets('tapUntil: Ziel fällt vor dem Tipp aus dem Baum, reveal holt es '
      'zurück, genau ein Tipp', (t) async {
    final phase = ValueNotifier(_Phase.verdeckt);
    var taps = 0;
    var reveals = 0;
    await t.pumpWidget(_Verschwindet(phase: phase, onTap: () => taps++));
    await tapUntil(
      t,
      find.byKey(const Key('ziel')),
      () => taps == 1,
      'ziel',
      reveal: () async {
        reveals++;
        phase.value = _Phase.frei;
        await t.pump();
      },
    );
    expect(taps, 1);
    expect(reveals, 1);
  });

  testWidgets('tapUntil: reveal holt das Ziel nicht zurück -> Taste fehlt', (
    t,
  ) async {
    final phase = ValueNotifier(_Phase.verdeckt);
    var taps = 0;
    await t.pumpWidget(_Verschwindet(phase: phase, onTap: () => taps++));
    await expectLater(
      tapUntil(
        t,
        find.byKey(const Key('ziel')),
        () => taps == 1,
        'ziel',
        reveal: () => t.pump(),
      ),
      throwsA(
        isA<TestFailure>().having(
          (e) => e.message,
          'message',
          'Taste fehlt: ziel',
        ),
      ),
    );
    expect(taps, 0);
  });

  testWidgets('tapKey: Taste fehlt bis zur Frist -> Tipp trifft nicht', (
    t,
  ) async {
    final phase = ValueNotifier(_Phase.verdeckt);
    var taps = 0;
    await t.pumpWidget(_Verschwindet(phase: phase, onTap: () => taps++));
    await expectLater(
      tapKey(t, 'ziel'),
      throwsA(
        isA<TestFailure>().having(
          (e) => e.message,
          'message',
          'Tipp trifft ziel nicht',
        ),
      ),
    );
    expect(taps, 0);
  });
}

enum _Phase { verdeckt, weg, frei }

/// Taste `ziel`: erst verdeckt (nicht treffbar), 150 ms nach dem Aufbau aus dem
/// Baum entfernt (wie ein Eintrag einer lazy Liste ausserhalb des gebauten
/// Bereichs); `frei` baut sie unverdeckt wieder ein.
class _Verschwindet extends StatefulWidget {
  const _Verschwindet({required this.phase, required this.onTap});

  final ValueNotifier<_Phase> phase;
  final VoidCallback onTap;

  @override
  State<_Verschwindet> createState() => _VerschwindetState();
}

class _VerschwindetState extends State<_Verschwindet> {
  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(milliseconds: 150), () {
      if (widget.phase.value == _Phase.verdeckt) {
        widget.phase.value = _Phase.weg;
      }
    });
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: ValueListenableBuilder<_Phase>(
      valueListenable: widget.phase,
      builder: (context, p, _) => Stack(
        children: [
          if (p != _Phase.weg)
            Center(
              child: TextButton(
                key: const Key('ziel'),
                onPressed: widget.onTap,
                child: const Text('x'),
              ),
            ),
          if (p == _Phase.verdeckt)
            const Positioned.fill(child: ColoredBox(color: Colors.black)),
        ],
      ),
    ),
  );
}
