import 'dart:async';

import 'package:core/core.dart';
import 'package:test/test.dart';

final _t0 = DateTime.utc(2030, 1, 1, 6, 28);

HeartRateReading _r(int seconds, List<int> rr, {String id = 'gurt-1'}) =>
    HeartRateReading(
      id,
      _t0.add(Duration(seconds: seconds)),
      60,
      rrIntervals: rr,
    );

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  late StreamController<HeartRateReading> source;

  setUp(() => source = StreamController<HeartRateReading>.broadcast());
  tearDown(() => source.close());

  MorningBeltRecorder rec({bool dev = true}) => MorningBeltRecorder(
    readings: source.stream,
    developerMode: () async => dev,
  );

  test(
    'ohne Entwicklermodus wird nichts gespeichert (und nicht abonniert)',
    () async {
      final r = rec(dev: false);
      await r.onRestStarted(_t0);
      source.add(_r(1, [900]));
      await _settle();
      expect(r.packets, isEmpty);
      expect(source.hasListener, isFalse);
      await r.dispose();
    },
  );

  test('im Modus nur das Zeitfenster Ruhephase-Beginn bis Messende', () async {
    final r = rec();
    source.add(_r(-5, [800])); // vor dem Fenster (nicht abonniert)
    await r.onRestStarted(_t0);
    source.add(_r(-1, [801])); // Empfangszeit vor dem Beginn
    source.add(_r(0, [900, 910]));
    source.add(_r(60, [920]));
    source.add(_r(90, const [])); // Puls ohne RR: kein Paket
    await _settle();
    r.onMeasurementEnded(_t0.add(const Duration(seconds: 180)));
    source.add(_r(181, [930])); // nach dem Ende
    await _settle();
    expect(
      [for (final p in r.packets) p.intervals],
      [
        [900, 910],
        [920],
      ],
    );
    expect(r.packets.first.time, _t0);
    expect(r.packets.first.source, 'gurt-1');
    await r.dispose();
  });

  test('Noch einmal öffnet das Fenster wieder, die Lücke fehlt', () async {
    final r = rec();
    await r.onRestStarted(_t0);
    source.add(_r(10, [900]));
    await _settle();
    r.onMeasurementEnded(_t0.add(const Duration(seconds: 20)));
    source.add(_r(25, [910]));
    await _settle();
    r.onMeasurementResumed();
    source.add(_r(40, [920]));
    await _settle();
    expect([for (final p in r.packets) p.intervals.single], [900, 920]);
    await r.dispose();
  });

  test('dispose verwirft die Pakete und trennt (kein Verwaisen)', () async {
    final r = rec();
    await r.onRestStarted(_t0);
    source.add(_r(1, [900]));
    await _settle();
    await r.dispose();
    expect(r.packets, isEmpty);
    expect(source.hasListener, isFalse);
  });
}
