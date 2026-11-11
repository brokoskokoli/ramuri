import '../../ports/storage_plan.dart' show PlanVersionRecord;
import '../../ports/storage_values.dart' show ComputedValue, ValueQuality;
import '../plan/plan_unit.dart';
import '../load/training_load.dart' show LoadDay;
import 'hint_selection.dart' show Evidence, EvidenceKey;

/// Art einer Erklärung (FR-0180).
enum ExplanationKind {
  fitnessDevelopment,
  trainingRecommendation,
  planChange,
  dataQuality,
}

/// Erklärungsbaustein (FR-0179 bis FR-0181): Art, Code und Belege. Die Texte
/// setzt die App. Alles, was der Baustein nennt, steht in [evidence]; was
/// nicht in den Daten steht, wird nicht genannt (FR-0181).
class Explanation {
  const Explanation({
    required this.kind,
    required this.code,
    required this.evidence,
  });
  final ExplanationKind kind;
  final String code;
  final List<Evidence> evidence;

  Object? evidenceOf(EvidenceKey key) {
    for (final e in evidence) {
      if (e.key == key) return e.value;
    }
    return null;
  }

  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'code': code,
    'evidence': [for (final e in evidence) e.toJson()],
  };
}

/// Ein geschätzter VO₂max-Wert eines geeigneten Laufs (Ortstag).
class FitnessPoint {
  const FitnessPoint(this.day, this.value);
  final DateTime day;
  final double value;
}

/// Fitnessentwicklung (FR-0180): erster und letzter Wert der geeigneten Läufe
/// in den letzten [windowDays] Tagen (6 Wochen) mit Zahl der Läufe. Code `up`,
/// `down` oder `same`. Weniger als 2 Läufe: keine Erklärung.
Explanation? explainFitnessDevelopment(
  Iterable<FitnessPoint> points, {
  required DateTime today,
  int windowDays = 42,
}) {
  final t = DateTime.utc(today.year, today.month, today.day);
  final inWindow = [
    for (final p in points)
      if (p.value.isFinite &&
          !DateTime.utc(p.day.year, p.day.month, p.day.day).isAfter(t) &&
          t
                  .difference(DateTime.utc(p.day.year, p.day.month, p.day.day))
                  .inDays <
              windowDays)
        p,
  ]..sort((a, b) => a.day.compareTo(b.day));
  if (inWindow.length < 2) return null;
  final first = inWindow.first, last = inWindow.last;
  final diff = last.value - first.value;
  return Explanation(
    kind: ExplanationKind.fitnessDevelopment,
    code: diff > 0 ? 'up' : (diff < 0 ? 'down' : 'same'),
    evidence: [
      Evidence(EvidenceKey.fromDay, first.day),
      Evidence(EvidenceKey.toDay, last.day),
      Evidence(EvidenceKey.fromValue, first.value),
      Evidence(EvidenceKey.toValue, last.value),
      Evidence(EvidenceKey.runCount, inWindow.length),
    ],
  );
}

/// Trainingsempfehlung (FR-0180): die nächste geplante Einheit; die
/// Belastung (kurzfristig, langfristig) nur, wenn beide Werte da und nicht
/// vorläufig sind (PAR-073). Ohne Einheit keine Erklärung.
Explanation? explainTrainingRecommendation({
  required PlanUnit? plannedUnit,
  LoadDay? load,
}) {
  if (plannedUnit == null || plannedUnit.kind == PlanUnitKind.rest) {
    return null;
  }
  final atl = load?.atl, ctl = load?.ctl;
  final usable =
      load != null &&
      atl != null &&
      ctl != null &&
      atl.isFinite &&
      ctl.isFinite &&
      !load.atlProvisional &&
      !load.ctlProvisional;
  return Explanation(
    kind: ExplanationKind.trainingRecommendation,
    code: usable ? 'withLoad' : 'planOnly',
    evidence: [
      Evidence(EvidenceKey.plannedKind, plannedUnit.kind.name),
      Evidence(EvidenceKey.plannedDay, plannedUnit.day),
      if (usable) Evidence(EvidenceKey.shortTermLoad, atl),
      if (usable) Evidence(EvidenceKey.longTermLoad, ctl),
    ],
  );
}

/// Planänderung (FR-0180): Auslöser und Grund-Code der Fassung, dazu aus dem
/// Alt-Neu-Bild, ob die Änderung größer ist und wie viele Einheiten sie
/// betrifft (nur wenn gespeichert).
Explanation explainPlanChange(PlanVersionRecord version) {
  final s = version.summary;
  final larger = s['larger'];
  final count = s['changedUnitCount'];
  return Explanation(
    kind: ExplanationKind.planChange,
    code: version.reason,
    evidence: [
      Evidence(EvidenceKey.trigger, version.trigger.name),
      Evidence(EvidenceKey.reason, version.reason),
      Evidence(EvidenceKey.validFrom, version.validFrom),
      if (larger is bool) Evidence(EvidenceKey.larger, larger),
      if (count is int) Evidence(EvidenceKey.changedUnitCount, count),
    ],
  );
}

/// Datenqualität (FR-0180): warum ein Wert fehlt (Code = Grund) oder dass er
/// nur vorläufig bzw. nicht bestimmbar ist. Ein vollständiger Wert hat keine
/// Erklärung dieser Art. Belege: Schlüssel, Methode und Version, Zahl der
/// Messwerte (FR-0053).
Explanation? explainDataQuality(ComputedValue value) {
  final reason = value.unavailableReason;
  final String code;
  if (value.value == null && reason != null) {
    code = reason.name;
  } else if (value.value != null &&
      (value.quality == ValueQuality.provisional ||
          value.quality == ValueQuality.undeterminable)) {
    code = 'quality.${value.quality.name}';
  } else {
    return null;
  }
  return Explanation(
    kind: ExplanationKind.dataQuality,
    code: code,
    evidence: [
      Evidence(EvidenceKey.valueKey, value.key),
      if (reason != null) Evidence(EvidenceKey.unavailableReason, reason.name),
      Evidence(EvidenceKey.quality, value.quality.name),
      Evidence(EvidenceKey.method, value.method),
      Evidence(EvidenceKey.methodVersion, value.methodVersion),
      Evidence(EvidenceKey.measurementCount, value.measurementCount),
    ],
  );
}
