import 'generate_plan.dart';
import 'plan_course.dart' show HardFitStatus;
import 'plan_inputs.dart' show PlanVersion;
import 'plan_unit.dart';
import 'week_units.dart' show HardOmission;
import 'weekly_time.dart';

/// Schlüssel der Hinweise im `summary`-JSON einer Fassung (WP22). Das
/// Archiv beschreibt `summary` nur als JSON-Objekt; der Inhalt ist frei.
const String planHintsKey = 'hints';

/// Version der Form von [planHintsToJson].
const int planHintsVersion = 1;

String _day(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

DateTime? _parseDay(Object? v) {
  if (v is! String) return null;
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(v);
  if (m == null) return null;
  final d = DateTime.utc(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
  return _day(d) == v ? d : null;
}

/// Die Hinweise einer Rechnung (alles aus [GeneratedPlan] außer den
/// Einheiten), so wie sie an der Fassung im `summary` stehen: Verlauf der
/// Wochenzeit, nicht untergebrachte Minuten, fehlende harte Einheit,
/// entfallene Tage, Konflikte der Termine, Geh-Lauf und Passform. Die
/// Schlüsselreihenfolge ist fest.
Map<String, Object?> planHintsToJson(GeneratedPlan g) => {
  'hintsVersion': planHintsVersion,
  'weeks': [
    for (final w in g.weeks)
      {
        'index': w.index,
        'start': _day(w.start),
        'minutes': w.minutes,
        'phase': w.phase.name,
        'kind': w.kind.name,
      },
  ],
  'unplacedByWeek': {
    for (final e in g.unplacedByWeek.entries) '${e.key}': e.value,
  },
  'hardOmissions': {
    for (final e in g.hardOmissions.entries) '${e.key}': e.value.name,
  },
  'droppedDaysByWeek': {
    for (final e in g.droppedDaysByWeek.entries)
      '${e.key}': [for (final d in e.value) _day(d)],
  },
  'pinnedConflicts': [
    for (final c in g.pinnedConflicts)
      {
        'kind': c.kind.name,
        'day': _day(c.day),
        'otherDay': c.otherDay == null ? null : _day(c.otherDay!),
      },
  ],
  'walkRunStaysAtWeek': g.walkRunStaysAtWeek,
  'walkRunNoWeekFits': g.walkRunNoWeekFits,
  'hardFit': g.hardFit.name,
};

/// Liest die gespeicherten Hinweise aus dem `summary` einer Fassung und
/// setzt sie mit den gespeicherten Einheiten [units] der Fassung zu einem
/// [GeneratedPlan] zusammen (künftig ab [today] und ohne Lauf: `units`,
/// sonst `frozenUnits`); der Verlauf beginnt wie bei [generatePlan] mit der
/// Woche von [today], Konflikte von Terminen vor [today] fallen weg. `null`,
/// wenn die Fassung keine (lesbaren) Hinweise trägt, etwa eine Fassung von
/// vor WP22; der Aufrufer rechnet dann eine Vorschau.
GeneratedPlan? planHintsFromSummary(
  Map<String, Object?> summary, {
  required PlanVersion version,
  required List<PlanUnit> units,
  required DateTime today,
}) {
  final h = summary[planHintsKey];
  if (h is! Map<String, Object?> || h['hintsVersion'] != planHintsVersion) {
    return null;
  }
  try {
    T byName<T extends Enum>(List<T> values, Object? name) =>
        values.firstWhere((v) => v.name == name);
    Map<int, V> intMap<V>(Object? v, V Function(Object?) f) => {
      for (final e in (v! as Map<String, Object?>).entries)
        int.parse(e.key): f(e.value),
    };
    Map<String, Object?> obj(Object? v) => v! as Map<String, Object?>;
    final t = planDay(today);
    final monday = t.subtract(Duration(days: t.weekday - DateTime.monday));
    final weeks = [
      for (final w in (h['weeks']! as List<Object?>).map(obj))
        PlanWeek(
          index: w['index']! as int,
          start: _parseDay(w['start'])!,
          minutes: w['minutes'] as int?,
          phase: byName(PlanPhase.values, w['phase']),
          kind: byName(WeekKind.values, w['kind']),
        ),
    ]..removeWhere((w) => w.start.isBefore(monday));
    final conflicts = [
      for (final c in (h['pinnedConflicts']! as List<Object?>).map(obj))
        PinnedConflict(
          kind: byName(PinnedConflictKind.values, c['kind']),
          day: _parseDay(c['day'])!,
          otherDay: c['otherDay'] == null ? null : _parseDay(c['otherDay'])!,
        ),
    ]..removeWhere((c) => c.day.isBefore(t));
    final future = <PlanUnit>[];
    final frozen = <PlanUnit>[];
    for (final u in units) {
      (!u.day.isBefore(t) && u.runId == null ? future : frozen).add(u);
    }
    return GeneratedPlan(
      version: version,
      weeks: weeks,
      units: future,
      frozenUnits: frozen,
      unplacedByWeek: intMap(h['unplacedByWeek'], (v) => v! as int),
      hardOmissions: intMap(
        h['hardOmissions'],
        (v) => byName(HardOmission.values, v),
      ),
      droppedDaysByWeek: intMap(h['droppedDaysByWeek'], (v) {
        return [for (final d in v! as List<Object?>) _parseDay(d)!];
      }),
      pinnedConflicts: conflicts,
      walkRunStaysAtWeek: h['walkRunStaysAtWeek'] as int?,
      walkRunNoWeekFits: h['walkRunNoWeekFits']! as bool,
      hardFit: byName(HardFitStatus.values, h['hardFit']),
    );
  } on Object {
    // Unlesbare Hinweise (fremdes Archiv): wie ohne Hinweise.
    return null;
  }
}
