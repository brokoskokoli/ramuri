import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/run/run_controller.dart';

import 'app_harness.dart';
import 'history_summary_test.dart' show runAndFinish;

final _t0 = DateTime.utc(2030, 3, 1, 8);

/// Offload, der inline rechnet und die Läufe jeder Vorverarbeitung
/// ([replayJob]) zählt; mit [fail] wirft er dort.
class _CountingOffload {
  final replayed = <int>[];
  bool fail = false;

  Future<R> call<A, R>(R Function(A) job, A argument) async {
    if (identical(job, replayJob)) {
      if (fail) throw StateError('offload');
      if (argument
          is ({
            StoredRun run,
            DateTime end,
            StoredRawData raw,
            List<StoredGap> gaps,
            PreprocessingParameters parameters,
          })) {
        replayed.add(argument.run.id);
      }
    }
    return job(argument);
  }
}

/// Beendet einen synthetischen Lauf (5 min, ein Punkt je Sekunde) über
/// einen [RunController] mit [offload]; liefert Sitzung, Controller und
/// Lauf-ID.
Future<(StorageSession, RunController, int)> _finishRun(Offload offload) async {
  final session = await FakeStorage().open(Uint8List(32));
  await session.profile.save(
    const ProfileRecord(maxHeartRateBpm: 190, restingHeartRateBpm: 60),
  );
  final clock = FakeClock(_t0);
  final location = FakeLocationSource();
  final c = RunController(
    algorithms: AlgorithmRegistry.standard(),
    clock: clock,
    storage: session,
    location: location,
    tickEvery: const Duration(hours: 1),
    offload: offload,
  );
  await c.start();
  for (var i = 0; i < 300; i++) {
    clock.advance(const Duration(seconds: 1));
    location.emit(
      LocationSample(
        time: clock.now(),
        latitude: 50 + i * 0.000027,
        longitude: 8,
        accuracyMeters: 5,
        altitudeMeters: 100,
        verticalAccuracyMeters: 3,
      ),
    );
    await Future<void>.delayed(Duration.zero);
  }
  await c.finish();
  final id = (await session.runs.list()).single.id;
  return (session, c, id);
}

/// Die Laufwerte als Text (Vergleich zweier Durchläufe).
Future<List<String>> _values(StorageSession s, int id) async => [
  for (final p in await s.values.read(ValueOwner.run(id)))
    '${p.original.key}=${p.original.value} ${p.original.method}'
        '@${p.original.methodVersion}/${p.original.parameterVersion}'
        ' ${p.original.preprocessingVersion} n=${p.original.measurementCount}',
]..sort();

void main() {
  test('Nach dem Lauf: Vorverarbeitung über den Offload, Werte wie '
      'inline', () async {
    final offload = _CountingOffload();
    final (session, c, id) = await _finishRun(offload.call);
    addTearDown(c.dispose);
    expect(c.calculationFailed, isFalse);
    expect(offload.replayed, contains(id));

    final (inlineSession, inline, inlineId) = await _finishRun(inlineOffload);
    addTearDown(inline.dispose);
    final expected = await _values(inlineSession, inlineId);
    expect(expected, isNotEmpty);
    expect(await _values(session, id), expected);
  });

  test('Offload wirft nach dem Lauf: calculationFailed, Lauf gespeichert, '
      'Merker steht', () async {
    final offload = _CountingOffload()..fail = true;
    final (session, c, id) = await _finishRun(offload.call);
    addTearDown(c.dispose);
    expect(c.calculationFailed, isTrue);
    expect(c.phase, RecordingPhase.finished);
    final run = await session.runs.get(id);
    expect(run?.state, RunState.finished);
    expect((await session.rawData.read(id)).positions, hasLength(300));
    expect(
      await session.settings.get(ValueCalculationService.calculationPendingKey),
      '$id',
    );
  });

  testWidgets('Lauf über die Oberfläche: die Berechnung nach dem Lauf '
      'rechnet über den Offload der App', (tester) async {
    final offload = _CountingOffload();
    final d = Device()..offload = offload.call;
    await d.start(tester, const Locale('de'));
    await d.skipSetup(tester);
    await runAndFinish(d, tester, 30);
    final id = (await d.session.runs.list()).single.id;
    expect(offload.replayed, contains(id));
    expect(await d.session.values.read(ValueOwner.run(id)), isNotEmpty);
  });

  testWidgets('Lauf über die Oberfläche, Offload wirft: keine Laufwerte, '
      'Lauf gespeichert, Merker steht', (tester) async {
    final offload = _CountingOffload()..fail = true;
    final d = Device()..offload = offload.call;
    await d.start(tester, const Locale('de'));
    await d.skipSetup(tester);
    await runAndFinish(d, tester, 30);
    expect(tester.takeException(), isNull);
    final run = (await d.session.runs.list()).single;
    expect(run.state, RunState.finished);
    expect(await d.session.values.read(ValueOwner.run(run.id)), isEmpty);
    expect(
      await d.session.settings.get(
        ValueCalculationService.calculationPendingKey,
      ),
      '${run.id}',
    );
  });
}
