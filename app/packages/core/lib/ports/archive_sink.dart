import '../src/archive/archive_schema.dart';

/// Port: Ziel des Archiv-Lesers (WP12, `docs/contracts/archive.md` 4.5).
///
/// Der Leser ruft in dieser Reihenfolge auf: [begin], dann beliebig oft
/// [insert] (Zeilen in Dateireihenfolge, Abschnitte in Vertragsreihenfolge,
/// jede Zeile schon auf Spalten und Typen geprüft), dann **genau eines** von
/// [commit] oder [abort]. [commit] kommt nur, nachdem alle Stücke
/// entschlüsselt, der gzip-Rahmen und die Endzeile mit den Zählern geprüft
/// sind; bei jedem anderen Ausgang kommt [abort]. [abort] darf auch ohne
/// [begin] oder nach einem Fehler in [insert] aufgerufen werden, muss alles
/// verwerfen und darf nicht werfen.
///
/// Fremdschlüssel, CHECKs und Trigger der Datenbank prüft das Ziel selbst:
/// Wirft [insert] oder [commit] eine `ArchiveImportException`, gilt ihr Grund
/// (zum Beispiel `damaged` für eine Verletzung), jede andere Ausnahme wird zu
/// `targetFailed`.
abstract interface class ArchiveSink {
  Future<void> begin();

  Future<void> insert(
    ArchiveSectionSpec section,
    List<Map<String, Object?>> rows,
  );

  Future<void> commit();

  Future<void> abort();
}
