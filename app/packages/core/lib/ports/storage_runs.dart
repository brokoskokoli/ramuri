import 'storage.dart' show StorageException, StorageFailure;

/// Zustand eines Laufs. `paused` und `finished` sind aus FR-0028 und FR-0193
/// abgeleitet (ADR-0005 nennt nur `active`).
enum RunState { active, paused, finished }

class StoredRun {
  const StoredRun({
    required this.id,
    required this.state,
    required this.startedAt,
    this.endedAt,
    this.endedUtcOffset,
  });

  final int id;
  final RunState state;
  final DateTime startedAt;

  /// Nur bei [RunState.finished] gesetzt.
  final DateTime? endedAt;

  /// UTC-Versatz der Ortszeit zum Laufende (Zeitzone zum Laufzeitpunkt; der
  /// lokale Kalendertag des Laufendes ist `endedAt + endedUtcOffset`). `null` =
  /// unbekannt (Läufe aus Schema 1, oder beim Beenden nicht genannt). Nur bei
  /// [RunState.finished].
  final Duration? endedUtcOffset;
}

/// Läufe anlegen, Zustand ändern, lesen.
abstract interface class RunStore {
  /// Legt einen Lauf im Zustand `active` an.
  Future<StoredRun> create({required DateTime startedAt});

  /// Ändert den Zustand. [endedAt] ist genau bei `finished` Pflicht und sonst
  /// verboten (`rejected`); ein unbekannter Lauf ist `notFound`. Die Reihenfolge
  /// der Übergänge prüft WP06, nicht der Speicher. [endedUtcOffset] (UTC-Versatz
  /// der Ortszeit zum Laufende) ist optional und nur zusammen mit [endedAt]
  /// erlaubt; ganze Sekunden, höchstens 18 Stunden, sonst `rejected`. Ohne
  /// Angabe bleibt er unbekannt (`null`).
  Future<void> setState(
    int runId,
    RunState state, {
    DateTime? endedAt,
    Duration? endedUtcOffset,
  });

  /// `null` für einen unbekannten Lauf.
  Future<StoredRun?> get(int runId);

  /// Alle Läufe, neuester Start zuerst (Historie, WP10).
  Future<List<StoredRun>> list();

  /// Beendete Läufe mit `from <= endedAt < to` (Zeitpunkte), frühestes Ende
  /// zuerst. Liest nur den Zeitraum, z. B. für den Kalender (FR-0171).
  Future<List<StoredRun>> finishedBetween(DateTime from, DateTime to);

  /// Läufe, die nicht beendet sind (`active` oder `paused`), ältester zuerst.
  /// Für die Wiederaufnahme nach einem Abbruch (FR-0193, WP08).
  Future<List<StoredRun>> unfinished();
}

/// Runde (FR-0030). [index] zählt je Lauf ab 1 und ist je Lauf eindeutig.
class StoredLap {
  const StoredLap({
    required this.index,
    required this.markedAt,
    required this.lapTime,
  });

  final int index;
  final DateTime markedAt;
  final Duration lapTime;
}

enum RunGapKind { manualPause, positionLoss, heartRateLoss, interruption }

/// Lücke oder Pause, die die Aufzeichnung selbst markiert (FR-0194, FR-0193).
/// [end] ist `null`, solange sie offen ist.
class StoredGap {
  const StoredGap({
    required this.id,
    required this.kind,
    required this.start,
    this.end,
  });

  final int id;
  final RunGapKind kind;
  final DateTime start;
  final DateTime? end;
}

/// Runden und Lücken eines Laufs. Beides nur anhängen bzw. Lücke schließen.
abstract interface class RunMarkerStore {
  /// Doppelte Rundennummer oder Lauf unbekannt: `rejected` bzw. `notFound`.
  Future<void> addLap(int runId, StoredLap lap);

  /// Nach [StoredLap.index] sortiert.
  Future<List<StoredLap>> laps(int runId);

  /// Öffnet eine Lücke und liefert ihre Id.
  Future<int> openGap(int runId, RunGapKind kind, DateTime start);

  /// Schließt eine offene Lücke; unbekannt `notFound`, schon geschlossen
  /// `rejected`.
  Future<void> closeGap(int gapId, DateTime end);

  /// Nach Beginn sortiert.
  Future<List<StoredGap>> gaps(int runId);
}

/// Größter erlaubter UTC-Versatz der Ortszeit zum Laufende ([requireRunEnd]).
const maxRunEndUtcOffset = Duration(hours: 18);

/// Prüft Zustand, Ende und UTC-Versatz vor dem Speichern (Adapter und Fake
/// rufen dieselbe Regel). `rejected`, wenn das Ende nicht genau bei `finished`
/// steht, der Versatz ohne Ende genannt wird, nicht aus ganzen Sekunden besteht
/// oder 18 Stunden überschreitet.
void requireRunEnd(
  RunState state,
  DateTime? endedAt,
  Duration? endedUtcOffset,
) {
  final bad =
      (state == RunState.finished) != (endedAt != null) ||
      (endedUtcOffset != null &&
          (endedAt == null ||
              endedUtcOffset.inMicroseconds % Duration.microsecondsPerSecond !=
                  0 ||
              endedUtcOffset.abs() > maxRunEndUtcOffset));
  if (bad) throw const StorageException(StorageFailure.rejected);
}
