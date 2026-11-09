import 'dart:async';

import '../../ports/clock.dart';
import '../../ports/storage.dart';
import '../../ports/storage_profile.dart';
import '../../ports/storage_runs.dart';
import '../../ports/storage_values.dart';
import '../fitness/banister_trimp.dart';
import '../fitness/edwards_trimp.dart';
import '../fitness/load_profile.dart';
import '../fitness/vo2max_estimator.dart';
import '../profile/heart_rate_resolution.dart';
import '../settings/load_settings.dart';
import 'run_analysis.dart';
import 'run_load_values.dart';
import 'value_calculation_service.dart';

/// Warum eine Neuberechnung angeboten wird (FR-0006, FR-0058).
enum RecalculationCause {
  /// HFmax oder Ruhepuls (oder deren Schätzung) haben sich geändert.
  heartRateBasis,

  /// Parameter- oder Methodenversion der gespeicherten Werte weicht von der
  /// der App ab (Änderung des Algorithmus).
  algorithmVersion,

  /// Wechsel des Belastungsprofils (FR-0197, OQ-0053): das gewählte Profil
  /// ([RecalculationOffer.loadProfile]) gilt erst nach Bestätigung. Dieselbe
  /// Ursache bietet auch den Rückweg auf Edwards an, wenn bei aktivem Banister
  /// Ruhepuls oder Koeffizienten wegfallen.
  loadProfile,

  /// Der berechnete persönliche Faktor TRIMP/sRPE weicht mehr als 25 % vom
  /// angewandten ab (PAR-087, FR-0199): [RecalculationOffer.personalFactor]
  /// gilt erst nach Bestätigung. Ablehnen lässt den alten Faktor. Ändert keine
  /// gespeicherten Werte (der Faktor geht erst in den Belastungsverlauf ein).
  personalFactor,

  /// Änderung der Koeffizienten-Angabe bei aktivem Banister (FR-0002,
  /// FR-0197): die neue Angabe gilt erst nach Bestätigung, wie der
  /// Profilwechsel. Bis dahin rechnen neue Läufe mit der alten Angabe, der
  /// Verlauf bleibt auf einer Skala; Ablehnen lässt die alte Angabe.
  loadCoefficients,
}

/// Das gewählte Belastungsprofil ist nicht anwendbar (Ruhepuls oder
/// Koeffizienten-Angabe fehlen). Es wurde nichts geändert.
class LoadProfileNotApplicableException implements Exception {
  const LoadProfileNotApplicableException(this.profile, this.issues);

  final LoadProfile profile;
  final List<LoadProfileIssue> issues;

  @override
  String toString() => 'LoadProfileNotApplicableException($profile, $issues)';
}

/// Angebot einer Neuberechnung. Es ändert nichts, bis es bestätigt wird.
class RecalculationOffer {
  RecalculationOffer({
    required Set<RecalculationCause> causes,
    required List<int> runIds,
    this.loadProfile,
    this.personalFactor,
  }) : causes = Set.unmodifiable(causes),
       runIds = List.unmodifiable(runIds);

  final Set<RecalculationCause> causes;

  /// Läufe mit gespeichertem VO₂max-Laufwert, deren `current` neu gerechnet
  /// würde.
  final List<int> runIds;

  /// Das gewählte, noch nicht aktive Belastungsprofil bei der Ursache
  /// [RecalculationCause.loadProfile]; sonst `null`.
  final LoadProfile? loadProfile;

  /// Der angebotene neue Faktor bei [RecalculationCause.personalFactor].
  final LoadFactorRecord? personalFactor;
}

/// Ergebnis einer bestätigten Neuberechnung.
class RecalculationResult {
  const RecalculationResult({
    required this.runCount,
    required this.dayCount,
    this.offerCleared = true,
  });

  final int runCount;
  final int dayCount;

  /// `false`: Die Werte sind getauscht, aber das Angebot konnte danach nicht
  /// als erledigt gespeichert werden (Speicherfehler). Die Neuberechnung
  /// gilt; das Angebot kann bestehen bleiben, ein erneutes Bestätigen rechnet
  /// aus den Rohdaten dieselben Werte (nur `computedAt` ändert sich).
  final bool offerCleared;
}

/// Neuberechnung nach einer Änderung der Basis (ADR-0004 Punkt 5, FR-0006,
/// FR-0058, OQ-0031). Ablauf:
///
/// 1. [profileChanged] oder [checkVersions] melden eine Änderung und liefern
///    ein [RecalculationOffer] (auch über [offers]); es steht in den
///    Einstellungen und überlebt einen Neustart ([pendingOffer]).
/// 2. Nur [confirm] startet. Es rechnet alles in einen Zwischenstand und
///    tauscht ihn mit `swapCurrentAll` in einer Transaktion; `original` und
///    Rohdaten bleiben. Scheitert etwas, bleibt der alte Stand ganz.
/// 3. [decline] verwirft das Angebot und ändert keine Werte (alte Läufe
///    ändern sich nie still, OQ-0065).
///
/// Zonenzeiten und TRIMP sind Laufwerte, die nach dem Lauf einmal gespeichert
/// werden ([buildRunLoadValues]). Die Zonenzeiten fasst die Neuberechnung nie
/// an (L11, FR-0061, OQ-0065). TRIMP hängt an HFmax: Er wird bei einer Änderung
/// der Basis wie der VO₂max-Laufwert im `current` neu gerechnet (nur für Läufe
/// mit gespeichertem TRIMP; `original` bleibt).
class RecalculationService {
  RecalculationService({
    required this.session,
    required this.clock,
    required ValueCalculationService calculation,
  }) : _calc = calculation;

  /// Einstellungsschlüssel des offenen Angebots (Ursachen, durch Komma
  /// getrennt; leer = keines).
  static const String pendingKey = 'recalculation.pending';

  final StorageSession session;
  final Clock clock;
  final ValueCalculationService _calc;
  final _controller = StreamController<RecalculationOffer>.broadcast();

  /// Wie oft eine Ursache angeboten wurde; zeigt, ob während einer laufenden
  /// Bestätigung ein neues Angebot dazukam.
  ///
  /// Der Zähler lebt nur in dieser Instanz. Vorausgesetzt ist genau EINE
  /// Instanz je Sitzung (die App erfüllt das als Singleton der
  /// Abhängigkeitsinjektion) und dass Anbieten, Bestätigen und Ablehnen nicht
  /// gleichzeitig laufen. Zwischen Lesen ([_pendingCauses]) und Speichern
  /// ([_setPending]) der offenen Ursachen liegt eine Lücke: eine zweite
  /// Instanz oder ein paralleler Aufruf könnte ein Angebot dazwischen
  /// verlieren.
  final _offerSeq = <RecalculationCause, int>{};

  /// Ereignis „Neuberechnung angeboten“.
  Stream<RecalculationOffer> get offers => _controller.stream;

  Future<void> dispose() => _controller.close();

  /// Das offene Angebot, falls eines besteht (Abfrage).
  Future<RecalculationOffer?> pendingOffer() async {
    final causes = await _pendingCauses();
    if (causes.isEmpty) return null;
    return RecalculationOffer(
      causes: causes,
      runIds: await _affectedRuns(),
      loadProfile: await _pendingLoadProfile(causes),
      personalFactor: await _pendingFactor(causes),
    );
  }

  /// Das Profil wurde von [before] auf [after] geändert (nach dem Speichern).
  /// Ein Angebot gibt es nur, wenn sich die Herzfrequenzbasis geändert hat
  /// und Läufe mit Werten betroffen sind.
  Future<RecalculationOffer?> profileChanged({
    required ProfileRecord before,
    required ProfileRecord after,
  }) async {
    final year = clock.now().year;
    final a = resolveHeartRate(before, currentYear: year).basis;
    final b = resolveHeartRate(after, currentYear: year).basis;
    final same =
        a.maxBpm == b.maxBpm &&
        a.restingBpm == b.restingBpm &&
        a.maxIsEstimated == b.maxIsEstimated;
    if (same) return _offerLoadRevert();
    final offer = await _offer(RecalculationCause.heartRateBasis);
    // Fällt dabei der Ruhepuls weg, während Banister aktiv ist, kommt der
    // Rückweg auf Edwards als weitere Ursache dazu.
    return await _offerLoadRevert() ?? offer;
  }

  /// Wählt das Belastungsprofil [target] (FR-0197). Es gilt erst nach
  /// [confirm]; bis dahin bleibt das aktive Profil und es ändert sich nichts
  /// an den Werten. Banister nur anwendbar mit Ruhepuls und Koeffizienten,
  /// sonst [LoadProfileNotApplicableException]. Ist [target] das aktive
  /// Profil, verfällt eine offene Wahl. Gibt es keine Läufe mit Werten, wird
  /// sofort gewechselt (nichts zu rechnen) und es gibt kein Angebot.
  Future<RecalculationOffer?> requestLoadProfile(LoadProfile target) async {
    final active = await LoadSettings.activeProfile(session.settings);
    if (target == active) {
      await _dropLoadChoice();
      return null;
    }
    final resolution = await _calc.loadResolution(
      await _calc.profileBasis(),
      profile: target,
    );
    if (!resolution.applicable) {
      throw LoadProfileNotApplicableException(target, resolution.issues);
    }
    await LoadSettings.writePendingProfile(
      session.settings,
      target,
      at: clock.now(),
    );
    final offer = await _offer(RecalculationCause.loadProfile);
    if (offer == null) {
      await LoadSettings.writeActiveProfile(
        session.settings,
        target,
        at: clock.now(),
      );
      await LoadSettings.writePendingProfile(
        session.settings,
        null,
        at: clock.now(),
      );
    }
    return offer;
  }

  /// Nach einer Änderung des Ruhepulses aufrufen (die Koeffizienten-Angabe
  /// ändert [requestLoadCoefficients]). Ist Banister aktiv und nicht mehr
  /// anwendbar, gibt es keinen stillen Wechsel der Skala: Die App bietet den
  /// Rückweg auf Edwards an (Ursache [RecalculationCause.loadProfile]); lehnt
  /// der Nutzer ab, bleibt Banister gewählt und der TRIMP neuer Läufe steht
  /// als nicht verfügbar, gespeicherte Werte bleiben. Ist Banister weiter
  /// anwendbar, aber mit anderen Konstanten gerechnet, erkennt [checkVersions]
  /// die Abweichung.
  Future<RecalculationOffer?> loadBasisChanged() async =>
      await _offerLoadRevert() ?? await checkVersions();

  /// Ändert die Koeffizienten-Angabe auf [value] (`null` entfernt sie). Ist
  /// Banister aktiv, gilt die neue Angabe erst nach [confirm] (wie der
  /// Profilwechsel); bis dahin rechnet alles mit der alten und Ablehnen lässt
  /// sie bestehen. Das Entfernen bietet zugleich den Rückweg auf Edwards an
  /// (Ursache [RecalculationCause.loadProfile]). Ohne aktives Banister, bei
  /// unveränderter Angabe oder ohne Läufe mit Werten gilt die Angabe sofort
  /// und es gibt kein Angebot. Ist Banister mit der neuen Angabe nicht
  /// anwendbar, [LoadProfileNotApplicableException] und nichts geändert.
  Future<RecalculationOffer?> requestLoadCoefficients(
    LoadCoefficients? value,
  ) async {
    final store = session.settings;
    final current = await LoadSettings.coefficients(store);
    final active = await LoadSettings.activeProfile(store);
    if (value == current || active != LoadProfile.banister) {
      await _dropCoefficientChange();
      if (value != current) {
        await LoadSettings.writeCoefficients(store, value, at: clock.now());
      }
      return null;
    }
    final change = CoefficientChange(value);
    if (value != null) {
      final resolution = await _calc.loadResolution(
        await _calc.profileBasis(),
        coefficients: change,
      );
      if (!resolution.applicable) {
        throw LoadProfileNotApplicableException(active, resolution.issues);
      }
    }
    await LoadSettings.writePendingCoefficients(store, change, at: clock.now());
    if (value == null) {
      await LoadSettings.writePendingProfile(
        store,
        LoadProfile.edwards,
        at: clock.now(),
      );
    }
    final offer = await _offerCauses({
      RecalculationCause.loadCoefficients,
      if (value == null) RecalculationCause.loadProfile,
    });
    if (offer == null) {
      // Nichts umzurechnen: sofort wechseln.
      if (value == null) {
        await LoadSettings.writeActiveProfile(
          store,
          LoadProfile.edwards,
          at: clock.now(),
        );
        await _dropLoadChoice();
      }
      await LoadSettings.writeCoefficients(store, value, at: clock.now());
      await _dropCoefficientChange();
    }
    return offer;
  }

  /// Entfernt eine offene Änderung der Koeffizienten-Angabe samt Ursache. War
  /// es das Entfernen, fällt auch der dazu angebotene Rückweg auf Edwards weg.
  Future<void> _dropCoefficientChange() async {
    final pending = await LoadSettings.pendingCoefficients(session.settings);
    if (pending == null) return;
    await LoadSettings.writePendingCoefficients(
      session.settings,
      null,
      at: clock.now(),
    );
    final causes = await _pendingCauses();
    if (causes.remove(RecalculationCause.loadCoefficients)) {
      await _setPending(causes);
    }
    if (pending.value == null &&
        await LoadSettings.pendingProfile(session.settings) ==
            LoadProfile.edwards) {
      await _dropLoadChoice();
    }
  }

  /// Bietet den Rückweg auf Edwards an, wenn Banister aktiv und nicht mehr
  /// anwendbar ist; sonst `null`.
  Future<RecalculationOffer?> _offerLoadRevert() async {
    final active = await LoadSettings.activeProfile(session.settings);
    if (active == LoadProfile.banister) {
      final resolution = await _calc.loadResolution(await _calc.profileBasis());
      if (!resolution.applicable) {
        await LoadSettings.writePendingProfile(
          session.settings,
          LoadProfile.edwards,
          at: clock.now(),
        );
        final offer = await _offer(RecalculationCause.loadProfile);
        if (offer == null) await _dropLoadChoice();
        return offer;
      }
    }
    return null;
  }

  /// Bietet den neuen persönlichen Faktor [fresh] an (Ursache
  /// [RecalculationCause.personalFactor]). Anders als die anderen Ursachen
  /// braucht das keine betroffenen Läufe: es ändert keine gespeicherten Werte.
  Future<RecalculationOffer> requestPersonalFactor(
    LoadFactorRecord fresh,
  ) async {
    await LoadSettings.writePendingFactor(
      session.settings,
      fresh,
      at: clock.now(),
    );
    _offerSeq[RecalculationCause.personalFactor] =
        (_offerSeq[RecalculationCause.personalFactor] ?? 0) + 1;
    final causes = {
      ...await _pendingCauses(),
      RecalculationCause.personalFactor,
    };
    await _setPending(causes);
    final offer = RecalculationOffer(
      causes: causes,
      runIds: await _affectedRuns(),
      loadProfile: await _pendingLoadProfile(causes),
      personalFactor: fresh,
    );
    _controller.add(offer);
    return offer;
  }

  /// Nimmt ein offenes Faktor-Angebot zurück (der Faktor ist wieder innerhalb
  /// der Toleranz, nicht mehr berechenbar oder gehört zu einem anderen
  /// Profil). Merkt sich nichts als abgelehnt.
  Future<void> withdrawPersonalFactor() async {
    await LoadSettings.writePendingFactor(
      session.settings,
      null,
      at: clock.now(),
    );
    final causes = await _pendingCauses();
    if (causes.remove(RecalculationCause.personalFactor)) {
      await _setPending(causes);
    }
  }

  Future<LoadFactorRecord?> _pendingFactor(
    Set<RecalculationCause> causes,
  ) async => causes.contains(RecalculationCause.personalFactor)
      ? LoadSettings.pendingFactor(session.settings)
      : null;

  /// Entfernt eine offene Profilwahl samt Ursache.
  Future<void> _dropLoadChoice() async {
    await LoadSettings.writePendingProfile(
      session.settings,
      null,
      at: clock.now(),
    );
    final causes = await _pendingCauses();
    if (causes.remove(RecalculationCause.loadProfile)) {
      await _setPending(causes);
    }
  }

  Future<LoadProfile?> _pendingLoadProfile(
    Set<RecalculationCause> causes,
  ) async => causes.contains(RecalculationCause.loadProfile)
      ? LoadSettings.pendingProfile(session.settings)
      : null;

  /// Prüft, ob gespeicherte Laufwerte mit einer anderen Parameter- oder
  /// Methodenversion gerechnet sind als die App sie jetzt verwendet: VO2max
  /// und TRIMP (die Basis ändert sich mit dem Profil, das Ergebnis mit der
  /// Methode). Zonenzeiten gehören bewusst nicht dazu: sie werden nie neu
  /// gerechnet (L11), das Angebot käme nach jeder Bestätigung wieder.
  Future<RecalculationOffer?> checkVersions() async {
    const estimator = AcsmReserveVo2maxEstimator();
    // TRIMP-Modell des aktiven Belastungsprofils; nicht anwendbar: nicht
    // vergleichen (die Rückweg-Ursache deckt das ab, [loadBasisChanged]).
    final resolution = await _calc.loadResolution(await _calc.profileBasis());
    final LoadModel? trimp = resolution.model;
    for (final r in await session.runs.list()) {
      for (final p in await session.values.read(ValueOwner.run(r.id))) {
        final c = p.current;
        final (method, version) = switch (p.original.key) {
          vo2maxRunValueKey => (estimator.method, estimator.methodVersion),
          trimpRunValueKey when trimp != null => (
            trimp.method,
            trimp.methodVersion,
          ),
          _ => (null, 0),
        };
        if (method == null) continue;
        if (c.parameterVersion != _calc.fitness.parameterVersion ||
            c.method != method ||
            c.methodVersion != version) {
          return _offer(RecalculationCause.algorithmVersion);
        }
      }
    }
    return null;
  }

  /// Startet die Neuberechnung. Nur mit einem offenen Angebot; sonst
  /// [StateError]. Rechnet zuerst alles (Fehler dabei ändern nichts) und
  /// tauscht dann in einer Transaktion. Erst nach Erfolg gilt das Angebot als
  /// erledigt, und zwar nur die Ursachen, die beim Start offen waren; ein
  /// währenddessen neu gekommenes Angebot bleibt. Scheitert nur das Erledigen
  /// nach dem Tausch, wirft [confirm] nicht; das Ergebnis trägt dann
  /// `offerCleared: false`.
  Future<RecalculationResult> confirm(RecalculationOffer offer) async {
    final started = await _pendingCauses();
    if (started.isEmpty) {
      throw StateError('Es ist keine Neuberechnung angeboten.');
    }
    final seqAtStart = Map.of(_offerSeq);
    // Die Wahl gilt erst jetzt. Ist sie nicht mehr anwendbar, bricht confirm
    // ab, bevor etwas geändert wird; der Nutzer kann ablehnen.
    final target = started.contains(RecalculationCause.loadProfile)
        ? await LoadSettings.pendingProfile(session.settings)
        : null;
    final change = started.contains(RecalculationCause.loadCoefficients)
        ? await LoadSettings.pendingCoefficients(session.settings)
        : null;
    if (target != null || change != null) {
      final resolution = await _calc.loadResolution(
        await _calc.profileBasis(),
        profile: target,
        coefficients: change,
      );
      if (!resolution.applicable) {
        throw LoadProfileNotApplicableException(
          resolution.profile,
          resolution.issues,
        );
      }
    }
    // Nur der Faktor: es gibt nichts neu zu rechnen.
    final factorOnly =
        started.length == 1 &&
        started.contains(RecalculationCause.personalFactor);
    final snapshot = factorOnly
        ? const ValueSnapshot(runValues: {}, dayValues: {})
        : await _calc.buildSnapshot(loadProfile: target, coefficients: change);
    if (!factorOnly) {
      await session.values.swapCurrentAll({
        ...snapshot.runValues,
        ...snapshot.dayValues,
      });
    }
    // Ab hier ist getauscht: ein Fehler beim Erledigen des Angebots darf nicht
    // als gescheiterte Neuberechnung gemeldet werden.
    var cleared = true;
    try {
      // Nur erledigen, was beim Start offen war und währenddessen nicht erneut
      // angeboten wurde; ein neues Angebot (etwa nach einer Profiländerung
      // zwischen Zwischenstand und Tausch) bleibt stehen.
      final done = {
        for (final c in started)
          if (_offerSeq[c] == seqAtStart[c]) c,
      };
      if (done.contains(RecalculationCause.loadProfile)) {
        if (target != null) {
          await LoadSettings.writeActiveProfile(
            session.settings,
            target,
            at: clock.now(),
          );
        }
        await LoadSettings.writePendingProfile(
          session.settings,
          null,
          at: clock.now(),
        );
      }
      if (done.contains(RecalculationCause.loadCoefficients)) {
        // Erst nach dem Profil: bricht das Schreiben hier ab, ist nur die
        // alte Angabe geblieben, nie ein Banister ohne Angabe.
        if (change != null) {
          await LoadSettings.writeCoefficients(
            session.settings,
            change.value,
            at: clock.now(),
          );
        }
        await LoadSettings.writePendingCoefficients(
          session.settings,
          null,
          at: clock.now(),
        );
      }
      if (done.contains(RecalculationCause.personalFactor)) {
        // Der Faktor gilt nur für das (jetzt) aktive Profil.
        final offered = await LoadSettings.pendingFactor(session.settings);
        final active = await LoadSettings.activeProfile(session.settings);
        if (offered != null && offered.profile == active) {
          await LoadSettings.writeFactor(
            session.settings,
            offered,
            at: clock.now(),
          );
        }
        await LoadSettings.writePendingFactor(
          session.settings,
          null,
          at: clock.now(),
        );
      }
      await _setPending((await _pendingCauses()).difference(done));
    } on Object {
      cleared = false;
    }
    return RecalculationResult(
      runCount: snapshot.runValues.length,
      dayCount: snapshot.dayValues.length,
      offerCleared: cleared,
    );
  }

  /// Lehnt das Angebot ab: Werte, Rohdaten und Profil bleiben unverändert.
  /// Eine offene Profilwahl verfällt (OQ-0053): das aktive Profil bleibt.
  Future<void> decline(RecalculationOffer offer) async {
    // Ein abgelehnter Faktor wird nicht bei jedem Laden erneut angeboten.
    final offered = await LoadSettings.pendingFactor(session.settings);
    if (offered != null) {
      await LoadSettings.writeDeclinedFactor(
        session.settings,
        offered,
        at: clock.now(),
      );
      await LoadSettings.writePendingFactor(
        session.settings,
        null,
        at: clock.now(),
      );
    }
    await _setPending(const {});
    await LoadSettings.writePendingProfile(
      session.settings,
      null,
      at: clock.now(),
    );
    await LoadSettings.writePendingCoefficients(
      session.settings,
      null,
      at: clock.now(),
    );
  }

  Future<RecalculationOffer?> _offer(RecalculationCause cause) =>
      _offerCauses({cause});

  Future<RecalculationOffer?> _offerCauses(
    Set<RecalculationCause> added,
  ) async {
    final runs = await _affectedRuns();
    if (runs.isEmpty) return null;
    for (final cause in added) {
      _offerSeq[cause] = (_offerSeq[cause] ?? 0) + 1;
    }
    final causes = {...await _pendingCauses(), ...added};
    await _setPending(causes);
    final offer = RecalculationOffer(
      causes: causes,
      runIds: runs,
      loadProfile: await _pendingLoadProfile(causes),
      personalFactor: await _pendingFactor(causes),
    );
    _controller.add(offer);
    return offer;
  }

  Future<List<int>> _affectedRuns() async => [
    for (final r in await session.runs.list())
      if (r.state == RunState.finished && r.endedAt != null)
        // Laufwert (VO2max) ODER TRIMP: ein Lauf nur mit TRIMP wechselt beim
        // Profilwechsel mit, `buildSnapshot` tauscht dann nur den TRIMP.
        if ((await session.values.read(ValueOwner.run(r.id))).any(
          (p) =>
              p.original.key == vo2maxRunValueKey ||
              p.original.key == trimpRunValueKey,
        ))
          r.id,
  ];

  Future<Set<RecalculationCause>> _pendingCauses() async {
    final raw = await session.settings.get(pendingKey) ?? '';
    return {
      for (final n in raw.split(','))
        for (final c in RecalculationCause.values)
          if (c.name == n) c,
    };
  }

  Future<void> _setPending(Set<RecalculationCause> causes) =>
      session.settings.set(
        pendingKey,
        (causes.map((c) => c.name).toList()..sort()).join(','),
        at: clock.now(),
      );
}
