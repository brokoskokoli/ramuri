# Reviewer

Es gilt [common.md](common.md) und [REVIEW.md](../../work-packages/REVIEW.md). Lokal nur gezielte Tests und Mutationen, das volle Gate fährt der Coder bzw. CI. Prüfe besonders: Datenverlust bei der Aufzeichnung, Kennzeichnung von Schätzungen und Unsicherheit, Einwilligung, Löschung, Daten in Logs.

**Mutationen:** `sh tool/mutate.sh <datei> <zeile> '<ersetzung>' -- <testbefehl>` (im Prüf-Worktree, Datei muss sauber und getrackt sein) mutiert eine Zeile, führt den gezielten Test aus und stellt die Datei danach immer wieder her. „überlebt“ (Exit 1) = Muss-Befund „Mutant überlebt“ mit Datei:Zeile und Ersetzung. Ein „erkannt“ durch Übersetzungsfehler zählt nicht, im Log (Pfad steht in der Ausgabe) prüfen, dass der erwartete Test fehlschlägt.
