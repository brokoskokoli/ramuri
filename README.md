# ramuri – Adaptive Running & Fitness App

Android-App (später optional iOS) für Laufaufzeichnung, Fitnessanalyse, Regeneration und adaptive Trainingsplanung. Sie funktioniert ohne Wearable und ohne Bindung an einen Gerätehersteller.

**Projektstatus:** Die Phasen 1 bis 3 sind spezifiziert und vom Maintainer freigegeben. Die App liegt in `app/`: Phase 1 (Laufaufzeichnung und Fitnessanalyse) ist umgesetzt, Phase 2 (adaptiver Trainingscoach) ist in Umsetzung, Phase 3 folgt danach (Stand: [Umsetzungsstand](work-packages/STATUS.md)). Ein Release setzt eine rechtliche Prüfung voraus (OQ-0048).

- [Dokumentation](docs/index.md)
- [Offene Fragen](docs/migration/open-questions.md)
- [Migrationsbericht](docs/migration/migration-report.md)
- [Anweisungen für Agenten](AGENTS.md)
- [Umsetzungsstand](work-packages/STATUS.md)

## Releases

Ein Release entsteht aus einem Git-Tag:

- `vX.Y.Z` ist eine Version, z. B. `v0.1.0`.
- `vX.Y.Z-rcN` ist ein Release Candidate, z. B. `v0.1.0-rc1` (N von 1 bis 98).

`versionName` ist der Tag ohne `v` (`0.1.0-rc1`). `versionCode` = MAJOR·1000000 + MINOR·10000 + PATCH·100 + N (RC) bzw. 99 (Version), also `10001` für `v0.1.0-rc1` und `10099` für `v0.1.0`. MINOR und PATCH dürfen höchstens 99 sein, MAJOR höchstens 2000.

Der Push eines Tags startet `.github/workflows/release.yml`. Die Pipeline prüft, dass der Tag auf einen Commit in `main` zeigt, führt das volle Gate aus und baut APK und AAB mit dem Release-Schlüssel. Sie prüft, dass die APK mit dem Release-Zertifikat signiert ist und die Release-Rechte stimmen, und legt auf GitHub einen **Entwurf** an (ein RC als Pre-Release) mit APK, AAB und `SHA256SUMS.txt`. Sie veröffentlicht nie automatisch; das tut der Maintainer von Hand, bisher nicht vor OQ-0048.

**Lokal bauen:** `tool/build_signed.sh v0.1.0-rc1` legt APK, AAB und Prüfsummen in `dist/` ab. Den Schlüssel nimmt das Skript aus den Umgebungsvariablen der Secrets unten, sonst aus dem macOS-Schlüsselbund (Dienst `ramuri-release-signing`, Konten `store-password` und `keystore-base64`).

**APK prüfen:** `apksigner verify --print-certs dist/ramuri-0.1.0-rc1.apk` muss diesen SHA-256 des Zertifikats zeigen:

`1c7e8472f5e705814fe65808ad7f506f903e198f4ba8543a97bbb0f4d4b602c5`

**Secrets** in der GitHub-Umgebung `release`: `SIGNING_KEYSTORE_BASE64`, `SIGNING_STORE_PASSWORD`, `SIGNING_KEY_PASSWORD`, `SIGNING_KEY_ALIAS`. Neu setzen, ohne den Wert auf die Kommandozeile zu schreiben, z. B. aus dem Schlüsselbund:

```sh
security find-generic-password -s ramuri-release-signing -a store-password -w | gh secret set SIGNING_STORE_PASSWORD --env release
```

Der Wert läuft nur durch die Pipe; `-a keystore-base64` liefert den Keystore für `SIGNING_KEYSTORE_BASE64`.

Lizenz: [GPL-3.0](LICENSE).
