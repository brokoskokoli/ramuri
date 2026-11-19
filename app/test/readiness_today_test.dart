import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/readiness/readiness_service.dart';
import 'package:running_app/features/readiness/readiness_today.dart';

/// Readiness-Quelle des Plans (FR-0216, PAR-173): Der Tag des Werts kommt aus
/// der Berechnung, nicht vom Aufrufer. Synthetische Daten ohne Messwerte.

final _today = DateTime.utc(2026, 11, 12);
final _yesterday = DateTime.utc(2026, 11, 11);

ReadinessSnapshot _snap(DateTime? today) => ReadinessSnapshot(
  result: computeReadiness(
    ReadinessInputs(
      today: today ?? _today,
      now: (today ?? _today).add(const Duration(hours: 7)),
    ),
  ),
  developerMode: false,
  extended: true,
  today: today,
);

void main() {
  group('planReadinessSource', () {
    test('Snapshot mit dem Vortag: der Wert trägt den Vortag, nicht den '
        'angefragten Tag', () async {
      final source = planReadinessSource(() async => _snap(_yesterday));
      final r = await source(_today);
      expect(r, isNotNull);
      expect(r!.day, _yesterday);
    });

    test(
      'Snapshot mit dem angefragten Tag: der Wert trägt diesen Tag',
      () async {
        final source = planReadinessSource(() async => _snap(_today));
        expect((await source(_today))!.day, _today);
      },
    );

    test('Snapshot ohne Tag: kein Wert', () async {
      final source = planReadinessSource(() async => _snap(null));
      expect(await source(_today), isNull);
    });

    test('kein Snapshot: kein Wert', () async {
      final source = planReadinessSource(() async => null);
      expect(await source(_today), isNull);
    });
  });
}
