import 'package:core/core.dart';
import 'package:test/test.dart';

import 'recalc_support.dart';

Future<Map<String, ComputedValue>> _stored(RecalcWorld w, int id) async =>
    (await w.session.values.readRunValues(runLoadValueKeys))[id] ?? {};

String _fingerprint(Map<String, ComputedValue> m) => [
  for (final k in (m.keys.toList()..sort()))
    '$k=${m[k]!.value}|${m[k]!.unavailableReason?.name}|${m[k]!.computedAt.toIso8601String()}'
        '|${m[k]!.heartRateBasis?.maxBpm}/${m[k]!.heartRateBasis?.restingBpm}',
].join(';');

Future<int> _run(
  RecalcWorld w,
  int day, {
  bool calculate = true,
  int minutes = 5,
}) async {
  final id = await w.seedRun(DateTime.utc(2030, 1, day, 8), minutes: minutes);
  if (calculate) await w.calc().calculateAfterRun(id);
  return id;
}

void main() {
  group('Zonenzeiten und TRIMP als Laufwerte', () {
    test(
      'nach dem Lauf: je Zone ein Wert in Sekunden mit Basis-Schnappschuss',
      () async {
        final w = await RecalcWorld.create();
        final id = await _run(w, 10);
        final v = await _stored(w, id);
        expect(v.keys.toSet(), runLoadValueKeys);
        // 150 bpm: r = (150 - 60) / 130 = 0,69, also Zone 2 (60 bis 70 %).
        expect(v[zoneTimeValueKey(2)]!.value, closeTo(300, 5));
        for (final z in [1, 3, 4, 5]) {
          expect(v[zoneTimeValueKey(z)]!.value, 0, reason: 'gemessen 0 s');
        }
        expect(v[zoneBelowValueKey]!.value, 0);
        expect(v[zoneTimeValueKey(2)]!.unit, 's');
        expect(v[trimpRunValueKey]!.unit, 'points');
        expect(
          v[trimpRunValueKey]!.value,
          closeTo(15, 0.5),
        ); // 5 min * Gewicht 3 (150 / 190 = 79 %)
        for (final c in v.values) {
          expect(c.heartRateBasis!.maxBpm, 190);
          expect(c.heartRateBasis!.restingBpm, 60);
          expect(c.unavailableReason, isNull);
        }
        // original und current gleich (wie üblich), je Wert.
        final pairs = await w.session.values.read(ValueOwner.run(id));
        final zone2 = pairs.singleWhere(
          (p) => p.original.key == zoneTimeValueKey(2),
        );
        expect(zone2.original.value, zone2.current.value);
        final load = StoredRunLoad.fromValues(v);
        expect(load.zoneTimes![1].inSeconds, closeTo(300, 5));
        expect(load.trimpIncomplete, isFalse);
      },
    );

    test('fehlende Basis: Werte ohne Zahl mit Grund, nie 0', () async {
      final w = await RecalcWorld.create(profile: const ProfileRecord());
      final id = await _run(w, 10);
      final v = await _stored(w, id);
      expect(v.keys.toSet(), runLoadValueKeys);
      for (final c in v.values) {
        expect(c.value, isNull);
        expect(c.unavailableReason, UnavailableReason.missingMaxHeartRate);
        expect(c.quality, ValueQuality.undeterminable);
      }
      final load = StoredRunLoad.fromValues(v);
      expect(load.zoneTimes, isNull);
      expect(load.zonesReason, UnavailableReason.missingMaxHeartRate);
      expect(load.trimpReason, UnavailableReason.missingMaxHeartRate);
    });

    test('Zonengrenzen aus den Einstellungen zum Laufende', () async {
      final w = await RecalcWorld.create();
      await ReserveZoneSettings.save(w.session.settings, [
        50,
        55,
        60,
        65,
        70,
        100,
      ], at: w.clock.now());
      final id = await _run(w, 10);
      final v = await _stored(w, id);
      // r = 0,69 liegt bei diesen Grenzen in Zone 4 (65 bis 70 %).
      expect(v[zoneTimeValueKey(4)]!.value, closeTo(300, 5));
      expect(v[zoneTimeValueKey(2)]!.value, 0);
    });

    test('Profil- und Zonenänderung ändern gespeicherte Zonen nie (L11)', () async {
      final w = await RecalcWorld.create();
      final id = await _run(w, 10, minutes: 30);
      final other = await _run(w, 11, minutes: 30);
      final before = _fingerprint(await _stored(w, id));
      final vo2Before = (await w.session.values.read(ValueOwner.run(id)))
          .singleWhere((p) => p.original.key == vo2maxRunValueKey)
          .current
          .value;

      // Zonengrenzen im Editor geändert: alte Läufe bleiben.
      await ReserveZoneSettings.save(w.session.settings, [
        50,
        55,
        60,
        65,
        70,
        100,
      ], at: w.clock.now());
      final summary = (await RunSummaryService(
        session: w.session,
        clock: w.clock,
      ).load(id))!;
      expect(summary.load.zoneTimes![1].inSeconds, closeTo(1800, 10));
      expect(summary.load.zoneTimes![3], Duration.zero);

      // Profiländerung und bestätigte Neuberechnung: VO2max wird neu gerechnet,
      // die Zonen nicht.
      final s = w.recalc();
      await w.session.profile.save(profile180);
      final offer = await s.profileChanged(
        before: profile190,
        after: profile180,
      );
      await s.confirm(offer!);
      final vo2After = (await w.session.values.read(ValueOwner.run(id)))
          .singleWhere((p) => p.original.key == vo2maxRunValueKey)
          .current
          .value;
      expect(vo2After, isNot(vo2Before), reason: 'Neuberechnung lief');
      expect(_fingerprint(await _stored(w, id)), before);
      expect(
        (await _stored(w, other))[zoneTimeValueKey(2)]!.heartRateBasis!.maxBpm,
        190,
      );
      await s.dispose();
    });

    test('Lauf ohne gespeicherte Werte: nicht gespeichert, nie 0', () async {
      final w = await RecalcWorld.create();
      final id = await _run(w, 10, calculate: false);
      final s = (await RunSummaryService(
        session: w.session,
        clock: w.clock,
      ).load(id))!;
      expect(s.load.zonesStored, isFalse);
      expect(s.load.zoneTimes, isNull);
      expect(s.load.trimpStored, isFalse);
      expect(s.figures.zoneTimes, isNull);
      expect(s.figures.trimpPoints, isNull);
    });

    test(
      'Löschen: Zonenwerte gehen mit dem Lauf, die anderen bleiben',
      () async {
        final w = await RecalcWorld.create();
        final a = await _run(w, 10);
        final b = await _run(w, 11);
        await w.session.deleteRun(a);
        final all = await w.session.values.readRunValues(runLoadValueKeys);
        expect(all.keys, [b]);
        expect(await w.session.values.read(ValueOwner.run(a)), isEmpty);
      },
    );

    test(
      'Zeitraumstatistik und Historie lesen die gespeicherten Zonen',
      () async {
        final w = await RecalcWorld.create();
        final a = await _run(w, 10);
        final b = await _run(w, 11);
        final old = await _run(w, 12, calculate: false);
        // Danach ändert sich das Profil: die Statistik bleibt bei den
        // gespeicherten Werten.
        await w.session.profile.save(profile180);
        await ReserveZoneSettings.save(w.session.settings, [
          50,
          55,
          60,
          65,
          70,
          100,
        ], at: w.clock.now());
        final overviews = await RunOverviewService(
          session: w.session,
          clock: w.clock,
        ).load();
        final stats = computePeriodStatistics(
          StatisticsPeriod.custom(from: '2030-01-01', to: '2030-01-31'),
          [for (final o in overviews) o.toFigures()],
        );
        expect(stats.runCount, 3);
        expect(stats.zoneTimes.value![1].inSeconds, closeTo(600, 10));
        expect(stats.zoneTimes.value![3], Duration.zero);
        expect(stats.zoneTimes.runsWithValue, 2);
        expect(
          stats.zoneTimes.isPartial,
          isTrue,
          reason: 'ein alter Lauf fehlt',
        );
        expect(stats.trimpPoints.value, closeTo(30, 1));
        final byId = {for (final o in overviews) o.run.id: o};
        expect(byId[a]!.load.zonesStored, isTrue);
        expect(byId[b]!.load.zoneTimes![1].inSeconds, closeTo(300, 5));
        expect(byId[old]!.load.zonesStored, isFalse);
      },
    );
  });
}
