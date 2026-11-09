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
      LoadSettings.saveCoefficients(w.session.settings, c, at: w.clock.now());

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
      await LoadSettings.saveCoefficients(
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

    test('Zurück bestätigt: Edwards für alle Läufe', () async {
      await setCoefficients(null);
      final s = w.recalc();
      final offer = await s.loadBasisChanged();
      expect(offer!.loadProfile, LoadProfile.edwards);
      await s.confirm(offer);
      expect(await active(), LoadProfile.edwards);
      expect(
        (await trimps()).values.every((v) => v.method == EdwardsTrimp.methodId),
        isTrue,
      );
    });

    test('Zurück abgelehnt: Banister bleibt gewählt, Wahl verfällt', () async {
      await setCoefficients(null);
      final s = w.recalc();
      final offer = await s.loadBasisChanged();
      final before = await w.dump();
      await s.decline(offer!);
      expect(await active(), LoadProfile.banister);
      expect(await chosen(), isNull);
      expect(await w.dump(), before);
      final id = await w.seedRun(DateTime.utc(2030, 3, 3, 8));
      await w.calc().calculateAfterRun(id);
      final v = (await w.session.values.read(ValueOwner.run(id)))
          .firstWhere((p) => p.original.key == trimpRunValueKey)
          .current;
      expect(v.unavailableReason, UnavailableReason.missingLoadCoefficients);
    });

    test(
      'andere Koeffizienten bei anwendbarem Banister: Versionsangebot',
      () async {
        await setCoefficients(LoadCoefficients.female);
        final s = w.recalc();
        final offer = await s.loadBasisChanged();
        expect(offer!.causes, {RecalculationCause.algorithmVersion});
        await s.confirm(offer);
        expect((await trimps()).values.map((v) => v.method).toSet(), {
          BanisterTrimp.methodIdFemale,
        });
        expect(await active(), LoadProfile.banister);
      },
    );

    test('unveränderte Angaben: kein Angebot', () async {
      expect(await w.recalc().loadBasisChanged(), isNull);
    });
  });
}
