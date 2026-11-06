import 'package:core/core.dart';
import 'package:test/test.dart';

import 'recalc_support.dart';

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
}
