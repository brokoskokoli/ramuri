import 'package:core/core.dart';
import 'package:test/test.dart';

import 'package:core/fakes/fake_storage_settings.dart';

import '../fitness/fitness_support.dart';

const zones = ReserveZones(reserve: HeartRateReserve());
// HFR 100 bpm: bpm 165 ist r = 0,65.
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

  test('OQ-0065: bereits berechnete Zonenzeiten bleiben unverändert', () async {
    // Noch keine gespeicherten Zonenzeiten im Schema; das Ergebnis ist ein
    // unveränderlicher Wert, eine neue Einteilung rechnet nur neu.
    final hr = fitHeartRate(fitDense(0, 60, 155));
    final mv = fitMovement([fitSpan(0, 60)]);
    final before = zones.timeInZones(
      basis: basis,
      heartRate: hr,
      movement: mv,
      p: await ReserveZoneSettings.loadParameters(store),
    ) as FitnessAvailable<ReserveZoneTimes>;
    final snap = List.of(before.value.zoneMicros);
    await ReserveZoneSettings.save(store, [40, 50, 60, 70, 80, 100], at: at);
    final after = zones.timeInZones(
      basis: basis,
      heartRate: hr,
      movement: mv,
      p: await ReserveZoneSettings.loadParameters(store),
    ) as FitnessAvailable<ReserveZoneTimes>;
    expect(before.value.zoneMicros, snap);
    expect(before.value.zoneMicros[1], greaterThan(0));
    expect(after.value.zoneMicros[2], greaterThan(0));
    expect(after.value.zoneMicros, isNot(snap));
  });
}
