import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:core/core.dart';
import 'package:test/test.dart';

final d0 = DateTime.utc(2026, 11, 11); // Mittwoch

TrainingGoal goal({
  GoalType type = GoalType.time,
  GoalDistance? distance = GoalDistance.tenKilometers,
  Set<int> days = const {2, 4, 6},
  int maxMin = 120,
  int capMin = 240,
  bool hard = true,
  ContinuousRun30 c30 = ContinuousRun30.yes,
  double? stated,
  DateTime? date,
}) => TrainingGoal(
  type: type,
  distance: type == GoalType.open ? null : distance,
  targetSeconds: type == GoalType.time ? 3000 : null,
  targetDate: type == GoalType.open ? null : date,
  runDays: days,
  maxSessionSeconds: maxMin * 60.0,
  weeklyCapSeconds: capMin * 60.0,
  createdAt: d0,
  hardSessionEnabled: hard,
  currentWeeklySeconds: stated,
  canRun30: c30,
);

PlanInputs inputs({int start = 90, DateTime? today, DateTime? anchor}) =>
    PlanInputs(
      anchor: anchor ?? DateTime.utc(2026, 11, 9),
      startWeeklyMinutes: start,
      today: today ?? d0,
    );

String sig(PlanUnit u) =>
    '${u.day.toIso8601String()}|${u.kind.name}|${u.phase.name}|${u.weekIndex}|'
    '${u.minutes}|${[for (final s in u.segments) '${s.kind.name}:${s.minutes}'].join(',')}|'
    '${u.pinned}';

List<String> sigs(Iterable<PlanUnit> l) => [for (final u in l) sig(u)];

DateTime monday(DateTime d) => d.subtract(Duration(days: d.weekday - 1));

TrainingGoal randomGoal(Random r, DateTime today) {
  final type = GoalType.values[r.nextInt(3)];
  final days = <int>{};
  final n = 1 + r.nextInt(6);
  while (days.length < n) {
    days.add(1 + r.nextInt(7));
  }
  return goal(
    type: type,
    distance: GoalDistance.values[r.nextInt(3)],
    days: days,
    maxMin: 30 + r.nextInt(150),
    capMin: 60 + r.nextInt(500),
    hard: r.nextBool(),
    c30: ContinuousRun30.values[r.nextInt(3)],
    stated: r.nextBool() ? (20 + r.nextInt(200)) * 60.0 : null,
    date: today.add(Duration(days: 28 + r.nextInt(300))),
  );
}

PlanInputs randomInputs(Random r, DateTime today) => PlanInputs(
  anchor: monday(today.subtract(Duration(days: r.nextInt(70)))),
  startWeeklyMinutes: 20 + r.nextInt(250),
  today: today,
  easyPaceSecondsPerKm: r.nextBool() ? 300.0 + r.nextInt(200) : null,
  easyRunCount: r.nextInt(6),
);

void main() {
  group('PlanInputs', () {
    test('JSON: feste Schlüsselreihenfolge und Rundreise', () {
      final i = PlanInputs(
        anchor: DateTime.utc(2026, 11, 9),
        startWeeklyMinutes: 90,
        today: d0,
        easyPaceSecondsPerKm: 330.5,
        easyRunCount: 4,
        lastWeekMinutes: 80,
        achievedShare: 0.75,
      );
      expect(i.toJson().keys.toList(), [
        'inputsVersion',
        'anchor',
        'startWeeklyMinutes',
        'walkRunWeeks',
        'easyPaceSecondsPerKm',
        'easyRunCount',
        'lastWeekMinutes',
        'achievedShare',
        'walkRunStart',
        'walkRunFrom',
        'intensity',
        'today',
      ]);
      final text = jsonEncode(i.toJson());
      final back = PlanInputs.fromJson(
        jsonDecode(text) as Map<String, Object?>,
      );
      expect(jsonEncode(back.toJson()), text);
      expect(
        jsonEncode(inputs().toJson()),
        '{"inputsVersion":1,"anchor":"2026-11-09","startWeeklyMinutes":90,'
        '"walkRunWeeks":0,"easyPaceSecondsPerKm":null,"easyRunCount":0,'
        '"lastWeekMinutes":null,"achievedShare":null,"walkRunStart":null,'
        '"walkRunFrom":null,"intensity":null,"today":"2026-11-11"}',
      );
    });

    test('fromJson lehnt Ungültiges ab', () {
      final ok = inputs().toJson();
      expect(
        () => PlanInputs.fromJson({...ok, 'inputsVersion': 2}),
        throwsFormatException,
      );
      expect(
        () => PlanInputs.fromJson({...ok, 'anchor': '2026-02-30'}),
        throwsFormatException,
      );
      expect(
        () => PlanInputs.fromJson({...ok, 'startWeeklyMinutes': 0}),
        throwsFormatException,
      );
      expect(
        () => PlanInputs.fromJson({...ok, 'startWeeklyMinutes': 'x'}),
        throwsFormatException,
      );
    });

    test(
      'forNewGoal: Anker ist der Montag, Start aus Stand oder 30 je Tag',
      () {
        final a = PlanInputs.forNewGoal(goal(), d0);
        expect(a.anchor, DateTime.utc(2026, 11, 9));
        expect(a.startWeeklyMinutes, 90);
        final b = PlanInputs.forNewGoal(goal(stated: 150 * 60.0), d0);
        expect(b.startWeeklyMinutes, 150);
      },
    );
  });

  group('30 min am Stück (eine Ableitung)', () {
    test('ja, genannte Wochenzeit mit langem Lauf >= 30, sonst nein', () {
      bool c(TrainingGoal g, {int w = 0, int walk = 0}) =>
          canRunContinuous30(g, weekIndex: w, walkRunWeeks: walk);
      expect(c(goal(c30: ContinuousRun30.yes)), isTrue);
      expect(c(goal(c30: ContinuousRun30.no)), isFalse);
      expect(c(goal(c30: ContinuousRun30.unknown)), isFalse);
      // 3 Tage: 40 % von 75 = 30 -> ja; 40 % von 74 = 29,6 -> nein.
      expect(c(goal(c30: ContinuousRun30.unknown, stated: 75 * 60.0)), isTrue);
      expect(c(goal(c30: ContinuousRun30.no, stated: 74 * 60.0)), isFalse);
      // 2 Tage: 60 % von 50 = 30.
      expect(
        c(goal(c30: ContinuousRun30.unknown, days: {2, 5}, stated: 50 * 60.0)),
        isTrue,
      );
      // nach der Geh-Lauf-Abfolge
      expect(c(goal(c30: ContinuousRun30.no), w: 9, walk: 9), isTrue);
      expect(c(goal(c30: ContinuousRun30.no), w: 8, walk: 9), isFalse);
    });
  });

  group('Zielspitze (PAR-205)', () {
    test('mit Tempo ab 3 Läufen, sonst 35/65/100, höchstens 120', () {
      int t(GoalDistance d, [double? pace, int n = 0]) =>
          targetLongestRunMinutes(
            distance: d,
            easyPaceSecondsPerKm: pace,
            easyRunCount: n,
          );
      expect(t(GoalDistance.fiveKilometers), 35);
      expect(t(GoalDistance.tenKilometers), 65);
      expect(t(GoalDistance.halfMarathon), 100);
      expect(t(GoalDistance.fiveKilometers, 360, 2), 35);
      expect(t(GoalDistance.fiveKilometers, 360, 3), 30);
      expect(t(GoalDistance.tenKilometers, 360, 3), 60);
      expect(t(GoalDistance.halfMarathon, 360, 3), 96);
      expect(t(GoalDistance.halfMarathon, 480, 3), 120); // 128 -> 120
    });
  });

  group('generatePlan', () {
    test('Grundfall: künftige Einheiten ab heute, Tage = Lauftage', () {
      final g = goal(date: DateTime.utc(2027, 2, 14));
      final plan = generatePlan(g, inputs(), const [], d0);
      expect(plan.frozenUnits, isEmpty);
      expect(plan.units, isNotEmpty);
      expect(
        plan.units.first.day,
        DateTime.utc(2026, 11, 12),
      ); // Mi: kein Lauftag
      for (final u in plan.units) {
        expect(u.day.isBefore(d0), isFalse);
        expect(g.runDays.contains(u.day.weekday), isTrue);
        expect(u.runId, isNull);
      }
      expect(plan.version, PlanVersion.current);
      // Erste Woche: Do und Sa (Di ist vorbei), 3. Lauftag ist Mi? Nein: {2,4,6}.
      final first = plan.units.where((u) => u.weekIndex == 0).toList();
      expect([for (final u in first) u.day.weekday], [4, 6]);
    });

    test('Determinismus: gleiche Eingaben, auch nach JSON-Rundreise', () {
      final r = Random(42);
      for (var k = 0; k < 300; k++) {
        final today = DateTime.utc(
          2026,
          1,
          1,
        ).add(Duration(days: r.nextInt(300)));
        final g = randomGoal(r, today);
        final i = randomInputs(r, today);
        final a = generatePlan(g, i, const [], today);
        final b = generatePlan(g, i, const [], today);
        final i2 = PlanInputs.fromJson(
          jsonDecode(jsonEncode(i.toJson())) as Map<String, Object?>,
        );
        final c = generatePlan(g, i2, const [], today);
        expect(sigs(b.units), sigs(a.units), reason: 'Lauf $k');
        expect(sigs(c.units), sigs(a.units), reason: 'JSON $k');
        expect(c.unplacedMinutes, a.unplacedMinutes);
      }
    });

    test('Eigenschaften aus C1b über alle Wochen', () {
      final r = Random(7);
      for (var k = 0; k < 300; k++) {
        final today = DateTime.utc(
          2026,
          1,
          1,
        ).add(Duration(days: r.nextInt(300)));
        final g = randomGoal(r, today);
        final i = randomInputs(r, today);
        final plan = generatePlan(g, i, const [], today);
        final maxMin = (g.maxSessionSeconds / 60).floor();
        final byWeek = <int, List<PlanUnit>>{};
        for (final u in plan.units) {
          (byWeek[u.weekIndex] ??= []).add(u);
          expect(u.minutes, lessThanOrEqualTo(maxMin), reason: 'Lauf $k');
          expect(u.minutes, u.segments.fold(0, (a, s) => a + s.minutes));
          expect(u.minutes, greaterThanOrEqualTo(1));
        }
        for (final w in plan.weeks) {
          final us = byWeek[w.index] ?? [];
          // Höchstens eine harte Einheit; nur mit Schalter, >= 3 Läufen.
          final hard = us.where((u) => u.isHard).length;
          expect(hard, lessThanOrEqualTo(1));
          if (hard == 1) {
            expect(g.hardSessionEnabled, isTrue);
            expect(g.runDays.length, greaterThanOrEqualTo(3));
          }
          // Wochensumme: nur volle Wochen (alle Lauftage vorhanden).
          if (us.length == g.runDays.length && w.minutes != null) {
            expect(
              us.fold(0, (a, u) => a + u.minutes) +
                  (plan.unplacedByWeek[w.index] ?? 0),
              w.minutes,
              reason: 'Lauf $k Woche ${w.index}',
            );
          }
        }
        // Abstand zwischen intensiven Einheiten >= 2 Tage, auch über den
        // Wochenwechsel (nur bei mehr als einem Lauftag).
        final intensive = [
          for (final u in plan.units)
            if (u.isIntensive && u.kind != PlanUnitKind.easy) u,
        ];
        for (var a = 1; a < intensive.length; a++) {
          if (g.runDays.length < 2) continue;
          expect(
            intensive[a].day.difference(intensive[a - 1].day).inDays,
            greaterThanOrEqualTo(2),
            reason: 'Lauf $k',
          );
        }
      }
    });

    test('eingefrorene Einheiten bleiben unverändert (Eigenschaft)', () {
      final r = Random(11);
      for (var k = 0; k < 200; k++) {
        final t0 = DateTime.utc(2026, 1, 1).add(Duration(days: r.nextInt(300)));
        final g = randomGoal(r, t0);
        final i = randomInputs(r, t0);
        final p0 = generatePlan(g, i, const [], t0);
        if (p0.units.length < 3) continue;
        final t1 = t0.add(Duration(days: 1 + r.nextInt(60)));
        final frozen = <PlanUnit>[];
        for (final u in p0.units) {
          if (u.day.isBefore(t1)) {
            frozen.add(u);
          } else if (r.nextInt(5) == 0) {
            frozen.add(_withRun(u));
          }
        }
        final p1 = generatePlan(g, i, frozen, t1);
        // 1) übernommen, dieselben Objekte, nichts davon neu erzeugt.
        expect(p1.frozenUnits.length, frozen.length);
        for (final f in frozen) {
          expect(p1.frozenUnits.any((u) => identical(u, f)), isTrue);
        }
        // 2) neue Einheiten: nie vor heute, nie auf festen Tagen.
        final fixedDays = {for (final f in frozen) f.day};
        for (final u in p1.units) {
          expect(u.day.isBefore(t1), isFalse);
          expect(fixedDays.contains(u.day), isFalse);
        }
        // 3) gleiche Eingaben: die Zukunft gleicht der alten Zukunft
        // (Viererzählung über den Anker, Wechsel der harten Formen).
        final expected = [
          for (final u in p0.units)
            if (!u.day.isBefore(t1) && !fixedDays.contains(u.day)) u,
        ];
        final a = sigs(p1.units), b = sigs(expected);
        for (var x = 0; x < a.length && x < b.length; x++) {
          if (a[x] != b[x]) {
            fail('Lauf $k: $t0 -> $t1 $g\n got ${a[x]}\n exp ${b[x]}');
          }
        }
        if (g.type == GoalType.open) {
          // Ziel ohne Datum läuft fort: der Horizont wandert mit heute.
          expect(a.length, greaterThanOrEqualTo(b.length), reason: 'Lauf $k');
        } else {
          expect(a.length, b.length, reason: 'Lauf $k');
        }
      }
    });

    test('Geh-Lauf-Woche mit eingefrorenen Einheiten nach geänderten Tagen '
        'hat nie mehr Einheiten als die Abfolge (NB3 Muss 1)', () {
      final t0 = DateTime.utc(2026, 11, 9); // Montag
      final date = t0.add(const Duration(days: 120));
      final g0 = goal(
        type: GoalType.distance,
        distance: GoalDistance.fiveKilometers,
        days: {1, 3, 5},
        c30: ContinuousRun30.no,
        date: date,
      );
      final i0 = PlanInputs.forNewGoal(g0, t0);
      final p0 = generatePlan(g0, i0, const [], t0);
      final t1 = DateTime.utc(2026, 11, 12); // Donnerstag
      final frozen = [
        for (final u in p0.units)
          if (u.day.isBefore(t1)) u,
      ];
      expect(frozen.length, 2);
      final g1 = goal(
        type: GoalType.distance,
        distance: GoalDistance.fiveKilometers,
        days: {4, 6, 7},
        c30: ContinuousRun30.no,
        date: date,
      );
      final p1 = generatePlan(g1, i0.copyWith(today: t1), frozen, t1);
      final week0 = p1.allUnits.where((u) => monday(u.day) == t0).toList();
      expect([for (final u in week0) u.day.weekday], [1, 3, 4]);
      expect(p1.droppedDaysByWeek[0], [
        DateTime.utc(2026, 11, 14),
        DateTime.utc(2026, 11, 15),
      ]);
      final week1 = p1.allUnits
          .where((u) => monday(u.day) == t0.add(const Duration(days: 7)))
          .toList();
      expect(week1.length, 3);
    });

    for (final walkRun in [false, true]) {
      test(
        'Eigenschaften über den ganzen Plan mit eingefrorenen Einheiten '
        'und geänderten Lauftagen${walkRun ? ' (Geh-Lauf-Abfolge)' : ''}',
        () {
          final r = Random(walkRun ? 31 : 29);
          for (var k = 0; k < 400; k++) {
            final t0 = DateTime.utc(
              2026,
              1,
              1,
            ).add(Duration(days: r.nextInt(300)));
            var g0 = randomGoal(r, t0);
            if (r.nextInt(4) == 0) {
              // Kurze maximale Zeit: keine Woche der Abfolge passt (PAR-141).
              g0 = goal(
                type: g0.type,
                distance: g0.distance,
                days: g0.runDays,
                maxMin: 5 + r.nextInt(25),
                capMin: (g0.weeklyCapSeconds / 60).floor(),
                hard: g0.hardSessionEnabled,
                c30: g0.canRun30,
                stated: g0.currentWeeklySeconds,
                date: g0.targetDate,
              );
            }
            final days1 = <int>{};
            final n1 = 1 + r.nextInt(6);
            while (days1.length < n1) {
              days1.add(1 + r.nextInt(7));
            }
            final g1 = goal(
              type: g0.type,
              distance: g0.distance,
              days: days1,
              maxMin: (g0.maxSessionSeconds / 60).floor(),
              capMin: (g0.weeklyCapSeconds / 60).floor(),
              hard: g0.hardSessionEnabled,
              c30: g0.canRun30,
              stated: g0.currentWeeklySeconds,
              date: g0.targetDate,
            );
            final i0 = walkRun
                ? PlanInputs.forNewGoal(g0, t0)
                : randomInputs(r, t0);
            final p0 = generatePlan(g0, i0, const [], t0);
            if (p0.units.length < 3) continue;
            final t1 = t0.add(Duration(days: 1 + r.nextInt(60)));
            final t1Week = monday(t1);
            final frozen = <PlanUnit>[];
            for (final u in p0.units) {
              if (u.day.isBefore(t1)) {
                frozen.add(u);
              } else if (monday(u.day) == t1Week && r.nextInt(3) == 0) {
                frozen.add(_withRun(u));
              }
            }
            // Ein Lauf an einem beliebigen Tag der laufenden Woche, als harte
            // oder lange Einheit eingetragen (der Nutzer lief anders geplant).
            final extraDay = t1.add(Duration(days: r.nextInt(8 - t1.weekday)));
            final kind = r.nextBool() ? PlanUnitKind.tempo : PlanUnitKind.long;
            final sameRole = kind == PlanUnitKind.long
                ? (PlanUnit u) => u.kind == PlanUnitKind.long
                : (PlanUnit u) => u.isHard;
            if (r.nextBool() &&
                !frozen.any(
                  (u) =>
                      u.day == extraDay ||
                      (monday(u.day) == t1Week && sameRole(u)),
                )) {
              final m = 20 + r.nextInt(40);
              frozen.add(
                PlanUnit(
                  day: extraDay,
                  kind: kind,
                  phase: PlanPhase.build,
                  weekIndex: 0,
                  minutes: m,
                  segments: [
                    PlanSegment(kind: PlanSegmentKind.easy, minutes: m),
                  ],
                  runId: 98,
                ),
              );
            }
            final i1 = i0.copyWith(today: t1);
            final p1 = generatePlan(g1, i1, frozen, t1);
            final maxMin = (g1.maxSessionSeconds / 60).floor();
            final why =
                'Lauf $k walkRun=$walkRun $t0 -> $t1 '
                '${g0.runDays} -> ${g1.runDays}';
            final frozenSet = frozen.toSet();
            final all = p1.allUnits;
            final byWeek = <DateTime, List<PlanUnit>>{};
            for (final u in all) {
              (byWeek[monday(u.day)] ??= []).add(u);
            }
            for (final u in p1.units) {
              expect(u.minutes, greaterThanOrEqualTo(1), reason: why);
              expect(u.minutes, lessThanOrEqualTo(maxMin), reason: why);
              // Nur gewählte Lauftage (hier ohne Pinned).
              expect(g1.runDays.contains(u.day.weekday), isTrue, reason: why);
            }
            for (final w in p1.weeks) {
              final us = byWeek[w.start] ?? [];
              final walkUnits = us.where((u) => u.kind == PlanUnitKind.walkRun);
              if (walkUnits.isNotEmpty) {
                // Nie mehr Einheiten als die Abfolge je Woche (3) und als
                // gewählte Lauftage, außer eingefrorene auf anderen Tagen.
                final nFrozen = us.where(frozenSet.contains).length;
                final cap = g1.runDays.length < 3 ? g1.runDays.length : 3;
                expect(
                  us.length,
                  lessThanOrEqualTo(nFrozen > cap ? nFrozen : cap),
                  reason: '$why Woche ${w.index}: Einheiten der Geh-Lauf-Woche',
                );
              }
              expect(
                us.where((u) => u.kind == PlanUnitKind.long).length,
                lessThanOrEqualTo(1),
                reason: '$why Woche ${w.index}: langer Lauf',
              );
              expect(
                us.where((u) => u.isHard).length,
                lessThanOrEqualTo(1),
                reason: '$why Woche ${w.index}: hart',
              );
              final minutes = w.minutes;
              if (minutes != null) {
                final frozenSum = us
                    .where(frozenSet.contains)
                    .fold(0, (a, u) => a + u.minutes);
                final sum = us.fold(0, (a, u) => a + u.minutes);
                expect(
                  sum,
                  lessThanOrEqualTo(minutes > frozenSum ? minutes : frozenSum),
                  reason: '$why Woche ${w.index}: über der Wochenzeit',
                );
              }
            }
            final intensive = [
              for (final u in all)
                if (u.isIntensive) u,
            ];
            for (var a = 1; a < intensive.length; a++) {
              final x = intensive[a - 1], y = intensive[a];
              if (frozenSet.contains(x) && frozenSet.contains(y)) continue;
              expect(
                y.day.difference(x.day).inDays,
                greaterThanOrEqualTo(2),
                reason: '$why: Abstand ${x.day} ${y.day}',
              );
            }
          }
        },
      );
    }

    test('eingefrorene harte Einheit: neuer langer Lauf hält den Abstand', () {
      // Lauftage Di, Do, So; die harte Einheit lief am Samstag (Lauf
      // zugeordnet). Der lange Lauf am Sonntag läge nur 1 Tag danach.
      final g = goal(days: {2, 4, 7}, hard: false);
      final today = DateTime.utc(2026, 11, 9);
      final frozen = [
        PlanUnit(
          day: DateTime.utc(2026, 11, 14),
          kind: PlanUnitKind.tempo,
          phase: PlanPhase.build,
          weekIndex: 0,
          minutes: 40,
          segments: const [
            PlanSegment(kind: PlanSegmentKind.tempo, minutes: 40),
          ],
          runId: 5,
        ),
      ];
      final p = generatePlan(
        g,
        inputs(start: 120, today: today),
        frozen,
        today,
      );
      final week0 = p.units.where((u) => u.weekIndex == 0).toList();
      expect(week0.map((u) => u.day.weekday), [2, 4, 7]);
      expect(week0.any((u) => u.kind == PlanUnitKind.long), isFalse);
      expect(week0.last.kind, PlanUnitKind.easy);
    });

    test('eingefrorener langer Lauf: kein zweiter, Woche nie über der '
        'Wochenzeit', () {
      final g = goal(days: {2, 4, 6}, hard: false);
      final today = DateTime.utc(2026, 11, 12);
      final frozen = [
        PlanUnit(
          day: DateTime.utc(2026, 11, 10),
          kind: PlanUnitKind.long,
          phase: PlanPhase.build,
          weekIndex: 0,
          minutes: 80,
          segments: const [
            PlanSegment(kind: PlanSegmentKind.easy, minutes: 80),
          ],
          runId: 5,
        ),
      ];
      final i = inputs(start: 60, today: today);
      final p = generatePlan(g, i, frozen, today);
      final week0 = p.units.where((u) => u.weekIndex == 0).toList();
      expect(week0.where((u) => u.kind == PlanUnitKind.long), isEmpty);
      final total = week0.fold(0, (a, u) => a + u.minutes) + 80;
      expect(total, lessThanOrEqualTo(80), reason: '80 min eingefroren > 60');
      expect(week0, isEmpty);
      // Still entfallende Einheiten werden benannt gemeldet.
      expect(p.droppedDaysByWeek[0], [
        DateTime.utc(2026, 11, 12),
        DateTime.utc(2026, 11, 14),
      ]);
    });

    test('ohne Überschreitung entfällt nichts', () {
      final p = generatePlan(goal(hard: false), inputs(), const [], d0);
      expect(p.droppedDaysByWeek, isEmpty);
    });

    test('Pinned-Termin vor heute oder mit Lauf wird nicht übernommen', () {
      final g = goal(days: {2, 4, 6}, hard: false);
      final today = DateTime.utc(2026, 11, 12); // Donnerstag
      final i = inputs(start: 90, today: today);
      PlanUnit pin(int day, {int? runId}) => PlanUnit(
        day: DateTime.utc(2026, 11, day),
        kind: PlanUnitKind.easy,
        phase: PlanPhase.build,
        weekIndex: 0,
        minutes: 30,
        segments: const [PlanSegment(kind: PlanSegmentKind.easy, minutes: 30)],
        pinned: true,
        runId: runId,
      );
      final past = pin(10);
      final withRun = pin(14, runId: 4);
      final p = generatePlan(
        g,
        i,
        const [],
        today,
        pinnedUnits: [past, withRun],
      );
      expect(p.pinnedConflicts.map((c) => (c.kind, c.day)), [
        (PinnedConflictKind.noMatchingUnit, past.day),
        (PinnedConflictKind.noMatchingUnit, withRun.day),
      ]);
      expect(p.units.any((u) => u.pinned), isFalse);
      expect(p.units.any((u) => u.day.isBefore(today)), isFalse);
      expect(
        sigs(p.units),
        sigs(generatePlan(g, i, const [], today).units),
        reason: 'der Plan bleibt, wie er ohne Termine wäre',
      );
    });

    test('Neuberechnung ändert keine vergangenen Tage', () {
      final g = goal(date: DateTime.utc(2027, 3, 1));
      final p0 = generatePlan(g, inputs(), const [], d0);
      final t1 = DateTime.utc(2026, 12, 2);
      final frozen = [
        for (final u in p0.units)
          if (u.day.isBefore(t1)) u,
      ];
      final p1 = generatePlan(g, inputs(start: 150, today: t1), frozen, t1);
      expect(sigs(p1.frozenUnits), sigs(frozen));
      expect(p1.units.every((u) => !u.day.isBefore(t1)), isTrue);
      expect(
        p1.allUnits.where((u) => u.day.isBefore(t1)).length,
        frozen.length,
      );
    });

    test('Tage und Zahl der Läufe bleiben bei reiner Inhaltsänderung', () {
      final r = Random(5);
      for (var k = 0; k < 200; k++) {
        final t = DateTime.utc(2026, 1, 1).add(Duration(days: r.nextInt(300)));
        final g = randomGoal(r, t);
        final i = randomInputs(r, t);
        final a = generatePlan(g, i, const [], t);
        final g2 = goal(
          type: g.type,
          distance: g.distance,
          days: g.runDays,
          maxMin: (g.maxSessionSeconds / 60).floor() + 10,
          capMin: (g.weeklyCapSeconds / 60).floor() + 30,
          hard: !g.hardSessionEnabled,
          c30: g.canRun30,
          stated: g.currentWeeklySeconds,
          date: g.targetDate,
        );
        final b = generatePlan(
          g2,
          i.copyWith(startWeeklyMinutes: i.startWeeklyMinutes + 17),
          const [],
          t,
        );
        expect(
          [for (final u in b.units) u.day],
          [for (final u in a.units) u.day],
          reason: 'Lauf $k',
        );
      }
    });

    test('Anker bestimmt die Viererzählung (PAR-194)', () {
      final g = goal(type: GoalType.open, hard: false);
      final a = generatePlan(
        g,
        inputs(anchor: DateTime.utc(2026, 11, 9)),
        const [],
        d0,
      );
      final b = generatePlan(
        g,
        inputs(anchor: DateTime.utc(2026, 11, 2)),
        const [],
        d0,
      );
      final la = [
        for (final w in a.weeks)
          if (w.kind == WeekKind.lighter) w.index,
      ];
      final lb = [
        for (final w in b.weeks)
          if (w.kind == WeekKind.lighter) w.index,
      ];
      expect(la.take(3), [3, 7, 11]);
      // Anker eine Woche früher: die leichte Woche liegt eine Woche früher
      // (Woche 3 vom Anker 2.11. = Woche 2 vom Anker 9.11.).
      expect(lb.take(3), [3, 7, 11]);
      final ma = {for (final w in a.weeks) w.start: w.kind};
      final mb = {for (final w in b.weeks) w.start: w.kind};
      final firstLightA = ma.entries
          .firstWhere((e) => e.value == WeekKind.lighter)
          .key;
      final firstLightB = mb.entries
          .firstWhere((e) => e.value == WeekKind.lighter)
          .key;
      expect(firstLightA.difference(firstLightB).inDays, 7);
    });

    test('Wochenminuten der eingefrorenen Einheit werden angerechnet', () {
      final g = goal(hard: false, type: GoalType.open);
      final i = inputs(start: 90, today: DateTime.utc(2026, 11, 9));
      final monday0 = DateTime.utc(2026, 11, 9);
      final base = generatePlan(g, i, const [], monday0);
      final week0 = base.units.where((u) => u.weekIndex == 0).toList();
      expect(week0.fold(0, (a, u) => a + u.minutes), 90);
      // Dienstag war ein 50-min-Lauf (läuft anders als geplant: 27).
      final frozen = [
        PlanUnit(
          day: DateTime.utc(2026, 11, 10),
          kind: PlanUnitKind.easy,
          phase: PlanPhase.entry,
          weekIndex: 0,
          minutes: 50,
          segments: const [
            PlanSegment(kind: PlanSegmentKind.easy, minutes: 50),
          ],
          runId: 7,
        ),
      ];
      final p = generatePlan(g, i, frozen, DateTime.utc(2026, 11, 11));
      final w = p.units.where((u) => u.weekIndex == 0).toList();
      // 90 - 50 = 40 für Do und Sa (statt 27 + 36 = 63 geplant, minus 23).
      expect(frozen.single.minutes + w.fold(0, (a, u) => a + u.minutes), 90);
      expect(p.frozenUnits.single, same(frozen.single));
    });

    test('eingefrorene harte Einheit: keine zweite in der Woche', () {
      // Heute ist der Montag; die geplante harte Einheit liegt auf heute oder
      // danach (nicht vor heute, sonst fiele sie ohnehin weg), die
      // eingefrorene harte Einheit hat einen Lauf an einem anderen Tag.
      final g = goal(days: {1, 3, 5});
      final today = DateTime.utc(2026, 11, 9);
      final i = inputs(start: 150, today: today);
      final full = generatePlan(g, i, const [], today);
      final hardUnit = full.units.firstWhere(
        (u) => u.weekIndex == 0 && u.isHard,
        orElse: () => throw StateError('keine harte Einheit'),
      );
      expect(hardUnit.day.isBefore(today), isFalse, reason: 'Probe nicht leer');
      final other = full.units.firstWhere(
        (u) => u.weekIndex == 0 && u.day.weekday == 3,
      );
      final frozen = [
        PlanUnit(
          day: other.day,
          kind: PlanUnitKind.tempo,
          phase: other.phase,
          weekIndex: 0,
          minutes: other.minutes,
          segments: [
            PlanSegment(kind: PlanSegmentKind.tempo, minutes: other.minutes),
          ],
          runId: 3,
        ),
      ];
      final p = generatePlan(g, i, frozen, today);
      final week0 = p.units.where((u) => u.weekIndex == 0).toList();
      expect(week0.where((u) => u.isHard), isEmpty);
      final replaced = week0.firstWhere((u) => u.day == hardUnit.day);
      expect(replaced.kind, PlanUnitKind.easy);
      expect(
        week0.length,
        full.units.where((u) => u.weekIndex == 0 && u.day != other.day).length,
      );
    });

    test('Startfall nein ohne Abfolge: keine harte Einheit, 3 Läufe', () {
      final g = goal(c30: ContinuousRun30.no);
      final p = generatePlan(
        g,
        inputs(today: DateTime.utc(2026, 11, 9)),
        const [],
        DateTime.utc(2026, 11, 9),
      );
      expect(p.units.where((u) => u.isHard), isEmpty);
      expect(p.hardOmissions[0], HardOmission.notContinuous30);
    });

    test('kein Zugriff auf Uhr, Zufall oder Datenbank in src/plan', () {
      final dir = Directory('lib/src/plan');
      expect(dir.existsSync(), isTrue);
      for (final f in dir.listSync().whereType<File>()) {
        final text = f
            .readAsLinesSync()
            .where((l) => !l.trimLeft().startsWith('//'))
            .join('\n');
        expect(text.contains('DateTime.now'), isFalse, reason: f.path);
        expect(RegExp(r'\bRandom\b').hasMatch(text), isFalse, reason: f.path);
        expect(text.contains('dart:math'), isFalse, reason: f.path);
        expect(text.contains('dart:io'), isFalse, reason: f.path);
        expect(text.contains('drift'), isFalse, reason: f.path);
      }
    });
  });

  group('Pinned-Termine (ADR-0010 Punkt 4)', () {
    final g = goal(date: DateTime.utc(2027, 2, 14));
    final base = generatePlan(g, inputs(start: 150), const [], d0);
    List<PlanUnit> week1(GeneratedPlan p) => [
      for (final u in p.units)
        if (u.weekIndex == 1) u,
    ];
    final b1 = week1(base);
    PlanUnit of(PlanUnitKind k) => b1.firstWhere((u) => u.kind == k);
    PlanUnit pin(PlanUnit u, int dayOfNov) => PlanUnit(
      day: DateTime.utc(2026, 11, dayOfNov),
      kind: u.kind,
      phase: u.phase,
      weekIndex: u.weekIndex,
      minutes: u.minutes + 7, // alter Inhalt, wird neu gerechnet
      segments: [
        PlanSegment(kind: PlanSegmentKind.easy, minutes: u.minutes + 7),
      ],
      pinned: true,
    );

    test('Ausgangslage: Woche 1 hat Di hart, Do locker, Sa lang', () {
      expect([for (final u in b1) u.day.day], [17, 19, 21]);
      expect(b1.first.isHard, isTrue);
      expect(b1.last.kind, PlanUnitKind.long);
    });

    test('lockerer Lauf auf freien Tag: Tag gilt, Inhalt neu, Zahl bleibt', () {
      final easy = of(PlanUnitKind.easy);
      final p = generatePlan(
        g,
        inputs(start: 150),
        const [],
        d0,
        pinnedUnits: [pin(easy, 20)],
      );
      final w = week1(p);
      expect(w.length, b1.length);
      expect([for (final u in w) u.day.day], [17, 20, 21]);
      final moved = w.firstWhere((u) => u.day.day == 20);
      expect(moved.pinned, isTrue);
      expect(moved.kind, PlanUnitKind.easy);
      expect(moved.minutes, easy.minutes); // nicht die 7 min mehr des Pinned
      expect(p.pinnedConflicts, isEmpty);
      expect(p.units.length, base.units.length);
    });

    test('harte Einheit auf den Tag des lockeren Laufs: Tausch', () {
      final hard = b1.first;
      final p = generatePlan(
        g,
        inputs(start: 150),
        const [],
        d0,
        pinnedUnits: [pin(hard, 19)],
      );
      final w = week1(p);
      expect(
        [for (final u in w) '${u.day.day}:${u.kind.name}'],
        ['17:easy', '19:${hard.kind.name}', '21:long'],
      );
      expect(w[1].pinned, isTrue);
      expect(w[0].pinned, isFalse);
      expect(w[1].minutes, hard.minutes);
      expect(p.pinnedConflicts, isEmpty);
    });

    test('Abstand verletzt: Termin bleibt, Konflikt wird gemeldet', () {
      final hard = b1.first;
      final p = generatePlan(
        g,
        inputs(start: 150),
        const [],
        d0,
        pinnedUnits: [pin(hard, 20)],
      );
      final w = week1(p);
      expect(w.firstWhere((u) => u.isHard).day.day, 20);
      expect(p.pinnedConflicts, hasLength(1));
      final c = p.pinnedConflicts.single;
      expect(c.kind, PinnedConflictKind.spacing);
      expect(c.day, DateTime.utc(2026, 11, 20));
      expect(c.otherDay, DateTime.utc(2026, 11, 21));
    });

    test('langer Lauf auf einen Nicht-Lauftag, Tag davor wird frei', () {
      final long = of(PlanUnitKind.long);
      final p = generatePlan(
        g,
        inputs(start: 150),
        const [],
        d0,
        pinnedUnits: [pin(long, 22)],
      );
      final w = week1(p);
      expect([for (final u in w) u.day.day], [17, 19, 22]);
      expect(w.last.kind, PlanUnitKind.long);
      expect(p.pinnedConflicts, isEmpty);
    });

    test('Pinned auf eingefrorenem Tag: dayTaken, Einheit bleibt', () {
      final frozen = PlanUnit(
        day: DateTime.utc(2026, 11, 20),
        kind: PlanUnitKind.easy,
        phase: PlanPhase.build,
        weekIndex: 1,
        minutes: 30,
        segments: const [PlanSegment(kind: PlanSegmentKind.easy, minutes: 30)],
        runId: 5,
      );
      final p = generatePlan(
        g,
        inputs(start: 150),
        [frozen],
        d0,
        pinnedUnits: [pin(of(PlanUnitKind.easy), 20)],
      );
      expect(
        p.pinnedConflicts.map((c) => c.kind),
        contains(PinnedConflictKind.dayTaken),
      );
      expect(p.units.where((u) => u.pinned), isEmpty);
    });

    test('Pinned vor heute: noMatchingUnit', () {
      final p = generatePlan(
        g,
        inputs(start: 150),
        const [],
        d0,
        pinnedUnits: [pin(of(PlanUnitKind.easy), 10)],
      );
      expect(p.pinnedConflicts.single.kind, PinnedConflictKind.noMatchingUnit);
    });

    test('ohne Pinned: Ergebnis unverändert', () {
      final p = generatePlan(
        g,
        inputs(start: 150),
        const [],
        d0,
        pinnedUnits: const [],
      );
      expect(sigs(p.units), sigs(base.units));
      expect(p.pinnedConflicts, isEmpty);
    });
  });

  group('summarizeChange (PAR-204)', () {
    PlanUnit u(int day, PlanUnitKind k, int min, {int week = 0}) => PlanUnit(
      day: DateTime.utc(2026, 11, day),
      kind: k,
      phase: PlanPhase.build,
      weekIndex: week,
      minutes: min,
      segments: [PlanSegment(kind: PlanSegmentKind.easy, minutes: min)],
    );

    test('ohne Änderung leer und nicht größer', () {
      final a = [u(12, PlanUnitKind.easy, 30), u(14, PlanUnitKind.long, 40)];
      final s = summarizeChange(a, [...a]);
      expect(s.isEmpty, isTrue);
      expect(s.isLarger, isFalse);
      expect(s.headline, isNull);
    });

    test('Wochenzeit: 9 % kleiner, 10 % größer', () {
      final old = [u(12, PlanUnitKind.easy, 50), u(14, PlanUnitKind.long, 50)];
      final nine = [u(12, PlanUnitKind.easy, 46), u(14, PlanUnitKind.long, 45)];
      final ten = [u(12, PlanUnitKind.easy, 45), u(14, PlanUnitKind.long, 45)];
      final s9 = summarizeChange(old, nine);
      expect(s9.headline!.oldMinutes, 100);
      expect(s9.headline!.newMinutes, 91);
      expect(s9.changedUnits.length, 2);
      expect(s9.isLarger, isFalse);
      final s10 = summarizeChange(old, ten);
      expect(s10.isLarger, isTrue);
      expect(s10.headline!.relative, closeTo(0.10, 1e-12));
      // Zunahme zählt ebenso.
      expect(
        summarizeChange(ten, old).isLarger,
        isTrue,
      ); // 10 von 90 // 10/90 = 11 %? siehe unten
    });

    test('Wechsel hart/locker oder Einheit entfällt bzw. kommt hinzu', () {
      final easy = [u(12, PlanUnitKind.easy, 40), u(14, PlanUnitKind.easy, 40)];
      final withHard = [
        u(12, PlanUnitKind.easy, 40),
        u(14, PlanUnitKind.tempo, 40),
      ];
      final s = summarizeChange(easy, withHard);
      expect(s.weeks, isEmpty);
      expect(s.isLarger, isTrue);
      expect(s.changedUnits.single.changesClass, isTrue);
      // locker -> lang bleibt klein
      final longer = [
        u(12, PlanUnitKind.easy, 40),
        u(14, PlanUnitKind.long, 40),
      ];
      expect(summarizeChange(easy, longer).isLarger, isFalse);
      // entfällt / kommt hinzu
      expect(summarizeChange(easy, [easy[0]]).isLarger, isTrue);
      expect(summarizeChange([easy[0]], easy).isLarger, isTrue);
      // zu Ruhetag
      final rest = [easy[0], u(14, PlanUnitKind.rest, 0)];
      expect(summarizeChange(easy, rest).isLarger, isTrue);
    });

    test('toJson: höchstens maxUnits Einheiten', () {
      final old = [for (var d = 1; d <= 7; d++) u(d, PlanUnitKind.easy, 30)];
      final nw = [for (var d = 1; d <= 7; d++) u(d, PlanUnitKind.easy, 31)];
      final j = summarizeChange(old, nw).toJson();
      expect((j['changedUnits'] as List).length, 5);
      expect(j['changedUnitCount'], 7);
    });
  });
}

PlanUnit _withRun(PlanUnit u) => PlanUnit(
  day: u.day,
  kind: u.kind,
  phase: u.phase,
  weekIndex: u.weekIndex,
  minutes: u.minutes,
  segments: u.segments,
  runId: 99,
);
