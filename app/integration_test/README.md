# E2E-Regressionssammlung

Läuft auf GitHub im Workflow `e2e` (je API 31 und 36, zwei Shards) über `tool/ci_e2e.sh`; die Stufen-Zuordnung steht nur dort. Lokal, ohne GitHub, nur der E2E-Agent mit Emulator (`tool/ci_e2e.sh` mit `E2E_STUFEN="..."`).

| Ablauf | Datei | Stufe / Shard |
|---|---|---|
| Neuberechnung (recalc) | `e2e_recalc_test.dart` | `sammlung` / Shard sammlung |
| Lauf aufzeichnen | `e2e_run_test.dart` | `sammlung` / sammlung |
| Plan anlegen, anpassen, neu berechnen, Warnsignal | `e2e_plan_test.dart` | `sammlung` / sammlung |
| Archiv-Export und Reimport mit und ohne Passwort (ohne Dateidialog) | `e2e_archive_test.dart` | `sammlung` / sammlung |
| Laufband | `e2e_treadmill_test.dart` | `sammlung` / sammlung |
| Laufband: geführte Einheit aus dem Plan in Echtzeit (~5 min Abschnitt), Bandwerte, Abschnittswechsel, „Aus dem Plan“, Einheit erledigt (`--dart-define=TREADMILL_PLAN=true`, frischer Speicher ohne Ziel) | `e2e_treadmill_test.dart` | `treadmill-plan` / sammlung |
| Kamera-Ruhepuls (Fake-Kamera, guter Puls und kein Finger; Kamerawahl in den Entwicklereinstellungen, FR-0220) | `e2e_resting_test.dart` | `sammlung` / sammlung |
| Morgenmessung (Entwicklermodus, K67/K68, Gurtzeile, Ruhephase überspringen, Haltungsmarke, Fake-Kamera, Gurt-RR, Messpaare, Uhrzeit der Morgen-Erinnerung über den Zeitwähler mit geplantem Zeitpunkt am Plattformkanal, feste Uhr 23:58/00:02: zwei Ortstage (FR-0215), Ausschalten in den Entwicklereinstellungen) | `e2e_morning_test.dart` | `sammlung` / sammlung |
| Health-Connect-Import (Debug-Quelle: Rechte, Abruf, Verlauf, Übernehmen, Widerruf mit Löschfrage, Installieren); echter Dialog nur lokal mit `--dart-define=HC_REAL=true` | `e2e_health_test.dart` | `sammlung` / sammlung |
| Englisch und Meilen (NFR-0006): Gerätesprache Englisch im Test, Meilen über die Einstellungen; Lauf mit Test-Gurt und GPS, Zusammenfassung in `mi` und `min/mi`, Verlauf und Fortschritt in Meilen, geprüfte Texte aus der englischen Übersetzung und nicht der deutschen; danach wieder Kilometer | `e2e_locale_test.dart` | `sammlung` / sammlung |
| Wiederanlauf eines laufenden Laufs nach Prozessende | `e2e_recover_test.dart` | `recover-a`, `recover-b` / stufen |
| Plan, geführte Einheit mit „Abschnitt überspringen“ und „Rückgängig“ (FR-0218), „Aus dem Plan“, Rückmeldung, Zieländerung, Planverlauf; Karten-Frage nur in der Zusammenfassung | `e2e_m2_flow_test.dart` | `m2-flow` / stufen |
| Erholung (WP34): Basis, Kamera, Health Connect, Verlauf, Ortstag, Schlaf als Faktor mit fester Uhr (PAR-164: zählt bis Mitternacht, danach Grund „Schlaf fehlt“), Karten flackern beim Aufheben nicht (frische Installation, Stufe wegen der gesetzten Daten) | `e2e_readiness_test.dart` | `readiness` / stufen |
| Speicher nach Prozessende (Schreiben, Lesen) | `e2e_storage_test.dart` | `storage-a`, `storage-b` / stufen |

`all_test.dart` bindet die Sammlung ein (`e2e_m2_flow_test.dart` läuft wegen der Dauer als eigene Stufe, die geführte Einheit auf dem Laufband als Stufe `treadmill-plan` derselben Datei wie der freie Laufband-Lauf); Ziel- und Profilformular bedienen beide Abläufe mit Plan über `support/e2e_plan_form.dart`; eine neue `e2e_*_test.dart`, die weder dort noch als Stufe in `tool/ci_e2e.sh` steht, macht den Lauf rot (Wächter). Die Mehrphasen-Stufen brauchen ein Prozessende zwischen den Phasen und laufen darum einzeln.

Die Hilfen warten nach dem Tipp nicht fest: `tapKey` wartet vor dem Tipp, bis die Taste im Baum steht und getroffen wird (sonst `Taste <key> fehlt` bzw. `Tipp trifft <key> nicht`), danach folgt nur ein Frame; die Wirkung prüft der Aufrufer mit `waitFor` (Schlüsselname in der Meldung) oder gleich mit `tapUntil`. `back` und `tapDialog` warten vor dem Tipp ebenso auf einen Treffer (ein Menü, das noch aufgeht, schlösse sich sonst bei einem Tipp daneben ohne Auswahl) und danach selbst (Frist 5 s), bis der getippte Zurück-Knopf bzw. die getippte Dialog-Taste nicht mehr im Baum steht (Seite zu, Dialog oder Menü zu); sonst `Zurück ohne Wirkung` bzw. `Dialog-Taste <key> bleibt` (Zeile `PUB_tap_bleibt`). Bleibt ein Dialog nach einem Tipp bewusst offen, nimmt der Aufrufer `tapKey`/`tapUntil` mit eigener Bedingung. Neue feste `pumpFor`-Pausen nach einem Tipp gibt es nicht; der Abfrageabstand in Warteschleifen ist keine solche Pause.

Tipps mit Wirkungsprüfung laufen über `tapUntil` (`support/e2e_support.dart`). Ihre Bedingung darf nicht werfen: Widgets in lazy Listen (Formulare als `ListView`) lesen sie über `maybeWidget` (fehlt das Widget, gilt die Bedingung als nicht erfüllt); fällt das Ziel aus dem gebauten Bereich, holt der Parameter `reveal` es vor dem erneuten Prüfen zurück. `hittable` gilt bei fehlendem Ziel (Finder leer) als „nicht treffbar“ und wirft nicht; fällt das Ziel in der Warteschleife vor dem Tipp aus dem Baum, holen `tapUntil` (über `reveal`, sonst Pumpen; danach `Taste fehlt: <what>`) und `tapKey` (erneutes `ensureVisible`, sobald es wieder im Baum steht) es zurück (Zeile `PUB_tap_ziel_fehlt`). Die Zeilen `PUB_tap_vor`/`PUB_tap_nach` (`im_baum=ja|nein`) im CI-Log zeigen, ob das Ziel vor und nach dem Tipp im Baum stand; sie tragen nur Schlüsselnamen.

## Lokale Mehrphasentests (Health Connect, nicht in der CI)

Nur der E2E-Agent mit Emulator, je Phase ein Lauf `flutter test integration_test/<datei> -d <serial> --dart-define=...`; die Wächter in `tool/ci_e2e.sh` nehmen beide Dateien aus. Marker im Testlog: `SHOT <name>` (Bildschirmfoto), `HOSTACT <aktion>` (Host-Schritt, der Test wartet 6 s). Außer der ersten Phase immer mit `--no-uninstall`, damit Daten und Schlüssel bleiben. Paket `io.github.brokoskokoli.ramuri`.

- `e2e_health_real_test.dart`: echter Adapter, echter Berechtigungsdialog von Health Connect (API 34+). `--dart-define=HC_MODE=cancel` (Dialog abbrechen) oder `HC_MODE=grant` (Dialog bestätigen); der Host beantwortet den Systemdialog per `adb shell input` nach dem Marker `SHOT`.
- `e2e_health_revoke_test.dart`: Löschfrage beim Öffnen von „Heute“ nach Entzug des Rechts (SEC-0007), mit `--dart-define=HC_PHASE=...`:
  1. `HC_PHASE=1`: Debug-Quelle, Schlaf einwilligen und importieren (erste Phase, mit Neuinstallation ist ok).
  2. Host: `adb shell pm grant io.github.brokoskokoli.ramuri android.permission.health.READ_SLEEP`, dann `HC_PHASE=2 --no-uninstall` (echter Adapter, Recht erteilt: keine Frage).
  3. Host: `adb shell pm revoke io.github.brokoskokoli.ramuri android.permission.health.READ_SLEEP` (beendet den App-Prozess, daher eigene Phase), dann `HC_PHASE=3 --no-uninstall HC_ANSWER=delete|keep` (Frage erscheint; Abbrechen lässt sie offen; Löschen entfernt die Daten, Behalten lässt sie und beendet die Einwilligung).
  4. `HC_PHASE=B`: Debug-Quelle, Zähler je Art im Speicher (Ruhepuls, HRV, VO2max, Schlaf; nicht eingewilligte Art 0). Die Zahl hängt von der UTC-Tageszeit ab (siehe unten).

Die Debug-Quelle liefert je Nacht einen HRV-Wert 20 min nach dem Ende der Schlafphase (06:30 UTC); vor 06:50 UTC liegt der der letzten Nacht in der Zukunft und wird nicht gelesen: HRV 11 statt 12 gespeicherter Werte.

## Bleibt lokal oder offen, und warum

- System-Dateidialog (SAF, Teilen): Systemoberfläche, im Emulator nicht stabil bedienbar; das Archiv wird ohne Dialog über die echte Export-/Restore-Fabrik getestet.
- Echtes Kamera-Recht und echte Kamera, weitere PPG-Szenarien: Hardware; CI nutzt die Fake-Kamera.
- Karte und Einwilligung: im Test nur weggeklickt.
- Auslösen von Erinnerungen durch den System-Wecker zur Weckzeit und Antippen der Benachrichtigung: Systemoberfläche, braucht ein Host-Skript. Einschalten, Uhrzeit und Planung der Morgen-Erinnerung prüft `e2e_morning_test.dart`.
- `storage` mit `PHASE=fill` (Speicher voll): langsam und gerätenah.
- Sichtprüfungen (Layout, Lesbarkeit): Sache des E2E-Agenten.
- Nur im Feld: Hintergrundbetrieb, Akku, echter Brustgurt.

## Ausgabe der Tests: `log`, `logPub`, `step`

Tests geben nur Zähler, Schlüssel und Längen aus, nie Werte (SEC-0001..0010); `ci_e2e.sh` filtert `E2E_`-Zeilen aus Log und Artefakt. Hilfen in `support/e2e_support.dart`:

- `log(...)` schreibt `E2E_<zeit> ...`: alles, was Zähler, Zustände oder Werte trägt (z. B. `S5 reihen=...`). Diese Zeilen sieht nur, wer lokal testet; im öffentlichen CI-Log fehlen sie.
- `step('<name>')` schreibt `PUB_<zeit> SCHRITT <name>` ins öffentliche CI-Log. Jeder Test markiert damit seine Abschnitte (z. B. `READINESS S3 detail`, `HC4 loeschen`, `M2 abschnittswechsel`); Präfix nach Ablauf (`RUN`, `PLAN`, `WARNING`, `ARCHIVE`, `TREADMILL`, `TREADMILL_PLAN`, `RESTING_…`, `MORNING`, `HC…`, `LOCALE`, `RECALC`, `RECOVER_…`, `STORAGE`, `M2`, `READINESS`), damit der Ort in der Sammlung eindeutig ist. Der Name ist immer ein einzelnes Literal, nie aus Daten gebildet; `test/e2e_step_test.dart` weist jeden anderen Aufruf ab (Variable, Interpolation, Verkettung, bedingter Ausdruck) und prüft, dass jede `e2e_*_test.dart` Marken setzt. Unterschiedliche Fälle bekommen je ein eigenes Literal (`if`/`else`).
- `logPub(...)` schreibt `PUB_<zeit> ...` für Zustandsmarker mit Schlüsselnamen (`tap_vor`, `im_baum=ja|nein`) und den Fehlertext ohne Werte (`reportingFailures`); nie Werte.

Ist eine Stufe rot, zeigt der Fehlerabschnitt von `ci_e2e.sh` die letzten `PUB_`-Zeilen und die Zeile `letzter Schritt vor dem Fehler: ...` (letzte Schrittmarke vor dem ersten fehlgeschlagenen Test der Stufe).

## Bildschirmfotos: `E2E_SHOTS=1`

`shot(t, '<name>')` (`support/e2e_support.dart`) schreibt die Marke `SHOT <name>` als `E2E_`-Zeile (also nicht im öffentlichen CI-Log). Mit `E2E_SHOTS=1 sh tool/ci_e2e.sh <ausgabe>` reicht das Skript `--dart-define=E2E_SHOTS=true` an jede Stufe weiter; der Test hält die Seite dann bei jeder Marke 2,5 s, und der Host macht in dieser Zeit genau ein Foto `<ausgabe>/shots/<stufe>-<name>.png` (z. B. `sammlung-s3_morgenwerte_marken_dunkel.png`). Der Name besteht nur aus `[a-z0-9_-]`, sonst verwirft der Host die Marke (Meldung ohne Namen im Log). Am Ende jeder Stufe steht `FOTOS Stufe <stufe>: <anzahl>` im Log. Hell und dunkel schaltet der Test selbst (`platformBrightnessTestValue`, Fotos `..._hell`/`..._dunkel`). Ohne Schalter gibt es weder Fotos noch Pausen; ein anderer Wert als `1` ist ein Fehler. Die Tests der lokalen Health-Connect-Abläufe (`e2e_health*_test.dart`) halten bei `SHOT` immer (`pause: true`), weil der Host dort nach der Marke den Systemdialog bedient. Die Fotos zeigen nur synthetische Daten der Tests (SEC-0001..0010) und gehören nicht ins Repo.
