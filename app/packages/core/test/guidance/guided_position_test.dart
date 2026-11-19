import 'package:core/core.dart';
import 'package:test/test.dart';

PlanSegment seg(PlanSegmentKind k, int min, {int? sec}) =>
    PlanSegment(kind: k, minutes: min, seconds: sec);

void main() {
  final segs = [
    seg(PlanSegmentKind.warmUp, 5),
    seg(PlanSegmentKind.interval, 3),
    seg(PlanSegmentKind.coolDown, 5),
  ];

  test('Abschnitt, Index, Restzeit, naechster', () {
    final p = guidedPosition(segs, const Duration(minutes: 6));
    expect(p.index, 1);
    expect(p.segment!.kind, PlanSegmentKind.interval);
    expect(p.next!.kind, PlanSegmentKind.coolDown);
    expect(p.elapsedInSegment, const Duration(minutes: 1));
    expect(p.remaining, const Duration(minutes: 2));
    expect(p.finished, isFalse);
  });

  test('Grenze: genau am Ende beginnt der naechste Abschnitt', () {
    expect(guidedPosition(segs, const Duration(minutes: 5)).index, 1);
    expect(
      guidedPosition(segs, const Duration(minutes: 5, seconds: -1)).index,
      0,
    );
  });

  test('fertig nach der Summe, auch weit danach', () {
    final p = guidedPosition(segs, const Duration(minutes: 13));
    expect(p.finished, isTrue);
    expect(p.index, 3);
    expect(p.segment, isNull);
    expect(guidedPosition(segs, const Duration(hours: 5)).finished, isTrue);
  });

  test(
    'Geh-Lauf: Sekunden zaehlen, Abschnitte ohne Dauer werden uebersprungen',
    () {
      final s = [
        seg(PlanSegmentKind.run, 2, sec: 90),
        seg(PlanSegmentKind.walk, 0, sec: 0),
        seg(PlanSegmentKind.walk, 1, sec: 60),
      ];
      final p = guidedPosition(s, const Duration(seconds: 89));
      expect(p.index, 0);
      expect(p.next!.kind, PlanSegmentKind.walk);
      expect(p.remaining, const Duration(seconds: 1));
      expect(guidedPosition(s, const Duration(seconds: 90)).index, 2);
    },
  );

  test('leere Liste und negative Zeit', () {
    expect(guidedPosition(const [], Duration.zero).finished, isTrue);
    expect(guidedPosition(segs, const Duration(seconds: -5)).index, 0);
  });

  test(
    'Pause haelt: gleiche Bewegungszeit, gleicher Stand (reine Funktion)',
    () {
      final a = guidedPosition(segs, const Duration(minutes: 7));
      final b = guidedPosition(segs, const Duration(minutes: 7));
      expect(a.index, b.index);
      expect(a.remaining, b.remaining);
    },
  );

  group('Sprünge (FR-0218)', () {
    Duration m(int min, [int sec = 0]) => Duration(minutes: min, seconds: sec);

    test('mitten im Abschnitt: nächster ab jetzt mit voller Dauer, '
        'folgende rücken nach', () {
      // Intervall (5:00–8:00) bei 6:00 übersprungen.
      final skips = [m(6)];
      final p = guidedPosition(segs, m(6), skips: skips);
      expect(p.index, 2);
      expect(p.segment!.kind, PlanSegmentKind.coolDown);
      expect(p.elapsedInSegment, Duration.zero);
      expect(p.remaining, m(5));
      // Abwärmen endet 6:00 + 5:00 statt 13:00; die Einheit ist 2 min kürzer.
      expect(guidedPosition(segs, m(10, 59), skips: skips).index, 2);
      expect(
        guidedPosition(segs, m(10, 59), skips: skips).remaining,
        const Duration(seconds: 1),
      );
      expect(guidedPosition(segs, m(11), skips: skips).finished, isTrue);
      // Vor dem Sprung gilt der Stand nach Zeit.
      final before = guidedPosition(segs, m(5, 30), skips: skips);
      expect(before.index, 1);
      expect(before.remaining, m(2, 30));
    });

    test('nachrückende Abschnitte: Sprung im ersten verschiebt alle', () {
      final s = [
        seg(PlanSegmentKind.warmUp, 5),
        seg(PlanSegmentKind.interval, 3),
        seg(PlanSegmentKind.recovery, 2),
        seg(PlanSegmentKind.coolDown, 5),
      ];
      final skips = [m(1)];
      expect(guidedPosition(s, m(3, 59), skips: skips).index, 1);
      expect(guidedPosition(s, m(4), skips: skips).index, 2);
      expect(guidedPosition(s, m(6), skips: skips).index, 3);
      expect(guidedPosition(s, m(6), skips: skips).remaining, m(5));
      expect(guidedPosition(s, m(11), skips: skips).finished, isTrue);
    });

    test('im Aufwärmen und im Abwärmen', () {
      final warm = guidedPosition(segs, m(2), skips: [m(2)]);
      expect(warm.index, 1);
      expect(warm.remaining, m(3));
      // Abwärmen (8:00–13:00) bei 9:00 übersprungen: Einheit fertig.
      final cool = guidedPosition(segs, m(9), skips: [m(9)]);
      expect(cool.finished, isTrue);
      expect(cool.index, segs.length);
      expect(guidedPosition(segs, m(8, 59), skips: [m(9)]).index, 2);
    });

    test('Sprung im letzten Abschnitt → finished, auch später', () {
      final p = guidedPosition(segs, m(12), skips: [m(12)]);
      expect(p.finished, isTrue);
      expect(p.segment, isNull);
      expect(p.remaining, Duration.zero);
      expect(guidedPosition(segs, m(40), skips: [m(12)]).finished, isTrue);
    });

    test('mehrere Sprünge, auch zur selben Zeit (Pause)', () {
      final two = guidedPosition(segs, m(1), skips: [m(1), m(1)]);
      expect(two.index, 2);
      expect(two.remaining, m(5));
      final later = guidedPosition(segs, m(4), skips: [m(1), m(3)]);
      // Aufwärmen endet 1:00, Intervall 1:00–3:00 übersprungen bei 3:00.
      expect(later.index, 2);
      expect(later.elapsedInSegment, m(1));
      // Reihenfolge der Liste spielt keine Rolle.
      final swapped = guidedPosition(segs, m(4), skips: [m(3), m(1)]);
      expect(swapped.index, later.index);
      expect(swapped.remaining, later.remaining);
    });

    test('Sprünge nach der Bewegungszeit oder nach dem Ende zählen nicht', () {
      final p = guidedPosition(segs, m(6), skips: [m(7)]);
      expect(p.index, 1);
      expect(p.remaining, m(2));
      final end = guidedPosition(segs, m(20), skips: [m(15)]);
      expect(end.finished, isTrue);
    });

    test('Geh-Lauf: Abschnitt ohne Dauer zählt nicht als übersprungen', () {
      final s = [
        seg(PlanSegmentKind.run, 2, sec: 90),
        seg(PlanSegmentKind.walk, 0, sec: 0),
        seg(PlanSegmentKind.walk, 1, sec: 60),
        seg(PlanSegmentKind.run, 1, sec: 60),
      ];
      final p = guidedPosition(
        s,
        const Duration(seconds: 30),
        skips: const [Duration(seconds: 30)],
      );
      expect(p.index, 2);
      expect(p.remaining, const Duration(seconds: 60));
    });

    test('ohne Sprünge identisch zu heute (Eigenschaft)', () {
      final lists = [
        segs,
        [
          seg(PlanSegmentKind.run, 0, sec: 15),
          seg(PlanSegmentKind.walk, 0, sec: 0),
          seg(PlanSegmentKind.walk, 0, sec: 45),
        ],
        <PlanSegment>[],
      ];
      for (final l in lists) {
        for (var t = -2; t <= 14 * 60; t++) {
          final d = Duration(seconds: t);
          final a = guidedPosition(l, d);
          final b = guidedPosition(l, d, skips: const []);
          expect(
            (b.index, b.remaining, b.elapsedInSegment, b.finished, b.next),
            (a.index, a.remaining, a.elapsedInSegment, a.finished, a.next),
            reason: 't=$t',
          );
          // Ein Sprung erst nach t ändert nichts.
          if (t < 0) continue;
          final c = guidedPosition(
            l,
            d,
            skips: [d + const Duration(seconds: 1)],
          );
          expect(
            (c.index, c.remaining),
            (a.index, a.remaining),
            reason: 't=$t',
          );
        }
      }
    });
  });
}
