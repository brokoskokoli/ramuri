import '../fitness/heart_rate_basis.dart';
import '../prediction/prediction_parameters.dart';
import '../prediction/riegel.dart';
import '../settings/reserve_zone_settings.dart';
import 'plan_unit.dart';

/// Kennung und Version der Zielintensität (NFR-0001, NFR-0005).
const String targetIntensityMethod = 'target-intensity';
const int targetIntensityMethodVersion = 1;

/// Stand der Zahlen in [IntensityParameters].
const int targetIntensityParameterVersion = 1;

/// Grundlage einer Vorgabe (PAR-106). Der Code wird gespeichert
/// (`basisCode`), der Text-Schlüssel gehört zu den Oberflächentexten (WP22).
/// [germanText] ist der feste Wortlaut aus PAR-106; die englische Fassung
/// nennt die Regel nicht und kommt mit WP22.
enum IntensityBasis {
  /// Rang 2 (PAR-101, PAR-102): aus Referenzleistung per Riegel.
  reference('reference', 'planBasisReference', 'aus deiner Referenzzeit'),

  /// Rang 3 (PAR-103): aus der VO₂max-Schätzung.
  vo2max('vo2max', 'planBasisVo2max', 'aus deiner VO₂max-Schätzung'),

  /// Rang 4 (PAR-104): Herzfrequenzzonen.
  heartRateZones(
    'heart_rate_zones',
    'planBasisHeartRateZones',
    'aus deinen Herzfrequenzzonen',
  ),

  /// Rang 5 (PAR-105): nur RPE.
  effort('effort', 'planBasisEffort', 'nach Gefühl');

  const IntensityBasis(this.code, this.textKey, this.germanText);

  /// Gespeicherter Code (`PlanTargetIntensity.basisCode`).
  final String code;

  /// Schlüssel des Oberflächentexts (Präfix `plan`).
  final String textKey;

  /// Wortlaut nach PAR-106.
  final String germanText;

  /// Umkehrung von [code]; unbekannt: `null`.
  static IntensityBasis? fromCode(String? code) {
    for (final b in values) {
      if (b.code == code) return b;
    }
    return null;
  }
}

/// Güte des VO₂max-Langzeitwerts (PAR-081, PAR-082). „Vorläufig“ und „nicht
/// bestimmbar“ gibt es hier nicht: Der Aufrufer reicht dann `null`.
enum Vo2maxGrade { sufficient, good }

/// RPE-Bereich auf der Skala 0 bis 10 (PAR-105).
class RpeRange {
  const RpeRange(this.min, this.max);
  final int min;
  final int max;
}

/// Alle Zahlen der Zielintensität, jede mit ihrer Regel.
class IntensityParameters {
  const IntensityParameters({
    this.rpeEasy = const RpeRange(2, 4),
    this.rpeLong = const RpeRange(3, 4),
    this.rpeInterval = const RpeRange(7, 8),
    this.rpeRecovery = const RpeRange(1, 3),
    this.rpeTempo = const RpeRange(6, 7),
    this.rpeEndBlock = const RpeRange(5, 7),
    this.rpeWalkRun = const RpeRange(1, 4),
    this.intervalFastMeters = 3000,
    this.intervalSlowMeters = 5000,
    this.tempoSlowMeters = 21097.5,
    this.tempoFastMeters = 10000,
    this.tempoFastMinutes = 60,
    this.easyLimitFactor = 1.10,
    this.referenceYoungDays = 21,
    this.referenceMidDays = 91,
    this.referenceMaxDays = 182,
    this.referenceWidthYoung = 0.03,
    this.referenceWidthMid = 0.06,
    this.referenceWidthOld = 0.10,
    this.pauseExcludesDays = 56,
    this.vo2maxShareEasy = 0.65,
    this.vo2maxShareTempo = 0.80,
    this.vo2maxMinSpeedMetersPerMinute = 134,
    this.vo2maxWidthSufficient = 0.13,
    this.vo2maxWidthGood = 0.06,
    this.vo2maxRestMl = 3.5,
    this.vo2maxSlopeMl = 0.2,
    this.easyMaxShareOfMaxHr = 0.80,
    this.minReferenceMeters = 3000,
  });

  /// Lockerer Dauerlauf, Auf- und Abwärmen (PAR-109, PAR-119 bis PAR-121).
  final RpeRange rpeEasy;

  /// Längerer Dauerlauf (PAR-110).
  final RpeRange rpeLong;

  /// Intervalle (PAR-112).
  final RpeRange rpeInterval;

  /// Trabpause: RPE höchstens 3 (PAR-112); die Untergrenze 1 ist eigene Wahl
  /// (0 heißt Ruhe, die Speicherung verlangt mindestens 1).
  final RpeRange rpeRecovery;

  /// Tempodauerlauf (PAR-113).
  final RpeRange rpeTempo;

  /// Endblock des progressiven Laufs (PAR-114).
  final RpeRange rpeEndBlock;

  /// Geh-/Laufintervalle: Lauf höchstens 4 (PAR-115). Gehen höchstens 2; die
  /// Abschnitte unterscheiden das nicht, daher gilt eine Spanne für die
  /// Einheit.
  final RpeRange rpeWalkRun;

  /// Rang 2: Intervalle zwischen Tempo über 3 km und 5 km (PAR-102).
  final double intervalFastMeters;
  final double intervalSlowMeters;

  /// Rang 2: Tempodauerlauf, langsames Ende = Halbmarathon, schnelles Ende =
  /// das langsamere aus Tempo über 10 km und Riegel-Tempo für 60 min
  /// (PAR-102).
  final double tempoSlowMeters;
  final double tempoFastMeters;
  final double tempoFastMinutes;

  /// Rang 2: lockere Grenze = Halbmarathon-Tempo, mindestens 10 % langsamer
  /// (PAR-102).
  final double easyLimitFactor;

  /// Rang 2: Alter der Referenz und Bandbreite nach unten (PAR-101): unter
  /// [referenceYoungDays] 3 %, unter [referenceMidDays] 6 %, bis
  /// [referenceMaxDays] 10 %, älter keine Pace.
  final int referenceYoungDays;
  final int referenceMidDays;
  final int referenceMaxDays;
  final double referenceWidthYoung;
  final double referenceWidthMid;
  final double referenceWidthOld;

  /// Rang 2: Pause ab so vielen Tagen seit der Referenz sperrt die Pace
  /// (PAR-101, PAR-202: 8 Wochen).
  final int pauseExcludesDays;

  /// Rang 3: Reserveanteil `r` für locker und Tempodauerlauf (PAR-103).
  final double vo2maxShareEasy;
  final double vo2maxShareTempo;

  /// Rang 3: keine Pace unter dieser Geschwindigkeit (PAR-030, PAR-103).
  final double vo2maxMinSpeedMetersPerMinute;

  /// Rang 3: Bandbreite nach unten je Güte (PAR-082).
  final double vo2maxWidthSufficient;
  final double vo2maxWidthGood;

  /// Umkehrung der Laufformel: `v = r · (VO₂max − 3,5) / 0,2` (FR-0069,
  /// FR-0071, PAR-103).
  final double vo2maxRestMl;
  final double vo2maxSlopeMl;

  /// Obergrenze „locker“ beim Puls: unter 80 % HFmax (PAR-111).
  final double easyMaxShareOfMaxHr;

  /// Kürzeste brauchbare Referenzdistanz (wie die Prognose, PAR-144).
  final double minReferenceMeters;
}

/// Daten, aus denen die Zielintensität folgt. Fehlt etwas, gilt die nächste
/// Stufe (PAR-100 bis PAR-105, FR-0153). Rang 1 gibt es in Phase 2 und 3 nicht
/// (PAR-100); eine Testzeit ist eine Referenzleistung (Rang 2).
class IntensityInputs {
  IntensityInputs({
    this.referenceSeconds,
    this.referenceMeters,
    this.referenceAgeDays,
    this.longestPauseSinceReferenceDays = 0,
    this.vo2max,
    this.vo2maxGrade,
    this.heartRate,
    List<double>? zoneBounds,
  }) : zoneBounds = List.unmodifiable(
         zoneBounds ??
             [for (final p in ReserveZoneSettings.defaultPercents) p / 100],
       ) {
    final b = this.zoneBounds;
    if (b.length != ReserveZoneSettings.defaultPercents.length) {
      throw ArgumentError.value(zoneBounds, 'zoneBounds', 'falsche Anzahl');
    }
    for (var i = 0; i < b.length; i++) {
      if (!b[i].isFinite || b[i] < 0 || (i > 0 && b[i] <= b[i - 1])) {
        throw ArgumentError.value(zoneBounds, 'zoneBounds', 'ungültig');
      }
    }
  }

  /// Referenzleistung: Zeit und Distanz der Leistung.
  final double? referenceSeconds;
  final double? referenceMeters;

  /// Alter der Referenz in Tagen zum Planungsstand.
  final int? referenceAgeDays;

  /// Längste Pause seit der Referenz in Tagen (PAR-101, PAR-202).
  final int longestPauseSinceReferenceDays;

  /// VO₂max (ml/kg/min) und Güte nach PAR-081. `vo2maxGrade == null` heißt
  /// unzureichend (vorläufig, nicht bestimmbar, zu alter letzter Lauf): dann
  /// keine Pace aus der VO₂max (FR-0145). Die Prüfung von PAR-081 liegt beim
  /// Aufrufer.
  final double? vo2max;
  final Vo2maxGrade? vo2maxGrade;

  /// HFmax und Ruhepuls (PAR-104). Ohne Ruhepuls keine Zone.
  final HeartRateBasis? heartRate;

  /// Grenzen der Reservezonen als Anteil (sechs Werte, auch vom Nutzer
  /// angepasst). Maßgeblich ist die Zonennummer (PAR-104).
  final List<double> zoneBounds;
}

/// Zielintensität eines Abschnitts. [intensity] ist das Feld des Plans
/// (`PlanSegment.intensity`); der Pulsbereich und die Kennzeichnungen sind
/// (noch) nicht im Planmodell (siehe Übergabe `wp21-d`).
class SegmentTarget {
  const SegmentTarget({
    required this.intensity,
    required this.basis,
    required this.estimated,
    required this.paceIsLimit,
    this.hrMinBpm,
    this.hrMaxBpm,
    this.maxHrEstimated = false,
  });

  /// RPE (immer gesetzt), Pace-Bereich oder -Grenze, Grundlage-Code.
  final PlanTargetIntensity intensity;
  final IntensityBasis basis;

  /// Pace oder Puls kommt aus einer Schätzung (alles außer [IntensityBasis.effort]).
  final bool estimated;

  /// Pace ist nur eine Grenze „nicht schneller als“ (lockere Läufe, PAR-102):
  /// `paceFast` gesetzt, `paceSlow` offen. Sonst immer ein echter Bereich
  /// mit `paceFast < paceSlow` (PAR-082, PAR-106).
  final bool paceIsLimit;

  /// Pulsbereich in bpm, nur bei Grundlage [IntensityBasis.heartRateZones].
  final int? hrMinBpm;
  final int? hrMaxBpm;

  /// HFmax stammt aus einer Altersformel (PAR-104).
  final bool maxHrEstimated;
}

enum _Role { easy, long, interval, recovery, tempo, walkRun }

/// Zielintensität für einen Abschnitt [segment] der Einheit [unitKind];
/// `null` für Ruhetage (PAR-116: keine Zielintensität).
///
/// Rangfolge je Abschnitt (PAR-100 bis PAR-105, FR-0153): Pace aus der
/// Referenz (Rang 2), Pace aus der VO₂max (Rang 3), Pulsbereich (Rang 4),
/// sonst nur RPE (Rang 5). Intervalle erhalten Pace nur auf Rang 2 und nie
/// einen Pulsbereich (PAR-112, PAR-103). Der erste Teil des progressiven
/// Laufs hat keine Pace (PAR-114). Die RPE steht immer dabei (PAR-105).
SegmentTarget? segmentTarget({
  required PlanUnitKind unitKind,
  required PlanSegmentKind segment,
  required IntensityInputs inputs,
  IntensityParameters parameters = const IntensityParameters(),
}) {
  if (unitKind == PlanUnitKind.rest) return null;
  final p = parameters;

  final _Role role;
  if (unitKind == PlanUnitKind.walkRun) {
    role = _Role.walkRun;
  } else {
    role = switch (segment) {
      PlanSegmentKind.interval => _Role.interval,
      PlanSegmentKind.recovery => _Role.recovery,
      PlanSegmentKind.tempo || PlanSegmentKind.endBlock => _Role.tempo,
      PlanSegmentKind.warmUp ||
      PlanSegmentKind.coolDown ||
      PlanSegmentKind.run ||
      PlanSegmentKind.walk ||
      PlanSegmentKind.easy =>
        unitKind == PlanUnitKind.long ? _Role.long : _Role.easy,
    };
  }

  final rpe = switch (role) {
    _Role.easy => p.rpeEasy,
    _Role.long => p.rpeLong,
    _Role.interval => p.rpeInterval,
    _Role.recovery => p.rpeRecovery,
    _Role.tempo =>
      segment == PlanSegmentKind.endBlock ? p.rpeEndBlock : p.rpeTempo,
    _Role.walkRun => p.rpeWalkRun,
  };

  SegmentTarget make(IntensityBasis basis, {_Pace? pace, _Hr? hr}) =>
      SegmentTarget(
        intensity: PlanTargetIntensity(
          rpeMin: rpe.min,
          rpeMax: rpe.max,
          paceFastSecondsPerKm: pace?.fast,
          paceSlowSecondsPerKm: pace?.slow,
          basisCode: basis.code,
        ),
        basis: basis,
        estimated: basis != IntensityBasis.effort,
        paceIsLimit: pace != null && pace.slow == null,
        hrMinBpm: hr?.min,
        hrMaxBpm: hr?.max,
        maxHrEstimated:
            hr != null && (inputs.heartRate?.maxIsEstimated ?? false),
      );

  // Geh-Lauf: Vorgabe ist die Zeit, keine Zone, keine Pace (PAR-115).
  // Erholung: nur RPE (PAR-112).
  if (role == _Role.walkRun || role == _Role.recovery) {
    return make(IntensityBasis.effort);
  }

  // Erster Teil des progressiven Laufs: keine Pace (PAR-114).
  final paceAllowed =
      !(unitKind == PlanUnitKind.progressive &&
          segment == PlanSegmentKind.easy);

  if (paceAllowed) {
    final ref = _referencePace(role, inputs, p);
    if (ref != null) return make(IntensityBasis.reference, pace: ref);
    final vo = _vo2maxPace(role, inputs, p);
    if (vo != null) return make(IntensityBasis.vo2max, pace: vo);
  }

  final hr = _heartRate(role, inputs, p);
  if (hr != null) return make(IntensityBasis.heartRateZones, hr: hr);

  return make(IntensityBasis.effort);
}

class _Pace {
  const _Pace(this.fast, this.slow);
  final double fast;
  final double? slow;
}

class _Hr {
  const _Hr(this.min, this.max);
  final int min;
  final int max;
}

double _round(double v) => v.roundToDouble();

/// Rang 2: Riegel-Tempi (PAR-102) mit Bandbreite nach unten (PAR-101,
/// PAR-190).
_Pace? _referencePace(_Role role, IntensityInputs i, IntensityParameters p) {
  final t = i.referenceSeconds;
  final d = i.referenceMeters;
  final age = i.referenceAgeDays;
  if (t == null || d == null || age == null) return null;
  if (!(t > 0) || !t.isFinite || !(d >= p.minReferenceMeters) || !d.isFinite) {
    return null;
  }
  if (age < 0 || age > p.referenceMaxDays) return null;
  if (i.longestPauseSinceReferenceDays >= p.pauseExcludesDays) return null;
  if (role == _Role.recovery || role == _Role.walkRun) return null;

  final width = age < p.referenceYoungDays
      ? p.referenceWidthYoung
      : age < p.referenceMidDays
      ? p.referenceWidthMid
      : p.referenceWidthOld;
  final exponent = const PredictionParameters().riegelExponent;

  double pace(double meters) =>
      riegelSeconds(
        referenceSeconds: t,
        referenceMeters: d,
        targetMeters: meters,
        exponent: exponent,
      ) /
      (meters / 1000);

  switch (role) {
    case _Role.interval:
      return _Pace(
        _round(pace(p.intervalFastMeters)),
        _round(pace(p.intervalSlowMeters) * (1 + width)),
      );
    case _Role.tempo:
      final half = pace(p.tempoSlowMeters);
      // Riegel-Tempo für 60 min: Distanz, in der die Zeit 60 min beträgt.
      final sixtyMeters = riegelMeters(
        referenceSeconds: t,
        referenceMeters: d,
        targetSeconds: p.tempoFastMinutes * 60,
        exponent: exponent,
      );
      final sixty = p.tempoFastMinutes * 60 / (sixtyMeters / 1000);
      // Das schnelle Ende ist das langsamere der beiden Tempi, höchstens das
      // langsame Ende (bei sehr schnellen Referenzen läge das 60-min-Tempo
      // sonst dahinter).
      final slower = pace(p.tempoFastMeters) > sixty
          ? pace(p.tempoFastMeters)
          : sixty;
      final fast = slower < half ? slower : half;
      return _Pace(_round(fast), _round(half * (1 + width)));
    case _Role.easy || _Role.long:
      return _Pace(_round(pace(p.tempoSlowMeters) * p.easyLimitFactor), null);
    case _Role.recovery || _Role.walkRun:
      return null;
  }
}

/// Rang 3: Pace aus der VO₂max (PAR-103); Intervalle nie.
_Pace? _vo2maxPace(_Role role, IntensityInputs i, IntensityParameters p) {
  final vo2 = i.vo2max;
  final grade = i.vo2maxGrade;
  if (vo2 == null || grade == null || !vo2.isFinite) return null;
  final share = switch (role) {
    _Role.easy || _Role.long => p.vo2maxShareEasy,
    _Role.tempo => p.vo2maxShareTempo,
    _ => null,
  };
  if (share == null) return null;
  final v = share * (vo2 - p.vo2maxRestMl) / p.vo2maxSlopeMl;
  if (!(v >= p.vo2maxMinSpeedMetersPerMinute)) return null;
  final width = grade == Vo2maxGrade.good
      ? p.vo2maxWidthGood
      : p.vo2maxWidthSufficient;
  final fast = 60000 / v;
  return _Pace(_round(fast), _round(fast * (1 + width)));
}

/// Rang 4: Pulsbereich aus Zonen (PAR-104, PAR-109, PAR-111, PAR-113).
/// Intervalle erhalten keinen (PAR-112).
_Hr? _heartRate(_Role role, IntensityInputs i, IntensityParameters p) {
  final hr = i.heartRate;
  final max = hr?.usableMaxBpm;
  final rest = hr?.usableRestingBpm;
  if (max == null || rest == null || max <= rest) return null;
  final b = i.zoneBounds;
  final double lo;
  final double hi;
  switch (role) {
    case _Role.easy || _Role.long:
      lo = b[0];
      hi = b[2];
    case _Role.tempo:
      // Oberer Teil Zone 3 bis unterer Teil Zone 4 (PAR-113).
      lo = (b[2] + b[3]) / 2;
      hi = (b[3] + b[4]) / 2;
    default:
      return null;
  }
  final reserve = max - rest;
  var upper = rest + hi * reserve;
  if (role == _Role.easy || role == _Role.long) {
    // Locker heißt auch unter 80 % HFmax, der niedrigere Wert gilt (PAR-111).
    final cap = p.easyMaxShareOfMaxHr * max;
    if (cap < upper) upper = cap;
  }
  final low = (rest + lo * reserve).round();
  final high = upper.round();
  if (high <= low) return null;
  return _Hr(low, high);
}

/// Zielintensität je Abschnitt von [unit]; Ruhetag: leere Liste.
List<SegmentTarget> unitTargets(
  PlanUnit unit,
  IntensityInputs inputs, {
  IntensityParameters parameters = const IntensityParameters(),
}) => [
  for (final s in unit.segments)
    ?segmentTarget(
      unitKind: unit.kind,
      segment: s.kind,
      inputs: inputs,
      parameters: parameters,
    ),
];

/// [unit] mit gefülltem `PlanSegment.intensity` (FR-0153). Rein; Methode und
/// Version der Einheit bleiben. Eingefrorene Einheiten gibt der Aufrufer
/// nicht hinein.
PlanUnit applyTargetIntensity(
  PlanUnit unit,
  IntensityInputs inputs, {
  IntensityParameters parameters = const IntensityParameters(),
}) {
  if (unit.kind == PlanUnitKind.rest) return unit;
  return PlanUnit(
    id: unit.id,
    day: unit.day,
    kind: unit.kind,
    phase: unit.phase,
    weekIndex: unit.weekIndex,
    minutes: unit.minutes,
    segments: [
      for (final s in unit.segments)
        PlanSegment(
          kind: s.kind,
          minutes: s.minutes,
          seconds: s.seconds,
          intensity: segmentTarget(
            unitKind: unit.kind,
            segment: s.kind,
            inputs: inputs,
            parameters: parameters,
          )?.intensity,
        ),
    ],
    runId: unit.runId,
    pinned: unit.pinned,
    method: unit.method,
    methodVersion: unit.methodVersion,
  );
}

/// [applyTargetIntensity] für eine Liste, Reihenfolge bleibt.
List<PlanUnit> applyTargetIntensities(
  List<PlanUnit> units,
  IntensityInputs inputs, {
  IntensityParameters parameters = const IntensityParameters(),
}) => [
  for (final u in units)
    applyTargetIntensity(u, inputs, parameters: parameters),
];
