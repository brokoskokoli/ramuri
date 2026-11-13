/// Startwerte der geführten Einheit (WP24). Benannte Konstanten, damit jede
/// Zahl eine Stelle hat.
library;

/// PAR-107: Pulsansagen erst nach so langer Zeit im Abschnitt.
const Duration pulseAnnounceMinTimeInSegment = Duration(minutes: 3);

/// PAR-107: In Abschnitten kürzer als dies keine Pulsansagen.
const Duration pulseAnnounceMinSegmentLength = Duration(minutes: 4);

/// PAR-107: Die Überschreitung muss so lange anhalten.
const Duration pulseAnnounceMinOverrun = Duration(seconds: 30);

/// PAR-107: Pulsansagen nur bis zu dieser Bewegungszeit (danach Vorrang RPE).
const Duration pulseAnnounceMaxMovingTime = Duration(minutes: 60);

/// PAR-107: So viele letzte lockere Einheiten zählen für den Gehpausen-Hinweis.
const int walkBreakHintRunCount = 3;

/// PAR-107 (Auslegung WP24): Ein Lauf zählt als „überwiegend über der oberen
/// Grenze“, wenn mehr als dieser Anteil der Zeit mit bekanntem Puls darüber lag.
const double mostlyAboveShare = 0.5;

/// PAR-107 (Auslegung WP24): so viele der letzten Läufe müssen „überwiegend
/// darüber“ sein.
const int walkBreakHintMinRuns = 2;

/// Eigene Wahl WP24 (Festlegung 8, kein PAR): Vorankündigung des nächsten
/// Abschnitts so lange vor dem Wechsel.
const Duration segmentPreviewLead = Duration(seconds: 10);

/// Eigene Wahl WP24: Abschnitte bis zu dieser Länge (2 × Vorlauf) bekommen
/// keine Vorankündigung, sie würde mit der Ansage des Beginns zusammenfallen.
const Duration segmentPreviewMinSegment = Duration(seconds: 20);

/// Festlegung 6: Kilometer-Ansage bei jedem vollen Vielfachen.
const double guidanceKilometerMeters = 1000;
