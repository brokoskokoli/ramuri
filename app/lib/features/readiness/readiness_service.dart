import 'package:core/core.dart';

/// Was die Karte „Erholung“ auf „Heute“ braucht (WP34 Teil D1).
class ReadinessSnapshot {
  const ReadinessSnapshot({
    required this.result,
    required this.developerMode,
    required this.extended,
    this.series = const [],
    this.release,
    this.today,
    this.sleepEntry,
  });

  final ReadinessResult result;

  /// Entwicklermodus an: nur der unauffällige Hinweis, keine Kennzeichnung.
  final bool developerMode;

  /// `true`: erweiterte Stufe (Gesundheitsdaten freigegeben oder zulässige
  /// Kamera-Messungen vorhanden). `false`: Basisstufe, nur der Texthinweis aus WP23 (FR-0105,
  /// FR-0107).
  final bool extended;

  /// Die Reihen mit Tageswerten für den Verlauf (WP34 Teil D2): HRV und
  /// Ruhepuls aus Health Connect (nur mit Einwilligung) und alle Kamerareihen
  /// (nur wenn Kamerawerte zulässig sind), je Quelle getrennt, so wie das
  /// Modell sie bekam. Keine zweite Rechnung.
  final List<DeviationResult> series;

  /// Freigabe der Kamerawerte (für die Markierung der Kamerareihen);
  /// ohne Angabe ohne Opt-in und ohne Validierungsstand.
  final CameraRelease? release;

  /// Ortstag der Uhr als UTC-Datum (Ende der 28 Tage im Verlauf); ohne Angabe
  /// der jüngste Tag der Reihen.
  final DateTime? today;

  /// Die erste zählende Morgenmessung des Ortstags mit ihrer Schlafangabe
  /// (PAR-164K): dort setzt „Schlaf angeben“ die Stufe; `null` ohne heutige
  /// Morgenmessung oder ohne zulässige Kamerawerte (K62 Punkt 1).
  final ReadinessSleepEntry? sleepEntry;

  CameraRelease get effectiveRelease =>
      release ?? CameraRelease(developerMode: developerMode, rmssdOptIn: false);
}

/// Morgenmessung, an der die Schlafangabe hängt, und ihre Stufe.
class ReadinessSleepEntry {
  const ReadinessSleepEntry({required this.measurementId, this.band});

  final int measurementId;
  final SleepBand? band;

  @override
  String toString() => 'ReadinessSleepEntry($measurementId)';
}

/// Baut [ReadinessInputs] aus den Ports und rechnet [computeReadiness]
/// (WP34 Teil D1). Nichts wird gespeichert (Vorentscheidung des Pakets).
///
/// * Health-Connect-Reihen nur mit Einwilligung je Datenart
///   ([healthSourceKey]); fail-closed ([ConsentService.isGranted]).
/// * „Heute“ ist der Ortstag der Uhr; für Health Connect die Hauptschlafphase,
///   die an diesem Tag endet (PAR-164, im Modell), für die Kamera die
///   zählende Messung des Ortstags.
/// * Die Belastung (TSB%) liefert [loadToday] aus dem Belastungsdienst
///   (WP19); fehlt sie, gilt die Kappung aus PAR-170.
class ReadinessService {
  ReadinessService({
    required this.session,
    required this.clock,
    this.loadToday,
    this.validationState = ppgValidationState,
    this.processing = const HealthProcessing(),
  }) : _consents = ConsentService(session.consents, clock);

  final StorageSession session;
  final Clock clock;

  /// Letzter Tag des Belastungsverlaufs oder `null`; Fehler zählen als `null`.
  final Future<LoadDay?> Function()? loadToday;
  final Map<ValidationQuantity, ValidationState> validationState;
  final HealthProcessing processing;
  final ConsentService _consents;

  /// Tage der Referenz vor heute (PAR-160, PAR-161) plus heute.
  static const int _referenceDays = 28;

  Future<ReadinessSnapshot> load() async {
    final now = clock.now();
    final local = now.toUtc().add(clock.utcOffsetAt(now));
    final today = DateTime.utc(local.year, local.month, local.day);
    final dev = await SettingsDeveloperModeStore(
      session.settings,
      clock,
    ).read();
    final optIn =
        await session.settings.get(SettingKeys.morningCameraRmssdOptIn) == '1';
    final release = CameraRelease(
      developerMode: dev,
      rmssdOptIn: optIn,
      state: validationState,
    );

    final health = session is HealthStorage
        ? (session as HealthStorage).health
        : null;
    final hrvOn =
        health != null &&
        await _consents.isGranted(healthSourceKey(HealthDataKind.hrvRmssd));
    final rhrOn =
        health != null &&
        await _consents.isGranted(
          healthSourceKey(HealthDataKind.restingHeartRate),
        );
    final sleepOn =
        health != null &&
        await _consents.isGranted(healthSourceKey(HealthDataKind.sleep));

    final days = localDayRanges(
      DateTime(today.year, today.month, today.day - _referenceDays),
      _referenceDays + 1,
    );
    final from = days.first.start;
    final to = days.last.end;
    // Schlaf zählt für die HRV (Hauptschlafphase) und als Faktor.
    final sessions = sleepOn
        ? [
            for (final r in await health.sleepSessions(from, to))
              sleepSessionOf(r),
          ]
        : const <SleepSession>[];

    DeviationResult? hrv;
    if (hrvOn) {
      final samples = await _samples(health, HealthDataKind.hrvRmssd, from, to);
      hrv = healthConnectHrvDeviation(
        processing: processing,
        samples: samples,
        sessions: sessions,
        days: days,
      );
    }
    final rhr = rhrOn
        ? healthConnectRestingHrDeviation(
            processing: processing,
            samples: await _samples(
              health,
              HealthDataKind.restingHeartRate,
              from,
              to,
            ),
            days: days,
          )
        : null;

    var camera = const <DeviationResult>[];
    SleepBand? band;
    var hasMorning = false;
    var all = const <MorningMeasurement>[];
    ReadinessSleepEntry? sleepEntry;
    if (session is MorningStorage) {
      final stored = await (session as MorningStorage).morning.list();
      all = [for (final e in stored) e.value];
      hasMorning = all.isNotEmpty;
      camera = cameraDeviations(all, today: today);
      final counting = morningCountingToday(
        all,
        nowUtc: now.toUtc(),
        utcOffset: clock.utcOffsetAt(now),
      );
      for (final m in counting) {
        band ??= m.sleepBand;
      }
      if (counting.isNotEmpty && release.cameraValuesAllowed) {
        final first = counting.first;
        for (final e in stored) {
          if (identical(e.value, first)) {
            sleepEntry = ReadinessSleepEntry(
              measurementId: e.id,
              band: first.sleepBand,
            );
          }
        }
      }
    }
    final window = await SettingsMorningWindowStore(
      session.settings,
      clock,
    ).read();

    // Erweiterte Stufe (FR-0105): mit Einwilligung für Health Connect oder mit
    // vorhandenen, zulässigen Kamera-Messungen; der Entwicklermodus allein
    // (ohne Messung) lässt es bei der Basisstufe.
    final extended =
        hrvOn ||
        rhrOn ||
        sleepOn ||
        (release.cameraValuesAllowed && hasMorning);
    final loadDay = extended ? await _loadDay() : null;
    final inputs = ReadinessInputs(
      today: today,
      now: now,
      utcOffset: clock.utcOffsetAt(now),
      dayStart: days.last.start,
      hrvHealthConnect: hrv,
      restingHrHealthConnect: rhr,
      cameraDeviations: camera,
      release: release,
      sleepSessions: sessions,
      sleepBand: band,
      // Die Basisstufe braucht weder Belastung noch Befinden (kein Rechnen).
      tsbPercent: readinessTsbPercent(loadDay),
      wellbeing: extended ? await _wellbeing() : null,
      processing: processing,
      morningMeasurements: all,
      morningWindow: window,
      loadRequested: extended,
      loadDay: loadDay,
    );
    return ReadinessSnapshot(
      result: computeReadiness(inputs),
      developerMode: dev,
      extended: extended,
      release: release,
      today: today,
      series: [?hrv, ?rhr, if (release.cameraValuesAllowed) ...camera],
      sleepEntry: sleepEntry,
    );
  }

  Future<List<HealthSample>> _samples(
    HealthImportStore health,
    HealthDataKind kind,
    DateTime from,
    DateTime to,
  ) async => [
    for (final r in await health.values(kind, from, to))
      if (r.value != null)
        HealthSample(time: r.start, value: r.value!, origin: r.origin),
  ];

  Future<LoadDay?> _loadDay() async {
    try {
      return await loadToday?.call();
    } on Object {
      return null;
    }
  }

  /// Befinden des jüngsten beendeten Laufs mit Angabe (Befinden aus WP18).
  Future<ReadinessWellbeing?> _wellbeing() async {
    try {
      final subjective = await session.subjective.readAll();
      ReadinessWellbeing? best;
      for (final r in await session.runs.list()) {
        final w = subjective[r.id]?.subjective.wellbeing;
        if (r.state != RunState.finished || w == null) continue;
        final day = DateTime.parse('${dayOfRun(r)}T00:00:00Z');
        if (best == null || day.isAfter(best.day)) {
          best = ReadinessWellbeing(level: w, day: day);
        }
      }
      return best;
    } on Object {
      return null;
    }
  }
}
