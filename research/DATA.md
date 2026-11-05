# Katalog: wiederherstellbare Daten in research/data/

Alles, was ein `init.sh` nach `research/data/` liefern kann. Was davon gerade tatsächlich da ist, steht in `research/data/INDEX.md` (automatisch, nicht in Git). Regeln: `research/CLAUDE.md` → Inhaltsverzeichnisse.

| Pfad unter `data/` | Was, Version | Quelle, Lizenz | Größe ca. | Hergestellt von | Genutzt von |
| --- | --- | --- | --- | --- | --- |
| `work/R005/` | Rohdaten R005: Logs, DB-Kopien, Spuren, `report/` mit Auswertung (Prototyp `54e21e8`) | selbst erzeugt, nur synthetisch | 152 MB | `R005/init.sh` legt an, `R005/run.sh` füllt | R005 |
| `datasets/zenodo-1312834/` | Samsung Galaxy, Stand, GPGGA, 1 Hz | Szot et al. 2019, Zenodo 1312834, CC BY 4.0 | 57 MB | `R007/init.sh` (MD5 aus Zenodo) | R007 |
| `datasets/zenodo-20092798/` | 454 Stand-Sitzungen à 30 s, FIX-Zeilen | Parmar et al. 2026, Zenodo 20092798, CC BY 4.0 | 80 MB entpackt | `R007/init.sh` (MD5 aus Zenodo) | R007 |
| `datasets/zenodo-14712684/` | GNSSLogger Gehen, Rad, Bus u. a. | Medina und Lohan 2025, Zenodo 14712684, CC BY 4.0 | 141 MB, entpackt 690 MB | `R007/init.sh` (MD5 aus Zenodo) | R007 |
| `datasets/mendeley-kybmdyrzb3-v1/` | OnePlus Nord 2T, Stativ, GNSSLogger, Version 1 | Agarwal et al., Mendeley Data, CC BY 4.0 | 565 MB, entpackt 3,4 GB | `R007/init.sh` (Größe geprüft, Mendeley nennt keine Prüfsumme fürs Zip) | R007 |
| `work/R007/` | Laufausgaben: `report.txt`, CSV, normierte Spuren | selbst erzeugt aus den vier Datensätzen | 145 MB | `R007/run.sh` | R007 |
