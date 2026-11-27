// Messung, kein Test (läuft nicht im Gate): Zwischenstand der Neuberechnung
// über viele synthetische Läufe, Gesamtdauer und Spitzenspeicher.
//
// Aufruf in app/packages/core:
//   dart run test/benchmark/recalc_snapshot_benchmark.dart [isolate|inline] [Läufe]
//
// Jede Messung in einem eigenen Prozess. Der Spitzenspeicher ist das größte
// RSS des Prozesses während des Zwischenstands, abgetastet alle 5 ms in einem
// eigenen Isolate (läuft weiter, auch wenn der Haupt-Isolate rechnet).
// Ausgegeben werden der Speicher vor dem Zwischenstand (Grundlast: die
// angelegten Läufe), die Spitze und die Differenz.
import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:core/core.dart';

import '../recalculation/recalc_support.dart';

Future<void> main(List<String> args) async {
  final mode = args.isEmpty ? 'isolate' : args[0];
  final count = args.length > 1 ? int.parse(args[1]) : 300;
  final Offload offload = switch (mode) {
    'inline' => inlineOffload,
    'isolate' => isolateOffload,
    _ => throw ArgumentError.value(mode, 'mode', 'isolate oder inline'),
  };
  final w = await RecalcWorld.create();
  final seeding = Stopwatch()..start();
  // Ein Lauf je Tag, 1 h, gleichmäßig; Werte nur am ersten Lauf gerechnet,
  // die übrigen bekommen eine Kopie (buildSnapshot fragt nur, ob ein Lauf
  // Laufwerte hat, und rechnet alles neu).
  final first = DateTime.utc(2030, 2, 25, 8).subtract(Duration(days: count));
  List<ComputedValue>? template;
  for (var i = 0; i < count; i++) {
    final id = await w.seedRun(
      first.add(Duration(days: i)),
      minutes: 60,
      speed: 2.9 + (i % 7) * 0.05,
      bpm: 140 + (i % 11),
    );
    if (template == null) {
      await w.calc().calculateAfterRun(id);
      template = [
        for (final p in await w.session.values.read(ValueOwner.run(id)))
          p.current,
      ];
    } else {
      await w.session.values.writeAll(create: {ValueOwner.run(id): template});
    }
  }
  w.clock.set(recalcNow);
  await w.session.profile.save(profile180);
  seeding.stop();
  final baseRss = ProcessInfo.currentRss;
  final sampler = await _RssSampler.start();
  final service = ValueCalculationService(
    session: w.session,
    clock: w.clock,
    algorithms: AlgorithmRegistry.standard(),
    offload: offload,
  );
  final watch = Stopwatch()..start();
  final snapshot = await service.buildSnapshot();
  watch.stop();
  final peak = await sampler.stop();
  const mib = 1024 * 1024;
  stdout.writeln(
    'modus=$mode läufe=$count anlegen=${seeding.elapsed.inSeconds}s '
    'zwischenstand=${watch.elapsedMilliseconds}ms '
    'grundlast=${baseRss ~/ mib}MiB spitze=${peak ~/ mib}MiB '
    'zuwachs=${(peak - baseRss) ~/ mib}MiB '
    'laufwerte=${snapshot.runCount}',
  );
}

/// Größtes RSS seit [start], abgetastet in einem eigenen Isolate.
class _RssSampler {
  _RssSampler(this._control, this._replies);

  final SendPort _control;
  final StreamIterator<Object?> _replies;

  static Future<_RssSampler> start() async {
    final port = ReceivePort();
    await Isolate.spawn(_sample, port.sendPort);
    final replies = StreamIterator<Object?>(port);
    await replies.moveNext();
    return _RssSampler(replies.current! as SendPort, replies);
  }

  Future<int> stop() async {
    _control.send('stop');
    await _replies.moveNext();
    final peak = _replies.current! as int;
    await _replies.cancel();
    return peak;
  }

  static void _sample(SendPort out) {
    final control = ReceivePort();
    var peak = ProcessInfo.currentRss;
    final timer = Timer.periodic(const Duration(milliseconds: 5), (_) {
      final rss = ProcessInfo.currentRss;
      if (rss > peak) peak = rss;
    });
    control.listen((_) {
      timer.cancel();
      final rss = ProcessInfo.currentRss;
      out.send(rss > peak ? rss : peak);
      control.close();
    });
    out.send(control.sendPort);
  }
}
