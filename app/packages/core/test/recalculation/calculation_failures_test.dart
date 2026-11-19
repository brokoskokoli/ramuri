import 'package:core/core.dart';
import 'package:test/test.dart';

import 'recalc_support.dart';

/// Rohdaten, deren Lesen für Lauf [runId] scheitert, solange [broken] gilt;
/// zählt die Versuche für diesen Lauf.
class _BrokenRaw implements RawDataStore {
  _BrokenRaw(this.inner, this.runId);

  final RawDataStore inner;
  final int runId;
  bool broken = true;
  int attempts = 0;

  @override
  Future<void> append(int runId, RawBatch batch) => inner.append(runId, batch);

  @override
  Future<StoredRawData> read(int id) {
    if (id == runId) {
      attempts++;
      if (broken) throw const StorageException(StorageFailure.failed);
    }
    return inner.read(id);
  }
}

/// Werte, deren erstes Lesen für Lauf [runId] scheitert, solange [unread]
/// gilt (ein „Start“ setzt [armed] wieder); später gelingt es.
class _UnreadValues extends FailingValues {
  _UnreadValues(super.inner, this.runId) {
    failSwapAll = false;
  }

  final int runId;
  bool unread = true;
  bool armed = true;

  @override
  Future<List<ValuePair>> read(ValueOwner owner) {
    if (unread && armed && owner.runId == runId) {
      armed = false;
      throw const StorageException(StorageFailure.failed);
    }
    return inner.read(owner);
  }
}

void main() {
  late RecalcWorld w;

  setUp(() async {
    w = await RecalcWorld.create();
  });

  /// Ein Lauf weit vor den anderen (außerhalb jedes Fensters), dessen
  /// Berechnung scheitert, solange `broken` gilt.
  Future<(int, _BrokenRaw, FaultySession)> brokenRun() async {
    final id = await w.seedRun(DateTime.utc(2026, 6, 1, 8));
    final raw = _BrokenRaw(w.session.rawData, id);
    final session = FaultySession(
      w.session,
      rawData: raw,
      values: w.session.values,
    );
    return (id, raw, session);
  }

  /// Ein „App-Start“: neuer Dienst, Nachholen; Fehler wie in der App
  /// verschluckt.
  Future<void> start(StorageSession s, {ValueCalculationService? calc}) async {
    try {
      await (calc ?? w.calc(over: s)).completePendingCalculations();
    } on Object {
      // wie RecalculationController.start
    }
  }

  Future<Set<int>> uncomputable() => w.calc().failures.uncomputable();

  test('Start 1 bis 3 versuchen je einmal, ab Start 4 kein Versuch mehr; '
      'Zähler und Kennzeichnung gesetzt', () async {
    final (id, raw, s) = await brokenRun();
    final failures = w.calc().failures;
    for (var n = 1; n <= 3; n++) {
      await expectLater(
        w.calc(over: s).completePendingCalculations(),
        throwsA(isA<StorageException>()),
        reason: 'Start $n gibt den Fehler weiter',
      );
      expect(raw.attempts, n, reason: 'Start $n versucht genau einmal');
      expect(await failures.read(), {id: n});
      expect(await uncomputable(), n < 3 ? isEmpty : {id});
    }
    // Start 4 und 5: kein Versuch, kein Fehler, Kennzeichnung bleibt.
    await w.calc(over: s).completePendingCalculations();
    await w.calc(over: s).completePendingCalculations();
    expect(raw.attempts, 3);
    expect(await failures.read(), {id: 3});
    expect(await uncomputable(), {id});
    expect(
      await w.session.settings.get(CalculationFailures.key),
      '${failures.calculationStamp};$id:3',
    );
    // Die Aufzeichnung bleibt unverändert, Werte gibt es keine.
    expect(await w.session.values.read(ValueOwner.run(id)), isEmpty);
    expect((await w.session.runs.get(id))!.state, RunState.finished);
  });

  test('Fehlversuch nach dem Lauf: der Merker bleibt, gezählt wird erst beim '
      'Nachholen', () async {
    final (id, raw, s) = await brokenRun();
    await expectLater(
      w.calc(over: s).calculateAfterRunTracked(id),
      throwsA(isA<StorageException>()),
    );
    expect(await w.calc().failures.read(), isEmpty);
    await start(s);
    expect(await w.calc().failures.read(), {id: 1});
    expect(raw.attempts, 2);
  });

  test('retryUncomputable versucht erneut; gelingt es, sind Kennzeichnung '
      'und Zähler weg', () async {
    final (id, raw, s) = await brokenRun();
    for (var n = 0; n < 4; n++) {
      await start(s);
    }
    expect(raw.attempts, 3);
    // Scheitert der neue Versuch, zählt er als erster.
    await expectLater(
      w.calc(over: s).retryUncomputable(),
      throwsA(isA<StorageException>()),
    );
    expect(raw.attempts, 4);
    expect(await w.calc().failures.read(), {id: 1});
    expect(await uncomputable(), isEmpty);

    raw.broken = false;
    for (var n = 0; n < 2; n++) {
      await start(s);
    }
    await expectLater(w.calc(over: s).retryUncomputable(), completes);
    expect(await runVo2Pairs(w.session, id), hasLength(1));
    expect(await w.calc().failures.read(), isEmpty);
    expect(await uncomputable(), isEmpty);
    expect(await w.session.settings.get(CalculationFailures.key), '');
  });

  test('„Neu berechnen“ (Bestätigen des Angebots) versucht den nicht '
      'berechenbaren Lauf erneut; gelingt es, ist er ausgetragen', () async {
    final (id, raw, s) = await brokenRun();
    await w.seedFourRunsCalculated();
    for (var n = 0; n < 4; n++) {
      await start(s);
    }
    expect(raw.attempts, 3);
    expect(await uncomputable(), {id});

    raw.broken = false;
    final recalc = RecalculationService(
      session: s,
      clock: w.clock,
      calculation: w.calc(over: s),
    );
    await w.session.profile.save(profile180);
    final offer = await recalc.profileChanged(
      before: profile190,
      after: profile180,
    );
    await recalc.confirm(offer!);
    expect(raw.attempts, 4);
    expect(await runVo2Pairs(w.session, id), hasLength(1));
    expect(await uncomputable(), isEmpty);
    expect(await w.session.settings.get(CalculationFailures.key), '');
    await recalc.dispose();
  });

  test('„Neu berechnen“: scheitert der neue Versuch, gilt die Neuberechnung '
      'trotzdem und der Zähler beginnt neu', () async {
    final (id, raw, s) = await brokenRun();
    await w.seedFourRunsCalculated();
    for (var n = 0; n < 4; n++) {
      await start(s);
    }
    final recalc = RecalculationService(
      session: s,
      clock: w.clock,
      calculation: w.calc(over: s),
    );
    await w.session.profile.save(profile180);
    final offer = await recalc.profileChanged(
      before: profile190,
      after: profile180,
    );
    final result = await recalc.confirm(offer!);
    expect(result.runCount, 4);
    expect(raw.attempts, 4);
    expect(await w.calc().failures.read(), {id: 1});
    expect(await uncomputable(), isEmpty);
    // Der nächste Start versucht ihn wieder.
    await start(s);
    expect(raw.attempts, 5);
    await recalc.dispose();
  });

  test('neue Methoden- oder Parameterversion: Zähler eines anderen Stands '
      'gelten nicht, der Start versucht erneut', () async {
    final (id, raw, s) = await brokenRun();
    // Gezählt mit einem älteren Stand der Berechnung.
    await w.session.settings.set(
      CalculationFailures.key,
      'p3-3-vo2max-acsm-hrr-1;$id:3',
      at: w.clock.now(),
    );
    expect(await uncomputable(), isEmpty);
    await start(s);
    expect(raw.attempts, 1);
    expect(await w.calc().failures.read(), {id: 1});

    // Gelingt der Versuch mit dem neuen Stand, ist der Lauf ausgetragen.
    await w.session.settings.set(
      CalculationFailures.key,
      'p3-3-vo2max-acsm-hrr-1;$id:3',
      at: w.clock.now(),
    );
    raw.broken = false;
    await start(s);
    expect(await runVo2Pairs(w.session, id), hasLength(1));
    expect(await uncomputable(), isEmpty);
  });

  test('Lesefehler (unread) zählt nicht als Fehlversuch; andere Läufe werden '
      'weiter nachgeholt', () async {
    final unreadId = await w.seedRun(DateTime.utc(2026, 6, 1, 8));
    final other = await w.seedRun(DateTime.utc(2030, 2, 25, 8));
    final values = _UnreadValues(w.session.values, unreadId);
    final s = FaultySession(
      w.session,
      rawData: w.session.rawData,
      values: values,
    );
    for (var n = 0; n < 4; n++) {
      values.armed = true;
      await expectLater(
        w.calc(over: s).completePendingCalculations(),
        throwsA(isA<StorageException>()),
      );
    }
    expect(await w.calc().failures.read(), isEmpty);
    expect(await uncomputable(), isEmpty);
    expect(await runVo2Pairs(w.session, other), hasLength(1));
    // Lesbar: wird nachgeholt.
    values.unread = false;
    await w.calc(over: s).completePendingCalculations();
    expect(await runVo2Pairs(w.session, unreadId), hasLength(1));
  });

  test('ein nicht berechenbarer Lauf hält andere nicht auf', () async {
    final (id, raw, s) = await brokenRun();
    for (var n = 0; n < 3; n++) {
      await start(s);
    }
    final other = await w.seedRun(DateTime.utc(2030, 2, 25, 8));
    await w.calc(over: s).completePendingCalculations();
    expect(raw.attempts, 3);
    expect(await runVo2Pairs(w.session, other), hasLength(1));
    expect(await uncomputable(), {id});
  });

  test(
    'gelöschter Lauf: sein Zähler wird beim nächsten Start entfernt',
    () async {
      final (id, _, s) = await brokenRun();
      for (var n = 0; n < 3; n++) {
        await start(s);
      }
      await w.session.deleteRun(id);
      await w.calc().completePendingCalculations();
      expect(await w.calc().failures.read(), isEmpty);
      expect(await w.session.settings.get(CalculationFailures.key), '');
    },
  );

  test('scheitert das Zählen, wird der Lauf beim nächsten Start erneut '
      'versucht', () async {
    final id = await w.seedRun(DateTime.utc(2026, 6, 1, 8));
    final raw = _BrokenRaw(w.session.rawData, id);
    var failSettings = true;
    final s = SettingsFailingSession(
      w.session,
      rawData: raw,
      values: w.session.values,
      failSettingsWhen: () => failSettings,
    );
    for (var n = 0; n < 4; n++) {
      await start(s);
    }
    expect(raw.attempts, 4);
    expect(await w.calc().failures.read(), isEmpty);
    failSettings = false;
    await start(s);
    expect(await w.calc().failures.read(), {id: 1});
  });

  test('unlesbare Teile des Merkers werden übergangen', () async {
    final f = w.calc().failures;
    await w.session.settings.set(
      CalculationFailures.key,
      '${f.calculationStamp};x:1,4:,5:2,6:0,7:-1,8:3:1,9:3',
      at: w.clock.now(),
    );
    expect(await f.read(), {5: 2, 9: 3});
    expect(await f.uncomputable(), {9});
    await w.session.settings.set(
      CalculationFailures.key,
      'kaputt',
      at: w.clock.now(),
    );
    expect(await f.read(), isEmpty);
  });

  test('Merker steht nicht im Archiv', () {
    expect(archiveExcludedSettingKeys, contains(CalculationFailures.key));
  });
}
