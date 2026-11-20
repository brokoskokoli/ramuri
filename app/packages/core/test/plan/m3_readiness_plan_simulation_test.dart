import 'dart:math';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:test/test.dart';

// Abschlussprüfung M3, Kernlogik. Synthetische Daten: Uhr, Kamera, Ziel und
// Plan sind ausgedacht.
//
// 60 Tage Reihen – Uhr (Health Connect: Schlaf, HRV, Ruhepuls), Kamera liegend
// und sitzend (an manchen Tagen beide), Lücken, Quellwechsel der Uhr, eine
// Woche ohne Uhr – laufen Tag für Tag durch Readiness (wie der
// Readiness-Dienst der App die Eingaben baut) und Plan (Wochenprüfung und
// Nachprüfung nach Import oder Morgenmessung). Das für jeden Validierungsstand
// (nicht geprüft, bestanden mit und ohne Opt-in, eingeschränkt, nicht
// bestanden), mit und ohne Entwicklermodus, bei „fix“ und „adaptiv“.
//
// Invarianten je Tag:
// * „fix“: Plan gleich dem Plan ohne Gesundheitsdaten (FR-0157, FR-0216).
// * „adaptiv“: Abweichung vom Plan ohne Gesundheitsdaten nur als Lockerung
//   der harten Einheit an einem Tag mit niedrigem Wert (PAR-173, FR-0158).
// * Ohne Entwicklermodus und vor bestandener Validierung gehen Kamerawerte
//   nirgends ein, weder in Readiness noch in den Plan (K-1, K62 Punkt 1).
// * Zahl und Stufe nur mit genug Daten (FR-0105, PAR-147 bis PAR-150).
// * Ein zweiter Durchlauf ergibt dasselbe (NFR-0005).

const _days = 60;
const _ref = 28; // Referenztage vor heute wie im Readiness-Dienst

/// Ortszeit am Tag [n] der Simulation (Tag 0: Mittwoch, 11.11.2026).
DateTime _local(int n, [int h = 0, int m = 0]) =>
    DateTime(2026, 11, 11 + n, h, m);

/// Ortstag als UTC-Datum: „heute“ für Readiness und Plan.
DateTime _key(int n) => DateTime.utc(2026, 11, 11 + n);
DateTime _now(int n) => _local(n, 9).toUtc();

const _p = HealthProcessing();

/// Synthetische Reihen über 60 Tage.
class _Data {
  final hrv = <HealthSample>[];
  final rhr = <HealthSample>[];
  final sleep = <SleepSession>[];
  final morning = <MorningMeasurement>[];
  final tsb = <double?>[];
}

MorningMeasurement _morning(
  int n, {
  required RestingPosture posture,
  required int minute,
  required double hr,
  double? rmssd,
  PpgQuality quality = PpgQuality.good,
  SleepBand? band,
}) {
  final t = _local(n, 7, minute);
  return MorningMeasurement(
    measuredAt: t.toUtc(),
    utcOffset: t.timeZoneOffset,
    posture: posture,
    deviceManufacturer: 'Hersteller',
    deviceModel: 'Modell-1',
    method: ppgMethod,
    methodVersion: ppgMethodVersion,
    quality: quality,
    restingHrBpm: hr,
    rmssdMs: quality == PpgQuality.good ? rmssd : null,
    timingNoiseMs: 10,
    sleepBand: band,
    cameraIntervalsMs: const [],
    beforeValidation: true,
    outsideWindow: false,
  );
}

_Data _series(int seed) {
  final rnd = Random(seed);
  final d = _Data();
  for (var n = 0; n < _days; n++) {
    // Quellwechsel der Uhr an Tag 35 (PAR-189); Tage 18 bis 25 ohne Uhr,
    // dazu einzelne Lücken.
    final origin = n < 35 ? 'com.example.uhr.a' : 'com.example.uhr.b';
    final watch = !(n >= 18 && n < 26) && rnd.nextInt(9) != 0;
    // Etwa jeder dritte Tag schlecht: kurze Nacht, niedrige HRV, hoher
    // Ruhepuls, hohe Belastung.
    final bad = rnd.nextInt(3) == 0;
    if (watch) {
      final start = _local(n - 1, 23).toUtc();
      final hours = bad ? 3 + rnd.nextDouble() : 6 + rnd.nextDouble() * 2.5;
      final end = start.add(Duration(minutes: (hours * 60).round()));
      final phases = rnd.nextBool();
      d.sleep.add(
        SleepSession(
          origin: origin,
          start: start,
          end: end,
          stages: phases
              ? [
                  SleepStage(
                    kind: SleepStageKind.sleeping,
                    start: start,
                    end: end.subtract(const Duration(minutes: 25)),
                  ),
                  SleepStage(
                    kind: SleepStageKind.awake,
                    start: end.subtract(const Duration(minutes: 25)),
                    end: end,
                  ),
                ]
              : const [],
        ),
      );
      d.hrv.add(
        HealthSample(
          time: start.add(const Duration(hours: 2)),
          value: bad ? 14 + rnd.nextDouble() * 6 : 35 + rnd.nextDouble() * 30,
          origin: origin,
        ),
      );
      if (rnd.nextInt(6) != 0) {
        d.rhr.add(
          HealthSample(
            time: _local(n, 6, 30).toUtc(),
            value: (bad ? 64 : 46) + rnd.nextInt(10).toDouble(),
            origin: origin,
          ),
        );
      }
    }
    // Kamera liegend an den meisten Tagen, sitzend an manchen, an einigen
    // Tagen beide; „eingeschränkt“ ohne RMSSD.
    final band = rnd.nextInt(3) == 0
        ? SleepBand.values[rnd.nextInt(SleepBand.values.length)]
        : null;
    if (rnd.nextInt(5) != 0) {
      d.morning.add(
        _morning(
          n,
          posture: RestingPosture.lying,
          minute: 0,
          hr: 48 + rnd.nextInt(18).toDouble(),
          rmssd: 20 + rnd.nextDouble() * 50,
          quality: rnd.nextInt(8) == 0 ? PpgQuality.limited : PpgQuality.good,
          band: band,
        ),
      );
    }
    if (rnd.nextInt(3) == 0) {
      d.morning.add(
        _morning(
          n,
          posture: RestingPosture.sitting,
          minute: 20,
          hr: 52 + rnd.nextInt(18).toDouble(),
          rmssd: 15 + rnd.nextDouble() * 45,
          band: band,
        ),
      );
    }
    d.tsb.add(
      rnd.nextInt(4) == 0
          ? null
          : bad
          ? -40 + rnd.nextDouble() * 5
          : -20 + rnd.nextDouble() * 30,
    );
  }
  return d;
}

/// Readiness am Tag [n], gebaut wie im Readiness-Dienst der App: 29 Ortstage,
/// nur Daten bis jetzt, Kamerareihen aus allen Morgenmessungen, Schlafangabe
/// der zählenden Messung von heute. [camera] `false`: ohne Kamera.
ReadinessResult _readiness(
  _Data d,
  int n,
  CameraRelease release, {
  bool camera = true,
}) {
  final now = _now(n);
  final days = localDayRanges(_local(n - _ref), _ref + 1);
  final from = days.first.start, to = days.last.end;
  bool inWindow(DateTime t) =>
      !t.isBefore(from) && t.isBefore(to) && !t.isAfter(now);
  final sessions = [
    for (final s in d.sleep)
      if (s.end.isAfter(from) && s.start.isBefore(to) && !s.end.isAfter(now)) s,
  ];
  final hrv = healthConnectHrvDeviation(
    processing: _p,
    samples: [
      for (final s in d.hrv)
        if (inWindow(s.time)) s,
    ],
    sessions: sessions,
    days: days,
  );
  final rhr = healthConnectRestingHrDeviation(
    processing: _p,
    samples: [
      for (final s in d.rhr)
        if (inWindow(s.time)) s,
    ],
    days: days,
  );
  final all = camera
      ? [
          for (final m in d.morning)
            if (!m.measuredAt.isAfter(now)) m,
        ]
      : const <MorningMeasurement>[];
  SleepBand? band;
  for (final m in morningCountingToday(
    all,
    nowUtc: now,
    utcOffset: _local(n, 9).timeZoneOffset,
  )) {
    band ??= m.sleepBand;
  }
  return computeReadiness(
    ReadinessInputs(
      today: _key(n),
      now: now,
      dayStart: days.last.start,
      hrvHealthConnect: hrv,
      restingHrHealthConnect: rhr,
      cameraDeviations: cameraDeviations(all, today: _key(n)),
      release: release,
      sleepSessions: sessions,
      sleepBand: band,
      tsbPercent: d.tsb[n],
      morningMeasurements: all,
    ),
  );
}

/// Alles, was die Readiness zeigt oder weitergibt.
String _sigR(ReadinessResult r) => [
  r.method,
  r.methodVersion,
  r.state.name,
  r.value,
  r.band?.name,
  r.capped,
  r.level.name,
  r.hasFreshMeasurement,
  for (final f in r.factors)
    'F:${f.id.name}/${f.source.name}/${f.score}/${f.mark.name}/'
        '${f.referenceCount}/${f.estimated}/${f.fewMeasurements}',
  for (final f in r.facts)
    'T:${f.kind.name}/${f.source.name}/${f.z}/${f.hours}/${f.mark.name}',
  for (final f in r.markedFacts)
    'M:${f.kind.name}/${f.source.name}/${f.z}/${f.mark.name}',
  for (final l in r.levelReasons) 'L:${l.code.name}/${l.count}',
  'missing:${r.missing.map((e) => e.name)}',
  for (final e in r.missingReasons.entries)
    'R:${e.key.name}/${e.value.code.name}/${e.value.count}',
  'E:${r.explanation.code.name}',
  for (final x in r.explanation.drivers)
    'D:${x.id.name}/${x.source.name}/${x.direction.name}',
].join('|');

bool _cameraOrSelfReport(ReadinessFactorSource s) =>
    s == ReadinessFactorSource.camera || s == ReadinessFactorSource.selfReport;

TrainingGoal _goal() => TrainingGoal(
  type: GoalType.distance,
  distance: GoalDistance.tenKilometers,
  targetDate: DateTime(2027, 6, 1),
  runDays: const {2, 4, 6},
  maxSessionSeconds: 7200,
  weeklyCapSeconds: 240 * 60.0,
  createdAt: DateTime.utc(2026, 11, 1),
  hardSessionEnabled: true,
  canRun30: ContinuousRun30.yes,
);

String _sig(PlanUnit u) =>
    '${u.day.toIso8601String()}|${u.kind.name}|${u.minutes}|'
    '${[for (final s in u.segments) '${s.kind.name}:${s.minutes}'].join(',')}|'
    '${u.pinned}|${u.fixed.name}|${u.runId}';

/// Härte einer Einheit: Ruhe < locker/lang < hart.
int _rank(PlanUnit u) => switch (u.kind) {
  PlanUnitKind.rest => 0,
  PlanUnitKind.intervals || PlanUnitKind.tempo || PlanUnitKind.progressive => 2,
  _ => 1,
};

/// Ein Plan im Speicher mit Schalter [mode]. [health] `false`: der Zwilling
/// ohne Gesundheitsdaten (dieselben Auslöser, keine Readiness).
class _Plan {
  _Plan._(this.session) : plans = (session as PlanStorage).plans;
  final StorageSession session;
  final PlanRepository plans;

  static Future<_Plan> open(PlanAdaptationMode mode) async {
    final p = _Plan._(
      await FakeStorage().open(Uint8List.fromList(List.generate(32, (i) => i))),
    );
    await (p.session as GoalStorage).goals.save(_goal(), today: _key(0));
    await SettingsPlanAdaptationStore(p.session.settings)
        .set(mode, at: _now(0));
    await p.recalc(
      PlanTrigger.create,
      0,
      inputs: PlanInputs.forNewGoal(
        _goal(),
        _key(0),
      ).copyWith(startWeeklyMinutes: 180),
    );
    return p;
  }

  Future<PlanRecalculation> recalc(
    PlanTrigger t,
    int n, {
    Iterable<PlanReadinessDay> readiness = const [],
    PlanInputs? inputs,
    String? reason,
  }) => recalculatePlan(
    plans: plans,
    settings: session.settings,
    trigger: t,
    today: _key(n),
    now: _now(n),
    readiness: readiness,
    inputs: inputs,
    reason: reason,
    warning: (session as WarningStorage).warning,
  );

  /// Ein Tag: montags die Wochenprüfung, dann die Prüfung nach Import oder
  /// Morgenmessung, wenn heute eine harte Einheit offen ist. Der Kern bekommt
  /// den heutigen Wert auch bei „fix“ (die App ruft dort nicht, der Kern muss
  /// ihn trotzdem übergehen). Der Zwilling rechnet an denselben Stellen ohne
  /// Readiness.
  Future<void> day(int n, PlanReadinessDay? today, {required bool twin}) async {
    if (_key(n).weekday == DateTime.monday) {
      await recalc(PlanTrigger.weekly, n);
    }
    final unit = await plans.unitOn(_key(n));
    if (unit == null || !recoveryEasable(unit)) return;
    if (today == null || !today.eases) return;
    await recalc(
      PlanTrigger.feedback,
      n,
      readiness: twin ? const [] : [today],
      reason: planReasonReadiness,
    );
  }

  Future<Map<DateTime, PlanUnit>> units() async => {
    for (final u in await plans.unitsBetween(_key(-7), _key(_days + 14)))
      planDay(u.day): u,
  };
}

/// Validierungsstand und Entwicklermodus.
class _Case {
  const _Case(this.name, this.state, this.optIn, this.dev);
  final String name;
  final ValidationState state;
  final bool optIn;
  final bool dev;

  CameraRelease get release => CameraRelease(
    developerMode: dev,
    rmssdOptIn: optIn,
    state: {
      ValidationQuantity.restingHr: state,
      ValidationQuantity.lnRmssdSupine: state,
    },
  );

  /// Vor bestandener Validierung ohne Entwicklermodus (K-1, K62 Punkt 1).
  bool get locked => !dev && state != ValidationState.passed;

  @override
  String toString() => '$name, Entwicklermodus ${dev ? 'an' : 'aus'}';
}

final _cases = [
  for (final dev in [false, true]) ...[
    _Case('nicht geprüft', ValidationState.notChecked, true, dev),
    _Case('bestanden mit Opt-in', ValidationState.passed, true, dev),
    _Case('bestanden ohne Opt-in', ValidationState.passed, false, dev),
    _Case('eingeschränkt', ValidationState.limited, true, dev),
    _Case('nicht bestanden', ValidationState.failed, true, dev),
  ],
];

/// Ergebnis eines Durchlaufs: Spur je Tag (Readiness und Plan) und Zähler.
class _Run {
  final trace = <String>[];
  int numbers = 0;
  int cameraFactors = 0;
  int eased = 0;
  int lowDays = 0;
}

/// Ein Durchlauf über 60 Tage für [c] und [mode] mit allen Invarianten.
Future<_Run> _simulate(_Data d, _Case c, PlanAdaptationMode mode) async {
  final run = _Run();
  final plan = await _Plan.open(mode);
  final twin = await _Plan.open(mode);
  final release = c.release;
  final lowOn = <DateTime>{};
  int? firstNumber;
  for (var n = 0; n < _days; n++) {
    final r = _readiness(d, n, release);
    final why = '$c, ${mode.name}, Tag $n';

    // K-1: vor der Freischaltung ohne Entwicklermodus wie ganz ohne Kamera.
    if (c.locked) {
      expect(
        _sigR(r),
        _sigR(_readiness(d, n, release, camera: false)),
        reason: why,
      );
      expect(
        [
          ...r.factors.map((f) => f.source),
          ...r.facts.map((f) => f.source),
          ...r.markedFacts.map((f) => f.source),
        ].where(_cameraOrSelfReport),
        isEmpty,
        reason: why,
      );
    }
    if (r.factors.any((f) => f.source == ReadinessFactorSource.camera)) {
      run.cameraFactors++;
    }

    // FR-0105, PAR-147 bis PAR-150: Zahl und Stufe nur mit genug Daten.
    final number = r.state == ReadinessState.number;
    expect(r.level != ReadinessLevel.notDeterminable, number, reason: why);
    expect(r.value != null, number, reason: why);
    if (number) {
      firstNumber ??= n;
      run.numbers++;
      final hrv = r.factors.singleWhere((f) => f.id == ReadinessFactorId.hrv);
      expect(
        r.factors.where((f) => f.id == ReadinessFactorId.sleep),
        hasLength(1),
        reason: why,
      );
      expect(
        hrv.referenceCount,
        greaterThanOrEqualTo(readinessMinReferenceValues),
        reason: why,
      );
      if (r.level == ReadinessLevel.sufficient ||
          r.level == ReadinessLevel.good) {
        expect(
          hrv.referenceCount,
          greaterThanOrEqualTo(readinessSufficientHrvReference),
          reason: why,
        );
        expect(
          r.factors.where((f) => f.id == ReadinessFactorId.restingHeartRate),
          isNotEmpty,
          reason: why,
        );
      }
      if (r.level == ReadinessLevel.good) {
        expect(
          hrv.referenceCount,
          greaterThanOrEqualTo(readinessGoodHrvReference),
          reason: why,
        );
      }
    }

    // Plan: heutiger Wert wie in der App (PlanReadinessDay.of).
    final today = PlanReadinessDay.of(_key(n), r);
    if (today.eases) {
      lowOn.add(_key(n));
      run.lowDays++;
    }
    final before = await plan.units();
    await plan.day(n, today, twin: false);
    await twin.day(n, today, twin: true);
    final after = await plan.units();
    final base = await twin.units();
    expect(after.keys.toSet(), base.keys.toSet(), reason: why);
    for (final day in base.keys) {
      final a = after[day]!, b = base[day]!;
      // Vergangene Tage bleiben, was sie waren.
      if (day.isBefore(_key(n)) && before.containsKey(day)) {
        expect(_sig(a), _sig(before[day]!), reason: '$why, $day');
      }
      if (_sig(a) == _sig(b)) continue;
      // Abweichung vom Plan ohne Gesundheitsdaten: nur „adaptiv“, nur eine
      // Lockerung, nur an einem Tag mit niedrigem Wert, Dauer gleich.
      expect(mode, PlanAdaptationMode.adaptive, reason: '$why, $day');
      expect(lowOn, contains(day), reason: '$why, $day');
      expect(day.isAfter(_key(n)), isFalse, reason: '$why, $day');
      expect(_rank(a), lessThan(_rank(b)), reason: '$why, $day');
      expect(a.kind, PlanUnitKind.easy, reason: '$why, $day');
      expect(a.minutes, b.minutes, reason: '$why, $day');
    }
    if (mode == PlanAdaptationMode.adaptive) {
      final u = after[_key(n)];
      if (u != null && _sig(u) != _sig(base[_key(n)]!)) {
        run.eased++;
        final last = (await plan.plans.history()).last;
        expect(last.reason, planReasonReadiness, reason: why);
        expect(
          recoveryEasedFromSummary(last.summary)
              .any((e) => planDay(e.day) == _key(n)),
          isTrue,
          reason: why,
        );
      }
    }
    run.trace.add(
      '$n|${_sigR(r)}|${[for (final u in after.values) _sig(u)].join(';')}',
    );
  }
  // Ohne Referenz keine Zahl: frühestens nach der Mindestzahl Referenztage.
  expect(firstNumber, isNotNull, reason: '$c');
  expect(
    firstNumber!,
    greaterThanOrEqualTo(readinessMinReferenceValues),
    reason: '$c',
  );
  // Der Zwilling ohne Gesundheitsdaten hat nie eine Fassung mit Grund
  // „readiness“ und nichts Gelockertes.
  for (final v in await twin.plans.history()) {
    expect(recoveryEasedFromSummary(v.summary), isEmpty, reason: '$c');
  }
  if (mode == PlanAdaptationMode.fixed) {
    expect(run.eased, 0, reason: '$c');
    for (final v in await plan.plans.history()) {
      expect(recoveryEasedFromSummary(v.summary), isEmpty, reason: '$c');
    }
  }
  return run;
}

void main() {
  for (final seed in [11]) {
    final data = _series(seed);
    group('Reihe $seed', () {
      for (final mode in PlanAdaptationMode.values) {
        test('60 Tage bei „${mode.name}“, alle Validierungsstände mit und '
            'ohne Entwicklermodus: Invarianten je Tag, zweiter Durchlauf '
            'gleich', () async {
          final runs = <_Case, _Run>{};
          for (final c in _cases) {
            runs[c] = await _simulate(data, c, mode);
          }
          // Ganz ohne Kamera: Referenz für die Fälle vor der Freischaltung.
          final noCamera = <String>[];
          for (var n = 0; n < _days; n++) {
            noCamera.add(
              _sigR(
                _readiness(
                  data,
                  n,
                  const CameraRelease(developerMode: false, rmssdOptIn: false),
                  camera: false,
                ),
              ),
            );
          }
          for (final c in _cases.where((c) => c.locked)) {
            // Readiness und Plan gleich in allen gesperrten Fällen.
            expect(runs[c]!.trace, runs[_cases.first]!.trace, reason: '$c');
            expect(runs[c]!.cameraFactors, 0, reason: '$c');
          }
          for (var n = 0; n < _days; n++) {
            final t = runs[_cases.first]!.trace[n];
            expect(t, startsWith('$n|${noCamera[n]}|'), reason: 'Tag $n');
          }
          // Die Reihe prüft etwas: Zahlen, niedrige Tage, Kamera zählt mit
          // Entwicklermodus und nach bestandener Validierung, Lockerungen
          // bei „adaptiv“.
          for (final c in _cases) {
            expect(runs[c]!.numbers, greaterThan(10), reason: '$c');
            expect(runs[c]!.lowDays, greaterThan(0), reason: '$c');
            if (!c.locked) {
              expect(runs[c]!.cameraFactors, greaterThan(0), reason: '$c');
            }
            if (mode == PlanAdaptationMode.adaptive) {
              expect(runs[c]!.eased, greaterThan(0), reason: '$c');
            }
          }
          // Zweiter Durchlauf identisch (deterministisch, NFR-0005).
          for (final c in [_cases[6]]) {
            final again = await _simulate(_series(seed), c, mode);
            expect(again.trace, runs[c]!.trace, reason: '$c');
          }
        });
      }
    });
  }
}
