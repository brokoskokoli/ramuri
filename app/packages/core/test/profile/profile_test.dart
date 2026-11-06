import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:test/test.dart';

// Synthetische Werte. Stichtag 2026: Geburtsjahr 1986 ergibt Alter 40.
const year = 2026;
const birth40 = 1986;

ProfileValidation check(ProfileRecord p) =>
    validateProfileInput(p, currentYear: year);

Set<ProfileIssueCode> codes(ProfileValidation v) =>
    v.issues.map((i) => i.code).toSet();

final key = Uint8List.fromList(List.filled(32, 7));

Future<ProfileService> service() async {
  final session = await FakeStorage().open(key);
  return ProfileService(session.profile, FakeClock(DateTime.utc(year, 6, 1)));
}

ResolvedHeartRate resolve(ProfileRecord p, {int? external}) =>
    resolveHeartRate(p, currentYear: year, externalRestingBpm: external);

void main() {
  group('FR-0002 leeres Profil, positive Zahlen (OQ-0065)', () {
    test('leeres Profil ist gültig, ohne Meldung', () {
      final v = check(const ProfileRecord());
      expect(v.canSave, isTrue);
      expect(v.issues, isEmpty);
    });

    test(
      'Geburtsjahr, Gewicht, Größe: 0 und negativ abgelehnt, knapp > 0 ok',
      () {
        for (final p in [
          const ProfileRecord(birthYear: 0),
          const ProfileRecord(birthYear: -1),
          const ProfileRecord(bodyWeightKg: 0),
          const ProfileRecord(bodyWeightKg: -0.1),
          const ProfileRecord(bodyWeightKg: double.nan),
          const ProfileRecord(bodyHeightMeters: 0),
          const ProfileRecord(bodyHeightMeters: double.infinity),
        ]) {
          final v = check(p);
          expect(v.canSave, isFalse, reason: '$p');
          expect(codes(v), {ProfileIssueCode.notPositive});
        }
        expect(
          check(
            const ProfileRecord(
              birthYear: 1,
              bodyWeightKg: 0.1,
              bodyHeightMeters: 0.01,
            ),
          ).issues,
          isEmpty,
        );
      },
    );

    test('Weitere Felder (Trainingsplan) werden nicht geprüft', () {
      expect(
        check(
          const ProfileRecord(
            weeklyRunMinutes: 120,
            trainingDaysMask: 5,
            usualTrainingMinutes: 45,
          ),
        ).issues,
        isEmpty,
      );
    });
  });

  group('PAR-016 HFmax', () {
    bool rejected(int max) =>
        !check(ProfileRecord(maxHeartRateBpm: max)).canSave;

    test('99 und 231 abgelehnt, 100 und 230 gespeichert', () {
      expect(rejected(99), isTrue);
      expect(rejected(231), isTrue);
      expect(rejected(100), isFalse);
      expect(rejected(230), isFalse);
      expect(codes(check(const ProfileRecord(maxHeartRateBpm: 99))), {
        ProfileIssueCode.maxHrOutOfRange,
      });
    });

    Set<ProfileIssueCode> hintFor(int max) =>
        codes(check(ProfileRecord(birthYear: birth40, maxHeartRateBpm: max)));

    test('Alter 40, Näherung 180: Hinweis ab 26 bpm Abstand, nicht bei 25', () {
      expect(hintFor(205), isEmpty); // +25
      expect(hintFor(206), {ProfileIssueCode.maxHrDeviatesFromEstimate});
      expect(hintFor(155), isEmpty); // -25
      expect(hintFor(154), {ProfileIssueCode.maxHrDeviatesFromEstimate});
      expect(
        check(const ProfileRecord(birthYear: birth40, maxHeartRateBpm: 206))
            .canSave,
        isTrue,
      );
    });

    test('Nachkommastelle der Näherung zählt: Alter 41, Näherung 179,3', () {
      // 204,3 wäre genau 25 darüber: 204 liegt innen, 205 außen.
      Set<ProfileIssueCode> h(int m) =>
          codes(check(ProfileRecord(birthYear: 1985, maxHeartRateBpm: m)));
      expect(h(204), isEmpty);
      expect(h(205), {ProfileIssueCode.maxHrDeviatesFromEstimate});
      expect(h(155), isEmpty); // 24,3 darunter
      expect(h(154), {ProfileIssueCode.maxHrDeviatesFromEstimate}); // 25,3
    });

    test('Ohne bekanntes Alter kein Abweichungshinweis', () {
      expect(check(const ProfileRecord(maxHeartRateBpm: 230)).issues, isEmpty);
      // Geburtsjahr in der Zukunft ergibt kein Alter.
      expect(
        check(const ProfileRecord(birthYear: 2027, maxHeartRateBpm: 230))
            .issues,
        isEmpty,
      );
    });
  });

  group('PAR-017 Ruhepuls', () {
    Set<ProfileIssueCode> c(int r) =>
        codes(check(ProfileRecord(restingHeartRateBpm: r)));
    bool ok(int r) => check(ProfileRecord(restingHeartRateBpm: r)).canSave;

    test('Ablehnen unter 30 und über 120, 30 und 120 gespeichert', () {
      expect(ok(29), isFalse);
      expect(ok(121), isFalse);
      expect(ok(30), isTrue);
      expect(ok(120), isTrue);
      expect(c(29), {ProfileIssueCode.restHrOutOfRange});
    });

    test('Hinweis bei 30 bis 39 und 111 bis 120, keiner bei 40 bis 110', () {
      expect(c(39), {ProfileIssueCode.restHrUnusual});
      expect(c(30), {ProfileIssueCode.restHrUnusual});
      expect(c(40), isEmpty);
      expect(c(110), isEmpty);
      expect(c(111), {ProfileIssueCode.restHrUnusual});
      expect(c(120), {ProfileIssueCode.restHrUnusual});
    });
  });

  group('PAR-018 Konflikt aus Eingaben im Profil', () {
    test('HFmax = Ruhepuls und HFmax < Ruhepuls abgelehnt, +1 gespeichert', () {
      final eq = check(
        const ProfileRecord(maxHeartRateBpm: 100, restingHeartRateBpm: 100),
      );
      expect(eq.canSave, isFalse);
      expect(codes(eq), contains(ProfileIssueCode.maxNotAboveResting));
      expect(
        check(
          const ProfileRecord(maxHeartRateBpm: 100, restingHeartRateBpm: 110),
        ).canSave,
        isFalse,
      );
      expect(
        check(
          const ProfileRecord(maxHeartRateBpm: 101, restingHeartRateBpm: 100),
        ).canSave,
        isTrue,
      );
    });

    test('Konflikt wird nicht gespeichert, altes Profil bleibt', () async {
      final s = await service();
      const old = ProfileRecord(maxHeartRateBpm: 190, restingHeartRateBpm: 60);
      expect((await s.save(old)).saved, isTrue);
      final r = await s.save(
        const ProfileRecord(maxHeartRateBpm: 190, restingHeartRateBpm: 120),
      );
      expect(r.saved, isTrue); // 190 > 120, kein Konflikt (PAR-019 greift)
      final bad = await s.save(
        const ProfileRecord(maxHeartRateBpm: 110, restingHeartRateBpm: 120),
      );
      expect(bad.saved, isFalse);
      final stored = await s.load();
      expect(stored.maxHeartRateBpm, 190);
      expect(stored.restingHeartRateBpm, 120);
    });
  });

  group('Speichern und Laden', () {
    test('Rundreise; Hinweis speichert trotzdem', () async {
      final s = await service();
      const p = ProfileRecord(
        birthYear: birth40,
        bodyWeightKg: 70.5,
        maxHeartRateBpm: 215, // 35 über der Näherung: Hinweis
        restingHeartRateBpm: 38, // Hinweis
      );
      final r = await s.save(p);
      expect(r.saved, isTrue);
      expect(r.validation.hints.length, 2);
      final back = await s.load();
      expect(back.maxHeartRateBpm, 215);
      expect(back.bodyWeightKg, 70.5);
    });

    test('Leeres Profil laden und speichern', () async {
      final s = await service();
      expect((await s.load()).maxHeartRateBpm, isNull);
      expect((await s.save(const ProfileRecord())).saved, isTrue);
    });
  });

  group('FR-0003/FR-0004 HFmax-Auflösung', () {
    test('Alter 40 ergibt 180 bpm, gekennzeichnet als Schätzung', () {
      final r = resolve(const ProfileRecord(birthYear: birth40));
      expect(r.basis.maxBpm, 180);
      expect(r.basis.maxIsEstimated, isTrue);
      expect(r.maxSource, MaxHeartRateSource.estimated);
    });

    test('Messwert und Alter: der Messwert gilt, keine Schätzung', () {
      final r = resolve(
        const ProfileRecord(birthYear: birth40, maxHeartRateBpm: 170),
      );
      expect(r.basis.maxBpm, 170);
      expect(r.basis.maxIsEstimated, isFalse);
      expect(r.maxSource, MaxHeartRateSource.entered);
    });

    test('Rundung der Näherung: Alter 41 gibt 179, Alter 5 gibt 205', () {
      expect(approximateMaxHeartRate(41), 179); // 179,3
      expect(approximateMaxHeartRate(42), 179); // 178,6 -> 179
      expect(approximateMaxHeartRate(5), 205); // 204,5 halbe nach oben
      expect(approximateMaxHeartRate(null), isNull);
      expect(approximateMaxHeartRate(0), isNull);
      expect(approximateMaxHeartRate(298), isNull); // 208 - 208,6 < 0
    });

    test('Ohne Alter und HFmax: Bitte um Eingabe, abhängige Werte fehlen', () {
      final r = resolve(const ProfileRecord(restingHeartRateBpm: 60));
      expect(r.maxSource, MaxHeartRateSource.missing);
      expect(r.askForMaxInput, isTrue);
      expect(r.basis.maxBpm, isNull);
      expect(r.reserveBasedReason, UnavailableReason.missingMaxHeartRate);
      expect(r.trimpReason, UnavailableReason.missingMaxHeartRate);
    });

    test(
      'Alter 0 (Geburtsjahr = Stichtagsjahr) oder Zukunft: keine Näherung',
      () {
        for (final y in [year, year + 1]) {
          final r = resolve(ProfileRecord(birthYear: y));
          expect(r.maxSource, MaxHeartRateSource.missing, reason: '$y');
        }
        expect(
          resolve(const ProfileRecord(birthYear: year - 1)).basis.maxBpm,
          207,
        );
      },
    );

    test('Leeres Profil: Bitte um Eingabe, kein Absturz', () {
      final r = resolve(const ProfileRecord());
      expect(r.askForMaxInput, isTrue);
      expect(r.askForInputOrCheck, isTrue);
    });

    test('Voll bestückt: nichts nicht verfügbar', () {
      final r = resolve(
        const ProfileRecord(maxHeartRateBpm: 190, restingHeartRateBpm: 60),
      );
      expect(r.reserveBasedReason, isNull);
      expect(r.trimpReason, isNull);
      expect(r.askForInputOrCheck, isFalse);
      expect(r.conflictAcrossSources, isFalse);
    });

    test('Fehlender Ruhepuls: r nicht verfügbar, TRIMP läuft', () {
      final r = resolve(const ProfileRecord(maxHeartRateBpm: 190));
      expect(r.reserveBasedReason, UnavailableReason.missingRestingHeartRate);
      expect(r.trimpReason, isNull);
    });
  });

  group('PAR-018 aus verschiedenen Quellen', () {
    test('Näherung <= Ruhepuls: speichern ok, r und TRIMP nicht verfügbar', () async {
      // Alter 80: Näherung 152. Ruhepuls 120 liegt darunter -> kein Konflikt.
      // Alter 100: Näherung 138, Ruhepuls 120 -> auch kein Konflikt. Konflikt
      // braucht Näherung <= Ruhepuls, also nahe 120: Alter 126 -> 120 (119,8).
      const p = ProfileRecord(birthYear: 1900, restingHeartRateBpm: 120);
      final s = await service();
      expect((await s.save(p)).saved, isTrue);
      final r = await s.resolve();
      expect(r.basis.maxBpm, 120);
      expect(r.conflictAcrossSources, isTrue);
      expect(r.reserveBasedReason, UnavailableReason.maxNotAboveResting);
      expect(r.trimpReason, UnavailableReason.maxNotAboveResting);
      expect(r.askForInputOrCheck, isTrue);
    });

    test('Eingegebene HFmax <= Ruhepuls aus fremder Quelle: Konflikt', () {
      final r = resolve(
        const ProfileRecord(maxHeartRateBpm: 150),
        external: 150,
      );
      expect(r.conflictAcrossSources, isTrue);
      expect(r.reserveBasedReason, UnavailableReason.maxNotAboveResting);
      expect(r.trimpReason, UnavailableReason.maxNotAboveResting);
    });

    test('Ruhepuls im Profil hat Vorrang vor fremder Quelle', () {
      final r = resolve(
        const ProfileRecord(maxHeartRateBpm: 190, restingHeartRateBpm: 60),
        external: 200,
      );
      expect(r.basis.restingBpm, 60);
      expect(r.reserveBasedReason, isNull);
    });
  });

  group('PAR-019 Mindestreserve', () {
    ResolvedHeartRate res(int max, int rest) =>
        resolve(ProfileRecord(maxHeartRateBpm: max, restingHeartRateBpm: rest));

    test('Reserve 49: gespeichert, r nicht verfügbar, TRIMP läuft', () async {
      const p = ProfileRecord(maxHeartRateBpm: 149, restingHeartRateBpm: 100);
      final s = await service();
      expect((await s.save(p)).saved, isTrue);
      final r = await s.resolve();
      expect(r.reserveBasedReason, UnavailableReason.reserveTooSmall);
      expect(r.trimpReason, isNull);
      expect(r.askForInputOrCheck, isTrue);
      expect(r.conflictAcrossSources, isFalse);
    });

    test('Reserve 50 ist noch verfügbar, Reserve 1 nicht', () {
      expect(res(150, 100).reserveBasedReason, isNull);
      expect(
        res(101, 100).reserveBasedReason,
        UnavailableReason.reserveTooSmall,
      );
    });
  });
}
