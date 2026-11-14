import 'package:core/core.dart';

/// Was die Karte „Erholung“ auf „Heute“ braucht (WP34 Teil D1).
class ReadinessSnapshot {
  const ReadinessSnapshot({
    required this.result,
    required this.developerMode,
    required this.extended,
  });

  final ReadinessResult result;

  /// Entwicklermodus an: nur der unauffällige Hinweis, keine Kennzeichnung.
  final bool developerMode;

  /// `true`: erweiterte Stufe (Gesundheitsdaten freigegeben oder Kamerawerte
  /// zulässig). `false`: Basisstufe, nur der Texthinweis aus WP23 (FR-0105,
  /// FR-0107).
  final bool extended;
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
    int span = 0;
    if (hrvOn) {
      final samples = await _samples(health, HealthDataKind.hrvRmssd, from, to);
      hrv = healthConnectHrvDeviation(
        processing: processing,
        samples: samples,
        sessions: sessions,
        days: days,
      );
      final origin = hrv.origin;
      if (origin != null) {
        final perDay = hrvDayValues(processing, samples, sessions, days);
        span = readinessSourceSpanDays([
          for (var i = 0; i < days.length; i++)
            if (perDay[i][origin] != null) _dayOf(days[i]),
        ], today);
      }
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
    if (session is MorningStorage) {
      final all = [
        for (final e in await (session as MorningStorage).morning.list())
          e.value,
      ];
      camera = cameraDeviations(all, today: today);
      for (final m in morningCountingToday(
        all,
        nowUtc: now.toUtc(),
        utcOffset: clock.utcOffsetAt(now),
      )) {
        band ??= m.sleepBand;
      }
    }

    final extended = hrvOn || rhrOn || sleepOn || release.cameraValuesAllowed;
    final inputs = ReadinessInputs(
      today: today,
      now: now,
      hrvHealthConnect: hrv,
      restingHrHealthConnect: rhr,
      cameraDeviations: camera,
      release: release,
      sleepSessions: sessions,
      sleepBand: band,
      // Die Basisstufe braucht weder Belastung noch Befinden (kein Rechnen).
      tsbPercent: extended ? await _tsb() : null,
      wellbeing: extended ? await _wellbeing() : null,
      processing: processing,
      hrvSourceSpanDays: span,
    );
    return ReadinessSnapshot(
      result: computeReadiness(inputs),
      developerMode: dev,
      extended: extended,
    );
  }

  static DateTime _dayOf(DayRange d) {
    final l = d.start.toLocal();
    return DateTime.utc(l.year, l.month, l.day);
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

  Future<double?> _tsb() async {
    try {
      return readinessTsbPercent(await loadToday?.call());
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
