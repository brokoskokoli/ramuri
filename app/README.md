# app

Flutter-App (Android) des Projekts. Fachlogik liegt in `packages/core` (reines Dart, ohne Flutter), Plattformanbindungen in `packages/adapters`.

Lokalisierte Texte (de/en) stehen in `lib/l10n/*.arb`. Die Dateien `lib/l10n/app_localizations*.dart` werden von `flutter pub get` erzeugt und nicht eingecheckt.

Prüfen: im Repository-Wurzelverzeichnis `sh tool/gate.sh` (siehe `docs/quality/testing.md`).
