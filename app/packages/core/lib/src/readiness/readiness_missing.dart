import '../../ports/storage_morning.dart';
import '../load/training_load.dart'
    show LoadDay, LoadProvisionalReason, trainingLoadParameters;
import '../morning/morning_logic.dart';
import '../ppg/ppg_evaluator.dart' show PpgQuality;
import 'readiness_deviation.dart';
import 'readiness_parameters.dart';
import 'readiness_release.dart';
import 'readiness_result.dart' show ReadinessFactorId;
import 'readiness_series.dart' show cameraRmssdValue, cameraRestingHrValue;

/// Warum ein Faktor fehlt (FR-0111: Grund mit der fehlenden Menge). Der
/// Schlüssel ist [name]; die Texte setzt die App.
enum ReadinessMissingCode {
  // HRV und Ruhepuls
  /// Keine Quelle hat einen Wert (weder Health Connect noch Kamera).
  noMeasurement,

  /// Es gibt Werte, aber heute keinen.
  noMeasurementToday,

  /// Die heutige Kamera-Messung lag außerhalb des Morgenfensters (PAR-160K);
  /// Fenster in [ReadinessMissingReason.windowStartHour] bis
  /// [ReadinessMissingReason.windowEndHour].
  cameraOutsideWindow,

  /// Die heutige Kamera-Messung ist „eingeschränkt“: ohne RMSSD (PAR-160K).
  cameraQualityLimited,

  /// Die heutige Kamera-Messung ist „unbrauchbar“ (K68).
  cameraQualityUnusable,

  /// Die heutige Kamera-Messung hat keinen gültigen Wert für diesen Faktor
  /// (etwa Zeitrauschen oder Bereich, PAR-160K).
  cameraValueInvalid,

  /// Die Kamera-Werte dieses Faktors sind gesperrt (Validierung, Opt-in).
  cameraNotReleased,

  /// Zu wenige Werte in den letzten 7 Tagen: [ReadinessMissingReason.count]
  /// von [ReadinessMissingReason.required] (PAR-161, PAR-162).
  tooFewInWindow,

  /// Zu kurzer Vergleich: [ReadinessMissingReason.count] von
  /// [ReadinessMissingReason.required] Referenztagen (PAR-161, PAR-162).
  tooFewReference,

  /// Werte zu gleichmäßig (MAD unter der Grenze, FR-0114).
  madTooSmall,

  // Schlaf
  /// Keine Hauptschlafphase aus Health Connect und keine Selbstangabe.
  sleepNoEntry,

  /// Keine Hauptschlafphase aus Health Connect; eine Selbstangabe gibt es
  /// ohne freigeschaltete Morgenmessung nicht (K62 Punkt 1).
  sleepNoHealthConnect,

  // Belastung (PAR-168)
  /// Nur bei der erweiterten Einschätzung berechnet.
  loadOnlyExtended,

  /// Noch kein bewerteter Tag im Belastungsverlauf.
  loadNoHistory,

  /// Verlauf kürzer als [ReadinessMissingReason.required] Tage (PAR-089).
  loadHistoryShort,

  /// Zu viele Einheiten ohne Bewertung (PAR-090): mehr als
  /// [ReadinessMissingReason.required] % in [ReadinessMissingReason.count]
  /// Tagen.
  loadMissingUnits,

  /// Keine Angabe „alles erfasst“ (PAR-090, FR-0103).
  loadNoCommitment,

  /// TSB% nicht an allen [ReadinessMissingReason.required] Tagen (PAR-073).
  loadNoMean,

  // Befinden (PAR-169)
  /// Kein Befinden bei einem Lauf angegeben.
  wellbeingNone,

  /// Letzte Angabe vor [ReadinessMissingReason.count] Tagen, zählt
  /// [ReadinessMissingReason.required] Tage.
  wellbeingTooOld,
}

/// Weg zum Nachholen eines fehlenden Faktors.
enum ReadinessCatchUp {
  /// Knopf „Morgenmessung starten“ (Morgenmessung erreichbar, heute keine
  /// zählende Messung).
  startMorning,

  /// Knopf „Schlaf angeben“ an der ersten Morgenmessung des Ortstags
  /// (PAR-164K).
  enterSleep,

  /// Hinweis: Schlaf bei der Morgenmessung angeben.
  sleepAtMorning,

  /// Hinweis: Werte kommen aus Health Connect (Uhr synchronisieren).
  healthConnectSync,

  /// Hinweis: Befinden nach dem nächsten Lauf angeben.
  wellbeingAfterRun,
}

/// Grund eines fehlenden Faktors mit Zahlen und Wegen zum Nachholen.
/// Enthält keine Messwerte; [toString] nennt nur den Code.
class ReadinessMissingReason {
  const ReadinessMissingReason(
    this.code, {
    this.count,
    this.required,
    this.windowStartHour,
    this.windowEndHour,
    this.laterIgnored = false,
    this.catchUp = const [],
  });

  final ReadinessMissingCode code;

  /// Vorhandene Menge (Werte, Tage), wo der Code sie nennt.
  final int? count;

  /// Nötige Menge, wo der Code sie nennt.
  final int? required;

  /// Morgenfenster bei [ReadinessMissingCode.cameraOutsideWindow].
  final int? windowStartHour;
  final int? windowEndHour;

  /// Am selben Ortstag gab es in derselben Reihe spätere Messungen; sie zählen
  /// nicht, es gilt die erste ([countingMorningMeasurements]).
  final bool laterIgnored;

  /// Wege zum Nachholen in der Reihenfolge der Anzeige.
  final List<ReadinessCatchUp> catchUp;

  /// Noch fehlende Menge (`required − count`), sonst `null`.
  int? get remaining =>
      count == null || required == null ? null : required! - count!;

  @override
  bool operator ==(Object other) =>
      other is ReadinessMissingReason &&
      other.code == code &&
      other.count == count &&
      other.required == required &&
      other.windowStartHour == windowStartHour &&
      other.windowEndHour == windowEndHour &&
      other.laterIgnored == laterIgnored &&
      _sameList(other.catchUp, catchUp);

  @override
  int get hashCode => Object.hash(
    code,
    count,
    required,
    windowStartHour,
    windowEndHour,
    laterIgnored,
    Object.hashAll(catchUp),
  );

  @override
  String toString() => 'ReadinessMissingReason(${code.name})';
}

bool _sameList<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

DateTime _day(DateTime d) => DateTime.utc(d.year, d.month, d.day);

/// Gründe der fehlenden Faktoren (FR-0111). Rein und deterministisch; rechnet
/// nichts am Modell, liest nur dieselben Eingaben wie `computeReadiness`.
///
/// * [missing]: die Faktoren ohne Wert, in dieser Reihenfolge.
/// * [today]: Ortstag als UTC-Datum.
/// * [hrvHealthConnect], [restingHrHealthConnect]: Reihen aus Health Connect
///   (nur mit Einwilligung, sonst `null`).
/// * [cameraDeviations], [morningMeasurements]: Kamerareihen und alle
///   gespeicherten Morgenmessungen; beide zählen nur bei
///   [CameraRelease.cameraValuesAllowed] (K62 Punkt 1: sonst kein Kamerabezug).
/// * [window]: Morgenfenster für den Text bei Messungen außerhalb.
/// * [loadRequested]: die Belastung wurde berechnet (erweiterte Stufe);
///   [loadDay] ist dann ihr letzter Tag.
Map<ReadinessFactorId, ReadinessMissingReason> readinessMissingReasons({
  required List<ReadinessFactorId> missing,
  required DateTime today,
  required CameraRelease release,
  DeviationResult? hrvHealthConnect,
  DeviationResult? restingHrHealthConnect,
  Iterable<DeviationResult> cameraDeviations = const [],
  Iterable<MorningMeasurement> morningMeasurements = const [],
  MorningWindow window = MorningWindow.standard,
  bool loadRequested = true,
  LoadDay? loadDay,
  ({int level, DateTime day})? wellbeing,
}) {
  final allowed = release.cameraValuesAllowed;
  final day = _day(today);
  final cams = allowed ? cameraDeviations.toList() : <DeviationResult>[];
  final todayAll = allowed
      ? ([
          for (final m in morningMeasurements)
            if (morningLocalDay(m) == day) m,
        ]..sort((a, b) => a.measuredAt.compareTo(b.measuredAt)))
      : <MorningMeasurement>[];
  final countingToday = allowed
      ? [
          for (final m in countingMorningMeasurements(morningMeasurements))
            if (morningLocalDay(m) == day) m,
        ]
      : <MorningMeasurement>[];

  ReadinessMissingReason deviation(
    ReadinessFactor factor,
    DeviationResult? hc,
  ) {
    final series = [
      ?hc,
      for (final c in cams)
        if (c.factor == factor) c,
    ];
    // a. Kamerawert mit `z`, aber gesperrt (Validierung, Opt-in).
    if (series.any(
      (s) =>
          s.source == ReadinessSource.camera &&
          s.hasZ &&
          !release.isReleased(s),
    )) {
      return const ReadinessMissingReason(
        ReadinessMissingCode.cameraNotReleased,
      );
    }
    // b. Heute ein Wert, aber kein `z`: Health Connect vor Kamera, dann die
    // Kamerareihe mit mehr Referenzwerten (wie die Vorrangregel K-1).
    final withToday = [
      for (final s in series)
        if (!s.hasZ &&
            s.reason != NoDeviationReason.noSeries &&
            s.reason != NoDeviationReason.noValueToday)
          s,
    ];
    if (withToday.isNotEmpty) {
      final best = withToday.reduce((a, b) {
        if (a.source != b.source) {
          return a.source == ReadinessSource.healthConnect ? a : b;
        }
        return b.referenceCount > a.referenceCount ? b : a;
      });
      return switch (best.reason!) {
        NoDeviationReason.tooFewInWindow => ReadinessMissingReason(
          ReadinessMissingCode.tooFewInWindow,
          count: best.windowCount,
          required: readinessMinWindowValues,
        ),
        NoDeviationReason.tooFewReference => ReadinessMissingReason(
          ReadinessMissingCode.tooFewReference,
          count: best.referenceCount,
          required: readinessMinReferenceValues,
        ),
        _ => const ReadinessMissingReason(ReadinessMissingCode.madTooSmall),
      };
    }
    final startMorning = allowed && countingToday.isEmpty
        ? const [ReadinessCatchUp.startMorning]
        : const <ReadinessCatchUp>[];
    // c. Heute eine Kamera-Messung, die für diesen Faktor nichts liefert. Es
    // gilt die erste zählende Messung des Ortstags; ohne zählende die erste.
    if (countingToday.isNotEmpty) {
      final first = countingToday.first;
      final key = MorningSeriesKey.of(first);
      final later = todayAll.any(
        (m) =>
            !identical(m, first) &&
            m.measuredAt.isAfter(first.measuredAt) &&
            MorningSeriesKey.of(m) == key,
      );
      final value = factor == ReadinessFactor.hrv
          ? cameraRmssdValue(first)
          : cameraRestingHrValue(first);
      if (value == null) {
        return ReadinessMissingReason(
          first.quality == PpgQuality.limited
              ? ReadinessMissingCode.cameraQualityLimited
              : ReadinessMissingCode.cameraValueInvalid,
          laterIgnored: later,
        );
      }
    } else if (todayAll.isNotEmpty) {
      final first = todayAll.first;
      return first.outsideWindow
          ? ReadinessMissingReason(
              ReadinessMissingCode.cameraOutsideWindow,
              windowStartHour: window.startHour,
              windowEndHour: window.endHour,
              catchUp: startMorning,
            )
          : ReadinessMissingReason(
              ReadinessMissingCode.cameraQualityUnusable,
              catchUp: startMorning,
            );
    }
    // d./e. Kein Wert heute bzw. gar keiner.
    final hcWithoutToday =
        hc != null &&
        (hc.reason == NoDeviationReason.noSeries ||
            hc.reason == NoDeviationReason.noValueToday);
    final catchUp = [
      ...startMorning,
      if (hcWithoutToday) ReadinessCatchUp.healthConnectSync,
    ];
    final anyValues = series.any((s) => s.reason != NoDeviationReason.noSeries);
    return ReadinessMissingReason(
      anyValues
          ? ReadinessMissingCode.noMeasurementToday
          : ReadinessMissingCode.noMeasurement,
      catchUp: catchUp,
    );
  }

  ReadinessMissingReason sleep() {
    if (!allowed) {
      return const ReadinessMissingReason(
        ReadinessMissingCode.sleepNoHealthConnect,
      );
    }
    return ReadinessMissingReason(
      ReadinessMissingCode.sleepNoEntry,
      catchUp: countingToday.isNotEmpty
          ? const [ReadinessCatchUp.enterSleep]
          : const [
              ReadinessCatchUp.sleepAtMorning,
              ReadinessCatchUp.startMorning,
            ],
    );
  }

  ReadinessMissingReason load() {
    final p = trainingLoadParameters;
    final d = loadDay;
    if (!loadRequested) {
      return const ReadinessMissingReason(
        ReadinessMissingCode.loadOnlyExtended,
      );
    }
    if (d == null || !d.hasValues) {
      return const ReadinessMissingReason(ReadinessMissingCode.loadNoHistory);
    }
    final reasons = {...d.ctlProvisionalReasons, ...d.atlProvisionalReasons};
    if (reasons.contains(LoadProvisionalReason.startup)) {
      return ReadinessMissingReason(
        ReadinessMissingCode.loadHistoryShort,
        required: p.ctlProvisionalDays,
      );
    }
    if (reasons.contains(LoadProvisionalReason.noCommitment)) {
      return const ReadinessMissingReason(
        ReadinessMissingCode.loadNoCommitment,
      );
    }
    if (reasons.contains(LoadProvisionalReason.missingUnits)) {
      return ReadinessMissingReason(
        ReadinessMissingCode.loadMissingUnits,
        count: p.fallbackWindowDays,
        required: p.fallbackMissingPercent,
      );
    }
    return ReadinessMissingReason(
      ReadinessMissingCode.loadNoMean,
      required: p.tsbPercentMeanDays,
    );
  }

  ReadinessMissingReason wellbeingReason() {
    const hint = [ReadinessCatchUp.wellbeingAfterRun];
    final w = wellbeing;
    final age = w == null ? null : day.difference(_day(w.day)).inDays;
    if (age == null || age < 0) {
      return const ReadinessMissingReason(
        ReadinessMissingCode.wellbeingNone,
        catchUp: hint,
      );
    }
    return ReadinessMissingReason(
      ReadinessMissingCode.wellbeingTooOld,
      count: age,
      required: readinessWellbeingMaxAgeDays,
      catchUp: hint,
    );
  }

  return {
    for (final id in missing)
      id: switch (id) {
        ReadinessFactorId.hrv => deviation(
          ReadinessFactor.hrv,
          hrvHealthConnect,
        ),
        ReadinessFactorId.restingHeartRate => deviation(
          ReadinessFactor.restingHeartRate,
          restingHrHealthConnect,
        ),
        ReadinessFactorId.sleep => sleep(),
        ReadinessFactorId.load => load(),
        ReadinessFactorId.wellbeing => wellbeingReason(),
      },
  };
}
