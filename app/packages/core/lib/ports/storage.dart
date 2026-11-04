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

  /// Zugriff: Der Lauf oder der Eintrag existiert nicht.
  notFound,

  /// Zugriff: Die Datenbank hat die Eingabe abgelehnt (Beschränkung verletzt,
  /// etwa doppelte Rundennummer oder nicht endlicher Wert). Nichts wurde
  /// geschrieben.
  rejected,

  /// Zugriff: sonstiger Fehler (Ein-/Ausgabe, Zustand). Die Datenbank selbst
  /// gilt nicht als unlesbar; der Dialog aus OQ-0062 gehört nur zu [unreadable].
  failed,
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
/// keine Löschen-Methode (ADR-0004 Punkt 1); Löschen kommt mit WP02 Teil C.
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

  Future<void> close();
}

/// Port: Speicher. Bewusst dünn: kein SQL, keine Tabellen.
abstract interface class Storage {
  /// Öffnet den Speicher mit dem Schlüssel; wirft [StorageException].
  Future<StorageSession> open(Uint8List key);
}
