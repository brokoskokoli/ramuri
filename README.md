# ramuri – Adaptive Running & Fitness App

Android-App (später optional iOS) für Laufaufzeichnung, Fitnessanalyse, Regeneration und adaptive Trainingsplanung. Sie funktioniert ohne Wearable und ohne Bindung an einen Gerätehersteller.

**Projektstatus:** Die Phasen 1 bis 3 sind spezifiziert und vom Maintainer freigegeben. Die App liegt in `app/`: Phase 1 (Laufaufzeichnung und Fitnessanalyse) und Phase 2 (adaptiver Trainingscoach) sind umgesetzt, Phase 3 (erweiterte Gesundheits- und Erholungsanalyse) ist in Umsetzung. Ein Release setzt eine rechtliche Prüfung voraus (OQ-0048).

- [Dokumentation und Spezifikation](docs/index.md)
- [Anforderungsregister](docs/requirements.md)
- [Anweisungen für Agenten](AGENTS.md)

## Releases

Ein Release entsteht aus einem Git-Tag:

- `vX.Y.Z` ist eine Version, z. B. `v0.1.0`.
- `vX.Y.Z-rcN` ist ein Release Candidate, z. B. `v0.1.0-rc1` (N von 1 bis 98).

`versionName` ist der Tag ohne `v` (`0.1.0-rc1`). `versionCode` = MAJOR·1000000 + MINOR·10000 + PATCH·100 + N (RC) bzw. 99 (Version), also `10001` für `v0.1.0-rc1` und `10099` für `v0.1.0`. MINOR und PATCH dürfen höchstens 99 sein, MAJOR höchstens 2000.

Der Push eines Tags startet `.github/workflows/release.yml`. Die Pipeline prüft, dass der Tag auf einen Commit in `main` zeigt und dass der Workflow `e2e` auf genau diesem Commit grün war (läuft er noch, wartet sie bis zu 45 min; sonst ist der Release rot mit „e2e auf <sha> nicht grün“, eine Ausnahme gibt es nicht, siehe [Tests und Abnahme](docs/quality/testing.md)), führt das volle Gate aus und baut APK und AAB mit dem Release-Schlüssel. Sie prüft, dass die APK mit dem Release-Zertifikat signiert ist und die Release-Rechte stimmen, und legt auf GitHub einen **Entwurf** an (ein RC als Pre-Release) mit APK, AAB und `SHA256SUMS.txt`. Sie veröffentlicht nie automatisch; das tut der Maintainer von Hand, bisher nicht vor OQ-0048.

**Lokal bauen:** `tool/build_signed.sh v0.1.0-rc1` legt APK, AAB und Prüfsummen in `dist/` ab. Den Schlüssel nimmt das Skript aus den Umgebungsvariablen der Secrets unten, sonst aus dem macOS-Schlüsselbund (Dienst `ramuri-release-signing`, Konten `store-password` und `keystore-base64`).

**Nightly:** `tool/build_signed.sh --nightly` baut aus dem aktuellen Commit nur die APK `dist/ramuri-nightly.apk` mit `SHA256SUMS.txt` (kein AAB); der Workflow `nightly` benennt sie beim Veröffentlichen in `ramuri-nightly-<JJJJ-MM-TT>-<7 Zeichen Commit>.apk` um (Datum des Laufs in UTC) und schreibt `SHA256SUMS.txt` dafür neu; `tool/build_signed.sh --print-version --nightly` zeigt nur die Version. Basis ist der jüngste Tag `vX.Y.Z` oder `vX.Y.Z-rcN`, der Vorfahre des Commits ist (ohne solchen Tag `0.0.0` mit `versionCode` 1 und einer Zeile `WARNUNG:` auf stderr). Einen flachen Git-Klon lehnt der Nightly mit einem Fehler ab, weil ihm Historie und Tags fehlen (`git fetch --unshallow --tags`). `versionCode` ist der der Basis, so dass jedes spätere RC oder Release als Update angenommen wird. `versionName` ist `<Basis ohne v>-nightly.<JJJJMMTT>+<7 Zeichen Commit>`, das Datum in UTC aus der Commit-Zeit, z. B. `0.1.0-rc1-nightly.20261118+2c61ca1`. Ein Nightly ist ungeprüft. Er wird mit dem Release-Schlüssel signiert und hat dieselbe App-ID, lässt sich also über eine installierte offizielle Version installieren und umgekehrt.

**Nightly auf GitHub:** `.github/workflows/nightly.yml` baut jede Nacht um 02:17 UTC (GitHub startet geplante Läufe teils verspätet; dazu von Hand per `workflow_dispatch`) den aktuellen `main` nach vollem Gate mit `tool/build_signed.sh --nightly` und veröffentlicht die APK als Pre-Release `nightly` (nicht „Latest“) unter <https://github.com/brokoskokoli/ramuri/releases/tag/nightly> mit den Anhängen `ramuri-nightly-<JJJJ-MM-TT>-<7 Zeichen Commit>.apk` (Datum des Laufs in UTC, z. B. `ramuri-nightly-2026-11-21-25a0d66.apk`) und `SHA256SUMS.txt`. Zeigt der Tag `nightly` schon auf den Kopf von `main`, überspringt der nächtliche Lauf den Build; ein Lauf von Hand baut immer. Es gibt nur einen Nightly: Nach grünem Gate und Build werden das vorige Release und der Tag `nightly` gelöscht und das Release jede Nacht neu angelegt, so dass das Veröffentlichungsdatum des Releases der Tag des Laufs ist und kein alter Anhang zurückbleibt. Scheitert der Lauf vor dem Löschen, bleibt der vorige Nightly unverändert; scheitert erst das Anlegen, gibt es bis zum nächsten Lauf keinen Nightly, und der nächste nächtliche Lauf baut neu. Die APK prüfst du wie unten mit `apksigner verify --print-certs ramuri-nightly-<Datum>-<Commit>.apk`.

**APK prüfen:** `apksigner verify --print-certs dist/ramuri-0.1.0-rc1.apk` muss diesen SHA-256 des Zertifikats zeigen:

`1c7e8472f5e705814fe65808ad7f506f903e198f4ba8543a97bbb0f4d4b602c5`

**Secrets** in der GitHub-Umgebung `release`: `SIGNING_KEYSTORE_BASE64`, `SIGNING_STORE_PASSWORD`, `SIGNING_KEY_PASSWORD`, `SIGNING_KEY_ALIAS`. Neu setzen, ohne den Wert auf die Kommandozeile zu schreiben, z. B. aus dem Schlüsselbund:

```sh
security find-generic-password -s ramuri-release-signing -a store-password -w | gh secret set SIGNING_STORE_PASSWORD --env release
```

Der Wert läuft nur durch die Pipe; `-a keystore-base64` liefert den Keystore für `SIGNING_KEYSTORE_BASE64`.

Lizenz: [GPL-3.0](LICENSE).
