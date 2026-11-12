import 'package:core/core.dart';
import 'package:test/test.dart';

/// Hinweise der Basisstufe (PAR-174 bis PAR-184, FR-0106, FR-0107): jeder
/// Hinweis aus den Eingangsdaten belegt, ohne Auslöser nichts, Sperre PAR-175.
void main() {
  pauseQuestionTests();
  final today = DateTime.utc(2030, 3, 1);
  DateTime ago(int n) => today.subtract(Duration(days: n));

  PlanUnit unit(PlanUnitKind kind, {int? runId, DateTime? day}) => PlanUnit(
    id: 1,
    day: day ?? today,
    kind: kind,
    phase: PlanPhase.build,
    weekIndex: 0,
    minutes: 40,
    runId: runId,
    segments: const [],
  );

  HintTraining run(int daysAgo, {int? rpe, int? wellbeing, int minutes = 30}) =>
      HintTraining(
        day: ago(daysAgo),
        minutes: minutes,
        rpe: rpe,
        wellbeing: wellbeing,
        isRun: true,
      );

  HintInputs inputs({
    PlanUnit? planned,
    List<HintTraining> trainings = const [],
    List<EasyPlanFeedback> easy = const [],
    bool allRecorded = false,
    PauseAnswer? answer,
    List<ShownHint> shown = const [],
    DateTime? warning,
    PauseRestartMark? mark,
  }) => HintInputs(
    today: today,
    plannedToday: planned,
    trainings: trainings,
    easyPlanned: easy,
    allRecorded: allRecorded,
    pauseAnswer: answer,
    pauseRestart: mark,
    shown: shown,
    warningReportedOn: warning,
  );

  HintCode? code(HintInputs i) => selectHint(i).hint?.code;

  group('PAR-184: ohne Auslöser kein Hinweis', () {
    test('keine Daten: nichts, keine positive Meldung', () {
      final s = selectHint(inputs());
      expect(s.hint, isNull);
      expect(s.locked, isEmpty);
    });

    test('regelmäßiges Training ohne Auslöser: nichts', () {
      expect(
        code(
          inputs(
            planned: unit(PlanUnitKind.intervals),
            trainings: [run(2, rpe: 5), run(4, rpe: 4), run(6, rpe: 5)],
            allRecorded: true,
          ),
        ),
        isNull,
      );
    });
  });

  group('PAR-179 kurzer Abstand', () {
    final planned = unit(PlanUnitKind.intervals);
    test(
      'intensive Einheit heute, gestern RPE 7: Hinweis mit Beleg, Knopf',
      () {
        final h = selectHint(
          inputs(planned: planned, trainings: [run(1, rpe: 7)]),
        ).hint!;
        expect(h.code, HintCode.shortInterval);
        expect(h.action, HintAction.easyRun);
        expect(h.evidenceOf(EvidenceKey.lastIntensiveDaysAgo), 1);
        expect(h.evidenceOf(EvidenceKey.lastIntensiveRpe), 7);
        expect(h.evidenceOf(EvidenceKey.plannedKind), 'intervals');
      },
    );

    test('heute bereits absolviert zählt (Abstand 0)', () {
      final h = selectHint(
        inputs(planned: planned, trainings: [run(0, rpe: 8)]),
      ).hint!;
      expect(h.evidenceOf(EvidenceKey.lastIntensiveDaysAgo), 0);
    });

    test('Grenzfälle: RPE 6, vorgestern, locker geplant: kein Hinweis', () {
      expect(
        code(inputs(planned: planned, trainings: [run(1, rpe: 6)])),
        isNull,
      );
      expect(
        code(inputs(planned: planned, trainings: [run(2, rpe: 9)])),
        isNull,
      );
      expect(
        code(
          inputs(planned: unit(PlanUnitKind.easy), trainings: [run(1, rpe: 9)]),
        ),
        isNull,
      );
    });

    test('langer Lauf zählt als intensiv (PAR-058); RPE ohne Angabe nicht', () {
      expect(
        code(
          inputs(planned: unit(PlanUnitKind.long), trainings: [run(1, rpe: 7)]),
        ),
        HintCode.shortInterval,
      );
      expect(code(inputs(planned: planned, trainings: [run(1)])), isNull);
    });

    test('Einheit schon gelaufen oder Ruhetag: kein Hinweis', () {
      expect(
        code(
          inputs(
            planned: unit(PlanUnitKind.intervals, runId: 3),
            trainings: [run(1, rpe: 7)],
          ),
        ),
        isNull,
      );
      expect(
        code(
          inputs(planned: unit(PlanUnitKind.rest), trainings: [run(1, rpe: 7)]),
        ),
        isNull,
      );
    });

    test('Nachtrag (kein Lauf) zählt als absolviert', () {
      final t = HintTraining(day: ago(1), minutes: 40, rpe: 8, isRun: false);
      expect(code(inputs(planned: planned, trainings: [t])), isNotNull);
    });
  });

  group('PAR-178 Anstieg vor Tag 126', () {
    // Erster Lauf vor 40 Tagen; 21 Tage davor: 3 Läufe à 60 min = 60 min je
    // Woche; letzte 7 Tage: Summe in Minuten.
    List<HintTraining> base({required int last7}) => [
      run(40, minutes: 10),
      run(15, minutes: 60),
      run(18, minutes: 60),
      run(21, minutes: 60),
      run(2, minutes: last7),
    ];

    test('genau 1,5-fach (90 von 60): Hinweis, mit Belegen, ohne Knopf', () {
      final h = selectHint(
        inputs(trainings: base(last7: 90), allRecorded: true),
      ).hint!;
      expect(h.code, HintCode.steepIncrease);
      expect(h.action, isNull);
      expect(h.evidenceOf(EvidenceKey.activeMinutes7d), 90);
      expect(h.evidenceOf(EvidenceKey.weeklyAverageMinutes21d), 60.0);
    });

    test('knapp darunter: kein Hinweis', () {
      // Wochenschnitt 60: 1,5-fach = 90, also 89 zu wenig.
      expect(
        code(inputs(trainings: base(last7: 89), allRecorded: true)),
        isNull,
      );
    });

    test('ohne Zusage und ohne bestätigte Pause: kein Hinweis', () {
      expect(code(inputs(trainings: base(last7: 200))), isNull);
      expect(
        code(
          inputs(
            trainings: base(last7: 200),
            answer: PauseAnswer(paused: false, on: ago(1)),
          ),
        ),
        isNull,
      );
    });

    test('bestätigte Pause genügt statt der Zusage', () {
      expect(
        code(
          inputs(
            trainings: base(last7: 200),
            answer: PauseAnswer(paused: true, on: ago(10)),
          ),
        ),
        HintCode.steepIncrease,
      );
    });

    test('eine alte bestätigte Pause (vor über 27 Tagen) genügt nicht', () {
      expect(
        code(
          inputs(
            trainings: base(last7: 200),
            answer: PauseAnswer(paused: true, on: ago(28)),
          ),
        ),
        isNull,
      );
    });

    test('unter 28 Tagen Daten und ab Tag 126: kein Hinweis', () {
      final young = [run(27, minutes: 60), run(2, minutes: 500)];
      expect(code(inputs(trainings: young, allRecorded: true)), isNull);
      final old = [run(126, minutes: 60), ...base(last7: 500)];
      expect(code(inputs(trainings: old, allRecorded: true)), isNull);
      final edge = [run(125, minutes: 10), ...base(last7: 500)];
      expect(
        code(inputs(trainings: edge, allRecorded: true)),
        HintCode.steepIncrease,
      );
    });

    test('Wochenschnitt 0: kein Hinweis', () {
      final t = [run(40, minutes: 5), run(2, minutes: 500)];
      expect(code(inputs(trainings: t, allRecorded: true)), isNull);
    });
  });

  group('PAR-180/181 Pause', () {
    test('7 Tage mit Zusage: Pause, Belege', () {
      final h = selectHint(inputs(trainings: [run(7)], allRecorded: true))
          .hint!;
      expect(h.code, HintCode.pause);
      expect(h.evidenceOf(EvidenceKey.daysSinceTraining), 7);
      expect(h.evidenceOf(EvidenceKey.lastTrainingDay), ago(7));
      expect(h.action, isNull);
    });

    test('6 Tage: nichts; 55 Tage Pause, 56 Tage lange Pause', () {
      expect(code(inputs(trainings: [run(6)], allRecorded: true)), isNull);
      expect(
        code(inputs(trainings: [run(55)], allRecorded: true)),
        HintCode.pause,
      );
      expect(
        code(inputs(trainings: [run(56)], allRecorded: true)),
        HintCode.longPause,
      );
    });

    test(
      'Beleg planRestarted: nur mit Merker „restart“ zum letzten Training',
      () {
        Object? restarted(PauseRestartMark? mark, {int days = 10}) =>
            selectHint(
              inputs(trainings: [run(days)], allRecorded: true, mark: mark),
            ).hint!.evidenceOf(EvidenceKey.planRestarted);
        expect(restarted(null), false);
        expect(
          restarted(PauseRestartMark(day: ago(10), restarted: true)),
          true,
        );
        expect(
          restarted(PauseRestartMark(day: ago(10), restarted: false)),
          false,
        );
        expect(
          restarted(PauseRestartMark(day: ago(30), restarted: true)),
          false,
        );
      },
    );

    test('ab 56 Tagen bietet der Hinweis den neuen Einstieg an (PAR-181)', () {
      HintAction? action(int days, {PauseRestartMark? mark}) => selectHint(
        inputs(trainings: [run(days)], allRecorded: true, mark: mark),
      ).hint!.action;
      expect(action(55), isNull);
      expect(action(56), HintAction.newStart);
      expect(
        action(56, mark: PauseRestartMark(day: ago(56), restarted: true)),
        isNull,
      );
      expect(
        action(56, mark: PauseRestartMark(day: ago(80), restarted: true)),
        HintAction.newStart,
      );
    });

    test('ohne Zusage und ohne Bestätigung: nichts (Pause unbekannt)', () {
      expect(code(inputs(trainings: [run(20)])), isNull);
      expect(
        code(
          inputs(
            trainings: [run(20)],
            answer: PauseAnswer(paused: false, on: ago(1)),
          ),
        ),
        isNull,
      );
    });

    test(
      'bestätigte Pause zählt nur, wenn sie nach dem letzten Training kam',
      () {
        expect(
          code(
            inputs(
              trainings: [run(20)],
              answer: PauseAnswer(paused: true, on: ago(5)),
            ),
          ),
          HintCode.pause,
        );
        expect(
          code(
            inputs(
              trainings: [run(20)],
              answer: PauseAnswer(paused: true, on: ago(30)),
            ),
          ),
          isNull,
        );
      },
    );

    test('kein Training überhaupt: nichts', () {
      expect(code(inputs(allRecorded: true)), isNull);
    });
  });

  group('PAR-182 Anstrengung über Plan', () {
    final planned = unit(PlanUnitKind.tempo);
    EasyPlanFeedback e(int daysAgo, int? rpe) =>
        EasyPlanFeedback(day: ago(daysAgo), rpe: rpe);

    test('2 von 3 mit RPE 6: Hinweis mit Beleg und Knopf', () {
      final h = selectHint(
        inputs(planned: planned, easy: [e(2, 6), e(4, 3), e(6, 8)]),
      ).hint!;
      expect(h.code, HintCode.effortAbovePlan);
      expect(h.action, HintAction.easyRun);
      expect(h.evidenceOf(EvidenceKey.easyRunsConsidered), 3);
      expect(h.evidenceOf(EvidenceKey.easyRunsAboveRpe), 2);
    });

    test('nur 1 von 3, RPE 5, fehlende RPE: kein Hinweis', () {
      expect(
        code(inputs(planned: planned, easy: [e(2, 6), e(4, 5), e(6, 5)])),
        isNull,
      );
      expect(
        code(inputs(planned: planned, easy: [e(2, 6), e(4, null), e(6, 7)])),
        HintCode.effortAbovePlan,
      );
      expect(
        code(inputs(planned: planned, easy: [e(2, 6), e(4, null), e(6, null)])),
        isNull,
      );
    });

    test('nur die letzten 3 zählen', () {
      expect(
        code(
          inputs(
            planned: planned,
            easy: [e(2, 6), e(4, 3), e(6, 3), e(8, 9), e(10, 9)],
          ),
        ),
        isNull,
      );
    });

    test('ohne geplante Einheit heute oder bei Ruhetag: kein Hinweis', () {
      expect(code(inputs(easy: [e(2, 7), e(4, 7), e(6, 7)])), isNull);
      expect(
        code(
          inputs(
            planned: unit(PlanUnitKind.rest),
            easy: [e(2, 7), e(4, 7), e(6, 7)],
          ),
        ),
        isNull,
      );
    });
  });

  group('PAR-183 / PAR-188 Befinden', () {
    test('Befinden 2 beim letzten Lauf, 3 Tage alt: Hinweis', () {
      final h = selectHint(inputs(trainings: [run(3, wellbeing: 2, rpe: 4)]))
          .hint!;
      expect(h.code, HintCode.lowWellbeing);
      expect(h.action, HintAction.easyRun);
      expect(h.evidenceOf(EvidenceKey.wellbeing), 2);
      expect(h.evidenceOf(EvidenceKey.wellbeingDaysAgo), 3);
    });

    test('Grenzfälle: Befinden 3, 4 Tage alt, nicht der letzte Lauf', () {
      expect(code(inputs(trainings: [run(1, wellbeing: 3)])), isNull);
      expect(code(inputs(trainings: [run(4, wellbeing: 1)])), isNull);
      expect(
        code(inputs(trainings: [run(2, wellbeing: 1), run(1, wellbeing: 4)])),
        isNull,
      );
      expect(
        code(inputs(trainings: [run(2, wellbeing: 1), run(1)])),
        isNull,
        reason: 'der letzte Lauf hat keine Angabe',
      );
    });

    test('Nachträge haben kein Befinden und zählen nicht als letzter Lauf', () {
      final manual = HintTraining(day: ago(0), minutes: 30, isRun: false);
      expect(
        code(inputs(trainings: [run(2, wellbeing: 1), manual])),
        HintCode.lowWellbeing,
      );
    });
  });

  group('PAR-175 Auswahl und Sperre', () {
    final planned = unit(PlanUnitKind.intervals);
    // Auslöser von 179 und 183 zugleich.
    final both = [run(1, rpe: 7, wellbeing: 1)];

    test('höchstens ein Hinweis, Vorrang: 179 vor 183', () {
      expect(
        code(inputs(planned: planned, trainings: both)),
        HintCode.shortInterval,
      );
    });

    test('Vorrang 178 vor 180 vor 182 vor 183 (paarweise)', () {
      // 180 vs 182: Pause mit Zusage und Lauf-RPE-Folge kann nicht
      // gleichzeitig; prüfe 182 vs 183 und 178 vs 183.
      final easy = [
        EasyPlanFeedback(day: ago(2), rpe: 7),
        EasyPlanFeedback(day: ago(3), rpe: 7),
      ];
      expect(
        code(
          inputs(
            planned: unit(PlanUnitKind.easy),
            trainings: [run(1, wellbeing: 1)],
            easy: easy,
          ),
        ),
        HintCode.effortAbovePlan,
      );
      final t = [
        run(40, minutes: 10),
        run(15, minutes: 60),
        run(18, minutes: 60),
        run(21, minutes: 60),
        run(1, minutes: 300, wellbeing: 1),
      ];
      expect(
        code(inputs(trainings: t, allRecorded: true)),
        HintCode.steepIncrease,
      );
    });

    test('Vorrang 179 vor 178 und 180 vor 182', () {
      final t = [
        run(40, minutes: 10),
        run(15, minutes: 60),
        run(18, minutes: 60),
        run(21, minutes: 60),
        run(1, minutes: 300, rpe: 8),
      ];
      expect(
        code(inputs(planned: planned, trainings: t, allRecorded: true)),
        HintCode.shortInterval,
      );
      expect(
        code(
          inputs(
            planned: planned,
            trainings: [run(9)],
            allRecorded: true,
            easy: [
              EasyPlanFeedback(day: ago(2), rpe: 7),
              EasyPlanFeedback(day: ago(3), rpe: 7),
            ],
          ),
        ),
        HintCode.pause,
      );
    });

    test('3 Tage in Folge gezeigt: am 4. Tag gesperrt, nächster folgt', () {
      final shown = [
        for (final n in [1, 2, 3]) ShownHint(ago(n), HintCode.shortInterval),
      ];
      final s = selectHint(
        inputs(planned: planned, trainings: both, shown: shown),
      );
      expect(s.locked, [HintCode.shortInterval]);
      expect(s.hint!.code, HintCode.lowWellbeing);
    });

    test('nur 2 Tage in Folge oder Lücke: nicht gesperrt', () {
      expect(
        code(
          inputs(
            planned: planned,
            trainings: both,
            shown: [
              ShownHint(ago(1), HintCode.shortInterval),
              ShownHint(ago(2), HintCode.shortInterval),
            ],
          ),
        ),
        HintCode.shortInterval,
      );
      expect(
        code(
          inputs(
            planned: planned,
            trainings: both,
            shown: [
              ShownHint(ago(1), HintCode.shortInterval),
              ShownHint(ago(3), HintCode.shortInterval),
              ShownHint(ago(4), HintCode.shortInterval),
            ],
          ),
        ),
        HintCode.shortInterval,
      );
    });

    test(
      'Sperre gilt je Hinweis: anderer Code an den Vortagen sperrt nicht',
      () {
        expect(
          code(
            inputs(
              planned: planned,
              trainings: both,
              shown: [
                for (final n in [1, 2, 3])
                  ShownHint(ago(n), HintCode.lowWellbeing),
              ],
            ),
          ),
          HintCode.shortInterval,
        );
      },
    );

    test('gesperrt und nichts sonst: kein Hinweis, locked belegt es', () {
      final s = selectHint(
        inputs(
          trainings: [run(2, wellbeing: 1)],
          shown: [
            for (final n in [1, 2, 3]) ShownHint(ago(n), HintCode.lowWellbeing),
          ],
        ),
      );
      expect(s.hint, isNull);
      expect(s.locked, [HintCode.lowWellbeing]);
    });
  });

  group('Warnsignal: Vorrang, von der Sperre ausgenommen', () {
    test('unterdrückt alle anderen Hinweise', () {
      final s = selectHint(
        inputs(
          warning: ago(2),
          planned: unit(PlanUnitKind.intervals),
          trainings: [run(1, rpe: 8, wellbeing: 1)],
        ),
      );
      expect(s.hint!.code, HintCode.warning);
      expect(s.hint!.evidenceOf(EvidenceKey.warningReportedOn), ago(2));
      expect(s.hint!.action, isNull);
    });

    test('auch nach 3 Tagen und mit voller Hinweissperre noch da', () {
      final shown = [
        for (final n in [1, 2, 3]) ShownHint(ago(n), HintCode.warning),
      ];
      expect(code(inputs(warning: ago(5), shown: shown)), HintCode.warning);
    });
  });
}

/// Pausenfrage (PAR-202).
void pauseQuestionTests() {
  final today = DateTime.utc(2030, 3, 1);
  DateTime ago(int n) => today.subtract(Duration(days: n));

  HintTraining run(int daysAgo, {int minutes = 30}) =>
      HintTraining(day: ago(daysAgo), minutes: minutes, isRun: true);

  HintInputs inputs({
    List<HintTraining> trainings = const [],
    bool allRecorded = false,
    PauseAnswer? answer,
    DateTime? warning,
    PauseRestartMark? mark,
  }) => HintInputs(
    today: today,
    trainings: trainings,
    allRecorded: allRecorded,
    pauseAnswer: answer,
    pauseRestart: mark,
    warningReportedOn: warning,
  );

  PauseQuestion? ask(HintInputs i) => selectPauseQuestion(i);

  group('Pausenfrage (PAR-202)', () {
    test('ab 7 Tagen ohne Training, letzte volle Woche als Grundlage', () {
      final q = ask(
        inputs(trainings: [run(7), run(9, minutes: 20), run(12, minutes: 99)]),
      )!;
      expect(q.daysSinceTraining, 7);
      expect(q.lastTrainingDay, ago(7));
      // Letztes Training Fr 2030-02-22: angebrochene Woche (50 min) zählt
      // nicht, Basis ist die Woche davor (11.–17.2.: 99 min).
      expect(q.baseWeekMinutes, 99);
    });

    test('Grenze: 6 Tage nein, 7 Tage ja', () {
      expect(ask(inputs(trainings: [run(6)])), isNull);
      expect(ask(inputs(trainings: [run(7)])), isNotNull);
    });

    test('nicht bei Zusage alles erfasst, ohne Training, unter Warnsignal', () {
      expect(ask(inputs(trainings: [run(10)], allRecorded: true)), isNull);
      expect(ask(inputs()), isNull);
      expect(ask(inputs(trainings: [run(10)], warning: ago(1))), isNull);
    });

    test('nach einer Antwort seit dem letzten Training nicht erneut', () {
      final a = PauseAnswer(paused: false, on: ago(2));
      expect(ask(inputs(trainings: [run(10)], answer: a)), isNull);
      final old = PauseAnswer(paused: true, on: ago(20));
      expect(ask(inputs(trainings: [run(10)], answer: old)), isNotNull);
    });
  });

  group('Neustart bei Zusage alles erfasst (PAR-202)', () {
    PauseQuestion? due(HintInputs i) => selectPauseRestart(i);

    test('fällig ab 7 Tagen mit der Zusage, sonst nicht', () {
      final q = due(inputs(trainings: [run(7)], allRecorded: true))!;
      expect(q.lastTrainingDay, ago(7));
      expect(due(inputs(trainings: [run(6)], allRecorded: true)), isNull);
      expect(due(inputs(trainings: [run(10)])), isNull);
      expect(due(inputs(allRecorded: true)), isNull);
      expect(
        due(inputs(trainings: [run(10)], allRecorded: true, warning: ago(1))),
        isNull,
      );
    });

    test('ab 56 Tagen mit der Zusage fällig (vorläufige Vorgabe), ohne sie '
        'nicht; nach dem Merker einmal je Pause', () {
      expect(due(inputs(trainings: [run(55)], allRecorded: true)), isNotNull);
      expect(due(inputs(trainings: [run(56)], allRecorded: true)), isNotNull);
      expect(due(inputs(trainings: [run(60)])), isNull);
      expect(
        due(
          inputs(
            trainings: [run(60)],
            allRecorded: true,
            mark: PauseRestartMark(
              day: ago(60),
              restarted: true,
              provisional: true,
            ),
          ),
        ),
        isNull,
      );
    });

    test('Merker: vorläufig bleibt lesbar; der Einstieg bleibt wählbar, bis '
        'er gewählt ist', () {
      for (final restarted in [true, false]) {
        final m = PauseRestartMark(
          day: ago(60),
          restarted: restarted,
          provisional: true,
        );
        final back = PauseRestartMark.parse(m.format())!;
        expect(back.provisional, isTrue);
        expect(back.restarted, restarted);
      }
      expect(
        PauseRestartMark.parse('2026-01-01 restart')!.provisional,
        isFalse,
      );
      final prov = PauseRestartMark(
        day: ago(60),
        restarted: true,
        provisional: true,
      );
      expect(
        selectNewStart(
          inputs(trainings: [run(60)], allRecorded: true, mark: prov),
        ),
        isNotNull,
      );
      final hint = selectHint(
        inputs(trainings: [run(60)], allRecorded: true, mark: prov),
      );
      expect(hint.hint?.action, HintAction.newStart);
    });

    test('neuer Einstieg ab 56 Tagen: Zusage oder bestätigte Pause', () {
      PauseQuestion? start(HintInputs i) => selectNewStart(i);
      expect(start(inputs(trainings: [run(55)], allRecorded: true)), isNull);
      final q = start(inputs(trainings: [run(56)], allRecorded: true))!;
      expect(q.lastTrainingDay, ago(56));
      expect(start(inputs(trainings: [run(60)])), isNull);
      expect(
        start(
          inputs(
            trainings: [run(60)],
            answer: PauseAnswer(paused: true, on: ago(1)),
          ),
        ),
        isNotNull,
      );
      expect(
        start(inputs(trainings: [run(60)], allRecorded: true, warning: ago(1))),
        isNull,
      );
      expect(
        start(
          inputs(
            trainings: [run(60)],
            allRecorded: true,
            mark: PauseRestartMark(day: ago(60), restarted: true),
          ),
        ),
        isNull,
      );
    });

    test('einmal je Pause: der Merker zum letzten Training sperrt', () {
      final mark = PauseRestartMark(day: ago(10), restarted: false);
      expect(
        due(inputs(trainings: [run(10)], allRecorded: true, mark: mark)),
        isNull,
      );
      final old = PauseRestartMark(day: ago(30), restarted: true);
      expect(
        due(inputs(trainings: [run(10)], allRecorded: true, mark: old)),
        isNotNull,
      );
    });

    test('Merker als Text: Rundlauf und Fehlformen', () {
      final m = PauseRestartMark(
        day: DateTime.utc(2030, 2, 20),
        restarted: true,
      );
      expect(m.format(), '2030-02-20 restart');
      expect(PauseRestartMark.parse(m.format())!.restarted, isTrue);
      expect(PauseRestartMark.parse('2030-02-20 none')!.restarted, isFalse);
      expect(PauseRestartMark.parse('2030-02-20'), isNull);
      expect(PauseRestartMark.parse('x none'), isNull);
      expect(PauseRestartMark.parse(null), isNull);
    });
  });
}
