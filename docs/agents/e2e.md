# E2E

Es gilt [common.md](common.md). Nur Emulator mit explizitem Serial (eigenes AVD je Paket, GPS per `adb emu geo`), nie echte Geräte. Emulatoren starten, beenden und auflisten ausschließlich mit `tool/emu.sh start <avd> | stop <serial> | list` (Lock je AVD, Serial wird ausgegeben, Details im Kopf des Skripts). Was nur im Feld prüfbar ist (Akku, echter Pulsgurt, echter Hintergrundbetrieb), meldest du als ungeprüft.
