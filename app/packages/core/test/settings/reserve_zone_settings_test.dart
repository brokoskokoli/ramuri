import 'package:core/core.dart';
import 'package:test/test.dart';

import 'package:core/fakes/fake_storage_settings.dart';

import '../fitness/fitness_support.dart';

const zones = ReserveZones(reserve: HeartRateReserve());
// HFR 100 bpm: bpm 155 ist r = 0,65.
const basis = HeartRateBasis(maxBpm: 190, restingBpm: 90);

int zoneAt(FitnessParameters p, int bpm) {
  final r =
      zones.zoneFor(basis, bpm, p) as FitnessAvailable<ReserveZonePlacement>;
  return (r.value as InReserveZone).zone;
}

void main() {
  final at = DateTime.utc(2026, 6, 1);
  late FakeSettingsStore store;
  setUp(() => store = FakeSettingsStore(FakeStorageData()));

  test('Standard ohne Eintrag = Werte aus FR-0062', () async {
    expect(await ReserveZoneSettings.load(store), [50, 60, 70, 80, 90, 100]);
    final p = await ReserveZoneSettings.loadParameters(store);
    expect(p.reserveZoneBounds, const FitnessParameters.v3().reserveZoneBounds);
  });

  test(
    'FR-0061: gespeicherte Grenzen ändern die Zone neuer Berechnungen',
    () async {
      // r = 0,65: Standard Zone 2.
      expect(zoneAt(await ReserveZoneSettings.loadParameters(store), 155), 2);
      await ReserveZoneSettings.save(store, [40, 50, 60, 70, 80, 100], at: at);
      final p = await ReserveZoneSettings.loadParameters(store);
      expect(zoneAt(p, 155), 3);
      expect(await ReserveZoneSettings.load(store), [40, 50, 60, 70, 80, 100]);
    },
  );

  test('Unter angepasster Zone 1 gesondert (FR-0063)', () async {
    await ReserveZoneSettings.save(store, [60, 70, 80, 85, 90, 100], at: at);
    final p = await ReserveZoneSettings.loadParameters(store);
    final r =
        zones.zoneFor(basis, 145, p) as FitnessAvailable<ReserveZonePlacement>;
    expect(r.value, isA<BelowReserveZone1>()); // r = 0,55
  });

  test('Grenze 0 ist gültig (Untergrenze inklusive)', () async {
    await ReserveZoneSettings.save(store, [0, 60, 70, 80, 90, 100], at: at);
    expect(await ReserveZoneSettings.load(store), [0, 60, 70, 80, 90, 100]);
  });

  test(
    'Parametersatz: nur Grenzen ersetzt, Version und Rest vom Satz',
    () async {
      await ReserveZoneSettings.save(store, [40, 50, 60, 70, 80, 100], at: at);
      final p = await ReserveZoneSettings.loadParameters(store);
      const base = FitnessParameters.v3();
      expect(p.reserveZoneBounds, [0.4, 0.5, 0.6, 0.7, 0.8, 1.0]);
      expect(p.parameterVersion, base.parameterVersion);
      expect(p.trimpWeights, base.trimpWeights);
      expect(p.hintAboveShare, base.hintAboveShare);
      expect(p.minCoveragePercent, base.minCoveragePercent);
      // copyWith übernimmt alles vom Ausgangssatz, auch Nicht-Standardwerte.
      const odd = FitnessParameters(
        parameterVersion: 99,
        hintAboveShare: 1.2,
        minCoveragePercent: 70,
      );
      final c = odd.copyWith(reserveZoneBounds: p.reserveZoneBounds);
      expect(c.parameterVersion, 99);
      expect(c.hintAboveShare, 1.2);
      expect(c.minCoveragePercent, 70);
      expect(c.reserveZoneBounds, p.reserveZoneBounds);
    },
  );

  final bad = <String, (List<int>, ZoneBoundsProblem, int)>{
    'absteigend': (
      [50, 70, 60, 80, 90, 100],
      ZoneBoundsProblem.notAscending,
      2,
    ),
    'gleich (Zone ohne Breite)': (
      [50, 60, 60, 80, 90, 100],
      ZoneBoundsProblem.notAscending,
      2,
    ),
    'außerhalb oben': (
      [50, 60, 70, 80, 90, 101],
      ZoneBoundsProblem.outOfRange,
      5,
    ),
    'außerhalb unten': (
      [-1, 60, 70, 80, 90, 100],
      ZoneBoundsProblem.outOfRange,
      0,
    ),
    'Obergrenze nicht 100 (fest)': (
      [50, 60, 70, 80, 90, 95],
      ZoneBoundsProblem.outOfRange,
      5,
    ),
    'zu wenige': ([50, 60, 70, 80, 90], ZoneBoundsProblem.wrongCount, 0),
    'zu viele': (
      [50, 60, 70, 80, 90, 95, 100],
      ZoneBoundsProblem.wrongCount,
      0,
    ),
  };
  bad.forEach((name, c) {
    test('ungültig ($name): abgelehnt, alter Stand bleibt', () async {
      await ReserveZoneSettings.save(store, [40, 50, 60, 70, 80, 100], at: at);
      await expectLater(
        ReserveZoneSettings.save(store, c.$1, at: at),
        throwsA(
          isA<ZoneBoundsException>()
              .having((e) => e.problem, 'problem', c.$2)
              .having((e) => e.index, 'index', c.$3),
        ),
      );
      expect(await ReserveZoneSettings.load(store), [40, 50, 60, 70, 80, 100]);
    });
  });

  test('beschädigter gespeicherter Wert fällt auf den Standard', () async {
    for (final raw in [
      '',
      'a,b',
      '50,x,70,80,90,100',
      '50,60,70',
      '90,80,70,60,50,40',
    ]) {
      await store.set(SettingKeys.reserveZoneBounds, raw, at: at);
      expect(
        await ReserveZoneSettings.load(store),
        ReserveZoneSettings.defaultPercents,
      );
    }
  });

  test('Zurücksetzen stellt den Standard her', () async {
    await ReserveZoneSettings.save(store, [40, 50, 60, 70, 80, 100], at: at);
    await ReserveZoneSettings.reset(store, at: at);
    expect(
      await ReserveZoneSettings.load(store),
      ReserveZoneSettings.defaultPercents,
    );
  });

  test('OQ-0065: mit alten Grenzen berechnetes Ergebnis bleibt unverändert, '
      'neue Berechnung weicht ab', () async {
    // Noch keine gespeicherten Zonenzeiten im Schema: Das Ergebnis ist ein
    // Wert, der nur mit den damals verwendeten Parametern reproduzierbar ist.
    final hr = fitHeartRate(fitDense(0, 60, 155));
    final mv = fitMovement([fitSpan(0, 60)]);
    List<int> times(FitnessParameters p) {
      final r = zones.timeInZones(
        basis: basis,
        heartRate: hr,
        movement: mv,
        p: p,
      ) as FitnessAvailable<ReserveZoneTimes>;
      return List.of(r.value.zoneMicros);
    }

    final oldParams = await ReserveZoneSettings.loadParameters(store);
    final before = times(oldParams);
    await ReserveZoneSettings.save(store, [40, 50, 60, 70, 80, 100], at: at);
    final newParams = await ReserveZoneSettings.loadParameters(store);

    expect(times(oldParams), before);
    expect(before[1], greaterThan(0));
    expect(times(newParams), isNot(before));
    expect(times(newParams)[2], greaterThan(0));
  });
}
