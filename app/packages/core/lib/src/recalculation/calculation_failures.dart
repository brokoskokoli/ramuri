import '../../ports/clock.dart';
import '../../ports/storage_settings.dart';
import '../fitness/fitness_parameters.dart';
import '../fitness/vo2max_estimator.dart';
import '../preprocessing/preprocessing_parameters.dart';

/// Nach so vielen gescheiterten Versuchen beim Nachholen gilt ein Lauf als
/// „nicht berechenbar“: der App-Start versucht ihn nicht mehr (FR-0219).
const int uncomputableAfterFailures = 3;

/// Zähler der gescheiterten Berechnungsversuche beim Nachholen je Lauf
/// (FR-0219). Technischer Merker in `settings`, keine Gesundheitsdaten, nicht
/// im Archiv (wie `values.calculationPending`).
///
/// Format des Werts: `<stand>;<id>:<anzahl>,<id>:<anzahl>`, aufsteigend nach
/// Lauf-ID; leer = keine Fehlversuche. `<stand>` ist der Stand der Berechnung,
/// mit dem gezählt wurde ([calculationStamp]); weicht er vom Stand der App ab
/// (neue Methoden- oder Parameterversion, ADR-0004), gelten alle Zähler als
/// zurückgesetzt. Nicht lesbare Teile werden übergangen.
class CalculationFailures {
  CalculationFailures({
    required this.settings,
    required this.clock,
    this.fitness = const FitnessParameters.v5(),
    this.preprocessing = const PreprocessingParameters.v5(),
  });

  /// Einstellungsschlüssel des Zählers.
  static const String key = 'values.calculationFailures';

  final SettingsStore settings;
  final Clock clock;
  final FitnessParameters fitness;
  final PreprocessingParameters preprocessing;

  /// Stand der Berechnung: Parameterversionen und Methode des VO₂max-Laufwerts
  /// (dieselben Angaben, die die Neuberechnung bei einer neuen Version anbieten,
  /// [RecalculationService.checkVersions]).
  String get calculationStamp =>
      'p${fitness.parameterVersion}-${preprocessing.parameterVersion}'
      '-$vo2maxEstimatorMethod-$vo2maxEstimatorMethodVersion';

  /// Gescheiterte Versuche je Lauf zum aktuellen Stand der Berechnung.
  Future<Map<int, int>> read() async {
    final raw = await settings.get(key) ?? '';
    final split = raw.indexOf(';');
    if (split < 0 || raw.substring(0, split) != calculationStamp) return {};
    final out = <int, int>{};
    for (final part in raw.substring(split + 1).split(',')) {
      final kv = part.split(':');
      if (kv.length != 2) continue;
      final id = int.tryParse(kv[0]);
      final n = int.tryParse(kv[1]);
      if (id == null || n == null || n <= 0) continue;
      out[id] = n;
    }
    return out;
  }

  Future<void> _write(Map<int, int> counts) {
    final ids = counts.keys.where((id) => counts[id]! > 0).toList()..sort();
    final value = ids.isEmpty
        ? ''
        : '$calculationStamp;${ids.map((id) => '$id:${counts[id]}').join(',')}';
    return settings.set(key, value, at: clock.now());
  }

  /// Läufe, deren Berechnung beim Nachholen [uncomputableAfterFailures]-mal
  /// gescheitert ist; sie werden beim Start nicht mehr versucht.
  Future<Set<int>> uncomputable() async => {
    for (final e in (await read()).entries)
      if (e.value >= uncomputableAfterFailures) e.key,
  };

  /// Zählt einen gescheiterten Versuch für Lauf [runId].
  Future<void> recordFailure(int runId) async {
    final counts = await read();
    counts[runId] = (counts[runId] ?? 0) + 1;
    await _write(counts);
  }

  /// Entfernt die Zähler der Läufe [runIds] (Berechnung gelungen, Lauf
  /// gelöscht). Schreibt nur, wenn sich etwas ändert.
  Future<void> remove(Iterable<int> runIds) async {
    final counts = await read();
    final before = counts.length;
    counts.removeWhere((id, _) => runIds.contains(id));
    if (counts.length != before) await _write(counts);
  }

  /// Setzt alle Zähler zurück („Neu berechnen“, FR-0219).
  Future<void> clear() async {
    if ((await settings.get(key) ?? '').isNotEmpty) {
      await settings.set(key, '', at: clock.now());
    }
  }
}
