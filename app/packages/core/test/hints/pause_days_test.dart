import 'package:core/core.dart';
import 'package:test/test.dart';

/// Bestätigte Pausentage aus der Antwort (PAR-202, K58).
void main() {
  DateTime d(int n) => DateTime.utc(2030, 3, n);

  test('Antwort ja: Tage nach der letzten Einheit bis zum Tag der Antwort', () {
    final days = confirmedPauseDays(
      answer: PauseAnswer(paused: true, on: d(10)),
      unitDays: [d(1), d(2)],
    );
    expect(days, {for (var i = 3; i <= 10; i++) d(i)});
  });

  test('Antwort nein, keine Antwort, keine frühere Einheit: keine Tage', () {
    expect(
      confirmedPauseDays(
        answer: PauseAnswer(paused: false, on: d(10)),
        unitDays: [d(1)],
      ),
      isEmpty,
    );
    expect(confirmedPauseDays(answer: null, unitDays: [d(1)]), isEmpty);
    expect(
      confirmedPauseDays(
        answer: PauseAnswer(paused: true, on: d(10)),
        unitDays: const [],
      ),
      isEmpty,
    );
  });

  test(
    'Einheit nach der Antwort zählt nicht; am Tag der Antwort: kein Pausentag',
    () {
      expect(
        confirmedPauseDays(
          answer: PauseAnswer(paused: true, on: d(10)),
          unitDays: [d(1), d(12)],
        ),
        {for (var i = 2; i <= 10; i++) d(i)},
      );
      expect(
        confirmedPauseDays(
          answer: PauseAnswer(paused: true, on: d(10)),
          unitDays: [d(1), d(10)],
        ),
        isEmpty,
      );
    },
  );
}
