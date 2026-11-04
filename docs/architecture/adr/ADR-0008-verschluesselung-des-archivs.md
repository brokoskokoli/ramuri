# ADR-0008 — Verschlüsselung des passwortgeschützten Archivs

- **Status:** Proposed
- **Datum:** 2026-11-04
- **Quellen:** SRC-003 (OQ-0032, OQ-0050)
- **Betroffene Anforderungen:** SEC-0009, SEC-0011, FR-0192, FR-0198, CON-0008, OQ-0032, OQ-0050, ADR-0001, ADR-0003, ADR-0004

## Kontext
Der Gesamtexport ist immer mit einem Passwort des Nutzers verschlüsselt und ohne Passwort nicht lesbar (SEC-0011). Der Reimport prüft die Datei, eine beschädigte oder falsche Datei ändert keine Daten (FR-0198). Das Archiv enthält alle Rohdaten (FR-0192), wächst also mit den Läufen ohne bekannte Obergrenze (ADR-0004). Die Datei verlässt das Gerät und kann offline angegriffen werden, ihr Schutz hängt also am Passwort und an der Schlüsselableitung. Das Projekt steht unter GPL-3.0, das Gate läuft lokal.

## Entscheidung
Alle Zahlen sind Vorschläge und werden erst mit der Freigabe verbindlich.

**1. Verschlüsselung:** ChaCha20-Poly1305 (RFC 8439) in Stücken nach dem STREAM-Aufbau von age v1 [1]: Stücke von 64 KiB, die Nonce besteht aus einem 11-Byte-Zähler und einem Byte, das nur beim letzten Stück 1 ist. So fallen Veränderung, Vertauschen und Abschneiden auf; endet die Datei ohne gültiges letztes Stück, ist das ein Fehler [1]. Der Dateikopf geht in jedes Stück als zusätzlich authentifizierte Daten ein. Eine eigene Unterschlüssel-Ableitung entfällt, weil das zufällige Salz je Archiv den Schlüssel einmalig macht. ADR-0003 nutzt für die Datenbank dasselbe Verfahren.

**2. Schlüsselableitung:** Argon2id (RFC 9106) mit 64 MiB, 3 Durchläufen, Parallelität 1, 16 Byte Salz je Archiv und 32 Byte Schlüssel. RFC 9106 nennt 64 MiB und 3 Durchläufe als Vorgabe für knappen Speicher, dort aber mit 4 Spuren [2]; die Parallelität 1 ist eine eigene Wahl für eine feste, einfache Last. Die Werte liegen über den Mindestwerten von OWASP (etwa 46 MiB mit 1 Durchlauf oder 12 MiB mit 3 Durchläufen, jeweils Parallelität 1) [3]. Sie laufen in einem eigenen Isolate, damit die Oberfläche nicht stockt.

**3. Feste Parameter je Formatversion:** Der Kopf nennt Formatversion und Parameter, eine App liest aber nur die zu dieser Version bekannten. Ein manipulierter Kopf kann so keine beliebig große Speicheranforderung auslösen; das age-Format verlangt aus demselben Grund eine Obergrenze [1], und für zu große Argon2-Parameter gibt es im gewählten Paket eine offene Absturzmeldung [4]. Stärkere Parameter kommen als neue Formatversion.

**4. Paket:** `cryptography` 2.9.0 (Apache-2.0, Stand 2025-11-21) [5], genutzt werden nur `DartArgon2id` und `DartChacha20.poly1305Aead`, hinter einem Port, die Umsetzung liegt in `app/packages/adapters` (ADR-0002). Apache-2.0-Code darf in GPL-3.0-Projekte [6]. Die direkten Abhängigkeiten `collection`, `crypto`, `ffi`, `meta` und `typed_data` stehen laut pub.dev unter BSD-3-Clause [5]. Das Paket baut ohne nativen Compiler und läuft in den Host-Tests des Gates. Den Rahmen aus Punkt 1 schreibt das Projekt selbst, deshalb bekommt das Paket feste Testvektoren aus einer unabhängigen Umsetzung.

**5. Umgang mit Klartext und Passwort:** Kein Klartext auf dem Datenträger: Der Export läuft als Strom von der Datenbank über die Kompression zur Verschlüsselung in das vom Nutzer gewählte Ziel. Der Reimport prüft und entpackt in eine neue, mit dem Datenbankschlüssel verschlüsselte Zwischendatenbank und tauscht sie erst nach dem gültigen letzten Stück gegen die aktive (FR-0198). Das Passwort wird nie gespeichert oder geloggt und beim Export zweimal abgefragt, zusammen mit dem Hinweis aus SEC-0011. Falsches Passwort und beschädigter Anfang sind technisch nicht unterscheidbar, die Meldung nennt deshalb beides.

**6. Inhalt:** Datenbankschlüssel, Zugangsdaten und Einwilligungen sind nie enthalten (SEC-0011). Aufbau und Inhalt unter der Verschlüsselung legt das Paket als Vertrag in `docs/contracts/` an (OQ-0032, [Verträge](../../contracts/README.md)).

## Vom Maintainer zu entscheiden
- **A. Paket:** `cryptography` (empfohlen, siehe Punkt 4) oder `sodium`/libsodium (siehe Alternativen). Letzteres heißt: vollständiges Xcode auf dem Entwicklungsrechner oder Kryptografie-Tests nur im Emulator, dafür kein eigener Rahmen.
- **B. Mindestlänge des Passworts:** Die Spec nennt keine. NIST verlangt für ein Passwort als alleinigen Faktor mindestens 15 Zeichen und verbietet Zeichenklassen-Regeln [7]. Empfehlung: 15 Zeichen ohne Klassenregeln, weil die Datei offline angreifbar ist und kein zweiter Faktor existiert. Die dort geforderte Sperrliste häufiger Passwörter [7] schlage ich wegen des Pflegeaufwands nicht vor.
- **C. Neueres Archiv in älterer App:** ADR-0004 lässt das offen. Empfehlung: ablehnen, ohne Daten zu ändern.

## Erwogene Alternativen
- **`sodium` 4.1.2+1 (BSD-3-Clause, Stand 2026-10-27) mit libsodium 1.0.22 (ISC):** Fertiger Strom `crypto_secretstream` mit Schutz gegen Abschneiden [8] und natives Argon2id [9], die stärkste Umsetzung im Vergleich. Der Build-Hook übersetzt libsodium aus dem Quellpaket [10]. Eigener Versuch: Android-APK mit minSdk 31 baut (arm64, Debug, rund 1 Minute, Flutter 3.47.7). `flutter test` scheitert aber auf dem Entwicklungsrechner ohne vollständiges Xcode bereits am Hook, sobald das Paket im Abhängigkeitsgraph liegt, auch für Tests, die es nicht nutzen. Ob es mit Xcode durchläuft, ist nicht geprüft. Der Hook lässt sich per Umgebungsvariable überspringen [10], dann prüft das Gate die Kryptografie nicht.
- **age-Format mit `dartage` 0.3.0 (MIT) oder `rage` 0.1.0 (Apache-2.0):** Ein fremdes Werkzeug könnte das Archiv öffnen, und das Format ist fertig dokumentiert [1]. Beide Pakete sind jung und kaum verbreitet, `rage` verlangt zudem eine Rust-Toolchain; age nutzt scrypt statt Argon2id. Bleibt Option, falls das Öffnen ohne die App gewünscht ist.
- **Archiv als verschlüsselte SQLite-Datei (SQLite3MultipleCiphers, AEGIS mit Argon2id) [11]:** Keine neue Abhängigkeit. Authentifiziert wird je Seite; zum Schutz gegen Abschneiden der ganzen Datei sagt die Dokumentation nichts, und das Archiv hinge am Datenbankformat statt an einem eigenen Vertrag.
- **ZIP mit AES:** Verbreitet, aber PBKDF2 mit 1000 Durchläufen [12] liegt weit unter den 600 000, die OWASP für PBKDF2-SHA256 nennt [3].
- **`pointycastle` 4.0.0 (MIT, Stand 2025-02-19):** Lizenz passt, älterer Stand als `cryptography`, gleicher Bedarf an einem eigenen Rahmen.
- **`hashlib` 2.4.2 (BSD-3-Clause):** Eigene Argon2-Umsetzung, aber keine Verschlüsselung [13]; im Vergleich unten nur als Gegenprobe genutzt.
- **AES-256-GCM:** Gleichwertig als Verfahren, aber ohne Hardwarebeschleunigung im reinen Dart ohne Vorteil, und ein zweites Verfahren neben ADR-0003 bringt nichts.
- **Scrypt oder PBKDF2 statt Argon2id:** OWASP führt Argon2id zuerst [3]; ein eigener Grund für die älteren Verfahren besteht nur beim age-Format.

## Konsequenzen
- Kein Compiler und keine Xcode-Pflicht; die Kryptografie läuft in jedem Gate-Lauf mit.
- Der STREAM-Rahmen ist eigener Sicherheitscode. Er bleibt klein, folgt einem veröffentlichten Aufbau und braucht Mutationsbelege (REVIEW.md).
- `cryptography` hatte seit fast einem Jahr keine Veröffentlichung, das Repository zeigt 37 offene Punkte. Der Port begrenzt die Kosten eines Wechsels, die Formatversion erlaubt ihn auch für neue Archive.
- Dart-Strings lassen sich nicht überschreiben; das Passwort kann also kurz im Speicher bleiben. Das schützt nicht gegen ein kompromittiertes, entsperrtes Gerät (wie ADR-0003).
- Ohne Passwort gibt es keinen Rettungsweg, darauf weist die App hin (SEC-0011).
- Das Archiv lässt sich außerhalb der App nur mit dem dokumentierten Format und eigenem Werkzeug öffnen.

## Eigene Messung
Auf dem Entwicklungsrechner (Apple Silicon, Dart 3.13.5, JIT, 2026-11-04), einmalig, also nur zur Größenordnung: Argon2id mit den Werten aus Punkt 2 dauerte 467 ms mit `cryptography` und 218 ms mit `hashlib`; beide lieferten denselben Schlüssel. ChaCha20-Poly1305 mit `cryptography` schaffte 10 MiB in 64-KiB-Stücken in 289 ms. Auf einem Telefon mit AOT sind andere Werte zu erwarten.

## Im Emulator nicht belegbar
Dauer und Speicherdruck von Argon2id auf schwachen Geräten, Abbruch durch das System bei wenig freiem Speicher, Dauer bei einem Archiv aus vielen echten Läufen und der Wechsel auf ein echtes zweites Gerät. Prüfbar sind Hin- und Rückweg mit synthetischen Daten, alle Fehlerfälle und die Dauer im Emulator als grobe Größe.

## Offene Punkte
Der Lizenzbaum ist nur für die direkten Abhängigkeiten geprüft; den vollständigen Baum prüft das Archivpaket wie in ADR-0002 beschrieben. Unter einer Rechtsprüfung stand die Einschätzung zur GPL-Verträglichkeit nicht (OQ-0048). Ob die feste Dauer von Argon2id auf dem schwächsten Zielgerät zumutbar ist, zeigt erst ein Feldtest; dann gäbe es eine neue Formatversion.

## Belege (Abruf 2026-11-04)
[1] https://github.com/C2SP/C2SP/blob/main/age.md ·
[2] https://www.rfc-editor.org/rfc/rfc9106.html ·
[3] https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html ·
[4] https://github.com/dint-dev/cryptography/issues/177 ·
[5] https://pub.dev/packages/cryptography (Metadaten, `LICENSE` im Archiv 2.9.0) ·
[6] https://www.apache.org/licenses/GPL-compatibility.html ·
[7] https://pages.nist.gov/800-63-4/sp800-63b.html (Abschnitt 3.1.1) ·
[8] https://doc.libsodium.org/secret-key_cryptography/secretstream ·
[9] https://doc.libsodium.org/password_hashing/default_phf ·
[10] https://pub.dev/packages/sodium (`README.md`, `hook/build.dart` im Archiv 4.1.2+1) ·
[11] https://utelle.github.io/SQLite3MultipleCiphers/docs/ciphers/cipher_aegis/ ·
[12] https://www.winzip.com/en/support/aes-encryption/ ·
[13] https://pub.dev/packages/hashlib
