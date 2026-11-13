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
}
