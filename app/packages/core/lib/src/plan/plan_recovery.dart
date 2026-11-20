import '../../ports/storage_settings.dart';
import '../readiness/readiness_explanation.dart' show ReadinessDirection;
import '../readiness/readiness_model.dart' show readinessBandOf;
import '../readiness/readiness_result.dart';
import 'plan_unit.dart';
import 'plan_warning.dart' show WarningHeld;
import 'weekly_time.dart' show planDay;

/// Plananpassung an Erholung (FR-0216, K61): ob Gesundheitsdaten den Plan
/// verändern. Vorgabe ist [fixed].
enum PlanAdaptationMode {
  /// Gesundheitsdaten werden erhoben und angezeigt, ändern den Plan aber nicht.
  fixed('fixed'),

  /// Zusätzlich gilt die Lockerung nach PAR-173 ([applyRecoveryEase]).
  adaptive('adaptive');

  const PlanAdaptationMode(this.storageValue);

  /// Wert in den Einstellungen ([planAdaptationKey]).
  final String storageValue;

  /// Nur der gespeicherte Wert `adaptive` ergibt [adaptive]; fehlt der
  /// Eintrag oder ist er unbekannt, gilt [fixed] (fail-closed: ohne
  /// ausdrückliche Wahl ändern Gesundheitsdaten den Plan nicht).
  static PlanAdaptationMode fromStorage(String? value) =>
      value == adaptive.storageValue ? adaptive : fixed;
}

/// Schlüssel in `settings` für [PlanAdaptationMode] (FR-0216): `fixed` oder
/// `adaptive`; fehlt der Eintrag, gilt `fixed`. Nutzereinstellung: kommt ins
/// Archiv, „Alles löschen“ leert sie mit den Einstellungen.
const String planAdaptationKey = 'plan.adaptation';

/// Port: Schalter „Plananpassung an Erholung“ lesen und setzen.
abstract interface class PlanAdaptationStore {
  Future<PlanAdaptationMode> read();

  Future<void> set(PlanAdaptationMode mode, {required DateTime at});
}

/// [PlanAdaptationStore] in [SettingsStore] unter [planAdaptationKey].
class SettingsPlanAdaptationStore implements PlanAdaptationStore {
  const SettingsPlanAdaptationStore(this._settings);

  final SettingsStore _settings;

  @override
  Future<PlanAdaptationMode> read() async =>
      PlanAdaptationMode.fromStorage(await _settings.get(planAdaptationKey));

  @override
  Future<void> set(PlanAdaptationMode mode, {required DateTime at}) =>
      _settings.set(planAdaptationKey, mode.storageValue, at: at);
}

/// Grund-Code ([PlanVersionDraft.reason]) einer Fassung, in der eine
/// intensive Einheit wegen eines niedrigen Readiness-Werts locker wurde
/// (PAR-173). Auslöser ist `feedback` (kein eigener Auslöser im Schema).
const String planReasonReadiness = 'readiness';

/// Grund-Code der Fassung nach dem Wechsel auf „fix“, wenn die Lockerung von
/// heute dadurch entfällt.
const String planReasonAdaptationFixed = 'adaptationFixed';

/// Schlüssel im `summary` einer Fassung: die Einheiten, die die Lockerung
/// nach PAR-173 ersetzt hat ([RecoveryEased]), ab dem Montag der Woche von
/// „heute“. Fehlt er, hat die Fassung nichts gelockert.
const String planRecoveryKey = 'recoveryEased';

/// Readiness eines Tags, so wie die Planregel sie braucht (PAR-173). Kein
/// Messwert, nur Band und die Faktoren der Erklärung (FR-0117).
class PlanReadinessDay {
  const PlanReadinessDay({
    required this.day,
    required this.band,
    this.drivers = const [],
  });

  /// Aus einem Wert 0 bis 100 (Band nach FR-0116).
  PlanReadinessDay.number({
    required DateTime day,
    required int value,
    List<ReadinessFactorId> drivers = const [],
  }) : this(day: day, band: readinessBandOf(value), drivers: drivers);

  /// Aus dem Ergebnis des Modells für [day]. Ohne Zahl (eingeschränkte
  /// Einschätzung, unzureichende Daten) ohne Band: wirkt nicht.
  factory PlanReadinessDay.of(DateTime day, ReadinessResult r) =>
      PlanReadinessDay(
        day: day,
        band: r.state == ReadinessState.number ? r.band : null,
        drivers: [
          for (final d in r.explanation.drivers)
            if (d.direction == ReadinessDirection.lower) d.id,
        ],
      );

  /// Kalendertag des Werts.
  final DateTime day;

  /// `null`: keine Zahl.
  final ReadinessBand? band;

  /// Faktoren, die den Wert gesenkt haben, wichtigster zuerst (FR-0117).
  final List<ReadinessFactorId> drivers;

  /// Band „Erhöhte Belastung“ oder „Erholung empfohlen“ (PAR-173).
  bool get eases =>
      band == ReadinessBand.elevatedLoad ||
      band == ReadinessBand.recoveryAdvised;
}

/// Eine nach PAR-173 gelockerte Einheit: ihr Stand vor der Lockerung
/// ([unit], gleiche Felder wie beim Warnsignal) und die Begründung (Band und
/// Faktoren nach FR-0117).
class RecoveryEased {
  const RecoveryEased({
    required this.unit,
    required this.band,
    this.drivers = const [],
  });

  final WarningHeld unit;
  final ReadinessBand band;
  final List<ReadinessFactorId> drivers;

  DateTime get day => unit.day;

  Map<String, Object?> toJson() => {
    ...unit.toJson(),
    'band': band.name,
    'drivers': [for (final d in drivers) d.name],
  };

  static RecoveryEased? fromJson(Object? json) {
    final unit = WarningHeld.fromJson(json);
    if (unit == null || json is! Map) return null;
    final band = ReadinessBand.values.asNameMap()[json['band']];
    if (band == null) return null;
    final raw = json['drivers'];
    final ids = ReadinessFactorId.values.asNameMap();
    return RecoveryEased(
      unit: unit,
      band: band,
      drivers: raw is List ? [for (final d in raw) ?ids[d]] : const [],
    );
  }
}

/// Die gelockerten Einheiten aus dem `summary` einer Fassung; leer, wenn sie
/// nichts gelockert hat. Unlesbare Einträge entfallen.
List<RecoveryEased> recoveryEasedFromSummary(Map<String, Object?> summary) {
  final raw = summary[planRecoveryKey];
  if (raw is! List) return const [];
  return [for (final e in raw) ?RecoveryEased.fromJson(e)];
}

/// Kann die Lockerung [u] treffen? Geplant intensiv nach PAR-058 (Intervalle,
/// Tempodauerlauf, progressiver Lauf; der lange Lauf zählt nur für den
/// Abstand), offen (ohne Lauf) und ohne vom Nutzer festgelegte Art
/// (ADR-0010).
bool recoveryEasable(PlanUnit u) =>
    u.isHard && u.runId == null && !u.fixed.keepsKind;

/// Ergebnis von [applyRecoveryEase].
class RecoveryEaseResult {
  const RecoveryEaseResult(this.units, this.eased);

  final List<PlanUnit> units;

  /// Alle heute geltenden Lockerungen (gehaltene und neue), nach Tag.
  final List<RecoveryEased> eased;
}

/// Lockerung nach PAR-173 über [units] (eine Rechnung ohne Lockerung, Tag ab
/// [today]):
///
/// * Nur bei [PlanAdaptationMode.adaptive]; bei „fix“ bleiben die Einheiten
///   unverändert, gehaltene Lockerungen ab heute entfallen.
/// * Eine Einheit nach [recoveryEasable] wird mit [ease] locker, wenn für
///   genau ihren Tag ein Wert in [readiness] liegt, der [PlanReadinessDay.eases]
///   erfüllt. Werte anderer Tage zählen nicht (nichts vorgezogen oder
///   übertragen). Ein hoher Wert ändert nichts.
/// * Eine Lockerung aus [held] (frühere Fassung) für den Tag bleibt, auch
///   wenn der Wert inzwischen besser ist: ein hoher Wert erhöht nie.
///
/// Das Warnsignal legt der Aufrufer danach darüber (Vorrang, K58).
RecoveryEaseResult applyRecoveryEase({
  required List<PlanUnit> units,
  required DateTime today,
  required PlanAdaptationMode mode,
  required PlanUnit Function(PlanUnit hard) ease,
  Iterable<PlanReadinessDay> readiness = const [],
  List<RecoveryEased> held = const [],
}) {
  if (mode != PlanAdaptationMode.adaptive) {
    return RecoveryEaseResult(units, const []);
  }
  final todayDay = planDay(today);
  final heldByDay = {
    for (final h in held)
      if (!h.day.isBefore(todayDay)) h.day: h,
  };
  final lowByDay = {
    for (final r in readiness)
      if (r.eases) planDay(r.day): r,
  };
  final eased = <RecoveryEased>[];
  final out = <PlanUnit>[];
  for (final u in units) {
    final day = planDay(u.day);
    if (day.isBefore(todayDay) || !recoveryEasable(u)) {
      out.add(u);
      continue;
    }
    final h = heldByDay[day];
    final low = lowByDay[day];
    final ReadinessBand band;
    final List<ReadinessFactorId> drivers;
    if (h != null) {
      band = h.band;
      drivers = h.drivers;
    } else if (low != null) {
      band = low.band!;
      drivers = low.drivers;
    } else {
      out.add(u);
      continue;
    }
    out.add(ease(u));
    eased.add(
      RecoveryEased(
        unit: WarningHeld(
          day: day,
          kind: u.kind,
          fixed: u.fixed,
          pinned: u.pinned,
          minutes: u.minutes,
          segments: u.segments,
        ),
        band: band,
        drivers: drivers,
      ),
    );
  }
  return RecoveryEaseResult(out, eased);
}

/// Stellt in [units] (gespeicherter Plan) die Einheiten der Lockerungen
/// [eased] wieder her (Art, Dauer, Abschnitte vor der Lockerung), damit die
/// Rechnung von der Fassung ohne Lockerung ausgeht. Nur offene lockere
/// Einheiten ohne Festlegung des Nutzers: Was der Nutzer danach festgelegt
/// hat, gilt weiter (ADR-0010).
List<PlanUnit> restoreRecoveryEased(
  List<PlanUnit> units,
  List<RecoveryEased> eased,
) {
  final byDay = {for (final e in eased) e.day: e.unit};
  return [
    for (final u in units)
      if (byDay[planDay(u.day)] case final h?
          when u.kind == PlanUnitKind.easy &&
              u.runId == null &&
              u.fixed == PlanUnitFixed.none)
        PlanUnit(
          id: u.id,
          day: u.day,
          kind: h.kind,
          phase: u.phase,
          weekIndex: u.weekIndex,
          minutes: h.minutes,
          segments: h.segments,
          pinned: u.pinned,
          fixed: h.fixed,
          method: u.method,
          methodVersion: u.methodVersion,
        )
      else
        u,
  ];
}

/// Empfehlung bei „fix“ (FR-0216, PAR-173): Der Plan bleibt, aber die App
/// empfiehlt für heute einen lockeren Lauf, wenn bei „adaptiv“ genau diese
/// Einheit gelockert würde: offene harte Einheit [unit] von [today]
/// ([recoveryEasable]) und ein Wert von [today] in einem Band nach
/// [PlanReadinessDay.eases]. Bei „adaptiv“ nie (dort lockert der Plan selbst),
/// ohne Wert, mit dem Wert eines anderen Tags oder ohne Zahl nicht.
bool recoveryRecommendsEasy({
  required PlanAdaptationMode mode,
  required PlanReadinessDay? readiness,
  required PlanUnit? unit,
  required DateTime today,
}) {
  if (mode != PlanAdaptationMode.fixed) return false;
  if (readiness == null || unit == null || !readiness.eases) return false;
  final day = planDay(today);
  return planDay(readiness.day) == day &&
      planDay(unit.day) == day &&
      recoveryEasable(unit);
}
