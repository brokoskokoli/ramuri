import 'package:core/core.dart';
import 'package:test/test.dart';

import 'recalc_support.dart';

/// Wechsel des Belastungsprofils über die Neuberechnung (WP19, FR-0197,
/// OQ-0053): erst nach Bestätigung aktiv, Ablehnung lässt die Wahl verfallen,
/// kein stiller Wechsel der Skala.
void main() {
  late RecalcWorld w;
  late List<int> ids;

  setUp(() async {
    w = await RecalcWorld.create();
    ids = await w.seedFourRunsCalculated();
  });

  Future<void> setCoefficients(LoadCoefficients? c) =>
      LoadSettings.writeCoefficients(w.session.settings, c, at: w.clock.now());

  Future<Map<int, ComputedValue>> trimps({bool original = false}) async => {
    for (final id in ids)
      id: [
        for (final p in await w.session.values.read(ValueOwner.run(id)))
          if (p.original.key == trimpRunValueKey)
            original ? p.original : p.current,
      ].single,
  };

  Future<LoadProfile> active() =>
      LoadSettings.activeProfile(w.session.settings);
  Future<LoadProfile?> chosen() =>
      LoadSettings.pendingProfile(w.session.settings);

  group('Einstellungen', () {
    test('Start: Edwards, keine Angabe, keine Zusage; Rundreise', () async {
      final s = w.session.settings;
      expect(await LoadSettings.activeProfile(s), LoadProfile.edwards);
      expect(await LoadSettings.coefficients(s), isNull);
      expect(await LoadSettings.allRecorded(s), isFalse);
      await setCoefficients(LoadCoefficients.female);
      await LoadSettings.saveAllRecorded(s, true, at: w.clock.now());
      expect(await LoadSettings.coefficients(s), LoadCoefficients.female);
      expect(await LoadSettings.allRecorded(s), isTrue);
      await setCoefficients(null);
      expect(await LoadSettings.coefficients(s), isNull);
      // Unbekannte Werte fallen auf den Start zurück.
      await s.set(SettingKeys.loadProfile, 'zzz', at: w.clock.now());
      await s.set(SettingKeys.loadCoefficients, 'x', at: w.clock.now());
      expect(await LoadSettings.activeProfile(s), LoadProfile.edwards);
      expect(await LoadSettings.coefficients(s), isNull);
      expect(SettingKeys.loadProfile, startsWith('load.'));
      expect(SettingKeys.loadProfilePending, startsWith('load.'));
    });
  });

  group('Wechsel Edwards -> Banister', () {
    test('Banister ohne Koeffizienten oder Ruhepuls: abgewiesen, nichts '
        'geändert', () async {
      final s = w.recalc();
      final before = await w.dump();
      await expectLater(
        s.requestLoadProfile(LoadProfile.banister),
        throwsA(
          isA<LoadProfileNotApplicableException>().having(
            (e) => e.issues,
            'issues',
            [LoadProfileIssue.missingCoefficients],
          ),
        ),
      );
      expect(await s.pendingOffer(), isNull);
      expect(await chosen(), isNull);
      expect(await w.dump(), before);
    });

    test('Wahl ändert nichts bis zur Bestätigung; neue Läufe rechnen noch '
        'Edwards', () async {
      await setCoefficients(LoadCoefficients.male);
      final s = w.recalc();
      final before = await w.dump();
      final offer = await s.requestLoadProfile(LoadProfile.banister);
      expect(offer!.causes, {RecalculationCause.loadProfile});
      expect(offer.loadProfile, LoadProfile.banister);
      expect(offer.runIds, unorderedEquals(ids));
      expect(await active(), LoadProfile.edwards);
      expect(await w.dump(), before);
      // Ein Lauf vor der Bestätigung: noch Edwards.
      final id = await w.seedRun(DateTime.utc(2030, 2, 27, 8));
      await w.calc().calculateAfterRun(id);
      final v = (await w.session.values.read(ValueOwner.run(id)))
          .firstWhere((p) => p.original.key == trimpRunValueKey);
      expect(v.current.method, EdwardsTrimp.methodId);
    });

    test(
      'Bestätigt: alle Läufe Banister-TRIMP, Profil aktiv, Wahl erledigt',
      () async {
        await setCoefficients(LoadCoefficients.male);
        final s = w.recalc();
        final offer = await s.requestLoadProfile(LoadProfile.banister);
        final edwards = await trimps();
        w.clock.set(DateTime.utc(2030, 3, 2, 9));
        final result = await s.confirm(offer!);
        expect(result.offerCleared, isTrue);
        expect(await active(), LoadProfile.banister);
        expect(await chosen(), isNull);
        expect(await s.pendingOffer(), isNull);
        final now = await trimps();
        final orig = await trimps(original: true);
        for (final id in ids) {
          expect(now[id]!.method, BanisterTrimp.methodIdMale);
          expect(now[id]!.value, isNotNull);
          expect(now[id]!.value, isNot(edwards[id]!.value));
          expect(now[id]!.computedAt, w.clock.now());
          // original bleibt Edwards.
          expect(orig[id]!.method, EdwardsTrimp.methodId);
        }
        // Neue Läufe rechnen jetzt im neuen Profil.
        final id = await w.seedRun(DateTime.utc(2030, 3, 3, 8));
        await w.calc().calculateAfterRun(id);
        final v = (await w.session.values.read(ValueOwner.run(id)))
            .firstWhere((p) => p.original.key == trimpRunValueKey);
        expect(v.original.method, BanisterTrimp.methodIdMale);
      },
    );

    test('Abgelehnt: Edwards bleibt, Wahl verfällt, nichts geändert', () async {
      await setCoefficients(LoadCoefficients.male);
      final s = w.recalc();
      final offer = await s.requestLoadProfile(LoadProfile.banister);
      final before = await w.dump();
      await s.decline(offer!);
      expect(await active(), LoadProfile.edwards);
      expect(await chosen(), isNull);
      expect(await s.pendingOffer(), isNull);
      expect(await w.dump(), before);
      await expectLater(s.confirm(offer), throwsStateError);
      expect(await active(), LoadProfile.edwards);
    });

    test('Neustart mit offenem Angebot: Wahl und Angebot bleiben, '
        'Bestätigen wirkt', () async {
      await setCoefficients(LoadCoefficients.female);
      await w.recalc().requestLoadProfile(LoadProfile.banister);
      final restarted = w.recalc();
      final offer = await restarted.pendingOffer();
      expect(offer!.causes, {RecalculationCause.loadProfile});
      expect(offer.loadProfile, LoadProfile.banister);
      expect(await active(), LoadProfile.edwards);
      await restarted.confirm(offer);
      expect(await active(), LoadProfile.banister);
      expect((await trimps()).values.map((v) => v.method).toSet(), {
        BanisterTrimp.methodIdFemale,
      });
    });

    test('Bestätigen scheitert, wenn Banister inzwischen nicht anwendbar '
        'ist; nichts geändert, Ablehnen möglich', () async {
      await setCoefficients(LoadCoefficients.male);
      final s = w.recalc();
      final offer = await s.requestLoadProfile(LoadProfile.banister);
      await setCoefficients(null);
      final before = await w.dump();
      await expectLater(
        s.confirm(offer!),
        throwsA(isA<LoadProfileNotApplicableException>()),
      );
      expect(await w.dump(), before);
      expect(await active(), LoadProfile.edwards);
      await s.decline(offer);
      expect(await chosen(), isNull);
    });

    test(
      'erneute Wahl des aktiven Profils lässt die offene Wahl verfallen',
      () async {
        await setCoefficients(LoadCoefficients.male);
        final s = w.recalc();
        await s.requestLoadProfile(LoadProfile.banister);
        expect(await s.requestLoadProfile(LoadProfile.edwards), isNull);
        expect(await chosen(), isNull);
        expect(await s.pendingOffer(), isNull);
      },
    );

    test('ohne Läufe mit Werten gilt die Wahl sofort', () async {
      final fresh = await RecalcWorld.create();
      await LoadSettings.writeCoefficients(
        fresh.session.settings,
        LoadCoefficients.male,
        at: fresh.clock.now(),
      );
      final offer = await fresh.recalc().requestLoadProfile(
        LoadProfile.banister,
      );
      expect(offer, isNull);
      expect(
        await LoadSettings.activeProfile(fresh.session.settings),
        LoadProfile.banister,
      );
      expect(await LoadSettings.pendingProfile(fresh.session.settings), isNull);
    });

    test('Wahl zusammen mit Änderung der Herzfrequenzbasis: eine Bestätigung '
        'rechnet beides', () async {
      await setCoefficients(LoadCoefficients.male);
      final s = w.recalc();
      await s.requestLoadProfile(LoadProfile.banister);
      await w.session.profile.save(profile180);
      final offer = await s.profileChanged(
        before: profile190,
        after: profile180,
      );
      expect(offer!.causes, {
        RecalculationCause.loadProfile,
        RecalculationCause.heartRateBasis,
      });
      await s.confirm(offer);
      expect(await active(), LoadProfile.banister);
      expect(
        (await trimps()).values.every(
          (v) =>
              v.method == BanisterTrimp.methodIdMale &&
              v.heartRateBasis!.maxBpm == 180,
        ),
        isTrue,
      );
    });
  });

  group('Banister aktiv, Angaben fallen weg', () {
    setUp(() async {
      await setCoefficients(LoadCoefficients.male);
      final s = w.recalc();
      await s.confirm((await s.requestLoadProfile(LoadProfile.banister))!);
      expect(await active(), LoadProfile.banister);
    });

    test('Ruhepuls fällt weg: Angebot zurück auf Edwards, kein stiller '
        'Wechsel; gespeicherte Werte bleiben', () async {
      const noRest = ProfileRecord(maxHeartRateBpm: 190);
      await w.session.profile.save(noRest);
      final s = w.recalc();
      final stored = await trimps();
      final offer = await s.profileChanged(before: profile190, after: noRest);
      expect(offer!.causes, contains(RecalculationCause.loadProfile));
      expect(offer.loadProfile, LoadProfile.edwards);
      expect(await active(), LoadProfile.banister);
      expect(
        (await trimps()).values.map((v) => v.value),
        stored.values.map((v) => v.value),
      );
      // Neuer Lauf: TRIMP nicht verfügbar, nicht mit Edwards gerechnet.
      final id = await w.seedRun(DateTime.utc(2030, 3, 3, 8));
      await w.calc().calculateAfterRun(id);
      final v = (await w.session.values.read(ValueOwner.run(id)))
          .firstWhere((p) => p.original.key == trimpRunValueKey)
          .current;
      expect(v.value, isNull);
      expect(v.unavailableReason, UnavailableReason.missingRestingHeartRate);
      expect(v.method, isNot(EdwardsTrimp.methodId));
    });

    test('Angabe entfernen, bestätigt: Rückweg auf Edwards für alle Läufe, '
        'Angabe weg', () async {
      final s = w.recalc();
      final offer = await s.requestLoadCoefficients(null);
      expect(offer!.causes, {
        RecalculationCause.loadCoefficients,
        RecalculationCause.loadProfile,
      });
      expect(offer.loadProfile, LoadProfile.edwards);
      // Bis zur Bestätigung gilt die alte Angabe.
      expect(await LoadSettings.coefficients(w.session.settings), isNotNull);
      expect(await active(), LoadProfile.banister);
      await s.confirm(offer);
      expect(await active(), LoadProfile.edwards);
      expect(await LoadSettings.coefficients(w.session.settings), isNull);
      expect(
        (await trimps()).values.every((v) => v.method == EdwardsTrimp.methodId),
        isTrue,
      );
      expect(await s.pendingOffer(), isNull);
      expect(
        await LoadSettings.pendingCoefficients(w.session.settings),
        isNull,
      );
    });

    test('Angabe entfernen, abgelehnt: alte Angabe und Banister bleiben, '
        'nichts geändert, keine Mischung', () async {
      final s = w.recalc();
      final offer = await s.requestLoadCoefficients(null);
      final before = await w.dump();
      await s.decline(offer!);
      expect(await active(), LoadProfile.banister);
      expect(await chosen(), isNull);
      expect(
        await LoadSettings.coefficients(w.session.settings),
        LoadCoefficients.male,
      );
      expect(
        await LoadSettings.pendingCoefficients(w.session.settings),
        isNull,
      );
      expect(await w.dump(), before);
      final id = await w.seedRun(DateTime.utc(2030, 3, 3, 8));
      await w.calc().calculateAfterRun(id);
      final v = (await w.session.values.read(ValueOwner.run(id)))
          .firstWhere((p) => p.original.key == trimpRunValueKey)
          .current;
      expect(v.method, BanisterTrimp.methodIdMale);
      expect(v.value, isNotNull);
    });

    test('andere Koeffizienten: gelten erst nach Bestätigung, neue Läufe '
        'rechnen bis dahin mit der alten Angabe', () async {
      final s = w.recalc();
      final offer = await s.requestLoadCoefficients(LoadCoefficients.female);
      expect(offer!.causes, {RecalculationCause.loadCoefficients});
      expect(offer.runIds, unorderedEquals(ids));
      expect(
        await LoadSettings.coefficients(w.session.settings),
        LoadCoefficients.male,
      );
      final id = await w.seedRun(DateTime.utc(2030, 3, 3, 8));
      await w.calc().calculateAfterRun(id);
      final v = (await w.session.values.read(ValueOwner.run(id)))
          .firstWhere((p) => p.original.key == trimpRunValueKey)
          .current;
      expect(v.method, BanisterTrimp.methodIdMale);
      // Der Neustart behält das Angebot, Bestätigen rechnet alle um.
      final restarted = w.recalc();
      final pending = await restarted.pendingOffer();
      expect(pending!.causes, {RecalculationCause.loadCoefficients});
      await restarted.confirm(pending);
      expect(
        await LoadSettings.coefficients(w.session.settings),
        LoadCoefficients.female,
      );
      expect(await active(), LoadProfile.banister);
      var seen = 0;
      for (final r in await w.session.runs.list()) {
        for (final p in await w.session.values.read(ValueOwner.run(r.id))) {
          if (p.original.key != trimpRunValueKey) continue;
          seen++;
          expect(p.current.method, BanisterTrimp.methodIdFemale);
        }
      }
      expect(seen, ids.length + 1);
      expect(await restarted.pendingOffer(), isNull);
      expect(
        await LoadSettings.pendingCoefficients(w.session.settings),
        isNull,
      );
    });

    test('andere Koeffizienten abgelehnt: alte Angabe bleibt, alle Läufe '
        'weiter männlich', () async {
      final s = w.recalc();
      final offer = await s.requestLoadCoefficients(LoadCoefficients.female);
      await s.decline(offer!);
      expect(
        await LoadSettings.coefficients(w.session.settings),
        LoadCoefficients.male,
      );
      expect(await s.pendingOffer(), isNull);
      expect((await trimps()).values.map((v) => v.method).toSet(), {
        BanisterTrimp.methodIdMale,
      });
      // Danach kein Versionsangebot: die Werte passen zur Angabe.
      expect(await s.checkVersions(), isNull);
    });

    test('Rückkehr zur alten Angabe lässt die offene Änderung verfallen; '
        'beim Entfernen auch den Rückweg', () async {
      final s = w.recalc();
      await s.requestLoadCoefficients(LoadCoefficients.female);
      expect(await s.requestLoadCoefficients(LoadCoefficients.male), isNull);
      expect(await s.pendingOffer(), isNull);
      await s.requestLoadCoefficients(null);
      expect(await s.requestLoadCoefficients(LoadCoefficients.male), isNull);
      expect(await s.pendingOffer(), isNull);
      expect(await chosen(), isNull);
      expect(await active(), LoadProfile.banister);
    });

    test('Banister mit neuer Angabe nicht anwendbar: abgewiesen, nichts '
        'geändert', () async {
      // Ruhepuls weg: Banister ist ohnehin nicht mehr anwendbar.
      await w.session.profile.save(const ProfileRecord(maxHeartRateBpm: 190));
      final s = w.recalc();
      final before = await w.dump();
      await expectLater(
        s.requestLoadCoefficients(LoadCoefficients.female),
        throwsA(isA<LoadProfileNotApplicableException>()),
      );
      expect(await w.dump(), before);
    });

    test(
      'ohne aktives Banister gilt die Angabe sofort, ohne Angebot',
      () async {
        final fresh = await RecalcWorld.create();
        await fresh.seedFourRunsCalculated();
        final s = fresh.recalc();
        expect(
          await s.requestLoadCoefficients(LoadCoefficients.female),
          isNull,
        );
        expect(
          await LoadSettings.coefficients(fresh.session.settings),
          LoadCoefficients.female,
        );
        expect(await s.pendingOffer(), isNull);
      },
    );

    test('unveränderte Angaben: kein Angebot', () async {
      expect(await w.recalc().loadBasisChanged(), isNull);
    });
  });

  group('Läufe mit TRIMP, aber ohne Laufwert (VO2max)', () {
    /// Ein Lauf, der nur einen TRIMP trägt (etwa älterer Bestand): der TRIMP
    /// eines berechneten Laufs, ohne VO2max-Wert.
    Future<int> trimpOnlyRun() async {
      final id = await w.seedRun(DateTime.utc(2030, 2, 26, 8));
      final trimp = (await w.session.values.read(ValueOwner.run(ids.first)))
          .firstWhere((p) => p.original.key == trimpRunValueKey)
          .original;
      await w.session.values.writeAll(
        create: {
          ValueOwner.run(id): [trimp],
        },
        swap: const {},
      );
      return id;
    }

    Future<List<ValuePair>> pairs(int id) =>
        w.session.values.read(ValueOwner.run(id));

    /// Invariante: nach Bestätigung trägt jeder TRIMP die Methode des aktiven
    /// Profils (eine Skala für ATL/CTL).
    Future<void> expectOneScale(String method) async {
      var seen = 0;
      for (final r in await w.session.runs.list()) {
        for (final p in await pairs(r.id)) {
          if (p.original.key != trimpRunValueKey) continue;
          seen++;
          expect(p.current.method, method, reason: 'Lauf ${r.id}');
        }
      }
      expect(seen, ids.length + 1);
    }

    test('Wechsel nach Banister und zurück: der Lauf wechselt mit', () async {
      final only = await trimpOnlyRun();
      expect((await pairs(only)).map((p) => p.original.key), [
        trimpRunValueKey,
      ]);
      await setCoefficients(LoadCoefficients.male);
      final s = w.recalc();
      final offer = await s.requestLoadProfile(LoadProfile.banister);
      expect(offer!.runIds, contains(only));
      await s.confirm(offer);
      await expectOneScale(BanisterTrimp.methodIdMale);
      // Kein Laufwert nebenbei entstanden.
      expect((await pairs(only)).map((p) => p.original.key), [
        trimpRunValueKey,
      ]);

      final back = await s.requestLoadProfile(LoadProfile.edwards);
      expect(back!.runIds, contains(only));
      await s.confirm(back);
      await expectOneScale(EdwardsTrimp.methodId);
    });

    test('Rückweg bei wegfallenden Angaben: der Lauf wechselt mit', () async {
      await setCoefficients(LoadCoefficients.male);
      final s = w.recalc();
      await s.confirm((await s.requestLoadProfile(LoadProfile.banister))!);
      final only = await trimpOnlyRun();
      final offer = await s.requestLoadCoefficients(null);
      expect(offer!.runIds, contains(only));
      await s.confirm(offer);
      await expectOneScale(EdwardsTrimp.methodId);
    });
  });
}
