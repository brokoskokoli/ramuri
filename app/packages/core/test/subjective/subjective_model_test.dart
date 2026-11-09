import 'package:core/core.dart';
import 'package:test/test.dart';

void main() {
  group('RPE und Befinden: Grenzen im Modell', () {
    for (final (rpe, ok) in [(-1, false), (0, true), (10, true), (11, false)]) {
      test('RPE $rpe ${ok ? 'gültig' : 'abgelehnt'}', () {
        if (ok) {
          expect(RunSubjective(rpe: rpe).rpe, rpe);
        } else {
          expect(
            () => RunSubjective(rpe: rpe),
            throwsA(isA<SubjectiveRangeError>()),
          );
        }
      });
    }
    for (final (w, ok) in [(0, false), (1, true), (5, true), (6, false)]) {
      test('Befinden $w ${ok ? 'gültig' : 'abgelehnt'}', () {
        if (ok) {
          expect(RunSubjective(wellbeing: w).wellbeing, w);
        } else {
          expect(
            () => RunSubjective(wellbeing: w),
            throwsA(isA<SubjectiveRangeError>()),
          );
        }
      });
    }

    test('Fehlertext nennt das Feld, nie den Wert', () {
      try {
        RunSubjective(rpe: 987);
        fail('hätte werfen müssen');
      } on SubjectiveRangeError catch (e) {
        expect(e.toString(), isNot(contains('987')));
        expect(e.toString(), contains('rpe'));
      }
      expect(
        RunSubjective(note: 'GEHEIM-42', complaints: 'KNIE-7').toString(),
        isNot(anyOf(contains('GEHEIM-42'), contains('KNIE-7'))),
      );
    });
  });

  group('Normalisierung', () {
    test('alles optional, leer ist leer', () {
      expect(RunSubjective().isEmpty, isTrue);
      expect(RunSubjective(note: '  ', complaints: '').isEmpty, isTrue);
      expect(RunSubjective(rpe: 0).isEmpty, isFalse);
    });

    test('Antwort auf die Warnsignal-Frage nur mit Beschwerden', () {
      expect(
        RunSubjective(
          complaints: 'Knie',
          warningAnswer: WarningAnswer.yes,
        ).warningAnswer,
        WarningAnswer.yes,
      );
      // Beschwerde entfernt: Antwort zurückgesetzt.
      expect(
        RunSubjective(warningAnswer: WarningAnswer.yes).warningAnswer,
        isNull,
      );
      expect(
        RunSubjective(
          complaints: '  ',
          warningAnswer: WarningAnswer.no,
        ).warningAnswer,
        isNull,
      );
    });
  });

  group('ManualTraining', () {
    ManualTraining make({
      DateTime? day,
      Duration duration = const Duration(minutes: 30),
      int rpe = 4,
    }) => ManualTraining(
      day: day ?? DateTime.utc(2030, 3, 1),
      kind: ManualTrainingKind.other,
      duration: duration,
      rpe: rpe,
    );

    test('Dauer größer 0 in ganzen Sekunden', () {
      expect(make(duration: const Duration(seconds: 1)).duration.inSeconds, 1);
      for (final d in [
        Duration.zero,
        const Duration(seconds: -5),
        const Duration(milliseconds: 1500),
        const Duration(milliseconds: 400),
      ]) {
        expect(
          () => make(duration: d),
          throwsA(isA<SubjectiveRangeError>()),
          reason: '$d',
        );
      }
    });

    for (final (rpe, ok) in [(-1, false), (0, true), (10, true), (11, false)]) {
      test('RPE $rpe ${ok ? 'gültig' : 'abgelehnt'}', () {
        if (ok) {
          expect(make(rpe: rpe).rpe, rpe);
        } else {
          expect(() => make(rpe: rpe), throwsA(isA<SubjectiveRangeError>()));
        }
      });
    }

    test('Tag ist ein Kalendertag, nicht in der Zukunft', () {
      final t = make(day: DateTime(2030, 3, 1, 23, 59));
      expect(t.isoDay, '2030-03-01');
      expect(t.day, DateTime.utc(2030, 3, 1));
      // Heute und früher gehen, morgen nicht.
      t.requireNotAfter(DateTime.utc(2030, 3, 1, 0, 0, 1));
      t.requireNotAfter(DateTime.utc(2030, 3, 9));
      expect(
        () => t.requireNotAfter(DateTime.utc(2030, 2, 28, 23, 59)),
        throwsA(isA<SubjectiveRangeError>()),
      );
    });

    test('sRPE des Trainings: Dauer mal RPE', () {
      expect(
        make(duration: const Duration(minutes: 45), rpe: 5).srpe.points,
        225,
      );
    });
  });
}
