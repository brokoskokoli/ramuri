# Research-Index

Regeln in [CLAUDE.md](CLAUDE.md). R001 bis R004 stammen aus der Konzeption und liegen als Berichte in `docs/migration/research-reviews/`. Nächste freie Nummer: R008 (R006 ist für den virtuellen Sensor vorgemerkt, R007 für das GPS-Rauschen).

| Nr. | Titel | Für | Ergebnis |
| --- | --- | --- | --- |
| R005 | Durchstich der Aufzeichnung | ADR-0005, ADR-0003, ADR-0006 | abgeschlossen, Review FREIGABE in Runde 3: Punkt 3 trägt im Emulator, Empfehlung `own`, tx 1 mit `FULL`, kein Verlust bestätigter Zeilen in 41 + 14 + 14 harten Kills (vor dem ersten Checkpoint, wiederverwendetes WAL, Zeilen nur in der Hauptdatei; `NORMAL` als Kontrolle verliert), belegt das Überstehen, nicht die Nötigkeit der Checkpoint-Synchronisation, Kill im Checkpoint und Checkpoints von 1000 Frames offen; Partial Wake Lock als Entscheidung des Maintainers; kein Beleg für Geräte ([RESULTS](R005-aufzeichnung-durchstich/RESULTS.md)) |
