import '../plan/plan_unit.dart';

/// Art einer Ansage. Nur Codes und Werte, keine Texte (Festlegung 11); die
/// App setzt Sprache und Wortlaut.
enum GuidanceEventKind {
  /// Voller Kilometer (Festlegung 6).
  kilometer,

  /// Neuer Abschnitt hat begonnen (FR-0033).
  segmentChange,

  /// Der nächste Abschnitt beginnt gleich (Festlegung 8).
  segmentPreview,

  /// Alle Abschnitte sind durchlaufen (gehört zum Schalter Abschnitte).
  unitComplete,

  /// Puls über dem Bereich des Abschnitts (FR-0032, PAR-107).
  heartRateAbove,

  /// Statt Pulsansagen: Gehpausen sind erlaubt (PAR-107).
  walkBreakHint,
}

/// Eine Ansage; je nach [kind] sind nur einige Felder gesetzt.
class GuidanceEvent {
  const GuidanceEvent._(
    this.kind, {
    this.kilometer,
    this.kilometerTime,
    this.kilometerDuration,
    this.segmentIndex,
    this.segmentKind,
    this.segmentDuration,
    this.target,
    this.secondsUntilChange,
    this.heartRateBpm,
    this.heartRateMaxBpm,
  });

  factory GuidanceEvent.kilometer({
    required int kilometer,
    required Duration time,
    Duration? duration,
  }) => GuidanceEvent._(
    GuidanceEventKind.kilometer,
    kilometer: kilometer,
    kilometerTime: time,
    kilometerDuration: duration,
  );

  factory GuidanceEvent.segmentChange({
    required int index,
    required PlanSegment segment,
  }) => GuidanceEvent._(
    GuidanceEventKind.segmentChange,
    segmentIndex: index,
    segmentKind: segment.kind,
    segmentDuration: Duration(seconds: segment.durationSeconds),
    target: segment.intensity,
  );

  factory GuidanceEvent.segmentPreview({
    required int index,
    required PlanSegment segment,
    required Duration until,
  }) => GuidanceEvent._(
    GuidanceEventKind.segmentPreview,
    segmentIndex: index,
    segmentKind: segment.kind,
    segmentDuration: Duration(seconds: segment.durationSeconds),
    target: segment.intensity,
    secondsUntilChange: until.inSeconds,
  );

  const GuidanceEvent.unitComplete() : this._(GuidanceEventKind.unitComplete);

  factory GuidanceEvent.heartRateAbove({
    required int bpm,
    required int maxBpm,
  }) => GuidanceEvent._(
    GuidanceEventKind.heartRateAbove,
    heartRateBpm: bpm,
    heartRateMaxBpm: maxBpm,
  );

  const GuidanceEvent.walkBreakHint() : this._(GuidanceEventKind.walkBreakHint);

  final GuidanceEventKind kind;

  /// Nummer des vollen Kilometers (1, 2, ...).
  final int? kilometer;

  /// Bewegungszeit bei diesem Kilometer.
  final Duration? kilometerTime;

  /// Bewegungszeit des letzten Kilometers (Pace); `null`, wenn unbekannt
  /// (erster Kilometer nach Wiederanlauf, übersprungene Kilometer).
  final Duration? kilometerDuration;

  /// Index in der Abschnittsliste (bei Vorankündigung: des nächsten).
  final int? segmentIndex;
  final PlanSegmentKind? segmentKind;
  final Duration? segmentDuration;

  /// Ziel des (nächsten) Abschnitts.
  final PlanTargetIntensity? target;

  /// Bei Vorankündigung: Sekunden bis zum Wechsel.
  final int? secondsUntilChange;

  /// Bei [GuidanceEventKind.heartRateAbove]: Puls und obere Grenze.
  final int? heartRateBpm;
  final int? heartRateMaxBpm;

  @override
  String toString() =>
      'GuidanceEvent($kind'
      '${kilometer == null ? '' : ' km $kilometer'}'
      '${segmentIndex == null ? '' : ' seg $segmentIndex'})';
}

/// Schalter je Art (Festlegung 10); Vorgabe alle an. [enabled] ist der
/// Hauptschalter, ist er aus, kommt nichts.
class GuidanceSwitches {
  const GuidanceSwitches({
    this.enabled = true,
    this.kilometer = true,
    this.heartRate = true,
    this.segments = true,
  });

  final bool enabled;
  final bool kilometer;

  /// Pulsansage und Gehpausen-Hinweis.
  final bool heartRate;

  /// Abschnittswechsel, Vorankündigung, Einheit fertig.
  final bool segments;

  bool allows(GuidanceEventKind k) {
    if (!enabled) return false;
    switch (k) {
      case GuidanceEventKind.kilometer:
        return kilometer;
      case GuidanceEventKind.heartRateAbove:
      case GuidanceEventKind.walkBreakHint:
        return heartRate;
      case GuidanceEventKind.segmentChange:
      case GuidanceEventKind.segmentPreview:
      case GuidanceEventKind.unitComplete:
        return segments;
    }
  }
}
