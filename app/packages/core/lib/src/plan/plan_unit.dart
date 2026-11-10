import 'plan_parameters.dart';
import 'weekly_time.dart' show PlanPhase;

/// Art einer Einheit (FR-0142, ADR-0010 Punkt 1).
enum PlanUnitKind {
  /// Lockerer Dauerlauf.
  easy,

  /// Langer Lauf (PAR-195, PAR-110).
  long,

  /// Harte Einheit: Intervalle (PAR-198).
  intervals,

  /// Harte Einheit: Tempodauerlauf (PAR-198).
  tempo,

  /// Harte Einheit: progressiver Lauf (PAR-198).
  progressive,

  /// Geh-Lauf-Einheit der Abfolge (PAR-065; kommt mit der Abfolge).
  walkRun,

  /// Ruhetag.
  rest,
}

/// Was der Nutzer an einer Einheit festgelegt hat (Spalte `plan_units.fixed`,
/// Schema 8, ADR-0010 Nachtrag). Der Termin selbst steht in
/// [PlanUnit.pinned]; [day] und [kind] setzen ihn immer voraus.
enum PlanUnitFixed {
  /// Nichts über den Termin hinaus: Die App rechnet Art, Dauer und
  /// Intensität (FR-0176 Kriterium 2).
  none,

  /// Ruhetag vom Nutzer ([PlanUnitKind.rest]): Die Neuberechnung legt dort
  /// keinen Lauf ab.
  day,

  /// Art vom Nutzer ersetzt: Die Art bleibt bei jeder Neuberechnung, Dauer
  /// und Intensität rechnet die App.
  kind,
}

/// Teil einer Einheit (FR-0143).
enum PlanSegmentKind {
  /// Aufwärmen (PAR-120).
  warmUp,

  /// Lockerer Hauptteil.
  easy,

  /// Harter Block eines Intervalls.
  interval,

  /// Block des Tempodauerlaufs.
  tempo,

  /// Trabpause zwischen Blöcken (PAR-198).
  recovery,

  /// Endblock des progressiven Laufs.
  endBlock,

  /// Abwärmen (PAR-121).
  coolDown,

  /// Laufphase der Geh-Lauf-Abfolge (PAR-065).
  run,

  /// Gehphase der Geh-Lauf-Abfolge (PAR-065).
  walk,
}

/// Zielintensität eines Abschnitts (ADR-0010 Punkt 11): RPE, Pace-Bereich,
/// Grundlage-Code. Die Werte setzt Teil D (FR-0153); bis dahin ist alles
/// `null`.
class PlanTargetIntensity {
  const PlanTargetIntensity({
    this.rpeMin,
    this.rpeMax,
    this.paceFastSecondsPerKm,
    this.paceSlowSecondsPerKm,
    this.basisCode,
    this.hrMinBpm,
    this.hrMaxBpm,
    this.estimated = false,
    this.maxHrEstimated = false,
    this.paceIsLimit = false,
  });

  final int? rpeMin;
  final int? rpeMax;
  final double? paceFastSecondsPerKm;
  final double? paceSlowSecondsPerKm;
  final String? basisCode;

  /// Pulsbereich in bpm (FR-0144), nur bei Grundlage Herzfrequenzzonen.
  final int? hrMinBpm;
  final int? hrMaxBpm;

  /// Pace oder Puls kommt aus einer Schätzung (FR-0144, PAR-106).
  final bool estimated;

  /// HFmax stammt aus einer Altersformel (PAR-104).
  final bool maxHrEstimated;

  /// Pace ist nur eine Grenze „nicht schneller als“ (PAR-102).
  final bool paceIsLimit;
}

/// Abschnitt einer Einheit mit Dauer in Minuten.
class PlanSegment {
  const PlanSegment({
    required this.kind,
    required this.minutes,
    this.seconds,
    this.intensity,
  });

  final PlanSegmentKind kind;

  /// Dauer in ganzen Minuten (gerundet, wenn [seconds] gesetzt ist).
  final int minutes;

  /// Genaue Dauer in Sekunden, wo die Minute nicht reicht (Geh-Lauf:
  /// 1:30 min). `null`: die Dauer ist [minutes].
  final int? seconds;

  /// Dauer in Sekunden.
  int get durationSeconds => seconds ?? minutes * 60;

  /// Zielintensität; in Teil C1b immer `null` (kommt mit Teil D).
  final PlanTargetIntensity? intensity;
}

/// Lesemodell einer geplanten Einheit (ADR-0010 Punkt 11), flutterfrei.
class PlanUnit {
  const PlanUnit({
    required this.day,
    required this.kind,
    required this.phase,
    required this.weekIndex,
    required this.minutes,
    required this.segments,
    this.id,
    this.runId,
    this.pinned = false,
    this.fixed = PlanUnitFixed.none,
    this.method = planMethod,
    this.methodVersion = planMethodVersion,
  });

  /// Kennung der Speicherung; `null` vor dem Schreiben.
  final int? id;

  /// Ortstag (Kalendertag, UTC-Mitternacht wie `calendarDay`).
  final DateTime day;
  final PlanUnitKind kind;
  final PlanPhase phase;

  /// Nummer der Woche ab dem Anker (wie `PlanWeek.index`).
  final int weekIndex;

  /// Dauer in Minuten; gleich der Summe der [segments] (bei Abschnitten mit
  /// Sekunden: deren Summe, auf ganze Minuten gerundet).
  final int minutes;
  final List<PlanSegment> segments;

  /// Zugeordneter Lauf (setzt WP22).
  final int? runId;

  /// Vom Nutzer bestätigt gesetzter Termin.
  final bool pinned;

  /// Vom Nutzer festgelegte Art oder Ruhetag ([PlanUnitFixed]).
  final PlanUnitFixed fixed;

  /// Vom Nutzer festgelegter Ruhetag (`rest`, Termin bestätigt).
  bool get isRestDay => kind == PlanUnitKind.rest && pinned;

  /// Methode und Version der Fassung, die die Einheit erzeugt hat.
  final String method;
  final int methodVersion;

  /// Kopie mit geänderter Kennung, Tag, Woche, Lauf, Termin- oder
  /// Festlegungs-Markierung.
  /// [runId] lässt sich über [clearRun] auf `null` setzen.
  PlanUnit copyWith({
    int? id,
    DateTime? day,
    int? weekIndex,
    int? runId,
    bool clearRun = false,
    bool? pinned,
    PlanUnitFixed? fixed,
    String? method,
    int? methodVersion,
  }) => PlanUnit(
    id: id ?? this.id,
    day: day ?? this.day,
    kind: kind,
    phase: phase,
    weekIndex: weekIndex ?? this.weekIndex,
    minutes: minutes,
    segments: segments,
    runId: clearRun ? null : (runId ?? this.runId),
    pinned: pinned ?? this.pinned,
    fixed: fixed ?? this.fixed,
    method: method ?? this.method,
    methodVersion: methodVersion ?? this.methodVersion,
  );

  /// Zählt für den Abstand als intensiv (PAR-058): langer Lauf und harte
  /// Einheiten.
  bool get isIntensive => switch (kind) {
    PlanUnitKind.long ||
    PlanUnitKind.intervals ||
    PlanUnitKind.tempo ||
    PlanUnitKind.progressive => true,
    _ => false,
  };

  /// Harte Einheit (PAR-198): höchstens eine je Woche.
  bool get isHard =>
      kind == PlanUnitKind.intervals ||
      kind == PlanUnitKind.tempo ||
      kind == PlanUnitKind.progressive;
}
