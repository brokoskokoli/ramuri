import 'dart:typed_data';

import 'storage_consents.dart';
import 'storage_derived.dart';
import 'storage_devices.dart';
import 'storage_profile.dart';
import 'storage_raw.dart';
import 'storage_runs.dart';
import 'storage_settings.dart';
import 'storage_values.dart';

enum StorageFailure {
  /// Verschlüsselung ist nicht aktiv; die Datei wird nicht geöffnet (ADR-0003).
  encryptionNotActive,

  /// Schlüssel passt nicht oder Datei ist unlesbar (OQ-0062).
  unreadable,

  /// Öffnen: Die Datei hat eine höhere Schemaversion als diese App kennt
  /// (Herabstufen). Die Datei ist gesund; ein Neubeginn wäre falsch, die neuere
  /// App-Version wird gebraucht.
  newerVersion,

  /// Öffnen: Die Migration auf die aktuelle Version ist gescheitert (Fehler
  /// der App, nicht der Datei). Kein Neubeginn.
  migrationFailed,

  /// Öffnen: Ein PRAGMA der Einrichtung (WAL, Synchronisation, `secure_delete`
  /// u. a.) hat nicht den verlangten Wert, etwa auf einem Dateisystem ohne WAL.
  /// Fehler der Umgebung, nicht der Datei: kein Neubeginn.
  configurationFailed,

  /// Zugriff: Der Lauf oder der Eintrag existiert nicht.
  notFound,

  /// Zugriff: Die Datenbank hat die Eingabe abgelehnt (Beschränkung verletzt,
  /// etwa doppelte Rundennummer oder nicht endlicher Wert). Nichts wurde
  /// geschrieben.
  rejected,

  /// Zugriff: sonstiger Fehler (Ein-/Ausgabe, Zustand). Die Datenbank selbst
  /// gilt nicht als unlesbar; der Dialog aus OQ-0062 gehört nur zu [unreadable].
  failed,

  /// Löschen: Die Daten sind gelöscht (Transaktion abgeschlossen, `secure_delete`
  /// war an), aber die Prüfung der Schreibvorgänge (WAL-Checkpoint) ist nicht
  /// durchgelaufen, etwa weil ein Leser die Datei hielt. Das Löschen bleibt
  /// gültig; die Marke könnte noch in der Journal-Datei stehen. Kein Erfolg.
  deletedNotErased,
}

/// Fehler des Speichers. Trägt absichtlich nie Inhalte (Statement, Parameter,
/// Schlüssel, Messwerte) und keine Ursache.
class StorageException implements Exception {
  const StorageException(this.failure);

  final StorageFailure failure;

  @override
  String toString() => 'StorageException($failure)';
}

/// Offene Verbindung zum Speicher mit schmalen Zugriffen je Bereich. Jede
/// Methode wirft nur [StorageException]. Die Rohdaten kennen keine Ändern- und
/// keine Löschen-Methode (ADR-0004 Punkt 1); gelöscht wird nur mit dem Lauf
/// ([deleteRun]) oder komplett ([deleteAll]).
abstract interface class StorageSession {
  RunStore get runs;
  RunMarkerStore get markers;
  RawDataStore get rawData;
  PreprocessingStore get preprocessing;
  RatedSectionStore get sections;
  ComputedValueStore get values;
  ProfileStore get profile;
  SettingsStore get settings;
  KnownDeviceStore get devices;
  ConsentStore get consents;

  /// Löscht den Lauf mit allem darunter (Rohdaten, Runden, Lücken,
  /// Vorverarbeitung, Abschnitte, Werte) und alle Tageswerte, deren
  /// Datenzeitraum den Lauf überlappt oder unbekannt ist (WP09 berechnet sie
  /// neu). Eine Transaktion, danach WAL-Checkpoint (TRUNCATE). Unbekannter
  /// Lauf: [StorageFailure.notFound]. Lief der Checkpoint nicht durch:
  /// [StorageFailure.deletedNotErased], das Löschen gilt trotzdem.
  Future<void> deleteRun(int runId);

  /// Löscht alle Nutzdaten (Läufe, Werte, Profil, Einstellungen, Geräte,
  /// Einwilligungen). Der Schlüssel liegt nicht im Speicher und bleibt.
  /// Sonst wie [deleteRun].
  Future<void> deleteAll();

  Future<void> close();
}

/// Port: Speicher. Bewusst dünn: kein SQL, keine Tabellen.
abstract interface class Storage {
  /// Öffnet den Speicher mit dem Schlüssel; wirft [StorageException].
  Future<StorageSession> open(Uint8List key);
}
