# WP30 – Release-Pipeline: signierte APK und AAB per Tag

**Zuordnung:** Werkzeuge, nach WP23/WP25 (Auftrag des Maintainers vom 2026-11-13). Keine Funktion der App ändert sich.

Bezug: DEC-0071 und OQ-0048 (Release erst nach rechtlicher Prüfung), `tool/gate.sh` (Release-Prüfung `release_rechte`), `.github/workflows/gate.yml`, `tool/hooks/pre-push`. Allgemeine Regeln: [M2-PLAN.md](M2-PLAN.md).

## Anlass
Der Maintainer will signierte Builds per Tag: `v0.1.0` baut eine Version, `v0.1.0-rc1` einen Release-Kandidaten. Heute signiert der Release-Build mit dem Debug-Schlüssel (`app/android/app/build.gradle.kts`, `signingConfig = debug`), und die GitHub-CI ist seit WP29 rot, weil `tool/gate.sh` `/usr/bin/lockf` aufruft, das es auf Linux nicht gibt (Exit 127).

## Entscheidungen (Maintainer und Orchestrator, 2026-11-13)
- **Ablage:** Jeder Tag erzeugt ein GitHub-Release **als Entwurf** (nur für Leute mit Schreibrecht sichtbar). Veröffentlicht wird von Hand, frühestens nach OQ-0048. Die Pipeline veröffentlicht nie selbst. Keine Workflow-Artefakte mit der APK (bei einem öffentlichen Repo für alle angemeldeten Nutzer ladbar).
- **Tag-Format:** `v<MAJOR>.<MINOR>.<PATCH>` oder `v<MAJOR>.<MINOR>.<PATCH>-rc<N>` mit N von 1 bis 98. Andere Tags `v*` bricht der Workflow mit klarer Meldung ab. Ein RC wird als Pre-Release markiert.
- **Version:** `versionName` = Tag ohne `v`. `versionCode` = MAJOR·1 000 000 + MINOR·10 000 + PATCH·100 + (N beim RC, 99 bei der Version), damit jeder RC unter seiner Version liegt und jede neue Version darüber. Übergabe per `flutter build --build-name/--build-number`; `pubspec.yaml` bleibt unverändert.
- **Schlüssel (vom Orchestrator angelegt, nicht Teil des Codes):**
  - Keystore PKCS12 lokal in `~/.ramuri-android-keys/release.jks`, Alias `ramuri`, Store- und Schlüsselpasswort gleich.
  - Im macOS-Schlüsselbund unter Dienst `ramuri-release-signing`, Konten `store-password` und `keystore-base64`.
  - Auf GitHub in der Umgebung `release` (nur Tags `v*` dürfen sie nutzen): `SIGNING_KEYSTORE_BASE64`, `SIGNING_STORE_PASSWORD`, `SIGNING_KEY_PASSWORD`, `SIGNING_KEY_ALIAS`.
  - SHA-256 des Zertifikats: `1c7e8472f5e705814fe65808ad7f506f903e198f4ba8543a97bbb0f4d4b602c5`.

## Inhalt
1. **Gradle (Teil A):** `signingConfigs.release` aus Umgebungsvariablen (`SIGNING_STORE_FILE`, `SIGNING_STORE_PASSWORD`, `SIGNING_KEY_ALIAS`, `SIGNING_KEY_PASSWORD`). Ohne diese Variablen bleibt es wie heute (Debug-Signatur), damit Gate und lokale Builds ohne Schlüssel laufen. Kein Geheimnis in Dateien des Repos, kein `key.properties`.
2. **Build-Skript (Teil A):** `tool/build_signed.sh <tag>` für lokal und CI gleich:
   - prüft das Tag-Format und rechnet `versionName`/`versionCode`;
   - nimmt die Secrets aus der Umgebung, sonst lokal aus dem Schlüsselbund (`security find-generic-password -s ramuri-release-signing -a … -w`); schreibt den Keystore nur in eine temporäre Datei, die per `trap` immer gelöscht wird;
   - baut Release-APK und AAB, prüft die APK mit `apksigner verify --print-certs` gegen den festen SHA-256 oben (sonst Abbruch), führt die bestehende Release-Prüfung des Gates (`release_rechte` bzw. derselbe Prüfcode) auf genau dieser APK aus;
   - legt `dist/ramuri-<version>.apk`, `.aab` und `SHA256SUMS.txt` ab (`dist/` in `.gitignore`);
   - gibt nie ein Secret aus (kein `set -x`, keine Secrets als Kommandozeilenargument).
3. **Workflow (Teil B):** `.github/workflows/release.yml`, Auslöser `push: tags: ['v*']`, Umgebung `release`, Rechte nur `contents: write` im Job (sonst `read`), Actions per Commit-SHA gepinnt (Kommentar = Tag). Ablauf: Tag prüfen, Flutter einrichten (Version aus `app/pubspec.yaml` wie in `gate.yml`), volles Gate, `tool/build_signed.sh`, Entwurf-Release anlegen oder aktualisieren (`gh release create --draft --verify-tag`, RC mit `--prerelease`, Titel `ramuri <version>`, Text mit `--generate-notes`), Dateien hochladen. Fork-Schutz `if: github.repository == 'brokoskokoli/ramuri'`.
4. **Gate unter Linux (Teil B):** `tool/gate.sh` nimmt den Lock mit `/usr/bin/lockf`, wo vorhanden, sonst mit `flock`; gibt es beides nicht (oder `CI=true`), läuft es ohne Lock. Verhalten auf macOS unverändert. `gate.yml` muss danach auf GitHub grün werden. Was sonst unter Linux scheitert, gehört dazu (nur Werkzeug, keine Prüfung abschwächen).
5. **Pre-Push (Teil B):** Ein Tag `v*` darf nur auf einen Commit zeigen, der schon in `origin/main` liegt; sonst lehnt der Hook ab. Andere Regeln unverändert.
6. **README (Teil C):** Abschnitt „Releases“: Tag-Formate mit Beispiel, was die Pipeline tut, wo das Ergebnis liegt (Entwurf), wie man lokal signiert baut (`tool/build_signed.sh v0.1.0-rc1`), Zertifikat-SHA-256 zum Prüfen der APK, Namen (nicht Werte) der Secrets und wie man sie neu setzt. Die veraltete Zeile „Es gibt noch keinen Code“ im Projektstatus durch den heutigen Stand ersetzen.

## Umsetzung
- Teile A, B, C je ein Coder-Auftrag; ein Review über alles, Schwerpunkt Geheimnisse.
- Keine neue Abhängigkeit in `pubspec.*`. Keine Änderung am Verhalten der App.
- Den lokalen signierten Build (`tool/build_signed.sh v0.1.0-rc1`) führt die Sitzung einmal aus; er liest den Schlüsselbund. Kein Tag setzen und nicht pushen: Den Tag `v0.1.0-rc1` setzt der Orchestrator nach dem Merge.

## Abnahmekriterien
- [ ] Lokal: `tool/build_signed.sh v0.1.0-rc1` erzeugt APK und AAB; `apksigner` zeigt den SHA-256 oben; `aapt2 dump badging` zeigt `versionName='0.1.0-rc1'` und `versionCode='10001'`; Release-Prüfung grün.
- [ ] Falsches Tag-Format, fehlendes Secret und eine mit dem Debug-Schlüssel signierte APK brechen ab (Beleg je Fall).
- [ ] Ohne Signatur-Variablen baut das Gate wie bisher (volles Gate grün).
- [ ] Kein Secret in Logs, Dateien des Repos oder Kommandozeilen (Review prüft Skript und Workflow, Beleg: Ausgabe eines Laufs ohne Treffer auf das Passwort).
- [ ] `tool/gate.sh` läuft auf Linux (Beleg: Lauf in einem Linux-Container oder Begründung, warum der Lauf erst auf GitHub belegt wird); auf macOS gilt der Lock weiter.
- [ ] Pre-Push lehnt einen Tag auf einem Commit außerhalb von `origin/main` ab (Beleg).
- [ ] README-Abschnitt „Releases“ vorhanden.
