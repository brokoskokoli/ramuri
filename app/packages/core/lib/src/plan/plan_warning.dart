import 'plan_unit.dart';
import 'weekly_time.dart' show planDay;

/// Schlüssel im `summary` einer Planfassung, die unter einem Warnsignal
/// entstand (FR-0203, K58): die Einheiten, die das Warnsignal zu Ruhetagen
/// gemacht hat (Art, `fixed`, `pinned`), damit Art und Festlegungen nach dem
/// Aufheben wiederkehren. Eine leere Liste heißt: Fassung unter Warnsignal,
/// nichts zu halten. Fehlt der Schlüssel, entstand die Fassung
/// ohne Warnsignal.
const String planWarningKey = 'warningHeld';

/// Grund-Code ([PlanVersionDraft.reason]) der Fassung bei gemeldetem Warnsignal.
const String planReasonWarning = 'warning';

/// Grund-Code der Fassung nach dem Aufheben.
const String planReasonWarningLifted = 'warningLifted';

/// Tage ohne Erinnerung: Nach so vielen Tagen ab Meldung ist sie fällig
/// (FR-0203, K58).
const int warningReminderDays = 7;

/// Festlegung einer Einheit, die das Warnsignal überdeckt.
class WarningHeld {
  const WarningHeld({
    required this.day,
    required this.kind,
    required this.fixed,
    required this.pinned,
    this.minutes = 0,
    this.segments = const [],
  });

  final DateTime day;
  final PlanUnitKind kind;
  final PlanUnitFixed fixed;
  final bool pinned;

  /// Dauer und Abschnitte der Einheit vor dem Warnsignal: Die Brücke vor dem
  /// Anker rechnet die Neuberechnung nicht neu, sie bekommt sie von hier
  /// zurück.
  final int minutes;
  final List<PlanSegment> segments;

  Map<String, Object?> toJson() => {
    'day': _iso(day),
    'kind': kind.name,
    'fixed': fixed.name,
    'pinned': pinned,
    'minutes': minutes,
    'segments': [for (final s in segments) _segmentToJson(s)],
  };

  static WarningHeld? fromJson(Object? json) {
    if (json is! Map) return null;
    final day = DateTime.tryParse('${json['day']}');
    final kind = PlanUnitKind.values.asNameMap()[json['kind']];
    final fixed = PlanUnitFixed.values.asNameMap()[json['fixed']];
    final pinned = json['pinned'];
    if (day == null || kind == null || fixed == null || pinned is! bool) {
      return null;
    }
    final minutes = json['minutes'];
    final rawSegments = json['segments'];
    return WarningHeld(
      day: planDay(day),
      kind: kind,
      fixed: fixed,
      pinned: pinned,
      minutes: minutes is int ? minutes : 0,
      segments: rawSegments is List
          ? [for (final e in rawSegments) ?_segmentFromJson(e)]
          : const [],
    );
  }
}

Map<String, Object?> _segmentToJson(PlanSegment s) => {
  'kind': s.kind.name,
  'minutes': s.minutes,
  if (s.seconds != null) 'seconds': s.seconds,
  if (s.intensity case final i?)
    'intensity': {
      'rpeMin': i.rpeMin,
      'rpeMax': i.rpeMax,
      'paceFast': i.paceFastSecondsPerKm,
      'paceSlow': i.paceSlowSecondsPerKm,
      'basis': i.basisCode,
      'hrMin': i.hrMinBpm,
      'hrMax': i.hrMaxBpm,
      'estimated': i.estimated,
      'maxHrEstimated': i.maxHrEstimated,
      'paceIsLimit': i.paceIsLimit,
    },
};

PlanSegment? _segmentFromJson(Object? json) {
  if (json is! Map) return null;
  final kind = PlanSegmentKind.values.asNameMap()[json['kind']];
  final minutes = json['minutes'];
  if (kind == null || minutes is! int) return null;
  final seconds = json['seconds'];
  final i = json['intensity'];
  return PlanSegment(
    kind: kind,
    minutes: minutes,
    seconds: seconds is int ? seconds : null,
    intensity: i is Map
        ? PlanTargetIntensity(
            rpeMin: i['rpeMin'] as int?,
            rpeMax: i['rpeMax'] as int?,
            paceFastSecondsPerKm: (i['paceFast'] as num?)?.toDouble(),
            paceSlowSecondsPerKm: (i['paceSlow'] as num?)?.toDouble(),
            basisCode: i['basis'] as String?,
            hrMinBpm: i['hrMin'] as int?,
            hrMaxBpm: i['hrMax'] as int?,
            estimated: i['estimated'] == true,
            maxHrEstimated: i['maxHrEstimated'] == true,
            paceIsLimit: i['paceIsLimit'] == true,
          )
        : null,
  );
}

String _iso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// Alle künftigen, nicht absolvierten Einheiten [future] (Tag ab [today],
/// ohne Lauf) als Ruhetage; Tag, Woche und Phase bleiben. Die Ruhetage sind
/// weder festgelegt noch bestätigt (`pinned` falsch, `fixed` none): Nur so
/// erfüllen sie die Speicherregel (`fixed = day` nur bei Ruhe, `kind` und
/// `easyForHard` hielten nicht) und sind vom Ruhetag des Nutzers (`pinned`,
/// `fixed = day`) zu unterscheiden. Art, `pinned` und `fixed` hält
/// [warningHeldOf].
/// Eingefrorene Einheiten (Tag vor [today] oder mit Lauf) bleiben unverändert.
List<PlanUnit> applyWarningRest(List<PlanUnit> future, DateTime today) {
  final todayDay = planDay(today);
  return [
    for (final u in future)
      if (u.day.isBefore(todayDay) ||
          u.runId != null ||
          u.kind == PlanUnitKind.rest)
        u
      else
        PlanUnit(
          id: u.id,
          day: u.day,
          kind: PlanUnitKind.rest,
          phase: u.phase,
          weekIndex: u.weekIndex,
          minutes: 0,
          segments: const [],
          method: u.method,
          methodVersion: u.methodVersion,
        ),
  ];
}

/// Die Einheiten [units] (vor [applyWarningRest]), die ein Ruhetag ersetzt:
/// alle künftigen offenen Läufe mit Art, `pinned` und `fixed`. Auch
/// nicht festgelegte Einheiten werden gehalten: Die Rechnung der
/// automatischen Auslöser hält die Tage und ordnet über die Art zu.
List<WarningHeld> warningHeldOf(List<PlanUnit> units, DateTime today) {
  final todayDay = planDay(today);
  return [
    for (final u in units)
      if (!u.day.isBefore(todayDay) &&
          u.runId == null &&
          u.kind != PlanUnitKind.rest)
        WarningHeld(
          day: planDay(u.day),
          kind: u.kind,
          fixed: u.fixed,
          pinned: u.pinned,
          minutes: u.minutes,
          segments: u.segments,
        ),
  ];
}

/// Die gehaltenen Festlegungen aus dem `summary` einer Fassung; `null`, wenn
/// die Fassung nicht unter einem Warnsignal entstand. Unlesbare Einträge
/// entfallen.
List<WarningHeld>? warningHeldFromSummary(Map<String, Object?> summary) {
  final raw = summary[planWarningKey];
  if (raw is! List) return null;
  return [for (final e in raw) ?WarningHeld.fromJson(e)];
}

/// Stellt in [units] (eine Fassung unter Warnsignal) die Art der gehaltenen
/// Festlegungen [held] wieder her: Einheiten auf deren Tagen, die ein
/// Ruhetag ersetzt hat, bekommen Art, `fixed`, `pinned`, Dauer und Abschnitte
/// zurück (die Rechnung ersetzt sie, außer bei der Brücke vor dem Anker). Nur Ruhetage, die noch die
/// Überlagerung sind (nicht `pinned`, `fixed` none, siehe [applyWarningRest]): Eine Festlegung, die
/// der Nutzer unter dem Warnsignal neu getroffen hat (z. B. Ruhetag), gilt
/// weiter (ADR-0010).
List<PlanUnit> restoreWarningHeld(
  List<PlanUnit> units,
  List<WarningHeld> held,
) {
  final byDay = {for (final h in held) h.day: h};
  return [
    for (final u in units)
      if (_isOverlay(u, byDay[planDay(u.day)]))
        _restored(u, byDay[planDay(u.day)]!)
      else
        u,
  ];
}

/// Einheiten [restored] (aus [restoreWarningHeld]) ohne Dauer und Abschnitte
/// (Einträge alter Fassungen, die beides noch nicht hielten) bekommen beides
/// von der ersten Einheit gleicher Art aus [generated] (der Rechnung ohne
/// Warnsignal); gibt es keine, bleibt die Einheit unverändert. Frühere
/// Fassungen speichern ihre Einheiten nicht, daher kommt der Ersatz aus der
/// neuen Rechnung.
List<PlanUnit> fillEmptyRestored(
  List<PlanUnit> restored,
  List<PlanUnit> generated,
) {
  PlanUnit? template(PlanUnitKind kind) {
    for (final g in generated) {
      if (g.kind == kind && g.runId == null && g.minutes > 0) return g;
    }
    return null;
  }

  return [
    for (final u in restored)
      if (u.kind == PlanUnitKind.rest ||
          u.minutes != 0 ||
          u.segments.isNotEmpty)
        u
      else
        _withTemplate(u, template(u.kind)),
  ];
}

PlanUnit _withTemplate(PlanUnit u, PlanUnit? t) => t == null
    ? u
    : PlanUnit(
        id: u.id,
        day: u.day,
        kind: u.kind,
        phase: u.phase,
        weekIndex: u.weekIndex,
        minutes: t.minutes,
        segments: t.segments,
        runId: u.runId,
        pinned: u.pinned,
        fixed: u.fixed,
        method: u.method,
        methodVersion: u.methodVersion,
      );

bool _isOverlay(PlanUnit u, WarningHeld? h) =>
    h != null &&
    u.kind == PlanUnitKind.rest &&
    !u.pinned &&
    u.fixed == PlanUnitFixed.none;

PlanUnit _restored(PlanUnit u, WarningHeld h) => PlanUnit(
  id: u.id,
  day: u.day,
  kind: h.kind,
  phase: u.phase,
  weekIndex: u.weekIndex,
  minutes: h.minutes,
  segments: h.segments,
  runId: u.runId,
  pinned: h.pinned,
  fixed: h.fixed,
  method: u.method,
  methodVersion: u.methodVersion,
);

/// Erinnerung fällig (FR-0203): [warningReminderDays] Tage nach der Meldung
/// [reportedOn]. Nur Anzeige in der App, keine Benachrichtigung.
bool warningReminderDue({
  required DateTime reportedOn,
  required DateTime today,
}) =>
    planDay(today).difference(planDay(reportedOn)).inDays >=
    warningReminderDays;
