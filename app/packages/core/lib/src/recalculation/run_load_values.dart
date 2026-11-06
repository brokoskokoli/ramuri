import '../../ports/storage_runs.dart';
import '../../ports/storage_values.dart';
import '../fitness/edwards_trimp.dart';
import '../fitness/fitness_parameters.dart';
import '../fitness/fitness_result.dart';
import '../fitness/heart_rate_basis.dart';
import '../fitness/heart_rate_reserve.dart';
import '../fitness/reserve_zones.dart';
import '../preprocessing/run_preprocessor.dart';
import 'run_analysis.dart' show snapshotOf;

/// Zonenzeiten und Trainingsbelastung eines Laufs als Laufwerte (Entscheidung
/// 2026-11-06, FR-0061, OQ-0065 „alte Läufe behalten ihre Zonenzeiten“). Sie
/// werden einmal nach dem Lauf mit den Zonengrenzen und der Herzfrequenzbasis
/// zum Laufende gerechnet und gespeichert. Die Neuberechnung nach einer
/// Profil- oder Zonenänderung (WP09) fasst sie NICHT an (L11).

/// Wertschlüssel der Zeit in Zone [zone] (1 bis [zoneValueCount]).
String zoneTimeValueKey(int zone) => 'zone_time_$zone';

/// Zeit unter Zone 1.
const String zoneBelowValueKey = 'zone_time_below_1';

/// Edwards-TRIMP-Punkte. TRIMP rechnet mit festen Anteilen an HFmax, nicht mit
/// den Zonengrenzen des Editors; aus den Zonenzeiten ist er nicht ableitbar.
const String trimpRunValueKey = 'trimp_run';

const int zoneValueCount = 5;
const String secondsUnit = 's';
const String pointsUnit = 'points';

/// Alle Schlüssel dieser Werte (für die gebündelte Abfrage).
final Set<String> runLoadValueKeys = Set.unmodifiable({
  for (var z = 1; z <= zoneValueCount; z++) zoneTimeValueKey(z),
  zoneBelowValueKey,
  trimpRunValueKey,
});

/// Rechnet die Laufwerte für Zonen und TRIMP. Fehlt ein Ergebnis (Basis oder
/// Daten), steht jeder Wert ohne Zahl mit [ComputedValue.unavailableReason],
/// nie 0. [pre] ist `null` bei einem Lauf ohne Dauer. [fitness] trägt die
/// Zonengrenzen zum Laufende, [basis] die Herzfrequenzbasis (wird als
/// Schnappschuss an jeden Wert geschrieben).
List<ComputedValue> buildRunLoadValues({
  required StoredRun run,
  required RunPreprocessing? pre,
  required HeartRateBasis basis,
  required FitnessParameters fitness,
  required Set<String> sources,
  required DateTime computedAt,
}) {
  final snapshot = snapshotOf(basis);
  final sorted = (sources.toList()..sort());
  ComputedValue make({
    required String key,
    required String unit,
    required FitnessResult<Object?> result,
    double? value,
    ValueQuality? quality,
    int measurements = 0,
  }) {
    final reason = result is FitnessUnavailable ? result.reason : null;
    return ComputedValue(
      key: key,
      value: reason == null ? value : null,
      unavailableReason: reason,
      heartRateBasis: snapshot,
      unit: unit,
      computedAt: computedAt,
      dataFrom: run.startedAt,
      dataTo: run.endedAt,
      measurementCount: measurements,
      sources: sorted,
      method: result.method,
      methodVersion: result.methodVersion,
      parameterVersion: result.parameterVersion,
      quality: reason != null
          ? ValueQuality.undeterminable
          : (quality ?? ValueQuality.good),
    );
  }

  FitnessResult<ReserveZoneTimes> zones;
  FitnessResult<TrimpResult> trimp;
  if (pre == null) {
    FitnessUnavailable<T> noTime<T>(String method, int version) =>
        FitnessUnavailable(
          reason: UnavailableReason.noMovingTime,
          method: method,
          methodVersion: version,
          parameterVersion: fitness.parameterVersion,
          maxIsEstimated: basis.maxIsEstimated,
        );
    zones = noTime(ReserveZones.methodId, 1);
    trimp = noTime(EdwardsTrimp.methodId, 1);
  } else {
    zones = const ReserveZones(reserve: HeartRateReserve()).timeInZones(
      basis: basis,
      heartRate: pre.heartRate,
      movement: pre.movement,
      p: fitness,
    );
    trimp = const EdwardsTrimp().compute(
      basis: basis,
      heartRate: pre.heartRate,
      movement: pre.movement,
      p: fitness,
    );
  }
  final count = pre?.heartRate.acceptedValues.length ?? 0;
  double seconds(int micros) => micros / Duration.microsecondsPerSecond;
  final z = zones is FitnessAvailable<ReserveZoneTimes> ? zones.value : null;
  final t = trimp is FitnessAvailable<TrimpResult> ? trimp.value : null;
  return [
    for (var i = 0; i < zoneValueCount; i++)
      make(
        key: zoneTimeValueKey(i + 1),
        unit: secondsUnit,
        result: zones,
        value: z == null ? null : seconds(z.zoneMicros[i]),
        measurements: count,
      ),
    make(
      key: zoneBelowValueKey,
      unit: secondsUnit,
      result: zones,
      value: z == null ? null : seconds(z.belowZone1Micros),
      measurements: count,
    ),
    make(
      key: trimpRunValueKey,
      unit: pointsUnit,
      result: trimp,
      value: t?.points,
      // Zu wenig Pulsabdeckung für die volle Bewegungszeit: vorläufig.
      quality: t != null && t.incomplete ? ValueQuality.provisional : null,
      measurements: count,
    ),
  ];
}

/// Zonenzeiten und TRIMP eines Laufs, wie sie am Lauf gespeichert sind. Ein
/// Lauf ohne diese Werte (vor dieser Entscheidung gespeichert) ist
/// „nicht gespeichert“; dort steht nichts, nie 0.
class StoredRunLoad {
  const StoredRunLoad({
    this.zoneTimes,
    this.belowZone1Time,
    this.zonesReason,
    this.zonesStored = false,
    this.trimpPoints,
    this.trimpIncomplete = false,
    this.trimpReason,
    this.trimpStored = false,
  });

  /// Kein Wert gespeichert.
  static const StoredRunLoad none = StoredRunLoad();

  /// Aus dem `current` der Werte eines Laufs (Schlüssel aus
  /// [runLoadValueKeys], andere werden ignoriert).
  factory StoredRunLoad.fromValues(Map<String, ComputedValue> v) {
    final zoneValues = [
      for (var z = 1; z <= zoneValueCount; z++) v[zoneTimeValueKey(z)],
      v[zoneBelowValueKey],
    ];
    final present = zoneValues.whereType<ComputedValue>().toList();
    Duration? time(ComputedValue c) => c.value == null
        ? null
        : Duration(
            microseconds: (c.value! * Duration.microsecondsPerSecond).round(),
          );
    final complete =
        present.length == zoneValues.length &&
        present.every((c) => c.value != null);
    final trimp = v[trimpRunValueKey];
    return StoredRunLoad(
      zonesStored: present.isNotEmpty,
      zoneTimes: complete
          ? [for (final c in present.take(zoneValueCount)) time(c)!]
          : null,
      belowZone1Time: complete ? time(present.last) : null,
      zonesReason: present
          .map((c) => c.unavailableReason)
          .whereType<UnavailableReason>()
          .firstOrNull,
      trimpStored: trimp != null,
      trimpPoints: trimp?.value,
      trimpIncomplete:
          trimp != null &&
          trimp.value != null &&
          trimp.quality == ValueQuality.provisional,
      trimpReason: trimp?.unavailableReason,
    );
  }

  /// Zeit je Zone (Index 0 = Zone 1) und unter Zone 1; `null`, wenn nicht
  /// gespeichert oder nicht verfügbar ([zonesReason]).
  final List<Duration>? zoneTimes;
  final Duration? belowZone1Time;

  /// Grund, warum die Zonenzeiten fehlen, wenn sie gespeichert als „nicht
  /// verfügbar“ stehen; `null` bei verfügbar und bei nicht gespeichert.
  final UnavailableReason? zonesReason;
  final bool zonesStored;

  final double? trimpPoints;

  /// Die Pulsabdeckung reichte nicht für die volle Bewegungszeit.
  final bool trimpIncomplete;
  final UnavailableReason? trimpReason;
  final bool trimpStored;
}
