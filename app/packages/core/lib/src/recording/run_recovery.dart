// ignore_for_file: prefer_initializing_formals
import '../../ports/clock.dart';
import '../../ports/storage_raw.dart';
import '../../ports/storage_runs.dart';

/// Letzter gespeicherter Zeitpunkt eines Laufs: das Späteste aus Start,
/// Rohwerten aller Kanäle, Runden und Lücken (Anfang und Ende). Er ist der
/// Stand, bis zu dem der Lauf belegt ist (FR-0193).
DateTime lastRecordedTime(
  StoredRun run,
  StoredRawData raw,
  List<StoredGap> gaps,
  List<StoredLap> laps,
) {
  var last = run.startedAt;
  void see(DateTime t) {
    if (t.isAfter(last)) last = t;
  }

  for (final r in raw.positions) {
    see(r.value.time);
  }
  for (final r in raw.heartRates) {
    see(r.value.time);
  }
  for (final r in raw.altitudes) {
    see(r.value.time);
  }
  for (final r in raw.steps) {
    see(r.value.time);
  }
  for (final r in raw.unavailable) {
    see(r.value.time);
  }
  for (final b in raw.beltSettings) {
    see(run.startedAt.add(b.value.offset));
  }
  for (final l in laps) {
    see(l.markedAt);
  }
  for (final g in gaps) {
    see(g.start);
    final end = g.end;
    if (end != null) see(end);
  }
  return last;
}

/// Wiederanlauf nach einem Abbruch (FR-0193, OQ-0061): findet einen Lauf, der
/// nicht beendet ist, obwohl kein Dienst mehr läuft, und beendet ihn auf
/// Wunsch. Fortsetzen macht [RunRecorder.restore].
///
/// Es gibt keine Frist und keinen automatischen Neustart: Das Angebot bleibt,
/// bis der Nutzer wählt oder der Lauf beendet ist.
class RunRecovery {
  RunRecovery({
    required Clock clock,
    required RunStore runs,
    required RawDataStore rawData,
    required RunMarkerStore markers,
  }) : _clock = clock,
       _runs = runs,
       _raw = rawData,
       _markers = markers;

  final Clock _clock;
  final RunStore _runs;
  final RawDataStore _raw;
  final RunMarkerStore _markers;

  /// Der älteste unfertige Lauf (auch pausiert) oder `null`. [serviceRunning]
  /// ist `RecordingServicePort.isRunning`: Läuft der Dienst, gehört der Lauf
  /// einer laufenden Aufzeichnung dieses Prozesses, nicht der Wiederaufnahme.
  /// Die Uhr geht nicht ein (keine Frist).
  Future<StoredRun?> pending({required bool serviceRunning}) async {
    if (serviceRunning) return null;
    final open = await _runs.unfinished();
    return open.isEmpty ? null : open.first;
  }

  /// Ob die Uhr vor dem letzten gespeicherten Zeitpunkt des Laufs steht (Uhr
  /// zurückgestellt): Beim Fortsetzen zählen Punkte erst, wenn sie aufholt.
  Future<bool> clockBehind(StoredRun run) async {
    final last = lastRecordedTime(
      run,
      await _raw.read(run.id),
      await _markers.gaps(run.id),
      await _markers.laps(run.id),
    );
    return _clock.now().isBefore(last);
  }

  /// Speichert den Lauf als beendet: Endzeit ist der letzte gespeicherte
  /// Zeitpunkt (nicht jetzt: die Zeit danach ist nicht belegt), mit dem
  /// UTC-Versatz zu diesem Zeitpunkt; offene Lücken werden dort geschlossen.
  /// Gibt den beendeten Lauf zurück, oder `null`, wenn er schon beendet oder
  /// unbekannt ist.
  Future<StoredRun?> saveFinished(int runId) async {
    final run = await _runs.get(runId);
    if (run == null || run.state == RunState.finished) return null;
    final raw = await _raw.read(runId);
    final gaps = await _markers.gaps(runId);
    final laps = await _markers.laps(runId);
    final last = lastRecordedTime(run, raw, gaps, laps);
    for (final g in gaps) {
      if (g.end == null) await _markers.closeGap(g.id, last);
    }
    final offset = Duration(seconds: _clock.utcOffsetAt(last).inSeconds);
    await _runs.setState(
      runId,
      RunState.finished,
      endedAt: last,
      endedUtcOffset: offset,
    );
    return _runs.get(runId);
  }
}
