import 'dart:convert';
import 'dart:io';

import 'package:core/core.dart';
import 'package:test/test.dart';

final monday = DateTime.utc(2026, 11, 9);

PlanWeek week([int index = 0]) => PlanWeek(
  index: index,
  start: monday,
  minutes: null,
  phase: PlanPhase.entry,
  kind: WeekKind.walkRun,
);

int runSeconds(List<WalkRunStep> s) => s
    .where((x) => x.kind == WalkRunStepKind.run)
    .fold(0, (a, x) => a + x.seconds);
int allSeconds(List<WalkRunStep> s) => s.fold(0, (a, x) => a + x.seconds);

void main() {
  final p = walkRunProgram;
  final w = p.weeks;

  group('Datensatz (PAR-065, PAR-132 bis PAR-139)', () {
    test('9 Programmwochen mit je 3 Einheiten, Auf-/Abwärmen 5 min', () {
      expect(w.length, 9);
      expect(w.every((x) => x.sessions.length == 3), isTrue);
      expect(p.warmUpSeconds, 300);
      expect(p.coolDownSeconds, 300);
    });

    test('Woche 1: 8 Läufe zu 1:00, 7 Gehpausen zu 1:30', () {
      for (final s in w[0].sessions) {
        final runs = s.where((x) => x.kind == WalkRunStepKind.run).toList();
        final walks = s.where((x) => x.kind == WalkRunStepKind.walk).toList();
        expect(runs.length, 8);
        expect(walks.length, 7);
        expect(runs.every((x) => x.seconds == 60), isTrue);
        expect(walks.every((x) => x.seconds == 90), isTrue);
        expect(s.first.kind, WalkRunStepKind.run);
        expect(s.last.kind, WalkRunStepKind.run);
      }
    });

    test('Gesamtzeiten je Einheit inkl. 2 x 5 min Gehen', () {
      int total(int week, int s) =>
          allSeconds(w[week].sessions[s]) + p.warmUpSeconds + p.coolDownSeconds;
      // PAR-132 bis PAR-139 (Woche 1 aus PAR-065: 8 + 10,5 + 10 min).
      expect(total(0, 0), 28 * 60 + 30);
      expect(total(1, 0), 29 * 60);
      expect(total(2, 1), 25 * 60);
      expect(total(3, 2), 31 * 60 + 30);
      expect(
        [for (var s = 0; s < 3; s++) total(4, s)],
        [31 * 60, 31 * 60, 30 * 60],
      );
      expect(
        [for (var s = 0; s < 3; s++) total(5, s)],
        [34 * 60, 33 * 60, 35 * 60],
      );
      expect(total(6, 0), 35 * 60);
      expect(total(7, 1), 38 * 60);
      expect(total(8, 2), 40 * 60);
    });

    test('bis 30 min Dauerlauf in der letzten Woche', () {
      expect(runSeconds(w.last.sessions.first), 30 * 60);
      expect(w.last.sessions.first.length, 1);
    });

    test('Rechnung PAR-065: Laufminuten 27 -> 48, Gesamt 75 -> 94,5', () {
      int runs(int wk) => w[wk].sessions.fold(0, (a, s) => a + runSeconds(s));
      int all(int wk) => w[wk].sessions.fold(
        0,
        (a, s) => a + allSeconds(s) + p.warmUpSeconds + p.coolDownSeconds,
      );
      expect(runs(2) / 60, 27);
      expect(runs(3) / 60, 48);
      expect(all(2) / 60, 75);
      expect(all(3) / 60, 94.5);
      // Woche 5: längster Dauerlauf 8 -> 20 min.
      int longest(List<WalkRunStep> s) => s
          .where((x) => x.kind == WalkRunStepKind.run)
          .fold(0, (m, x) => x.seconds > m ? x.seconds : m);
      expect(longest(w[4].sessions[1]) / 60, 8);
      expect(longest(w[4].sessions[2]) / 60, 20);
    });
  });

  group('Einheiten', () {
    test('Woche 3 Tage: PlanUnits Art Geh-Lauf mit Sekunden-Abschnitten', () {
      final r = planWalkRunWeek(
        week: week(2),
        runDays: {1, 3, 5},
        position: const WalkRunPosition(1),
      );
      expect(r.units.length, 3);
      expect(r.units.map((u) => u.day.weekday), [1, 3, 5]);
      final u = r.units.first;
      expect(u.kind, PlanUnitKind.walkRun);
      expect(u.weekIndex, 2);
      expect(u.minutes, 29);
      expect(u.segments.first.kind, PlanSegmentKind.warmUp);
      expect(u.segments.first.durationSeconds, 300);
      expect(u.segments.last.kind, PlanSegmentKind.coolDown);
      expect(u.segments[1].kind, PlanSegmentKind.run);
      expect(u.segments[1].durationSeconds, 90);
      expect(u.segments[2].kind, PlanSegmentKind.walk);
      expect(u.segments[2].durationSeconds, 120);
      expect(u.segments.fold(0, (a, s) => a + s.durationSeconds), 29 * 60);
      expect(r.next, const WalkRunPosition(2));
      expect(r.finished, isFalse);
      expect(u.method, walkRunMethod);
      expect(u.methodVersion, p.version);
    });

    test(
      'ohne Sensor: nur Wochentage nötig, Eingaben enthalten keine Daten',
      () {
        final r = planWalkRunWeek(
          week: week(),
          runDays: {2, 4, 6},
          position: const WalkRunPosition(0),
        );
        expect(r.units.length, 3);
      },
    );

    test('Woche wiederholen statt weiter (PAR-140)', () {
      final forward = planWalkRunWeek(
        week: week(),
        runDays: {1, 3, 5},
        position: const WalkRunPosition(4),
      );
      final again = planWalkRunWeek(
        week: week(),
        runDays: {1, 3, 5},
        position: const WalkRunPosition(4),
        repeatWeek: true,
      );
      expect(again.units.map((u) => u.minutes), [31, 31, 30]);
      expect(again.next, const WalkRunPosition(5));
      // Wiederholen heißt: dieselbe Woche, danach geht es normal weiter.
      final repeatThenNext = planWalkRunWeek(
        week: week(1),
        runDays: {1, 3, 5},
        position: again.next,
      );
      expect(repeatThenNext.units.map((u) => u.minutes), [34, 33, 35]);
      expect(forward.next, again.next);
    });

    test('Wiederholen mitten in der Woche beginnt wieder bei Einheit 1', () {
      final r = planWalkRunWeek(
        week: week(),
        runDays: {1, 3, 5},
        position: const WalkRunPosition(4, 2),
        repeatWeek: true,
      );
      expect(r.units.map((u) => u.minutes), [31, 31, 30]);
      final cont = planWalkRunWeek(
        week: week(),
        runDays: {1, 3, 5},
        position: const WalkRunPosition(4, 2),
      );
      // Die Folge läuft in die nächste Programmwoche weiter (PAR-141).
      expect(cont.units.map((u) => u.minutes), [30, 34, 33]);
    });

    test('weniger Tage: 2 Tage = 1,5 Wochen, 1 Tag = 3 Wochen (PAR-141)', () {
      var pos = const WalkRunPosition(0);
      var weeks = 0;
      while (pos.week < 1) {
        pos = planWalkRunWeek(
          week: week(),
          runDays: {2, 5},
          position: pos,
        ).next;
        weeks++;
      }
      expect(weeks, 2); // 3 Einheiten + 1 der nächsten Programmwoche
      expect(pos, const WalkRunPosition(1, 1));

      pos = const WalkRunPosition(0);
      weeks = 0;
      while (pos.week < 1) {
        pos = planWalkRunWeek(week: week(), runDays: {3}, position: pos).next;
        weeks++;
      }
      expect(weeks, 3);
    });

    test(
      'zu kurze Zeit: Gehen davor/danach 3 min, sonst Hinweis (PAR-141)',
      () {
        final r = planWalkRunWeek(
          week: week(),
          runDays: {1, 3, 5},
          position: const WalkRunPosition(8),
          maxSessionMinutes: 38,
        );
        expect(r.units.first.minutes, 36);
        expect(r.units.first.segments.first.durationSeconds, 180);
        expect(r.units.first.segments.last.durationSeconds, 180);
        expect(r.exceedsMaxSession, isFalse);
        final tight = planWalkRunWeek(
          week: week(),
          runDays: {1, 3, 5},
          position: const WalkRunPosition(8),
          maxSessionMinutes: 30,
        );
        expect(tight.exceedsMaxSession, isTrue);
      },
    );

    test('mehr als 3 Tage: 3 Einheiten, gleichmäßig verteilt', () {
      final r = planWalkRunWeek(
        week: week(),
        runDays: {1, 2, 4, 6},
        position: const WalkRunPosition(0),
      );
      expect(r.units.map((u) => u.day.weekday), [1, 4, 6]);
    });

    test('Ende der Abfolge', () {
      final r = planWalkRunWeek(
        week: week(),
        runDays: {1, 3, 5},
        position: const WalkRunPosition(8),
      );
      expect(r.finished, isTrue);
      expect(r.units.length, 3);
      final after = planWalkRunWeek(
        week: week(),
        runDays: {1, 3, 5},
        position: r.next,
      );
      expect(after.units, isEmpty);
      expect(after.finished, isTrue);
    });

    test('Tag über Monatsgrenze', () {
      final r = planWalkRunWeek(
        week: PlanWeek(
          index: 0,
          start: DateTime.utc(2026, 11, 30),
          minutes: null,
          phase: PlanPhase.entry,
          kind: WeekKind.walkRun,
        ),
        runDays: {7},
        position: const WalkRunPosition(0),
      );
      expect(r.units.single.day, DateTime.utc(2026, 12, 6));
    });
  });

  group('Austauschbarkeit', () {
    test('anderer Datensatz liefert andere Einheiten ohne weiteren Code', () {
      const other = WalkRunProgram(
        version: 99,
        warmUpSeconds: 60,
        coolDownSeconds: 120,
        shortenedWalkSeconds: 30,
        weeks: [
          WalkRunWeekData([
            [WalkRunStep(WalkRunStepKind.run, 120)],
            [WalkRunStep(WalkRunStepKind.run, 240)],
          ]),
        ],
      );
      final r = planWalkRunWeek(
        week: week(),
        runDays: {1, 3, 5},
        position: const WalkRunPosition(0),
        program: other,
      );
      expect(r.units.map((u) => u.minutes), [5, 7]);
      expect(r.units.first.methodVersion, 99);
      expect(r.units.first.segments.map((s) => s.durationSeconds), [
        60,
        120,
        120,
      ]);
      expect(r.finished, isTrue);
    });
  });

  test('Methode und Version des Datensatzes registriert', () {
    final v = AlgorithmRegistry.standard().active(walkRunFamily);
    expect(v.method, walkRunMethod);
    expect(v.methodVersion, p.version);
  });

  test('kein Bezug auf die Vorlage im App-Verzeichnis', () {
    final root = Directory('../..'); // app/
    final hits = <String>[];
    final skip = RegExp(r'(\.dart_tool|/build/|/\.git/|/\.gradle/|/Pods/)');
    for (final e in root.listSync(recursive: true, followLinks: false)) {
      if (e is! File || skip.hasMatch(e.path)) continue;
      final name = e.path.toLowerCase();
      if (name.endsWith('.png') ||
          name.endsWith('.jar') ||
          name.endsWith('.db') ||
          name.endsWith('.so') ||
          name.endsWith('.ttf') ||
          name.endsWith('.zip')) {
        continue;
      }
      final text = latin1.decode(e.readAsBytesSync());
      if (text.toLowerCase().contains(needle)) hits.add(e.path);
    }
    expect(hits, isEmpty);
  });
}

// Der Suchbegriff wird zusammengesetzt, damit diese Datei sich nicht selbst
// findet.
final needle = ['n', 'h', 's'].join();
