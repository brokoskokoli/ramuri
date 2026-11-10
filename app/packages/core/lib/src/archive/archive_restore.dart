import '../../ports/archive_sink.dart';
import '../../ports/clock.dart';
import '../../ports/database_files.dart';
import '../../ports/storage.dart';
import '../../ports/storage_goals.dart';
import '../../ports/storage_prediction.dart';
import 'archive_errors.dart';
import 'archive_export.dart';
import 'archive_import.dart';
import 'archive_lines.dart' show archiveExcludedSettingKeys;

/// Wiederherstellung aus dem Archiv (WP12, FR-0198, `docs/contracts/archive.md`
/// 4.6): einlesen in die Zwischendatenbank, dann tauschen.
///
/// 1. Nur auf **leerer App** oder mit ausdrücklichem Zurücksetzen
///    (`resetConfirmed`); sonst [ArchiveRestoreFailure.notEmpty], nichts
///    geschieht. Das Zurücksetzen löscht nichts vorab: Die alten Daten
///    verschwinden erst mit dem Tausch, ein Fehlschlag davor lässt sie stehen.
/// 2. [ArchiveImporter] füllt über den [ArchiveSink] die Zwischendatenbank;
///    `commit` kommt nur nach vollständiger Prüfung. Jeder Fehler hinterlässt
///    die aktive Datenbank unverändert und keine Zwischendatenbank.
/// 3. Tausch: aktive Sitzung mit Checkpoint schließen (scheitert der
///    Checkpoint, bleibt der alte Stand und `swapFailed`),
///    [DatabaseFiles.replaceWithImport] (bricht bei einem aktiven `-wal` mit
///    Inhalt ab), neu öffnen. Bei `swapFailed` trägt die Ausnahme die neu
///    geöffnete Sitzung. Einwilligungen sind danach leer (nicht erteilt).
///
/// [serialize] schließt Aufnahme und Neuberechnung aus (in der App
/// `RecalculationController.exclusive`); die Aufnahme darf nicht laufen.
class ArchiveRestoreService {
  ArchiveRestoreService({
    required this.session,
    required this.sink,
    required this.files,
    required this.cipherFactory,
    required this.reopen,
    required this.clock,
    this.serialize = _direct,
  });

  /// Die aktive, geöffnete Sitzung. Der Dienst schließt sie beim Tausch.
  final StorageSession session;
  final ArchiveSink sink;
  final DatabaseFiles files;
  final ArchiveCipherFactory cipherFactory;

  /// „Heute“ für die Obergrenze nachgetragener Trainings beim Einlesen.
  final Clock clock;

  /// Öffnet die Datenbank nach dem Tausch (oder nach einem gescheiterten
  /// Tausch den alten Stand) neu.
  final Future<StorageSession> Function() reopen;

  final Future<T> Function<T>(Future<T> Function() action) serialize;

  static Future<T> _direct<T>(Future<T> Function() action) => action();

  /// Keine Läufe, kein Profilwert, keine Geräte und keine Einstellung außer den
  /// technischen Merkern ([archiveExcludedSettingKeys]). Einwilligungen zählen
  /// nicht: Sie werden ohnehin nicht übernommen. Tageswerte zählen nicht: Sie
  /// sind aus Läufen abgeleitet (ohne Läufe nichts Eigenes) und der Port bietet
  /// keine Auflistung. Referenzleistungen und das Ziel zählen (sie brauchen keinen Lauf).
  /// Wirft [StorageException].
  static Future<bool> isEmpty(StorageSession s) async {
    if ((await s.runs.list()).isNotEmpty) return false;
    final p = await s.profile.read();
    if (p.birthYear != null ||
        p.bodyWeightKg != null ||
        p.bodyHeightMeters != null ||
        p.restingHeartRateBpm != null ||
        p.maxHeartRateBpm != null ||
        p.weeklyRunMinutes != null ||
        p.trainingDaysMask != null ||
        p.usualTrainingMinutes != null) {
      return false;
    }
    if ((await s.devices.list()).isNotEmpty) return false;
    if ((await s.manualTrainings.list()).isNotEmpty) return false;
    // Eingetragene Referenzleistungen sind eigene Daten, auch ohne Läufe.
    if (s is PredictionStorage &&
        (await (s as PredictionStorage).prediction.references()).isNotEmpty) {
      return false;
    }
    // Ein Trainingsziel ist ein eigenes Datum, auch ohne Läufe.
    if (s is GoalStorage && (await (s as GoalStorage).goals.goal()) != null) {
      return false;
    }
    final settings = await s.settings.all();
    return settings.keys.every(archiveExcludedSettingKeys.contains);
  }

  /// Liest [path] mit [password] und ersetzt die Datenbank. Wirft
  /// [ArchiveImportException] (Datei/Passwort/Ziel; aktive Datenbank
  /// unverändert) oder [ArchiveRestoreException]. Gibt die neue Sitzung
  /// zurück.
  Future<StorageSession> restore({
    required String path,
    required String password,
    bool resetConfirmed = false,
    ArchiveCancel? cancel,
  }) => serialize(() async {
    final bool empty;
    try {
      empty = await isEmpty(session);
    } catch (_) {
      throw const ArchiveRestoreException(ArchiveRestoreFailure.swapFailed);
    }
    if (!empty && !resetConfirmed) {
      throw const ArchiveRestoreException(ArchiveRestoreFailure.notEmpty);
    }
    // Wirft nur ArchiveImportException; der Sink hat dann aufgeräumt (abort).
    await ArchiveImporter(
      sink: sink,
      cipherFactory: cipherFactory,
      clock: clock,
    ).import(path: path, password: password, cancel: cancel);
    // Ab hier ist die Zwischendatenbank vollständig. Schlägt etwas vor dem
    // Umbenennen fehl, steht noch der alte Stand: aufräumen und neu öffnen.
    try {
      await session.close();
      await files.replaceWithImport();
    } catch (_) {
      try {
        await files.deleteImport();
      } catch (_) {}
      final StorageSession reopened;
      try {
        reopened = await reopen();
      } catch (_) {
        throw const ArchiveRestoreException(ArchiveRestoreFailure.reopenFailed);
      }
      throw ArchiveRestoreException(
        ArchiveRestoreFailure.swapFailed,
        session: reopened,
      );
    }
    try {
      return await reopen();
    } catch (_) {
      throw const ArchiveRestoreException(ArchiveRestoreFailure.reopenFailed);
    }
  });
}
