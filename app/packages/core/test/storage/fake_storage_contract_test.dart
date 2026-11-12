import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:core/testing/storage_contract.dart';
import 'package:test/test.dart';

void main() {
  final key = Uint8List.fromList(List.generate(32, (i) => i));
  for (final c in storageContractCases()) {
    test('Fake: ${c.name}', () async {
      final storage = FakeStorage();
      await c.run(StorageContractHarness(open: () => storage.open(key)));
    });
  }

  test('Fake: nicht durchgelaufener Checkpoint meldet deletedNotErased, Löschen gilt', () async {
    final storage = FakeStorage()..checkpointIncomplete = true;
    final s = await storage.open(key);
    final id = (await s.runs.create(startedAt: DateTime.utc(2030))).id;
    await expectLater(
      s.deleteRun(id),
      throwsA(
        isA<StorageException>().having(
          (e) => e.failure,
          'failure',
          StorageFailure.deletedNotErased,
        ),
      ),
    );
    expect(await s.runs.get(id), isNull);
    await expectLater(s.deleteAll(), throwsA(isA<StorageException>()));
  });

  group(
    'Fake: Einzelschreiber des Plans prüfen die Festlegung wie die CHECK-Regel',
    () {
      final today = DateTime.utc(2026, 11, 11);

      /// Plan mit Ziel; liefert Speicher, eine künftige Einheit [u] und einen
      /// freien Tag in deren Woche.
      Future<(FakeStorage, PlanUnit, DateTime)> seeded() async {
        final storage = FakeStorage();
        final s = await storage.open(key);
        await (s as GoalStorage).goals.save(
          TrainingGoal(
            type: GoalType.distance,
            distance: GoalDistance.tenKilometers,
            targetDate: DateTime(2027, 6, 1),
            runDays: const {2, 4, 6},
            maxSessionSeconds: 7200,
            weeklyCapSeconds: 240 * 60.0,
            createdAt: DateTime.utc(2026, 11, 1),
            hardSessionEnabled: true,
            canRun30: ContinuousRun30.yes,
          ),
          today: DateTime.utc(2026, 11, 1),
        );
        final plans = (s as PlanStorage).plans;
        await recalculatePlan(
          plans: plans,
          settings: s.settings,
          trigger: PlanTrigger.create,
          today: today,
          now: today,
        );
        final all = await plans.unitsBetween(today, planFarFuture);
        final u = all.firstWhere(
          (u) => u.day.isAfter(today.add(const Duration(days: 20))),
        );
        final monday = u.day.subtract(Duration(days: u.day.weekday - 1));
        final free = [for (var i = 0; i < 7; i++) monday.add(Duration(days: i))]
            .firstWhere((d) => all.every((x) => x.day != d));
        return (storage, u, free);
      }

      PlanUnit invalid(
        PlanUnit u, {
        required PlanUnitKind kind,
        required PlanUnitFixed fixed,
      }) => PlanUnit(
        id: u.id,
        day: u.day,
        kind: kind,
        phase: u.phase,
        weekIndex: u.weekIndex,
        minutes: 0,
        segments: const [],
        pinned: false,
        fixed: fixed,
      );

      test(
        'confirmMove lehnt ein Ergebnis mit ungültiger Festlegung ab',
        () async {
          final (storage, u, free) = await seeded();
          final s = await storage.open(key);
          // Ruhe mit fixed = kind: nach dem Verschieben (pinned) bleibt die
          // Festlegung unzulässig.
          final bad = invalid(
            u,
            kind: PlanUnitKind.rest,
            fixed: PlanUnitFixed.kind,
          );
          storage.data.planUnits[u.id!] = bad;
          await expectLater(
            (s as PlanStorage).plans.confirmMove(u.id!, free, today: today),
            throwsA(
              isA<StorageException>().having(
                (e) => e.failure,
                'failure',
                StorageFailure.rejected,
              ),
            ),
          );
          expect(storage.data.planUnits[u.id!], same(bad));
        },
      );

      test(
        'setRestDay lehnt eine verlegte Einheit mit ungültiger Festlegung ab',
        () async {
          final (storage, u, free) = await seeded();
          final s = await storage.open(key);
          // Locker mit fixed = day: nach dem Verlegen (pinned) unzulässig.
          final bad = invalid(
            u,
            kind: PlanUnitKind.easy,
            fixed: PlanUnitFixed.day,
          );
          storage.data.planUnits[u.id!] = bad;
          final before = Map.of(storage.data.planUnits);
          await expectLater(
            (s as PlanStorage).plans.setRestDay(
              PlanUnit(
                day: u.day,
                kind: PlanUnitKind.rest,
                phase: u.phase,
                weekIndex: u.weekIndex,
                minutes: 0,
                segments: const [],
              ),
              today: today,
              expectedUnitId: u.id,
              moveUnitTo: free,
            ),
            throwsA(
              isA<StorageException>().having(
                (e) => e.failure,
                'failure',
                StorageFailure.rejected,
              ),
            ),
          );
          expect(storage.data.planUnits, before);
        },
      );
    },
  );
}
