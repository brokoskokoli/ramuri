# WP01 – Projektgerüst und Gate (`app/`, `tool/gate.sh`, `.github/workflows/gate.yml`)

**Zuordnung:** M1.

Bezug: CON-0001, CON-0002; ADR-0002 (Versionen, Aufbau, Ports, iOS, Konsequenzen zum Gate), ADR-0004 Punkt 2. Keine Abhängigkeit von R005 oder ADR-0008.

## Inhalt
1. **Flutter-Version:** Exakt die Version aus ADR-0002 festlegen, als `environment.flutter` in `app/pubspec.yaml`. Der lokale Stand weicht ab (siehe `M1-PLAN.md`, L15) und wird zuerst angeglichen; andernfalls melden und nicht still eine andere Version pinnen.
2. **App und Workspace:** `flutter create --platforms=android` in `app/`, Pub-Workspace mit `app/packages/core` (reines Dart) und `app/packages/adapters`. minSdk, targetSdk und compileSdk nach ADR-0002 Punkt 1.
3. **Ports und Fakes in `core`:** Standort, Herzfrequenzsensor, Schrittfrequenz, Aufzeichnungsdienst, Speicher, Schlüsselablage, Health Connect (nur Verfügbarkeitsabfrage und Fake, keine Android-Umsetzung vor Phase 3) und Uhr. Nur die Schnittstellen, die spätere Pakete ausbauen.
4. **Gate:** `tool/gate.sh` prüft zusätzlich `app/packages/*`: Format und Analyse je Paket, `dart test` in `core`, `flutter test` in `adapters` und `app`. `--changed` beachtet weiter ganz `app/`. Ein Schritt vergleicht die laufende Flutter-Version mit `environment.flutter`.
5. **CI-Datei:** `.github/workflows/gate.yml` liest die Version aus `app/pubspec.yaml` (`flutter-version-file`) statt `channel: stable`. Sie greift erst mit einem Remote und wird deshalb nur durchgesehen, nicht ausgeführt.
6. **Gerüst für spätere Pakete:** Lokalisierung mit `flutter gen-l10n` und je einer ARB-Datei für Deutsch und Englisch, Einstieg und Zusammenbau der Abhängigkeiten in `app/lib`, Ordner je Funktion unter `app/lib/features/`.
7. **Testumgebung:** AVDs mit Google-Images für API 31 und API 36 (ADR-0002) anlegen oder den Weg dorthin dokumentieren; bisher liegt lokal nur API 35.

## Umsetzung
- **Teile für die Coder-Aufträge:** Teil A: Punkte 1 und 2 / Teil B: Punkt 3 mit Fakes und Tests / Teil C: Punkte 4 und 5 / Teil D: Punkte 6 und 7, je ein Auftrag ohne Übergabe, in dieser Reihenfolge.
- Keine Pakete außer Flutter-SDK-Bestandteilen ohne ADR (auch keine Bibliothek für Zustand, Navigation oder Diagramme). Ein Bedarf wird gemeldet.
- `AGENTS.md` (Abschnitte „Stand“ und „Befehle“) und `docs/quality/testing.md` (Abschnitt „CI-Gates“) nachziehen, in `work-packages/REVIEW.md` den Verweis auf `docs/ARCHITECTURE.md` korrigieren.
- Nicht dazu: Fachlogik, Oberfläche über einen Startbildschirm hinaus, Datenbank.
- Parallel: keine; alle anderen Pakete bauen hierauf. Dieses Paket läuft allein.

## Abnahmekriterien
- [ ] `sh tool/gate.sh` ist grün mit je einem echten Test in `core`, `adapters` und `app`.
- [ ] Negativfälle, je einmal belegt: Ein fehlschlagender Test in `core` und einer in `adapters` färben das Gate rot, ebenso eine Formatabweichung in `adapters` und ein Analysefehler in `core`.
- [ ] Ein Flutter-Import in `core` scheitert am Auflösen der Abhängigkeiten (ADR-0002).
- [ ] Eine abweichende Flutter-Version färbt das Gate rot; die Prüfung ist mit einer manipulierten Vorgabe belegt.
- [ ] `sh tool/gate.sh --changed` lässt Flutter nur aus, wenn `app/` samt `app/packages/` unverändert ist; eine Änderung nur in `app/packages/core` löst die Prüfung aus.
- [ ] Das Debug-APK baut mit den Versionen aus ADR-0002. Das zusammengeführte Manifest zeigt minSdk und targetSdk; es gibt kein `app/ios/`.
- [ ] Beide ARB-Dateien haben dieselben Schlüssel, ein Test prüft das und schlägt bei einem fehlenden Schlüssel fehl.
- [ ] E2E (separater Agent): App startet auf API 31 und API 36 im Emulator mit explizitem Serial und zeigt den Startbildschirm auf Deutsch und Englisch.
- [ ] Doku/Spezifikation nachgezogen (Änderungsprotokoll-Eintrag durch den Orchestrator). Gate grün.

## Ungeprüft
Verhalten auf Herstellergeräten (ADR-0002). Der Workflow `gate` läuft ohne Remote nicht.
