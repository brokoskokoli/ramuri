import 'package:core/core.dart';
import 'package:test/test.dart';

EasyRunExposure run(int above, int known) => EasyRunExposure(
  aboveUpper: Duration(minutes: above),
  known: Duration(minutes: known),
);

void main() {
  test('2 von 3 Laeufen ueberwiegend darueber: ja', () {
    expect(
      easyRunsMostlyAboveUpper([run(20, 30), run(5, 30), run(16, 30)]),
      isTrue,
    );
  });
  test('nur 1 von 3: nein', () {
    expect(
      easyRunsMostlyAboveUpper([run(20, 30), run(5, 30), run(1, 30)]),
      isFalse,
    );
  });
  test('genau die Haelfte ist nicht ueberwiegend', () {
    expect(run(15, 30).mostlyAbove, isFalse);
    expect(run(16, 30).mostlyAbove, isTrue);
  });
  test('weniger als 3 Laeufe oder kein Puls: nein', () {
    expect(easyRunsMostlyAboveUpper([run(30, 30), run(30, 30)]), isFalse);
    expect(
      easyRunsMostlyAboveUpper([run(0, 0), run(0, 0), run(30, 30)]),
      isFalse,
    );
  });
  test('mehr als 3 Laeufe: nur die ersten 3 zaehlen', () {
    expect(
      easyRunsMostlyAboveUpper([
        run(1, 30),
        run(1, 30),
        run(1, 30),
        run(30, 30),
        run(30, 30),
      ]),
      isFalse,
    );
  });
  test('aus Zonenzeiten: Zone 3 bis 5 ist darueber', () {
    final e = EasyRunExposure.fromZoneTimes([
      for (final m in [5, 5, 10, 5, 5]) Duration(minutes: m),
    ], belowZone1: const Duration(minutes: 5));
    expect(e.aboveUpper, const Duration(minutes: 20));
    expect(e.known, const Duration(minutes: 35));
    expect(e.mostlyAbove, isTrue);
  });
}
