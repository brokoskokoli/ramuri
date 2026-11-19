import 'dart:async';

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
    final zeilen = await _pubZeilen(
      () => tapUntil(
        t,
        find.byKey(const Key('ziel')),
        () => taps == 1,
        'ziel',
        reveal: () async {
          reveals++;
          phase.value = _Phase.frei;
          await t.pump();
        },
      ),
    );
    expect(taps, 1);
    expect(reveals, 1);
    // Der Tipp faellt in Versuch 1, ohne dass die Frist vor dem Tipp ablief
    // oder ein zweiter Versuch noetig war.
    expect(zeilen, contains('tap_ziel_fehlt what=ziel versuch=1'));
    expect(zeilen, contains('tap_vor what=ziel versuch=1 im_baum=ja'));
    expect(zeilen.where((z) => z.startsWith('tap_miss')), isEmpty);
    expect(zeilen.where((z) => z.startsWith('tap_ohne_wirkung')), isEmpty);
    expect(zeilen.where((z) => z.contains('versuch=2')), isEmpty);
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

  testWidgets('tapKey: Taste kommt ausserhalb des Sichtbereichs zurück -> '
      'erneut eingeblendet, ein Tipp', (t) async {
    final phase = ValueNotifier(_Phase.verdeckt);
    var taps = 0;
    await t.pumpWidget(_KommtUntenWieder(phase: phase, onTap: () => taps++));
    final zeilen = await _pubZeilen(() => tapKey(t, 'ziel'));
    expect(phase.value, _Phase.frei);
    expect(taps, 1);
    expect(zeilen, contains('tap_ziel_fehlt what=ziel versuch=1'));
  });

  testWidgets('back: zweite Seite zu -> zurück, sobald sie weg ist, ohne '
      'feste Pause', (t) async {
    await t.pumpWidget(const _ZweiSeiten(sperrt: false));
    await t.tap(find.byKey(const Key('oeffnen')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('seite2')), findsOneWidget);
    final vorher = t.binding.clock.now();
    await back(t);
    // Seite und ihr Zurueck-Knopf sind weg, die erste Seite steht.
    expect(find.byKey(const Key('seite2')), findsNothing);
    expect(find.byType(BackButton), findsNothing);
    expect(find.byKey(const Key('oeffnen')), findsOneWidget);
    // Testuhr (keine Wanduhr): nur der Uebergang, keine Pause von 1 s.
    expect(
      t.binding.clock.now().difference(vorher),
      lessThan(const Duration(seconds: 1)),
    );
  });

  testWidgets('back: abgefangenes Zurück -> Zurück ohne Wirkung', (t) async {
    await t.pumpWidget(const _ZweiSeiten(sperrt: true));
    await t.tap(find.byKey(const Key('oeffnen')));
    await t.pumpAndSettle();
    await expectLater(
      back(t),
      throwsA(
        isA<TestFailure>().having(
          (e) => e.message,
          'message',
          'Zurück ohne Wirkung',
        ),
      ),
    );
    expect(find.byKey(const Key('seite2')), findsOneWidget);
  });

  testWidgets('tapDialog: schliessende Taste -> zurück, sobald der Dialog '
      'weg ist, ohne feste Pause', (t) async {
    await t.pumpWidget(const _MitDialog());
    await t.tap(find.byKey(const Key('dialog_auf')));
    await t.pumpAndSettle();
    final vorher = t.binding.clock.now();
    await tapDialog(t, 'dialog_zu');
    expect(find.byKey(const Key('dialog')), findsNothing);
    expect(find.byKey(const Key('dialog_zu')), findsNothing);
    // Testuhr: nur der Uebergang, keine Pause von 300 ms je Tipp danach.
    expect(
      t.binding.clock.now().difference(vorher),
      lessThan(const Duration(seconds: 1)),
    );
  });

  testWidgets('tapDialog: Taste laesst den Dialog offen -> Dialog-Taste '
      '<key> bleibt', (t) async {
    await t.pumpWidget(const _MitDialog());
    await t.tap(find.byKey(const Key('dialog_auf')));
    await t.pumpAndSettle();
    final zeilen = <String>[];
    await expectLater(
      _pubIn(zeilen, () => tapDialog(t, 'dialog_bleibt')),
      throwsA(
        isA<TestFailure>().having(
          (e) => e.message,
          'message',
          'Dialog-Taste dialog_bleibt bleibt',
        ),
      ),
    );
    expect(find.byKey(const Key('dialog')), findsOneWidget);
    expect(zeilen, contains('tap_bleibt what=dialog_bleibt'));
  });

  testWidgets('tapDialog: Menue geht noch auf -> erst tippen, wenn der '
      'Eintrag getroffen wird, Auswahl kommt an', (t) async {
    String? gewaehlt;
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(
            actions: [
              PopupMenuButton<String>(
                key: const Key('menu'),
                onSelected: (v) => gewaehlt = v,
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    key: Key('menu_a'),
                    value: 'a',
                    child: Text('a'),
                  ),
                  PopupMenuItem(
                    key: Key('menu_b'),
                    value: 'b',
                    child: Text('b'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    await t.tap(find.byKey(const Key('menu')));
    // Nur ein Frame: das Menue steht im Baum, ist aber noch nicht offen.
    await t.pump();
    expect(find.byKey(const Key('menu_b')), findsOneWidget);
    await tapDialog(t, 'menu_b');
    await t.pumpAndSettle();
    expect(gewaehlt, 'b');
  });

  testWidgets('tapKey: nach dem Tipp nur ein Frame, keine feste Pause', (
    t,
  ) async {
    var taps = 0;
    await t.pumpWidget(
      MaterialApp(
        home: Center(
          child: TextButton(
            key: const Key('k'),
            onPressed: () => taps++,
            child: const Text('k'),
          ),
        ),
      ),
    );
    final vorher = t.binding.clock.now();
    await tapKey(t, 'k');
    expect(taps, 1);
    expect(t.binding.clock.now().difference(vorher), Duration.zero);
  });

  testWidgets('tapKey: Taste erscheint erst nach dem Aufruf -> gewartet, '
      'ein Tipp', (t) async {
    final phase = ValueNotifier(_Phase.weg);
    var taps = 0;
    await t.pumpWidget(_Erscheint(phase: phase, onTap: () => taps++));
    await tapKey(t, 'ziel');
    expect(taps, 1);
  });

  testWidgets('tapKey: Taste erscheint nie -> Taste <key> fehlt', (t) async {
    await t.pumpWidget(const MaterialApp(home: SizedBox()));
    await expectLater(
      tapKey(t, 'nie'),
      throwsA(
        isA<TestFailure>().having(
          (e) => e.message,
          'message',
          'Taste nie fehlt',
        ),
      ),
    );
  });
}

/// Fuehrt [f] aus und liefert die `logPub`-Zeilen ohne Praefix `PUB_<zeit> `.
Future<List<String>> _pubZeilen(Future<void> Function() f) async {
  final zeilen = <String>[];
  await _pubIn(zeilen, f);
  return zeilen;
}

/// Fuehrt [f] aus und sammelt die `logPub`-Zeilen (ohne Praefix) in [zeilen],
/// auch wenn [f] scheitert.
Future<void> _pubIn(List<String> zeilen, Future<void> Function() f) async {
  await runZoned(
    f,
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) {
        if (line.startsWith('PUB_')) {
          zeilen.add(line.substring(line.indexOf(' ') + 1));
        }
        parent.print(zone, line);
      },
    ),
  );
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

/// Taste `ziel` in einer scrollbaren Seite: erst oben und verdeckt, 150 ms nach
/// dem Aufbau aus dem Baum entfernt, 300 ms nach dem Aufbau unverdeckt weit
/// unterhalb des Sichtbereichs wieder eingebaut (`frei`). Treffbar wird sie nur,
/// wenn sie erneut eingeblendet wird.
class _KommtUntenWieder extends StatefulWidget {
  const _KommtUntenWieder({required this.phase, required this.onTap});

  final ValueNotifier<_Phase> phase;
  final VoidCallback onTap;

  @override
  State<_KommtUntenWieder> createState() => _KommtUntenWiederState();
}

class _KommtUntenWiederState extends State<_KommtUntenWieder> {
  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(milliseconds: 150), () {
      widget.phase.value = _Phase.weg;
    });
    Future<void>.delayed(const Duration(milliseconds: 300), () {
      widget.phase.value = _Phase.frei;
    });
  }

  Widget _taste() => TextButton(
    key: const Key('ziel'),
    onPressed: widget.onTap,
    child: const Text('x'),
  );

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: ValueListenableBuilder<_Phase>(
      valueListenable: widget.phase,
      builder: (context, p, _) => Stack(
        children: [
          SingleChildScrollView(
            child: Column(
              children: [
                if (p == _Phase.verdeckt) _taste(),
                const SizedBox(height: 3000),
                if (p == _Phase.frei) _taste(),
              ],
            ),
          ),
          if (p == _Phase.verdeckt)
            const Positioned.fill(child: ColoredBox(color: Colors.black)),
        ],
      ),
    ),
  );
}

/// Erste Seite mit Taste `oeffnen`; sie oeffnet die zweite Seite `seite2` mit
/// Zurueck-Knopf. Mit [sperrt] faengt die zweite Seite das Zurueck ab
/// (`PopScope(canPop: false)`).
class _ZweiSeiten extends StatelessWidget {
  const _ZweiSeiten({required this.sperrt});

  final bool sperrt;

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        appBar: AppBar(title: const Text('eins')),
        body: Center(
          child: TextButton(
            key: const Key('oeffnen'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => PopScope(
                  canPop: !sperrt,
                  child: Scaffold(
                    key: const Key('seite2'),
                    appBar: AppBar(title: const Text('zwei')),
                  ),
                ),
              ),
            ),
            child: const Text('oeffnen'),
          ),
        ),
      ),
    ),
  );
}

/// Seite mit Taste `dialog_auf`; der Dialog `dialog` hat eine schliessende
/// Taste `dialog_zu` und eine Taste `dialog_bleibt`, die ihn offen laesst.
class _MitDialog extends StatelessWidget {
  const _MitDialog();

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: TextButton(
            key: const Key('dialog_auf'),
            onPressed: () => showDialog<void>(
              context: context,
              builder: (context) => AlertDialog(
                key: const Key('dialog'),
                content: const Text('d'),
                actions: [
                  TextButton(
                    key: const Key('dialog_bleibt'),
                    onPressed: () {},
                    child: const Text('bleibt'),
                  ),
                  TextButton(
                    key: const Key('dialog_zu'),
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('zu'),
                  ),
                ],
              ),
            ),
            child: const Text('auf'),
          ),
        ),
      ),
    ),
  );
}

/// Taste `ziel` steht erst 150 ms nach dem Aufbau im Baum (wie nach einem
/// asynchronen Laden).
class _Erscheint extends StatefulWidget {
  const _Erscheint({required this.phase, required this.onTap});

  final ValueNotifier<_Phase> phase;
  final VoidCallback onTap;

  @override
  State<_Erscheint> createState() => _ErscheintState();
}

class _ErscheintState extends State<_Erscheint> {
  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(milliseconds: 150), () {
      widget.phase.value = _Phase.frei;
    });
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: ValueListenableBuilder<_Phase>(
      valueListenable: widget.phase,
      builder: (context, p, _) => Center(
        child: p == _Phase.frei
            ? TextButton(
                key: const Key('ziel'),
                onPressed: widget.onTap,
                child: const Text('x'),
              )
            : const SizedBox(),
      ),
    ),
  );
}
