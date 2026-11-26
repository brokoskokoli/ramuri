import '../../ports/storage_runs.dart';
import 'treadmill.dart';

/// Hinweis Wade/Achillessehne der anderen Sportart (FR-0221): Der Zähler der
/// Seilspring-Einheiten kommt aus den gespeicherten Einheiten, ohne eigenes Feld.

/// Hinweis Wade/Achillessehne: in den ersten so vielen Seilspring-Einheiten.
const int ropeHintRuns = 3;

bool _isRope(StoredRun r) =>
    r.mode == RunMode.sport && r.sport == OtherSport.rope;

/// Start: Hinweis, solange weniger als [ropeHintRuns] Seilspring-Einheiten
/// beendet gespeichert sind (die neue wäre die 1. bis 3.). Lesefehler: zeigen.
Future<bool> ropeHintBeforeStart(RunStore runs) async {
  try {
    final done = (await runs.list())
        .where((r) => r.state == RunState.finished && _isRope(r))
        .length;
    return done < ropeHintRuns;
  } on Object {
    return true;
  }
}

/// Zusammenfassung: Hinweis, wenn [runId] unter den ersten [ropeHintRuns]
/// beendeten Seilspring-Einheiten ist (nach Start, dann Nummer).
/// Lesefehler: zeigen.
Future<bool> ropeHintForRun(RunStore runs, int runId) async {
  try {
    final rope =
        (await runs.list())
            .where(
              (r) =>
                  _isRope(r) && (r.state == RunState.finished || r.id == runId),
            )
            .toList()
          ..sort((a, b) {
            final c = a.startedAt.compareTo(b.startedAt);
            return c != 0 ? c : a.id.compareTo(b.id);
          });
    final rank = rope.indexWhere((r) => r.id == runId);
    return rank >= 0 && rank < ropeHintRuns;
  } on Object {
    return true;
  }
}
