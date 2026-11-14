/// Schlüssel der Quellen im Freigabe-Rahmen (SEC-0002, SEC-0007). Jede Quelle hat einen eigenen Zustand; die
/// Freigabe einer Quelle gilt nie für eine andere.
library;

import '../../ports/health_import.dart';

/// Kartenanbieter (WP13, ADR-0009 Punkt 3): Kartenausschnitte aus dem Netz. Getrennt von allen anderen Quellen.
const String mapProviderSourceKey = 'map.provider';

/// Health Connect (WP32, ADR-0007): eine Einwilligung je Datenart, getrennt von allen anderen Quellen. Die Einwilligung
/// ist nur die eigene Freigabe der App; gelesen wird zusätzlich nur mit dem Recht von Health Connect.
String healthSourceKey(HealthDataKind kind) => 'health.${kind.key}';
