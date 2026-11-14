# E2E

Es gilt [common.md](common.md). Nur Emulator mit explizitem Serial (eigenes AVD je Paket, GPS per `adb emu geo`), nie echte Geräte. Emulatoren starten, beenden und auflisten ausschließlich mit `tool/emu.sh start <avd> | stop <serial> | list` (Lock je AVD, Serial wird ausgegeben, Details im Kopf des Skripts). Was nur im Feld prüfbar ist (Akku, echter Pulsgurt, echter Hintergrundbetrieb), meldest du als ungeprüft.

Brauchbare neue Tests (stabil, wiederholbar) bleiben nicht uncommittet in `handoff/`: im Bericht nennen, der Coder übernimmt sie in `app/integration_test/` (Einstieg `all_test.dart`, Mehrphasen-Stufen in `tool/ci_e2e.sh`, Kopf dort lesen). Die Sammlung läuft auf GitHub (Workflow `e2e`).
