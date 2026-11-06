import 'package:core/core.dart';
import 'package:test/test.dart';

import 'recalc_support.dart';

/// WP09 D2b: Besitzertag, Atomarität, gespeicherte Basis, Rennen.
void main() {
  group('Besitzertag: lokaler Kalendertag des Laufendes', () {
    // (Ende UTC, Versatz, erwarteter Tag, der andere Kandidat)
    final cases = <(String, DateTime, Duration?, String, String)>[
      (
        'UTC, Berechnung nach Mitternacht',
        DateTime.utc(2030, 2, 25, 23, 20),
        null,
        '2030-02-25',
        '2030-02-26',
      ),
      (
        'lokal +2 h: schon der nächste Tag',
        DateTime.utc(2030, 2, 25, 23, 20),
        const Duration(hours: 2),
        '2030-02-26',
        '2030-02-25',
      ),
      (
        'lokal -1 h: noch der Vortag',
        DateTime.utc(2030, 2, 26, 0, 20),
        const Duration(hours: -1),
        '2030-02-25',
        '2030-02-26',
      ),
    ];
    for (final (name, end, offset, day, other) in cases) {
      test('$name: Speichern, Bestätigen, Löschen', () async {
        final w = await RecalcWorld.create();
        final start = end.subtract(const Duration(minutes: 30));
        final early = await w.seedRun(DateTime.utc(2030, 2, 10, 8));
        await w.calc().calculateAfterRun(early);
        final id = await w.seedRun(start, utcOffset: offset);
        // Die Berechnung läuft erst nach Mitternacht (UTC).
        w.clock.set(DateTime.utc(2030, 2, 26, 0, 45));
        final res = await w.calc().calculateAfterRun(id);
        expect(res.day, day);

        Future<void> expectOnlyDay(String what) async {
          final days = await w.daysWithValues('2030-02-20', '2030-02-28');
          expect(days.keys.toSet(), {day}, reason: what);
          expect(days[other], isNull, reason: what);
        }

        await expectOnlyDay('Speichern');

        // Bestätigen tauscht den Tageswert desselben Tages.
        await w.session.profile.save(profile180);
        final s = w.recalc();
        final offer = await s.profileChanged(
          before: profile190,
          after: profile180,
        );
        w.clock.set(DateTime.utc(2030, 2, 26, 9));
        await s.confirm(offer!);
        await expectOnlyDay('Bestätigen');
        for (final p in (await w.daysWithValues(day, day))[day]!) {
          expect(p.current.computedAt, w.clock.now(), reason: 'neu gerechnet');
        }

        // Löschen des frühen Laufs: Tageswerte des Tages bleiben unter dem Tag.
        await w.session.deleteRun(early);
        await w.calc().refreshAfterDelete();
        await expectOnlyDay('Löschen');
      });
    }

    test('Tag des Laufs ohne Versatz ist der UTC-Tag (dokumentiert)', () async {
      final w = await RecalcWorld.create();
      final id = await w.seedRun(DateTime.utc(2030, 2, 25, 23, 40));
      final run = (await w.session.runs.get(id))!;
      expect(run.endedUtcOffset, isNull);
      expect(dayOfRun(run), '2030-02-26');
    });
  });

  group('Stichtag der Tageswerte', () {
    Future<ComputedValue> longOf(RecalcWorld w, String day) async =>
        (await w.session.values.read(ValueOwner.day(day)))
            .firstWhere((p) => p.original.key == vo2maxLongTermValueKey)
            .current;

    test(
      'vergangener Tag mit +2 h: Stichtag ist das lokale Tagesende',
      () async {
        final w = await RecalcWorld.create();
        const plus2 = Duration(hours: 2);
        // A endet 20:30 UTC = 22:30 lokal (25.), B endet 22:30 UTC = 00:30
        // lokal (26.). Der Tageswert des 25. darf B nicht enthalten, obwohl B
        // vor dem UTC-Tagesende liegt.
        final a = await w.seedRun(
          DateTime.utc(2030, 2, 25, 20),
          utcOffset: plus2,
        );
        final b = await w.seedRun(
          DateTime.utc(2030, 2, 25, 22),
          utcOffset: plus2,
        );
        w.clock.set(DateTime.utc(2030, 2, 27, 9));
        await w.calc().calculateAfterRun(b);
        await w.calc().calculateAfterRun(a);
        final v = await longOf(w, '2030-02-25');
        expect(v.measurementCount, 1);
        expect(v.dataTo, DateTime.utc(2030, 2, 25, 20, 30));
      },
    );

    test(
      'Lauf erst Tage später gerechnet: Stichtag ist sein Tagesende',
      () async {
        final w = await RecalcWorld.create();
        final a = await w.seedRun(DateTime.utc(2030, 2, 20, 8));
        final later = await w.seedRun(DateTime.utc(2030, 2, 25, 8));
        w.clock.set(DateTime.utc(2030, 2, 28, 9));
        await w.calc().calculateAfterRun(later);
        await w.calc().calculateAfterRun(a);
        final v = await longOf(w, '2030-02-20');
        expect(v.measurementCount, 1);
        expect(v.dataTo, DateTime.utc(2030, 2, 20, 8, 30));
      },
    );
  });

  group('nach dem Lauf: alles oder nichts', () {
    test('Fehler beim Lesen eines anderen Laufs hinterlässt nichts', () async {
      final w = await RecalcWorld.create();
      final first = await w.seedRun(DateTime.utc(2030, 2, 20, 8));
      await w.calc().calculateAfterRun(first);
      final second = await w.seedRun(DateTime.utc(2030, 2, 25, 8));
      final before = await w.dump();
      final faulty = FaultySession(
        w.session,
        rawData: FailingRawData(w.session.rawData, failOnRead: 2),
        values: w.session.values,
      );
      await expectLater(
        w.calc(over: faulty).calculateAfterRun(second),
        throwsA(isA<StorageException>()),
      );
      expect(await w.session.values.read(ValueOwner.run(second)), isEmpty);
      expect(await w.dump(), before);
      // Wiederholung gelingt: Laufwert und Tageswerte sind da.
      await w.calc().calculateAfterRun(second);
      expect(await w.session.values.read(ValueOwner.run(second)), hasLength(1));
      expect(
        await w.session.values.read(const ValueOwner.day('2030-02-25')),
        hasLength(2),
      );
    });

    test(
      'Fehler beim Schreiben: eine Transaktion, Wiederholung möglich',
      () async {
        final w = await RecalcWorld.create();
        final id = await w.seedRun(DateTime.utc(2030, 2, 25, 8));
        final before = await w.dump();
        final values = FailingValues(w.session.values)..failWriteAll = true;
        final faulty = FaultySession(
          w.session,
          rawData: w.session.rawData,
          values: values,
        );
        await expectLater(
          w.calc(over: faulty).calculateAfterRun(id),
          throwsA(isA<StorageException>()),
        );
        expect(values.writeAlls, 1);
        expect(await w.dump(), before);
        values.failWriteAll = false;
        await w.calc(over: faulty).calculateAfterRun(id);
        expect(await w.session.values.read(ValueOwner.run(id)), hasLength(1));
        expect(
          await w.session.values.read(const ValueOwner.day('2030-02-25')),
          hasLength(2),
        );
      },
    );
  });

  group('Herzfrequenzbasis am Wert', () {
    test('jeder geschriebene Wert trägt die verwendete Basis', () async {
      final w = await RecalcWorld.create(
        profile: const ProfileRecord(birthYear: 1990, restingHeartRateBpm: 60),
      );
      final id = await w.seedRun(DateTime.utc(2030, 2, 25, 8));
      final res = await w.calc().calculateAfterRun(id);
      for (final v in [res.runValue, res.efficiency!]) {
        final b = v.heartRateBasis!;
        expect((b.maxBpm, b.restingBpm, b.maxIsEstimated), (180, 60, true));
      }
      final stored = (await w.session.values.read(ValueOwner.run(id))).single;
      expect(stored.original.heartRateBasis!.maxBpm, 180);
      // Der Langzeitwert braucht keine Basis.
      expect(res.longTerm.heartRateBasis, isNull);
    });

    test(
      'Läufe mit verschiedenen Basen: Effizienz trägt keine (gemischt)',
      () async {
        final w = await RecalcWorld.create();
        await w.seedFourRunsCalculated();
        await w.session.profile.save(profile180);
        final id = await w.seedRun(DateTime.utc(2030, 2, 28, 8));
        final res = await w.calc().calculateAfterRun(id);
        expect(res.runValue.heartRateBasis!.maxBpm, 180);
        expect(res.efficiency!.heartRateBasis, isNull);
      },
    );

    test('Löschen rechnet alte Werte mit der gespeicherten Basis', () async {
      final w = await RecalcWorld.create();
      final extra = await w.seedRun(DateTime.utc(2030, 1, 10, 8));
      await w.calc().calculateAfterRun(extra);
      final ids = await w.seedFourRunsCalculated();
      w.clock.set(recalcNow);
      // Neue Basis (HFmax 300): würde alle Abschnitte ablehnen. Abgelehnt.
      const rejected = ProfileRecord(
        maxHeartRateBpm: 300,
        restingHeartRateBpm: 60,
      );
      await w.session.profile.save(rejected);
      await w.recalc().profileChanged(before: profile190, after: rejected);
      await w.session.deleteRun(extra);
      await w.calc().refreshAfterDelete();
      final feb25 = await w.session.values.read(
        const ValueOwner.day('2030-02-25'),
      );
      final eff = feb25
          .firstWhere((p) => p.original.key == aerobicEfficiencyValueKey)
          .current;
      expect(eff.quality, isNot(ValueQuality.undeterminable));
      expect(eff.heartRateBasis!.maxBpm, 190);
      // Laufwerte bleiben ganz unverändert.
      final run = (await w.session.values.read(ValueOwner.run(ids.last)))
          .single;
      expect(run.current.heartRateBasis!.maxBpm, 190);
    });

    test(
      'Basis unbekannt (NULL bei Wert, der sie braucht): unverändert',
      () async {
        final w = await RecalcWorld.create();
        // Lauf aus Schema 1: Laufwert ohne Basis.
        final legacy = await w.seedRun(DateTime.utc(2030, 2, 20, 8));
        await w.session.values.createOriginals(ValueOwner.run(legacy), [
          ComputedValue(
            key: vo2maxRunValueKey,
            value: 50,
            unit: vo2maxUnit,
            computedAt: DateTime.utc(2030, 2, 20, 9),
            dataFrom: DateTime.utc(2030, 2, 20, 8),
            dataTo: DateTime.utc(2030, 2, 20, 8, 30),
            measurementCount: 1,
            sources: const ['gps'],
            method: const AcsmReserveVo2maxEstimator().method,
            methodVersion: const AcsmReserveVo2maxEstimator().methodVersion,
            parameterVersion: const FitnessParameters.v3().parameterVersion,
            quality: ValueQuality.sufficient,
          ),
        ]);
        // Ein vorhandener Effizienz-Tageswert, der unverändert bleiben muss.
        const day = ValueOwner.day('2030-02-25');
        final sentinel = ComputedValue(
          key: aerobicEfficiencyValueKey,
          value: 7,
          unit: percentUnit,
          computedAt: DateTime.utc(2030, 2, 25, 10),
          dataFrom: DateTime.utc(2030, 2, 1),
          dataTo: DateTime.utc(2030, 2, 25),
          measurementCount: 4,
          sources: const ['strap'],
          method: aerobicEfficiencyMethod,
          methodVersion: aerobicEfficiencyMethodVersion,
          parameterVersion: 3,
          quality: ValueQuality.sufficient,
        );
        final later = await w.seedRun(DateTime.utc(2030, 2, 25, 8));
        await w.session.values.createOriginals(day, [sentinel]);
        final res = await w.calc().calculateAfterRun(later);
        expect(
          res.efficiency,
          isNull,
          reason: 'Basis des alten Laufs unbekannt',
        );
        await w.calc().refreshAfterDelete();
        final pairs = await w.session.values.read(day);
        final eff = pairs.firstWhere(
          (p) => p.original.key == aerobicEfficiencyValueKey,
        );
        expect(eff.current.value, 7);
        expect(eff.current.computedAt, sentinel.computedAt);
        expect(
          pairs.any((p) => p.original.key == vo2maxLongTermValueKey),
          isTrue,
          reason: 'Langzeitwert aus gespeicherten Laufwerten',
        );
      },
    );
  });

  group('Bestätigen', () {
    late RecalcWorld w;
    late List<int> ids;
    setUp(() async {
      w = await RecalcWorld.create();
      ids = await w.seedFourRunsCalculated();
    });

    test(
      'Berechnungszeit ist jetzt, Stichtag vergangener Tage ist ihr Ende',
      () async {
        final s = w.recalc();
        await w.session.profile.save(profile180);
        final offer = await s.profileChanged(
          before: profile190,
          after: profile180,
        );
        w.clock.set(DateTime.utc(2030, 3, 1, 12));
        await s.confirm(offer!);
        final past = await w.session.values.read(
          const ValueOwner.day('2030-02-20'),
        );
        expect(past, isNotEmpty);
        for (final p in past) {
          expect(p.current.computedAt, w.clock.now()); // FR-0053
          expect(
            p.current.dataTo!.isAfter(
              DateTime.utc(2030, 2, 20, 23, 59, 59, 999),
            ),
            isFalse,
            reason: 'Stand am Ende des Tages, nicht heute',
          );
        }
      },
    );

    test('Lauf ohne Laufwert wird nicht angelegt', () async {
      final bare = await w.seedRun(DateTime.utc(2030, 2, 27, 8));
      final s = w.recalc();
      await w.session.profile.save(profile180);
      final offer = await s.profileChanged(
        before: profile190,
        after: profile180,
      );
      await s.confirm(offer!);
      expect(await w.session.values.read(ValueOwner.run(bare)), isEmpty);
      expect(
        await w.session.values.read(const ValueOwner.day('2030-02-27')),
        isEmpty,
      );
      expect(ids, hasLength(4));
    });

    test('HFmax gleich, aber eingegeben gegen geschätzt: Angebot', () async {
      const entered = ProfileRecord(
        maxHeartRateBpm: 180,
        restingHeartRateBpm: 60,
      );
      const estimated = ProfileRecord(birthYear: 1990, restingHeartRateBpm: 60);
      final offer = await w.recalc().profileChanged(
        before: entered,
        after: estimated,
      );
      expect(offer, isNotNull);
    });

    test(
      'ein Angebot während des Bestätigens wird nicht mitgelöscht',
      () async {
        final s0 = w.recalc();
        await w.session.profile.save(profile180);
        await s0.profileChanged(before: profile190, after: profile180);
        late RecalculationService s;
        final faulty = FaultySession(
          w.session,
          rawData: HookedRawData(w.session.rawData, () async {
            // Das Profil ändert sich zwischen Start und Tausch.
            const next = ProfileRecord(
              maxHeartRateBpm: 170,
              restingHeartRateBpm: 60,
            );
            await w.session.profile.save(next);
            await s.profileChanged(before: profile180, after: next);
          }),
          values: w.session.values,
        );
        s = w.recalc(over: faulty);
        await s.confirm((await s.pendingOffer())!);
        expect(await s.pendingOffer(), isNotNull);
      },
    );
  });
}
