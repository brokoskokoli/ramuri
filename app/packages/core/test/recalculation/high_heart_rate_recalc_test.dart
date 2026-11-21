import 'package:core/core.dart';
import 'package:test/test.dart';

import 'recalc_support.dart';

Future<ValuePair?> _high(RecalcWorld w, int id) async {
  for (final p in await w.session.values.read(ValueOwner.run(id))) {
    if (p.original.key == highHeartRateTimeValueKey) return p;
  }
  return null;
}

void main() {
  group('Zeit bei mindestens 80 % HFmax (PAR-058) als Laufwert', () {
    test('nach dem Lauf angelegt, mit Methode, Version und Basis', () async {
      final w = await RecalcWorld.create();
      // 160 bpm bei HFmax 190: 84 %, die ganzen 12 min zählen.
      final id = await w.seedRun(
        DateTime.utc(2030, 1, 10, 8),
        minutes: 12,
        bpm: 160,
      );
      await w.calc().calculateAfterRun(id);
      expect(await _high(w, id), isNotNull, reason: 'nach dem Lauf angelegt');
      final v = (await _high(w, id))!.original;
      expect(v.value, closeTo(12, 0.05));
      expect(v.unit, minutesUnit);
      expect(v.method, HighHeartRateTime.methodId);
      expect(v.methodVersion, 1);
      expect(v.heartRateBasis!.maxBpm, 190);
      expect(v.quality, ValueQuality.good);
    });

    test('alter Lauf ohne den Wert: Angebot bei neuer Methode, Bestätigen '
        'legt ihn an, danach kein Angebot mehr (ADR-0004)', () async {
      final w = await RecalcWorld.create();
      final fresh = await w.seedRun(DateTime.utc(2030, 1, 10, 8), bpm: 160);
      await w.calc().calculateAfterRun(fresh);
      // Alter Lauf: nur VO2max-Laufwert, vor dem neuen Verfahren gerechnet.
      final old = await w.seedRun(DateTime.utc(2030, 1, 11, 8), bpm: 160);
      final vo2 = (await w.session.values.read(ValueOwner.run(fresh)))
          .singleWhere((p) => p.original.key == vo2maxRunValueKey)
          .original;
      await w.session.values.createOriginals(ValueOwner.run(old), [vo2]);
      expect(await _high(w, old), isNull);

      final s = w.recalc();
      final offer = await s.checkVersions();
      expect(offer, isNotNull, reason: 'Angebot für den alten Lauf');
      expect(offer!.causes, {RecalculationCause.algorithmVersion});
      // Das Angebot umfasst alle neu zu rechnenden Läufe, auch [old].
      expect(offer.runIds, contains(old));
      await s.confirm(offer);

      expect(await _high(w, old), isNotNull, reason: 'Wert angelegt');
      final pair = (await _high(w, old))!;
      expect(pair.original.value, closeTo(30, 0.05));
      expect(pair.current.value, pair.original.value);
      expect(pair.original.method, HighHeartRateTime.methodId);
      expect(await w.recalc().checkVersions(), isNull);
      await s.dispose();
    });

    test('anderer Methodenstand am Wert bietet Neuberechnung an', () async {
      final w = await RecalcWorld.create();
      final id = await w.seedRun(DateTime.utc(2030, 1, 10, 8), bpm: 160);
      await w.calc().calculateAfterRun(id);
      expect(await w.recalc().checkVersions(), isNull);
      final owner = ValueOwner.run(id);
      final c = (await _high(w, id))!.current;
      await w.session.values.swapCurrentAll({
        owner: [
          ComputedValue(
            key: c.key,
            value: c.value,
            heartRateBasis: c.heartRateBasis,
            unit: c.unit,
            computedAt: c.computedAt,
            dataFrom: c.dataFrom,
            dataTo: c.dataTo,
            measurementCount: c.measurementCount,
            sources: c.sources,
            method: c.method,
            methodVersion: 0,
            parameterVersion: c.parameterVersion,
            quality: c.quality,
          ),
        ],
      });
      final offer = await w.recalc().checkVersions();
      expect(offer!.causes, {RecalculationCause.algorithmVersion});
      expect(offer.runIds, contains(id));
    });

    test('HFmax-Änderung tauscht current, original bleibt (FR-0006)', () async {
      final w = await RecalcWorld.create();
      // 150 bpm: bei HFmax 190 79 % (zählt nicht), bei 180 83 % (zählt).
      final id = await w.seedRun(DateTime.utc(2030, 1, 10, 8), bpm: 150);
      await w.calc().calculateAfterRun(id);
      expect((await _high(w, id))!.original.value, 0);
      final s = w.recalc();
      await w.session.profile.save(profile180);
      final offer = await s.profileChanged(
        before: profile190,
        after: profile180,
      );
      await s.confirm(offer!);
      final pair = (await _high(w, id))!;
      expect(pair.original.value, 0);
      expect(pair.original.heartRateBasis!.maxBpm, 190);
      expect(pair.current.value, closeTo(30, 0.05));
      expect(pair.current.heartRateBasis!.maxBpm, 180);
      await s.dispose();
    });
  });
}
