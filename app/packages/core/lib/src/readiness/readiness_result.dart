import 'dart:math' as math;

import '../morning/morning_marks.dart' show MorningRmssdMark;
import 'readiness_deviation.dart' show ReadinessSource;
import 'readiness_explanation.dart' show ReadinessExplanation;
import 'readiness_level.dart' show ReadinessLevel, ReadinessLevelReason;
import 'readiness_parameters.dart';

/// Die fünf Faktoren des Gesamtwerts (FR-0110).
enum ReadinessFactorId { hrv, restingHeartRate, sleep, load, wellbeing }

/// Woher ein Faktor kommt (für die Erklärung, PAR-172).
enum ReadinessFactorSource {
  healthConnect,
  camera,

  /// Schlafdauer als Selbstangabe in Stufen (PAR-164K/165K).
  selfReport,

  /// TSB% aus dem Trainingsbelastungsmodell (PAR-168).
  trainingLoad,

  /// Befinden beim letzten Lauf (PAR-169).
  runRating,
}

ReadinessFactorSource factorSourceOf(ReadinessSource s) => switch (s) {
  ReadinessSource.healthConnect => ReadinessFactorSource.healthConnect,
  ReadinessSource.camera => ReadinessFactorSource.camera,
};

/// Zustand nach OQ-0006 (neue Fassung), PAR-171, PAR-171K.
enum ReadinessState {
  /// Zahl mit Band.
  number,

  /// „Eingeschränkte Einschätzung“: ohne Zahl und ohne Band, mit Tatsachen.
  limited,

  /// „Unzureichende Daten“.
  insufficient,
}

/// FR-0116 (OQ-0029): feste Bänder.
enum ReadinessBand { wellRecovered, normal, elevatedLoad, recoveryAdvised }

/// Ein eingegangener Faktor: Quelle, Gewicht und Teilskala `S`.
class ReadinessFactorValue {
  const ReadinessFactorValue({
    required this.id,
    required this.source,
    required this.weight,
    required this.score,
    this.mark = MorningRmssdMark.none,
    this.estimated = false,
    this.fewMeasurements = false,
    this.referenceCount = 0,
    this.values,
  });

  final ReadinessFactorId id;
  final ReadinessFactorSource source;

  /// Gewicht aus FR-0110 (PAR-170).
  final double weight;

  /// Teilskala `S` (0 bis 90).
  final double score;

  /// Markierung eines freigegebenen Kamerawerts (etwa „experimentell“); ändert
  /// die Teilskala nie.
  final MorningRmssdMark mark;

  /// Schlafdauer ist eine Schätzung (PAR-166: Phasen fehlen oder unter 90 %).
  final bool estimated;

  /// Kamerareihe mit wenigen Messungen (PAR-161K).
  final bool fewMeasurements;

  /// Gültige Referenzwerte der Reihe (PAR-149, PAR-150); 0 bei Faktoren ohne
  /// Reihe (Schlaf, Belastung, Befinden).
  final int referenceCount;

  /// Mittel, Referenz und Wert von heute bei HRV und Ruhepuls, sonst `null`.
  final ReadinessValues? values;

  @override
  String toString() => 'ReadinessFactorValue($id, $source)';
}

/// Werte einer Reihe für Tatsachentexte (FR-0114: gerundet nach [decimals],
/// ms bzw. bpm), aus dem [DeviationResult]. [toString] nennt sie nicht.
class ReadinessValues {
  const ReadinessValues({
    required this.windowMean,
    required this.referenceMedian,
    required this.today,
    required this.todayIsFallback,
    required this.decimals,
  });

  /// Mittel der letzten 7 Tage.
  final double windowMean;

  /// Median der Referenz der 28 Tage davor.
  final double referenceMedian;

  /// Wert von heute.
  final double today;

  /// PAR-160: Ersatzwert aus den 60 min nach der Hauptschlafphase; der Tag
  /// wird markiert.
  final bool todayIsFallback;

  /// Nachkommastellen (0, beim Kamera-Ruhepuls 1).
  final int decimals;

  /// Wert von heute minus Referenzmedian (nicht das 7-Tage-Mittel: es enthält
  /// heute selbst), auf [decimals] gerundet.
  double get todayMinusReference {
    final f = math.pow(10, decimals).toDouble();
    return ((today - referenceMedian) * f).round() / f;
  }

  @override
  String toString() => 'ReadinessValues()';
}

enum ReadinessFactKind {
  hrvDeviation,
  restingHeartRateDeviation,
  sleepDuration,
}

/// Tatsache für die Erklärung. Trägt Zahlen, aber [toString] nennt sie nicht.
class ReadinessFact {
  const ReadinessFact({
    required this.kind,
    required this.source,
    this.z,
    this.hours,
    this.mark = MorningRmssdMark.none,
    this.estimated = false,
    this.fewMeasurements = false,
    this.values,
  });

  final ReadinessFactKind kind;
  final ReadinessFactorSource source;

  /// Abweichung (günstig positiv, wie im Faktor) bei HRV und Ruhepuls.
  final double? z;

  /// Schlafdauer in Stunden (bei Selbstangabe der feste Stufenwert).
  final double? hours;

  /// Ungleich `none`: markierte Tatsache (Kamera gesperrt), nie in Zahl/Faktor.
  final MorningRmssdMark mark;
  final bool estimated;
  final bool fewMeasurements;

  /// Mittel, Referenz und Wert von heute (HRV, Ruhepuls), sonst `null`.
  final ReadinessValues? values;

  @override
  String toString() => 'ReadinessFact($kind, $source)';
}

/// Ergebnis des Modells `readiness` v1 (NFR-0001). Keine Messwerte in
/// [toString].
class ReadinessResult {
  const ReadinessResult({
    required this.state,
    required this.value,
    required this.band,
    required this.capped,
    required this.factors,
    required this.missing,
    required this.blockers,
    required this.facts,
    required this.markedFacts,
    required this.hasFreshMeasurement,
    required this.level,
    required this.levelReasons,
    required this.explanation,
  });

  final String method = readinessMethod;
  final int methodVersion = readinessMethodVersion;

  final ReadinessState state;

  /// Gerundeter Wert 0 bis 100, nur bei [ReadinessState.number].
  final int? value;
  final ReadinessBand? band;

  /// Der Wert wurde auf 74 gekappt (PAR-170, Belastung fehlt).
  final bool capped;

  /// Eingegangene Faktoren.
  final List<ReadinessFactorValue> factors;

  /// Nicht eingegangene Faktoren (herausgerechnet und auszuweisen, FR-0111).
  final List<ReadinessFactorId> missing;

  /// Warum keine Zahl: fehlende Pflichtfaktoren (HRV, Schlaf) nach OQ-0006.
  final List<ReadinessFactorId> blockers;

  /// Tatsachen ohne Markierung (für die eingeschränkte Einschätzung).
  final List<ReadinessFact> facts;

  /// Markierte Tatsachen (Kamera gesperrt): gehen in keine Zahl und keinen Faktor.
  final List<ReadinessFact> markedFacts;

  /// Heute liegt eine frische Messung vor (Kamera oder Health Connect).
  final bool hasFreshMeasurement;

  /// Stufe der Datenlage (PAR-147 bis PAR-150), immer gesetzt. Bei einer Zahl
  /// mindestens [ReadinessLevel.provisional], sonst
  /// [ReadinessLevel.notDeterminable].
  final ReadinessLevel level;

  /// Grund der Stufe als Wort mit Grund (PAR-159): bei „vorläufig“ und
  /// „ausreichend“ die nicht erfüllten Bedingungen der nächsthöheren Stufe, bei
  /// „nicht bestimmbar“ die fehlenden Bedingungen; der erste Eintrag ist der
  /// Hauptgrund. Dazu ein Hinweis „wenige Messungen“, wo er gilt (PAR-148).
  final List<ReadinessLevelReason> levelReasons;

  /// Erklärung nach PAR-172 und PAR-170 als strukturierte Bausteine.
  final ReadinessExplanation explanation;

  /// Mit Zahl, aber ohne alle Faktoren: als eingeschränkt erkennbar (FR-0111).
  bool get restricted => state == ReadinessState.number && missing.isNotEmpty;

  @override
  String toString() => 'ReadinessResult($state)';
}
