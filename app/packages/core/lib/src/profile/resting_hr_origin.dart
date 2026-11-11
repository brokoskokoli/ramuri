import '../../ports/storage_settings.dart';
import '../settings/display_settings.dart';

/// Haltung bei der Ruhepuls-Messung (FR-0214).
enum RestingPosture {
  sitting('sitting'),
  lying('lying');

  const RestingPosture(this.storageValue);
  final String storageValue;

  static RestingPosture? fromStorage(String? raw) {
    for (final p in values) {
      if (p.storageValue == raw) return p;
    }
    return null;
  }
}

/// Herkunft eines Ruhepulses im Profil. Heute nur die Kamera.
enum RestingHrSource {
  camera('camera');

  const RestingHrSource(this.storageValue);
  final String storageValue;

  static RestingHrSource? fromStorage(String? raw) {
    for (final s in values) {
      if (s.storageValue == raw) return s;
    }
    return null;
  }
}

/// Haltung, Zeitpunkt und Quelle des mit der Kamera gemessenen Ruhepulses
/// (FR-0214, ADR-0011 Punkt 8). Der Wert selbst steht im Profil; dies sind
/// Schlüssel in `settings` ohne Schemaänderung. Sie gelten nur zusammen mit
/// dem Wert, bei dem sie gesetzt wurden: eine manuelle Änderung entfernt sie
/// (`ProfileService.save`). Lesen ist tolerant: fehlt ein Teil oder ist er
/// unlesbar, gibt es keine Herkunft.
class RestingHrOrigin {
  const RestingHrOrigin({
    required this.posture,
    required this.measuredAt,
    this.source = RestingHrSource.camera,
  });

  final RestingPosture posture;

  /// UTC.
  final DateTime measuredAt;
  final RestingHrSource source;

  static Future<RestingHrOrigin?> read(SettingsStore store) async {
    final posture = RestingPosture.fromStorage(
      await store.get(SettingKeys.restingHrPosture),
    );
    final at = DateTime.tryParse(
      await store.get(SettingKeys.restingHrMeasuredAt) ?? '',
    );
    final source = RestingHrSource.fromStorage(
      await store.get(SettingKeys.restingHrSource),
    );
    if (posture == null || at == null || source == null) return null;
    return RestingHrOrigin(posture: posture, measuredAt: at, source: source);
  }

  /// Schreibt alle drei Schlüssel. Ohne Transaktion: zuerst die Quelle leeren,
  /// zuletzt schreiben; sie ist der Commit-Marker. Scheitert ein Schritt,
  /// liefert [read] `null` (nie eine Mischung aus alter und neuer Herkunft).
  /// [at] ist der Schreibzeitpunkt der Zeilen.
  Future<void> write(SettingsStore store, {required DateTime at}) async {
    await store.set(SettingKeys.restingHrSource, '', at: at);
    await store.set(SettingKeys.restingHrPosture, posture.storageValue, at: at);
    await store.set(
      SettingKeys.restingHrMeasuredAt,
      measuredAt.toUtc().toIso8601String(),
      at: at,
    );
    await store.set(SettingKeys.restingHrSource, source.storageValue, at: at);
  }

  /// Entfernt die Herkunft (leere Werte, wie bei den Koeffizienten); schreibt
  /// nur, wo ein Wert steht.
  static Future<void> clear(SettingsStore store, {required DateTime at}) async {
    for (final key in const [
      SettingKeys.restingHrPosture,
      SettingKeys.restingHrMeasuredAt,
      SettingKeys.restingHrSource,
    ]) {
      final v = await store.get(key);
      if (v != null && v.isNotEmpty) await store.set(key, '', at: at);
    }
  }
}
