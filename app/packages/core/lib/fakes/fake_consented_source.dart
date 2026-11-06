import '../src/consent/consented_source.dart';

/// Fake-Quelle für Tests; zählt die Zugriffe.
class FakeConsentedSource<T> implements ConsentedSource<T> {
  FakeConsentedSource(this.sourceKey, this.items);

  @override
  final String sourceKey;

  List<T> items;
  int fetchCount = 0;

  /// Wird bei jedem Abruf ausgeführt (etwa, um während des Abrufs zu widerrufen).
  Future<void> Function()? onFetch;

  @override
  Future<List<T>> fetch() async {
    fetchCount++;
    await onFetch?.call();
    return List.of(items);
  }
}
