import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../integration_test/support/e2e_support.dart';

// startRun der E2E-Tests: nach der ersten Frist ohne „GPS gut“
// einmal Zurueck und Start-Seite neu oeffnen, dann die zweite Frist; danach
// eine Meldung mit den sichtbaren Schluesseln der Start-Seite.

/// Ersatz fuer Heute und Start-Seite: [gutAb] ist die Zahl der Oeffnungen, ab
/// der die Seite sofort „GPS gut“ zeigt (0: nie). Sonst „sucht“ und die Taste
/// „Erneut pruefen“.
class _Fake {
  _Fake(this.gutAb);
  final int gutAb;
  int geoeffnet = 0;
  int geschlossen = 0;

  Widget app() => MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: TextButton(
            key: const Key('home_start_run'),
            onPressed: () async {
              geoeffnet++;
              final gut = gutAb > 0 && geoeffnet >= gutAb;
              await Navigator.of(context)
                  .push(MaterialPageRoute<void>(builder: (_) => _start(gut)));
              geschlossen++;
            },
            child: const Text('Lauf'),
          ),
        ),
      ),
    ),
  );

  Widget _start(bool gut) => Scaffold(
    appBar: AppBar(),
    body: Column(
      children: [
        Builder(
          builder: (context) => TextButton(
            key: const Key('run_start_ready'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    const Scaffold(body: Text('0:00', key: Key('run_time'))),
              ),
            ),
            child: const Text('Start'),
          ),
        ),
        if (gut)
          const Text('gut', key: Key('start_gps_good'))
        else ...[
          const Text('sucht', key: Key('start_gps_searching')),
          TextButton(
            key: const Key('run_block_recheck'),
            onPressed: () {},
            child: const Text('erneut'),
          ),
        ],
      ],
    ),
  );
}

Future<void> _start(WidgetTester t, _Fake f) async {
  await t.pumpWidget(f.app());
  await startRun(t, gpsErste: _erste, gpsZweite: _zweite);
}

const _erste = Duration(milliseconds: 600);
const _zweite = Duration(milliseconds: 900);

void main() {
  test('Fristen: 30 s, dann 60 s, gesamt hoechstens 90 s', () {
    expect(gpsErsteFrist, const Duration(seconds: 30));
    expect(gpsZweiteFrist, const Duration(seconds: 60));
    expect(gpsErsteFrist + gpsZweiteFrist, const Duration(seconds: 90));
  });

  testWidgets('GPS gut sofort: kein Neuoeffnen', (t) async {
    final f = _Fake(1);
    await _start(t, f);
    expect(f.geoeffnet, 1);
    expect(f.geschlossen, 0);
    expect(has('run_time'), isTrue);
  });

  testWidgets('GPS gut erst nach Neuoeffnen: einmal zurueck und neu', (
    t,
  ) async {
    final f = _Fake(2);
    await _start(t, f);
    expect(f.geoeffnet, 2);
    expect(f.geschlossen, 1);
    expect(has('run_time'), isTrue);
  });

  testWidgets('nie GPS gut: Meldung mit sichtbaren Schluesseln', (t) async {
    final f = _Fake(0);
    await t.pumpWidget(f.app());
    await expectLater(
      startRun(t, gpsErste: _erste, gpsZweite: _zweite),
      throwsA(
        isA<TestFailure>().having(
          (e) => e.message,
          'message',
          'GPS gut nicht erreicht (Emulator-Fix); sichtbar: '
              'run_block_recheck, start_gps_searching',
        ),
      ),
    );
    // Genau einmal neu geoeffnet, nicht in einer Schleife.
    expect(f.geoeffnet, 2);
    expect(f.geschlossen, 1);
  });

  testWidgets('sichtbare Schluessel: keiner, wenn die Seite fehlt', (t) async {
    await t.pumpWidget(const MaterialApp(home: SizedBox()));
    expect(visibleStartKeys(), isEmpty);
  });
}
