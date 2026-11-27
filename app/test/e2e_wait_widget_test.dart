import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../integration_test/support/e2e_support.dart';

/// Zeigt den Schalter `ziel` erst nach [nach] (Testuhr), wie ein Eintrag einer
/// lazy Liste, der erst nach einem Neuaufbau wieder im Baum steht.
class _Spaet extends StatefulWidget {
  const _Spaet({this.nach});
  final Duration? nach;
  @override
  State<_Spaet> createState() => _SpaetState();
}

class _SpaetState extends State<_Spaet> {
  var _da = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    final nach = widget.nach;
    if (nach != null) {
      _timer = Timer(nach, () => setState(() => _da = true));
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: _da
          ? SwitchListTile(
              key: const Key('ziel'),
              value: true,
              onChanged: (_) {},
              title: const Text('Schalter'),
            )
          : const SizedBox(),
    ),
  );
}

Future<Object?> _fehler(Future<void> Function() body) async {
  try {
    await body();
  } catch (e) {
    return e;
  }
  return null;
}

// Widget-Zugriffe der E2E-Tests warten auf ihr Ziel: fehlt es, laeuft die Frist
// weiter, und am Ende steht eine waitFor-Meldung mit Schritt bzw. Schluessel
// statt `Bad state: No element`.
void main() {
  const frist = Duration(seconds: 1);
  final ziel = find.byKey(const Key('ziel'));

  testWidgets('Bedingung mit maybeWidget: fehlt der Schalter, wartet waitFor', (
    t,
  ) async {
    await t.pumpWidget(const _Spaet());
    final e = await _fehler(
      () => waitFor(
        t,
        () => maybeWidget<SwitchListTile>(ziel)?.value == true,
        'S7d Schalter an',
        timeout: frist,
      ),
    );
    expect(e, isA<TestFailure>());
    expect(
      (e! as TestFailure).message,
      'nach 1 s nicht erreicht: S7d Schalter an',
    );
  });

  testWidgets(
    'Bedingung mit maybeWidget: Schalter kommt spaeter, kein Fehler',
    (t) async {
      await t.pumpWidget(const _Spaet(nach: Duration(milliseconds: 500)));
      await waitFor(
        t,
        () => maybeWidget<SwitchListTile>(ziel)?.onChanged != null,
        'S7d Schalter bedienbar',
      );
      expect(maybeWidget<SwitchListTile>(ziel)?.value, isTrue);
    },
  );

  testWidgets('elementWhen: fehlt das Ziel, Meldung nennt den Schluessel', (
    t,
  ) async {
    await t.pumpWidget(const _Spaet());
    final e = await _fehler(
      () => elementWhen(t, ziel, 'Heute ziel', timeout: frist),
    );
    expect(e, isA<TestFailure>());
    expect((e! as TestFailure).message, 'nach 1 s nicht erreicht: Heute ziel');
  });

  testWidgets('elementWhen: Ziel kommt spaeter, liefert sein Element', (
    t,
  ) async {
    await t.pumpWidget(const _Spaet(nach: Duration(milliseconds: 500)));
    final el = await elementWhen(t, ziel, 'Heute ziel');
    expect(el.widget.key, const Key('ziel'));
    expect(Localizations.localeOf(el).languageCode, 'en');
  });

  testWidgets('widgetWhen: fehlt das Ziel, Meldung nennt den Schluessel', (
    t,
  ) async {
    await t.pumpWidget(const _Spaet());
    final e = await _fehler(
      () => widgetWhen<SwitchListTile>(t, ziel, 'Los ziel', timeout: frist),
    );
    expect(e, isA<TestFailure>());
    expect((e! as TestFailure).message, 'nach 1 s nicht erreicht: Los ziel');
  });

  testWidgets('widgetWhen: Ziel kommt spaeter, liefert das Widget', (t) async {
    await t.pumpWidget(const _Spaet(nach: Duration(milliseconds: 500)));
    final w = await widgetWhen<SwitchListTile>(t, ziel, 'Los ziel');
    expect(w.value, isTrue);
  });

  testWidgets('themeAt: ohne Ziel null statt Fehler', (t) async {
    await t.pumpWidget(const _Spaet());
    expect(themeAt(t, 'ziel'), isNull);
  });
}
