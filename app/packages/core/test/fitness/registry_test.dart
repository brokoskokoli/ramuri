import 'package:core/core.dart';
import 'package:test/test.dart';

abstract class FakeAlgo extends AlgorithmVariant {
  const FakeAlgo();
  int run(int x, FitnessParameters p);
}

class Fake extends FakeAlgo {
  const Fake(
    this.method,
    this.methodVersion, {
    this.category = AlgorithmCategory.heuristic,
    this.factor = 1,
  });
  @override
  final String method;
  @override
  final int methodVersion;
  @override
  final AlgorithmCategory category;
  final int factor;
  @override
  int run(int x, FitnessParameters p) => x * factor;
}

const family = AlgorithmFamily<FakeAlgo>('fake');
const other = AlgorithmFamily<FakeAlgo>('other');

void main() {
  test('Fake-Variante läuft über die Registry, Wert nennt seine Variante', () {
    final r = AlgorithmRegistry()
      ..register(family, const Fake('a', 1))
      ..register(family, const Fake('b', 1, factor: 3));
    expect(r.active(family).method, 'a');
    r.setActive(family, 'b', 1);
    final v = r.active(family);
    final res = FitnessAvailable<int>(
      value: v.run(2, const FitnessParameters.v4()),
      method: v.method,
      methodVersion: v.methodVersion,
      parameterVersion: currentParameterVersion,
    );
    expect(res.value, 6);
    expect(res.method, 'b');
    expect(r.variants(family).map((e) => e.method), ['a', 'b']);
    expect(r.variants(other), isEmpty);
    expect(() => r.active(other), throwsStateError);
  });

  test('ungültige Varianten werden abgewiesen', () {
    final r = AlgorithmRegistry()..register(family, const Fake('a', 1));
    expect(() => r.register(family, const Fake('', 1)), throwsArgumentError);
    expect(() => r.register(family, const Fake('  ', 1)), throwsArgumentError);
    expect(() => r.register(family, const Fake('x', 0)), throwsArgumentError);
    expect(() => r.register(family, const Fake('x', -1)), throwsArgumentError);
    expect(() => r.register(family, const Fake('a', 1)), throwsArgumentError);
    // gleiche Methode, andere Version ist erlaubt; andere Familie ebenso.
    r.register(family, const Fake('a', 2));
    r.register(other, const Fake('a', 1));
    expect(r.variants(family), hasLength(2));
  });

  test('aktiv setzen nur für registrierte Varianten', () {
    final r = AlgorithmRegistry()..register(family, const Fake('a', 1));
    expect(() => r.setActive(family, 'b', 1), throwsArgumentError);
    expect(() => r.setActive(family, 'a', 2), throwsArgumentError);
    expect(() => r.setActive(other, 'a', 1), throwsArgumentError);
    expect(r.active(family).method, 'a');
  });

  test(
    'jede Variante der Standardbestückung trägt Methode, Version, Kategorie',
    () {
      final all = AlgorithmRegistry.standard().allVariants;
      for (final v in all) {
        expect(v.method.trim(), isNotEmpty, reason: '${v.runtimeType}');
        expect(v.methodVersion, greaterThanOrEqualTo(1));
        expect(AlgorithmCategory.values, contains(v.category));
      }
    },
  );
}
