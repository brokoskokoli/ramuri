import 'package:core/core.dart';
import 'package:test/test.dart';

import 'recalc_support.dart';

/// Kopie von [v] mit anderer Methode bzw. Version (Bestand einer älteren
/// App-Version).
ComputedValue changed(
  ComputedValue v, {
  String? method,
  int? methodVersion,
  int? parameterVersion,
}) => ComputedValue(
  key: v.key,
  value: v.value,
  unit: v.unit,
  computedAt: v.computedAt,
  measurementCount: v.measurementCount,
  sources: v.sources,
  method: method ?? v.method,
  methodVersion: methodVersion ?? v.methodVersion,
  parameterVersion: parameterVersion ?? v.parameterVersion,
  quality: v.quality,
  dataFrom: v.dataFrom,
  dataTo: v.dataTo,
  unavailableReason: v.unavailableReason,
  heartRateBasis: v.heartRateBasis,
);

void main() {
  late RecalcWorld w;
  late List<int> ids;

  setUp(() async {
    w = await RecalcWorld.create();
    ids = await w.seedFourRunsCalculated();
  });

  Future<RecalculationOffer> offerAfterChange(RecalculationService s) async {
    await w.session.profile.save(profile180);
    final o = await s.profileChanged(before: profile190, after: profile180);
    expect(o, isNotNull);
    return o!;
  }

  test(
    'Änderung der Basis bietet an (Ereignis, Abfrage), ändert aber nichts',
    () async {
      final s = w.recalc();
      final events = <RecalculationOffer>[];
      s.offers.listen(events.add);
      final before = await w.dump();
      final offer = await offerAfterChange(s);
      await Future<void>.delayed(Duration.zero);
      expect(events, hasLength(1));
      expect(offer.causes, {RecalculationCause.heartRateBasis});
      expect(offer.runIds, unorderedEquals(ids));
      expect((await s.pendingOffer())!.runIds, offer.runIds);
      // Auch ein neuer Dienst (Neustart) findet das Angebot.
      expect(await w.recalc().pendingOffer(), isNotNull);
      expect(await w.dump(), before);
      await s.dispose();
    },
  );

  test('Änderung ohne Einfluss auf die Basis bietet nichts an', () async {
    final s = w.recalc();
    final o = await s.profileChanged(
      before: profile190,
      after: const ProfileRecord(
        maxHeartRateBpm: 190,
        restingHeartRateBpm: 60,
        bodyWeightKg: 80,
      ),
    );
    expect(o, isNull);
    expect(await s.pendingOffer(), isNull);
  });

  test(
    'ohne Bestätigung keine Änderung; confirm ohne Angebot ist ein Fehler',
    () async {
      final s = w.recalc();
      final before = await w.dump();
      await expectLater(
        s.confirm(RecalculationOffer(causes: const {}, runIds: const [])),
        throwsStateError,
      );
      await offerAfterChange(s);
      expect(await w.dump(), before);
    },
  );

  test('Ablehnen ändert keine Werte und verwirft das Angebot', () async {
    final s = w.recalc();
    final offer = await offerAfterChange(s);
    final before = await w.dump();
    await s.decline(offer);
    expect(await w.dump(), before);
    expect(await s.pendingOffer(), isNull);
    await expectLater(s.confirm(offer), throwsStateError);
  });

  test('Bestätigen: original, current und ursprüngliche Qualität abrufbar, Rohdaten unverändert', () async {
    final s = w.recalc();
    final offer = await offerAfterChange(s);
    final before = {for (final id in ids) id: (await runVo2(w.session, id))};
    final dayBefore = await w.session.values.read(
      const ValueOwner.day('2030-02-25'),
    );
    final rawBefore = {
      for (final id in ids) id: await w.session.rawData.read(id),
    };
    w.clock.set(DateTime.utc(2030, 3, 2, 9));

    final result = await s.confirm(offer);
    expect(result.runCount, 4);
    expect(result.dayCount, greaterThan(0));

    for (final id in ids) {
      final p = (await runVo2(w.session, id));
      final b = before[id]!;
      // original unverändert, samt Qualität und Abschnitten.
      expect(p.original.value, b.original.value);
      expect(p.original.quality, b.original.quality);
      expect(p.original.computedAt, b.original.computedAt);
      expect(p.original.sections.length, b.original.sections.length);
      expect(
        p.original.sections.map((x) => x.estimate),
        b.original.sections.map((x) => x.estimate),
      );
      // current neu: HFmax 180 statt 190 -> r = 0,75 -> 51,5 statt 55,5.
      final fast = id == ids[2] || id == ids[3];
      // 0,2 * v + 3,5, hochgerechnet mit r (HFmax 190: 0,692; 180: 0,75).
      final demand = 0.2 * (fast ? 189 : 180) + 3.5;
      expect(b.current.value, closeTo(3.5 + (demand - 3.5) / (90 / 130), 0.2));
      expect(p.current.value, closeTo(3.5 + (demand - 3.5) / 0.75, 0.2));
      expect(p.current.value, isNot(p.original.value));
      expect(p.current.computedAt, w.clock.now());
      expect(p.current.sections, isNotEmpty);
      // Rohdaten unverändert.
      final raw = await w.session.rawData.read(id);
      expect(raw.positions.length, rawBefore[id]!.positions.length);
      expect(raw.heartRates.length, rawBefore[id]!.heartRates.length);
      expect(
        raw.positions.first.value.latitude,
        rawBefore[id]!.positions.first.value.latitude,
      );
    }
    final dayAfter = await w.session.values.read(
      const ValueOwner.day('2030-02-25'),
    );
    expect(dayAfter.length, dayBefore.length);
    for (var i = 0; i < dayAfter.length; i++) {
      expect(dayAfter[i].original.value, dayBefore[i].original.value);
      expect(dayAfter[i].original.computedAt, dayBefore[i].original.computedAt);
    }
    final long = dayAfter.firstWhere(
      (p) => p.original.key == vo2maxLongTermValueKey,
    );
    expect(long.current.value, isNot(long.original.value));
    expect(await s.pendingOffer(), isNull);
  });

  test(
    'Abbruch bei der Berechnung lässt den alten Stand einheitlich',
    () async {
      final s0 = w.recalc();
      await offerAfterChange(s0);
      final before = await w.dump();
      final faulty = FaultySession(
        w.session,
        rawData: FailingRawData(w.session.rawData, failOnRead: 3),
        values: w.session.values,
      );
      final s = w.recalc(over: faulty);
      await expectLater(
        s.confirm((await s.pendingOffer())!),
        throwsA(isA<StorageException>()),
      );
      expect(await w.dump(), before);
      // Das Angebot bleibt, ein neuer Versuch gelingt.
      expect(await w.recalc().pendingOffer(), isNotNull);
      await w.recalc().confirm((await w.recalc().pendingOffer())!);
      expect(await w.dump(), isNot(before));
    },
  );

  test('Abbruch beim Tauschen: ein Sammel-Tausch, nie einzeln', () async {
    final s0 = w.recalc();
    await offerAfterChange(s0);
    final before = await w.dump();
    final values = FailingValues(w.session.values);
    final faulty = FaultySession(
      w.session,
      rawData: w.session.rawData,
      values: values,
    );
    final s = w.recalc(over: faulty);
    await expectLater(
      s.confirm((await s.pendingOffer())!),
      throwsA(isA<StorageException>()),
    );
    expect(values.singleSwaps, 0);
    expect(await w.dump(), before);
    expect(await s.pendingOffer(), isNotNull);
  });

  test(
    'Fehler nach dem Tausch: erledigt gemeldet, Angebot nicht gelöscht',
    () async {
      final s0 = w.recalc();
      await offerAfterChange(s0);
      final before = await w.dump();
      final values = SwapSignalValues(w.session.values);
      final faulty = SettingsFailingSession(
        w.session,
        rawData: w.session.rawData,
        values: values,
        failSettingsWhen: () => values.swapped,
      );
      final s = w.recalc(over: faulty);
      final result = await s.confirm((await s.pendingOffer())!);
      expect(values.swapped, isTrue);
      expect(result.offerCleared, isFalse);
      expect(result.runCount, greaterThan(0));
      expect(await w.dump(), isNot(before));
      expect(await w.recalc().pendingOffer(), isNotNull);
    },
  );

  test('Versionsänderung der Methode oder Parameter bietet an', () async {
    final s = w.recalc();
    expect(await s.checkVersions(), isNull);
    final old = await RecalcWorld.create();
    final id = await old.seedRun(DateTime.utc(2030, 2, 25, 8));
    await old
        .calc(
          fitness: const FitnessParameters(parameterVersion: 2),
          pre: const PreprocessingParameters(parameterVersion: 2),
        )
        .calculateAfterRun(id);
    final offer = await old.recalc().checkVersions();
    expect(offer!.causes, {RecalculationCause.algorithmVersion});
    expect(offer.runIds, [id]);
  });

  group('Versionsprüfung: TRIMP, nicht die Zonenzeiten', () {
    // Ändert nur den Wert [key] im current des ersten Laufs.
    Future<void> alter(
      String key, {
      String? method,
      int? methodVersion,
      int? parameterVersion,
    }) async {
      final owner = ValueOwner.run(ids.first);
      final pair = (await w.session.values.read(owner))
          .firstWhere((p) => p.original.key == key);
      await w.session.values.swapCurrentAll({
        owner: [
          changed(
            pair.current,
            method: method,
            methodVersion: methodVersion,
            parameterVersion: parameterVersion,
          ),
        ],
      });
    }

    test('Ausgangslage: nichts anzubieten', () async {
      expect(await w.recalc().checkVersions(), isNull);
    });

    for (final (name, method, methodVersion, parameterVersion) in [
      ('Methodenversion', null, 99, null),
      ('Methode', 'anderes-trimp', null, null),
      ('Parameterversion', null, null, 99),
    ]) {
      test('TRIMP mit anderer $name bietet an', () async {
        await alter(
          trimpRunValueKey,
          method: method,
          methodVersion: methodVersion,
          parameterVersion: parameterVersion,
        );
        final offer = await w.recalc().checkVersions();
        expect(offer!.causes, {RecalculationCause.algorithmVersion});
        expect(offer.runIds, contains(ids.first));
      });
    }

    test(
      'Zonenzeiten mit anderer Version bieten nichts an (keine Schleife)',
      () async {
        await alter(
          zoneTimeValueKey(1),
          methodVersion: 99,
          parameterVersion: 99,
        );
        expect(await w.recalc().checkVersions(), isNull);
      },
    );

    test('TRIMP veraltet: nach der Bestätigung kein neues Angebot', () async {
      await alter(trimpRunValueKey, methodVersion: 99);
      final before = await w.session.values.read(ValueOwner.run(ids.first));
      final original = before
          .firstWhere((p) => p.original.key == trimpRunValueKey)
          .original;
      final offer = await w.recalc().checkVersions();
      expect(offer, isNotNull);
      await w.recalc().confirm(offer!);
      expect(await w.recalc().checkVersions(), isNull);
      final after = await w.session.values.read(ValueOwner.run(ids.first));
      final pair = after.firstWhere((p) => p.original.key == trimpRunValueKey);
      expect(pair.original.methodVersion, original.methodVersion);
      expect(pair.original.value, original.value);
      expect(pair.current.methodVersion, original.methodVersion);
    });
  });

  group('Versionsprüfung: Tageswerte', () {
    final runStart = DateTime.utc(2030, 2, 25, 8);
    const runDay = '2030-02-25';

    // Ein Lauf mit aktuellen Laufwerten; der Tageswert [key] seines Tages ist
    // mit [stale] gerechnet (original und current), wie von einer älteren
    // App-Version gespeichert.
    Future<RecalcWorld> worldWithStaleDay(
      String key,
      ComputedValue Function(ComputedValue) stale,
    ) async {
      final ref = await RecalcWorld.create();
      await ref.calc().calculateAfterRun(await ref.seedRun(runStart));
      final refValue = (await ref.session.values.read(
        const ValueOwner.day(runDay),
      )).firstWhere((p) => p.original.key == key).original;
      final old = stale(refValue);
      final x = await RecalcWorld.create();
      final id = await x.seedRun(runStart);
      const owner = ValueOwner.day(runDay);
      await x.session.values.createOriginals(owner, [old]);
      await x.calc().calculateAfterRun(id);
      await x.session.values.swapCurrentAll({
        owner: [old],
      });
      return x;
    }

    Future<ComputedValue> dayPart(
      RecalcWorld x,
      String day,
      String key, {
      bool original = false,
    }) async {
      final p = (await x.session.values.read(ValueOwner.day(day)))
          .firstWhere((p) => p.original.key == key);
      return original ? p.original : p.current;
    }

    test('Langzeitwert der Methodenversion 1: Angebot, nach der Bestätigung '
        'Version 2 im current, 1 im original, kein neues Angebot', () async {
      final x = await worldWithStaleDay(
        vo2maxLongTermValueKey,
        (v) => changed(v, methodVersion: 1),
      );
      final offer = await x.recalc().checkVersions();
      expect(offer!.causes, {RecalculationCause.algorithmVersion});
      await x.recalc().confirm(offer);
      final current = await dayPart(x, runDay, vo2maxLongTermValueKey);
      expect(current.methodVersion, vo2maxLongTermMethodVersion);
      expect(current.methodVersion, 2);
      expect(current.method, vo2maxLongTermMethod);
      final original = await dayPart(
        x,
        runDay,
        vo2maxLongTermValueKey,
        original: true,
      );
      expect(original.methodVersion, 1);
      expect(await x.recalc().checkVersions(), isNull);
    });

    for (final (name, method, methodVersion) in [
      ('Methode', 'andere-effizienz', null),
      ('Methodenversion', null, 99),
    ]) {
      test('Aerobe Effizienz mit anderer $name: Angebot, nach der '
          'Bestätigung aktuell, original unverändert', () async {
        final x = await worldWithStaleDay(
          aerobicEfficiencyValueKey,
          (v) => changed(v, method: method, methodVersion: methodVersion),
        );
        final before = await dayPart(
          x,
          runDay,
          aerobicEfficiencyValueKey,
          original: true,
        );
        final offer = await x.recalc().checkVersions();
        expect(offer!.causes, {RecalculationCause.algorithmVersion});
        await x.recalc().confirm(offer);
        final current = await dayPart(x, runDay, aerobicEfficiencyValueKey);
        expect(current.method, aerobicEfficiencyMethod);
        expect(current.methodVersion, aerobicEfficiencyMethodVersion);
        final original = await dayPart(
          x,
          runDay,
          aerobicEfficiencyValueKey,
          original: true,
        );
        expect(original.method, before.method);
        expect(original.methodVersion, before.methodVersion);
        expect(await x.recalc().checkVersions(), isNull);
      });
    }

    for (final key in dayValueKeys) {
      test('$key mit anderer Parameterversion bietet an', () async {
        final x = await worldWithStaleDay(
          key,
          (v) => changed(v, parameterVersion: 99),
        );
        final offer = await x.recalc().checkVersions();
        expect(offer!.causes, {RecalculationCause.algorithmVersion});
      });
    }

    test('Alles aktuell, auch ein Tageswert ohne Wert: kein Angebot', () async {
      final days = await w.session.values.readDayValues(dayValueKeys);
      final all = [for (final d in days.values) ...d.values];
      expect(dayValueKeys, everyElement(isIn(all.map((v) => v.key))));
      expect(
        all.where((v) => v.unavailableReason != null),
        isNotEmpty,
        reason: 'Ausgangslage braucht einen Tageswert ohne Wert',
      );
      expect(await w.recalc().checkVersions(), isNull);
    });

    test('Tageswert an einem Tag ohne Lauf: kein Angebot; eine Bestätigung '
        'aus anderem Grund entfernt ihn, danach kommt keines wieder '
        '(PAR-237)', () async {
      const emptyDay = '2030-02-10';
      final template = await dayPart(w, runDay, vo2maxLongTermValueKey);
      await w.session.values.createOriginals(const ValueOwner.day(emptyDay), [
        changed(template, methodVersion: 1),
      ]);
      expect(await w.recalc().checkVersions(), isNull);

      // Ein anderer veralteter Tageswert löst das Angebot aus.
      final pair = (await w.session.values.read(const ValueOwner.day(runDay)))
          .firstWhere((p) => p.original.key == vo2maxLongTermValueKey);
      await w.session.values.swapCurrentAll({
        const ValueOwner.day(runDay): [changed(pair.current, methodVersion: 1)],
      });
      final offer = await w.recalc().checkVersions();
      expect(offer, isNotNull);
      final before = await w.session.values.read(const ValueOwner.day(runDay));
      await w.recalc().confirm(offer!);
      expect(await w.recalc().checkVersions(), isNull);
      expect(
        await w.session.values.read(const ValueOwner.day(emptyDay)),
        isEmpty,
      );
      // Der Tag mit Lauf behält seine Werte (Original unverändert).
      final after = await w.session.values.read(const ValueOwner.day(runDay));
      expect(
        [for (final p in after) p.original.key],
        [for (final p in before) p.original.key],
      );
    });

    test(
      'Jeder Tagesschlüssel hat Methode und Version, wie gerechnet',
      () async {
        final methods = w.calc().dayValueMethods;
        expect(methods.keys.toSet(), dayValueKeys);
        final days = await w.session.values.readDayValues(dayValueKeys);
        for (final d in days.values) {
          for (final v in d.values) {
            expect((v.method, v.methodVersion), methods[v.key], reason: v.key);
          }
        }
      },
    );
  });
}
