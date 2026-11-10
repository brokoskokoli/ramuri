import 'dart:math';

import 'package:core/core.dart';
import 'package:test/test.dart';

final monday = DateTime.utc(2026, 11, 9);

PlanWeek week(
  int minutes, {
  WeekKind kind = WeekKind.climbing,
  PlanPhase phase = PlanPhase.build,
}) => PlanWeek(
  index: 3,
  start: monday,
  minutes: minutes,
  phase: phase,
  kind: kind,
);

PlannedWeek plan(
  int minutes,
  Set<int> days, {
  int max = 120,
  bool hard = false,
  bool c30 = true,
  int ordinal = 0,
  int? prev,
  WeekKind kind = WeekKind.climbing,
  PlanPhase phase = PlanPhase.build,
}) => planWeekUnits(
  week: week(minutes, kind: kind, phase: phase),
  runDays: days,
  maxSessionMinutes: max,
  hardEnabled: hard,
  continuous30: c30,
  hardOrdinal: ordinal,
  previousIntensiveWeekday: prev,
);

int _min(int a, int b) => a < b ? a : b;

List<int> mins(PlannedWeek w) => [for (final u in w.units) u.minutes];
List<PlanUnitKind> kinds(PlannedWeek w) => [for (final u in w.units) u.kind];
int sum(PlannedWeek w) => w.units.fold(0, (a, u) => a + u.minutes);

void main() {
  group('Beispiel FR-0151 / PAR-197: 3 Tage, 90 min', () {
    test('ohne Schalter: locker, locker, lang; 36 + 27 + 27', () {
      final w = plan(90, {2, 4, 6});
      expect(kinds(w), [
        PlanUnitKind.easy,
        PlanUnitKind.easy,
        PlanUnitKind.long,
      ]);
      expect(mins(w), [27, 27, 36]);
      expect(w.unplacedMinutes, 0);
      expect(w.hardOmission, isNull);
    });

    test(
      'mit Schalter, Form passt nicht in den Anteil: alles locker (PAR-197)',
      () {
        // Intervalle kurz = 36 min, gleichmäßiger Anteil nach dem langen Lauf
        // = 27 min: keine harte Einheit, Grund gemeldet (M3).
        final w = plan(90, {2, 4, 6}, hard: true);
        expect(w.units.any((u) => u.isHard), isFalse);
        expect(mins(w), [27, 27, 36]);
        expect(w.hardOmission, HardOmission.weekTooShort);
      },
    );

    test('auch in leichterer Woche (72 min): keine Intervalle', () {
      final w = plan(72, {2, 4, 6}, hard: true, kind: WeekKind.lighter);
      expect(w.units.any((u) => u.isHard), isFalse);
      expect(w.hardOmission, HardOmission.weekTooShort);
      expect(sum(w), 72);
    });

    test('mit Schalter, Form passt (150 min): eine harte Einheit', () {
      final w = plan(150, {2, 4, 6}, hard: true);
      expect(w.units.where((u) => u.isHard), hasLength(1));
      expect(w.units.where((u) => u.kind == PlanUnitKind.long), hasLength(1));
      expect(w.units.where((u) => u.kind == PlanUnitKind.easy), hasLength(1));
      expect(sum(w), 150);
      // Intervalle kurz: 10 + (12 + 9) + 5 = 36 min, Lauftage Di/Do/Sa.
      final h = w.units.firstWhere((u) => u.isHard);
      expect(h.kind, PlanUnitKind.intervals);
      expect(h.minutes, 36);
      expect(h.day, DateTime.utc(2026, 11, 10)); // Dienstag
    });

    test('1 Tag: lockerer Lauf; 2 Tage: locker und lang (60 %)', () {
      final one = plan(50, {3});
      expect(kinds(one), [PlanUnitKind.easy]);
      expect(mins(one), [50]);
      final two = plan(100, {2, 6});
      expect(kinds(two), [PlanUnitKind.easy, PlanUnitKind.long]);
      expect(mins(two), [40, 60]);
    });

    test('ab 4 Tagen: weitere lockere Läufe', () {
      final w = plan(200, {1, 3, 5, 7});
      expect(kinds(w).where((k) => k == PlanUnitKind.easy), hasLength(3));
      expect(mins(w).last, 80);
      expect(sum(w), 200);
    });
  });

  group('Langer Lauf und maximale Zeit (PAR-195, FR-0136)', () {
    test('längster Lauf = 40 % (3 Tage)', () {
      expect(plan(150, {1, 3, 5}).units.last.minutes, 60);
    });

    test('begrenzt auf die maximale Zeit; Rest fließt in die anderen', () {
      final w = plan(300, {1, 3, 5}, max: 90);
      expect(w.units.last.minutes, 90); // 120 wären 40 %
      expect(mins(w).sublist(0, 2), [90, 90]); // (300-90)/2 = 105 → 90
      expect(w.unplacedMinutes, 30);
    });

    test('ein Lauftag: Rest über der maximalen Zeit wird benannt', () {
      final w = plan(100, {4}, max: 60);
      expect(mins(w), [60]);
      expect(w.unplacedMinutes, 40);
    });
  });

  group('Harte Einheit (PAR-198)', () {
    test('Wechsel: Intervalle, Tempodauerlauf, progressiver Lauf', () {
      PlanUnitKind hardKind(int o) => plan(
        150,
        {1, 3, 5},
        hard: true,
        ordinal: o,
      ).units.firstWhere((u) => u.isHard).kind;
      expect(hardKind(0), PlanUnitKind.intervals);
      expect(hardKind(1), PlanUnitKind.tempo);
      expect(hardKind(2), PlanUnitKind.progressive);
      expect(hardKind(3), PlanUnitKind.intervals);
    });

    test('Struktur kurze Form: Aufwärmen 10, 4 × 3 min mit 3 min Trab, 5', () {
      final h = plan(150, {
        1,
        3,
        5,
      }, hard: true).units.firstWhere((u) => u.isHard);
      expect(
        [for (final s in h.segments) '${s.kind.name}${s.minutes}'],
        [
          'warmUp10',
          'interval3',
          'recovery3',
          'interval3',
          'recovery3',
          'interval3',
          'recovery3',
          'interval3',
          'coolDown5',
        ],
      );
      expect(h.segments.fold(0, (a, s) => a + s.minutes), h.minutes);
    });

    test('ab 3 h Wochenzeit die längere Form (6 × 3, 2 × 12, 15 min)', () {
      PlanUnit hard(int o, int total, {WeekKind k = WeekKind.climbing}) => plan(
        total,
        {1, 3, 5},
        hard: true,
        ordinal: o,
        kind: k,
        max: 150,
      ).units.firstWhere((u) => u.isHard);
      expect(
        hard(0, 180).segments.where((s) => s.kind == PlanSegmentKind.interval),
        hasLength(6),
      );
      expect(
        hard(
          1,
          180,
        ).segments.where((s) => s.kind == PlanSegmentKind.tempo).first.minutes,
        12,
      );
      expect(hard(2, 180).segments.last.minutes, 15);
      // Unter 3 h und in leichter Woche: kürzere Form.
      expect(
        hard(0, 179).segments.where((s) => s.kind == PlanSegmentKind.interval),
        hasLength(4),
      );
      expect(
        hard(
          0,
          240,
          k: WeekKind.lighter,
        ).segments.where((s) => s.kind == PlanSegmentKind.interval),
        hasLength(4),
      );
      expect(
        plan(
              240,
              {1, 3, 5},
              hard: true,
              phase: PlanPhase.reduction,
              kind: WeekKind.reduction,
              max: 150,
            ).units
            .firstWhere((u) => u.isHard)
            .segments
            .where((s) => s.kind == PlanSegmentKind.interval),
        hasLength(4),
      );
    });

    test('Bedingungen: ab 3 Läufen, 30 min am Stück, Schalter', () {
      expect(
        plan(100, {1, 5}, hard: true).hardOmission,
        HardOmission.tooFewRunDays,
      );
      expect(
        plan(100, {1, 3, 5}, hard: true, c30: false).hardOmission,
        HardOmission.notContinuous30,
      );
      final off = plan(100, {1, 3, 5});
      expect(off.units.any((u) => u.isHard), isFalse);
      expect(off.hardOmission, isNull);
    });

    test('passt nicht in die maximale Zeit: lockerer Lauf', () {
      final w = plan(150, {1, 3, 5}, hard: true, max: 35);
      expect(w.units.any((u) => u.isHard), isFalse);
      expect(w.hardOmission, HardOmission.exceedsMaxSession);
      expect(w.units.every((u) => u.minutes <= 35), isTrue);
    });

    test('progressiver Lauf: Endblock am Ende, mindestens 30 min', () {
      final h = plan(
        120,
        {1, 3, 5},
        hard: true,
        ordinal: 2,
      ).units.firstWhere((u) => u.isHard);
      expect(h.minutes, greaterThanOrEqualTo(30));
      expect(h.segments.last.kind, PlanSegmentKind.endBlock);
      expect(h.segments.last.minutes, 10);
    });

    test('Zielintensität ist noch leer (Teil D)', () {
      final w = plan(150, {1, 3, 5}, hard: true);
      expect(
        w.units.every((u) => u.segments.every((s) => s.intensity == null)),
        isTrue,
      );
    });
  });

  group('Abstand intensiver Einheiten (FR-0152, PAR-058/059)', () {
    test('lang und hart nie an Nachbartagen, wenn es anders geht', () {
      // Mo, Di, Fr: lang Fr, hart Mo (Di wäre kein Problem zu Fr; Mo größter Abstand).
      final w = plan(150, {1, 2, 5}, hard: true);
      final h = w.units.firstWhere((u) => u.isHard);
      expect(h.day, DateTime.utc(2026, 11, 9));
    });

    test('Lauftage Mo, Di, Mi nach intensivem Sonntag: keine harte', () {
      final w = plan(150, {1, 2, 3}, hard: true, prev: 7);
      expect(w.units.any((u) => u.isHard), isFalse);
      expect(w.hardOmission, HardOmission.noRecoveryDay);
      expect(w.units.where((u) => u.isIntensive), hasLength(1));
    });

    test('Wochenwechsel: harte Einheit am Sonntag, Montag nicht intensiv', () {
      // Lauftage Mo, Mi, So: lang So; Vorwoche intensiv am Sonntag (7).
      final w = plan(150, {1, 3, 7}, hard: true, prev: 7);
      final h = w.units.firstWhere((u) => u.isHard);
      expect(h.day, DateTime.utc(2026, 11, 11)); // Mi, nicht Mo
    });

    test('langer Lauf liegt am spätesten Lauftag, also nach der Vorwoche', () {
      final a = plan(150, {1, 3, 7}, prev: 7);
      expect(
        a.units.firstWhere((u) => u.kind == PlanUnitKind.long).day,
        DateTime.utc(2026, 11, 15),
      );
    });
  });

  group('Eigenschaften über viele Eingaben', () {
    test('Zeit, Maximum, Abstand, Härte, Lauftage', () {
      final rnd = Random(21);
      for (var i = 0; i < 4000; i++) {
        final days = <int>{};
        final count = 1 + rnd.nextInt(7);
        while (days.length < count) {
          days.add(1 + rnd.nextInt(7));
        }
        final total = 20 * count + rnd.nextInt(500);
        final max = 20 + rnd.nextInt(180);
        final kind = WeekKind.values[1 + rnd.nextInt(4)];
        final prev = rnd.nextBool() ? null : 1 + rnd.nextInt(7);
        final w = plan(
          total,
          days,
          max: max,
          hard: rnd.nextBool(),
          c30: rnd.nextInt(4) != 0,
          ordinal: rnd.nextInt(9),
          prev: prev,
          kind: kind,
        );
        final ctx = 'W=$total max=$max days=$days prev=$prev $kind';
        expect(sum(w) + w.unplacedMinutes, total, reason: ctx);
        expect(sum(w), lessThanOrEqualTo(total), reason: ctx);
        expect(w.units.length, count, reason: ctx);
        for (final u in w.units) {
          expect(u.minutes, lessThanOrEqualTo(max), reason: ctx);
          expect(u.minutes, greaterThan(0), reason: ctx);
          expect(days, contains(u.day.weekday), reason: ctx);
          expect(
            u.segments.fold(0, (a, s) => a + s.minutes),
            u.minutes,
            reason: ctx,
          );
        }
        expect(
          w.units.where((u) => u.isHard).length,
          lessThanOrEqualTo(1),
          reason: ctx,
        );
        expect(w.units.map((u) => u.day).toSet().length, count, reason: ctx);
        final hard = w.units.where((u) => u.isHard);
        if (hard.isNotEmpty) {
          expect(count, greaterThanOrEqualTo(3), reason: ctx);
          // Keine lockere Einheit kürzer als der gleichmäßige Anteil wegen
          // der harten Einheit (PAR-197, M3).
          final long = w.units.firstWhere((u) => u.kind == PlanUnitKind.long);
          final slot = (total - long.minutes) ~/ (count - 1);
          for (final u in w.units.where((u) => u.kind == PlanUnitKind.easy)) {
            expect(
              u.minutes,
              greaterThanOrEqualTo(_min(slot, max)),
              reason: ctx,
            );
          }
          expect(hard.first.minutes, lessThanOrEqualTo(slot), reason: ctx);
        }
        // Abstand: keine zwei intensiven an Nachbartagen (auch zur Vorwoche),
        // außer wenn gemeldet.
        final inten = [
          for (final u in w.units)
            if (u.isIntensive) u.day.weekday,
        ];
        for (var a = 0; a < inten.length; a++) {
          for (var b = a + 1; b < inten.length; b++) {
            expect(
              (inten[a] - inten[b]).abs(),
              greaterThanOrEqualTo(2),
              reason: ctx,
            );
          }
        }
        if (prev != null) {
          for (final d in inten) {
            expect(d - (prev - 7), greaterThanOrEqualTo(2), reason: ctx);
          }
        }
      }
    });

    test('Woche ohne Minuten (Geh-Lauf) liefert keine Einheiten', () {
      final w = planWeekUnits(
        week: PlanWeek(
          index: 0,
          start: monday,
          minutes: null,
          phase: PlanPhase.entry,
          kind: WeekKind.walkRun,
        ),
        runDays: {1, 3, 5},
        maxSessionMinutes: 60,
        hardEnabled: false,
        continuous30: false,
      );
      expect(w.units, isEmpty);
    });
  });

  test('Methode weiterhin über die Registry', () {
    final v = AlgorithmRegistry.standard().active(planFamily);
    expect(v.method, planMethod);
    expect(week(10).minutes, 10);
  });
}
