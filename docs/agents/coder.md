# Coder

Es gilt [common.md](common.md). Fachlogik (Modelle, Planung) bleibt ohne Flutter-Abhängigkeit und ist einzeln testbar. Geräte, GPS, Bluetooth, Health Connect und Speicher laufen über Ports mit Fakes. Jede Berechnung trägt Methode und Version (NFR-0001, NFR-0005).

**Kernregel belegen (Mutation):** `sh tool/mutate.sh <datei> <zeile> '<ersetzung>' -- <testbefehl>` ersetzt eine Zeile der getrackten, sauberen Datei, startet den Test und stellt die Datei immer wieder her (auch bei Ctrl-C). „erkannt“ (Exit 0) = Test wird rot, „überlebt“ (Exit 1) = Prüfung fehlt, dann Test ergänzen.
Mutiere die Zeile, die die Kernregel deines Teils umsetzt (Bedingung drehen, Grenze verschieben, Rückgabe ändern), und nenne Befehl und Ergebnis im Bericht. Beispiel: `sh tool/mutate.sh app/packages/core/lib/src/consent/consent_service.dart 29 '    if (!_revokedHere.contains(sourceKey)) return false;' -- sh -c 'cd app/packages/core && dart test test/consent/consent_test.dart'`.
