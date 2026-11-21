import 'package:core/core.dart';

import '../../l10n/app_localizations.dart';
import '../measure/morning_trend_screen.dart' show morningMarkText;

/// Textbausteine der Erholung (WP34 Teil D1; die Detailseite aus Teil D2
/// nutzt dieselben). Nur Beschreibung der Daten, nie eine Diagnose und kein
/// „erholt“ oder „bereit“ in Sätzen (PAR-174, PAR-184). Der Bandname „Gut
/// erholt“ ist ein Name, kein Satz (OQ-0029).

String readinessBandName(AppLocalizations l, ReadinessBand band) =>
    switch (band) {
      ReadinessBand.wellRecovered => l.readinessBandWellRecovered,
      ReadinessBand.normal => l.readinessBandNormal,
      ReadinessBand.elevatedLoad => l.readinessBandElevatedLoad,
      ReadinessBand.recoveryAdvised => l.readinessBandRecoveryAdvised,
    };

/// Das Wort der Stufe (PAR-159: Stufe und Grund).
String readinessLevelWord(AppLocalizations l, ReadinessLevel level) =>
    switch (level) {
      ReadinessLevel.notDeterminable => l.readinessLevelNotDeterminable,
      ReadinessLevel.provisional => l.readinessLevelProvisional,
      ReadinessLevel.sufficient => l.readinessLevelSufficient,
      ReadinessLevel.good => l.readinessLevelGood,
    };

String readinessFactorName(AppLocalizations l, ReadinessFactorId id) =>
    switch (id) {
      ReadinessFactorId.hrv => l.readinessFactorHrv,
      ReadinessFactorId.restingHeartRate => l.readinessFactorRestingHr,
      ReadinessFactorId.sleep => l.readinessFactorSleep,
      ReadinessFactorId.load => l.readinessFactorLoad,
      ReadinessFactorId.wellbeing => l.readinessFactorWellbeing,
    };

String readinessSourceName(AppLocalizations l, ReadinessFactorSource s) =>
    switch (s) {
      ReadinessFactorSource.healthConnect => l.readinessSourceHealthConnect,
      ReadinessFactorSource.camera => l.readinessSourceCamera,
      ReadinessFactorSource.selfReport => l.readinessSourceSelfReport,
      ReadinessFactorSource.trainingLoad => l.readinessSourceLoad,
      ReadinessFactorSource.runRating => l.readinessSourceSelfReport,
    };

/// Warum ein Faktor fehlt (Detailseite und Karte, FR-0111): der Grund mit der
/// fehlenden Menge, bei späteren Messungen desselben Tages mit dem Hinweis,
/// dass sie nicht zählen.
String readinessMissingReasonText(
  AppLocalizations l,
  ReadinessMissingReason r,
) {
  final count = r.count ?? 0;
  final required = r.required ?? 0;
  final text = switch (r.code) {
    ReadinessMissingCode.noMeasurement => l.readinessMissingNoMeasurement,
    ReadinessMissingCode.noMeasurementToday =>
      l.readinessMissingNoMeasurementToday,
    ReadinessMissingCode.cameraOutsideWindow => l.readinessMissingOutsideWindow(
      r.windowStartHour ?? 0,
      r.windowEndHour ?? 0,
    ),
    ReadinessMissingCode.cameraQualityLimited =>
      l.readinessMissingQualityLimited,
    ReadinessMissingCode.cameraQualityUnusable =>
      l.readinessMissingQualityUnusable,
    ReadinessMissingCode.cameraValueInvalid => l.readinessMissingValueInvalid,
    ReadinessMissingCode.cameraNotReleased => l.readinessMissingNotReleased,
    ReadinessMissingCode.tooFewInWindow => l.readinessMissingTooFewInWindow(
      count,
      required,
    ),
    ReadinessMissingCode.tooFewReference => l.readinessMissingTooFewReference(
      count,
      required,
      r.remaining ?? 0,
    ),
    ReadinessMissingCode.madTooSmall => l.readinessMissingMadTooSmall,
    ReadinessMissingCode.sleepNoEntry => l.readinessMissingSleepNoEntry,
    ReadinessMissingCode.sleepNoHealthConnect =>
      l.readinessMissingSleepNoHealthConnect,
    ReadinessMissingCode.loadOnlyExtended => l.readinessMissingLoadOnlyExtended,
    ReadinessMissingCode.loadNoHistory => l.readinessMissingLoadNoHistory,
    ReadinessMissingCode.loadHistoryShort => l.readinessMissingLoadHistoryShort(
      required,
    ),
    ReadinessMissingCode.loadMissingUnits => l.readinessMissingLoadMissingUnits(
      required,
      count,
    ),
    ReadinessMissingCode.loadNoCommitment => l.readinessMissingLoadNoCommitment,
    ReadinessMissingCode.loadNoMean => l.readinessMissingLoadNoMean(required),
    ReadinessMissingCode.wellbeingNone => l.readinessMissingWellbeingNone,
    ReadinessMissingCode.wellbeingTooOld => l.readinessMissingWellbeingTooOld(
      count,
      required,
    ),
  };
  return r.laterIgnored ? '$text ${l.readinessMissingLaterIgnored}' : text;
}

/// Grund eines fehlenden Faktors; ohne berechneten Grund der allgemeine Satz.
String readinessMissingText(
  AppLocalizations l,
  ReadinessResult result,
  ReadinessFactorId id,
) => switch (result.missingReasons[id]) {
  final r? => readinessMissingReasonText(l, r),
  null => switch (id) {
    ReadinessFactorId.hrv ||
    ReadinessFactorId.restingHeartRate => l.readinessMissingValue,
    ReadinessFactorId.sleep => l.readinessMissingSleep,
    ReadinessFactorId.load => l.readinessMissingLoad,
    ReadinessFactorId.wellbeing => l.readinessMissingWellbeing,
  },
};

/// Stufengründe, die sagen, warum die HRV fehlt (PAR-147).
const Set<ReadinessLevelReasonCode> _hrvMissingCodes = {
  ReadinessLevelReasonCode.hrvNoSeries,
  ReadinessLevelReasonCode.hrvNoValueToday,
  ReadinessLevelReasonCode.hrvTooFewInWindow,
  ReadinessLevelReasonCode.hrvTooFewReference,
  ReadinessLevelReasonCode.hrvMadTooSmall,
  ReadinessLevelReasonCode.hrvCameraLocked,
};

/// Die Stufengründe als Sätze (Karte und Detailseite). Fehlt die HRV, steht an
/// der Stelle ihrer Gründe genau einmal derselbe Grund wie in der Liste
/// „Fehlende Faktoren“ (FR-0111), mit dem Faktornamen davor; Karte und
/// Detailseite sagen so dasselbe.
List<String> readinessLevelReasonTexts(AppLocalizations l, ReadinessResult r) {
  final hrv = r.missingReasons[ReadinessFactorId.hrv];
  final out = <String>[];
  var hrvDone = false;
  for (final reason in r.levelReasons) {
    if (hrv != null && _hrvMissingCodes.contains(reason.code)) {
      if (hrvDone) continue;
      hrvDone = true;
      out.add(
        l.readinessMissingOnCard(
          readinessFactorName(l, ReadinessFactorId.hrv),
          readinessMissingReasonText(l, hrv),
        ),
      );
    } else {
      out.add(readinessReasonText(l, reason));
    }
  }
  return out;
}

/// Ein Grund der Stufe als Satz (PAR-159).
String readinessReasonText(AppLocalizations l, ReadinessLevelReason r) {
  final count = r.count ?? 0;
  final required = r.required ?? 0;
  return switch (r.code) {
    ReadinessLevelReasonCode.hrvNoSeries => l.readinessReasonHrvNoSeries,
    ReadinessLevelReasonCode.hrvNoValueToday =>
      l.readinessReasonHrvNoValueToday,
    ReadinessLevelReasonCode.hrvTooFewInWindow =>
      l.readinessReasonHrvTooFewInWindow,
    ReadinessLevelReasonCode.hrvTooFewReference =>
      l.readinessReasonHrvTooFewReference(count, required),
    ReadinessLevelReasonCode.hrvMadTooSmall => l.readinessReasonHrvMadTooSmall,
    ReadinessLevelReasonCode.hrvCameraLocked =>
      l.readinessReasonHrvCameraLocked,
    ReadinessLevelReasonCode.sleepMissing => l.readinessReasonSleepMissing,
    ReadinessLevelReasonCode.hrvReferenceBelowSufficient =>
      l.readinessReasonHrvReferenceBelowSufficient(count, required),
    ReadinessLevelReasonCode.restingHrMissing =>
      l.readinessReasonRestingHrMissing,
    ReadinessLevelReasonCode.hrvReferenceBelowGood =>
      l.readinessReasonHrvReferenceBelowGood(count, required),
    ReadinessLevelReasonCode.sleepPhasesMissing =>
      l.readinessReasonSleepPhasesMissing,
    ReadinessLevelReasonCode.loadMissing => l.readinessReasonLoadMissing,
    ReadinessLevelReasonCode.sourceTooShort => l.readinessReasonSourceTooShort(
      count,
      required,
    ),
    ReadinessLevelReasonCode.fewMeasurements =>
      l.readinessReasonFewMeasurements,
  };
}

/// Der Grund als kurze Wendung ohne Satzende („HRV unter deinem Mittel“),
/// samt Zusätzen (Kamera, geschätzt, wenige Messungen).
String readinessDriverText(AppLocalizations l, ReadinessDriver d) {
  final lower = d.direction == ReadinessDirection.lower;
  final base = switch (d.id) {
    ReadinessFactorId.hrv =>
      lower ? l.readinessDriverHrvLower : l.readinessDriverHrvHigher,
    ReadinessFactorId.restingHeartRate =>
      lower ? l.readinessDriverRhrLower : l.readinessDriverRhrHigher,
    ReadinessFactorId.sleep =>
      !lower
          ? l.readinessDriverSleepHigher
          : d.sleepCause == ReadinessSleepCause.lowEfficiency
          ? l.readinessDriverSleepEfficiency
          : l.readinessDriverSleepShort,
    ReadinessFactorId.load => l.readinessDriverLoadLower,
    ReadinessFactorId.wellbeing =>
      lower
          ? l.readinessDriverWellbeingLower
          : l.readinessDriverWellbeingHigher,
  };
  final notes = [
    if (d.source == ReadinessFactorSource.camera) l.readinessDriverCamera,
    if (d.estimated) l.readinessDriverEstimated,
    if (d.fewMeasurements) l.readinessDriverFew,
  ];
  return notes.isEmpty
      ? base
      : l.readinessDriverQualified(base, notes.join(', '));
}

/// Zahl mit den Nachkommastellen der Reihe (FR-0114), Dezimalkomma in de.
String readinessNumberText(AppLocalizations l, double v, int decimals) {
  final t = v.toStringAsFixed(decimals);
  return l.localeName.startsWith('de') ? t.replaceAll('.', ',') : t;
}

/// Betrag mit den Nachkommastellen der Reihe (FR-0114), Dezimalkomma in de.
String _amount(AppLocalizations l, double v, int decimals) {
  final t = v.abs().toStringAsFixed(decimals);
  return l.localeName.startsWith('de') ? t.replaceAll('.', ',') : t;
}

/// Eine Tatsache als Satz (eingeschränkte Einschätzung, Detailseite). Mit Werten
/// nennt sie die Differenz von heute zur Referenz (Median der 28 Tage davor) („Ruhepuls
/// heute 3/min über deinem Mittel“, PAR-171K), ohne Werte nur die Richtung aus
/// dem Vorzeichen von `z`. Ein Ersatzwert (PAR-160) wird gesagt.
String readinessFactText(AppLocalizations l, ReadinessFact f) {
  final source = readinessSourceName(l, f.source);
  final z = f.z ?? 0;
  final v = f.values;
  final diff = v?.todayMinusReference ?? 0;
  final amount = v == null ? '' : _amount(l, diff, v.decimals);
  final byValue = v != null && diff != 0;
  final text = switch (f.kind) {
    ReadinessFactKind.sleepDuration => l.readinessFactSleep(
      (f.hours ?? 0).round(),
    ),
    ReadinessFactKind.hrvDeviation =>
      byValue
          ? (diff > 0
                ? l.readinessFactHrvAboveBy(amount, source)
                : l.readinessFactHrvBelowBy(amount, source))
          : v != null || z == 0
          ? l.readinessFactHrvLevel(source)
          : z > 0
          ? l.readinessFactHrvAbove(source)
          : l.readinessFactHrvBelow(source),
    // Ruhepuls: z ist „günstig positiv“, also positiv = unter dem Mittel.
    ReadinessFactKind.restingHeartRateDeviation =>
      byValue
          ? (diff > 0
                ? l.readinessFactRhrAboveBy(amount, source)
                : l.readinessFactRhrBelowBy(amount, source))
          : v != null || z == 0
          ? l.readinessFactRhrLevel(source)
          : z > 0
          ? l.readinessFactRhrBelow(source)
          : l.readinessFactRhrAbove(source),
  };
  return v != null && v.todayIsFallback
      ? '$text ${l.readinessFactFallback}'
      : text;
}

/// Markierung einer gesperrten Kamerawerts-Tatsache samt „geht in keine Zahl
/// ein“ (PAR-171K); `null` ohne Markierung.
String? readinessMarkText(AppLocalizations l, MorningRmssdMark mark) {
  final text = morningMarkText(l, mark);
  return text == null ? null : l.readinessFactMarked(text);
}

/// Tatsache mit ihrer Markierung, falls sie eine trägt (PAR-171K: eine
/// gesperrte Kamera-Tatsache steht nie ohne „geht in keine Zahl ein“).
///
/// Die Markierung folgt nach einem Doppelpunkt. Nennt der Grund davor die Sperre schon
/// ([lockNamed]), steht darin nur die Markierung, sonst mit „geht in keine
/// Zahl ein“, damit der Satz es nicht zweimal sagt.
String _factWithMark(
  AppLocalizations l,
  ReadinessFact f, {
  required bool lockNamed,
}) {
  final text = readinessFactText(l, f);
  final mark = lockNamed
      ? morningMarkText(l, f.mark)
      : readinessMarkText(l, f.mark);
  if (mark == null) return text;
  final bare = text.endsWith('.') ? text.substring(0, text.length - 1) : text;
  return '$bare: $mark.';
}

/// Der Text unter dem Zustand auf der Karte: Datenlage mit Ursachen (Zahl),
/// Grund und Tatsachen (eingeschränkt) oder der feste Satz (unzureichend).
String readinessCardText(AppLocalizations l, ReadinessResult r) {
  switch (r.state) {
    case ReadinessState.number:
      final e = r.explanation;
      final level = l.readinessLevelLine(readinessLevelWord(l, r.level));
      final tail = switch (e.code) {
        ReadinessExplanationCode.drivers => l.readinessDriversLine(
          e.drivers.map((d) => readinessDriverText(l, d)).join(', '),
        ),
        ReadinessExplanationCode.onlySleepBelow => l.readinessOnlySleepBelow(
          readinessDriverText(l, e.drivers.first),
        ),
        ReadinessExplanationCode.noDeviation => l.readinessNoDeviation,
        ReadinessExplanationCode.noNumber => '',
      };
      return tail.isEmpty ? level : '$level $tail';
    case ReadinessState.limited:
      // Der Grund nennt die Sperre samt „geht in keine Zahl ein“ nur in der
      // Stufenformulierung; steht dort der Grund der fehlenden HRV, trägt die
      // Tatsache den vollen Hinweis selbst (PAR-171K).
      final lockNamed =
          r.levelReasons.isNotEmpty &&
          r.levelReasons.first.code ==
              ReadinessLevelReasonCode.hrvCameraLocked &&
          r.missingReasons[ReadinessFactorId.hrv] == null;
      final reasons = readinessLevelReasonTexts(l, r);
      return [
        if (reasons.isNotEmpty) reasons.first else l.readinessLimitedNeed,
        for (final f in [...r.facts.take(2), ...r.markedFacts])
          _factWithMark(
            l,
            f,
            lockNamed: lockNamed && f.kind == ReadinessFactKind.hrvDeviation,
          ),
      ].join(' ');
    case ReadinessState.insufficient:
      return l.readinessInsufficientText;
  }
}

/// Hinweis statt „Morgenmessung starten“ außerhalb des Morgenfensters
/// (FR-0111): ab wann die nächste Messung zählt, heute oder morgen.
String readinessNextWindowText(AppLocalizations l, ReadinessMissingReason r) {
  final hour = r.nextWindowStartHour ?? 0;
  final time = l.localeName.startsWith('de') ? '$hour' : _hourEn(hour);
  return r.nextWindowToday
      ? l.readinessCatchUpNextWindowToday(time)
      : l.readinessCatchUpNextWindowTomorrow(time);
}

/// Volle Stunde im 12-Stunden-Format („4 am“, „12 pm“).
String _hourEn(int hour) {
  final h = hour % 24;
  final twelve = h % 12 == 0 ? 12 : h % 12;
  return '$twelve ${h < 12 ? 'am' : 'pm'}';
}
