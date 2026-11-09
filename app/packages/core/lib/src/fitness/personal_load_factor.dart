/// Persönlicher Faktor TRIMP / sRPE (FR-0097, PAR-086, PAR-087), je Profil.
/// Reine Funktionen; die Auswahl geeigneter Läufe (Puls nach PAR-010, RPE
/// vorhanden) macht der Aufrufer. Zahlen als benannte Parameter (PAR-086,
/// PAR-087, Heuristik).
class PersonalLoadFactorParameters {
  const PersonalLoadFactorParameters();

  /// PAR-087: Median über die letzten 20 geeigneten Läufe.
  final int medianRuns = 20;

  /// PAR-086: mindestens 10 Läufe mit beiden Werten ...
  final int minRuns = 10;

  /// ... in den letzten 180 Tagen,
  final int windowDays = 180;

  /// davon mindestens 2 mit RPE >= 6 ...
  final int highRpe = 6;
  final int minHighRuns = 2;

  /// ... und 2 mit RPE <= 4.
  final int lowRpe = 4;
  final int minLowRuns = 2;

  /// PAR-087: unter 20 Läufen „noch wenig gesichert“.
  final int securedRuns = 20;

  /// PAR-087: Abweichung über 25 % -> Neuberechnung anbieten.
  final double adoptTolerance = 0.25;

  /// PAR-087 „Vorwert der letzten 6 Monate“: nur ein gespeicherter Faktor, der
  /// höchstens so viele Tage alt ist, gilt als Vorwert. Festlegung WP19,
  /// Spec nennt keine Tageszahl: 6 Monate als 183 Tage (365 / 2, aufgerundet).
  final int priorValueDays = 183;
}

const personalLoadFactorParameters = PersonalLoadFactorParameters();

/// Ein Lauf mit TRIMP des Profils und sRPE (Punkte, FR-0095) und RPE.
class FactorRun {
  const FactorRun({
    required this.time,
    required this.trimp,
    required this.srpePoints,
    required this.rpe,
  });
  final DateTime time;
  final double trimp;
  final double srpePoints;
  final int rpe;

  /// Verhältnis rechenbar: beide endlich, TRIMP >= 0, sRPE > 0 (RPE 0 und
  /// Dauer 0 ergeben 0 Punkte, kein Verhältnis).
  bool get usable =>
      trimp.isFinite && srpePoints.isFinite && trimp >= 0 && srpePoints > 0;
}

enum FactorUnavailableReason { tooFewRuns, tooFewHighRpe, tooFewLowRpe }

/// Faktor oder Grund, warum keiner entsteht.
class PersonalLoadFactor {
  const PersonalLoadFactor._({
    required this.value,
    required this.runCount,
    required this.unavailable,
  });

  /// TRIMP-Punkte je sRPE-Punkt, `null` ohne Faktor.
  final double? value;

  /// Zahl der in den Median eingegangenen Läufe.
  final int runCount;
  final FactorUnavailableReason? unavailable;

  bool get available => value != null;

  /// „noch wenig gesichert“ (PAR-087): Faktor da, aber unter 20 Läufen.
  bool get tentative =>
      value != null && runCount < personalLoadFactorParameters.securedRuns;

  /// Umrechnung sRPE -> TRIMP-Skala; Ergebnis ist immer gekennzeichnet
  /// „umgerechnet“ (Aufrufer).
  double? convert(double srpePoints) =>
      value == null ? null : srpePoints * value!;
}

/// Berechnet den Faktor aus [runs] (eines Profils) zum Zeitpunkt [now].
/// Voraussetzung (PAR-086): mindestens 10 verwendbare Läufe in den letzten
/// 180 Tagen, davon >= 2 mit RPE >= 6 und >= 2 mit RPE <= 4. Dann Median von
/// TRIMP/sRPE über die letzten 20 verwendbaren Läufe (PAR-087; bei weniger
/// alle). Läufe nach [now] zählen nie.
PersonalLoadFactor computePersonalLoadFactor(
  Iterable<FactorRun> runs, {
  required DateTime now,
  PersonalLoadFactorParameters p = personalLoadFactorParameters,
}) {
  final usable = runs.where((r) => r.usable && !r.time.isAfter(now)).toList()
    ..sort((a, b) => b.time.compareTo(a.time));
  final from = now.subtract(Duration(days: p.windowDays));
  final inWindow = usable.where((r) => !r.time.isBefore(from)).toList();
  FactorUnavailableReason? reason;
  if (inWindow.length < p.minRuns) {
    reason = FactorUnavailableReason.tooFewRuns;
  } else if (inWindow.where((r) => r.rpe >= p.highRpe).length < p.minHighRuns) {
    reason = FactorUnavailableReason.tooFewHighRpe;
  } else if (inWindow.where((r) => r.rpe <= p.lowRpe).length < p.minLowRuns) {
    reason = FactorUnavailableReason.tooFewLowRpe;
  }
  if (reason != null) {
    return PersonalLoadFactor._(
      value: null,
      runCount: inWindow.length,
      unavailable: reason,
    );
  }
  final used = usable.take(p.medianRuns).toList();
  final ratios = [for (final r in used) r.trimp / r.srpePoints]..sort();
  final n = ratios.length;
  final median = n.isOdd
      ? ratios[n ~/ 2]
      : (ratios[n ~/ 2 - 1] + ratios[n ~/ 2]) / 2;
  return PersonalLoadFactor._(value: median, runCount: n, unavailable: null);
}

enum FactorDecision {
  /// Noch kein gespeicherter Faktor oder neuer innerhalb der Toleranz:
  /// neuen Faktor speichern und anwenden.
  adopt,

  /// Abweichung über der Toleranz: Neuberechnung anbieten; Ablehnen lässt
  /// den gespeicherten Faktor.
  offerRecalculation,
}

/// Übernahmeregel (PAR-087, FR-0199): neuer Faktor innerhalb ±25 % des
/// gespeicherten (Grenze inklusive) wird übernommen, sonst Angebot. Ohne
/// gespeicherten (oder mit nicht positivem) Faktor wird übernommen. Ist der
/// gespeicherte älter als [PersonalLoadFactorParameters.priorValueDays]
/// ([storedAgeDays], Tage seit der Übernahme), ist er kein Vorwert der letzten
/// 6 Monate (PAR-087): der neue wird still übernommen. Ohne [storedAgeDays]
/// gilt das Alter nicht.
FactorDecision decideFactorAdoption({
  required double? stored,
  required double fresh,
  int? storedAgeDays,
  PersonalLoadFactorParameters p = personalLoadFactorParameters,
}) {
  if (stored == null || !stored.isFinite || stored <= 0) {
    return FactorDecision.adopt;
  }
  if (storedAgeDays != null && storedAgeDays > p.priorValueDays) {
    return FactorDecision.adopt;
  }
  final deviation = (fresh - stored).abs() / stored;
  return deviation <= p.adoptTolerance
      ? FactorDecision.adopt
      : FactorDecision.offerRecalculation;
}
