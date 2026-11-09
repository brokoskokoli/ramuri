import 'aerobic_efficiency.dart';
import 'algorithm_variant.dart';
import 'edwards_trimp.dart';
import '../prediction/prediction_registry.dart';
import 'heart_rate_reserve.dart';
import 'reserve_zones.dart';
import 'vo2max_estimator.dart';
import 'vo2max_long_term.dart';

/// Familie -> registrierte Varianten und aktive Variante (NFR-0005).
///
/// Die App baut die Registry zusammen; [AlgorithmRegistry.standard] liefert
/// die Standardbestückung des Pakets. Eine Wahl durch den Nutzer gibt es noch
/// nicht (FR-0197, Phase 2).
///
/// [setActive] wählt nur, was die App danach abfragt. Auf Varianten, die schon
/// aus anderen zusammengesetzt sind (etwa `ReserveZones` mit ihrer Reserve),
/// wirkt es nicht: Die App baut sie mit der aktiven Variante zusammen.
/// Welche Reserve ein Zonenergebnis nutzte, steht im Ergebnis
/// (`reserveMethod`, `reserveMethodVersion`).
class AlgorithmRegistry {
  AlgorithmRegistry();

  /// Standardbestückung. Spätere Pakete tragen ihre Varianten hier ein.
  factory AlgorithmRegistry.standard() => AlgorithmRegistry()
    ..register(heartRateReserveFamily, const HeartRateReserve())
    ..register(
      reserveZonesFamily,
      const ReserveZones(reserve: HeartRateReserve()),
    )
    ..register(loadModelFamily, const EdwardsTrimp())
    ..register(vo2maxEstimatorFamily, const AcsmReserveVo2maxEstimator())
    ..register(vo2maxLongTermFamily, const SmoothedVo2maxLongTerm())
    ..register(aerobicEfficiencyFamily, const MedianAerobicEfficiency())
    ..register(performancePredictionFamily, const RiegelPrediction());

  final Map<String, _Entry> _families = {};

  /// Nimmt [variant] in [family] auf. Die erste Variante einer Familie ist
  /// zunächst aktiv. Wirft [ArgumentError] bei leerer oder blanker Methode,
  /// Version unter 1 oder bereits vorhandener Kennung (Methode und Version).
  void register<V extends AlgorithmVariant>(
    AlgorithmFamily<V> family,
    V variant,
  ) {
    if (variant.method.trim().isEmpty) {
      throw ArgumentError.value(
        variant.method,
        'method',
        'darf nicht leer sein',
      );
    }
    if (variant.methodVersion < 1) {
      throw ArgumentError.value(
        variant.methodVersion,
        'methodVersion',
        'muss mindestens 1 sein',
      );
    }
    final entry = _families.putIfAbsent(family.id, _Entry.new);
    if (entry.find(variant.method, variant.methodVersion) != null) {
      throw ArgumentError(
        'Variante ${variant.method} v${variant.methodVersion} ist in '
        '${family.id} schon registriert',
      );
    }
    entry.variants.add(variant);
    entry.active ??= variant;
  }

  /// Registrierte Varianten in Reihenfolge der Registrierung.
  List<V> variants<V extends AlgorithmVariant>(AlgorithmFamily<V> family) =>
      List.unmodifiable((_families[family.id]?.variants ?? const []).cast<V>());

  /// Aktive Variante; [StateError], wenn die Familie keine hat.
  V active<V extends AlgorithmVariant>(AlgorithmFamily<V> family) {
    final a = _families[family.id]?.active;
    if (a == null) {
      throw StateError('Familie ${family.id} hat keine Variante');
    }
    return a as V;
  }

  /// Macht die registrierte Variante aktiv. [ArgumentError], wenn es sie
  /// nicht gibt.
  void setActive<V extends AlgorithmVariant>(
    AlgorithmFamily<V> family,
    String method,
    int methodVersion,
  ) {
    final entry = _families[family.id];
    final found = entry?.find(method, methodVersion);
    if (entry == null || found == null) {
      throw ArgumentError(
        'Variante $method v$methodVersion ist in ${family.id} nicht registriert',
      );
    }
    entry.active = found;
  }

  /// Alle registrierten Varianten aller Familien (für Prüfungen).
  Iterable<AlgorithmVariant> get allVariants =>
      _families.values.expand((e) => e.variants);
}

class _Entry {
  final List<AlgorithmVariant> variants = [];
  AlgorithmVariant? active;

  AlgorithmVariant? find(String method, int version) {
    for (final v in variants) {
      if (v.method == method && v.methodVersion == version) return v;
    }
    return null;
  }
}
