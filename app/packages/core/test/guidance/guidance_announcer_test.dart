import 'package:core/core.dart';
import 'package:test/test.dart';

PlanTargetIntensity hr(int max) =>
    PlanTargetIntensity(hrMinBpm: 100, hrMaxBpm: max);

PlanSegment seg(PlanSegmentKind k, int min, {int? max, int? sec}) =>
    PlanSegment(
      kind: k,
      minutes: min,
      seconds: sec,
      intensity: max == null ? null : hr(max),
    );

Duration s(int n) => Duration(seconds: n);

/// Spielt Sekundentakt von [from] bis [to] ein (je einschliesslich).
class Sim {
  Sim(this.a);
  final GuidanceAnnouncer a;
  final List<(int, GuidanceEvent)> events = [];

  void play(
    int from,
    int to, {
    int? Function(int t)? bpm,
    double Function(int t)? dist,
    RecordingPhase phase = RecordingPhase.running,
  }) {
    for (var t = from; t <= to; t++) {
      for (final e in a.onTick(
        GuidanceTick(
          movingTime: s(t),
          phase: phase,
          distanceMeters: dist?.call(t) ?? 0.0,
          heartRateBpm: bpm?.call(t),
        ),
      )) {
        events.add((t, e));
      }
    }
  }

  List<(int, GuidanceEvent)> of(GuidanceEventKind k) =>
      events.where((e) => e.$2.kind == k).toList();
}

final easyOnly = [seg(PlanSegmentKind.easy, 30, max: 140)];

void main() {
  group('Abschnittswechsel', () {
    final segs = [
      seg(PlanSegmentKind.warmUp, 1),
      seg(PlanSegmentKind.interval, 2),
      seg(PlanSegmentKind.coolDown, 1),
    ];

    test(
      'Wechsel mit Index und Ziel, Vorankuendigung 10 s vorher, am Ende fertig',
      () {
        final sim = Sim(GuidanceAnnouncer(segments: segs))..play(0, 300);
        final ch = sim.of(GuidanceEventKind.segmentChange);
        expect(ch.map((e) => (e.$1, e.$2.segmentIndex)), [(60, 1), (180, 2)]);
        expect(ch.first.$2.segmentKind, PlanSegmentKind.interval);
        final pre = sim.of(GuidanceEventKind.segmentPreview);
        expect(
          pre.map((e) => (e.$1, e.$2.segmentIndex, e.$2.secondsUntilChange)),
          [(50, 1, 10), (170, 2, 10)],
        );
        expect(sim.of(GuidanceEventKind.unitComplete).map((e) => e.$1), [240]);
      },
    );

    test('Pause haelt den Abschnitt: keine Ereignisse, kein Fortschritt', () {
      final sim = Sim(GuidanceAnnouncer(segments: segs))..play(0, 40);
      sim.play(40, 40, phase: RecordingPhase.paused);
      sim.play(40, 40, phase: RecordingPhase.autoPaused);
      expect(sim.events, isEmpty);
      sim.play(41, 70);
      expect(sim.of(GuidanceEventKind.segmentChange).map((e) => e.$1), [60]);
    });

    test('Wiederanlauf mitten im Abschnitt: kein doppelter Wechsel, Vorankuendigung', () {
      // Neuer Geber nach Absturz bei 100 s: Abschnitt 1 laeuft schon.
      final sim = Sim(GuidanceAnnouncer(segments: segs))..play(100, 300);
      expect(
        sim.of(GuidanceEventKind.segmentChange).map((e) => e.$2.segmentIndex),
        [2],
      );
      expect(
        sim.of(GuidanceEventKind.segmentPreview).map((e) => e.$2.segmentIndex),
        [2],
      );
    });

    test(
      'Wiederanlauf im Vorankuendigungsfenster: Vorankuendigung nicht doppelt',
      () {
        final sim = Sim(GuidanceAnnouncer(segments: segs))..play(55, 70);
        expect(sim.of(GuidanceEventKind.segmentPreview), isEmpty);
        expect(sim.of(GuidanceEventKind.segmentChange).map((e) => e.$1), [60]);
      },
    );

    test('Wiederanlauf nach Ende: nichts', () {
      final sim = Sim(GuidanceAnnouncer(segments: segs))..play(250, 260);
      expect(sim.events, isEmpty);
    });

    test('kurze Abschnitte (Geh-Lauf 15 s) ohne Vorankuendigung', () {
      final sim = Sim(
        GuidanceAnnouncer(
          segments: [
            seg(PlanSegmentKind.run, 0, sec: 15),
            seg(PlanSegmentKind.walk, 0, sec: 15),
            seg(PlanSegmentKind.run, 0, sec: 15),
          ],
        ),
      )..play(0, 50);
      expect(sim.of(GuidanceEventKind.segmentPreview), isEmpty);
      expect(sim.of(GuidanceEventKind.segmentChange).length, 2);
    });

    test('letzter Abschnitt hat keine Vorankuendigung', () {
      final sim = Sim(GuidanceAnnouncer(segments: segs))..play(0, 300);
      expect(
        sim.of(GuidanceEventKind.segmentPreview).map((e) => e.$2.segmentIndex),
        isNot(contains(3)),
      );
    });
  });

  group('Überspringen (FR-0218)', () {
    final segs = [
      seg(PlanSegmentKind.warmUp, 1),
      seg(PlanSegmentKind.interval, 5, max: 150),
      seg(PlanSegmentKind.recovery, 2),
      seg(PlanSegmentKind.coolDown, 1),
    ];

    test('Sprung: genau eine Ansage segmentChange, folgende nach Zeit', () {
      final a = GuidanceAnnouncer(segments: segs);
      final sim = Sim(a)..play(0, 90);
      final e = a.skip(s(90));
      expect(e.map((x) => (x.kind, x.segmentIndex)), [
        (GuidanceEventKind.segmentChange, 2),
      ]);
      expect(a.skips, [s(90)]);
      sim.play(91, 400);
      final ch = sim.of(GuidanceEventKind.segmentChange);
      // Wechsel nach Zeit: 60 (Intervall), dann Abwärmen 90 + 120 = 210.
      expect(ch.map((x) => (x.$1, x.$2.segmentIndex)), [(60, 1), (210, 3)]);
      // Keine Ansage des übersprungenen Wechsels bei 360, keine doppelte.
      expect(sim.of(GuidanceEventKind.segmentPreview).map((x) => x.$1), [
        50,
        200,
      ]);
      expect(sim.of(GuidanceEventKind.unitComplete).map((x) => x.$1), [270]);
    });

    test('Sprung im Vorankündigungsfenster: keine weitere Vorankündigung', () {
      final a = GuidanceAnnouncer(segments: segs);
      final sim = Sim(a)..play(0, 355);
      expect(sim.of(GuidanceEventKind.segmentPreview).map((x) => x.$1), [
        50,
        350,
      ]);
      expect(a.skip(s(355)).single.segmentIndex, 2);
      sim.play(356, 365);
      expect(sim.of(GuidanceEventKind.segmentPreview), hasLength(2));
      expect(sim.of(GuidanceEventKind.segmentChange), hasLength(1));
    });

    test('letzter Abschnitt: unitComplete, danach nichts mehr', () {
      final a = GuidanceAnnouncer(segments: segs);
      final sim = Sim(a)..play(0, 490);
      expect(sim.of(GuidanceEventKind.segmentChange), hasLength(3));
      final e = a.skip(s(490));
      expect(e.map((x) => x.kind), [GuidanceEventKind.unitComplete]);
      sim.play(491, 600);
      expect(sim.of(GuidanceEventKind.unitComplete), isEmpty);
      expect(sim.of(GuidanceEventKind.segmentChange), hasLength(3));
      // Fertige Einheit: Überspringen tut nichts.
      expect(a.skip(s(600)), isEmpty);
      expect(a.skips, [s(490)]);
    });

    test('Schalter „Intervallwechsel“ aus: Sprung ohne Ansage', () {
      final a = GuidanceAnnouncer(
        segments: segs,
        switches: const GuidanceSwitches(segments: false),
      );
      Sim(a).play(0, 30);
      expect(a.skip(s(30)), isEmpty);
      expect(a.skips, [s(30)]);
    });

    test('Pause: Ansage sofort, Abschnitt steht danach still', () {
      final a = GuidanceAnnouncer(segments: segs);
      final sim = Sim(a)..play(0, 30);
      sim.play(30, 30, phase: RecordingPhase.paused);
      expect(a.skip(s(30)).single.segmentIndex, 1);
      sim.play(30, 30, phase: RecordingPhase.paused);
      sim.play(30, 30, phase: RecordingPhase.autoPaused);
      expect(sim.events, isEmpty);
      // Weiter: das Intervall läuft ab 30 s volle 5 min.
      sim.play(31, 340);
      expect(sim.of(GuidanceEventKind.segmentChange).map((x) => x.$1), [330]);
    });

    test('Pulshinweis zurückgesetzt: Zählung beginnt im neuen Abschnitt', () {
      final s2 = [
        seg(PlanSegmentKind.easy, 10, max: 140),
        seg(PlanSegmentKind.easy, 10, max: 140),
      ];
      final a = GuidanceAnnouncer(segments: s2);
      // 3:00–3:20 über der Grenze, dann Sprung bei 200 s.
      final sim = Sim(a)..play(0, 200, bpm: (_) => 150);
      expect(a.pulseOverrunSustained, isFalse);
      a.skip(s(200));
      sim.play(201, 600, bpm: (_) => 150);
      final hr = sim.of(GuidanceEventKind.heartRateAbove);
      // Neuer Abschnitt ab 200 s: Fenster ab 380 s, plus 30 s über der Grenze.
      expect(hr.map((x) => x.$1), [410]);
    });

    test(
      'Rückgängig: keine erneute Ansage, Abschnitt läuft nach Zeit weiter',
      () {
        final a = GuidanceAnnouncer(segments: segs);
        final sim = Sim(a)..play(0, 90);
        a.skip(s(90));
        sim.play(91, 93);
        expect(a.undoSkip(s(93)), isTrue);
        expect(a.skips, isEmpty);
        sim.play(94, 400);
        // Wie ohne Sprung: Intervall endet bei 360, keine Ansage für das
        // wiederhergestellte Intervall.
        expect(
          sim
              .of(GuidanceEventKind.segmentChange)
              .map((x) => (x.$1, x.$2.segmentIndex)),
          [(60, 1), (360, 2)],
        );
        expect(a.undoSkip(s(400)), isFalse);
      },
    );

    test('Rückgängig nach gesprochener Vorankündigung: nicht noch einmal', () {
      final a = GuidanceAnnouncer(segments: segs);
      final sim = Sim(a)..play(0, 352);
      a.skip(s(352));
      sim.play(353, 354);
      a.undoSkip(s(354));
      sim.play(355, 365);
      expect(sim.of(GuidanceEventKind.segmentPreview).map((x) => x.$1), [
        50,
        350,
      ]);
      expect(sim.of(GuidanceEventKind.segmentChange).map((x) => x.$1), [
        60,
        360,
      ]);
    });

    test('Rückgängig nach unitComplete: letzter Abschnitt wieder da', () {
      final a = GuidanceAnnouncer(segments: segs);
      final sim = Sim(a)..play(0, 490);
      a.skip(s(490));
      a.undoSkip(s(491));
      sim.play(491, 600);
      expect(sim.of(GuidanceEventKind.unitComplete).map((x) => x.$1), [540]);
    });

    test('zwei Sprünge, Rückgängig nimmt nur den letzten zurück', () {
      final a = GuidanceAnnouncer(segments: segs);
      final sim = Sim(a)..play(0, 30);
      a.skip(s(30));
      sim.play(31, 40);
      a.skip(s(40));
      expect(a.skips, [s(30), s(40)]);
      a.undoSkip(s(41));
      expect(a.skips, [s(30)]);
      sim.play(41, 400);
      expect(
        sim
            .of(GuidanceEventKind.segmentChange)
            .map((x) => (x.$1, x.$2.segmentIndex)),
        [(330, 2)],
      );
    });

    test('Wiederanlauf mit Sprüngen: setzt am erreichten Abschnitt fort', () {
      final sim = Sim(GuidanceAnnouncer(segments: segs, skips: [s(90)]))
        ..play(100, 400);
      expect(
        sim
            .of(GuidanceEventKind.segmentChange)
            .map((x) => (x.$1, x.$2.segmentIndex)),
        [(210, 3)],
      );
      expect(sim.of(GuidanceEventKind.unitComplete).map((x) => x.$1), [270]);
    });
  });

  group('Kilometer', () {
    test('bei jedem vollen km, Zeit und Dauer des letzten km', () {
      // 3 m/s bis 400 s, danach 2 m/s.
      final sim = Sim(GuidanceAnnouncer(segments: const []))
        ..play(
          0,
          1000,
          dist: (t) => t <= 400 ? t * 3.0 : 1200 + (t - 400) * 2.0,
        );
      final k = sim.of(GuidanceEventKind.kilometer);
      expect(k.map((e) => e.$2.kilometer), [1, 2]);
      expect(k[0].$1, 334); // 334 * 3 = 1002
      expect(k[0].$2.kilometerTime, s(334));
      expect(k[0].$2.kilometerDuration, s(334));
      expect(k[1].$2.kilometerDuration, k[1].$2.kilometerTime! - s(334));
    });

    test(
      'Wiederanlauf bei 2,4 km: keine alten km, erster km danach ohne Dauer',
      () {
        final sim = Sim(GuidanceAnnouncer(segments: const []))
          ..play(800, 1200, dist: (t) => 2400.0 + (t - 800) * 3);
        final k = sim.of(GuidanceEventKind.kilometer);
        expect(k.map((e) => e.$2.kilometer), [3]);
        expect(k.single.$2.kilometerDuration, isNull);
      },
    );

    test('Pause: kein km waehrend Pause, nach Wiederanlauf einmal', () {
      final sim = Sim(GuidanceAnnouncer(segments: const []))
        ..play(0, 300, dist: (t) => t * 3.3);
      sim.play(301, 310, dist: (_) => 1005, phase: RecordingPhase.paused);
      expect(sim.of(GuidanceEventKind.kilometer), isEmpty);
      sim.play(301, 305, dist: (t) => 1005);
      sim.play(306, 310, dist: (t) => 1005);
      expect(sim.of(GuidanceEventKind.kilometer).length, 1);
    });

    test('ohne Strecke keine km', () {
      final a = GuidanceAnnouncer(segments: const []);
      for (var t = 0; t < 10; t++) {
        expect(
          a.onTick(
            GuidanceTick(movingTime: s(t), phase: RecordingPhase.running),
          ),
          isEmpty,
        );
      }
    });
  });

  group('Puls PAR-107', () {
    List<(int, GuidanceEvent)> pulse(
      List<PlanSegment> segs,
      int? Function(int) bpm, {
      int to = 1200,
      int from = 0,
      GuidanceSwitches sw = const GuidanceSwitches(),
      bool walk = false,
    }) {
      final sim = Sim(
        GuidanceAnnouncer(
          segments: segs,
          switches: sw,
          suppressHeartRateForWalkBreaks: walk,
        ),
      )..play(from, to, bpm: bpm);
      return sim.events
          .where(
            (e) =>
                e.$2.kind == GuidanceEventKind.heartRateAbove ||
                e.$2.kind == GuidanceEventKind.walkBreakHint,
          )
          .toList();
    }

    test(
      'erste Ansage fruehestens 3 min im Abschnitt plus 30 s Ueberschreitung',
      () {
        final e = pulse(easyOnly, (_) => 150, to: 400);
        expect(e.map((x) => x.$1), [210]);
        expect(e.single.$2.heartRateBpm, 150);
        expect(e.single.$2.heartRateMaxBpm, 140);
      },
    );

    test('Ueberschreitung unter 30 s: keine Ansage', () {
      final e = pulse(
        easyOnly,
        (t) => t >= 200 && t < 229 ? 150 : 130,
        to: 400,
      );
      expect(e, isEmpty);
    });

    test('genau 30 s Ueberschreitung loest aus, 29 s nicht', () {
      expect(
        pulse(
          easyOnly,
          (t) => t >= 300 && t <= 330 ? 150 : 130,
          to: 400,
        ).length,
        1,
      );
      expect(
        pulse(easyOnly, (t) => t >= 300 && t <= 329 ? 150 : 130, to: 400),
        isEmpty,
      );
    });

    test('Puls genau auf der Grenze ist nicht darueber', () {
      expect(pulse(easyOnly, (_) => 140, to: 600), isEmpty);
    });

    test(
      'Abschnitt unter 4 min (3:50): nie, obwohl 3 min + 30 s hineinpassen',
      () {
        final segs = [seg(PlanSegmentKind.easy, 4, sec: 230, max: 140)];
        expect(pulse(segs, (_) => 160, to: 229), isEmpty);
      },
    );

    test('Abschnitt 3:59: nie (Grenze genau eine Sekunde darunter)', () {
      final segs = [seg(PlanSegmentKind.easy, 4, sec: 239, max: 140)];
      expect(pulse(segs, (_) => 160, to: 238), isEmpty);
    });

    test('Abschnitt genau 4 min: erlaubt', () {
      final segs = [seg(PlanSegmentKind.easy, 4, max: 140)];
      expect(pulse(segs, (_) => 160, to: 239).map((e) => e.$1), [210]);
    });

    test('Zaehlung startet im Abschnitt neu (Wechsel setzt zurueck)', () {
      final segs = [
        seg(PlanSegmentKind.easy, 5, max: 140),
        seg(PlanSegmentKind.easy, 5, max: 140),
      ];
      // Segment 2 beginnt bei 300; dort frueheste Ansage 300 + 210.
      final e = pulse(segs, (t) => t >= 300 ? 160 : 100, to: 590);
      expect(e.map((x) => x.$1), [510]);
    });

    test('nur mit oberer Pulsgrenze im Abschnitt', () {
      expect(
        pulse([seg(PlanSegmentKind.easy, 30)], (_) => 190, to: 600),
        isEmpty,
      );
    });

    test('ohne Pulswert keine Ansage, Luecke setzt die 30 s zurueck', () {
      expect(pulse(easyOnly, (_) => null, to: 600), isEmpty);
      final e = pulse(easyOnly, (t) => t == 200 ? null : 150, to: 400);
      expect(e.map((x) => x.$1), [231]);
    });

    test('ab Minute 60 der Bewegungszeit keine Ansage mehr', () {
      final segs = [seg(PlanSegmentKind.easy, 90, max: 140)];
      final e = pulse(segs, (t) => t >= 3580 ? 160 : 100, from: 3400, to: 4200);
      expect(e, isEmpty);
    });

    test('Minute 60: bei 59:59 noch moeglich, bei 60:00 nicht', () {
      final segs = [seg(PlanSegmentKind.easy, 90, max: 140)];
      // Ueberschreitung seit 3570: 30 s waeren 3600 -> ausserhalb.
      expect(
        pulse(segs, (t) => t >= 3570 ? 160 : 100, from: 3400, to: 3700),
        isEmpty,
      );
      // seit 3569 (Ansage bei 3599).
      expect(
        pulse(
          segs,
          (t) => t >= 3569 ? 160 : 100,
          from: 3400,
          to: 3700,
        ).map((e) => e.$1),
        [3599],
      );
    });

    test('Wiederholung nur nach Rueckkehr in den Bereich und erneut 30 s', () {
      final e = pulse(
        easyOnly,
        (t) => (t >= 200 && t < 400) || t >= 500 ? 150 : 130,
        to: 700,
      );
      expect(e.map((x) => x.$1), [230, 530]);
    });

    test(
      'Wiederanlauf mitten in der Ueberschreitung: Zaehlung beginnt neu',
      () {
        final e = pulse(easyOnly, (_) => 150, from: 500, to: 600);
        expect(e.map((x) => x.$1), [531]);
        // erster Tick ist Basis; erste Auswertung bei 501, Beginn 501 -> 531.
      },
    );

    test('Gehpausen-Hinweis statt Pulsansage, einmalig', () {
      final e = pulse(easyOnly, (_) => 150, to: 1200, walk: true);
      expect(e.map((x) => x.$2.kind), [GuidanceEventKind.walkBreakHint]);
      expect(e.single.$1, 210);
    });

    test(
      'Gehpausen-Hinweis folgt denselben Regeln (kein Puls: kein Hinweis)',
      () {
        expect(pulse(easyOnly, (_) => null, to: 600, walk: true), isEmpty);
        expect(pulse(easyOnly, (_) => 130, to: 600, walk: true), isEmpty);
      },
    );

    test(
      'bereits gegebener Hinweis wird nach Wiederanlauf nicht wiederholt',
      () {
        final sim = Sim(
          GuidanceAnnouncer(
            segments: easyOnly,
            suppressHeartRateForWalkBreaks: true,
            walkBreakHintGiven: true,
          ),
        )..play(0, 600, bpm: (_) => 150);
        expect(sim.events, isEmpty);
      },
    );
  });

  group('Schalter', () {
    final segs = [
      seg(PlanSegmentKind.easy, 2, max: 140),
      seg(PlanSegmentKind.easy, 30, max: 140),
    ];
    Sim run(GuidanceSwitches sw) {
      final sim = Sim(GuidanceAnnouncer(segments: segs, switches: sw))
        ..play(0, 700, bpm: (_) => 150, dist: (t) => t * 3.0);
      return sim;
    }

    test('alle an: jede Art kommt vor', () {
      final kinds = run(const GuidanceSwitches()).events
          .map((e) => e.$2.kind)
          .toSet();
      expect(
        kinds,
        containsAll([
          GuidanceEventKind.kilometer,
          GuidanceEventKind.segmentChange,
          GuidanceEventKind.segmentPreview,
          GuidanceEventKind.heartRateAbove,
        ]),
      );
    });

    test('Hauptschalter aus: nichts', () {
      expect(run(const GuidanceSwitches(enabled: false)).events, isEmpty);
    });

    test('Kilometer aus: nur diese Art fehlt', () {
      final k = run(const GuidanceSwitches(kilometer: false)).events
          .map((e) => e.$2.kind)
          .toSet();
      expect(k, isNot(contains(GuidanceEventKind.kilometer)));
      expect(k, contains(GuidanceEventKind.heartRateAbove));
      expect(k, contains(GuidanceEventKind.segmentChange));
    });

    test('Puls aus: nur diese Art fehlt', () {
      final k = run(const GuidanceSwitches(heartRate: false)).events
          .map((e) => e.$2.kind)
          .toSet();
      expect(k, isNot(contains(GuidanceEventKind.heartRateAbove)));
      expect(k, contains(GuidanceEventKind.kilometer));
      expect(k, contains(GuidanceEventKind.segmentChange));
    });

    test('Abschnitte aus: Wechsel und Vorankuendigung fehlen', () {
      final k = run(const GuidanceSwitches(segments: false)).events
          .map((e) => e.$2.kind)
          .toSet();
      expect(k, isNot(contains(GuidanceEventKind.segmentChange)));
      expect(k, isNot(contains(GuidanceEventKind.segmentPreview)));
      expect(k, contains(GuidanceEventKind.kilometer));
      expect(k, contains(GuidanceEventKind.heartRateAbove));
    });

    test('Gehpausen-Hinweis haengt am Pulsschalter', () {
      final sim = Sim(
        GuidanceAnnouncer(
          segments: easyOnly,
          suppressHeartRateForWalkBreaks: true,
          switches: const GuidanceSwitches(heartRate: false),
        ),
      )..play(0, 600, bpm: (_) => 150);
      expect(sim.events, isEmpty);
    });

    test('Wiederanschalten sagt Altes nicht nach (Kilometer)', () {
      final a = GuidanceAnnouncer(
        segments: const [],
        switches: const GuidanceSwitches(kilometer: false),
      );
      final sim = Sim(a)..play(0, 400, dist: (t) => t * 3.0);
      a.switches = const GuidanceSwitches();
      sim.play(401, 600, dist: (t) => t * 3.0);
      expect(sim.of(GuidanceEventKind.kilometer), isEmpty);
      sim.play(601, 700, dist: (t) => t * 3.0);
      expect(sim.of(GuidanceEventKind.kilometer).map((e) => e.$2.kilometer), [
        2,
      ]);
    });
  });

  group('pulseOverrunSustained', () {
    GuidanceAnnouncer a(GuidanceSwitches sw) =>
        GuidanceAnnouncer(segments: easyOnly, switches: sw);

    test('29 s nein, 30 s ja (Fenster ab 3 min im Abschnitt)', () {
      final x = a(const GuidanceSwitches());
      Sim(x).play(0, 209, bpm: (t) => t < 180 ? 120 : 150);
      expect(x.pulseOverrunSustained, isFalse); // 29 s über der Grenze
      Sim(x).play(210, 210, bpm: (_) => 150);
      expect(x.pulseOverrunSustained, isTrue);
    });

    test('Pause: false, danach wieder true', () {
      final x = a(const GuidanceSwitches());
      Sim(x).play(0, 215, bpm: (t) => t < 180 ? 120 : 150);
      expect(x.pulseOverrunSustained, isTrue);
      Sim(x).play(216, 216, phase: RecordingPhase.paused, bpm: (_) => 150);
      expect(x.pulseOverrunSustained, isFalse);
      Sim(x).play(217, 217, bpm: (_) => 150);
      expect(x.pulseOverrunSustained, isTrue);
    });

    test('Pulsschalter aus: trotzdem true; Puls unter Grenze: false', () {
      final x = a(const GuidanceSwitches(heartRate: false));
      Sim(x).play(0, 215, bpm: (t) => t < 180 ? 120 : 150);
      expect(x.pulseOverrunSustained, isTrue);
      Sim(x).play(216, 216, bpm: (_) => 130);
      expect(x.pulseOverrunSustained, isFalse);
    });
  });
}
