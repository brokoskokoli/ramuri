import '../fitness/load_profile.dart';

/// Parameter des Belastungsverlaufs (FR-0098, FR-0099, FR-0101, PAR-073,
/// PAR-088 bis PAR-090). Zahlen als benannte Parameter; Quelle je Wert.
class TrainingLoadParameters {
  const TrainingLoadParameters();

  /// FR-0098: Zeitkonstante ATL in Tagen.
  final int atlDays = 7;

  /// FR-0099: Zeitkonstante CTL in Tagen.
  final int ctlDays = 42;

  /// PAR-073: TSB% als rollendes Mittel der letzten 7 Tage.
  final int tsbPercentMeanDays = 7;

  /// PAR-088: ATL vorläufig in den ersten 21 Tagen ab dem ersten bewerteten
  /// Tag (abgeleitet).
  final int atlProvisionalDays = 21;

  /// PAR-089: CTL und TSB vorläufig in den ersten 126 Tagen (entschieden).
  final int ctlProvisionalDays = 126;

  /// PAR-090: Fenster für den Rückfall in „vorläufig“ (42 Tage).
  final int fallbackWindowDays = 42;

  /// PAR-090: Fehlen in diesem Fenster mehr als 10 % der erwarteten Einheiten
  /// als bewertet, gelten CTL und TSB wieder als vorläufig (Beginn abgeleitet,
  /// Ende Heuristik). Ganze Prozent, damit der Vergleich ganzzahlig bleibt.
  final int fallbackMissingPercent = 10;
}

const trainingLoadParameters = TrainingLoadParameters();

/// Art einer Einheit (OQ-0058): Lauf aus der App oder nachgetragenes Training
/// (`run` oder `other`).
enum LoadUnitKind { run, manual }

/// Eine Einheit für die Tageslast. Das Datum zählt als Kalendertag (Jahr,
/// Monat, Tag); die Uhrzeit wird ignoriert.
///
/// * Lauf: [trimp] (Skala des Profils, gültiger Puls nach PAR-010) ist
///   bewertet. Ohne [trimp] gilt [srpePoints] mit Faktor (umgerechnet).
/// * Nachgetragenes Training: nie TRIMP, nur [srpePoints] mit Faktor.
/// * Fehlt der Wert (kein Puls bzw. kein RPE) oder der Faktor: unbewertet.
class LoadUnit {
  const LoadUnit.run({required this.day, this.trimp, this.srpePoints})
    : kind = LoadUnitKind.run;

  const LoadUnit.manual({required this.day, this.srpePoints})
    : kind = LoadUnitKind.manual,
      trimp = null;

  final DateTime day;
  final LoadUnitKind kind;

  /// TRIMP des gewählten Profils; `null`, wenn der Puls nicht reicht.
  final double? trimp;

  /// sRPE-Punkte (FR-0095); `null` ohne RPE.
  final double? srpePoints;
}

/// Kennzeichen eines Tages.
enum LoadDayFlag {
  /// Mindestens eine Einheit ist aus sRPE mit dem Faktor umgerechnet.
  converted,

  /// Mindestens eine Einheit ist unbewertet: ATL und CTL unverändert
  /// (OQ-0054), keine Last 0 (FR-0102).
  unrated,

  /// Leerer Tag ohne Zusage „alles erfasst“: ATL und CTL unverändert
  /// (FR-0103, OQ-0058).
  emptyUnchanged,
}

/// Gründe, warum CTL und TSB vorläufig sind.
enum LoadProvisionalReason {
  /// PAR-089: weniger als 126 Tage ab dem ersten bewerteten Tag.
  startup,

  /// PAR-090: über 10 % der erwarteten Einheiten im 42-Tage-Fenster fehlen.
  missingUnits,

  /// PAR-090, FR-0103: keine Zusage „alles erfasst“.
  noCommitment,
}

/// Ein Tag des Verlaufs. Vor dem ersten bewerteten Tag sind ATL, CTL, TSB
/// `null`: keine Aussage, kein niedriges Niveau (FR-0104).
class LoadDay {
  const LoadDay({
    required this.day,
    required this.load,
    required this.atl,
    required this.ctl,
    required this.tsb,
    required this.tsbPercentMean7,
    required this.flags,
    required this.atlProvisional,
    required this.ctlProvisionalReasons,
    required this.unitCount,
    required this.ratedUnits,
    required this.convertedUnits,
    required this.unratedUnits,
  });

  /// Kalendertag (UTC-Mitternacht des Datums).
  final DateTime day;

  /// Tageslast L (Summe der bewerteten Einheiten); `null` bei unbewertetem
  /// Tag, bei leerem Tag ohne Zusage und vor dem Start. Leer mit Zusage: 0.
  final double? load;

  final double? atl;
  final double? ctl;

  /// FR-0101: `CTL[t−1] − ATL[t−1]`, ohne Wertung.
  final double? tsb;

  /// PAR-073: Mittel der TSB% (`TSB / CTL[t−1] · 100`) der letzten 7 Tage;
  /// `null`, wenn nicht alle 7 Tage einen Wert haben.
  final double? tsbPercentMean7;

  final Set<LoadDayFlag> flags;
  final bool atlProvisional;
  final Set<LoadProvisionalReason> ctlProvisionalReasons;

  final int unitCount;
  final int ratedUnits;
  final int convertedUnits;
  final int unratedUnits;

  bool get ctlProvisional => ctlProvisionalReasons.isNotEmpty;

  /// PAR-073: Die TSB%-Schwellen greifen nicht, solange ATL oder CTL
  /// vorläufig sind. Der Code wertet TSB sonst nicht aus.
  bool get tsbThresholdsLocked => atlProvisional || ctlProvisional;

  bool get hasValues => atl != null;
}

/// Zusammenfassung des Verlaufs bis heute.
class TrainingLoadSummary {
  const TrainingLoadSummary({
    required this.current,
    required this.firstRatedDay,
    required this.lastRatedDay,
    required this.lastUnitDay,
    required this.unratedUnits,
    required this.convertedUnits,
    required this.unratedDays,
  });

  /// Stand heute (letzter Tag der Reihe); `null`, wenn es keine Einheit gibt.
  final LoadDay? current;

  /// Erster Tag mit Tageslast (Start 0 davor).
  final DateTime? firstRatedDay;

  /// Letzter Tag mit bewerteter Einheit (ging in ATL/CTL ein).
  final DateTime? lastRatedDay;

  /// Datenstand: Tag der letzten erfassten Einheit bis heute.
  final DateTime? lastUnitDay;

  final int unratedUnits;
  final int convertedUnits;
  final int unratedDays;

  /// FR-0104: Es gibt eine Aussage erst ab dem ersten bewerteten Tag.
  bool get hasStatement => current?.hasValues ?? false;
}

/// Ergebnis mit Methode und Version (NFR-0001, NFR-0005) und der einen Skala.
class TrainingLoadSeries {
  const TrainingLoadSeries({
    required this.method,
    required this.methodVersion,
    required this.profile,
    required this.factor,
    required this.confirmsAllRecorded,
    required this.days,
    required this.summary,
  });

  final String method;
  final int methodVersion;

  /// Alle Werte stehen auf der Skala dieses Profils (ACC-07).
  final LoadProfile profile;
  final double? factor;
  final bool confirmsAllRecorded;
  final List<LoadDay> days;
  final TrainingLoadSummary summary;
}

const trainingLoadMethod = 'training-load-atl-ctl-tsb';
const trainingLoadMethodVersion = 1;

/// Rechnet Tageslast, ATL, CTL, TSB (FR-0098, FR-0099, FR-0101) bis [today].
/// Reine Funktion; keine Wertung (PAR-072): kein Text, keine Kategorie.
///
/// * [units]: alle Einheiten auf der Skala von [profile]; Einheiten nach
///   [today] zählen nie (FR-0199).
/// * [factor]: persönlicher Faktor TRIMP/sRPE (PAR-087) oder `null`.
/// * [confirmsAllRecorded]: Zusage „alles erfasst“ (FR-0103).
/// * [expectedUnitsPerDay]: erwartete Einheiten je Tag (später aus dem Plan,
///   WP21/23). Ohne Angabe gelten alle erfassten Einheiten als erwartet.
/// * [confirmedPauseDays]: bestätigte Pausen (PAR-202): Der Tag ist bekannt
///   leer (Last 0, auch ohne Zusage), erwartete Einheiten fallen weg.
TrainingLoadSeries computeTrainingLoad({
  required LoadProfile profile,
  required Iterable<LoadUnit> units,
  required double? factor,
  required bool confirmsAllRecorded,
  required DateTime today,
  Map<DateTime, int>? expectedUnitsPerDay,
  Set<DateTime> confirmedPauseDays = const {},
  TrainingLoadParameters parameters = trainingLoadParameters,
}) {
  final p = parameters;
  final usableFactor = factor != null && factor.isFinite && factor > 0
      ? factor
      : null;
  final todayIndex = _dayIndex(today);

  // Einheiten je Tag, ohne Zukunft.
  final byDay = <int, List<LoadUnit>>{};
  for (final u in units) {
    final d = _dayIndex(u.day);
    if (d > todayIndex) continue;
    (byDay[d] ??= []).add(u);
  }
  final pauses = {for (final d in confirmedPauseDays) _dayIndex(d)};
  final expectedByDay = <int, int>{};
  if (expectedUnitsPerDay != null) {
    expectedUnitsPerDay.forEach((d, n) {
      final i = _dayIndex(d);
      if (i <= todayIndex && n > 0 && !pauses.contains(i)) {
        expectedByDay[i] = (expectedByDay[i] ?? 0) + n;
      }
    });
  }

  if (byDay.isEmpty) {
    return TrainingLoadSeries(
      method: trainingLoadMethod,
      methodVersion: trainingLoadMethodVersion,
      profile: profile,
      factor: usableFactor,
      confirmsAllRecorded: confirmsAllRecorded,
      days: const [],
      summary: const TrainingLoadSummary(
        current: null,
        firstRatedDay: null,
        lastRatedDay: null,
        lastUnitDay: null,
        unratedUnits: 0,
        convertedUnits: 0,
        unratedDays: 0,
      ),
    );
  }

  final first = byDay.keys.reduce((a, b) => a < b ? a : b);
  final count = todayIndex - first + 1;

  // Bewertung je Einheit und Tag.
  final rated = List<int>.filled(count, 0);
  final converted = List<int>.filled(count, 0);
  final unrated = List<int>.filled(count, 0);
  final units0 = List<int>.filled(count, 0);
  final loads = List<double>.filled(count, 0);
  for (final e in byDay.entries) {
    final i = e.key - first;
    for (final u in e.value) {
      units0[i]++;
      final trimp = u.kind == LoadUnitKind.run ? u.trimp : null;
      if (trimp != null && trimp.isFinite && trimp >= 0) {
        rated[i]++;
        loads[i] += trimp;
        continue;
      }
      final srpe = u.srpePoints;
      if (srpe != null && srpe.isFinite && srpe >= 0 && usableFactor != null) {
        rated[i]++;
        converted[i]++;
        loads[i] += srpe * usableFactor;
        continue;
      }
      unrated[i]++;
    }
  }

  // Fenster-Summen (Präfixsummen) für PAR-090.
  final prefExpected = List<int>.filled(count + 1, 0);
  final prefMissing = List<int>.filled(count + 1, 0);
  for (var i = 0; i < count; i++) {
    final int expected;
    final int missing;
    if (expectedUnitsPerDay == null) {
      expected = units0[i];
      missing = unrated[i];
    } else {
      expected = expectedByDay[first + i] ?? 0;
      missing = 0; // plan-based: Fenster-Differenz unten
    }
    prefExpected[i + 1] = prefExpected[i] + expected;
    prefMissing[i + 1] = prefMissing[i] + missing;
  }
  final prefRated = List<int>.filled(count + 1, 0);
  for (var i = 0; i < count; i++) {
    prefRated[i + 1] = prefRated[i] + rated[i];
  }
  bool fallbackAt(int i) {
    final lo = i - p.fallbackWindowDays + 1 < 0
        ? 0
        : i - p.fallbackWindowDays + 1;
    final expected = prefExpected[i + 1] - prefExpected[lo];
    if (expected <= 0) return false;
    final int missing;
    if (expectedUnitsPerDay == null) {
      missing = prefMissing[i + 1] - prefMissing[lo];
    } else {
      final r = prefRated[i + 1] - prefRated[lo];
      missing = expected > r ? expected - r : 0;
    }
    return missing * 100 > expected * p.fallbackMissingPercent;
  }

  final loadOf = List<double?>.filled(count, null);
  final flagsOf = List<Set<LoadDayFlag>>.generate(count, (_) => {});
  final atlOf = List<double?>.filled(count, null);
  final ctlOf = List<double?>.filled(count, null);
  final tsbOf = List<double?>.filled(count, null);
  final tsbPctOf = List<double?>.filled(count, null);
  double atl = 0;
  double ctl = 0;
  int? start;
  int? lastRated;
  int? lastUnit;
  var unratedDays = 0;
  var unratedTotal = 0;
  var convertedTotal = 0;

  for (var i = 0; i < count; i++) {
    final hasUnits = units0[i] > 0;
    final hasUnrated = unrated[i] > 0;
    if (hasUnits) lastUnit = i;
    unratedTotal += unrated[i];
    convertedTotal += converted[i];
    if (hasUnrated) unratedDays++;
    final flags = flagsOf[i];
    if (converted[i] > 0) flags.add(LoadDayFlag.converted);
    if (hasUnrated) flags.add(LoadDayFlag.unrated);

    // Last des Tages: bewertet, bekannt leer oder keine (OQ-0054, FR-0103).
    double? load;
    if (hasUnrated) {
      load = null;
    } else if (hasUnits) {
      load = loads[i];
    } else if (confirmsAllRecorded || pauses.contains(first + i)) {
      load = 0;
    } else if (start != null) {
      flags.add(LoadDayFlag.emptyUnchanged);
    }
    loadOf[i] = load;

    // Start bei 0 am ersten Tag mit bewerteter Einheit (FR-0098). Davor keine
    // Aussage (FR-0104).
    if (start == null && hasUnits && load != null) start = i;
    if (start == null) continue;

    final prevCtl = ctl;
    tsbOf[i] = trainingStressBalance(ctlPrevious: ctl, atlPrevious: atl);
    tsbPctOf[i] = prevCtl > 0 ? tsbOf[i]! / prevCtl * 100 : null;
    if (load != null) {
      atl = nextAtl(atl, load, p);
      ctl = nextCtl(ctl, load, p);
      if (hasUnits) lastRated = i;
    }
    atlOf[i] = atl;
    ctlOf[i] = ctl;
  }

  final days = <LoadDay>[];
  for (var i = 0; i < count; i++) {
    final s = start;
    final reasons = <LoadProvisionalReason>{};
    var atlProvisional = false;
    double? mean;
    if (s != null && i >= s) {
      final age = i - s;
      atlProvisional = age < p.atlProvisionalDays || !confirmsAllRecorded;
      if (age < p.ctlProvisionalDays) {
        reasons.add(LoadProvisionalReason.startup);
      }
      if (fallbackAt(i)) reasons.add(LoadProvisionalReason.missingUnits);
      if (!confirmsAllRecorded) reasons.add(LoadProvisionalReason.noCommitment);
      if (i - p.tsbPercentMeanDays + 1 >= s) {
        var sum = 0.0;
        var ok = true;
        for (var k = i - p.tsbPercentMeanDays + 1; k <= i; k++) {
          final v = tsbPctOf[k];
          if (v == null) {
            ok = false;
            break;
          }
          sum += v;
        }
        if (ok) mean = sum / p.tsbPercentMeanDays;
      }
    }
    days.add(
      LoadDay(
        day: DateTime.utc(1970).add(Duration(days: first + i)),
        load: loadOf[i],
        atl: atlOf[i],
        ctl: ctlOf[i],
        tsb: tsbOf[i],
        tsbPercentMean7: mean,
        flags: flagsOf[i],
        atlProvisional: atlProvisional,
        ctlProvisionalReasons: reasons,
        unitCount: units0[i],
        ratedUnits: rated[i],
        convertedUnits: converted[i],
        unratedUnits: unrated[i],
      ),
    );
  }

  DateTime? dayAt(int? i) => i == null ? null : days[i].day;
  return TrainingLoadSeries(
    method: trainingLoadMethod,
    methodVersion: trainingLoadMethodVersion,
    profile: profile,
    factor: usableFactor,
    confirmsAllRecorded: confirmsAllRecorded,
    days: days,
    summary: TrainingLoadSummary(
      current: days.last,
      firstRatedDay: dayAt(start),
      lastRatedDay: dayAt(lastRated),
      lastUnitDay: dayAt(lastUnit),
      unratedUnits: unratedTotal,
      convertedUnits: convertedTotal,
      unratedDays: unratedDays,
    ),
  );
}

/// FR-0098: `ATL[t] = ATL[t−1] + (L[t] − ATL[t−1]) / 7`.
double nextAtl(
  double atlPrevious,
  double load, [
  TrainingLoadParameters p = trainingLoadParameters,
]) => atlPrevious + (load - atlPrevious) / p.atlDays;

/// FR-0099: `CTL[t] = CTL[t−1] + (L[t] − CTL[t−1]) / 42`.
double nextCtl(
  double ctlPrevious,
  double load, [
  TrainingLoadParameters p = trainingLoadParameters,
]) => ctlPrevious + (load - ctlPrevious) / p.ctlDays;

/// FR-0101: `TSB[t] = CTL[t−1] − ATL[t−1]`, ohne Wertung (PAR-072).
double trainingStressBalance({
  required double ctlPrevious,
  required double atlPrevious,
}) => ctlPrevious - atlPrevious;

int _dayIndex(DateTime d) =>
    DateTime.utc(d.year, d.month, d.day).difference(DateTime.utc(1970)).inDays;
