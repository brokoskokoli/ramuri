# Research – Regeln für dieses Verzeichnis

Hier liegen alle Analysen, die nicht direkt Code der App sind: Messungen, Vergleiche (z. B. Spracherkennungs-Engines), Machbarkeitsprüfungen, Modelltrainings. Zuständig ist je Auftrag ein Research Supervisor (Agent `research-supervisor`): Der Researcher (Agent und Skill `researcher`) bearbeitet den Auftrag, der Research Reviewer (Agent und Skill `research-reviewer`) prüft Methodik, Ergebnisse und Dokumentation. Diese Regeln gelten für jeden, der hier arbeitet, Mensch oder Agent.

**Oberstes Ziel: Ein Mensch versteht jede Analyse ohne Vorwissen und kann sie selbst wiederholen.**

## Aufbau

```
research/
  CLAUDE.md              diese Regeln
  README.md              Index aller Analysen (eine Zeile je Analyse)
  DATA.md                Katalog: was in data/ liegen kann, wer es liefert (in Git)
  init-all.sh            ruft das init.sh aller Analysen auf (stellt data/ komplett her)
  _shared/paths.sh       gemeinsame Pfade und Hilfsfunktionen für alle Skripte
  _template/             Vorlage für einen neuen Analyseordner (README, RESULTS, init.sh, run.sh)
  input/                 NICHT wiederherstellbar: das einzige Verzeichnis, das gesichert werden muss
    README.md              Index aller Sammlungen (in Git)
    <sammlung>/            z. B. stimme-maintainer-2026-10/
      README.md              Beschreibung der Sammlung (in Git)
      …                      die Dateien selbst (NICHT in Git)
  data/                  wiederherstellbar: NICHT in Git, darf jederzeit komplett gelöscht werden
    INDEX.md               Ist-Stand: was gerade wirklich da liegt (automatisch von init.sh)
    models/<name>/         geteilt: heruntergeladene oder trainierte Modelle
    datasets/<name>/       geteilt: heruntergeladene oder abgeleitete Datensätze
    work/Rnnn/             Zwischen- und Laufausgaben einer Analyse (Logs, Zwischenstände)
  R001-<slug>/
    README.md            Auftrag: Frage, Hintergrund, Methode, Daten, Ausführung
    RESULTS.md           Ergebnis: Zahlen, Bewertung, Zweifel, Empfehlung
    init.sh              stellt alles her, was die Analyse in data/ braucht
    run.sh               Kommando, das die Analyse ausführt
    src/                 Analysecode (falls nötig, vom Researcher selbst geschrieben)
    requirements.txt     bzw. andere Abhängigkeiten, mit Versionen
    figures/             kleine Ergebnisgrafiken, die RESULTS.md zeigt (in Git)
```

- **Neue Analyse:** `research/_template/` nach `research/Rnnn-<slug>/` kopieren und ausfüllen.
- **Ein Ordner je Analyse:** `Rnnn-<slug>`, fortlaufend dreistellig nummeriert, Slug kurz und sprechend (`R001-stt-vergleich-de`). Nummern werden nie neu vergeben.
- **Folgeanalysen** bekommen einen eigenen Ordner und verweisen auf den Vorgänger. Eine abgeschlossene Analyse wird nicht umgeschrieben; Korrekturen stehen datiert als Nachtrag in ihrer `RESULTS.md`.
- **Erst nachsehen, dann laden:** Bevor eine Analyse Daten beschafft, liest sie `input/README.md`, `DATA.md` und `data/INDEX.md`. Was schon da ist, wird genutzt, nicht ein zweites Mal geladen oder aufgenommen.

## Daten: wiederherstellbar oder nicht
Jede Datei gehört in genau eine von zwei Klassen:

1. **Nicht wiederherstellbar** (z. B. WAV-Aufnahmen des Maintainers, manuell erstellte Annotationen, Testprotokolle): liegt in `research/input/<sammlung>/`. Alle Analysen dürfen sie lesen. Sie werden **nie automatisch gelöscht, verändert oder überschrieben**, von keinem Skript; Skripte lesen nur. Die Dateien sind nicht in Git (private Daten, Größe), die Sicherung liegt beim Maintainer: `research/input/` ist das einzige Verzeichnis, das er sichern muss.
2. **Wiederherstellbar** (Downloads, Modelle, abgeleitete Daten, Trainingsergebnisse, Zwischenausgaben, Logs): liegt in `research/data/`. Dieses Verzeichnis ist **wegwerfbar**: Wird es gelöscht, stellt `./init.sh` der jeweiligen Analyse (bzw. `research/init-all.sh` für alle) alles Nötige wieder her, und `./run.sh` erzeugt den Rest neu. Große Dateien sind hier ausdrücklich in Ordnung. Auch aus `input/` abgeleitete Daten (z. B. geschnittene oder umgerechnete Aufnahmen) gehören hierher, nicht nach `input/`.

Geteilt wird über `data/models/` und `data/datasets/`: Brauchen mehrere Analysen dasselbe Modell, laden sie es an dieselbe Stelle und nutzen es gemeinsam. Der Unterordnername enthält die Version bzw. Variante (`whisper-small-v3`), damit nichts still ausgetauscht wird. Was nur eine Analyse betrifft, liegt unter `data/work/Rnnn/`.

**Pfade immer über `_shared/paths.sh`.** Analysen laufen in Worktrees (`../<projekt>-wt/rNNN`). Dort gibt es weder `data/` noch die Dateien in `input/`. `paths.sh` zeigt deshalb immer auf den Haupt-Checkout: `$RESEARCH_DATA` (Standard `<Haupt-Checkout>/research/data`, per Umgebungsvariable überschreibbar), `$RESEARCH_INPUT` (`<Haupt-Checkout>/research/input`) und `research_input <sammlung>` für eine Sammlung.

## Inhaltsverzeichnisse
Niemand soll raten müssen, was in `input/` oder `data/` liegt. Agenten lesen die Verzeichnisse über diese Dateien, nicht durch Herumstöbern.

**`input/README.md`** (in Git): eine Zeile je Sammlung: Name, Inhalt in einem Satz, Umfang (Anzahl, Dauer, Größe), Datum, privat ja/nein, genutzt von (Analysen).

**`input/<sammlung>/README.md`** (in Git) beschreibt die Sammlung so, dass man sie ohne Reinhören versteht:
- Was ist es, wer hat es erstellt, wann, wie (Gerät, Umgebung, Vorgehen).
- Format (z. B. WAV, 16 kHz, mono), Dateibenennung, Anzahl, Gesamtdauer bzw. -größe.
- Inhalt je Datei, wenn nötig als Tabelle oder Begleitdatei (z. B. `transkript.csv` mit Dateiname und gesprochenem Text).
- Privat ja/nein und erlaubte Nutzung (z. B. „nur lokal für Analysen, nie ins Training eines geteilten Modells“).
- Welche Analysen sie nutzen.

Eine Sammlung wird nur mit README angelegt. Legt der Maintainer Dateien ohne README ab, schreibt der Researcher sie (nach Rückfrage, was es ist) und ergänzt den Index. Da `input/` nur im Haupt-Checkout existiert, werden diese README-Dateien **dort auf `main` committet**, und zwar nur sie (`git commit -- research/input/…`, Nachricht `docs(input): <sammlung>`). Das ist die einzige Ausnahme vom Grundsatz „Research committet nur auf dem eigenen Branch“.

**`DATA.md`** (in Git): Katalog aller Modelle und Datensätze, die ein `init.sh` nach `data/` liefern kann: Pfad unter `data/`, Version, Quelle/Lizenz, ungefähre Größe, welches `init.sh` ihn herstellt, welche Analysen ihn nutzen. Wer ein `init.sh` um einen neuen Eintrag erweitert, ergänzt den Katalog im selben Commit.

**`data/INDEX.md`** (nicht in Git, automatisch): Ist-Stand, was gerade wirklich in `data/` liegt (Pfad, Beschreibung, Größe, hergestellt von, Datum). Jedes `init.sh` trägt alles, was es herstellt, mit `research_register` aus `paths.sh` ein. Wird `data/` gelöscht, verschwindet der Index mit und entsteht beim nächsten `init.sh` neu. Zwischenausgaben unter `work/` werden nicht einzeln eingetragen.

## init.sh (Daten herstellen)
- Stellt alles her, was die Analyse in `data/` braucht: lädt Modelle und Datensätze, bereitet sie vor, trägt jeden Eintrag mit `research_register` in `data/INDEX.md` ein. Prüft, ob die benötigten Sammlungen in `input/` vollständig sind, und sagt klar, was fehlt (ändert dort nichts).
- **Idempotent:** Vorhandenes wird erkannt (Prüfsumme oder `.done`-Marker) und nicht neu geladen. Mehrfaches Aufrufen ist gefahrlos, auch wenn andere Analysen dieselben Dateien schon geladen haben.
- Feste Versionen bzw. Prüfsummen für Downloads, damit eine Wiederherstellung dieselben Daten liefert.
- `./init.sh --help` beschreibt, was geladen wird, wohin und wie groß es ungefähr ist.
- `research/init-all.sh` ruft alle `init.sh` nacheinander auf.

## README.md (der Auftrag)
Pflichtabschnitte:
1. **Frage:** Was soll geklärt werden, in 1–3 Sätzen. Welche Entscheidung hängt daran.
2. **Auftraggeber und Datum:** wer gefragt hat (Maintainer, Project Supervisor, Arbeitspaket WPnn).
3. **Hintergrund:** Bezug zum Konzept bzw. zum Arbeitspaket, frühere Analysen.
4. **Methode:** Vorgehen, Daten (Herkunft, Umfang, Lizenz), Metriken, Vergleichsbasis. Warum diese Methode aussagekräftig für die Entscheidung ist.
5. **Daten:** welche Sammlungen aus `input/` genutzt werden (mit Verweis auf deren README) und was `init.sh` nach `data/` holt (mit Größe, Verweis auf `DATA.md`).
6. **Ausführung:** Voraussetzungen (Software, Hardware, Rechenzeit), dann `./init.sh` und das Kommando `./run.sh` mit **allen Parametern und Standardwerten** in einer Tabelle und mindestens einem vollständigen Beispiel. Wo die Ausgaben landen.
7. **Status:** `geplant` · `läuft` · `abgeschlossen` · `abgebrochen` (mit Grund).

## run.sh (das Kommando)
- Einstiegspunkt für jede Ausführung, aus dem Analyseordner aufrufbar: `./run.sh [Parameter]`.
- `./run.sh --help` gibt alle Parameter mit Standardwerten aus, gleichlautend zur Tabelle in der README.
- Bricht bei Fehlern ab (`set -euo pipefail`), prüft Voraussetzungen und verweist bei fehlenden Daten auf `./init.sh`.
- Schreibt Ausgaben nach `$RESEARCH_DATA/work/Rnnn/<lauf-kennung>/`, nie über alte Läufe drüber. Kleine Ergebnisgrafiken für `RESULTS.md` kommen nach `figures/`.
- Zufall mit festem Seed (als Parameter). Versionen von Modellen und Bibliotheken werden im Lauf mitgeloggt.
- Lange Läufe (Training, große Messungen) sind fortsetzbar: per `nohup` mit Log, PID und `.done`-Markern; „fertig“ wird erst nach Exit 0 geschrieben.

## RESULTS.md (das Ergebnis)
Pflichtabschnitte:
1. **Kurzfassung (ganz oben):** ein Absatz in Alltagssprache, höchstens ~10 Sätze, für jemanden, der nur diesen Absatz liest. Erst die Antwort auf die Frage, auch wenn sie nur „Ja, mit Verfahren X geht es“ heißt, dann die **Empfehlung** und die wichtigste Einschränkung. Keine Abkürzungen ohne Erklärung, keine Tabellen, keine Befundnummern und keine Nachbesserungsgeschichte (die steht weiter unten). Nach jeder Nachbesserung neu schreiben, nicht ergänzen.
2. **Lauf:** Datum, exaktes Kommando mit Parametern, Commit, Umgebung (Rechner, Versionen), Laufzeit.
3. **Ergebnisse:** Zahlen als Tabelle, mit Stichprobengröße und Unsicherheit (Intervalle, Streuung). Grafiken als Datei in den Ordner, wenn sie helfen.
4. **Bewertung und Zweifel:** Wie belastbar ist das? Was könnte das Ergebnis verfälschen (Datenleck, zu kleine Stichprobe, ungleiche Bedingungen, Messfehler)? Was wurde geprüft (Stichproben selbst angesehen)?
5. **Offene Punkte und Folgeanalysen.**

## Rechenserver (CPU-aufwendige Läufe)
Konfiguration: `research/compute.env` (Host aus `~/.ssh/config`, Zielordner, Priorität, Thread-Grenze; keine Secrets). Werkzeug: `research/_shared/remote.sh` (`--help` ohne Argumente).

- **Wann auf den Server:** Läufe, die den Mac spürbar auslasten: länger als ~10 Minuten mehr als 2 Kerne, Trainings, große Benchmarks, Raster über viele Einstellungen. Kurze Proben, `--help`, kleine Beispielläufe und Läufe mit API-Schlüsseln bleiben lokal (Schlüssel werden nie auf den Server übertragen).
- **Gleiche Struktur:** Auf dem Server liegt unter `~/<REMOTE_ROOT>/research/` dieselbe Struktur wie hier (`_shared/`, `Rnnn-<slug>/`, `data/…`), ohne Git. `paths.sh` funktioniert dort genauso.
- **Ablauf:** `remote.sh push <Rnnn-ordner> [--data models/x datasets/y]` → `remote.sh run <Rnnn-ordner> <name> -- ./run.sh …` (gelöst, `nice`, Thread-Grenze, Log und `.done`-Marker unter `data/work/Rnnn/remote/`) → `remote.sh wait …` im Hintergrund → `remote.sh fetch <Rnnn-ordner>` holt `data/work/Rnnn/` zurück, `remote.sh pull <Rnnn-ordner> figures/` holt Dateien des Analyseordners an denselben Ort zurück.
- **Ergebnisse liegen hier:** `RESULTS.md`, Grafiken und alles, was in Git gehört, entstehen bzw. landen im lokalen Analyseordner und werden hier committet. Rohdaten kommen nach `research/data/work/Rnnn/` (wie lokal, nicht in Git). Der Server ist nur Rechenort, keine Ablage.
- **Daten:** Was `init.sh` auf dem Server nicht herstellen kann (z. B. mit macOS `say` erzeugte Sätze), wird per `push --data` hochgeladen. Die venv entsteht auf dem Server per `init.sh` neu (`uv` liegt dort in `~/.local/bin`).
- **Zeitmessungen:** Ergebnisse vom Server und vom Mac sind nicht vergleichbar. In README und RESULTS steht, wo gemessen wurde (Host, Kerne, Last). Vergleiche innerhalb einer Analyse laufen auf demselben Rechner. Der Server ist geteilt (andere Dienste): Last mitprotokollieren wie lokal.
- Nicht wiederherstellbare Eingaben (`input/`) kommen nur auf den Server, wenn ihre Sammlung das in „erlaubte Nutzung“ zulässt.

## Private Daten
- Eigene Aufnahmen des Maintainers oder anderer Personen nur mit Freigabe und im Rahmen der „erlaubten Nutzung“ ihrer Sammlung verwenden, nur in `input/`, nie in Git, nie in Logs oder `RESULTS.md` zitiert (nur Dateinamen und Kennzahlen).
- Kleine, synthetische oder öffentlich lizenzierte Beispieldaten dürfen ins Repo, wenn die Lizenz es erlaubt (in der README nennen).

## Code
- Der Researcher schreibt den Analysecode selbst. **Code-Qualität ist zweitrangig:** Research-Code muss nicht robust, schön oder getestet sein; stürzt er ab, wird er neu gestartet. Richtig sein muss, was das Ergebnis bestimmt (Kennzahl, Datenauswahl, Messpunkte).
- Geprüft wird vom Research Reviewer die **Methodik**: Beantwortet die Methode die Frage fehlerfrei, tragen die Zahlen die Schlüsse, ist alles nach diesen Regeln dokumentiert und wiederholbar. Code liest er nur, wo er das Ergebnis bestimmt. Urteil als Datei laut `work-packages/REVIEW.md`.
- Analysecode liegt im Analyseordner (`src/`). Wiederverwendbares für mehrere Analysen kommt nach `research/_shared/`, erst wenn es zum zweiten Mal gebraucht wird.
- Kein Research-Code wird von der App (`src/` im Hauptverzeichnis) importiert. Was in die App soll, wird über ein Arbeitspaket übernommen.

## Git
- Jede Analyse läuft (bis auf die README-Dateien in `input/`, siehe oben) auf dem Branch `research/rNNN-<slug>` im Worktree `../<projekt>-wt/rNNN`. Gemergt wird durch den Project Supervisor.
- Commit-Regeln wie im Hauptverzeichnis (`CLAUDE.md`): erlaubte Identität, nur der freigegebene Co-Autor-Trailer.

## Index der Analysen
`research/README.md` hat je Analyse eine Zeile: Nummer, Titel, Frage in einem Satz, Status, Ergebnis in einem Satz. Er wird beim Anlegen und beim Abschluss einer Analyse aktualisiert.
