# R005 – Durchstich der Aufzeichnung

**Status:** läuft · **Auftraggeber:** Project Supervisor (ADR-0005, ADR-0003) · **Datum:** 2026-11-04

## Frage
Trägt ADR-0005 Punkt 3 (ein FlutterEngine im Application-Objekt, dünner Kotlin-Foreground-Service, Logik in Dart) eine lückenlose Aufzeichnung bei gesperrtem Bildschirm? Daran hängen ADR-0005 Punkt 3 und Wake Lock, ADR-0003 Punkt 5 (WAL, Transaktionsgröße), ADR-0006 (Plugin) und die Pakete der Aufzeichnung in M1. Ergebnis ist eine Empfehlung für Host und Transaktionsgröße, keine Produktgrenzwerte.

**Kriterien:** keine Datenlücke im Emulator bei gesperrtem Bildschirm und Idle; gesicherte Daten überstehen den Kill; WAL nachweislich verschlüsselt; alle Abhängigkeiten GPL-3.0-verträglich, soweit ohne Rechtsprüfung einschätzbar.

## Hintergrund
ADR-0005 (Abschnitt „Vorschlag Research R005“), ADR-0003 (Punkte 1, 4, 5, Offene Punkte), ADR-0006 (Konsequenzen: Bau mit Target 36). Reihenfolge: zuerst Bau, Lizenzen, WAL; dann Prototyp; dann lange Läufe.

## Methode
Wird mit dem Prototyp ergänzt (siehe unten).

## Daten
Nur synthetische GPS-Spuren mit festem Seed. Rohdaten nach `research/data/work/R005/`.

## Ausführung
Wird mit den Skripten ergänzt.
