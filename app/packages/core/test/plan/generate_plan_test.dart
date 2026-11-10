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
      final g = goal(days: {1, 3, 5, 7});
      final i = inputs(start: 200, today: DateTime.utc(2026, 11, 9));
      final full = generatePlan(g, i, const [], DateTime.utc(2026, 11, 9));
      final hardUnit = full.units.firstWhere(
        (u) => u.weekIndex == 0 && u.isHard,
        orElse: () => throw StateError('keine harte Einheit'),
      );
      // Eine andere harte Einheit schon gelaufen: Montag (nicht dort geplant).
      final other = hardUnit.day.weekday == 1
          ? full.units.firstWhere((u) => u.weekIndex == 0 && !u.isHard)
          : full.units.firstWhere(
              (u) => u.weekIndex == 0 && u.day.weekday == 1,
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
      final p = generatePlan(g, i, frozen, DateTime.utc(2026, 11, 10));
      expect(p.units.where((u) => u.weekIndex == 0 && u.isHard), isEmpty);
      expect(
        p.units.where((u) => u.weekIndex == 0).length,
        full.units
            .where(
              (u) =>
                  u.weekIndex == 0 &&
                  u.day.isAfter(DateTime.utc(2026, 11, 9)) &&
                  u.day != other.day,
            )
            .length,
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
    final base = generatePlan(g, inputs(), const [], d0);
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
        inputs(),
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
        inputs(),
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
        inputs(),
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
        inputs(),
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
        inputs(),
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
        inputs(),
        const [],
        d0,
        pinnedUnits: [pin(of(PlanUnitKind.easy), 10)],
      );
      expect(p.pinnedConflicts.single.kind, PinnedConflictKind.noMatchingUnit);
    });

    test('ohne Pinned: Ergebnis unverändert', () {
      final p = generatePlan(g, inputs(), const [], d0, pinnedUnits: const []);
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
