import 'algorithm_variant.dart';

/// Lesesicht auf die Algorithmen-Registry (ADR-0004, NFR-0005): die aktive
/// Variante je Familie.
///
/// Die Rechnungen in `recalculation` hängen nur an dieser Sicht, nicht an
/// `AlgorithmRegistry` (Modul `algorithms`), denn die Registry importiert
/// `plan` und `prediction`; eine Kante von `recalculation` dorthin schlösse
/// einen Modulzyklus. Die App übergibt ihre eine Registry
/// (`AlgorithmRegistry.standard()`) als diese Sicht.
abstract interface class AlgorithmLookup {
  /// Aktive Variante von [family]; [StateError], wenn die Familie keine hat.
  V active<V extends AlgorithmVariant>(AlgorithmFamily<V> family);
}
