/// Zusammenbau der Abhängigkeiten der App (ohne DI-Bibliothek).
///
/// Hier werden später die Adapter aus `adapters` an die Ports aus `core`
/// gebunden. Tests setzen stattdessen die Fakes aus `core` ein.
class AppDependencies {
  const AppDependencies();

  /// Verdrahtung für den Produktivbetrieb.
  factory AppDependencies.create() => const AppDependencies();
}
