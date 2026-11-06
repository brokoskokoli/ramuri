import 'package:core/core.dart';
import 'package:test/test.dart';

FitnessValueMetadata meta(QualityTier t, {DateTime? to}) =>
    FitnessValueMetadata(
      calculatedAt: DateTime.utc(2026, 11, 5),
      dataFrom: DateTime.utc(2026, 10, 1),
      dataTo: to ?? DateTime.utc(2026, 11, 1),
      usableMeasurements: 12,
      dataSources: {'gps', 'heart-rate'},
      method: 'm',
      methodVersion: 1,
      parameterVersion: currentParameterVersion,
      tier: t,
    );

void main() {
  test('Ergebnis: Wert und Nicht-verfügbar tragen Variante und Version', () {
    const a = FitnessAvailable<double>(
      value: 0.5,
      method: 'm',
      methodVersion: 1,
      parameterVersion: currentParameterVersion,
      maxIsEstimated: true,
    );
    const u = FitnessUnavailable<double>(
      reason: UnavailableReason.reserveTooSmall,
      method: 'm',
      methodVersion: 1,
      parameterVersion: currentParameterVersion,
    );
    for (final FitnessResult<double> r in [a, u]) {
      expect(r.method, 'm');
      expect(r.methodVersion, 1);
      expect(r.parameterVersion, currentParameterVersion);
    }
    expect(a.maxIsEstimated, isTrue);
    expect(u.maxIsEstimated, isFalse);
    // Exhaustiv: ohne default muss der Switch alle Fälle abdecken.
    String d(FitnessResult<double> r) => switch (r) {
      FitnessAvailable<double>(:final value) => 'v$value',
      FitnessUnavailable<double>(:final reason) => reason.name,
    };
    expect(d(a), 'v0.5');
    expect(d(u), 'reserveTooSmall');
  });

  test('Gründe nach FR-0060, PAR-018, PAR-019, OQ-0051 sind vorhanden', () {
    expect(
      UnavailableReason.values.map((e) => e.name),
      containsAll([
        'missingMaxHeartRate',
        'missingRestingHeartRate',
        'maxNotAboveResting',
        'reserveTooSmall',
        'noHeartRate',
        'insufficientCoverage',
        'noMovingTime',
      ]),
    );
  });

  test('nicht bestimmbar: Grund und kein Wert', () {
    final v = AdvancedFitnessValue<double>(
      metadata: meta(QualityTier.notDeterminable),
      reason: UnavailableReason.insufficientData,
    );
    expect(v.value, isNull);
    expect(v.reason, UnavailableReason.insufficientData);
    expect(
      () => AdvancedFitnessValue<double>(
        metadata: meta(QualityTier.notDeterminable),
      ),
      throwsArgumentError,
    );
    expect(
      () => AdvancedFitnessValue<double>(
        metadata: meta(QualityTier.notDeterminable),
        value: 1,
        reason: UnavailableReason.insufficientData,
      ),
      throwsArgumentError,
    );
    expect(
      () => AdvancedFitnessValue<double>(
        metadata: meta(QualityTier.notDeterminable),
        value: 0,
        reason: UnavailableReason.insufficientData,
      ),
      throwsArgumentError,
    );
  });

  test('übrige Stufen: Wert und kein Grund', () {
    for (final t in [
      QualityTier.preliminary,
      QualityTier.sufficient,
      QualityTier.good,
    ]) {
      final v = AdvancedFitnessValue<double>(metadata: meta(t), value: 0);
      expect(v.value, 0); // eine echte 0 ist ein Wert
      expect(v.reason, isNull);
      expect(
        () => AdvancedFitnessValue<double>(metadata: meta(t)),
        throwsArgumentError,
      );
      expect(
        () => AdvancedFitnessValue<double>(
          metadata: meta(t),
          value: 1,
          reason: UnavailableReason.noHeartRate,
        ),
        throwsArgumentError,
      );
    }
  });

  test('Metadaten: sieben Angaben, Quellen unveränderlich, Prüfungen', () {
    final m = meta(QualityTier.good);
    expect(m.calculatedAt, DateTime.utc(2026, 11, 5));
    expect(m.dataFrom, DateTime.utc(2026, 10, 1));
    expect(m.dataTo, DateTime.utc(2026, 11, 1));
    expect(m.usableMeasurements, 12);
    expect(m.dataSources, {'gps', 'heart-rate'});
    expect(m.method, 'm');
    expect(m.methodVersion, 1);
    expect(m.tier, QualityTier.good);
    expect(() => m.dataSources.add('x'), throwsUnsupportedError);
    expect(
      () => meta(QualityTier.good, to: DateTime.utc(2026, 9, 1)),
      throwsArgumentError,
    );
  });

  test('HeartRateBasis: fehlende Werte bleiben null', () {
    const b = HeartRateBasis();
    expect(b.maxBpm, isNull);
    expect(b.restingBpm, isNull);
    expect(b.maxIsEstimated, isFalse);
  });
}
