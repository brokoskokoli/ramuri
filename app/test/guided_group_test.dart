// Teil G: wiederholte Abschnittsfolgen auf „Lauf vorbereiten“ in einer Zeile
// zusammenfassen (reine Anzeige-Logik, Gesamtdauer und Reihenfolge bleiben).
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/run/guided_segments.dart';

PlanSegment _s(PlanSegmentKind k, int sec, [PlanTargetIntensity? t]) =>
    PlanSegment(
      kind: k,
      minutes: (sec / 60).round(),
      seconds: sec,
      intensity: t,
    );

List<PlanSegment> _walkRun({int n = 8}) => [
  _s(PlanSegmentKind.warmUp, 300),
  for (var i = 0; i < n; i++) ...[
    _s(PlanSegmentKind.run, 60),
    _s(PlanSegmentKind.walk, 120),
  ],
  _s(PlanSegmentKind.coolDown, 300),
];

String _shape(List<SegmentGroup> g) =>
    g.map((e) => '${e.repeat}x${e.segments.length}').join(',');

void main() {
  test('8x Laufen/Gehen: 17 Abschnitte werden 3 Einträge', () {
    final s = _walkRun();
    expect(s.length, 18);
    final g = groupSegments(s);
    expect(_shape(g), '1x1,8x2,1x1');
    expect(g[1].segments.map((e) => e.kind), [
      PlanSegmentKind.run,
      PlanSegmentKind.walk,
    ]);
    expect(g[1].durationSeconds, 8 * 180);
  });

  test('Gesamtdauer und Reihenfolge bleiben', () {
    final s = _walkRun(n: 5);
    final g = groupSegments(s);
    final flat = [
      for (final e in g)
        for (var i = 0; i < e.repeat; i++) ...e.segments,
    ];
    expect(
      flat.map((e) => (e.kind, e.durationSeconds)),
      s.map((e) => (e.kind, e.durationSeconds)),
    );
    expect(
      g.fold<int>(0, (a, e) => a + e.durationSeconds),
      s.fold<int>(0, (a, e) => a + e.durationSeconds),
    );
  });

  test('Auf- und Abwärmen bleiben einzeln, auch wenn sie sich gleichen', () {
    final g = groupSegments([
      _s(PlanSegmentKind.warmUp, 300),
      _s(PlanSegmentKind.warmUp, 300),
      _s(PlanSegmentKind.coolDown, 300),
      _s(PlanSegmentKind.coolDown, 300),
    ]);
    expect(_shape(g), '1x1,1x1,1x1,1x1');
  });

  test(
    'einmaliger Wechsel und ungleiche Dauer werden nicht zusammengefasst',
    () {
      expect(
        _shape(
          groupSegments([
            _s(PlanSegmentKind.run, 60),
            _s(PlanSegmentKind.walk, 120),
          ]),
        ),
        '1x1,1x1',
      );
      expect(
        _shape(
          groupSegments([
            _s(PlanSegmentKind.run, 60),
            _s(PlanSegmentKind.walk, 120),
            _s(PlanSegmentKind.run, 90),
            _s(PlanSegmentKind.walk, 120),
          ]),
        ),
        '1x1,1x1,1x1,1x1',
      );
    },
  );

  test('gleiche Abschnitte hintereinander: eine Folge der Länge 1', () {
    final g = groupSegments([
      _s(PlanSegmentKind.interval, 240),
      _s(PlanSegmentKind.interval, 240),
      _s(PlanSegmentKind.interval, 240),
    ]);
    expect(_shape(g), '3x1');
  });

  test('unterschiedliche Zielwerte trennen die Folge', () {
    const a = PlanTargetIntensity(rpeMin: 7, rpeMax: 8);
    const b = PlanTargetIntensity(rpeMin: 8, rpeMax: 9);
    final g = groupSegments([
      _s(PlanSegmentKind.interval, 240, a),
      _s(PlanSegmentKind.interval, 240, b),
    ]);
    expect(_shape(g), '1x1,1x1');
    final same = groupSegments([
      _s(PlanSegmentKind.interval, 240, a),
      _s(
        PlanSegmentKind.interval,
        240,
        const PlanTargetIntensity(rpeMin: 7, rpeMax: 8),
      ),
    ]);
    expect(_shape(same), '2x1');
  });

  test('Rest nach der Folge bleibt einzeln', () {
    final s = [..._walkRun(n: 3), _s(PlanSegmentKind.run, 60)];
    expect(_shape(groupSegments(s)), '1x1,3x2,1x1,1x1');
  });

  test('leere Liste', () => expect(groupSegments(const []), isEmpty));
}
