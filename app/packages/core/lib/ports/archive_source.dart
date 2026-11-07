import '../src/archive/archive_schema.dart';

/// Port: Datenbank seitenweise für den Export lesen (WP12, Vertrag 4.2).
///
/// Liefert nur Spalten laut [ArchiveSectionSpec]; `storage_meta`,
/// Einwilligungen und Schlüssel sind nicht erreichbar.
abstract interface class ArchiveSource {
  /// Beginnt einen Lesevorgang. Der Stand wird hier festgelegt: Zeilen, die
  /// danach hinzukommen, erscheinen nicht im selben Archiv.
  Future<ArchiveSnapshot> open();
}

abstract interface class ArchiveSnapshot {
  /// Bis zu [limit] Zeilen des Abschnitts mit Schlüssel größer als [after]
  /// (`null`: ab Anfang), aufsteigend nach dem Schlüssel. Jede Zeile hat genau
  /// die Spalten des Abschnitts (`null` für NULL). Leer: Abschnitt zu Ende.
  Future<List<Map<String, Object?>>> readPage(
    ArchiveSectionSpec section, {
    Object? after,
    required int limit,
  });
}
