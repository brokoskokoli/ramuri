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
  });

  final int? rpeMin;
  final int? rpeMax;
  final double? paceFastSecondsPerKm;
  final double? paceSlowSecondsPerKm;
  final String? basisCode;
}

/// Abschnitt einer Einheit mit Dauer in Minuten.
class PlanSegment {
  const PlanSegment({
    required this.kind,
    required this.minutes,
    this.intensity,
  });

  final PlanSegmentKind kind;
  final int minutes;

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

  /// Dauer in Minuten; gleich der Summe der [segments].
  final int minutes;
  final List<PlanSegment> segments;

  /// Zugeordneter Lauf (setzt WP22).
  final int? runId;

  /// Vom Nutzer bestätigt gesetzter Termin.
  final bool pinned;

  /// Methode und Version der Fassung, die die Einheit erzeugt hat.
  final String method;
  final int methodVersion;

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
