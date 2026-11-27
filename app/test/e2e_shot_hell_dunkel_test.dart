import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../integration_test/support/e2e_support.dart';

// shotHellDunkel: Fotopaar dunkel/hell an einer Marke; die Systemhelligkeit
// gilt danach wieder, auch wenn das Warten auf das Thema scheitert.
void main() {
  Widget app({bool mitDunkel = true}) => MaterialApp(
    theme: ThemeData(brightness: Brightness.light),
    darkTheme: mitDunkel ? ThemeData(brightness: Brightness.dark) : null,
    home: const Scaffold(body: Text('seite', key: Key('seite'))),
  );

  /// Fuehrt [body] aus und sammelt die Marken `SHOT <name>` mit dem Thema, das
  /// beim Setzen der Marke an `seite` galt.
  Future<List<String>> marken(
    WidgetTester t,
    Future<void> Function() body,
  ) async {
    final out = <String>[];
    await runZoned(
      body,
      zoneSpecification: ZoneSpecification(
        print: (self, parent, zone, line) {
          final i = line.indexOf('SHOT ');
          if (i >= 0) {
            out.add('${line.substring(i + 5)}:${themeAt(t, 'seite')?.name}');
          }
        },
      ),
    );
    return out;
  }

  testWidgets('erst dunkel, dann hell, jeweils mit passendem Thema', (t) async {
    await t.pumpWidget(app());
    final m = await marken(
      t,
      () => shotHellDunkel(t, 'probe', 'seite', pause: false),
    );
    expect(m, ['probe_dunkel:dark', 'probe_hell:light']);
    expect(t.platformDispatcher.platformBrightness, Brightness.light);
  });

  testWidgets('Thema wird nie dunkel: rot, ohne Foto, Helligkeit zurück', (
    t,
  ) async {
    await t.pumpWidget(app(mitDunkel: false));
    late Object fehler;
    final m = await marken(t, () async {
      try {
        await shotHellDunkel(
          t,
          'probe',
          'seite',
          timeout: const Duration(milliseconds: 600),
          pause: false,
        );
      } catch (e) {
        fehler = e;
      }
    });
    expect(fehler, isA<TestFailure>());
    expect(m, isEmpty);
    expect(t.platformDispatcher.platformBrightness, Brightness.light);
  });

  testWidgets('falscher Schlüssel: rot mit Schlüssel, Helligkeit zurück', (
    t,
  ) async {
    await t.pumpWidget(app());
    Object? fehler;
    try {
      await shotHellDunkel(
        t,
        'probe',
        'gibt_es_nicht',
        timeout: const Duration(seconds: 1),
        pause: false,
      );
    } catch (e) {
      fehler = e;
    }
    // Fehlt der Schluessel, wartet waitFor bis zur Frist (kein StateError).
    expect(fehler, isA<TestFailure>());
    expect(
      (fehler! as TestFailure).message,
      'nach 1 s nicht erreicht: Thema dunkel (gibt_es_nicht)',
    );
    expect(t.platformDispatcher.platformBrightness, Brightness.light);
  });
}
