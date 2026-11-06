import 'dart:io';

import 'package:core/core.dart';
import 'package:test/test.dart';

import 'recalc_support.dart';

void main() {
  test(
    'nach dem Lauf: Laufwert als original und current mit Abschnitten',
    () async {
      final w = await RecalcWorld.create();
      final id = await w.seedRun(DateTime.utc(2030, 2, 25, 8));
      final res = await w.calc().calculateAfterRun(id);

      final pair = (await w.session.values.read(ValueOwner.run(id))).single;
      expect(pair.original.key, vo2maxRunValueKey);
      // ACSM: 0,2 * 180 m/min + 3,5 = 39,5; r = (150 - 60) / 130 = 0,692;
      // 3,5 + 36 / 0,692 = 55,5 ml/kg/min.
      expect(pair.original.value, closeTo(55.5, 0.1));
      expect(pair.current.value, pair.original.value);
      expect(pair.original.quality, isNot(ValueQuality.undeterminable));
      expect(pair.original.sections, isNotEmpty);
      expect(pair.original.sections.length, pair.current.sections.length);
      expect(pair.original.sources, containsAll(['strap', 'gps']));
      expect(pair.original.computedAt, w.clock.now());
      expect(res.runValue.value, pair.original.value);
      // Tageswerte am Tag der Berechnung.
      final day = await w.session.values.read(ValueOwner.day(res.day));
      expect(day.map((p) => p.original.key), [
        aerobicEfficiencyValueKey,
        vo2maxLongTermValueKey,
      ]);
      final longTerm = day.last.current;
      expect(longTerm.value, closeTo(pair.original.value!, 0.01));
    },
  );

  test(
    'Sauerstoffbedarf und Abschnitte: abgelehnte bleiben mit Grund',
    () async {
      final w = await RecalcWorld.create();
      // Puls zu niedrig: r unter 0,55 -> alle Abschnitte abgelehnt.
      final id = await w.seedRun(DateTime.utc(2030, 2, 25, 8), bpm: 100);
      await w.calc().calculateAfterRun(id);
      final pair = (await w.session.values.read(ValueOwner.run(id))).single;
      expect(pair.original.quality, ValueQuality.undeterminable);
      expect(pair.original.value, isNull);
      expect(pair.original.sections, isNotEmpty);
      expect(
        pair.original.sections.every((s) => s.status == SectionStatus.rejected),
        isTrue,
      );
      expect(pair.original.sections.first.reasons, isNotEmpty);
    },
  );

  test('Abschnittsauswahl und Schätzer teilen dieselbe HF-Basis', () async {
    // HFmax aus dem Alter: Schätzung, deckelt die Stufe auf vorläufig (PAR-038).
    // Die Abschnittslast nutzt dieselbe HFmax (208 - 0,7 * 40 = 180).
    final w = await RecalcWorld.create(
      profile: const ProfileRecord(birthYear: 1990, restingHeartRateBpm: 60),
    );
    final id = await w.seedRun(DateTime.utc(2030, 2, 25, 8));
    await w.calc().calculateAfterRun(id);
    final v = (await w.session.values.read(ValueOwner.run(id))).single.original;
    expect(v.quality, ValueQuality.provisional);
    // r = (150 - 60) / (180 - 60) = 0,75 -> 3,5 + 36 / 0,75 = 51,5.
    expect(v.value, closeTo(51.5, 0.1));
    expect(
      v.sections.where((s) => s.estimate != null).first.estimate,
      closeTo(51.5, 0.1),
    );
  });

  test(
    'ohne Basis: nicht bestimmbar, wird gespeichert, Langzeitwert bleibt',
    () async {
      final w = await RecalcWorld.create(profile: const ProfileRecord());
      final first = await w.seedRun(DateTime.utc(2030, 2, 25, 8));
      final res = await w.calc().calculateAfterRun(first);
      expect(res.runValue.quality, ValueQuality.undeterminable);
      expect(res.runValue.value, isNull);
      expect(res.longTerm.quality, ValueQuality.undeterminable);

      // Mit Basis kommt ein Wert; ein späterer unbestimmbarer Lauf ändert ihn nicht.
      await w.session.profile.save(profile190);
      final good = await w.seedRun(DateTime.utc(2030, 2, 26, 8));
      final r1 = await w.calc().calculateAfterRun(good);
      await w.session.profile.save(const ProfileRecord());
      final bad = await w.seedRun(DateTime.utc(2030, 2, 27, 8));
      final r2 = await w.calc().calculateAfterRun(bad);
      expect(r2.runValue.quality, ValueQuality.undeterminable);
      expect(r2.longTerm.value, r1.longTerm.value);
    },
  );

  test('jeder erzeugte Wert trägt die sieben Angaben aus FR-0053', () async {
    final w = await RecalcWorld.create();
    await w.seedFourRunsCalculated();
    final pairs = await w.allPairs();
    expect(pairs.length, greaterThanOrEqualTo(3 * 4 ~/ 2));
    expect(pairs.map((p) => p.original.key).toSet(), {
      vo2maxRunValueKey,
      vo2maxLongTermValueKey,
      aerobicEfficiencyValueKey,
    });
    for (final p in pairs) {
      for (final v in [p.original, p.current]) {
        final what = '${v.key} ${v.quality}';
        // 1. Berechnungszeitpunkt
        expect(v.computedAt.isUtc, isTrue, reason: what);
        // 2. Datenzeitraum
        expect(v.dataFrom, isNotNull, reason: what);
        expect(v.dataTo, isNotNull, reason: what);
        expect(v.dataTo!.isBefore(v.dataFrom!), isFalse, reason: what);
        // 3. Anzahl verwertbarer Messungen
        expect(v.measurementCount, greaterThanOrEqualTo(0), reason: what);
        // 5./6. Methode und Version (und Parameterversion)
        expect(v.method.trim(), isNotEmpty, reason: what);
        expect(v.methodVersion, greaterThanOrEqualTo(1), reason: what);
        expect(v.parameterVersion, greaterThanOrEqualTo(1), reason: what);
        // 7. Stufe; ohne Wert genau bei „nicht bestimmbar“
        expect(
          v.value == null,
          v.quality == ValueQuality.undeterminable,
          reason: what,
        );
        if (v.quality != ValueQuality.undeterminable) {
          expect(v.measurementCount, greaterThan(0), reason: what);
          // 4. Datenquellen
          expect(v.sources, isNotEmpty, reason: what);
        }
      }
    }
    // Die aerobe Effizienz ist mit vier Läufen bestimmbar.
    final eff = pairs.where((p) => p.original.key == aerobicEfficiencyValueKey);
    final last = eff
        .map((p) => p.current)
        .singleWhere((v) => v.quality != ValueQuality.undeterminable);
    expect(last.value, closeTo(5, 0.2)); // 3,15 / 3,0 - 1 = 5 %
    expect(last.unit, '%');
  });

  test('Versionsabweichung wirft ArgumentError und speichert nichts', () async {
    final w = await RecalcWorld.create();
    final id = await w.seedRun(DateTime.utc(2030, 2, 25, 8));
    final calc = w.calc(
      pre: const PreprocessingParameters(parameterVersion: 2),
    );
    await expectLater(calc.calculateAfterRun(id), throwsArgumentError);
    expect(await w.session.values.read(ValueOwner.run(id)), isEmpty);
  });

  test('Lauf mit Pause und ohne Dauer', () async {
    final w = await RecalcWorld.create();
    final run = await w.session.runs.create(
      startedAt: DateTime.utc(2030, 2, 25),
    );
    await w.session.runs.setState(
      run.id,
      RunState.finished,
      endedAt: DateTime.utc(2030, 2, 25),
    );
    await w.calc().calculateAfterRun(run.id);
    final v = (await w.session.values.read(ValueOwner.run(run.id))).single;
    expect(v.original.quality, ValueQuality.undeterminable);
  });

  test('nach dem Löschen: Tageswerte neu, Laufwerte unverändert', () async {
    final w = await RecalcWorld.create();
    final ids = await w.seedFourRunsCalculated();
    final keepBefore = [
      for (final id in ids.take(3))
        (await w.session.values.read(ValueOwner.run(id))).single,
    ];
    await w.session.deleteRun(ids.last);
    await w.calc().refreshAfterDelete();

    for (var i = 0; i < 3; i++) {
      final p = (await w.session.values.read(ValueOwner.run(ids[i]))).single;
      expect(p.current.value, keepBefore[i].current.value);
      expect(p.current.computedAt, keepBefore[i].current.computedAt);
    }
    // Der Tag des gelöschten Laufs hat keinen Lauf mehr; dessen Tageswerte
    // sind weg, die übrigen Tage haben welche.
    expect(
      await w.session.values.read(const ValueOwner.day('2030-02-25')),
      isEmpty,
    );
    final feb20 = await w.session.values.read(
      const ValueOwner.day('2030-02-20'),
    );
    expect(feb20, isNotEmpty);
    // Ohne den vierten Lauf fehlt dem aktuellen Fenster die Mindestmenge nicht,
    // die Veränderung stützt sich nur noch auf den Lauf vom 20.2.
    final eff = feb20.firstWhere(
      (p) => p.original.key == aerobicEfficiencyValueKey,
    );
    expect(eff.current.dataTo!.isAfter(DateTime.utc(2030, 2, 25)), isFalse);
  });

  test('SEC-0006: core hat keine Netzwerkabhängigkeit', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, isNot(contains('http')));
    expect(pubspec, isNot(contains('dio')));
    final banned = RegExp(
      r"import\s+'(dart:io|dart:html|dart:js_interop|package:(http|dio|web_socket)[^']*)'",
    );
    for (final f in Directory('lib/src/recalculation').listSync()) {
      if (f is File && f.path.endsWith('.dart')) {
        expect(banned.hasMatch(f.readAsStringSync()), isFalse, reason: f.path);
      }
    }
    for (final f in Directory('lib/src/recalculation').listSync()) {
      if (f is File) {
        expect(f.readAsStringSync(), isNot(contains('DateTime.now(')));
      }
    }
  });
}
