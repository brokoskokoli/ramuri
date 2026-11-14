import 'package:core/core.dart';
import 'package:test/test.dart';

import '../recalculation/recalc_support.dart';

/// Belastungsstand aus der Datenbank (WP19 C4a): Einheiten je lokalem
/// Kalendertag, heute leer, persönlicher Faktor (still / Angebot / Ablehnung),
/// Profilwechsel.
void main() {
  late RecalcWorld w;
  late TrainingLoadService service;
  late RecalculationService recalc;

  // recalcNow = 2030-03-01 12:00 UTC, Versatz 0: heute = 1. März 2030.
  final today = DateTime.utc(2030, 3, 1);
  DateTime ago(int days) => today.subtract(Duration(days: days));

  setUp(() async {
    w = await RecalcWorld.create();
    recalc = w.recalc();
    service = TrainingLoadService(
      session: w.session,
      clock: w.clock,
      calculation: w.calc(),
      recalculation: recalc,
    );
  });

  ComputedValue trimpValue(
    double? value, {
    String method = 'edwards-trimp',
    int version = 1,
    UnavailableReason? reason,
  }) => ComputedValue(
    key: trimpRunValueKey,
    value: value,
    unavailableReason: value == null
        ? (reason ?? UnavailableReason.noHeartRate)
        : null,
    unit: pointsUnit,
    computedAt: recalcNow,
    measurementCount: 1,
    sources: const [],
    method: method,
    methodVersion: version,
    parameterVersion: 1,
    quality: value == null ? ValueQuality.undeterminable : ValueQuality.good,
  );

  /// Legt einen beendeten Lauf an (Ende [end], Dauer 30 min), optional mit
  /// TRIMP-Wert und RPE (sRPE = 30 min * RPE).
  Future<int> addRun(
    DateTime end, {
    ComputedValue? trimp,
    int? rpe,
    Duration? offset,
  }) async {
    final run = await w.session.runs.create(
      startedAt: end.subtract(const Duration(minutes: 30)),
    );
    await w.session.runs.setState(
      run.id,
      RunState.finished,
      endedAt: end,
      endedUtcOffset: offset,
    );
    if (trimp != null) {
      await w.session.values.createOriginals(ValueOwner.run(run.id), [trimp]);
    }
    if (rpe != null) {
      await w.session.subjective.save(
        run.id,
        RunSubjective(rpe: rpe),
        srpe: SrpeLoad.compute(duration: const Duration(minutes: 30), rpe: rpe),
      );
    }
    return run.id;
  }

  /// Zwölf geeignete Läufe (RPE 3, 7, 5 im Wechsel, TRIMP = [ratio] * sRPE),
  /// ab [firstAgo] Tage zurück, alle 12 Stunden einer.
  Future<void> seedFactorRuns(
    double ratio, {
    int firstAgo = 60,
    int n = 12,
    String method = 'edwards-trimp',
  }) async {
    for (var i = 0; i < n; i++) {
      final rpe = const [3, 7, 5][i % 3];
      await addRun(
        ago(firstAgo).add(Duration(hours: 8 + 12 * i)),
        trimp: trimpValue(ratio * 30 * rpe, method: method),
        rpe: rpe,
      );
    }
  }

  LoadDay dayOf(TrainingLoadReport r, DateTime d) =>
      r.series.days.singleWhere((x) => x.day == d);

  group('Einheiten je Tag', () {
    setUp(() => seedFactorRuns(2.0));

    test(
      'Lauf mit TRIMP im aktiven Profil: Last = TRIMP, nicht umgerechnet',
      () async {
        await addRun(
          ago(1).add(const Duration(hours: 9)),
          trimp: trimpValue(80),
        );
        final r = await service.load();
        final d = dayOf(r, ago(1));
        expect(d.load, 80);
        expect(d.flags, isNot(contains(LoadDayFlag.converted)));
        expect(r.series.profile, LoadProfile.edwards);
        expect(r.series.method, trainingLoadMethod);
      },
    );

    test(
      'Lauf ohne gültigen Puls, mit RPE: sRPE mal Faktor, gekennzeichnet',
      () async {
        await addRun(
          ago(1).add(const Duration(hours: 9)),
          trimp: trimpValue(null),
          rpe: 6,
        );
        final r = await service.load();
        expect(r.factor.value, closeTo(2.0, 1e-9));
        final d = dayOf(r, ago(1));
        expect(d.load, closeTo(30 * 6 * 2.0, 1e-9));
        expect(d.flags, contains(LoadDayFlag.converted));
      },
    );

    test('Lauf ohne Puls und ohne RPE: unbewertet, nie 0', () async {
      await addRun(
        ago(1).add(const Duration(hours: 9)),
        trimp: trimpValue(null),
      );
      final r = await service.load();
      final d = dayOf(r, ago(1));
      expect(d.load, isNull);
      expect(d.flags, contains(LoadDayFlag.unrated));
      expect(r.series.summary.unratedUnits, 1);
    });

    test(
      'Lauf mit Puls, aber ohne TRIMP-Wert: unbewertet, auch mit RPE',
      () async {
        await addRun(ago(1).add(const Duration(hours: 9)), rpe: 6);
        final r = await service.load();
        final d = dayOf(r, ago(1));
        expect(d.load, isNull);
        expect(d.flags, contains(LoadDayFlag.unrated));
      },
    );

    test('TRIMP einer anderen Skala (Methode passt nicht): unbewertet, nicht '
        'gemischt', () async {
      await addRun(
        ago(1).add(const Duration(hours: 9)),
        trimp: trimpValue(80, method: 'banister-trimp-male'),
        rpe: 6,
      );
      final r = await service.load();
      final d = dayOf(r, ago(1));
      expect(d.load, isNull);
      expect(d.flags, contains(LoadDayFlag.unrated));
    });

    test(
      'Nachgetragene Trainings (Lauf und Sonstiges) zählen mit Faktor',
      () async {
        await w.session.manualTrainings.add(
          ManualTraining(
            day: ago(2),
            kind: ManualTrainingKind.run,
            duration: const Duration(minutes: 40),
            rpe: 5,
          ),
        );
        await w.session.manualTrainings.add(
          ManualTraining(
            day: ago(3),
            kind: ManualTrainingKind.other,
            duration: const Duration(minutes: 60),
            rpe: 3,
          ),
        );
        final r = await service.load();
        expect(dayOf(r, ago(2)).load, closeTo(40 * 5 * 2.0, 1e-9));
        expect(dayOf(r, ago(2)).flags, contains(LoadDayFlag.converted));
        expect(dayOf(r, ago(3)).load, closeTo(60 * 3 * 2.0, 1e-9));
      },
    );

    test('Mehrere Einheiten eines Tages addieren sich', () async {
      await addRun(ago(1).add(const Duration(hours: 7)), trimp: trimpValue(50));
      await addRun(
        ago(1).add(const Duration(hours: 18)),
        trimp: trimpValue(30),
      );
      await w.session.manualTrainings.add(
        ManualTraining(
          day: ago(1),
          kind: ManualTrainingKind.other,
          duration: const Duration(minutes: 10),
          rpe: 4,
        ),
      );
      final d = dayOf(await service.load(), ago(1));
      expect(d.load, closeTo(50 + 30 + 10 * 4 * 2.0, 1e-9));
      expect(d.unitCount, 3);
    });

    test('Nachtrag mit Datum nach heute zählt nie', () async {
      await addRun(ago(1).add(const Duration(hours: 9)), trimp: trimpValue(50));
      await w.session.manualTrainings.add(
        ManualTraining(
          day: today.add(const Duration(days: 3)),
          kind: ManualTrainingKind.run,
          duration: const Duration(minutes: 40),
          rpe: 9,
        ),
      );
      final r = await service.load();
      expect(r.series.days.last.day.isAfter(today), isFalse);
      expect(r.series.summary.lastUnitDay, ago(1));
    });
  });

  group('Eine Skala (FR-0097): nur Methode und Version des aktiven Modells '
      'zählen als bewertet', () {
    setUp(() async {
      await LoadSettings.writeCoefficients(
        w.session.settings,
        LoadCoefficients.male,
        at: recalcNow,
      );
      await LoadSettings.writeActiveProfile(
        w.session.settings,
        LoadProfile.banister,
        at: recalcNow,
      );
    });

    test('Banister männlich aktiv: weiblicher TRIMP unbewertet, männlicher '
        'bewertet', () async {
      await addRun(
        ago(3).add(const Duration(hours: 9)),
        trimp: trimpValue(70, method: BanisterTrimp.methodIdMale),
      );
      await addRun(
        ago(2).add(const Duration(hours: 9)),
        trimp: trimpValue(90, method: BanisterTrimp.methodIdFemale),
        rpe: 6,
      );
      final r = await service.load();
      expect(r.profileApplicable, isTrue);
      expect(dayOf(r, ago(3)).load, 70);
      final mixed = dayOf(r, ago(2));
      expect(mixed.load, isNull);
      expect(mixed.flags, contains(LoadDayFlag.unrated));
      expect(r.series.summary.unratedUnits, 1);
    });

    test('gleiche Methode, andere Version: unbewertet', () async {
      await addRun(
        ago(2).add(const Duration(hours: 9)),
        trimp: trimpValue(90, method: BanisterTrimp.methodIdMale, version: 2),
      );
      final r = await service.load();
      expect(dayOf(r, ago(2)).load, isNull);
      expect(dayOf(r, ago(2)).flags, contains(LoadDayFlag.unrated));
      expect(r.series.summary.unratedUnits, 1);
    });

    test('Läufe mit TRIMP einer fremden Skala (Methode oder Version) gehen '
        'nicht in den Faktor ein', () async {
      // Nur fremde Skala: weder Faktor noch Läufe gezählt.
      await seedFactorRuns(2.0, method: BanisterTrimp.methodIdFemale);
      var r = await service.load();
      expect(r.factor.value, isNull);
      expect(r.factor.eligibleRuns, 0);
      expect(await LoadSettings.factor(w.session.settings), isNull);
      // Passende Läufe (Faktor 2,0) und neuere fremde (9,0, andere Version):
      // der Faktor kommt allein aus den passenden.
      await seedFactorRuns(
        2.0,
        firstAgo: 50,
        method: BanisterTrimp.methodIdMale,
      );
      for (var i = 0; i < 20; i++) {
        final rpe = const [3, 7, 5][i % 3];
        await addRun(
          ago(30).add(Duration(hours: 8 + 12 * i)),
          trimp: trimpValue(
            9.0 * 30 * rpe,
            method: BanisterTrimp.methodIdMale,
            version: 2,
          ),
          rpe: rpe,
        );
      }
      r = await service.load();
      expect(r.factor.eligibleRuns, 12);
      expect(r.factor.value, closeTo(2.0, 1e-9));
      expect(r.factor.offered, isNull);
    });

    test('Profil nicht anwendbar (Koeffizienten fehlen): kein Faktor, pulslose '
        'Läufe bleiben unbewertet, der gespeicherte Faktor bleibt '
        'unangetastet', () async {
      await LoadSettings.writeCoefficients(
        w.session.settings,
        null,
        at: recalcNow,
      );
      final stored = LoadFactorRecord(
        profile: LoadProfile.banister,
        value: 2.0,
        runs: 12,
        day: ago(5),
      );
      await LoadSettings.writeFactor(w.session.settings, stored, at: recalcNow);
      await addRun(
        ago(1).add(const Duration(hours: 9)),
        trimp: trimpValue(null),
        rpe: 6,
      );
      final r = await service.load();
      expect(r.profileApplicable, isFalse);
      expect(r.factor.value, isNull);
      final d = dayOf(r, ago(1));
      expect(d.load, isNull);
      expect(d.flags, contains(LoadDayFlag.unrated));
      expect(
        (await LoadSettings.factor(w.session.settings))!.storageValue,
        stored.storageValue,
      );
    });

    test('Lücke zwischen Tausch und Schreiben der Einstellung: die getauschten '
        'Läufe zählen nicht in der alten Skala (Bestätigen scheitert nach dem '
        'Tausch)', () async {
      final w2 = await RecalcWorld.create();
      await w2.seedFourRunsCalculated();
      await LoadSettings.writeCoefficients(
        w2.session.settings,
        LoadCoefficients.male,
        at: recalcNow,
      );
      final r2 = w2.recalc();
      await r2.confirm((await r2.requestLoadProfile(LoadProfile.banister))!);
      final svc = TrainingLoadService(
        session: w2.session,
        clock: w2.clock,
        calculation: w2.calc(),
        recalculation: r2,
      );
      final ok = await svc.load();
      expect(ok.series.summary.unratedUnits, 0);
      expect(ok.series.summary.lastUnitDay, isNotNull);

      final offer = (await r2.requestLoadCoefficients(
        LoadCoefficients.female,
      ))!;
      final values = SwapSignalValues(w2.session.values);
      final faulty = SettingsFailingSession(
        w2.session,
        rawData: w2.session.rawData,
        values: values,
        failSettingsWhen: () => values.swapped,
      );
      final result = await w2.recalc(over: faulty).confirm(offer);
      expect(values.swapped, isTrue);
      expect(result.offerCleared, isFalse);
      // Werte weiblich, Einstellung noch männlich: keine Mischung, sondern
      // alle vier Läufe unbewertet.
      expect(
        await LoadSettings.coefficients(w2.session.settings),
        LoadCoefficients.male,
      );
      final gap = await svc.load();
      expect(gap.series.summary.unratedUnits, 4);
      expect(gap.series.days.every((d) => d.load == null), isTrue);
      // Erneutes Bestätigen heilt den Zustand.
      final again = w2.recalc();
      await again.confirm((await again.pendingOffer())!);
      final healed = await svc.load();
      expect(healed.series.summary.unratedUnits, 0);
    });
  });

  group('Lokaltag', () {
    test('Der Tag eines Laufs ist der lokale Tag des Laufendes', () async {
      // 23:30 UTC am 20.2. mit +2 h = 1:30 am 21.2.
      await addRun(
        DateTime.utc(2030, 2, 20, 23, 30),
        trimp: trimpValue(40),
        offset: const Duration(hours: 2),
      );
      // Ohne Versatz (alter Lauf): UTC-Tag 19.2.
      await addRun(DateTime.utc(2030, 2, 19, 23, 30), trimp: trimpValue(10));
      final r = await service.load();
      expect(dayOf(r, DateTime.utc(2030, 2, 21)).load, 40);
      expect(dayOf(r, DateTime.utc(2030, 2, 20)).load, isNull);
      expect(dayOf(r, DateTime.utc(2030, 2, 19)).load, 10);
    });

    test('Heute ist der lokale Tag der Uhr (Versatz)', () async {
      w.clock.utcOffset = const Duration(
        hours: 13,
      ); // 1.3. 12:00 UTC = 2.3. 01:00
      final r = await service.load();
      expect(r.today, DateTime.utc(2030, 3, 2));
    });
  });

  group('Heute leer', () {
    test('Ohne Einheit heute endet der Verlauf gestern; kein Tag mit Last 0, '
        'auch mit Zusage', () async {
      await addRun(ago(3).add(const Duration(hours: 9)), trimp: trimpValue(60));
      await LoadSettings.saveAllRecorded(
        w.session.settings,
        true,
        at: recalcNow,
      );
      final r = await service.load();
      expect(r.todayEmpty, isTrue);
      expect(r.seriesEnd, ago(1));
      expect(r.series.days.last.day, ago(1));
      expect(r.series.days.any((d) => d.day == today), isFalse);
      // Gestern und vorgestern zählen mit Zusage als Last 0.
      expect(r.series.days.last.load, 0);
    });

    test(
      'Mit Einheit heute (auch unbewertet) endet der Verlauf heute',
      () async {
        await addRun(
          ago(3).add(const Duration(hours: 9)),
          trimp: trimpValue(60),
        );
        await addRun(
          today.add(const Duration(hours: 7)),
          trimp: trimpValue(null),
        );
        final r = await service.load();
        expect(r.todayEmpty, isFalse);
        expect(r.series.days.last.day, today);
        expect(r.series.days.last.load, isNull);
      },
    );

    test('Ohne jede Einheit: leere Reihe, keine Aussage', () async {
      final r = await service.load();
      expect(r.series.days, isEmpty);
      expect(r.series.summary.hasStatement, isFalse);
    });
  });

  group('Persönlicher Faktor', () {
    Future<LoadFactorRecord?> stored() =>
        LoadSettings.factor(w.session.settings);

    test('Erster Faktor wird still übernommen und gespeichert', () async {
      await seedFactorRuns(2.0);
      final r = await service.load();
      expect(r.factor.value, closeTo(2.0, 1e-9));
      expect(r.factor.runCount, 12);
      expect(r.factor.tentative, isTrue);
      expect(r.factor.offered, isNull);
      final s = (await stored())!;
      expect(s.profile, LoadProfile.edwards);
      expect(s.value, closeTo(2.0, 1e-9));
      expect(s.runs, 12);
      expect(s.day, today);
      expect(await recalc.pendingOffer(), isNull);
    });

    test(
      'loadReadOnly schreibt nichts und bietet nichts an (WP34 Heute)',
      () async {
        await seedFactorRuns(2.0);
        final before = await w.dump();
        final r = await service.loadReadOnly();
        // Der Faktor wäre berechenbar, ist aber nie übernommen worden.
        expect(r.factor.value, isNull);
        expect(await stored(), isNull);
        expect(await w.dump(), before);

        await service.load();
        await seedFactorRuns(3.0, firstAgo: 30, n: 20);
        final mid = await w.dump();
        final ro = await service.loadReadOnly();
        expect(ro.factor.value, closeTo(2.0, 1e-9));
        expect(ro.factor.offered, isNull);
        expect(await recalc.pendingOffer(), isNull);
        expect((await stored())!.value, closeTo(2.0, 1e-9));
        expect(await w.dump(), mid);
      },
    );

    test(
      'Zu wenige Läufe oder Spreizung: kein Faktor, Grund genannt',
      () async {
        await seedFactorRuns(2.0, n: 9);
        final r = await service.load();
        expect(r.factor.value, isNull);
        expect(r.factor.unavailable, FactorUnavailableReason.tooFewRuns);
        expect(await stored(), isNull);
      },
    );

    test(
      'Neuer Faktor innerhalb 25 %: still übernommen, kein Angebot',
      () async {
        await seedFactorRuns(2.0);
        await service.load();
        // 20 neuere Läufe mit Verhältnis 2,4 (+20 %): Median wird 2,4.
        await seedFactorRuns(2.4, firstAgo: 30, n: 20);
        final r = await service.load();
        expect(r.factor.value, closeTo(2.4, 1e-9));
        expect((await stored())!.value, closeTo(2.4, 1e-9));
        expect(await recalc.pendingOffer(), isNull);
      },
    );

    test('Abweichung über 25 %: Angebot, alter Faktor gilt bis zur '
        'Bestätigung; confirm übernimmt ohne Werte zu tauschen', () async {
      await seedFactorRuns(2.0);
      await service.load();
      await seedFactorRuns(3.0, firstAgo: 30, n: 20);
      final before = await w.dump();
      final r = await service.load();
      expect(r.factor.value, closeTo(2.0, 1e-9));
      expect(r.factor.offered!.value, closeTo(3.0, 1e-9));
      expect((await stored())!.value, closeTo(2.0, 1e-9));
      final offer = (await recalc.pendingOffer())!;
      expect(offer.causes, {RecalculationCause.personalFactor});
      expect(offer.personalFactor!.value, closeTo(3.0, 1e-9));
      // Wiederholtes Laden bietet nicht erneut an.
      await service.load();
      expect((await recalc.pendingOffer())!.causes.length, 1);

      await recalc.confirm(offer);
      expect(await recalc.pendingOffer(), isNull);
      expect((await stored())!.value, closeTo(3.0, 1e-9));
      expect(await w.dump(), before);
      final after = await service.load();
      expect(after.factor.value, closeTo(3.0, 1e-9));
      expect(after.factor.offered, isNull);
    });

    test('Ablehnen behält den alten Faktor und bietet denselben nicht erneut '
        'an; ein deutlich anderer wird wieder angeboten', () async {
      await seedFactorRuns(2.0);
      await service.load();
      await seedFactorRuns(3.0, firstAgo: 30, n: 20);
      await service.load();
      await recalc.decline((await recalc.pendingOffer())!);
      expect((await stored())!.value, closeTo(2.0, 1e-9));
      var r = await service.load();
      expect(r.factor.value, closeTo(2.0, 1e-9));
      expect(r.factor.offered, isNull);
      expect(await recalc.pendingOffer(), isNull);
      // Neuere Läufe mit 5: weit weg vom abgelehnten Wert.
      await seedFactorRuns(5.0, firstAgo: 10, n: 20);
      r = await service.load();
      expect(r.factor.offered!.value, closeTo(5.0, 1e-9));
      expect(await recalc.pendingOffer(), isNotNull);
    });

    test(
      'Fällt der berechnete Faktor weg, wird das Angebot zurückgenommen; der '
      'angewandte Faktor bleibt gekennzeichnet',
      () async {
        await seedFactorRuns(2.0);
        await service.load();
        await seedFactorRuns(3.0, firstAgo: 30, n: 20);
        await service.load();
        expect(await recalc.pendingOffer(), isNotNull);
        for (final run in await w.session.runs.list()) {
          await w.session.subjective.save(run.id, RunSubjective());
        }
        final r = await service.load();
        expect(r.factor.value, closeTo(2.0, 1e-9));
        expect(r.factor.unsupported, isTrue);
        expect(r.factor.unavailable, FactorUnavailableReason.tooFewRuns);
        expect(r.factor.offered, isNull);
        expect(await recalc.pendingOffer(), isNull);
        expect((await stored())!.value, closeTo(2.0, 1e-9));
      },
    );

    test('Einmal angewandt, später unter der Mindestanzahl (180-Tage-Fenster): '
        'Faktor bleibt, umgerechnete Tage werden nicht unbewertet', () async {
      await seedFactorRuns(2.0);
      // Lauf ohne Puls mit RPE, lange vor dem Fenster-Ende.
      await addRun(
        ago(1).add(const Duration(hours: 9)),
        trimp: trimpValue(null),
        rpe: 6,
      );
      final first = await service.load();
      expect(first.factor.value, closeTo(2.0, 1e-9));
      expect(first.factor.unsupported, isFalse);
      final day = dayOf(first, ago(1));
      expect(day.load, closeTo(30 * 6 * 2.0, 1e-9));

      // 200 Tage später liegen alle Faktor-Läufe außerhalb der 180 Tage.
      w.clock.set(recalcNow.add(const Duration(days: 200)));
      final later = await service.load();
      expect(later.factor.unavailable, FactorUnavailableReason.tooFewRuns);
      expect(later.factor.unsupported, isTrue);
      expect(later.factor.value, closeTo(2.0, 1e-9));
      expect(later.factor.adoptedDay, today);
      expect((await stored())!.value, closeTo(2.0, 1e-9));
      final kept = dayOf(later, ago(1));
      expect(kept.load, closeTo(30 * 6 * 2.0, 1e-9));
      expect(kept.flags, contains(LoadDayFlag.converted));
      expect(kept.flags, isNot(contains(LoadDayFlag.unrated)));
    });

    group('Vorwert der letzten 6 Monate (PAR-087)', () {
      Future<TrainingLoadReport> afterDays(int days) async {
        await seedFactorRuns(2.0);
        await service.load(); // Faktor 2,0 am Tag `today`
        w.clock.set(recalcNow.add(Duration(days: days)));
        // Neue Läufe ab Tag +days-14, Verhältnis 3,0 (+50 %); die alten
        // liegen außerhalb des 180-Tage-Fensters.
        await seedFactorRuns(3.0, firstAgo: -(days - 14));
        return service.load();
      }

      test(
        'Vorwert 183 Tage alt: Abweichung über 25 % wird angeboten',
        () async {
          final r = await afterDays(183);
          expect(r.factor.value, closeTo(2.0, 1e-9));
          expect(r.factor.offered!.value, closeTo(3.0, 1e-9));
          expect(await recalc.pendingOffer(), isNotNull);
        },
      );

      test('Vorwert 184 Tage alt: kein Vorwert, neuer Faktor still '
          'übernommen', () async {
        final r = await afterDays(184);
        expect(r.factor.value, closeTo(3.0, 1e-9));
        expect(r.factor.offered, isNull);
        expect(await recalc.pendingOffer(), isNull);
        expect((await stored())!.value, closeTo(3.0, 1e-9));
      });
    });
  });

  group('Ablehnung des Faktors gilt nur bis 183 Tage (PAR-087)', () {
    Future<TrainingLoadReport> withDeclined(int declinedAgeDays) async {
      await seedFactorRuns(3.0); // Kandidat 3,0
      await LoadSettings.writeFactor(
        w.session.settings,
        LoadFactorRecord(
          profile: LoadProfile.edwards,
          value: 2.0,
          runs: 12,
          day: today,
        ),
        at: recalcNow,
      );
      await LoadSettings.writeDeclinedFactor(
        w.session.settings,
        LoadFactorRecord(
          profile: LoadProfile.edwards,
          value: 3.0,
          runs: 12,
          day: ago(declinedAgeDays),
        ),
        at: recalcNow,
      );
      return service.load();
    }

    test(
      '183 Tage alt: ähnlicher Faktor wird nicht erneut angeboten',
      () async {
        final r = await withDeclined(183);
        expect(r.factor.offered, isNull);
        expect(await recalc.pendingOffer(), isNull);
      },
    );

    test(
      '184 Tage alt: Ablehnung verfallen, der Faktor wird angeboten',
      () async {
        final r = await withDeclined(184);
        expect(r.factor.offered!.value, closeTo(3.0, 1e-9));
        expect(await recalc.pendingOffer(), isNotNull);
      },
    );

    test('alte Ablehnung (3,0) unterdrückt später kein Angebot 4,0', () async {
      await seedFactorRuns(2.0);
      await service.load();
      await seedFactorRuns(3.0, firstAgo: 30, n: 20);
      await service.load();
      await recalc.decline((await recalc.pendingOffer())!);
      // 190 Tage später: Vorwert älter als 183 Tage, 2,2 wird still übernommen.
      w.clock.set(recalcNow.add(const Duration(days: 190)));
      await seedFactorRuns(2.2, firstAgo: -176);
      await service.load();
      expect(
        (await LoadSettings.factor(w.session.settings))!.value,
        closeTo(2.2, 1e-9),
      );
      // Weitere 10 Tage, jetzt 4,0 (weit weg von 2,2): Angebot.
      w.clock.set(recalcNow.add(const Duration(days: 200)));
      await seedFactorRuns(4.0, firstAgo: -183, n: 20);
      final r = await service.load();
      expect(r.factor.offered!.value, closeTo(4.0, 1e-9));
    });
  });

  group('Profilwechsel', () {
    test(
      'Nach dem Wechsel gilt der Faktor des neuen Profils, ohne Angebot',
      () async {
        // Echte Läufe: Edwards und Banister rechnen verschieden.
        for (var i = 0; i < 12; i++) {
          final id = await w.seedRun(
            DateTime.utc(2030, 2, 1 + 2 * i, 8),
            minutes: 10,
            bpm: 140 + 4 * i,
          );
          await w.calc().calculateAfterRun(id);
          await w.session.subjective.save(
            id,
            RunSubjective(rpe: const [3, 7, 5][i % 3]),
          );
          await refreshSrpe(w.session, id);
        }
        w.clock.set(recalcNow);
        await LoadSettings.writeCoefficients(
          w.session.settings,
          LoadCoefficients.male,
          at: recalcNow,
        );

        final edwards = await service.load();
        expect(edwards.profile, LoadProfile.edwards);
        expect(edwards.factor.value, isNotNull);
        expect(
          (await LoadSettings.factor(w.session.settings))!.profile,
          LoadProfile.edwards,
        );

        final offer = (await recalc.requestLoadProfile(LoadProfile.banister))!;
        // Bis zur Bestätigung gilt alles Alte.
        final waiting = await service.load();
        expect(waiting.profile, LoadProfile.edwards);
        expect(waiting.factor.value, edwards.factor.value);

        await recalc.confirm(offer);
        final banister = await service.load();
        expect(banister.profile, LoadProfile.banister);
        expect(banister.series.profile, LoadProfile.banister);
        expect(banister.factor.profile, LoadProfile.banister);
        expect(banister.factor.value, isNotNull);
        expect(banister.factor.offered, isNull);
        expect(await recalc.pendingOffer(), isNull);
        expect(
          (await LoadSettings.factor(w.session.settings))!.profile,
          LoadProfile.banister,
        );

        // Unabhängig nachgerechnet: Median TRIMP/sRPE über die Banister-Werte.
        final ratios = <double>[];
        for (final run in await w.session.runs.list()) {
          final t = (await w.session.values.read(ValueOwner.run(run.id)))
              .firstWhere((p) => p.current.key == trimpRunValueKey)
              .current;
          expect(t.method, startsWith('banister-trimp'));
          final srpe = (await w.session.subjective.read(run.id))!.srpe!.points;
          ratios.add(t.value! / srpe);
        }
        ratios.sort();
        final median = (ratios[5] + ratios[6]) / 2;
        expect(banister.factor.value, closeTo(median, 1e-9));
        expect(
          banister.factor.value,
          isNot(closeTo(edwards.factor.value!, 1e-6)),
        );
      },
    );
  });

  group('Plan und Pause im Belastungsdienst (K58, PAR-090, PAR-202)', () {
    late FakeStorage fs;

    PlanUnit planned(
      int agoDays, {
      int? runId,
      PlanUnitKind kind = PlanUnitKind.easy,
    }) => PlanUnit(
      id: 100 + agoDays,
      day: ago(agoDays),
      kind: kind,
      phase: PlanPhase.build,
      weekIndex: 0,
      minutes: 30,
      runId: runId,
      segments: const [],
    );

    void plan(Iterable<PlanUnit> units) {
      fs.data.planVersions[1] = PlanVersionRecord(
        id: 1,
        goalId: 1,
        createdAt: recalcNow,
        validFrom: ago(30),
        trigger: PlanTrigger.create,
        reason: 'start',
        version: const PlanVersion(),
        inputsJson: '{}',
        summaryJson: '{}',
      );
      for (final u in units) {
        fs.data.planUnits[u.id!] = u;
        fs.data.planUnitPlan[u.id!] = 1;
      }
    }

    // 6 Läufe vor 30 bis 25 Tagen, danach nichts; Plan erwartet 20 Tage lang
    // täglich einen Lauf.
    Future<TrainingLoadService> world() async {
      fs = FakeStorage();
      w = await RecalcWorld.create(storage: fs);
      for (var a = 30; a >= 25; a--) {
        await addRun(
          ago(a).add(const Duration(hours: 9)),
          trimp: trimpValue(80),
          rpe: 5,
        );
      }
      plan([for (var a = 20; a >= 1; a--) planned(a)]);
      return TrainingLoadService(
        session: w.session,
        clock: w.clock,
        calculation: w.calc(),
        recalculation: w.recalc(),
      );
    }

    bool missing(TrainingLoadReport r) => r
        .series
        .days
        .last
        .ctlProvisionalReasons
        .contains(LoadProvisionalReason.missingUnits);

    test('erwartete Einheiten aus dem Plan: ausgefallene Läufe machen CTL '
        'vorläufig (missingUnits)', () async {
      final svc = await world();
      expect(missing(await svc.load()), isTrue);
    });

    test('ohne Plan gelten alle erfassten Einheiten als erwartet', () async {
      final svc = await world();
      fs.data.planUnits.clear();
      expect(missing(await svc.load()), isFalse);
    });

    test(
      'Ruhetage im Plan und der heutige offene Tag sind nicht erwartet',
      () async {
        final svc = await world();
        fs.data.planUnits.clear();
        plan([
          for (var a = 20; a >= 1; a--) planned(a, kind: PlanUnitKind.rest),
          planned(0),
        ]);
        expect(missing(await svc.load()), isFalse);
      },
    );

    test('heute geplant und noch ohne Lauf: heute ist nicht vorbei, die '
        'Einheit fehlt nicht', () async {
      fs = FakeStorage();
      w = await RecalcWorld.create(storage: fs);
      for (var a = 5; a >= 1; a--) {
        await addRun(
          ago(a).add(const Duration(hours: 9)),
          trimp: trimpValue(80),
        );
      }
      // Heute ein unbewerteter Lauf (zählt als Einheit, Verlauf endet heute).
      await addRun(today.add(const Duration(hours: 8)));
      plan([for (var a = 5; a >= 0; a--) planned(a)]);
      final svc = TrainingLoadService(
        session: w.session,
        clock: w.clock,
        calculation: w.calc(),
        recalculation: w.recalc(),
      );
      final r = await svc.load();
      expect(r.series.days.last.day, today);
      expect(missing(r), isFalse);
    });

    test('bestätigte Pause (ja): Tage ohne Einheit sind bekannt leer, nichts '
        'fehlt', () async {
      final svc = await world();
      await WarningState(w.session.settings)
          .setPauseAnswer(PauseAnswer(paused: true, on: ago(1)), at: recalcNow);
      final r = await svc.load();
      expect(missing(r), isFalse);
      expect(r.series.days.last.load, 0);
    });

    test('Antwort nein ändert nichts', () async {
      final svc = await world();
      await WarningState(
        w.session.settings,
      ).setPauseAnswer(PauseAnswer(paused: false, on: ago(1)), at: recalcNow);
      expect(missing(await svc.load()), isTrue);
    });
  });
}
