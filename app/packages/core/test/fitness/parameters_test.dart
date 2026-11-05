import 'dart:io';

import 'package:core/core.dart';
import 'package:test/test.dart';

void main() {
  test('Code und docs/model-parameters.md melden dieselbe Version', () {
    final doc = File('../../../docs/model-parameters.md').readAsStringSync();
    final m = RegExp(r'\*\*Status:\*\*[^\n]*?Version (\d+)').firstMatch(doc);
    expect(m, isNotNull, reason: 'Statuszeile mit "Version N" fehlt');
    final docVersion = int.parse(m!.group(1)!);
    expect(currentParameterVersion, docVersion);
    expect(const PreprocessingParameters.v3().parameterVersion, docVersion);
    expect(const FitnessParameters.v3().parameterVersion, docVersion);
    expect(docVersion, 3);
  });

  test('Startwerte aus FR-0062, FR-0092, PAR-019, OQ-0051', () {
    const p = FitnessParameters.v3();
    expect(p.minHeartRateReserveBpm, 50);
    expect(p.reserveZoneBounds, [0.5, 0.6, 0.7, 0.8, 0.9, 1.0]);
    expect(p.trimpZoneLowerBounds, [0.5, 0.6, 0.7, 0.8, 0.9]);
    expect(p.trimpWeights, [1, 2, 3, 4, 5]);
    expect(p.hintAboveShare, 1.0);
    expect(p.minCoveragePercent, 80);
    expect(p.fullCoveragePercent, 100);
  });
}
