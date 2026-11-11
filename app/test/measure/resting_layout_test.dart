import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'resting_measure_screen_test.dart' show Rig, goodLive, settle, unusable;

// Alle Werte synthetisch. Prüft, dass auf 390x844 bei größerer Schrift (1,3
// und 2,0) nichts überläuft (WP27 D2a Soll 4), in de und en, hell und dunkel.

typedef _Scene = Future<Rig> Function(
  WidgetTester tester,
  bool dark,
  String lang,
  double scale,
);

Future<Rig> _rig(
  WidgetTester tester,
  bool dark,
  String lang,
  double scale, {
  ProfileRecord? start,
  void Function(Rig r)? prepare,
}) async {
  final r = await Rig.make(start: start);
  prepare?.call(r);
  await r.show(tester, dark: dark, lang: lang, textScale: scale);
  return r;
}

final Map<String, _Scene> _scenes = {
  'Einstieg': (t, d, l, s) => _rig(t, d, l, s),
  'Ruhephase': (t, d, l, s) async {
    final r = await _rig(t, d, l, s);
    r.c.setRestMinutes(3);
    r.c.startRest();
    await t.pump();
    return r;
  },
  'Messung mit Puls': (t, d, l, s) async {
    final r = await _rig(t, d, l, s, prepare: (r) => r.script.live = goodLive);
    await r.measure(t, 30);
    return r;
  },
  'Messung mit Hinweis': (t, d, l, s) async {
    final r = await _rig(
      t,
      d,
      l,
      s,
      prepare: (r) =>
          r.script.live = unusable(PpgQualityReason.tooManyDisturbances),
    );
    await r.measure(t, 20);
    return r;
  },
  'Ergebnis gut mit Vorwert': (t, d, l, s) async {
    final r = await _rig(
      t,
      d,
      l,
      s,
      start: const ProfileRecord(restingHeartRateBpm: 64, birthYear: 1986),
    );
    await r.measure(t, 67);
    return r;
  },
  'Ergebnis eingeschränkt': (t, d, l, s) async {
    final r = await _rig(
      t,
      d,
      l,
      s,
      prepare: (r) => r.script.last = const PpgMeasurement(
        quality: PpgQuality.limited,
        reasons: [PpgQualityReason.lowSignalQuality],
        bpm: 58.4,
      ),
    );
    await r.measure(t, 67);
    return r;
  },
  'Ergebnis mit Fehlerhinweis': (t, d, l, s) async {
    final r = await _rig(t, d, l, s);
    await r.measure(t, 67);
    r.store.failSave = true;
    await r.c.adopt();
    await t.pump();
    return r;
  },
  'Kein Wert, Signal': (t, d, l, s) async {
    final r = await _rig(
      t,
      d,
      l,
      s,
      prepare: (r) => r.script.last = unusable(PpgQualityReason.weakSignal),
    );
    await r.measure(t, 67);
    return r;
  },
  'Kein Wert, keine Kamera': (t, d, l, s) async {
    final r = await _rig(
      t,
      d,
      l,
      s,
      prepare: (r) =>
          r.cam.availabilityState = PpgCameraAvailability.permissionDenied,
    );
    await r.c.startNow();
    await t.pump();
    await t.pump();
    return r;
  },
};

String _scene = '';

void main() {
  for (final lang in ['de', 'en']) {
    for (final dark in [false, true]) {
      for (final scale in [1.0, 1.3, 2.0]) {
        testWidgets(
          'kein Überlauf auf 390x844: $lang, ${dark ? 'dunkel' : 'hell'}, Schrift $scale',
          (tester) async {
            final problems = <String>[];
            final old = FlutterError.onError;
            FlutterError.onError = (d) {
              final text = d.toString();
              if (problems.isEmpty) debugPrint(text);
              problems.add(
                '${d.exceptionAsString().split('\n').first} @ $_scene',
              );
            };
            for (final e in _scenes.entries) {
              _scene = e.key;
              final r = await e.value(tester, dark, lang, scale);
              await settle(tester);
              // Frische Seite je Szene (Rig räumt per addTearDown erst am Ende).
              await tester.pumpWidget(const SizedBox.shrink());
              expect(r.c.phase, isNotNull);
            }
            FlutterError.onError = old;
            expect(problems, isEmpty);
          },
        );
      }
    }
  }
}
