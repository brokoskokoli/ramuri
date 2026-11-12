import '../../ports/clock.dart';
import '../../ports/storage.dart';
import '../../ports/storage_runs.dart';
import '../../ports/storage_values.dart';
import '../fitness/aerobic_efficiency.dart';
import '../fitness/fitness_parameters.dart';
import '../fitness/heart_rate_basis.dart';
import '../fitness/load_profile.dart';
import '../fitness/vo2max_long_term.dart';
import '../preprocessing/preprocessing_parameters.dart';
import '../recording/treadmill.dart' show RunMode;
import '../statistics/run_overview.dart' show overviewOf;
import '../profile/heart_rate_resolution.dart';
import '../settings/load_settings.dart';
import '../settings/reserve_zone_settings.dart';
import 'run_analysis.dart';
import '../subjective/subjective_service.dart' show refreshSrpe;
import 'run_load_values.dart';

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
class ValueSnapshot {
  const ValueSnapshot({required this.runValues, required this.dayValues});

  final Map<ValueOwner, List<ComputedValue>> runValues;
  final Map<ValueOwner, List<ComputedValue>> dayValues;
}

/// ISO-Datum (UTC) `JJJJ-MM-TT` eines Zeitpunkts.
String isoDay(DateTime t) {
  final u = t.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${u.year.toString().padLeft(4, '0')}-${two(u.month)}-${two(u.day)}';
}

/// Besitzertag der Tageswerte eines Laufs: der LOKALE Kalendertag des
/// Laufendes, also `endedAt + endedUtcOffset`. Fehlt der Versatz (alter Lauf,
/// unbekannt), gilt der UTC-Tag. Die EINE Stelle für Speichern, Neuberechnung
/// und Löschen.
String dayOfRun(StoredRun run) =>
    isoDay(run.endedAt!.toUtc().add(run.endedUtcOffset ?? Duration.zero));

/// Rechnet VO₂max-Laufwert, Langzeitwert und aerobe Effizienz aus den
/// gespeicherten Rohdaten (FR-0066 bis FR-0087), dazu die Laufwerte für Zonen
/// und TRIMP ([buildRunLoadValues]), und speichert sie als
/// `original` und `current` mit den Angaben aus FR-0053, den bewerteten
/// Abschnitten (FR-0073) und der verwendeten Herzfrequenzbasis (OQ-0065).
/// Netzwerkfrei (SEC-0006), Zeit nur über [Clock].
///
/// Tageswerte (Langzeitwert, aerobe Effizienz) gehören dem lokalen
/// Kalendertag des Laufendes ([dayOfRun]); sie gelten für das Ende dieses
/// Tages (mit dem Versatz des zuletzt endenden Laufs des Tages), für den
/// heutigen Tag für jetzt. Gibt es für den Tag schon einen Wert, wird sein
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
    this.fitness = const FitnessParameters.v4(),
    this.preprocessing = const PreprocessingParameters.v4(),
    this.longTerm = const SmoothedVo2maxLongTerm(),
    this.efficiency = const MedianAerobicEfficiency(),
  });

  final StorageSession session;
  final Clock clock;
  final FitnessParameters fitness;
  final PreprocessingParameters preprocessing;
  final Vo2maxLongTerm longTerm;
  final AerobicEfficiency efficiency;

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

  RunAnalyzer _analyzer(HeartRateBasis basis) =>
      RunAnalyzer(fitness: fitness, preprocessing: preprocessing, basis: basis);

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
  Future<RunCalculationResult> calculateAfterRun(int runId) async {
    final now = clock.now();
    final run = await session.runs.get(runId);
    if (run == null) throw const StorageException(StorageFailure.notFound);
    final profile = await _profileBasis();
    final analysis = await _analyzer(profile)
        .analyze(session, run, calculatedAt: now);
    final runValue = analysis.vo2maxValue(now);

    final runs = await _finishedRuns();
    final runValues = <int, ComputedValue>{runId: runValue};
    for (final other in runs) {
      if (other.id == runId) continue;
      final stored = await _runValue(other.id);
      if (stored != null) runValues[other.id] = stored.current;
    }
    final day = dayOfRun(run);
    final cache = <int, RunAnalysis>{runId: analysis};
    final values = await _dayValues(
      asOf: _asOf(day, runs, now),
      computedAt: now,
      runValues: runValues,
      fallback: profile,
      analysisOf: (r, basis) async =>
          cache[r.id] ??= await _analyzer(basis)
              .analyze(session, r, calculatedAt: now),
    );
    final plan = _DayPlan();
    await plan.add(session, day, values.all);
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
      loadProfile: await loadResolution(profile),
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
        ),
      );
      // Angaben zum Lauf, die schon vor der Berechnung gemacht wurden: sRPE
      // folgt der jetzt bekannten Bewegungszeit.
      await refreshSrpe(session, runId);
    }
    await session.values.writeAll(
      create: {
        ValueOwner.run(runId): [runValue, ...loadValues],
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

  /// Rechnet beim Start alle beendeten Läufe ohne Laufwert nach, gemerkte oder
  /// nicht: [calculateAfterRun] schreibt immer einen Laufwert (notfalls „nicht
  /// bestimmbar“ mit Grund), ein beendeter Lauf ohne Laufwert ist also offen,
  /// auch wenn der Merker fehlt (Schreibfehler im Lauf, App-Ende vor dem
  /// Merken). Gemerkte, gelöschte Läufe und Läufe mit Laufwert werden nur
  /// ausgetragen; ein Lauf, dessen Werte nicht gelesen werden konnten, bleibt
  /// gemerkt. Der erste Fehler wird nach den übrigen Läufen weitergegeben;
  /// die betroffenen Einträge bleiben.
  Future<void> completePendingCalculations() async {
    Object? failure;
    final marked = await _pendingCalculations();
    final open = <int>{};
    final unread = <int>{};
    for (final r in await _finishedRuns()) {
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
    for (final id in ({...marked, ...open}).toList()..sort()) {
      try {
        if (open.contains(id)) await calculateAfterRun(id);
        if (marked.contains(id) && !unread.contains(id)) await _unmark(id);
      } on Object catch (e) {
        failure ??= e;
      }
    }
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
  Future<void> refreshAfterDelete() async {
    final now = clock.now();
    final runs = await _finishedRuns();
    final runValues = <int, ComputedValue>{};
    for (final r in runs) {
      final stored = await _runValue(r.id);
      if (stored != null) runValues[r.id] = stored.current;
    }
    if (runValues.isEmpty) return;
    final profile = await _profileBasis();
    final cache = <int, RunAnalysis>{};
    final plan = _DayPlan();
    final days = <String>{
      for (final r in runs)
        if (runValues.containsKey(r.id)) dayOfRun(r),
    };
    for (final day in days.toList()..sort()) {
      final values = await _dayValues(
        asOf: _asOf(day, runs, now),
        computedAt: now,
        runValues: runValues,
        fallback: profile,
        analysisOf: (r, basis) async =>
            cache[r.id] ??= await _analyzer(basis)
                .analyze(session, r, calculatedAt: now),
      );
      await plan.add(session, day, values.all);
    }
    await session.values.writeAll(create: plan.create, swap: plan.swap);
  }

  /// Rechnet alle Läufe mit gespeichertem Laufwert und deren Tageswerte mit
  /// der aktuellen Profilbasis neu, ohne etwas zu speichern (Zwischenstand der
  /// Neuberechnung). Tageswerte nur für Tage, die schon einen haben.
  ///
  /// [loadProfile]: das Belastungsprofil, mit dem der TRIMP gerechnet wird
  /// (Wechsel nach Bestätigung, OQ-0053); ohne Angabe das aktive. Ist das
  /// Profil nicht anwendbar, bleiben die gespeicherten TRIMP-Werte
  /// unverändert (kein stiller Wechsel, nichts Unbrauchbares schreiben).
  ///
  /// [coefficients]: die Koeffizienten-Angabe, mit der gerechnet wird (Änderung
  /// nach Bestätigung); ohne Angabe die gespeicherte.
  Future<ValueSnapshot> buildSnapshot({
    LoadProfile? loadProfile,
    CoefficientChange? coefficients,
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
    final cache = <int, RunAnalysis>{};
    Future<RunAnalysis> analysisOf(StoredRun r, HeartRateBasis _) async =>
        cache[r.id] ??= await analyzer.analyze(session, r, calculatedAt: now);

    final runValues = <int, ComputedValue>{};
    final runOwners = <ValueOwner, List<ComputedValue>>{};
    for (final r in runs) {
      if (await _runValue(r.id) == null) {
        // Lauf mit TRIMP, aber ohne Laufwert (VO2max): nur der TRIMP wird
        // getauscht, sonst bliebe er nach einem Profilwechsel im alten Modell
        // und ATL/CTL mischten Skalen (FR-0097, FR-0197).
        if (!await _hasTrimp(r.id)) continue;
        final trimp = await _trimpSwap(
          r,
          await analysisOf(r, profile),
          profile,
          resolution,
          now,
        );
        if (trimp.isNotEmpty) runOwners[ValueOwner.run(r.id)] = trimp;
        continue;
      }
      final analysis = await analysisOf(r, profile);
      final value = analysis.vo2maxValue(now);
      runValues[r.id] = value;
      runOwners[ValueOwner.run(r.id)] = [
        value,
        ...await _trimpSwap(r, analysis, profile, resolution, now),
      ];
    }
    final dayOwners = <ValueOwner, List<ComputedValue>>{};
    final days = <String>{for (final r in runs) dayOfRun(r)};
    for (final day in days.toList()..sort()) {
      final existing = {
        for (final p in await session.values.read(ValueOwner.day(day)))
          p.original.key,
      };
      if (existing.isEmpty) continue;
      final values = await _dayValues(
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
    }
    return ValueSnapshot(runValues: runOwners, dayValues: dayOwners);
  }

  /// TRIMP des Laufs mit der neuen Basis, wenn der Lauf schon einen gespeicherten
  /// TRIMP hat (FR-0006, OQ-0031: TRIMP hängt an HFmax; `original` bleibt).
  /// Zonenzeiten werden nie neu gerechnet (L11), ein Lauf ohne gespeicherten
  /// TRIMP (vor dieser Entscheidung) bekommt keinen.
  Future<List<ComputedValue>> _trimpSwap(
    StoredRun r,
    RunAnalysis analysis,
    HeartRateBasis profile,
    LoadProfileResolution resolution,
    DateTime now,
  ) async {
    if (!await _hasTrimp(r.id) || !resolution.applicable) return const [];
    return [
      for (final v in buildRunLoadValues(
        run: r,
        pre: analysis.preprocessing,
        basis: profile,
        fitness: fitness,
        sources: analysis.sources,
        computedAt: now,
        loadProfile: resolution,
      ))
        if (v.key == trimpRunValueKey) v,
    ];
  }

  /// Zeitpunkt, für den der Tageswert des lokalen Tages [day] gilt: Ende des
  /// Tages (mit dem Versatz des zuletzt endenden Laufs des Tages; unbekannt:
  /// UTC), für den heutigen Tag jetzt.
  DateTime _asOf(String day, List<StoredRun> runs, DateTime now) {
    StoredRun? last;
    for (final r in runs) {
      if (dayOfRun(r) != day) continue;
      if (last == null || r.endedAt!.isAfter(last.endedAt!)) last = r;
    }
    final offset = last?.endedUtcOffset ?? Duration.zero;
    final end = DateTime.parse('${day}T00:00:00Z')
        .add(const Duration(days: 1))
        .subtract(offset)
        .subtract(const Duration(microseconds: 1));
    return end.isAfter(now) ? now : end;
  }

  /// Hat der Lauf einen gespeicherten TRIMP (auch „nicht verfügbar“)?
  Future<bool> _hasTrimp(int runId) async =>
      (await session.values.read(ValueOwner.run(runId)))
          .any((p) => p.original.key == trimpRunValueKey);

  Future<ValuePair?> _runValue(int runId) async {
    for (final p in await session.values.read(ValueOwner.run(runId))) {
      if (p.original.key == vo2maxRunValueKey) return p;
    }
    return null;
  }

  /// Langzeitwert und aerobe Effizienz zum Zeitpunkt [asOf]. Die Basis eines
  /// Laufs im Fenster ist die an seinem Laufwert in [runValues] gespeicherte;
  /// ohne Laufwert [fallback]; ist sie unbekannt, entfällt die Effizienz.
  Future<_DayValues> _dayValues({
    required DateTime asOf,
    required DateTime computedAt,
    required Map<int, ComputedValue> runValues,
    required HeartRateBasis fallback,
    required Future<RunAnalysis> Function(StoredRun, HeartRateBasis) analysisOf,
  }) async {
    final long = longTerm.compute(
      runs: [for (final v in runValues.values) ?toAdvancedValue(v)],
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
    for (final r in await _finishedRuns()) {
      final end = r.endedAt!;
      if (end.isBefore(from) || end.isAfter(asOf)) continue;
      // Bandläufe nicht: das Tempo ist eingestellt, nicht gemessen (FR-0196).
      if (r.mode == RunMode.treadmill) continue;
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
class _DayPlan {
  final create = <ValueOwner, List<ComputedValue>>{};
  final swap = <ValueOwner, List<ComputedValue>>{};

  Future<void> add(
    StorageSession session,
    String day,
    List<ComputedValue> values,
  ) async {
    final owner = ValueOwner.day(day);
    final existing = {
      for (final p in await session.values.read(owner)) p.original.key,
    };
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
