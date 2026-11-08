/// Schlüssel der Quellen im Freigabe-Rahmen (SEC-0002, SEC-0007). Jede Quelle hat einen eigenen Zustand; die
/// Freigabe einer Quelle gilt nie für eine andere.
library;

/// Kartenanbieter (WP13, ADR-0009 Punkt 3): Kartenausschnitte aus dem Netz. Getrennt von allen anderen Quellen.
const String mapProviderSourceKey = 'map.provider';
