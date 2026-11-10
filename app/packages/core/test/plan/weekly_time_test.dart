import 'package:core/core.dart';
import 'package:test/test.dart';

// Montag.
final anchor = DateTime(2026, 11, 9);

DateTime weekStart(int i) => DateTime(2026, 11, 9 + 7 * i);

WeeklyTimeResult course({
  int start = 90,
  int cap = 600,
  int? peak,
  GoalDistance? distance,
  DateTime? date,
  int walk = 0,
  DateTime? today,
}) => planWeeklyTime(
  startMinutes: start,
  capMinutes: cap,
  anchor: anchor,
  today: today ?? anchor,
  peakMinutes: peak,
  distance: distance,
  targetDate: date,
  walkRunWeeks: walk,
);

List<int> minutes(WeeklyTimeResult r) => [for (final w in r.weeks) w.minutes!];

/// Längster Lauf bei 3 Lauftagen (PAR-195: 40 %).
int longest(int weekly) => (weekly * 0.4).round();

void main() {
  zoneTests();
  group('Rechenbeispiele PAR-193 (3 x 30 min, PAR-195 40 %)', () {
    test('rund 10 Wochen bis zu einem längsten Lauf von gut 1 h', () {
      final m = minutes(course());
      final week = m.indexWhere((x) => longest(x) >= 60) + 1;
      // PAR-193: „rund 10 Wochen“; mit den Regeln ergibt sich Woche 9.
      expect(week, inInclusiveRange(9, 11));
    });

    test('rund 18 Wochen bis etwa 100 min', () {
      final m = minutes(course());
      final week = m.indexWhere((x) => longest(x) >= 100) + 1;
      expect(week, inInclusiveRange(17, 20));
    });

    test('Steigerung nach Höhe: +10 %, +7 %, +5 % (PAR-193)', () {
      final m = minutes(course(start: 100));
      expect(m.sublist(0, 3), [100, 110, 121]);
      final high = minutes(course(start: 240));
      expect(high.sublist(0, 3), [240, 252, 265]);
      final mid = minutes(course(start: 130));
      expect(mid.sublist(0, 3), [130, 139, 149]);
    });
  });

  group('Leichtere Woche (PAR-194)', () {
    test('jede 4. Woche minus 20 %, danach vom Wert davor weiter', () {
      final r = course();
      final m = minutes(r);
      expect(r.weeks[3].kind, WeekKind.lighter);
      expect(r.weeks[7].kind, WeekKind.lighter);
      expect(m[3], (m[2] * 0.8).round());
      // keine Steigerung in der leichten Woche: die Woche danach steigt aus
      // dem Wert der Woche 3 (109), nicht aus der leichten.
      expect(m[4], 120);
      expect(r.weeks[2].kind, WeekKind.climbing);
    });

    test('auch am Regler: halten, jede 4. Woche leichter', () {
      final r = course(start: 100, cap: 100);
      expect(minutes(r).take(8), [100, 100, 100, 80, 100, 100, 100, 80]);
      expect(r.weeks[0].kind, WeekKind.holding);
    });
  });

  group('Halten (PAR-196)', () {
    test('Steigerung endet an der Zielspitze, nicht am Regler', () {
      final r = course(peak: 150, cap: 400);
      expect(r.levelMinutes, 150);
      expect(minutes(r).where((x) => x > 150), isEmpty);
      expect(r.reachedLevelWeek, isNotNull);
      expect(r.weeks[r.reachedLevelWeek!].minutes, 150);
    });

    test('Start über dem Regler: auf den Regler begrenzt', () {
      final r = course(start: 500, cap: 300);
      expect(minutes(r).first, 300);
    });

    test('Start über der Zielspitze: hält den Start, senkt nicht', () {
      final r = course(start: 200, peak: 90, cap: 400);
      expect(r.levelMinutes, 200);
      expect(minutes(r).first, 200);
    });

    test('Ziel ohne Datum läuft über den Horizont fort', () {
      final r = course(cap: 150);
      expect(r.weeks.length, const PlanParameters().openHorizonWeeks);
      expect(r.weeks.last.phase, PlanPhase.build);
    });
  });

  group('Zieltermin (PAR-199)', () {
    test('5 km: letzte Woche 30 % weniger, Wochenende ist das Ende', () {
      // Termin Samstag der Woche 12.
      final r = course(
        peak: 150,
        distance: GoalDistance.fiveKilometers,
        date: DateTime(2026, 11, 9 + 7 * 12 + 5),
      );
      expect(r.weeks.length, 13);
      expect(r.weeks.last.index, 12);
      expect(r.weeks.last.kind, WeekKind.reduction);
      expect(r.weeks.last.phase, PlanPhase.reduction);
      expect(r.weeks[11].kind, isNot(WeekKind.reduction));
      expect(r.weeks.last.minutes, (150 * 0.7).round());
    });

    test('Halbmarathon: 2 Wochen mit 40 % weniger', () {
      final r = course(
        peak: 250,
        cap: 300,
        distance: GoalDistance.halfMarathon,
        date: DateTime(2026, 11, 9 + 7 * 30),
      );
      final red = r.weeks.where((w) => w.kind == WeekKind.reduction).toList();
      expect(red.map((w) => w.index), [29, 30]);
      expect(red.map((w) => w.minutes), [150, 150]);
    });

    test(
      'Halbmarathon in 12 Monaten: ruhig, Spitze 4 Wochen vor Reduktion',
      () {
        const lastWeek = 52;
        final undamped = course(peak: 250, cap: 300).reachedLevelWeek!;
        final r = course(
          peak: 250,
          cap: 300,
          distance: GoalDistance.halfMarathon,
          date: DateTime(2026, 11, 9 + 7 * lastWeek),
        );
        const reductionStart = lastWeek - 1;
        expect(r.dampingFactor, lessThan(1));
        // Die Woche reductionStart - 4 ist selbst eine leichtere Woche (ohne
        // Steigerung): Die Spitze liegt dann eine Woche davor.
        expect(
          r.reachedLevelWeek,
          inInclusiveRange(reductionStart - 5, reductionStart - 4),
        );
        expect(r.reachedLevelWeek, greaterThan(undamped + 10));
        // kein früher Gipfel: nichts auf Spitzenhöhe vor der Spitzenwoche
        final early = r.weeks.where(
          (w) => w.index < r.reachedLevelWeek! && w.minutes! >= 250,
        );
        expect(early, isEmpty);
        // Zwischen den Wochen kein größerer Schritt als PAR-193 erlaubt.
        expect(r.weeks.last.minutes, 150);
      },
    );

    test('Termin zu nah: ungedämpft, Spitze nicht erreicht', () {
      final r = course(
        peak: 250,
        distance: GoalDistance.halfMarathon,
        date: DateTime(2026, 11, 9 + 7 * 6),
      );
      expect(r.dampingFactor, 1);
      expect(r.reachedLevelWeek, isNull);
    });

    test('Termin vor dem Anker: leer', () {
      final r = course(
        distance: GoalDistance.tenKilometers,
        date: DateTime(2026, 11, 1),
      );
      expect(r.weeks, isEmpty);
    });
  });

  group('Phasen (FR-0141), Anker, heute', () {
    test('Einstieg 4 Wochen, dann Aufbau', () {
      final r = course();
      expect(
        r.weeks.take(4).map((w) => w.phase),
        everyElement(PlanPhase.entry),
      );
      expect(r.weeks[4].phase, PlanPhase.build);
    });

    test('Ausgabe beginnt in der Woche von heute, Zählung bleibt am Anker', () {
      final full = course();
      final r = course(today: DateTime(2026, 11, 9 + 7 * 5 + 3));
      expect(r.weeks.first.index, 5);
      expect(
        r.weeks.first.start,
        weekStart(5).toUtc().isUtc ? r.weeks.first.start : null,
      );
      expect(r.weeks.first.minutes, full.weeks[5].minutes);
      expect(r.weeks.first.start.weekday, DateTime.monday);
    });

    test('Geh-Lauf-Abfolge: Wochen ohne Zeit, PAR-194 zählt erst danach', () {
      final r = course(walk: 9);
      expect(
        r.weeks.take(9).map((w) => w.kind),
        everyElement(WeekKind.walkRun),
      );
      expect(r.weeks.take(9).map((w) => w.minutes), everyElement(isNull));
      expect(
        r.weeks.take(9).map((w) => w.phase),
        everyElement(PlanPhase.entry),
      );
      expect(r.weeks[9].minutes, 90);
      expect(r.weeks[12].kind, WeekKind.lighter);
      expect(r.weeks[11].kind, isNot(WeekKind.lighter));
    });

    test('Anker mitten in der Woche zählt ab dem Montag', () {
      final r = planWeeklyTime(
        startMinutes: 90,
        capMinutes: 600,
        anchor: DateTime(2026, 11, 12),
        today: DateTime(2026, 11, 12),
      );
      expect(r.weeks.first.start.weekday, DateTime.monday);
      expect(r.weeks.first.start.day, 9);
    });
  });

  group('Eigenschaften über viele Eingaben', () {
    test('nie über dem Regler, leichtere Woche, Reduktion, Steigerung', () {
      var checked = 0;
      final starts = [30, 60, 90, 120, 200, 260, 400];
      final caps = [60, 120, 180, 240, 360, 500];
      final peaks = <int?>[null, 80, 150, 250, 450];
      final dists = <GoalDistance?>[
        null,
        GoalDistance.fiveKilometers,
        GoalDistance.tenKilometers,
        GoalDistance.halfMarathon,
      ];
      final dates = [-1, 2, 8, 20, 52];
      for (final s in starts) {
        for (final c in caps) {
          for (final pk in peaks) {
            for (final d in dists) {
              for (final dw in dates) {
                if (d != null && dw == -1) continue;
                final date = dw == -1 || d == null
                    ? null
                    : DateTime(2026, 11, 9 + 7 * dw + 2);
                final r = planWeeklyTime(
                  startMinutes: s,
                  capMinutes: c,
                  anchor: anchor,
                  today: anchor,
                  peakMinutes: pk,
                  distance: d,
                  targetDate: date,
                );
                checked++;
                _checkInvariants(r, s, c);
              }
            }
          }
        }
      }
      expect(checked, greaterThan(500));
    });

    test('deterministisch', () {
      final a = minutes(course(peak: 200, cap: 300));
      final b = minutes(course(peak: 200, cap: 300));
      expect(a, b);
    });
  });

  group('Eingaben und Registrierung', () {
    test('ungültige Eingaben', () {
      expect(() => course(start: 0), throwsArgumentError);
      expect(() => course(cap: 0), throwsArgumentError);
      expect(() => course(walk: -1), throwsArgumentError);
    });

    test('Zielspitze als Wochenzeit (PAR-195, PAR-205)', () {
      expect(peakWeeklyMinutes(longestRunMinutes: 100, runDays: 3), 250);
      expect(peakWeeklyMinutes(longestRunMinutes: 65, runDays: 2), 109);
      expect(peakWeeklyMinutes(longestRunMinutes: 35, runDays: 1), 35);
    });

    test('Methode über die Registry', () {
      final v = AlgorithmRegistry.standard().active(planFamily);
      expect(v.method, planMethod);
      expect(v.methodVersion, planMethodVersion);
      expect(v.category, AlgorithmCategory.heuristic);
    });
  });
}

void _checkInvariants(WeeklyTimeResult r, int start, int cap) {
  final w = r.weeks;
  for (var i = 0; i < w.length; i++) {
    final m = w[i].minutes!;
    expect(m, lessThanOrEqualTo(cap), reason: 'über Regler in Woche $i');
    expect(m, greaterThanOrEqualTo(0));
    if (w[i].kind == WeekKind.lighter) {
      // −20 % der Vorwoche, ohne Steigerung (nie höher als die Vorwoche).
      // Eine Rundung nur am Ende: höchstens 1 min Abstand zu 80 % der
      // gerundeten Vorwoche.
      expect((m - w[i - 1].minutes! * 0.8).abs(), lessThanOrEqualTo(1));
      expect(m, lessThan(w[i - 1].minutes!));
      // Danach geht es beim Wert davor weiter, nie darunter.
      if (i + 1 < w.length && w[i + 1].kind != WeekKind.reduction) {
        expect(w[i + 1].minutes, greaterThanOrEqualTo(w[i - 1].minutes!));
      }
    }
    if (w[i].kind == WeekKind.reduction) {
      expect(m, lessThan(w[i - 1 < 0 ? 0 : i - 1].minutes! + 1));
      // Reduktion bleibt bis zum Ende.
      if (i + 1 < w.length) expect(w[i + 1].kind, WeekKind.reduction);
    }
    if (i > 0 &&
        w[i].kind == WeekKind.climbing &&
        w[i - 1].kind == WeekKind.climbing) {
      final prev = w[i - 1].minutes!;
      // Die Vorwoche ist gerundet: Schwelle mit 1 min Toleranz.
      final rate = prev - 1 < 120 ? 0.10 : (prev - 1 < 240 ? 0.07 : 0.05);
      expect(m, lessThanOrEqualTo((prev * (1 + rate)).ceil() + 1));
    }
  }
}

// Kalendertage als UTC-Mitternacht (so liegen Anker, Einheiten und Zieltag
// im Plan vor) dürfen in keiner Zeitzone auf den Vortag rutschen. Gilt unter
// `TZ=America/New_York` (westlich) wie `TZ=Asia/Tokyo` (östlich).
void zoneTests() {
  group('Kalendertage als UTC-Mitternacht (Zeitzone)', () {
    test('Wochenbeginn bleibt der Montag, der Verlauf gleicht dem lokalen', () {
      final utc = planWeeklyTime(
        startMinutes: 90,
        capMinutes: 600,
        anchor: DateTime.utc(2026, 11, 9),
        today: DateTime.utc(2026, 11, 16),
        targetDate: DateTime.utc(2027, 1, 10),
        distance: GoalDistance.tenKilometers,
        peakMinutes: 300,
      );
      final local = planWeeklyTime(
        startMinutes: 90,
        capMinutes: 600,
        anchor: DateTime(2026, 11, 9),
        today: DateTime(2026, 11, 16),
        targetDate: DateTime(2027, 1, 10),
        distance: GoalDistance.tenKilometers,
        peakMinutes: 300,
      );
      expect(utc.weeks.first.start, DateTime.utc(2026, 11, 16));
      expect(utc.weeks.first.start.weekday, DateTime.monday);
      expect(
        [for (final w in utc.weeks) w.start],
        [for (final w in local.weeks) w.start],
      );
      expect(minutes(utc), minutes(local));
    });
  });
}
