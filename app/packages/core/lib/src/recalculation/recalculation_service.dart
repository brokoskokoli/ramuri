import 'dart:async';

import '../../ports/clock.dart';
import '../../ports/storage.dart';
import '../../ports/storage_profile.dart';
import '../../ports/storage_runs.dart';
import '../../ports/storage_values.dart';
import '../fitness/vo2max_estimator.dart';
import '../profile/heart_rate_resolution.dart';
import 'run_analysis.dart';
import 'value_calculation_service.dart';

/// Warum eine Neuberechnung angeboten wird (FR-0006, FR-0058).
enum RecalculationCause {
  /// HFmax oder Ruhepuls (oder deren Schätzung) haben sich geändert.
  heartRateBasis,

  /// Parameter- oder Methodenversion der gespeicherten Werte weicht von der
  /// der App ab (Änderung des Algorithmus).
  algorithmVersion,
}

/// Angebot einer Neuberechnung. Es ändert nichts, bis es bestätigt wird.
class RecalculationOffer {
  RecalculationOffer({
    required Set<RecalculationCause> causes,
    required List<int> runIds,
  }) : causes = Set.unmodifiable(causes),
       runIds = List.unmodifiable(runIds);

  final Set<RecalculationCause> causes;

  /// Läufe mit gespeichertem VO₂max-Laufwert, deren `current` neu gerechnet
  /// würde.
  final List<int> runIds;
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
    return RecalculationOffer(causes: causes, runIds: await _affectedRuns());
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
    if (same) return null;
    return _offer(RecalculationCause.heartRateBasis);
  }

  /// Prüft, ob gespeicherte Laufwerte mit einer anderen Parameter- oder
  /// Methodenversion gerechnet sind als die App sie jetzt verwendet.
  Future<RecalculationOffer?> checkVersions() async {
    const estimator = AcsmReserveVo2maxEstimator();
    for (final r in await session.runs.list()) {
      for (final p in await session.values.read(ValueOwner.run(r.id))) {
        if (p.original.key != vo2maxRunValueKey) continue;
        final c = p.current;
        if (c.parameterVersion != _calc.fitness.parameterVersion ||
            c.method != estimator.method ||
            c.methodVersion != estimator.methodVersion) {
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
    final snapshot = await _calc.buildSnapshot();
    await session.values.swapCurrentAll({
      ...snapshot.runValues,
      ...snapshot.dayValues,
    });
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
  Future<void> decline(RecalculationOffer offer) => _setPending(const {});

  Future<RecalculationOffer?> _offer(RecalculationCause cause) async {
    final runs = await _affectedRuns();
    if (runs.isEmpty) return null;
    _offerSeq[cause] = (_offerSeq[cause] ?? 0) + 1;
    final causes = {...await _pendingCauses(), cause};
    await _setPending(causes);
    final offer = RecalculationOffer(causes: causes, runIds: runs);
    _controller.add(offer);
    return offer;
  }

  Future<List<int>> _affectedRuns() async => [
    for (final r in await session.runs.list())
      if (r.state == RunState.finished && r.endedAt != null)
        if ((await session.values.read(ValueOwner.run(r.id)))
            .any((p) => p.original.key == vo2maxRunValueKey))
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
