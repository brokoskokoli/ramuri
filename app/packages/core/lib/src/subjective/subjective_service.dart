import '../../ports/clock.dart';
import '../../ports/storage.dart';
import 'manual_training.dart';
import 'run_subjective.dart';
import 'srpe.dart';

/// Rechnet den sRPE-Wert eines Laufs neu aus seinem gespeicherten RPE und der
/// gespeicherten Bewegungszeit (FR-0095, OQ-0015) und speichert ihn am Lauf.
/// Ohne RPE oder ohne Bewegungszeit steht kein Wert. Ohne Angaben zum Lauf
/// passiert nichts. Aufruf, wenn sich die Bewegungszeit des Laufs geändert hat
/// (Berechnung nach dem Lauf, Neuberechnung der Kurzfassung).
Future<void> refreshSrpe(StorageSession session, int runId) async {
  final stored = await session.subjective.read(runId);
  if (stored == null) return;
  final srpe = await _srpeOf(session, runId, stored.subjective.rpe);
  if (srpe == stored.srpe) return;
  // Nur die sRPE-Spalten, und nur wenn das RPE noch das gelesene ist: eine
  // parallele Änderung der Angabe geht nicht verloren (sie rechnet ihren
  // eigenen Wert).
  await session.subjective.setSrpe(
    runId,
    srpe,
    expectedRpe: stored.subjective.rpe,
  );
}

Future<SrpeLoad?> _srpeOf(StorageSession session, int runId, int? rpe) async {
  if (rpe == null) return null;
  final moving = (await session.preprocessing.read(runId))?.summary.movingTime;
  if (moving == null) return null;
  return SrpeLoad.compute(duration: moving, rpe: rpe);
}

/// Angaben zum Lauf und nachgetragene Trainings (FR-0038, FR-0199). sRPE wird
/// beim Lauf als eigener Wert gespeichert und folgt der Angabe; er wird nie mit
/// TRIMP zusammengerechnet (FR-0096).
class SubjectiveService {
  SubjectiveService({required this.session, required this.clock});

  final StorageSession session;
  final Clock clock;

  Future<StoredRunSubjective?> read(int runId) =>
      session.subjective.read(runId);

  /// Ersetzt die Angaben des Laufs und rechnet den sRPE-Wert mit der
  /// gespeicherten Bewegungszeit neu: Ändert oder entfernt sich das RPE, folgt
  /// der Wert. Leere Angaben entfernen den Satz. Unbekannter Lauf: `notFound`.
  Future<void> save(int runId, RunSubjective subjective) async {
    final srpe = await _srpeOf(session, runId, subjective.rpe);
    await session.subjective.save(runId, subjective, srpe: srpe);
  }

  /// Trägt ein Training nach. Liegt der Tag nach heute (Ortstag laut Uhr des Geräts),
  /// wirft es [SubjectiveRangeError].
  Future<StoredManualTraining> addTraining(ManualTraining training) async {
    training.requireNotAfter(_localDay());
    return session.manualTrainings.add(training);
  }

  Future<void> updateTraining(int id, ManualTraining training) async {
    training.requireNotAfter(_localDay());
    await session.manualTrainings.update(id, training);
  }

  /// „Heute“ ist der Ortstag des Nutzers (wie Oberfläche und Datumswähler),
  /// nicht der UTC-Tag. Als UTC-Zeitpunkt mit Ortsuhrzeit zurückgegeben.
  DateTime _localDay() {
    final n = clock.now();
    return n.toUtc().add(clock.utcOffsetAt(n));
  }

  Future<void> deleteTraining(int id) => session.manualTrainings.delete(id);

  Future<List<StoredManualTraining>> trainings() =>
      session.manualTrainings.list();
}
