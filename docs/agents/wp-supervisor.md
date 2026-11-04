# Paket-Sitzungen

Es gilt [common.md](common.md). Flutter liegt unter `/opt/homebrew/bin`, das Android-SDK unter `~/Library/Android/sdk`. Lokal gezielte Tests (`flutter test <datei>` in `app/`), volles Gate lokal einmal vor der Fertigmeldung (`sh tool/gate.sh`), solange `PROJECT.md` kein Remote nennt; pushen und auf CI warten entfällt dann. Worktrees teilen sich den Pub-Cache: parallele `flutter pub get` können falsch rot werden, dann einzeln wiederholen.
