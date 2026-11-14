import 'package:core/core.dart';
import 'package:test/test.dart';

void main() {
  // Review 1, Befund 6: Feinbestimmung des Anstiegs-Bezugspunkts an beiden Rändern der Vorlage.
  // Die Randwerte der Steigungsvorlage waren -inf; `refine` machte daraus NaN, sobald der steilste
  // Anstieg am zweiten oder vorletzten Index lag.
  const fs = 100.0;
  const f0 = 2.0; // Periode 50 Bilder
  final peaks = [for (var k = 0; k < 8; k++) 20 + 50 * k];

  /// Impulsfolge: [pulse] ab dem Gipfelindex minus [pre], sonst 0.
  List<double> train(List<double> pulse, int pre) {
    final x = List<double>.filled(450, 0.0);
    for (final p in peaks) {
      for (var j = 0; j < pulse.length; j++) {
        x[p - pre + j] = pulse[j];
      }
    }
    return x;
  }

  test('steilster Anstieg am zweiten Index (linker Rand): Zeiten endlich', () {
    // pre = 2 (preFrac 0,04), Vorlage 0, 0, 1, 0,9 ... : größte zentrale Differenz bei j = 1.
    final pulse = [0.0, 0.0, 1.0, for (var j = 1; j <= 25; j++) 1.0 - 0.035 * j];
    final r = PpgAnalyzer.templateMatch(
      train(pulse, 2),
      fs,
      peaks,
      f0,
      0.04,
      0.5,
      refOnSlope: true,
    );
    expect(r.times, hasLength(peaks.length));
    expect(r.times.every((t) => t.isFinite), isTrue);
  });

  test('steilster Anstieg am vorletzten Index (rechter Rand): Zeiten endlich', () {
    // pre = 9, post = 2 (Länge 12): 0, ..., 0, 1 nur am letzten Bild: größte Differenz bei j = 10.
    final pulse = [for (var j = 0; j < 11; j++) 0.0, 1.0];
    final r = PpgAnalyzer.templateMatch(
      train(pulse, 9),
      fs,
      peaks,
      f0,
      0.18,
      0.01,
      refOnSlope: true,
    );
    expect(r.times.every((t) => t.isFinite), isTrue);
  });
}
