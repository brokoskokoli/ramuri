import 'package:core/core.dart';
import 'package:test/test.dart';

RawHeartRate _hr(int s, String source, int bpm, {MeasurementState? state}) =>
    RawHeartRate(
      time: DateTime.utc(2026, 1, 1, 10, 0, s),
      source: source,
      bpm: bpm,
      state: state ?? MeasurementState.present,
    );

void main() {
  group('Quellgeräte aus gespeicherten Pulswerten (FR-0020)', () {
    test('ohne Pulswerte keine Quelle', () {
      expect(heartRateSourceSections(const []), isEmpty);
      expect(heartRateSourceDevices(const []), isEmpty);
    });

    test(
      'Abschnitte je Gerät in zeitlicher Reihenfolge, unsortiert gelesen',
      () {
        final rows = [
          _hr(5, 'b', 140),
          _hr(1, 'a', 150),
          _hr(3, 'a', 151),
          _hr(6, 'b', 141),
          _hr(8, 'a', 152),
        ];
        final s = heartRateSourceSections(rows);
        expect(s.map((e) => e.deviceId), ['a', 'b', 'a']);
        expect(s.map((e) => e.count), [2, 2, 1]);
        expect(s.first.start, DateTime.utc(2026, 1, 1, 10, 0, 1));
        expect(s.first.end, DateTime.utc(2026, 1, 1, 10, 0, 3));
        expect(heartRateSourceDevices(rows), ['a', 'b']);
      },
    );

    test('Zeilen ohne Wert zählen nicht als Quelle', () {
      final rows = [
        _hr(1, 'a', 150),
        _hr(2, 'b', 0, state: MeasurementState.unavailable),
      ];
      expect(heartRateSourceDevices(rows), ['a']);
    });
  });
}
