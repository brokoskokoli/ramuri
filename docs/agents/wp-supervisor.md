# Paket-Sitzungen

Es gilt [common.md](common.md). Flutter liegt unter `/opt/homebrew/bin`, das Android-SDK unter `~/Library/Android/sdk`. Lokal gezielte Tests (`flutter test <datei>` in `app/`) und zwischendurch `sh tool/gate.sh --fast`; vor der Fertigmeldung den Branch pushen und das grüne Gate und E2E auf GitHub abwarten (siehe common.md, Prüfen und CI). Emulatoren nur über `tool/emu.sh`. Worktrees teilen sich den Pub-Cache: parallele `flutter pub get` können falsch rot werden, dann einzeln wiederholen.
- E2E-Tests liegen committet in `app/integration_test/` (Einstieg `all_test.dart`; Mehrphasen-Stufen mit Prozessende in `tool/ci_e2e.sh`, Kopf dort lesen) und laufen auf GitHub im Workflow `e2e`. Lohnende neue Tests des E2E-Agenten übernimmt ein Coder dorthin, nicht nach `handoff/`.
