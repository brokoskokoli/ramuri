import 'package:core/core.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  group('PAR-004 Lücken', () {
    test('Abstand genau 10 s: überbrückt, Distanz gezählt, keine Lücke', () {
      final r = run([pos(0, 0), pos(10, 20)]);
      expect(r.gaps, isEmpty);
      expect(r.distanceMeters, closeTo(20, 1e-6));
    });
    test('Abstand knapp über 10 s: Lücke, Distanz nicht gezählt', () {
      final r = run([pos(0, 0), pos(10.001, 20)]);
      expect(r.gaps, hasLength(1));
      expect(r.gaps.single.state, MeasurementState.unavailable);
      expect(r.gaps.single.start, at(0));
      expect(r.gaps.single.end, at(10.001));
      expect(r.gaps.single.open, isFalse);
      expect(r.distanceMeters, 0);
      expect(r.acceptedPoints, hasLength(2));
    });
    test('Punkt nach der Lücke ist neuer Anker', () {
      final r = run([pos(0, 0), pos(30, 200), pos(31, 205)]);
      expect(r.distanceMeters, closeTo(5, 1e-6));
    });
    test('Die Lücke bleibt auch nach einem Sprungkandidaten eine einzige', () {
      final r = run([pos(0, 0), pos(5, 0, acc: 99), pos(12, 30)]);
      expect(r.gaps, hasLength(1));
      expect(r.distanceMeters, 0);
    });
    test('offene Lücke am Ende: ab mehr als 10 s seit dem letzten Punkt', () {
      final proc = processor()..add(pos(0, 0));
      expect(proc.result(at: at(10)).gaps, isEmpty);
      final g = proc.result(at: at(10.5)).gaps.single;
      expect(g.open, isTrue);
      expect(g.start, at(0));
      expect(g.end, at(10.5));
    });
    test(
      'result ändert den Zustand nicht (offene Lücke verschwindet bei Punkt)',
      () {
        final proc = processor()..add(pos(0, 0));
        proc.result(at: at(60));
        proc.add(pos(1, 2));
        final r = proc.result(at: at(2));
        expect(r.gaps, isEmpty);
        expect(r.distanceMeters, closeTo(2, 1e-6));
      },
    );
    test('abweichender Parameter (5 s) wirkt', () {
      const p = PreprocessingParameters(gapMaxDuration: Duration(seconds: 5));
      expect(run([pos(0, 0), pos(5, 5)], p: p).gaps, isEmpty);
      expect(run([pos(0, 0), pos(5.1, 5)], p: p).gaps, hasLength(1));
    });
  });

  group('PAR-004 Lücke ab Abschnittsbeginn', () {
    test('erster Fix genau 10 s nach Start: keine Lücke', () {
      final proc = processor(const PreprocessingParameters.v2(), at(0))
        ..add(pos(10, 0));
      expect(proc.result(at: at(10)).gaps, isEmpty);
    });
    test('erster Fix knapp über 10 s nach Start: Lücke ab Start', () {
      final proc = processor(const PreprocessingParameters.v2(), at(0))
        ..add(pos(10.001, 0));
      final r = proc.result(at: at(10.001));
      expect(r.gaps, hasLength(1));
      expect(r.gaps.single.start, at(0));
      expect(r.gaps.single.end, at(10.001));
      expect(r.gaps.single.open, isFalse);
      expect(r.distanceMeters, 0);
      expect(r.acceptedPoints, hasLength(1));
    });
    test('erster Fix nach Fortsetzen: 10 s keine, knapp mehr Lücke', () {
      PositionProcessor build(num fixSec) =>
          processor(const PreprocessingParameters.v2(), at(0))
            ..add(pos(1, 0))
            ..pause(at(2))
            ..resume(at(100))
            ..add(pos(fixSec, 5));
      expect(build(110).result(at: at(110)).gaps, isEmpty);
      final g = build(110.001).result(at: at(111)).gaps.single;
      expect(g.start, at(100));
      expect(g.end, at(110.001));
      expect(g.open, isFalse);
    });
    test('gar kein Fix: offene Lücke ab Start erst nach mehr als 10 s', () {
      final proc = processor(const PreprocessingParameters.v2(), at(0));
      expect(proc.result(at: at(10)).gaps, isEmpty);
      final g = proc.result(at: at(10.5)).gaps.single;
      expect(g.open, isTrue);
      expect(g.start, at(0));
      expect(g.end, at(10.5));
    });
    test('Pause während der Lücke schließt sie, Pausenzeit zählt nicht', () {
      final proc = processor(const PreprocessingParameters.v2(), at(0))
        ..pause(at(15));
      final r = proc.result(at: at(500));
      expect(r.gaps, hasLength(1));
      expect(r.gaps.single.end, at(15));
      expect(r.gaps.single.open, isFalse);
    });
    test('Pause nach höchstens 10 s ohne Fix: keine Lücke', () {
      final proc = processor(const PreprocessingParameters.v2(), at(0))
        ..pause(at(10));
      expect(proc.result(at: at(500)).gaps, isEmpty);
    });
    test('Startbezug ist kein Anker: erster Fix wird nicht gefiltert', () {
      final proc = processor(const PreprocessingParameters.v2(), at(0))
        ..add(pos(1, 5000));
      expect(proc.result(at: at(1)).acceptedPoints, hasLength(1));
    });
  });

  group('Überbrückung', () {
    test(
      'Aussetzer <= 10 s mit verworfenem Punkt: gerade Distanz, geschätzt',
      () {
        final r = run([pos(0, 0), pos(3, 9, acc: 90), pos(6, 18)]);
        expect(r.distanceMeters, closeTo(18, 1e-6));
        expect(r.bridgedDistanceMeters, closeTo(18, 1e-6));
        expect(r.positions[1].state, MeasurementState.discarded);
        expect(r.positions[2].state, MeasurementState.estimated);
        expect(r.positions[2].countedDistanceMeters, closeTo(18, 1e-6));
      },
    );
    test('reiner Taktabstand ohne verworfene Punkte ist normal', () {
      final r = run([pos(0, 0), pos(8, 10)]);
      expect(r.positions[1].state, MeasurementState.present);
      expect(r.bridgedDistanceMeters, 0);
      expect(r.distanceMeters, closeTo(10, 1e-6));
    });
    test('Aussetzer über 10 s: keine Überbrückung, nur Lücke', () {
      final r = run([pos(0, 0), pos(5, 5, acc: 90), pos(12, 20)]);
      expect(r.distanceMeters, 0);
      expect(r.bridgedDistanceMeters, 0);
      expect(r.positions[2].state, MeasurementState.present);
    });
    test('Sensor liefert estimated: Punkt bleibt geschätzt, zählt aber', () {
      final r = run([pos(0, 0), pos(1, 3, state: MeasurementState.estimated)]);
      expect(r.positions[1].state, MeasurementState.estimated);
      expect(r.bridgedDistanceMeters, 0);
      expect(r.distanceMeters, closeTo(3, 1e-6));
    });
  });

  group('Manuelle Pause', () {
    test('keine Distanz über die Pause, Pausenzeit ist keine Lücke', () {
      final proc = processor()
        ..add(pos(0, 0))
        ..add(pos(1, 3))
        ..pause(at(2))
        ..resume(at(500))
        ..add(pos(501, 2000))
        ..add(pos(502, 2004));
      final r = proc.result(at: at(502));
      expect(r.distanceMeters, closeTo(3 + 4, 1e-6));
      expect(r.gaps, isEmpty);
      expect(r.positions[2].countedDistanceMeters, closeTo(0, 1e-9));
    });
    test('Punkte während der Pause sind nicht verfügbar und zählen nicht', () {
      final proc = processor()
        ..add(pos(0, 0))
        ..pause(at(1));
      final during = proc.add(pos(2, 5));
      proc.resume(at(3));
      expect(during.state, MeasurementState.unavailable);
      expect(during.reason, isNull);
      expect(proc.result(at: at(3)).acceptedPoints, hasLength(1));
    });
    test('während der Pause entsteht keine offene Lücke', () {
      final proc = processor()
        ..add(pos(0, 0))
        ..pause(at(2));
      expect(proc.result(at: at(900)).gaps, isEmpty);
    });
    test('Lücke vor der Pause wird am Pausenbeginn geschlossen', () {
      final proc = processor()
        ..add(pos(0, 0))
        ..pause(at(20));
      final g = proc.result(at: at(900)).gaps.single;
      expect(g.end, at(20));
      expect(g.open, isFalse);
    });
    test('nach dem Fortsetzen kann wieder eine Lücke entstehen', () {
      final proc = processor()
        ..add(pos(0, 0))
        ..pause(at(1))
        ..resume(at(100))
        ..add(pos(101, 0));
      expect(proc.result(at: at(112)).gaps.single.open, isTrue);
    });
  });

  group('Zuordnung über Zeitstempel (FR-0046)', () {
    test(
      'letzter akzeptierter Wert <= t mit Alter; verworfene zählen nicht',
      () {
        final proc = processor()
          ..add(pos(0, 0))
          ..add(pos(4, 5, acc: 90))
          ..add(pos(5, 4));
        final l = proc.positionAt(at(8));
        expect(l.state, MeasurementState.present);
        expect(l.value!.time, at(5));
        expect(l.age, const Duration(seconds: 3));
        expect(proc.positionAt(at(5)).age, Duration.zero);
        expect(proc.positionAt(at(4.5)).value!.time, at(0));
      },
    );
    test('vor dem ersten Punkt: nicht verfügbar, ohne Alter', () {
      final proc = processor()..add(pos(5, 0));
      final l = proc.positionAt(at(1));
      expect(l.state, MeasurementState.unavailable);
      expect(l.value, isNull);
      expect(l.age, isNull);
    });
    test('Alter genau 10 s verfügbar, darüber nicht verfügbar (mit Alter)', () {
      final proc = processor()..add(pos(0, 0));
      expect(proc.positionAt(at(10)).state, MeasurementState.present);
      final l = proc.positionAt(at(10.5));
      expect(l.state, MeasurementState.unavailable);
      expect(l.value, isNull);
      expect(l.age, const Duration(milliseconds: 10500));
    });
    test('LatestValueIndex ohne Grenze liefert nur das Alter', () {
      final idx = LatestValueIndex<int>()..add(at(0), 7);
      final l = idx.valueAt(at(3600));
      expect(l.state, MeasurementState.present);
      expect(l.age, const Duration(hours: 1));
    });
  });
}
