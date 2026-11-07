# WP12 – Verschlüsseltes Archiv und Reimport (`app/packages/core/lib/src/archive`, `app/packages/adapters`, `app/lib/features/archive`, `app/lib/features/storage`, `docs/contracts/`)

**Zuordnung:** M1. **Wartet auf ADR-0008** (Status `Accepted` mit den Antworten A, B und C).

Bezug: FR-0192, FR-0198, SEC-0011, ACC-15; SEC-0009 (Reimport aus dem Dialog, OQ-0062), SEC-0010; ADR-0001, ADR-0004 Punkt 6, ADR-0008; OQ-0032, OQ-0050, DEC-0028.

Alle Einzelheiten zu Verfahren und Paket stehen in ADR-0008. Ändert die Freigabe etwas daran, passt der Project Supervisor dieses Paket an.

## Inhalt
1. **Vertrag:** Aufbau des Archivs als Dokument in `docs/contracts/` (OQ-0032): Kopf, Formatversion, Abschnitte mit allen Datenebenen und Kennungen (ADR-0004 Punkt 6). Abschnitte für Ziele, Pläne und aktive Warnmeldung sind vorgesehen und bleiben in Phase 1 leer (FR-0192, L13).
2. **Verschlüsselung:** Stück-Rahmen und Schlüsselableitung nach ADR-0008 hinter einem Port, feste Testvektoren aus einer unabhängigen Umsetzung.
3. **Export:** Datenbank als Strom über Kompression und Verschlüsselung ins gewählte Ziel, ohne Klartext auf dem Datenträger; Passwort zweimal, Hinweis aus SEC-0011, Passwortregel laut Antwort B. Keine Zugangsdaten, Einwilligungen oder Schlüssel. Ablage über den Port aus WP11.
4. **Reimport:** Nur auf leerer App oder nach ausdrücklichem Zurücksetzen, mit Hinweis aus OQ-0050; Datei prüfen und in Zwischendatenbank entpacken, Tausch erst nach vollständiger Prüfung; Einwilligungen werden neu eingeholt. Formatversionen laut Antwort C.
5. **Einbindung SEC-0009:** Der Dialog aus WP02 bietet nun auch den Reimport an.

## Umsetzung
- Aus WP10: Zonenzeiten und `trimp_run` sind Laufwerte in `computed_values` (K26). Zonenwerte sind nicht aus den Rohdaten rekonstruierbar (Grenzen nicht gespeichert), eine Neuberechnung nach dem Import nähme die aktuellen Grenzen. Das Archiv führt alle Laufwerte mit (`original` und `current`, `unavailable_reason`, Basis) und reicht unbekannte `value_key`s durch. Die Kurzfassung in `preprocessing_results` ist ableitbar und nach dem Reimport per Versionsvergleich neu rechenbar. Schema v4.
- Aus WP11: Ablage über den Port `FileHandoff` (`core/lib/ports/file_handoff.dart`): `share`/`save` liefern `completed`, `cancelled` oder `failed` und werfen nie. Große Dateien nicht als Bytes, sondern über `exportDirectory()` und `ExportFile.inExportDirectory(path)`; der Kanal überträgt nur den Pfad, Speichern streamt. Zugelassen sind nur reguläre Dateien unter `cacheDir/exports`. Dieser Ordner wird beim App-Start und vor jedem Teilen geleert: das Archiv erst vollständig schreiben, dann übergeben, nie parallel zu einem Teilen. Zwei Soll-Punkte aus dem Re-Review gehören hierher: (a) bei Pfadquelle Dateiname gleich `fileName` erzwingen (`FileHandoffChannel.kt` `source()` und `ExportFile.inExportDirectory`, je ein Test); (b) `source()` als reine Funktion nach `ExportFiles` ziehen und auf der JVM testen. Vorlagen für E2E (Empfänger-App, Teilen-Skripte) in `../running-app-wt/handoff/e2e-vorlagen/wp11-e2e/`.
- Aus WP02: Im Daten-Bildschirm ist Platz für den Reimport vorgesehen (nur Kommentar).
- **Teile für die Coder-Aufträge:** Teil A: Punkte 1 und 2 / Teil B: Punkt 3 / Teil C: Punkt 4 / Teil D: Punkt 5 und Oberfläche, je ein Auftrag ohne Übergabe, in dieser Reihenfolge.
- Vollständigen Lizenzbaum prüfen und im Abschluss nennen (ADR-0008, Offene Punkte). Die Mutationstests sind hier Pflicht (Sicherheitslogik).
- Nicht dazu: Erinnerung an die Sicherung (OQ-0056: „kann“), automatischer Export, Cloud.
- Parallel: Nach WP11. Kann mit jedem Paket laufen, das `app/lib/features/storage` und `core/lib/src/archive` nicht berührt; ändert sich das Schema später, muss der Vertrag mitwachsen.

## Abnahmekriterien
- [ ] SEC-0011: Ohne Passwort und mit falschem Passwort nicht lesbar; synthetische Marken stehen nicht im Klartext in der Datei; Hinweis auf ein vergessenes Passwort sichtbar; Mutationsbelege an Prüfung des Endstücks, Zähler und Kopfbindung.
- [ ] Rahmen, Negativfälle: abgeschnittene Datei, fehlendes Endstück, vertauschte oder doppelte Stücke, verändertes Byte in Kopf und Stück, angehängte Daten, leere Datei, fremde Datei, unbekannte Formatversion oder Parameter. Jeder Fall scheitert und ändert keine Daten (FR-0198, Vergleich der Datenbank vor und danach).
- [ ] Testvektoren der unabhängigen Umsetzung bestehen in beide Richtungen.
- [ ] FR-0192, ACC-15: Der Rundgang enthält Historie, Einstellungen, berechnete Werte (`original` und `current`) und Rohdaten; Abschnitte für spätere Objekte vorhanden.
- [ ] SEC-0011: Zugangsdaten, Einwilligungen und Datenbankschlüssel fehlen im Archiv; Test mit gesetzter Einwilligung.
- [ ] FR-0198: Nach Rundgang auf leerer App sind Läufe, Einstellungen und berechnete Werte gleich; Reimport auf nicht leerer App wird ohne ausdrückliches Zurücksetzen abgelehnt; der Hinweis auf gelöschte Daten erscheint; Einwilligungen sind danach nicht erteilt.
- [ ] Abbruch: Unterbrechung beim Export hinterlässt keine als gültig lesbare Datei; Prozess-Kill beim Reimport hinterlässt den alten Stand (Test mit Fehlerinjektion).
- [ ] Kein Klartext in temporären Dateien (Test mit Marke über das App-Verzeichnis); Passwort und Inhalte nicht in Logs.
- [ ] SEC-0009: Vom Dialog aus WP02 führt der Weg zum Reimport; die alte Datei bleibt, bis der Nutzer ihr Löschen bestätigt.
- [ ] E2E (separater Agent), API 31 und 36: Rundgang über zwei AVDs mit synthetischen Daten; falsches Passwort; beschädigte Datei; nicht leere App; Dauer der Ableitung und eines Archivs als grobe Größe berichtet.
- [ ] Doku/Spezifikation nachgezogen (Änderungsprotokoll-Eintrag durch den Orchestrator). Gate grün.

## Ungeprüft
Dauer und Speicherdruck auf schwachen Geräten, echter Gerätewechsel, sehr große Archive aus echten Läufen (ADR-0008).
