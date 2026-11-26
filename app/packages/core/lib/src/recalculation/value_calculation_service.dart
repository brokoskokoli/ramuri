import '../../ports/clock.dart';
import '../../ports/storage.dart';
import '../../ports/storage_runs.dart';
import '../../ports/storage_values.dart';
import '../fitness/aerobic_efficiency.dart';
import '../fitness/algorithm_lookup.dart';
import '../fitness/fitness_parameters.dart';
import '../fitness/heart_rate_basis.dart';
import '../fitness/high_heart_rate_time.dart';
import '../fitness/load_profile.dart';
import '../fitness/vo2max_estimator.dart';
import '../fitness/vo2max_long_term.dart';
import '../preprocessing/preprocessing_chain.dart';
import '../preprocessing/preprocessing_parameters.dart';
import '../recording/treadmill.dart' show RunMode;
import 'run_overview_summary.dart' show overviewOf;
import '../profile/heart_rate_resolution.dart';
import '../settings/load_settings.dart';
import '../settings/reserve_zone_settings.dart';
import '../statistics/offload.dart';
import 'calculation_failures.dart';
import 'high_heart_rate_value.dart';
import 'run_analysis.dart';
import '../subjective/subjective_service.dart' show refreshSrpe;
import 'run_load_values.dart';
import '../calendar/run_day.dart';

/// Die Werte, die nach einem Lauf entstehen.
class RunCalculationResult {
  const RunCalculationResult({
    required this.runValue,
    required this.longTerm,
    required this.efficiency,
    required this.day,
  });

  /// VO₂max-Laufwert (Besitzer: der Lauf).
  final ComputedValue runValue;

  /// Langzeitwert und aerobe Effizienz (Besitzer: der Tag [day]). Die
  /// Effizienz fehlt (`null`), wenn die Basis eines Laufs im Fenster nicht
  /// bekannt ist (siehe [ValueCalculationService]).
  final ComputedValue longTerm;
  final ComputedValue? efficiency;
  final String day;
}

/// Zwischenstand einer Neuberechnung: alle neuen Werte, noch nicht gespeichert.
/// [runValues] und [dayValues] tauschen vorhandene Werte (`current`);
/// [runCreates] legt Laufwerte an, die ein Lauf noch nicht hat (ein Wert, den
/// eine neue Methode einführt, ADR-0004).
class ValueSnapshot {
  const ValueSnapshot({
    required this.runValues,
    required this.dayValues,
    this.runCreates = const {},
    this.dayCreates = const {},
    this.removedDays = const {},
  });

  final Map<ValueOwner, List<ComputedValue>> runValues;
  final Map<ValueOwner, List<ComputedValue>> dayValues;
  final Map<ValueOwner, List<ComputedValue>> runCreates;

  /// Tageswerte, die neu angelegt werden: Tage mit einem Lauf mit Laufwert,
  /// die noch keine haben (z. B. der Starttag eines Laufs über Mitternacht
  /// nach der neuen Tageszuordnung, PAR-237).
  final Map<ValueOwner, List<ComputedValue>> dayCreates;

  /// Tage mit gespeicherten Tageswerten, aber ohne beendeten Lauf ([dayOfRun]):
  /// ihre Tageswerte entfallen (z. B. der Endtag eines Laufs über
  /// Mitternacht, PAR-237).
  final Set<String> removedDays;

  /// Läufe mit getauschten oder neu angelegten Werten.
  int get runCount => {...runValues.keys, ...runCreates.keys}.length;
}

/// Gehört ein Lauf mit diesen gespeicherten Werten zur Neuberechnung? Ja,
/// wenn er einen Laufwert (VO₂max) oder einen TRIMP hat; ein Lauf ohne beide
/// ist noch nicht gerechnet und bekommt alle Werte mit seiner Berechnung. Die
/// EINE Stelle für [ValueCalculationService.buildSnapshot], die betroffenen
/// Läufe und die Prüfung auf fehlende Werte im Angebot.
bool hasRecalculatedRunValue(Iterable<ValuePair> stored) =>
    hasRecalculatedRunKey(stored.map((p) => p.original.key));

/// [hasRecalculatedRunValue] über die Schlüssel der gespeicherten Werte (für
/// die Sammelabfrage `readRunValues` mit [recalculatedRunValueKeys]).
bool hasRecalculatedRunKey(Iterable<String> keys) =>
    keys.any(recalculatedRunValueKeys.contains);

/// Schlüssel der Laufwerte, die einen Lauf zur Neuberechnung gehören lassen
/// ([hasRecalculatedRunValue]).
const Set<String> recalculatedRunValueKeys = {
  vo2maxRunValueKey,
  trimpRunValueKey,
};

/// Rechnet VO₂max-Laufwert, Langzeitwert und aerobe Effizienz aus den
/// gespeicherten Rohdaten (FR-0066 bis FR-0087), dazu die Laufwerte für Zonen
/// und TRIMP ([buildRunLoadValues]), und speichert sie als
/// `original` und `current` mit den Angaben aus FR-0053, den bewerteten
/// Abschnitten (FR-0073) und der verwendeten Herzfrequenzbasis (OQ-0065).
/// Netzwerkfrei (SEC-0006), Zeit nur über [Clock].
///
/// Tageswerte (Langzeitwert, aerobe Effizienz) gehören dem Tag des Laufs,
/// dem Ortstag seines Beginns ([dayOfRun], PAR-237); sie gelten für das Ende
/// dieses Tages (mit dem Versatz des zuletzt endenden Laufs des Tages, bei
/// einem Lauf über Mitternacht für dessen Ende), für den heutigen Tag für
/// jetzt. Gibt es für den Tag schon einen Wert, wird sein
/// `current` getauscht, das `original` ist dann der erste Wert des Tages.
///
/// Herzfrequenzbasis der aeroben Effizienz: jeder Lauf mit gespeichertem
/// Laufwert geht mit der Basis ein, die an diesem Wert steht, nie mit der
/// aktuellen. Läufe ohne Laufwert gehen mit der aktuellen Profilbasis ein
/// (es gibt keine andere). Ist die Basis eines Laufwerts unbekannt (Wert aus
/// Schema 1, `heartRateBasis == null`), wird die Effizienz nicht berechnet:
/// ein vorhandener Tageswert bleibt unverändert, ein fehlender wird nicht
/// angelegt. Der Langzeitwert braucht nur die gespeicherten Laufwerte. Die
/// Basis am Effizienzwert ist die gemeinsame der Läufe im Fenster, bei
/// verschiedenen `null`; der Langzeitwert trägt keine.
class ValueCalculationService {
  ValueCalculationService({
    required this.session,
    required this.clock,
    required this.algorithms,
    this.fitness = const FitnessParameters.v4(),
    this.preprocessing = const PreprocessingParameters.v4(),
    this.offload = inlineOffload,
    String? preprocessingVersion,
  }) : vo2maxEstimator = algorithms.active(vo2maxEstimatorFamily),
       longTerm = algorithms.active(vo2maxLongTermFamily),
       efficiency = algorithms.active(aerobicEfficiencyFamily),
       highHeartRateTime = algorithms.active(highHeartRateTimeFamily),
       preprocessingVersion =
           preprocessingVersion ?? preprocessingChainVersion();

  final StorageSession session;
  final Clock clock;

  /// Die Registry der App (ADR-0004, NFR-0005). Die Verfahren unten sind ihre
  /// aktiven Varianten beim Bau; Laufanalyse ([RunAnalyzer]) und
  /// Versionsprüfung (`RecalculationService.checkVersions`) nehmen beide
  /// diese, nie eine eigene Instanz.
  final AlgorithmLookup algorithms;
  final FitnessParameters fitness;
  final PreprocessingParameters preprocessing;

  /// Wo die Vorverarbeitung jedes Laufs gerechnet wird ([RunAnalyzer.offload]);
  /// in der App für die Neuberechnung ein eigener Isolate.
  final Offload offload;

  /// VO₂max-Schätzer des Laufwerts ([vo2maxEstimatorFamily]).
  final Vo2maxEstimator vo2maxEstimator;

  /// Langzeitwert ([vo2maxLongTermFamily]).
  final Vo2maxLongTerm longTerm;

  /// Aerobe Effizienz ([aerobicEfficiencyFamily]).
  final AerobicEfficiency efficiency;

  /// Zeit bei mindestens 80 % HFmax ([highHeartRateTimeFamily]).
  final HighHeartRateTimeModel highHeartRateTime;

  /// Methode und Methodenversion, mit denen dieser Dienst jeden Tageswert aus
  /// [dayValueKeys] rechnet (die Parameterversion ist die der
  /// Fitnessparameter). Die Versionsprüfung der Neuberechnung vergleicht die
  /// gespeicherten Tageswerte damit (ADR-0004 Punkt 3); ein neuer
  /// Tagesschlüssel braucht hier einen Eintrag.
  Map<String, (String, int)> get dayValueMethods => {
    vo2maxLongTermValueKey: (longTerm.method, longTerm.methodVersion),
    aerobicEfficiencyValueKey: (efficiency.method, efficiency.methodVersion),
  };

  /// Kettenversion der Vorverarbeitung, die an jeden neuen Laufwert kommt
  /// und gegen die `RecalculationService.checkVersions` die gespeicherten
  /// prüft (ADR-0004). Ohne Angabe die der App ([preprocessingChainVersion]);
  /// Tests setzen eine Kette mit erhöhter Stufe.
  final String preprocessingVersion;

  /// Herzfrequenzbasis des gespeicherten Profils (FR-0003, FR-0004), wie sie
  /// an Werten gespeichert wird.
  Future<HeartRateBasis> _profileBasis() async => snapshotOf(
    resolveHeartRate(
      await session.profile.read(),
      currentYear: clock.now().year,
      fitness: fitness,
    ).basis,
  );

  /// Aufgelöstes Belastungsprofil (FR-0197): [profile] oder das gespeicherte
  /// aktive; Banister nur anwendbar mit Ruhepuls, Koeffizienten und
  /// berechenbarem `r`. [coefficients] ersetzt die gespeicherte Angabe (die
  /// Änderung, die ein Angebot erst nach der Bestätigung gültig macht).
  Future<LoadProfileResolution> loadResolution(
    HeartRateBasis basis, {
    LoadProfile? profile,
    CoefficientChange? coefficients,
  }) async => resolveLoadProfile(
    requested: profile ?? await LoadSettings.activeProfile(session.settings),
    basis: basis,
    coefficients: coefficients != null
        ? coefficients.value
        : await LoadSettings.coefficients(session.settings),
    fitness: fitness,
  );

  /// Basis des gespeicherten Profils für die Auflösung des Belastungsprofils.
  Future<HeartRateBasis> profileBasis() => _profileBasis();

  RunAnalyzer _analyzer(HeartRateBasis basis) => RunAnalyzer(
    fitness: fitness,
    preprocessing: preprocessing,
    basis: basis,
    estimator: vo2maxEstimator,
    offload: offload,
  );

  Future<List<StoredRun>> _finishedRuns() async => [
    for (final r in await session.runs.list())
      if (r.state == RunState.finished && r.endedAt != null) r,
  ];

  /// Rechnet den beendeten Lauf [runId] und speichert seine Werte samt den
  /// Tageswerten in EINER Transaktion; vorher wird alles gerechnet, ein
  /// Fehler dabei oder beim Speichern hinterlässt nichts, und ein neuer
  /// Versuch ist möglich. Ein Lauf, der schon Werte hat, ist `rejected` (ein
  /// Original wird nie ersetzt). Eine abweichende Parameterversion wirft
  /// [ArgumentError].
  ///
  /// Spätere Tage (ADR-0004, FR-0078): Liegen nach dem Tag des Laufs Tage mit
  /// einem Lauf mit Laufwert (der Lauf wird nachträglich gerechnet), werden
  /// deren Tageswerte in derselben Transaktion mit dem neuen Laufwert neu
  /// gerechnet, wie bei [refreshAfterDelete]: vorhandene im `current`
  /// getauscht (das `original` bleibt, FR-0058), fehlende angelegt. Ohne
  /// solche Tage (gerade beendeter Lauf) entsteht keine weitere Rechnung.
  Future<RunCalculationResult> calculateAfterRun(int runId) =>
      _calculateAfterRun(runId);

  /// [calculateAfterRun]; [refreshDay] wählt die übrigen Tage, deren
  /// Tageswerte mitgerechnet werden (ohne Angabe: alle nach dem Tag des
  /// Laufs). Der Tag des Laufs selbst wird immer gerechnet.
  Future<RunCalculationResult> _calculateAfterRun(
    int runId, {
    bool Function(String day, String runDay)? refreshDay,
  }) async {
    final now = clock.now();
    final run = await session.runs.get(runId);
    if (run == null) throw const StorageException(StorageFailure.notFound);
    final profile = await _profileBasis();
    final analysis = await _analyzer(profile)
        .analyze(session, run, calculatedAt: now);
    final runValue = analysis.vo2maxValue(
      now,
      preprocessingVersion: preprocessingVersion,
    );

    final runs = await _finishedRuns();
    final stored = await session.values.readRunValues({vo2maxRunValueKey});
    final runValues = <int, ComputedValue>{
      runId: runValue,
      for (final other in runs)
        if (other.id != runId) other.id: ?stored[other.id]?[vo2maxRunValueKey],
    };
    final day = dayOfRun(run);
    final cache = <int, RunAnalysis>{runId: analysis};
    final values = await _dayValues(
      day: day,
      runs: runs,
      asOf: _asOf(day, runs, now),
      computedAt: now,
      runValues: runValues,
      fallback: profile,
      analysisOf: (r, basis) async =>
          cache[r.id] ??= await _analyzer(basis)
              .analyze(session, r, calculatedAt: now),
    );
    // Tageswerte des Tags und aller späteren Tage in EINER Abfrage; geschrieben
    // wird erst am Ende, alle Entscheidungen sehen also denselben Stand.
    final plan = _DayPlan(await session.values.readDayValues(dayValueKeys));
    plan.add(day, values.all);
    final select = refreshDay ?? (d, runDay) => d.compareTo(runDay) > 0;
    final later = <String>{
      for (final r in runs)
        if (runValues.containsKey(r.id) && dayOfRun(r) != day) dayOfRun(r),
    }.where((d) => select(d, day)).toList()..sort();
    for (final d in later) {
      final dayValues = await _dayValues(
        day: d,
        runs: runs,
        asOf: _asOf(d, runs, now),
        computedAt: now,
        runValues: runValues,
        fallback: profile,
        analysisOf: (r, basis) async =>
            cache[r.id] ??= await _analyzer(basis)
                .analyze(session, r, calculatedAt: now),
      );
      plan.add(d, dayValues.all);
    }
    // Zonenzeiten und TRIMP mit den Zonengrenzen und der Basis zum Laufende;
    // Zonenzeiten werden nie neu gerechnet (L11), TRIMP nur bei geänderter
    // Basis im current (FR-0006).
    final bounds = (await ReserveZoneSettings.loadParameters(session.settings))
        .reserveZoneBounds;
    final loadValues = buildRunLoadValues(
      run: run,
      pre: analysis.preprocessing,
      basis: profile,
      fitness: fitness.copyWith(reserveZoneBounds: bounds),
      sources: analysis.sources,
      computedAt: now,
      preprocessingVersion: preprocessingVersion,
      loadProfile: await loadResolution(profile),
    );
    // Zeit bei mindestens 80 % HFmax (PAR-058) mit der Basis zum Laufende.
    final highTime = buildHighHeartRateTimeValue(
      run: run,
      pre: analysis.preprocessing,
      basis: profile,
      fitness: fitness,
      sources: analysis.sources,
      computedAt: now,
      preprocessingVersion: preprocessingVersion,
      model: highHeartRateTime,
    );
    // Kurzfassung für Historie und Vergleich (vor den Werten: scheitert sie,
    // ist nichts geschrieben und ein neuer Versuch möglich).
    final pre = analysis.preprocessing;
    if (pre != null) {
      await session.preprocessing.replace(
        runId,
        overviewOf(
          pre,
          computedAt: now,
          lapCount: (await session.markers.laps(runId)).length,
          belt: analysis.belt,
          isRunning: run.mode.isRunning,
        ),
      );
      // Angaben zum Lauf, die schon vor der Berechnung gemacht wurden: sRPE
      // folgt der jetzt bekannten Bewegungszeit.
      await refreshSrpe(session, runId);
    }
    await session.values.writeAll(
      create: {
        ValueOwner.run(runId): [runValue, ...loadValues, highTime],
        ...plan.create,
      },
      swap: plan.swap,
    );
    return RunCalculationResult(
      runValue: runValue,
      longTerm: values.longTerm,
      efficiency: values.efficiency,
      day: day,
    );
  }

  /// Einstellungsschlüssel des Merkers „Werte nach dem Lauf noch berechnen“:
  /// kommagetrennte Lauf-IDs (keine Gesundheitsdaten).
  static const String calculationPendingKey = 'values.calculationPending';

  Future<Set<int>> _pendingCalculations() async {
    final raw = await session.settings.get(calculationPendingKey) ?? '';
    return {
      for (final p in raw.split(','))
        if (int.tryParse(p) != null) int.parse(p),
    };
  }

  Future<void> _setPendingCalculations(Set<int> ids) => session.settings.set(
    calculationPendingKey,
    (ids.toList()..sort()).join(','),
    at: clock.now(),
  );

  /// Berechnet die Werte des gerade beendeten Laufs [runId] ([calculateAfterRun])
  /// und merkt ihn vorher als offen. Gelingt die Berechnung, wird er
  /// ausgetragen; sonst wird der Fehler weitergegeben, der Lauf bleibt
  /// gespeichert und [completePendingCalculations] (App-Start) holt die
  /// Berechnung nach. Scheitert schon das Merken, wird trotzdem gerechnet.
  Future<RunCalculationResult> calculateAfterRunTracked(int runId) async {
    var marked = true;
    try {
      await _setPendingCalculations({...await _pendingCalculations(), runId});
    } on Object {
      marked = false;
    }
    final result = await calculateAfterRun(runId);
    if (marked) await _unmark(runId);
    return result;
  }

  Future<void> _unmark(int runId) async {
    try {
      await _setPendingCalculations(
        (await _pendingCalculations())..remove(runId),
      );
    } on Object {
      // Ein stehengebliebener Eintrag wird beim nächsten Start erkannt
      // (Lauf hat dann Werte) und entfernt.
    }
  }

  /// Zähler der gescheiterten Versuche beim Nachholen (FR-0219).
  CalculationFailures get failures => CalculationFailures(
    settings: session.settings,
    clock: clock,
    fitness: fitness,
    preprocessing: preprocessing,
  );

  /// Rechnet beim Start alle beendeten Läufe ohne Laufwert nach, gemerkte oder
  /// nicht: [calculateAfterRun] schreibt immer einen Laufwert (notfalls „nicht
  /// bestimmbar“ mit Grund), ein beendeter Lauf ohne Laufwert ist also offen,
  /// auch wenn der Merker fehlt (Schreibfehler im Lauf, App-Ende vor dem
  /// Merken). Gemerkte, gelöschte Läufe und Läufe mit Laufwert werden nur
  /// ausgetragen; ein Lauf, dessen Werte nicht gelesen werden konnten, bleibt
  /// gemerkt. Der erste Fehler wird nach den übrigen Läufen weitergegeben;
  /// die betroffenen Einträge bleiben.
  ///
  /// Fehlversuche (FR-0219): Jede gescheiterte Berechnung zählt für den Lauf
  /// ([CalculationFailures]); ein Lesefehler zählt nicht. Nach
  /// [uncomputableAfterFailures] Fehlversuchen wird der Lauf nicht mehr
  /// versucht (er bleibt gemerkt), bis die Zähler zurückgesetzt sind
  /// ([retryUncomputable]) oder der Stand der Berechnung sich ändert. Gelingt
  /// die Berechnung oder fehlt der Lauf, wird sein Zähler entfernt. Scheitert
  /// nur das Zählen, wird der Lauf beim nächsten Start erneut versucht.
  ///
  /// Spätere Tage: Die Läufe werden in der Reihenfolge ihres Endes gerechnet;
  /// jeder rechnet die späteren Tageswerte ([calculateAfterRun]) nur bis vor
  /// den Tag des nächsten Laufs, jeder Tag wird so höchstens einmal neu
  /// gerechnet. Scheitert ein Lauf nach einem gelungenen, rechnet der nächste
  /// gelungene die Tage ab dem Tag des gescheiterten mit; scheitern die
  /// letzten, werden diese Tage am Ende in einem Schritt neu gerechnet.
  Future<void> completePendingCalculations() async {
    Object? failure;
    final marked = await _pendingCalculations();
    final open = <int>{};
    final unread = <int>{};
    final finished = await _finishedRuns();
    for (final r in finished) {
      try {
        if ((await session.values.read(ValueOwner.run(r.id))).isEmpty) {
          open.add(r.id);
        }
      } on Object catch (e) {
        // Nicht gelesen: weder rechnen noch austragen, der Merker bleibt.
        unread.add(r.id);
        failure ??= e;
      }
    }
    final counter = failures;
    var counts = const <int, int>{};
    try {
      counts = await counter.read();
      // Gelöschte Läufe und Läufe mit Laufwert brauchen keinen Zähler mehr.
      await counter.remove({
        for (final id in counts.keys)
          if (!open.contains(id) && !unread.contains(id)) id,
      });
    } on Object {
      // Ohne Zähler wird jeder offene Lauf versucht.
    }
    // Zu rechnen sind die offenen Läufe unter der Grenze der Fehlversuche.
    final byId = {for (final r in finished) r.id: r};
    final calculated = await _calculateInOrder(
      [
        for (final id in open)
          if ((counts[id] ?? 0) < uncomputableAfterFailures) byId[id]!,
      ],
      counter: counter,
      onComputed: (id) async {
        if (counts.containsKey(id)) await _forget(counter, id);
      },
    );
    failure ??= calculated.failure;
    final computed = calculated.computed;
    // Gemerkte Läufe austragen, außer sie sind noch offen oder nicht gelesen.
    for (final id in marked.toList()..sort()) {
      if (unread.contains(id)) continue;
      if (open.contains(id) && !computed.contains(id)) continue;
      await _unmark(id);
    }
    if (failure != null) throw failure;
  }

  /// Rechnet die offenen Läufe [runs] ([calculateAfterRun]) in der
  /// Reihenfolge ihres Tages ([dayOfRun]), am selben Tag ihres Endes: Jeder Lauf rechnet die späteren Tage nur bis vor
  /// den Tag des nächsten (der rechnet sie ohnehin), so wird jeder spätere Tag
  /// höchstens einmal neu gerechnet. Scheitert ein Lauf nach einem gelungenen,
  /// rechnet der nächste gelungene die Tage ab dem Tag des gescheiterten mit;
  /// scheitern die letzten, werden diese Tage am Ende in einem Schritt neu
  /// gerechnet. Jeder Fehlschlag zählt für den Lauf ([_recordFailure]); nach
  /// jedem gelungenen Lauf folgt [onComputed]. Gibt die gelungenen Läufe und
  /// den ersten Fehler zurück.
  Future<({Set<int> computed, Object? failure})> _calculateInOrder(
    List<StoredRun> runs, {
    required CalculationFailures counter,
    required Future<void> Function(int runId) onComputed,
  }) async {
    final toCalculate = [...runs]..sort(_byDay);
    Object? failure;
    // Tag, ab dem (einschließlich) Tageswerte nach einem gescheiterten Lauf
    // noch einen früher gerechneten Laufwert brauchen.
    String? staleFrom;
    var changed = false;
    final computed = <int>{};
    for (var i = 0; i < toCalculate.length; i++) {
      final id = toCalculate[i].id;
      final next = i + 1 < toCalculate.length
          ? dayOfRun(toCalculate[i + 1])
          : null;
      final from = staleFrom;
      try {
        try {
          await _calculateAfterRun(
            id,
            refreshDay: (d, runDay) =>
                (d.compareTo(runDay) > 0 ||
                    (from != null && d.compareTo(from) >= 0)) &&
                (next == null || d.compareTo(next) < 0),
          );
        } on Object {
          await _recordFailure(counter, id);
          rethrow;
        }
        changed = true;
        computed.add(id);
        staleFrom = null;
      } on Object catch (e) {
        if (changed) staleFrom ??= dayOfRun(toCalculate[i]);
        failure ??= e;
        continue;
      }
      try {
        await onComputed(id);
      } on Object catch (e) {
        failure ??= e;
      }
    }
    if (staleFrom != null) {
      try {
        await _refreshDays(from: staleFrom);
      } on Object catch (e) {
        failure ??= e;
      }
    }
    return (computed: computed, failure: failure);
  }

  static int _byDay(StoredRun a, StoredRun b) {
    final d = dayOfRun(a).compareTo(dayOfRun(b));
    if (d != 0) return d;
    final c = a.endedAt!.compareTo(b.endedAt!);
    return c != 0 ? c : a.id.compareTo(b.id);
  }

  Future<void> _recordFailure(CalculationFailures counter, int runId) async {
    try {
      await counter.recordFailure(runId);
    } on Object {
      // Nicht gezählt: der Lauf wird beim nächsten Start erneut versucht.
    }
  }

  Future<void> _forget(CalculationFailures counter, int runId) async {
    try {
      await counter.remove({runId});
    } on Object {
      // Der Lauf hat jetzt Werte; der Eintrag wird beim nächsten Start entfernt.
    }
  }

  /// Versucht die nicht berechenbaren Läufe ([CalculationFailures.uncomputable])
  /// erneut, mit zurückgesetztem Zähler („Neu berechnen“, FR-0219). Gelingt
  /// die Berechnung, ist der Lauf ausgetragen; ein neuer Fehlschlag zählt als
  /// erster Versuch, der Start versucht ihn dann wieder. Andere offene Läufe
  /// bleiben dem Nachholen beim Start ([completePendingCalculations]). Der
  /// erste Fehler wird nach den übrigen Läufen weitergegeben. Spätere Tage wie
  /// beim Nachholen ([_calculateInOrder]): jeder höchstens einmal neu gerechnet.
  Future<void> retryUncomputable() async {
    final counter = failures;
    final ids = await counter.uncomputable();
    if (ids.isEmpty) return;
    await counter.remove(ids);
    Object? failure;
    // Gelöschte, nicht beendete und schon gerechnete Läufe entfallen.
    final open = <StoredRun>[];
    for (final id in ids.toList()..sort()) {
      try {
        final run = await session.runs.get(id);
        if (run == null ||
            run.state != RunState.finished ||
            run.endedAt == null ||
            (await session.values.read(ValueOwner.run(id))).isNotEmpty) {
          continue;
        }
        open.add(run);
      } on Object catch (e) {
        failure ??= e;
      }
    }
    final calculated = await _calculateInOrder(
      open,
      counter: counter,
      onComputed: (id) async {
        if ((await _pendingCalculations()).contains(id)) await _unmark(id);
      },
    );
    failure ??= calculated.failure;
    if (failure != null) throw failure;
  }

  /// Einstellungsschlüssel des Merkers „Tageswerte nach dem Löschen neu
  /// anlegen“ (nur Lauf-ID und Zeitpunkt, keine Gesundheitsdaten).
  static const String refreshPendingKey = 'values.refreshPending';

  /// Setzt den Merker vor dem Löschen von Lauf [runId]. Scheitert das, wirft
  /// es; dann wurde noch nichts gelöscht.
  Future<void> markRefreshPending(int runId) => session.settings.set(
    refreshPendingKey,
    '$runId@${clock.now().toUtc().toIso8601String()}',
    at: clock.now(),
  );

  /// Entfernt den Merker (ohne ihn zu prüfen).
  Future<void> clearRefreshPending() =>
      session.settings.set(refreshPendingKey, '', at: clock.now());

  /// Steht ein Merker, werden die Tageswerte neu angelegt
  /// ([refreshAfterDelete]); nach Erfolg wird der Merker entfernt, bei einem
  /// Fehler bleibt er stehen und der Fehler wird weitergegeben. Nicht
  /// parallel zu einer Neuberechnung aufrufen (eine Dienstinstanz).
  Future<void> completePendingRefresh() async {
    final mark = await session.settings.get(refreshPendingKey);
    if (mark == null || mark.isEmpty) return;
    await refreshAfterDelete();
    await clearRefreshPending();
  }

  /// Nach dem Löschen eines Laufs: Langzeit- und Tageswerte aller Tage mit
  /// einem Lauf, der einen Laufwert hat, neu rechnen (die Speicherschicht hat
  /// überlappende Tageswerte gelöscht). Laufwerte bleiben unverändert
  /// (OQ-0065), die Effizienz alter Läufe wird mit der am Laufwert gespeicherten
  /// Basis gerechnet (nie mit der aktuellen, vielleicht abgelehnten); ist sie
  /// unbekannt, bleibt die Effizienz unverändert (siehe Klasse). Fehlende
  /// Tageswerte werden neu angelegt, vorhandene im `current` getauscht, alle in
  /// EINER Transaktion. Tage ohne Lauf mit Laufwert bekommen nichts.
  ///
  /// Wird das Neuanlegen unterbrochen, fehlen Tageswerte ohne Grund. Darum
  /// setzt der Aufrufer vor dem Löschen [markRefreshPending]; [completePendingRefresh]
  /// legt die Werte neu an (auch beim nächsten Start) und entfernt den Merker.
  Future<void> refreshAfterDelete() => _refreshDays();

  /// Rechnet die Tageswerte aller Tage mit einem Lauf mit Laufwert neu, ab dem
  /// Tag [from] (einschließlich; ohne Angabe alle), in EINER Transaktion.
  Future<void> _refreshDays({String? from}) async {
    final now = clock.now();
    final runs = await _finishedRuns();
    final stored = await session.values.readRunValues({vo2maxRunValueKey});
    final runValues = <int, ComputedValue>{
      for (final r in runs) r.id: ?stored[r.id]?[vo2maxRunValueKey],
    };
    if (runValues.isEmpty) return;
    final profile = await _profileBasis();
    final cache = <int, RunAnalysis>{};
    // Tageswerte aller Tage in EINER Abfrage (erst nach dem Ausstieg ohne
    // Laufwert); geschrieben wird erst am Ende.
    final plan = _DayPlan(await session.values.readDayValues(dayValueKeys));
    final days = <String>{
      for (final r in runs)
        if (runValues.containsKey(r.id) &&
            (from == null || dayOfRun(r).compareTo(from) >= 0))
          dayOfRun(r),
    };
    for (final day in days.toList()..sort()) {
      final values = await _dayValues(
        day: day,
        runs: runs,
        asOf: _asOf(day, runs, now),
        computedAt: now,
        runValues: runValues,
        fallback: profile,
        analysisOf: (r, basis) async =>
            cache[r.id] ??= await _analyzer(basis)
                .analyze(session, r, calculatedAt: now),
      );
      plan.add(day, values.all);
    }
    await session.values.writeAll(create: plan.create, swap: plan.swap);
  }

  /// Die Tage, deren gespeicherte Tageswerte [buildSnapshot] neu rechnet: alle
  /// Tage mit einem beendeten Lauf. Ein Tageswert an einem anderen Tag wird
  /// bei einer Neuberechnung nicht getauscht.
  Future<Set<String>> recalculableDays() async =>
      _daysWithRun(await _finishedRuns());

  static Set<String> _daysWithRun(List<StoredRun> runs) => {
    for (final r in runs) dayOfRun(r),
  };

  /// Rechnet alle Läufe mit gespeichertem Laufwert und deren Tageswerte mit
  /// der aktuellen Profilbasis neu, ohne etwas zu speichern (Zwischenstand der
  /// Neuberechnung). Tageswerte für Tage, die schon einen haben, und für Tage
  /// mit einem Lauf mit Laufwert ([ValueSnapshot.dayCreates]); Tageswerte an
  /// Tagen ohne Lauf entfallen ([ValueSnapshot.removedDays], PAR-237).
  ///
  /// [loadProfile]: das Belastungsprofil, mit dem der TRIMP gerechnet wird
  /// (Wechsel nach Bestätigung, OQ-0053); ohne Angabe das aktive. Ist das
  /// Profil nicht anwendbar, bleiben die gespeicherten TRIMP-Werte
  /// unverändert (kein stiller Wechsel, nichts Unbrauchbares schreiben).
  ///
  /// [coefficients]: die Koeffizienten-Angabe, mit der gerechnet wird (Änderung
  /// nach Bestätigung); ohne Angabe die gespeicherte.
  ///
  /// Speicher: Die Vorverarbeitung eines Laufs wird nur für seine eigenen
  /// Laufwerte gebraucht (Zeit bei hoher Herzfrequenz, TRIMP) und danach
  /// nicht gehalten; die Tageswerte brauchen nur Auswahl und Quellen
  /// ([RunAnalysisCache]). [analyses]: wohin die Analysen gelegt werden (ohne
  /// Angabe ein eigener Zwischenspeicher; Tests prüfen darüber, was gehalten
  /// wird).
  Future<ValueSnapshot> buildSnapshot({
    LoadProfile? loadProfile,
    CoefficientChange? coefficients,
    RunAnalysisCache? analyses,
  }) async {
    final now = clock.now();
    final runs = await _finishedRuns();
    final profile = await _profileBasis();
    final resolution = await loadResolution(
      profile,
      profile: loadProfile,
      coefficients: coefficients,
    );
    final analyzer = _analyzer(profile);
    final cache = analyses ?? RunAnalysisCache();
    // Volle Analyse (mit Vorverarbeitung) nur für den Aufrufer; gehalten wird
    // sie ohne.
    Future<RunAnalysis> analyze(StoredRun r) async {
      final a = await analyzer.analyze(session, r, calculatedAt: now);
      cache.keep(a);
      return a;
    }

    Future<RunAnalysis> analysisOf(StoredRun r, HeartRateBasis _) async =>
        cache[r.id] ?? await analyze(r);

    // Laufwerte aller Läufe in EINER Abfrage (nur die Schlüssel zählen, keine
    // Abschnitte nötig).
    final storedRuns = await session.values.readRunValues({
      ...recalculatedRunValueKeys,
      highHeartRateTimeValueKey,
    });
    final runValues = <int, ComputedValue>{};
    final runOwners = <ValueOwner, List<ComputedValue>>{};
    final runCreates = <ValueOwner, List<ComputedValue>>{};
    for (final r in runs) {
      final stored = storedRuns[r.id]?.keys.toSet() ?? const <String>{};
      if (!hasRecalculatedRunKey(stored)) continue;
      final hasTrimp = stored.contains(trimpRunValueKey);
      // Jeder Lauf kommt hier genau einmal vor, die Tageswerte danach.
      final analysis = await analyze(r);
      final high = buildHighHeartRateTimeValue(
        run: r,
        pre: analysis.preprocessing,
        basis: profile,
        fitness: fitness,
        sources: analysis.sources,
        computedAt: now,
        preprocessingVersion: preprocessingVersion,
        model: highHeartRateTime,
      );
      // Vorhanden: tauschen (hängt an HFmax wie der TRIMP); fehlt er (Lauf
      // von vor dieser Methode): anlegen.
      if (stored.contains(highHeartRateTimeValueKey)) {
        runOwners[ValueOwner.run(r.id)] = [high];
      } else {
        runCreates[ValueOwner.run(r.id)] = [high];
      }
      if (!stored.contains(vo2maxRunValueKey)) {
        // Lauf mit TRIMP, aber ohne Laufwert (VO2max): nur der TRIMP wird
        // getauscht, sonst bliebe er nach einem Profilwechsel im alten Modell
        // und ATL/CTL mischten Skalen (FR-0097, FR-0197).
        final trimp = _trimpSwap(
          r,
          analysis,
          profile,
          resolution,
          now,
          hasTrimp: hasTrimp,
        );
        if (trimp.isNotEmpty) {
          (runOwners[ValueOwner.run(r.id)] ??= []).addAll(trimp);
        }
        continue;
      }
      final value = analysis.vo2maxValue(
        now,
        preprocessingVersion: preprocessingVersion,
      );
      runValues[r.id] = value;
      (runOwners[ValueOwner.run(r.id)] ??= []).addAll([
        value,
        ..._trimpSwap(
          r,
          analysis,
          profile,
          resolution,
          now,
          hasTrimp: hasTrimp,
        ),
      ]);
    }
    final dayOwners = <ValueOwner, List<ComputedValue>>{};
    final dayCreates = <ValueOwner, List<ComputedValue>>{};
    final days = _daysWithRun(runs);
    // Tage mit einem Lauf mit Laufwert: fehlen dort Tageswerte (der Lauf
    // gehörte nach der alten Tageszuordnung einem anderen Tag), werden sie
    // angelegt.
    final daysWithValue = {
      for (final r in runs)
        if (runValues.containsKey(r.id)) dayOfRun(r),
    };
    // Tageswerte aller Tage in EINER Abfrage; alle Tagesschlüssel stehen in
    // [dayValueKeys] (_DayPlan prüft das beim Schreiben).
    final storedDays = await session.values.readDayValues(dayValueKeys);
    for (final day in days.toList()..sort()) {
      final existing = storedDays[day]?.keys.toSet() ?? const <String>{};
      if (existing.isEmpty && !daysWithValue.contains(day)) continue;
      final values = await _dayValues(
        day: day,
        runs: runs,
        asOf: _asOf(day, runs, now),
        computedAt: now,
        runValues: runValues,
        fallback: profile,
        analysisOf: analysisOf,
      );
      final swappable = [
        for (final v in values.all)
          if (existing.contains(v.key)) v,
      ];
      if (swappable.isNotEmpty) dayOwners[ValueOwner.day(day)] = swappable;
      if (existing.isEmpty) dayCreates[ValueOwner.day(day)] = values.all;
    }
    return ValueSnapshot(
      runValues: runOwners,
      dayValues: dayOwners,
      runCreates: runCreates,
      dayCreates: dayCreates,
      removedDays: {
        for (final day in storedDays.keys)
          if (!days.contains(day)) day,
      },
    );
  }

  /// TRIMP des Laufs mit der neuen Basis, wenn der Lauf schon einen gespeicherten
  /// TRIMP hat (FR-0006, OQ-0031: TRIMP hängt an HFmax; `original` bleibt).
  /// Zonenzeiten werden nie neu gerechnet (L11), ein Lauf ohne gespeicherten
  /// TRIMP (vor dieser Entscheidung) bekommt keinen. [hasTrimp]: hat der Lauf
  /// einen gespeicherten TRIMP (auch „nicht verfügbar“)?
  List<ComputedValue> _trimpSwap(
    StoredRun r,
    RunAnalysis analysis,
    HeartRateBasis profile,
    LoadProfileResolution resolution,
    DateTime now, {
    required bool hasTrimp,
  }) {
    if (!hasTrimp || !resolution.applicable) return const [];
    return [
      for (final v in buildRunLoadValues(
        run: r,
        pre: analysis.preprocessing,
        basis: profile,
        fitness: fitness,
        sources: analysis.sources,
        computedAt: now,
        preprocessingVersion: preprocessingVersion,
        loadProfile: resolution,
      ))
        if (v.key == trimpRunValueKey) v,
    ];
  }

  /// Zeitpunkt, für den der Tageswert des lokalen Tages [day] gilt: Ende des
  /// Tages (mit dem Versatz des zuletzt endenden Laufs des Tages; unbekannt:
  /// UTC), bei einem Lauf des Tages über Mitternacht (PAR-237) dessen Ende,
  /// für den heutigen Tag jetzt.
  DateTime _asOf(String day, List<StoredRun> runs, DateTime now) {
    StoredRun? last;
    for (final r in runs) {
      if (dayOfRun(r) != day) continue;
      if (last == null || r.endedAt!.isAfter(last.endedAt!)) last = r;
    }
    final offset = last?.endedUtcOffset ?? Duration.zero;
    var end = DateTime.parse('${day}T00:00:00Z')
        .add(const Duration(days: 1))
        .subtract(offset)
        .subtract(const Duration(microseconds: 1));
    if (last != null && last.endedAt!.isAfter(end)) end = last.endedAt!;
    return end.isAfter(now) ? now : end;
  }

  /// Langzeitwert und aerobe Effizienz des Tages [day] zum Zeitpunkt [asOf].
  /// Es zählen die Läufe aus [runs] bis zu diesem Tag (Tag des Laufs nach
  /// [dayOfRun], PAR-237), ein Lauf über Mitternacht also schon an seinem
  /// Starttag. Die Basis eines Laufs im Fenster ist die an seinem Laufwert in
  /// [runValues] gespeicherte; ohne Laufwert [fallback]; ist sie unbekannt,
  /// entfällt die Effizienz.
  Future<_DayValues> _dayValues({
    required String day,
    required List<StoredRun> runs,
    required DateTime asOf,
    required DateTime computedAt,
    required Map<int, ComputedValue> runValues,
    required HeartRateBasis fallback,
    required Future<RunAnalysis> Function(StoredRun, HeartRateBasis) analysisOf,
  }) async {
    final upToDay = {
      for (final r in runs)
        if (dayOfRun(r).compareTo(day) <= 0) r.id,
    };
    final long = longTerm.compute(
      runs: [
        for (final MapEntry(key: id, value: v) in runValues.entries)
          if (upToDay.contains(id)) ?toAdvancedValue(v),
      ],
      p: fitness,
      now: asOf,
    );
    final longValue = toComputedValue(
      key: vo2maxLongTermValueKey,
      unit: vo2maxUnit,
      value: long,
      computedAt: computedAt,
    );
    final span = fitness.aerobicEfficiency.windowLength * 2;
    final from = asOf.subtract(span);
    final inputs = <EfficiencyRun>[];
    final sources = <String>{};
    final bases = <HeartRateBasis>[];
    var unknown = false;
    for (final r in runs) {
      final end = r.endedAt!;
      if (end.isBefore(from) || !upToDay.contains(r.id)) continue;
      // Nur GPS-Läufe: beim Band ist das Tempo eingestellt, nicht gemessen
      // (FR-0196); eine andere Sportart hat kein Tempo (FR-0221).
      if (r.mode != RunMode.gps) continue;
      final stored = runValues[r.id];
      // Ein Laufwert braucht eine Basis (nach Schlüssel, nicht nach Inhalt):
      // fehlt sie am Wert, ist sie unbekannt und wird nie ersetzt.
      final basis = stored == null
          ? fallback
          : (needsHeartRateBasis(stored.key)
                ? stored.heartRateBasis
                : fallback);
      if (basis == null) {
        unknown = true;
        continue;
      }
      final a = await analysisOf(r, basis);
      bases.add(basis);
      inputs.add(EfficiencyRun(endedAt: end, selection: a.selection));
      sources.addAll(a.sources);
    }
    if (unknown) return _DayValues(longValue, null);
    final eff = efficiency.compute(
      runs: inputs,
      p: fitness,
      now: asOf,
      dataSources: sources,
    );
    return _DayValues(
      longValue,
      toComputedValue(
        key: aerobicEfficiencyValueKey,
        unit: percentUnit,
        value: eff.change,
        computedAt: computedAt,
        heartRateBasis: _common(bases),
      ),
    );
  }

  /// Die gemeinsame Basis, sonst `null`. `null` heißt am Effizienzwert also
  /// „gemischt“ (Läufe mit verschiedenen Basen) und ist dort nicht von
  /// „unbekannt“ (Schema 1) zu unterscheiden. Das ist fürs Rechnen harmlos: Die
  /// Effizienz-Basis wird nie gelesen; eine Neuberechnung nimmt die Basis der
  /// Laufwerte. Für Anzeige und Export bedeutet `null` „gemischt oder
  /// unbekannt“ (OQ-0065).
  static HeartRateBasis? _common(List<HeartRateBasis> bases) {
    if (bases.isEmpty) return null;
    final first = bases.first;
    for (final b in bases) {
      if (b.maxBpm != first.maxBpm ||
          b.restingBpm != first.restingBpm ||
          b.maxIsEstimated != first.maxIsEstimated) {
        return null;
      }
    }
    return first;
  }
}

/// Die Tageswerte eines Tages; die Effizienz kann fehlen.
class _DayValues {
  _DayValues(this.longTerm, this.efficiency);

  final ComputedValue longTerm;
  final ComputedValue? efficiency;

  List<ComputedValue> get all => [longTerm, ?efficiency];
}

/// Sammelt, was zu schreiben ist: je Tag neu anlegen (kein Wert vorhanden)
/// oder tauschen (vorhanden).
///
/// [stored]: die gespeicherten Tageswerte aller Tage aus EINER Sammelabfrage
/// mit [dayValueKeys] (`readDayValues`), gelesen vor dem Schreiben. Ein Tag,
/// der darin fehlt, hat keine Tageswerte; seine Werte werden angelegt.
/// `original` und `current` tragen denselben Schlüssel, und jeder Schlüssel,
/// der hier geschrieben wird, steht in [dayValueKeys] (Prüfung in [add]).
class _DayPlan {
  _DayPlan(this.stored);

  final Map<String, Map<String, ComputedValue>> stored;
  final create = <ValueOwner, List<ComputedValue>>{};
  final swap = <ValueOwner, List<ComputedValue>>{};

  void add(String day, List<ComputedValue> values) {
    assert(
      values.every((v) => dayValueKeys.contains(v.key)),
      'Tagesschlüssel fehlt in dayValueKeys (Export, run_analysis.dart)',
    );
    final owner = ValueOwner.day(day);
    final existing = stored[day]?.keys.toSet() ?? const <String>{};
    final toSwap = [
      for (final v in values)
        if (existing.contains(v.key)) v,
    ];
    final toCreate = [
      for (final v in values)
        if (!existing.contains(v.key)) v,
    ];
    if (toCreate.isNotEmpty) create[owner] = toCreate;
    if (toSwap.isNotEmpty) swap[owner] = toSwap;
  }
}
