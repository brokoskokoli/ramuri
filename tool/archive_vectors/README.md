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
- Positiv: `empty`, `short`, `exact_65536`, `exact_65537`, `multi_150k`, `exact_131072`, `archive_small` (alle 19 Abschnitte, Lauf mit `original` und `current`, unbekannter `value_key`).
- Negativ (`neg_*`): Abschneiden an Stückgrenze, angehängtes Byte, vertauschte Stücke, gekippte Bits, nur Kopf, volles Stück mit leerem Stück danach, volles Stück mit Flag 0, Formatversion 2, Speicher 1024 KiB, falsches Magic, 20-Byte-Datei. Fehlerklassen: `wrong_password_or_start_damaged`, `corrupt`, `unknown_version`, `unsupported_parameters`, `not_an_archive`.
- Passwörter: auch Umlaute/€, ein nicht normalisiertes (NFD) und ein leeres (`exact_131072`, nur als Formatvektor).
