import 'dart:convert';
import 'dart:io';

import 'package:core/core.dart';
import 'package:test/test.dart';

import 'ppg_compare.dart';
import 'ppg_synth.dart';

/// Port von `PpgAnalyzerTest.kt` (algo-v0.4-frozen, die 6 synthetischen Tests) und Abgleich
/// gegen die Ausgabe der Kotlin-Referenz auf denselben Vektoren
/// (`fixtures/reference_synthetic.json`, nur synthetische Daten, siehe ALGORITHMUS.md Abschn. 12).

Map<String, Map<String, dynamic>> _loadReference() {
  final list = jsonDecode(
    File('test/ppg/fixtures/reference_synthetic.json').readAsStringSync(),
  ) as List;
  return {
    for (final e in list.cast<Map<String, dynamic>>()) e['name'] as String: e,
  };
}

PpgAnalysisSet runSet(Synth s, {List<PpgSeries> blocks = const []}) =>
    PpgAnalyzer.analyze(
      s.t,
      [PpgSeries('Rot', s.red), PpgSeries('Grün', s.green)],
      blocks,
      ppgStandardWindow,
    );

PpgChannelResult run(Synth s) => runSet(s).best;

Synth _scenario(String name) {
  const ev = [15.3, 28.7, 48.1];
  if (name.startsWith('t1_seed')) {
    return synth(0.85, 0.05, 0.03, 0.3, 30.0, int.parse(name.substring(7)));
  }
  if (name.startsWith('t5_artifacts_seed')) {
    return synth(
      0.85,
      0.05,
      0.03,
      0.3,
      30.0,
      int.parse(name.substring(17)),
      artifacts: ev,
    );
  }
  return switch (name) {
    't2_high_pulse' => synth(0.5, 0.01, 0.01, 0.3, 30.0, 9),
    't3_halves' => synth(0.8, 0.03, 0.02, 0.3, 30.0, 3),
    't4_60fps' => synth(0.85, 0.05, 0.03, 0.3, 60.0, 11),
    't6_blocks' => synth(0.85, 0.05, 0.03, 1.5, 30.0, 31),
    _ => throw ArgumentError(name),
  };
}

List<PpgSeries> _blocks(Synth s) {
  final rnd = KotlinRandom(5);
  return [
    for (var k = 0; k < 4; k++)
      PpgSeries('B$k', [
        for (var i = 0; i < s.t.length; i++)
          k < 2
              ? s.red[i] + 1.5 * rnd.nextDouble(-1.0, 1.0)
              : 100 + 3 * rnd.nextDouble(-1.0, 1.0),
      ]),
  ];
}

void main() {
  final ref = _loadReference();

  group('Generator (Kotlin-Random nachgebaut)', () {
    test('Vektoren stimmen bitgleich mit der Referenz überein', () {
      for (final e in ref.entries) {
        final s = _scenario(e.key);
        final gen = e.value['gen'] as Map<String, dynamic>;
        expect(s.t.length, gen['n'], reason: e.key);
        for (var i = 0; i < 3; i++) {
          expect(s.t[i], (gen['t'] as List)[i], reason: e.key);
          expect(s.red[i], (gen['red'] as List)[i], reason: e.key);
          expect(s.green[i], (gen['green'] as List)[i], reason: e.key);
        }
        expect(s.t.last, gen['tLast'], reason: e.key);
        expect(s.red.last, gen['redLast'], reason: e.key);
      }
    });
  });

  group('Abgleich mit der Kotlin-Referenz (Puls 0,1/min, RMSSD 0,5 ms)', () {
    var maxBpm = 0.0;
    var maxRmssd = 0.0;
    tearDownAll(
      () => print(
        'größte Abweichung Hauptergebnis (synthetisch): '
        'Puls $maxBpm/min, RMSSD $maxRmssd ms',
      ),
    );
    for (final e in ref.entries) {
      test(e.key, () {
        final s = _scenario(e.key);
        final set = runSet(
          s,
          blocks: e.key == 't6_blocks' ? _blocks(s) : const [],
        );
        final diffs = comparePpgSet(
          set,
          e.value['result'] as Map<String, dynamic>,
        );
        expect(diffs, isEmpty);
        final d = mainDeviation(set, e.value['result'] as Map<String, dynamic>);
        maxBpm = d.bpm > maxBpm ? d.bpm : maxBpm;
        maxRmssd = d.rmssd > maxRmssd ? d.rmssd : maxRmssd;
        expect(d.bpm, lessThanOrEqualTo(tolBpm));
        expect(d.rmssd, lessThanOrEqualTo(tolMs));
      });
    }
  });

  group('Die 6 synthetischen Tests der Referenz', () {
    test('findsPulseAndHrvAt30fps', () {
      for (var seed = 1; seed <= 5; seed++) {
        final s = synth(0.85, 0.05, 0.03, 0.3, 30.0, seed);
        final r = run(s);
        final t = truth([for (final b in s.beats) b + 0.12], 5.0, 65.0);
        expect(r.channel, 'Rot');
        expect(r.artifacts, isEmpty, reason: 'keine Fehlalarme');
        for (final m in r.methods) {
          expect(m.total.bpm, closeTo(t.bpm, 0.5), reason: m.name);
          expect(m.total.rmssdMs, closeTo(t.rmssd, 5.0), reason: m.name);
        }
      }
    });

    test('handlesHigherPulse', () {
      final s = synth(0.5, 0.01, 0.01, 0.3, 30.0, 9);
      final r = run(s);
      final t = truth([for (final b in s.beats) b + 0.12], 5.0, 65.0);
      expect(r.main.total.bpm, closeTo(t.bpm, 1.0));
      expect((r.spectralBpm - t.bpm).abs(), lessThan(3));
    });

    test('halvesAreComputed', () {
      final r = run(synth(0.8, 0.03, 0.02, 0.3, 30.0, 3));
      expect(r.main.first.validIbis, greaterThan(30));
      expect(r.main.second.validIbis, greaterThan(30));
      expect(r.main.total.ibis, r.main.first.ibis + r.main.second.ibis);
    });

    test('worksAt60fps', () {
      final s = synth(0.85, 0.05, 0.03, 0.3, 60.0, 11);
      final r = run(s);
      final t = truth([for (final b in s.beats) b + 0.12], 5.0, 65.0);
      expect(r.main.total.bpm, closeTo(t.bpm, 0.5));
      expect(r.main.total.rmssdMs, closeTo(t.rmssd, 3.0));
    });

    test('motionArtifactsAreDetectedAndExcluded', () {
      const ev = [15.3, 28.7, 48.1];
      for (var seed = 21; seed <= 25; seed++) {
        final s = synth(0.85, 0.05, 0.03, 0.3, 30.0, seed, artifacts: ev);
        final r = run(s);
        final t = truth([for (final b in s.beats) b + 0.12], 5.0, 65.0);
        for (final e in ev) {
          expect(
            r.artifacts.any((a) => e - 5 >= a[0] - 0.2 && e - 5 <= a[1] + 0.2),
            isTrue,
            reason: 'Ereignis $e erkannt (seed $seed)',
          );
        }
        expect(r.main.total.bpm, closeTo(t.bpm, 1.0));
        expect(r.main.total.rmssdMs, closeTo(t.rmssd, 5.0));
      }
    });

    test('blockCombinationPrefersCleanBlocks', () {
      final s = synth(0.85, 0.05, 0.03, 1.5, 30.0, 31);
      final set = runSet(s, blocks: _blocks(s));
      final combo = set.all.firstWhere((c) => c.channel == 'Kombi');
      expect((set.blocksUsed, set.blocksScored), (2, 4));
      expect(combo.quality, greaterThan(0.5));
    });
  });

  test('Fixture enthält alle Szenarien der Referenz', () {
    expect(ref.length, 5 + 1 + 1 + 1 + 5 + 1);
  });
}
