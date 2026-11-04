# Änderungsprotokoll der Umsetzung

Abweichungen von der Spezifikation, die sich bei der Umsetzung ergeben. Neue Einträge haben den Status `offen`, bis der Maintainer sie bestätigt. Agenten melden sie im Abschlussbericht, der Orchestrator trägt sie ein. Änderungen an Anforderungen selbst folgen dem Ablauf in [index.md](index.md#änderungen).

| Nr. | Datum | Bereich | Änderung | Anlass | Status |
| --- | --- | --- | --- | --- | --- |
| K1 | 2026-11-04 | ADR-0002 | **Flutter-Version:** 3.47.7 statt 3.47.9, weil das globale Flutter auch andere Projekte nutzen. | Plan für M1 (L15) | bestätigt (2026-11-04) |
| K2 | 2026-11-04 | ADR-0002 Punkt 2 | **Flutter-Freiheit von `core`:** Im Pub-Workspace teilen alle Pakete eine `package_config`, ein Flutter-Import scheitert dort also nicht am Auflösen. Ersatz ist der Gate-Schritt „core flutterfrei“: Abhängigkeits-Walk, Auflösen und Kompilieren einer Kopie von `core` außerhalb des Workspace, bedingte Importe verboten. Grenzen stehen in `docs/quality/testing.md`. | WP01 | offen |
| K3 | 2026-11-04 | ADR-0002, Abhängigkeiten | **Entwicklungspakete ohne ADR:** `test`, `lints`, `flutter_lints`. `intl` kommt nur transitiv über `flutter_localizations`, generierter Code importiert es. | WP01 | offen |
| K4 | 2026-11-04 | Gate | **Zusätzliche Prüfungen:** `--enforce-lockfile`, Schritt „lock unverändert“, `--changed` bezieht `tool/gate.sh` ein. Generierte l10n-Dateien liegen nicht in Git, `pub get` erzeugt sie. | WP01 | offen |
| K5 | 2026-11-04 | App-Kennung | **Vorläufige Festlegung:** Application-ID `io.github.brokoskokoli.running_app`, `android:label` „Running App“. | WP01 | offen |
