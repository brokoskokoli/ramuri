import '../algorithm_category.dart';

/// Kennung und Version des Kamera-PPG-Verfahrens (NFR-0001, NFR-0005).
/// Version 1 = Port von `PpgAnalyzer.kt` im Stand `algo-v0.4-frozen`.
const String ppgMethod = 'camera-ppg';
const int ppgMethodVersion = 1;

/// Stand der Referenz, aus der das Verfahren portiert ist.
const String ppgReference = 'algo-v0.4-frozen';

/// Kategorie des Verfahrens (NFR-0002): B, Heuristik.
const AlgorithmCategory ppgCategory = AlgorithmCategory.heuristic;

// Alle Konstanten stehen in ALGORITHMUS.md (gleicher Ordner), Abschnitt in
// Klammern. Gültigkeit des Messwerts im Alltag: PAR-160K.

/// Abtastrate des gleichmäßigen Rasters nach der Spline-Interpolation (Hz), Abschn. 3.
const double ppgGridRate = 100.0;

/// Bandpass 0,5 bis 4 Hz, Butterworth 2. Ordnung je Seite, phasenfrei, Abschn. 3.
const double ppgBandLowHz = 0.5;
const double ppgBandHighHz = 4.0;
const double ppgButterworthQ = 0.7071067811865476;

/// Länge des gleitenden Mittels für die Rohkurve ohne Drift (s), Abschn. 3.
const double ppgDetrendSeconds = 1.5;

/// Ränder beim Filtern: ungerade Spiegelung über so viele Sekunden, Abschn. 3.
const double ppgFilterPadSeconds = 3.0;

/// Mindestzahl an Bildern im Auswertebereich, sonst „zu wenige Bilder“, Abschn. 2.
const int ppgMinFrames = 50;

/// Konstante Rohwerte (Abschn. 2): Spannweite im Messfenster höchstens 1e-12 des größten
/// Betrags. Numerisch begründet, keine Amplitudenschwelle: Ein Bildmittelwert über N ≤ 2^24
/// Pixeln mit 8 Bit hat Stufen von mindestens 1/N, relativ zu 255 also über 2e-10; 1e-12
/// liegt darunter und über dem Rundungsrauschen von Summe und Mittel in Double (~1e-16 je
/// Operation).
const double ppgFlatRelativeTolerance = 1e-12;

/// Goertzel-Suche der Grundfrequenz, Abschn. 4: Raster 0,5 bis 4 Hz in 0,01-Hz-Schritten,
/// Grundton nur zwischen 0,7 und 3,5 Hz, Signalleistung bei f0 ± 0,08 Hz und 2·f0 ± 0,12 Hz.
const double ppgSpectrumStartHz = 0.5;
const double ppgSpectrumEndHz = 4.0;
const double ppgSpectrumStepHz = 0.01;
const double ppgPulseMinHz = 0.7;
const double ppgPulseMaxHz = 3.5;
const double ppgFundamentalHalfWidthHz = 0.08;
const double ppgHarmonicHalfWidthHz = 0.12;

/// Gipfelsuche, Abschn. 5.1: Mindestabstand max(0,27 s, 0,55 Perioden); Gipfel unter
/// 30 % der mittleren Höhe fallen weg.
const double ppgPeakMinDistanceSeconds = 0.27;
const double ppgPeakMinDistancePeriods = 0.55;
const double ppgPeakMinHeightFraction = 0.3;

/// Rückwärtssuche des steilsten Anstiegs vor dem Gipfel in Perioden, Abschn. 5.2.
const double ppgSlopeSearchPeriods = 0.6;

/// Vorlagenabgleich, Abschn. 5.3: Mindestkorrelation eines Schlags (darunter Artefakt),
/// Korrelation für die Vorlagenbildung ab dem zweiten Durchgang, Verschiebung ±0,12 s,
/// drei Durchgänge.
const double ppgMinCorrelation = 0.6;
const double ppgTemplateCorrelation = 0.7;
const double ppgTemplateMaxLagSeconds = 0.12;
const int ppgTemplatePasses = 3;

/// Fenster der Vorlage in Perioden vor und nach dem Anker, Abschn. 5.3:
/// ganzer Schlag (Gipfel als Anker) und Anstieg (steilster Anstieg als Anker).
const double ppgWholeBeatPreFraction = 0.35;
const double ppgWholeBeatPostFraction = 0.55;
const double ppgRiseBeatPreFraction = 0.18;
const double ppgRiseBeatPostFraction = 0.15;

/// Störabschnitte, Abschn. 6: Steigung über 2,5 × typischer Steigung oder Ausschlag über
/// 2 × typischer Gipfelhöhe; Stellen näher als 0,3 s werden verbunden, Rand 0,3 s.
const double ppgArtifactSlopeFactor = 2.5;
const double ppgArtifactAmplitudeFactor = 2.0;
const double ppgArtifactMarginSeconds = 0.3;

/// Ausreißerprüfung der Intervalle (nach Lipponen & Tarvainen 2019, vereinfacht), Abschn. 7:
/// lokaler Median über ±5 Intervalle, Schwelle 5,2 × halber Quartilsabstand, begrenzt auf
/// 8 bis 25 % des Medians; erlaubte Intervalle 0,27 bis 2,0 s.
const int ppgOutlierMedianRadius = 5;
const double ppgOutlierQuartileFactor = 5.2;
const double ppgOutlierMinFraction = 0.08;
const double ppgOutlierMaxFraction = 0.25;
const double ppgIntervalMinSeconds = 0.27;
const double ppgIntervalMaxSeconds = 2.0;

/// Pulsdifferenzen über 50 ms zählen für pNN50, Abschn. 8.
const double ppgPnnThresholdMs = 50.0;

/// Auswahl der Signalquelle, Abschn. 9: brauchbar ab Q 0,25 und 60 % gültigen Intervallen;
/// Teilbereiche mit Q ab 70 % des besten gehen in die Kombination ein.
const double ppgSourceMinQuality = 0.25;
const double ppgSourceMinValidFraction = 0.6;
const double ppgBlockQualityFraction = 0.7;

/// Bewertung, Abschn. 10 (PAR-160K): unbrauchbar bei Q unter 0,25 oder unter 50 % gültigen
/// Intervallen; eingeschränkt bei Q unter 0,3, unter 70 % gültigen Intervallen oder
/// Zeitrauschen über 25 ms.
const double ppgUnusableQuality = 0.25;
const double ppgUnusableValidFraction = 0.5;
const double ppgLimitedQuality = 0.3;
const double ppgLimitedValidFraction = 0.7;
const double ppgLimitedTimingNoiseMs = 25.0;

/// Messfenster der Referenz in Sekunden seit Aufnahmebeginn, Abschn. 2: Filter ab 3 s
/// (Einschwingen), Auswertung von 5 bis 65 s, Daten bis 66,5 s (Filterrand).
const PpgWindow ppgStandardWindow = PpgWindow(
  filterStart: 3.0,
  start: 5.0,
  end: 65.0,
  dataEnd: 66.5,
);

/// Messfenster (Sekunden seit Aufnahmebeginn).
class PpgWindow {
  const PpgWindow({
    required this.filterStart,
    required this.start,
    required this.end,
    required this.dataEnd,
  });

  /// Bilder davor werden ignoriert (Einschwingen von Belichtung und Finger).
  final double filterStart;

  /// Beginn und Ende des Auswertefensters.
  final double start;
  final double end;

  /// Bilder danach werden ignoriert; Rand für das Filter.
  final double dataEnd;
}

/// Größte erlaubte Lücke zwischen zwei Bildern in Sekunden (Maintainer 2026-11-11, WP27, PAR-Nummer
/// folgt). Wer länger kein Bild bekommt, dessen Messung ist unbrauchbar: `evaluatePpg` meldet
/// `PpgQualityReason.frameGap` (geprüft zwischen den Bildern ab `filterStart` bis `dataEnd`).
const double ppgMaxFrameGapSeconds = 1.0;

/// Fingerprüfung (Maintainer 2026-11-11, WP27, Evidenz niedrig: 10 Messungen eines Handys einer
/// Person und eine Emulator-Szene, PAR-Nummer folgt): Mittel von Rot geteilt durch Mittel von Grün
/// über die Bilder im Messfenster (Mitte) unter diesem Wert ergibt „unbrauchbar, kein Finger“
/// (`PpgQualityReason.noFinger`). Mit Blitz auf der Haut absorbiert das Blut Grün weit stärker
/// als Rot; eine freie Szene hat Rot/Grün um 1 und darunter. Die Referenz prüft nur die Anzeige.
const double ppgMinRedGreenRatio = 1.5;
