import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../integration_test/support/e2e_support.dart';

// startRun der E2E-Tests: nach der ersten Frist ohne „GPS gut“ einmal Zurueck
// und Start-Seite neu oeffnen, dann die zweite Frist; danach eine Meldung mit
// den sichtbaren Schluesseln der Start-Seite. Fristen hier verkuerzt; die
// Verzoegerungen der Ersatz-Seite liegen mit Abstand zwischen den Fristen.

const _erste = Duration(milliseconds: 600);
const _zweite = Duration(milliseconds: 3000);

/// Ersatz fuer Heute und Start-Seite. [gutNach] je Oeffnung (Index 0 = erste):
/// Verzoegerung, nach der die Seite „GPS gut“ zeigt; null oder fehlend: nie.
/// Bis dahin „sucht“ und die Taste „Erneut pruefen“.
class _Fake {
  _Fake(this.gutNach);
  final List<Duration?> gutNach;
  int geoeffnet = 0;
  int geschlossen = 0;
  int erneut = 0;

  Widget app() => MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: TextButton(
            key: const Key('home_start_run'),
            onPressed: () async {
              final i = geoeffnet++;
              final d = i < gutNach.length ? gutNach[i] : null;
              await Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => _StartSeite(d, () => erneut++),
                ),
              );
              geschlossen++;
            },
            child: const Text('Lauf'),
          ),
        ),
      ),
    ),
  );
}

class _StartSeite extends StatefulWidget {
  const _StartSeite(this.gutNach, this.erneut);
  final Duration? gutNach;
  final VoidCallback erneut;

  @override
  State<_StartSeite> createState() => _StartSeiteState();
}

class _StartSeiteState extends State<_StartSeite> {
  bool gut = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    final d = widget.gutNach;
    if (d == Duration.zero) {
      gut = true;
    } else if (d != null) {
      _timer = Timer(d, () => setState(() => gut = true));
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(),
    body: Column(
      children: [
        TextButton(
          key: const Key('run_start_ready'),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) =>
                  const Scaffold(body: Text('0:00', key: Key('run_time'))),
            ),
          ),
          child: const Text('Start'),
        ),
        if (gut)
          const Text('gut', key: Key('start_gps_good'))
        else ...[
          const Text('sucht', key: Key('start_gps_searching')),
          TextButton(
            key: const Key('run_block_recheck'),
            onPressed: widget.erneut,
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

void main() {
  test('Fristen: 30 s, dann 60 s, gesamt hoechstens 90 s', () {
    expect(gpsErsteFrist, const Duration(seconds: 30));
    expect(gpsZweiteFrist, const Duration(seconds: 60));
    expect(gpsErsteFrist + gpsZweiteFrist, const Duration(seconds: 90));
  });

  testWidgets('GPS gut sofort: kein Neuoeffnen', (t) async {
    final f = _Fake([Duration.zero]);
    await _start(t, f);
    expect(f.geoeffnet, 1);
    expect(f.geschlossen, 0);
    expect(has('run_time'), isTrue);
  });

  testWidgets('GPS gut erst nach Neuoeffnen: einmal zurueck und neu', (
    t,
  ) async {
    final f = _Fake([null, Duration.zero]);
    await _start(t, f);
    expect(f.geoeffnet, 2);
    expect(f.geschlossen, 1);
    expect(has('run_time'), isTrue);
  });

  testWidgets('Neuoeffnen schon nach der ersten Frist, nicht spaeter', (
    t,
  ) async {
    // Die erste Seite wuerde erst deutlich nach der ersten Frist gut.
    final f = _Fake([const Duration(milliseconds: 1800), Duration.zero]);
    await _start(t, f);
    expect(f.geoeffnet, 2);
    expect(f.geschlossen, 1);
  });

  testWidgets('nach dem Neuoeffnen gilt die zweite Frist, nicht die erste', (
    t,
  ) async {
    // Die zweite Seite wird deutlich nach der ersten, vor der zweiten Frist gut.
    final f = _Fake([null, const Duration(milliseconds: 1500)]);
    await _start(t, f);
    expect(f.geoeffnet, 2);
    expect(has('run_time'), isTrue);
  });

  testWidgets('nie GPS gut: Meldung mit sichtbaren Schluesseln', (t) async {
    final f = _Fake([]);
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
    // „Erneut pruefen“ wurde beim Warten getippt.
    expect(f.erneut, greaterThan(0));
  });

  testWidgets('sichtbare Schluessel: keiner, wenn die Seite fehlt', (t) async {
    await t.pumpWidget(const MaterialApp(home: SizedBox()));
    expect(visibleStartKeys(), isEmpty);
  });
}
