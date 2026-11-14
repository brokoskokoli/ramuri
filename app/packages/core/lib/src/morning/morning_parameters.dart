// Parameter der Kamera-Morgenmessung (FR-0215, Regelversion K-1, Phase 3).
// Jeder Wert nennt seine PAR-Nummer; Art "Heuristik, Evidenz niedrig", Herkunft R009, K46.

/// PAR-160K: Morgenfenster, Vorgabe 4 bis 11 Uhr Ortszeit (einstellbar, siehe
/// `MorningWindow`). Der Beginn gehört zum Fenster, das Ende nicht (4:00 bis
/// 10:59, ganze Stunden). Eigene Wahl, weil ohne Schlafdaten die Aufwachzeit fehlt.
const int morningWindowDefaultStartHour = 4;
const int morningWindowDefaultEndHour = 11;

/// PAR-160K: Ruhephase vor der Messung (Sekunden), Haltung wie gespeichert.
const int morningRestSeconds = 120;

/// PAR-160K: Messdauer (Sekunden), spontane Atmung.
const int morningMeasureSeconds = 60;

/// PAR-160K: RMSSD-Qualitätsgrenze, Zeitrauschen der Schlagzeitpunkte höchstens
/// so viel (ms, die Grenze selbst gilt). Vorläufig bis Validierung (WP36); gilt
/// je Messung, auch im Entwicklermodus. Gleiche Zahl wie
/// `ppgLimitedTimingNoiseMs`, aber ein eigener Parameter, weil WP36 sie ändern
/// darf, ohne die Stufe "gut" zu ändern.
const double morningRmssdTimingNoiseLimitMs = 25.0;

/// PAR-160K (wie PAR-160): gültiger RMSSD-Bereich in ms, Grenzen eingeschlossen.
/// Ein Wert außerhalb wird nicht gespeichert (der Ruhepuls bleibt).
const double morningRmssdMinMs = 1.0;
const double morningRmssdMaxMs = 200.0;

/// PAR-160K, PAR-017: gültiger Ruhepuls in 1/min, Grenzen eingeschlossen (30
/// und 120 gelten). Eine Messung außerhalb wird verworfen.
const double morningRestingHrMinBpm = 30.0;
const double morningRestingHrMaxBpm = 120.0;

/// PAR-164K/165K: feste Stundenwerte je Schlafstufe in der Reihenfolge der
/// Stufen (unter 5, 5-6, 6-7, 7-8, über 8 h); die Werte der offenen Stufen
/// sind eigene Wahl.
const List<double> morningSleepBandHours = [4.5, 5.5, 6.5, 7.5, 8.5];
