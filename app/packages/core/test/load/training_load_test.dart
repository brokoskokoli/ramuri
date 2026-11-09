import 'package:core/core.dart';
import 'package:test/test.dart';

final _d0 = DateTime.utc(2026, 1, 1);
DateTime _d(int n) => _d0.add(Duration(days: n));

LoadUnit _run(int day, double trimp) =>
    LoadUnit.run(day: _d(day), trimp: trimp);

TrainingLoadSeries _calc(
  List<LoadUnit> units, {
  required int today,
  double? factor,
  bool commit = true,
  Map<DateTime, int>? expected,
  Set<DateTime> pauses = const {},
}) => computeTrainingLoad(
  profile: LoadProfile.edwards,
  units: units,
  factor: factor,
  confirmsAllRecorded: commit,
  today: _d(today),
  expectedUnitsPerDay: expected,
  confirmedPauseDays: pauses,
);

List<LoadUnit> _daily(int from, int to, [double l = 50]) => [
  for (var i = from; i <= to; i++) _run(i, l),
];

void main() {
  group('Formeln', () {
    test('FR-0098: ATL 70, L 140 -> 80', () {
      expect(nextAtl(70, 140), 80);
    });
    test('FR-0099: CTL 42, L 84 -> 43', () {
      expect(nextCtl(42, 84), 43);
    });
    test('FR-0101: CTL 50, ATL 70 -> TSB -20', () {
      expect(trainingStressBalance(ctlPrevious: 50, atlPrevious: 70), -20);
    });
  });

  group('Reihe', () {
    test('Start 0 am ersten bewerteten Tag, TSB aus dem Vortag', () {
      final r = _calc([_run(0, 490), _run(1, 140)], today: 1);
      expect(r.days[0].atl, closeTo(70, 1e-9));
      expect(r.days[0].ctl, closeTo(490 / 42, 1e-9));
      expect(r.days[0].tsb, 0); // Vortag: 0 - 0
      expect(r.days[1].atl, closeTo(80, 1e-9)); // FR-0098 in der Reihe
      expect(r.days[1].tsb, closeTo(490 / 42 - 70, 1e-9)); // FR-0101
      expect(r.method, trainingLoadMethod);
      expect(r.methodVersion, 1);
      expect(r.profile, LoadProfile.edwards);
    });

    test('CTL in der Reihe: 1764 -> 42, dann 84 -> 43', () {
      final r = _calc([_run(0, 1764), _run(1, 84)], today: 1);
      expect(r.days[0].ctl, closeTo(42, 1e-9));
      expect(r.days[1].ctl, closeTo(43, 1e-9));
    });

    test('Mehrere Einheiten am Tag addieren sich', () {
      final r = _calc([_run(0, 30), _run(0, 40)], today: 0);
      expect(r.days.single.load, 70);
      expect(r.days.single.atl, closeTo(10, 1e-9));
    });

    test('TSB%: auf CTL des Vortags, 7-Tage-Mittel nur mit 7 Werten', () {
      final r = _calc(_daily(0, 20), today: 20);
      // Tag 0: CTL[-1]=0 -> kein TSB%; Mittel erst, wenn 7 Werte da sind.
      expect(r.days[6].tsbPercentMean7, isNull);
      expect(r.days[7].tsbPercentMean7, isNotNull); // Fenster 1..7
      // Handrechnung Tag 8: Mittel der TSB% der Tage 2..8.
      var a = 0.0, c = 0.0;
      final pct = <double?>[];
      for (var i = 0; i <= 8; i++) {
        final t = c - a;
        pct.add(c > 0 ? t / c * 100 : null);
        a = nextAtl(a, 50);
        c = nextCtl(c, 50);
      }
      final expected = pct.sublist(2, 9).reduce((x, y) => x! + y!)! / 7;
      expect(r.days[8].tsbPercentMean7, closeTo(expected, 1e-9));
    });
  });

  group('Unbewertet, umgerechnet, nachgetragen (OQ-0054, FR-0199)', () {
    test('unbewerteter Tag: ATL/CTL unverändert, gekennzeichnet, nicht 0', () {
      final r = _calc([
        _run(0, 70),
        LoadUnit.run(day: _d(1)), // kein Puls, kein RPE
        _run(2, 70),
      ], today: 2);
      final d0 = r.days[0], d1 = r.days[1];
      expect(d1.load, isNull);
      expect(d1.atl, d0.atl);
      expect(d1.ctl, d0.ctl);
      expect(d1.flags, {LoadDayFlag.unrated});
      expect(d1.tsb, closeTo(d0.ctl! - d0.atl!, 1e-12));
      expect(r.days[2].atl, closeTo(nextAtl(d0.atl!, 70), 1e-12));
      expect(r.summary.unratedUnits, 1);
      expect(r.summary.unratedDays, 1);
    });

    test(
      'Tag mit bewerteter und unbewerteter Einheit gilt ganz als unbewertet',
      () {
        final r = _calc([
          _run(0, 70),
          _run(1, 100),
          LoadUnit.run(day: _d(1)),
        ], today: 1);
        expect(r.days[1].load, isNull);
        expect(r.days[1].atl, r.days[0].atl);
        expect(r.days[1].ratedUnits, 1);
        expect(r.days[1].unratedUnits, 1);
      },
    );

    test(
      'Lauf ohne Puls: sRPE ohne Faktor unbewertet, mit Faktor umgerechnet',
      () {
        final unit = LoadUnit.run(day: _d(1), srpePoints: 300);
        final without = _calc([_run(0, 70), unit], today: 1);
        expect(without.days[1].flags, {LoadDayFlag.unrated});
        expect(without.days[1].load, isNull);

        final withF = _calc([_run(0, 70), unit], today: 1, factor: 0.5);
        expect(withF.days[1].load, 150);
        expect(withF.days[1].flags, {LoadDayFlag.converted});
        expect(withF.days[1].atl, closeTo(nextAtl(10, 150), 1e-12));
        expect(withF.summary.convertedUnits, 1);
      },
    );

    test('ungültiger Faktor (0, negativ, NaN) gilt als keiner', () {
      for (final f in [0.0, -1.0, double.nan]) {
        final r = _calc(
          [LoadUnit.run(day: _d(0), srpePoints: 300)],
          today: 0,
          factor: f,
        );
        expect(r.factor, isNull);
        expect(r.days.single.flags, {LoadDayFlag.unrated});
      }
    });

    test('Lauf mit Puls bleibt TRIMP, auch wenn RPE und Faktor da sind', () {
      final r = _calc(
        [LoadUnit.run(day: _d(0), trimp: 60, srpePoints: 999)],
        today: 0,
        factor: 1,
      );
      expect(r.days.single.load, 60);
      expect(r.days.single.flags, isEmpty);
    });

    test('nachgetragenes Training zählt mit Faktor, gekennzeichnet', () {
      final r = _calc(
        [_run(0, 70), LoadUnit.manual(day: _d(1), srpePoints: 200)],
        today: 1,
        factor: 0.5,
      );
      expect(r.days[1].load, 100);
      expect(r.days[1].flags, {LoadDayFlag.converted});
      expect(r.days[1].atl, closeTo(nextAtl(10, 100), 1e-12));
    });

    test('nachgetragenes Training ohne Faktor oder RPE: unbewertet', () {
      final a = _calc([
        _run(0, 70),
        LoadUnit.manual(day: _d(1), srpePoints: 200),
      ], today: 1);
      expect(a.days[1].flags, {LoadDayFlag.unrated});
      final b = _calc(
        [_run(0, 70), LoadUnit.manual(day: _d(1))],
        today: 1,
        factor: 0.5,
      );
      expect(b.days[1].flags, {LoadDayFlag.unrated});
    });

    test('Einheiten nach heute zählen nie (Lauf und Nachtrag)', () {
      final base = _calc([_run(0, 70)], today: 3, factor: 1);
      final r = _calc(
        [
          _run(0, 70),
          LoadUnit.manual(day: _d(4), srpePoints: 900),
          _run(5, 900),
        ],
        today: 3,
        factor: 1,
      );
      expect(r.days.length, base.days.length);
      expect(r.days.last.day, _d(3));
      expect(r.days.last.atl, base.days.last.atl);
      expect(r.days.last.ctl, base.days.last.ctl);
      expect(r.summary.lastUnitDay, _d(0));
      // Nicht nur über den Index (RangeError), sondern an den Werten: keine
      // Einheit der Zukunft taucht in Zählern, Lasten oder Kennzeichen auf.
      expect(r.summary.unratedUnits, 0);
      expect(r.summary.convertedUnits, 0);
      expect(r.summary.unratedUnits, base.summary.unratedUnits);
      expect(r.summary.convertedUnits, base.summary.convertedUnits);
      expect(
        [for (final d in r.days) d.load],
        [for (final d in base.days) d.load],
      );
      expect(
        [for (final d in r.days) d.flags],
        [for (final d in base.days) d.flags],
      );
      expect(r.days.map((d) => d.day), isNot(contains(_d(4))));
      expect(r.days.map((d) => d.day), isNot(contains(_d(5))));
      // nur Zukunft: keine Aussage
      final only = _calc(
        [LoadUnit.manual(day: _d(4), srpePoints: 9)],
        today: 3,
        factor: 1,
      );
      expect(only.days, isEmpty);
      expect(only.summary.hasStatement, isFalse);
    });

    test('Uhrzeit der Einheit ändert den Tag nicht', () {
      final r = _calc([
        LoadUnit.run(day: DateTime(2026, 1, 3, 23, 59), trimp: 70),
      ], today: 1);
      expect(r.days, isEmpty); // 3. Januar liegt nach heute (2. Januar)
    });
  });

  group('Leere Tage (FR-0103, OQ-0058)', () {
    test('mit Zusage: leerer Tag ist Last 0, ATL sinkt', () {
      final r = _calc([_run(0, 70)], today: 2);
      expect(r.days[1].load, 0);
      expect(r.days[1].atl, closeTo(nextAtl(10, 0), 1e-12));
      expect(r.days[1].flags, isEmpty);
    });

    test('ohne Zusage: leerer Tag unverändert, gekennzeichnet', () {
      final r = _calc([_run(0, 70)], today: 2, commit: false);
      expect(r.days[1].load, isNull);
      expect(r.days[1].atl, r.days[0].atl);
      expect(r.days[1].ctl, r.days[0].ctl);
      expect(r.days[1].flags, {LoadDayFlag.emptyUnchanged});
    });

    test('ohne Zusage dauerhaft vorläufig, auch nach 200 Tagen', () {
      final r = _calc(_daily(0, 200), today: 200, commit: false);
      final d = r.days.last;
      expect(d.ctlProvisionalReasons, {LoadProvisionalReason.noCommitment});
      expect(d.atlProvisional, isTrue);
      expect(d.tsbThresholdsLocked, isTrue);
    });

    test('mit Zusage nach 200 Tagen: nicht vorläufig, Sperre frei', () {
      final d = _calc(_daily(0, 200), today: 200).days.last;
      expect(d.ctlProvisionalReasons, isEmpty);
      expect(d.atlProvisional, isFalse);
      expect(d.tsbThresholdsLocked, isFalse);
    });

    test('bestätigte Pause: Last 0 auch ohne Zusage', () {
      final r = _calc([_run(0, 70)], today: 2, commit: false, pauses: {_d(1)});
      expect(r.days[1].load, 0);
      expect(r.days[1].flags, isEmpty);
    });
  });

  group('Neuer Nutzer (FR-0104)', () {
    test('ohne Einheiten: keine Aussage', () {
      final r = _calc([], today: 10);
      expect(r.days, isEmpty);
      expect(r.summary.current, isNull);
      expect(r.summary.hasStatement, isFalse);
    });

    test('nur unbewertete Einheiten: keine Werte, kein Niveau 0', () {
      final r = _calc([
        LoadUnit.run(day: _d(0)),
        LoadUnit.run(day: _d(2)),
      ], today: 3);
      expect(r.summary.hasStatement, isFalse);
      for (final d in r.days) {
        expect(d.atl, isNull);
        expect(d.ctl, isNull);
        expect(d.tsb, isNull);
        expect(d.tsbPercentMean7, isNull);
        expect(d.tsbThresholdsLocked, isFalse);
      }
      expect(r.summary.firstRatedDay, isNull);
      expect(r.summary.unratedUnits, 2);
    });

    test(
      'leere Tage vor dem ersten bewerteten Tag zählen nicht als Niveau 0',
      () {
        final r = _calc([LoadUnit.run(day: _d(0)), _run(3, 70)], today: 4);
        expect(r.days[1].atl, isNull);
        expect(r.days[2].atl, isNull);
        expect(r.days[3].atl, closeTo(10, 1e-12));
        expect(r.summary.firstRatedDay, _d(3));
      },
    );

    test('neuer Nutzer ist vorläufig (Start)', () {
      final d = _calc(_daily(0, 5), today: 5).days.last;
      expect(d.atlProvisional, isTrue);
      expect(d.ctlProvisionalReasons, {LoadProvisionalReason.startup});
      expect(d.tsbThresholdsLocked, isTrue);
    });
  });

  group('Vorläufig (PAR-088, PAR-089)', () {
    test('ATL 21 Tage, CTL/TSB 126 Tage ab erstem bewerteten Tag', () {
      final r = _calc(_daily(5, 200), today: 200);
      // Start Tag 5 -> Alter 0 ist Index 0 der Reihe.
      expect(r.days[20].atlProvisional, isTrue);
      expect(r.days[21].atlProvisional, isFalse);
      expect(r.days[125].ctlProvisionalReasons, {
        LoadProvisionalReason.startup,
      });
      expect(r.days[126].ctlProvisionalReasons, isEmpty);
      // ATL nach 21 Tagen schon frei, Sperre hängt aber an CTL.
      expect(r.days[21].tsbThresholdsLocked, isTrue);
      expect(r.days[126].tsbThresholdsLocked, isFalse);
    });
  });

  group('Rückfall (PAR-090)', () {
    List<LoadUnit> withUnrated(List<int> days) => [
      for (var i = 0; i <= 260; i++)
        if (days.contains(i)) LoadUnit.run(day: _d(i)) else _run(i, 50),
    ];

    test(
      'Beginn bei mehr als 10 % unbewertet im 42-Tage-Fenster, Ende danach',
      () {
        // 5 von 42 = 11,9 %, 4 von 42 = 9,5 %.
        final r = _calc(withUnrated([195, 196, 197, 198, 199]), today: 260);
        bool fb(int i) => r.days[i].ctlProvisionalReasons.contains(
          LoadProvisionalReason.missingUnits,
        );
        expect(fb(198), isFalse);
        expect(fb(199), isTrue);
        expect(fb(236), isTrue);
        expect(fb(237), isFalse);
        expect(r.days[199].tsbThresholdsLocked, isTrue);
        expect(r.days[237].tsbThresholdsLocked, isFalse);
        // ATL ist vom Rückfall nicht betroffen.
        expect(r.days[199].atlProvisional, isFalse);
      },
    );

    test(
      'mit erwarteten Einheiten aus dem Plan: Fehlen zählt, Pause nicht',
      () {
        final expected = {for (var i = 0; i <= 200; i++) _d(i): 1};
        // 10 erwartete Tage ohne Einheit (Fenster 159..200).
        final units = [
          for (var i = 0; i <= 200; i++)
            if (i < 180 || i > 189) _run(i, 50),
        ];
        final miss = _calc(units, today: 200, expected: expected);
        expect(
          miss.days.last.ctlProvisionalReasons,
          contains(LoadProvisionalReason.missingUnits),
        );
        final paused = _calc(
          units,
          today: 200,
          expected: expected,
          pauses: {for (var i = 180; i <= 189; i++) _d(i)},
        );
        expect(paused.days.last.ctlProvisionalReasons, isEmpty);
        // Genau 4 von 42 fehlen: noch nicht vorläufig.
        final four = _calc(
          [
            for (var i = 0; i <= 200; i++)
              if (i < 180 || i > 183) _run(i, 50),
          ],
          today: 200,
          expected: expected,
        );
        expect(four.days.last.ctlProvisionalReasons, isEmpty);
      },
    );
  });

  test('Laufzeit: 5 Jahre täglich', () {
    final units = <LoadUnit>[];
    for (var i = 0; i < 365 * 5 + 1; i++) {
      if (i % 7 == 3) continue; // Ruhetag
      units.add(switch (i % 11) {
        0 => LoadUnit.run(day: _d(i), srpePoints: 300),
        1 => LoadUnit.manual(day: _d(i), srpePoints: 200),
        2 => LoadUnit.run(day: _d(i)),
        _ => _run(i, 40 + (i % 5) * 10.0),
      });
    }
    final sw = Stopwatch()..start();
    final r = _calc(units, today: 365 * 5, factor: 0.8);
    sw.stop();
    // ignore: avoid_print
    print(
      '5 Jahre, ${r.days.length} Tage, ${units.length} Einheiten: '
      '${sw.elapsedMilliseconds} ms',
    );
    expect(r.days.length, 365 * 5 + 1);
    expect(sw.elapsedMilliseconds, lessThan(2000));
    for (final d in r.days) {
      if (d.atl != null) {
        expect(d.atl!.isFinite && d.ctl!.isFinite, isTrue);
      }
    }
  });
}
