import 'package:core/core.dart';
import 'package:test/test.dart';

import 'support.dart';

/// Neu ankern bei Positionssprüngen (Vorschlag, Bezug PAR-002/PAR-003/PAR-004,
/// `reanchorCount` = 3; nicht in docs/model-parameters.md).
void main() {
  group('Neu ankern nach aufeinanderfolgenden Sprungverwürfen', () {
    test('falscher erster Punkt weit weg: nach 3 Punkten wird gezählt, '
        'ohne Versatz', () {
      final r = run([
        pos(0, 500000), // falscher Standardpunkt
        pos(1, 0), pos(2, 3), pos(3, 6), // hardJump, hardJump, Re-Anker
        pos(4, 9), pos(5, 12), pos(6, 15),
      ]);
      expect(r.positions.map((p) => p.state.name), [
        'present',
        'discarded',
        'discarded',
        'present',
        'present',
        'present',
        'present',
      ]);
      expect(r.positions[3].reanchored, isTrue);
      expect(r.positions[3].countedDistanceMeters, 0);
      expect(r.distanceMeters, closeTo(9, 1e-3), reason: '3 Schritte à 3 m');
      expect(r.acceptedPoints, hasLength(5));
    });

    test('der Übergang ist eine Lücke, auch kürzer als PAR-004', () {
      final r = run([pos(0, 500000), pos(1, 0), pos(2, 3), pos(3, 6)]);
      expect(r.gaps, hasLength(1));
      expect(r.gaps.single.start, at(0));
      expect(r.gaps.single.end, at(3));
      expect(r.gaps.single.open, isFalse);
      expect(r.gaps.single.end.difference(r.gaps.single.start).inSeconds, 3);
    });

    test('falscher Anker 500 m daneben: Versatz nie in der Strecke', () {
      // 5 s Abstand: 100 m/s zum Anker, hardJump; der Rest geht mit 3 m/s.
      final r = run([
        pos(0, 500),
        pos(5, 0),
        pos(10, 15),
        pos(15, 30),
        pos(16, 33),
      ]);
      expect(r.positions[1].reason, DiscardReason.hardJump);
      expect(r.positions[3].reanchored, isTrue);
      expect(r.distanceMeters, closeTo(3, 1e-3));
      expect(r.positions.every((p) => p.countedDistanceMeters < 100), isTrue);
    });

    test('ohne Re-Anker (Anzahl 99) würde der Anker hängen bleiben', () {
      const p = PreprocessingParameters(parameterVersion: 3, reanchorCount: 99);
      final r = run([pos(0, 500), pos(5, 0), pos(10, 15), pos(15, 30)], p: p);
      expect(r.acceptedPoints, hasLength(1));
    });

    test('Einzelausreißer bleibt verworfen, kein Re-Anker', () {
      final r = run([pos(0, 0), pos(1, 3), pos(2, 5000), pos(3, 9)]);
      expect(r.positions[2].reason, DiscardReason.hardJump);
      expect(r.positions.any((p) => p.reanchored), isFalse);
      expect(r.gaps, isEmpty);
      expect(r.distanceMeters, closeTo(9, 1e-3));
    });

    test('drei Ausreißer, die untereinander nicht passen: kein Re-Anker', () {
      final r = run([
        pos(0, 0),
        pos(1, 500),
        pos(2, 1000),
        pos(3, 1500),
        pos(4, 2000),
      ]);
      expect(r.positions.skip(1).every((p) => p.reason != null), isTrue);
      expect(r.acceptedPoints, hasLength(1));
      expect(r.gaps, isEmpty);
    });

    test('ein gültiger Punkt dazwischen beendet die Folge', () {
      final r = run([
        pos(0, 0),
        pos(1, 500), pos(2, 503), // zwei passende Ausreißer
        pos(3, 6), // gültig gegen den Anker
        pos(4, 509), // wieder ein einzelner Ausreißer
        pos(5, 9),
      ]);
      expect(r.positions.any((p) => p.reanchored), isFalse);
      expect(r.gaps, isEmpty);
      expect(r.distanceMeters, closeTo(9, 1e-3));
    });
  });
}
