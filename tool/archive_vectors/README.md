# Testvektoren für das Archivformat

`make_vectors.py` erzeugt Testvektoren für `docs/contracts/archive.md` (WP12). Es wurde nur nach dem Vertragstext geschrieben, ohne den Dart-Code zu lesen, und ist damit eine unabhängige zweite Umsetzung. Alle Daten sind synthetisch; Passwörter und Salze sind fest, die Ausgabe ist byte-reproduzierbar (gzip mit `mtime=0`).

## Aufruf

```sh
python3 -m venv <venv>
<venv>/bin/pip install cryptography==50.0.2
<venv>/bin/python -I tool/archive_vectors/make_vectors.py --out app/packages/adapters/test/archive/vectors
```

Das Skript prüft zuerst die Bibliothek gegen öffentliche Referenzvektoren (RFC 9106 Abschnitt 5.3 für Argon2id, RFC 8439 Abschnitt 2.8.2 für ChaCha20-Poly1305) und bricht sonst ab. Dauer unter einer Sekunde.

## Bibliotheken

| Bibliothek | Version | Lizenz | Zweck |
|---|---|---|---|
| pyca/cryptography | 50.0.2 | Apache-2.0 OR BSD-3-Clause | Argon2id (`kdf.argon2`), ChaCha20-Poly1305 |
| Python Standardbibliothek | 3.15.0 | PSF | gzip, json, hashlib, struct |

Ein Schlüssel (`short`) wurde zusätzlich mit der Referenzimplementierung `argon2` (C, Homebrew) gegengerechnet: gleich.

## Ausgabe

- `vectors.json`: je Vektor Passwort (und UTF-8 hex), Salz, erwarteter Schlüssel (hex), Kopf (hex), Klartextlänge und SHA-256, Stückzahl, Erwartung (`ok` oder Fehlerklasse).
- `<name>.runarchv`: die Archivdatei; `<name>.plain`: der Klartext (bei `archive_small` das gzip-Element), `archive_small.jsonl`: das entpackte JSON Lines.
- Format 2 (WP19 C0): `archive_v2` (Kopf Version 2, Manifest Format 2/Schema 5, 21 Abschnitte, `run_feedback` und `manual_trainings` mit einem Training genau auf "heute" 2026-11-20; Feld `today` im `vectors.json`) und `neg_v2_training_after_today` (Rahmen gültig, Training einen Tag später; `layer: content`, erwartet `corrupt` vom Leser, nicht von der Verschlüsselung). Die Format-1-Vektoren bleiben byte-gleich.
- Format 2 mit Schema 6 (WP20): `archive_v2_s6` (Kopf Version 2, Manifest Format 2/Schema 6, 23 Abschnitte; `reference_performances` mit drei Zeilen, darunter ein bestätigter Lauf mit `run_id` 1, und `rejected_suggestions` mit einer Zeile; Feld `today` wie bei `archive_v2`). Die übrigen Vektoren bleiben byte-gleich.
- Format 2 mit Schema 7 (WP21): `archive_v2_s7` (Kopf Version 2, Manifest Format 2/Schema 7, 23 Abschnitte wie Schema 6; Abschnitt 19 `goals` mit einer Zeile, ein Zeitziel über 10 km; 20 und 21 bleiben leer; Feld `today` wie bei `archive_v2`). Die übrigen Vektoren bleiben byte-gleich.
- Format 2 mit Schema 8 (WP22): `archive_v2_s8` (Abschnitte wie Schema 7, `plan_units` mit der Spalte `fixed` und vier Zeilen: `none`, `day` (Ruhetag), `kind` (ersetzte Art) und `easyForHard` (harte Einheit locker ersetzt, `kind` = `easy`)). Die übrigen Vektoren bleiben byte-gleich.
- Format 2 mit Schema 9 (WP26): `archive_v2_s9` (Manifest Format 2/Schema 9, 25 Abschnitte; `raw_rr_packets` mit drei Zeilen, `rr` als kleingeschriebener Hex-Text von uint16 little-endian, Randwerte 0 und 65535, zwei Quellgeräte). Die übrigen Vektoren bleiben byte-gleich (geprüft: Neuerzeugung ergibt für alle bisherigen Dateien dieselben Bytes).
- Positiv: `empty`, `short`, `exact_65536`, `exact_65537`, `multi_150k`, `exact_131072`, `archive_small` (alle 19 Abschnitte, Lauf mit `original` und `current`, unbekannter `value_key`).
- Negativ (`neg_*`): Abschneiden an Stückgrenze, angehängtes Byte, vertauschte Stücke, gekippte Bits, nur Kopf, volles Stück mit leerem Stück danach, volles Stück mit Flag 0, Formatversion 3, Speicher 1024 KiB, falsches Magic, 20-Byte-Datei. Fehlerklassen: `wrong_password_or_start_damaged`, `corrupt`, `unknown_version`, `unsupported_parameters`, `not_an_archive`.
- Passwörter: auch Umlaute/€, ein nicht normalisiertes (NFD) und ein leeres (`exact_131072`, nur als Formatvektor).

Alle Vektoren außer `archive_v2`, `archive_v2_s6`, `archive_v2_s7`, `archive_v2_s8` und `neg_v2_training_after_today` sind Format 1 (Kopf `0001`, Schema 4, 19 Abschnitte), von der unabhängigen Umsetzung vor WP18 erzeugt. Sie belegen, dass Format 1 nach der Einführung von Format 2 lesbar bleibt (WP18). Bis auf `neg_version_3` (vorher `neg_version_2`, seit Format 2 gültig) unverändert.
