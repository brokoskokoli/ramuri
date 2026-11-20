// Gründe fehlender Faktoren (FR-0111): je Grund feste Eingaben, fester
// Ortstag und feste Versätze (keine Wanduhr, keine Zeitzone des Rechners).
import 'package:core/core.dart';
import 'package:test/test.dart';

const _cet = Duration(hours: 1);
const _cest = Duration(hours: 2);
final _today = DateTime.utc(2026, 11, 14);
const _dev = CameraRelease(developerMode: true, rmssdOptIn: false);

/// Messung am Ortstag [day] (UTC-Datum) um [hour]:[minute] Ortszeit.
MorningMeasurement _m(
  DateTime day, {
  int hour = 7,
  int minute = 0,
  Duration offset = _cet,
  PpgQuality quality = PpgQuality.good,
  double? hr = 58,
  double? rmssd = 42,
  bool outside = false,
  String model = 'M1',
}) => MorningMeasurement(
  measuredAt: DateTime.utc(
    day.year,
    day.month,
    day.day,
    hour,
    minute,
  ).subtract(offset),
  utcOffset: offset,
  posture: RestingPosture.lying,
  deviceManufacturer: 'H',
  deviceModel: model,
  method: 'ppg',
  methodVersion: 1,
  quality: quality,
  restingHrBpm: quality == PpgQuality.unusable ? null : hr,
  rmssdMs: quality == PpgQuality.good ? rmssd : null,
  timingNoiseMs: quality == PpgQuality.good ? 10 : null,
  cameraIntervalsMs: const [],
  beforeValidation: false,
  outsideWindow: outside,
);

DateTime _back(int n) => _today.subtract(Duration(days: n));

/// Gute Messungen an den Tagen [from] bis [to] vor heute (einschließlich),
/// mit Streuung über der MAD-Grenze.
List<MorningMeasurement> _history(int from, int to) => [
  for (var i = from; i <= to; i++)
    _m(_back(i), hr: 54.0 + (i % 5) * 2, rmssd: 36.0 + (i % 5) * 4),
];

/// Modell mit „jetzt“ um [nowHour]:[nowMinute] Ortszeit mit Versatz
/// [offset]; Vorgabe 8:00, also im Standardfenster 4–11.
ReadinessResult _run(
  List<MorningMeasurement> all, {
  DateTime? today,
  CameraRelease release = _dev,
  DeviationResult? hrvHc,
  ReadinessWellbeing? wellbeing,
  MorningWindow window = MorningWindow.standard,
  bool loadRequested = true,
  LoadDay? loadDay,
  int nowHour = 8,
  int nowMinute = 0,
  Duration offset = _cet,
}) {
  final day = today ?? _today;
  return computeReadiness(
    ReadinessInputs(
      today: day,
      now: DateTime.utc(
        day.year,
        day.month,
        day.day,
        nowHour,
        nowMinute,
      ).subtract(offset),
      utcOffset: offset,
      dayStart: day.subtract(offset),
      hrvHealthConnect: hrvHc,
      cameraDeviations: cameraDeviations(all, today: day),
      morningMeasurements: all,
      morningWindow: window,
      release: release,
      wellbeing: wellbeing,
      loadRequested: loadRequested,
      loadDay: loadDay,
    ),
  );
}

ReadinessMissingReason? _hrv(ReadinessResult r) =>
    r.missingReasons[ReadinessFactorId.hrv];
ReadinessMissingReason? _rhr(ReadinessResult r) =>
    r.missingReasons[ReadinessFactorId.restingHeartRate];

LoadDay _loadDay({
  Set<LoadProvisionalReason> ctl = const {},
  Set<LoadProvisionalReason> atl = const {},
  double? atlValue = 30,
}) => LoadDay(
  day: _today,
  load: 10,
  atl: atlValue,
  ctl: 30,
  tsb: 0,
  tsbPercentMean7: null,
  flags: const {},
  atlProvisionalReasons: atl,
  ctlProvisionalReasons: ctl,
  unitCount: 1,
  ratedUnits: 1,
  convertedUnits: 0,
  unratedUnits: 0,
);

void main() {
  group('HRV und Ruhepuls', () {
    test(
      'keine Quelle mit Werten: noch keine Messung, Knopf Morgenmessung',
      () {
        final r = _run(const []);
        expect(
          _hrv(r),
          const ReadinessMissingReason(
            ReadinessMissingCode.noMeasurement,
            catchUp: [ReadinessCatchUp.startMorning],
          ),
        );
        expect(_rhr(r)!.code, ReadinessMissingCode.noMeasurement);
      },
    );

    test('Werte, aber heute keiner: heute noch keine Messung', () {
      final r = _run(_history(1, 20));
      expect(
        _hrv(r),
        const ReadinessMissingReason(
          ReadinessMissingCode.noMeasurementToday,
          catchUp: [ReadinessCatchUp.startMorning],
        ),
      );
    });

    test('Kamera-Messung um 11:30, jetzt 12:00: außerhalb des Zeitfensters, '
        'Hinweis auf morgen ab 4 statt Knopf', () {
      final r = _run([
        ..._history(1, 20),
        _m(_today, hour: 11, minute: 30, outside: true),
      ], nowHour: 12);
      const expected = ReadinessMissingReason(
        ReadinessMissingCode.cameraOutsideWindow,
        windowStartHour: 4,
        windowEndHour: 11,
        catchUp: [ReadinessCatchUp.nextMorningWindow],
        nextWindowStartHour: 4,
      );
      expect(_hrv(r), expected);
      expect(_rhr(r), expected);
    });

    test('Fenster aus der Einstellung steht im Grund', () {
      final r = _run([
        _m(_today, hour: 10, outside: true),
      ], window: const MorningWindow(5, 9));
      expect(_hrv(r)!.windowStartHour, 5);
      expect(_hrv(r)!.windowEndHour, 9);
    });

    test('unbrauchbare Messung heute: Grund unbrauchbar', () {
      final r = _run([
        ..._history(1, 20),
        _m(_today, quality: PpgQuality.unusable),
      ]);
      expect(_hrv(r)!.code, ReadinessMissingCode.cameraQualityUnusable);
      expect(_hrv(r)!.catchUp, [ReadinessCatchUp.startMorning]);
    });

    test('Stufe eingeschränkt: HRV fehlt mit Grund, Ruhepuls zählt', () {
      final r = _run([
        ..._history(1, 20),
        _m(_today, quality: PpgQuality.limited, hr: 56),
      ]);
      expect(r.missing, contains(ReadinessFactorId.hrv));
      expect(
        _hrv(r),
        const ReadinessMissingReason(ReadinessMissingCode.cameraQualityLimited),
      );
      expect(
        r.factors.map((f) => f.id),
        contains(ReadinessFactorId.restingHeartRate),
      );
      expect(
        r.missingReasons.containsKey(ReadinessFactorId.restingHeartRate),
        isFalse,
      );
    });

    test('zweite Messung des Tages ignoriert, Grund der ersten gilt', () {
      final r = _run([
        ..._history(1, 20),
        _m(_today, hour: 6, quality: PpgQuality.limited, hr: 56),
        _m(_today, hour: 7, rmssd: 44, hr: 57),
      ]);
      expect(
        _hrv(r),
        const ReadinessMissingReason(
          ReadinessMissingCode.cameraQualityLimited,
          laterIgnored: true,
        ),
      );
    });

    test('spätere Messung eines anderen Geräts: kein Zusatz „spätere zählen '
        'nicht“', () {
      final r = _run([
        ..._history(1, 20),
        _m(_today, hour: 6, quality: PpgQuality.limited, hr: 56),
        // Eigene Reihe, zählt dort; ohne HRV (eingeschränkt), damit der
        // Grund weiter aus der ersten Messung des Tages kommt.
        _m(_today, hour: 7, quality: PpgQuality.limited, hr: 57, model: 'M2'),
      ]);
      expect(
        _hrv(r),
        const ReadinessMissingReason(ReadinessMissingCode.cameraQualityLimited),
      );
    });

    test('2 Werte in 7 Tagen: 2 von 3', () {
      final r = _run([_m(_back(3)), _m(_today)]);
      expect(
        _hrv(r),
        const ReadinessMissingReason(
          ReadinessMissingCode.tooFewInWindow,
          count: 2,
          required: 3,
        ),
      );
    });

    test('9 Referenztage: 9 von 14, noch 5', () {
      final r = _run([..._history(1, 9), _m(_today)]);
      final h = _hrv(r)!;
      expect(h.code, ReadinessMissingCode.tooFewReference);
      expect(h.count, 9);
      expect(h.required, 14);
      expect(h.remaining, 5);
      expect(h.catchUp, isEmpty);
      expect(_rhr(r)!.count, 9);
    });

    test('gleichmäßige Werte: zu gleichmäßig für einen Vergleich', () {
      final r = _run([
        for (var i = 0; i <= 20; i++) _m(_back(i), hr: 58, rmssd: 42),
      ]);
      expect(_hrv(r)!.code, ReadinessMissingCode.madTooSmall);
      expect(_rhr(r)!.code, ReadinessMissingCode.madTooSmall);
    });

    test('Kamera-HRV nicht freigegeben (ohne Opt-in): Grund gesperrt', () {
      const release = CameraRelease(
        developerMode: false,
        rmssdOptIn: false,
        state: {
          ValidationQuantity.restingHr: ValidationState.passed,
          ValidationQuantity.lnRmssdSupine: ValidationState.passed,
        },
      );
      final r = _run([..._history(1, 20), _m(_today)], release: release);
      expect(
        _hrv(r),
        const ReadinessMissingReason(ReadinessMissingCode.cameraNotReleased),
      );
      expect(r.missing, isNot(contains(ReadinessFactorId.restingHeartRate)));
    });

    test('Health Connect ohne Wert heute: Hinweis auf Health Connect', () {
      final hc = deviationForSeries(
        byDay: {_back(1): 40, _back(2): 41},
        today: _today,
        factor: ReadinessFactor.hrv,
        source: ReadinessSource.healthConnect,
        rules: DeviationRules.hrv,
      );
      final r = _run(const [], hrvHc: hc);
      expect(
        _hrv(r),
        const ReadinessMissingReason(
          ReadinessMissingCode.noMeasurementToday,
          catchUp: [
            ReadinessCatchUp.startMorning,
            ReadinessCatchUp.healthConnectSync,
          ],
        ),
      );
    });

    test('Health Connect mit Wert heute vor der Kamera', () {
      final hc = deviationForSeries(
        byDay: {_today: 40, _back(1): 41},
        today: _today,
        factor: ReadinessFactor.hrv,
        source: ReadinessSource.healthConnect,
        rules: DeviationRules.hrv,
      );
      final r = _run([..._history(1, 9), _m(_today)], hrvHc: hc);
      expect(
        _hrv(r),
        const ReadinessMissingReason(
          ReadinessMissingCode.tooFewInWindow,
          count: 2,
          required: 3,
        ),
      );
    });
  });

  group('Ortstag', () {
    test('Messung um 23:59 des Vortags zählt nicht als heute', () {
      final r = _run([
        ..._history(2, 20),
        _m(_back(1), hour: 23, minute: 59),
      ], window: const MorningWindow(0, 24));
      expect(_hrv(r)!.code, ReadinessMissingCode.noMeasurementToday);
      expect(_hrv(r)!.catchUp, [ReadinessCatchUp.startMorning]);
    });

    test('Uhrumstellung: Ortstag folgt dem Versatz der Messung', () {
      // 25.10.2026: Ende der Sommerzeit in Mitteleuropa (03:00 → 02:00).
      final dst = DateTime.utc(2026, 10, 25);
      final before = DateTime.utc(2026, 10, 24);
      // 02:30 Sommerzeit am Umstellungstag (UTC 00:30) ist heute; 23:59
      // Sommerzeit am Vortag (UTC 21:59) ist gestern.
      final r = _run(
        [
          _m(before, hour: 23, minute: 59, offset: _cest),
          _m(
            dst,
            hour: 2,
            minute: 30,
            offset: _cest,
            quality: PpgQuality.limited,
          ),
        ],
        today: dst,
        window: const MorningWindow(0, 24),
      );
      expect(_hrv(r)!.code, ReadinessMissingCode.cameraQualityLimited);
      // Ohne die Messung des Umstellungstags fehlt der Wert heute.
      final r2 = _run(
        [_m(before, hour: 23, minute: 59, offset: _cest)],
        today: dst,
        window: const MorningWindow(0, 24),
      );
      expect(_hrv(r2)!.code, ReadinessMissingCode.noMeasurementToday);
    });
  });

  group('Morgenfenster: Knopf oder Hinweis auf die nächste Messung', () {
    const sleep = ReadinessFactorId.sleep;
    final outside = [
      ..._history(1, 20),
      _m(_today, hour: 11, minute: 30, outside: true),
    ];

    test('jetzt 10:59, Messung um 3:30 außerhalb: Knopf bleibt', () {
      final r = _run(
        [..._history(1, 20), _m(_today, hour: 3, minute: 30, outside: true)],
        nowHour: 10,
        nowMinute: 59,
      );
      for (final reason in [_hrv(r)!, _rhr(r)!]) {
        expect(reason.code, ReadinessMissingCode.cameraOutsideWindow);
        expect(reason.catchUp, [ReadinessCatchUp.startMorning]);
        expect(reason.nextWindowStartHour, isNull);
      }
    });

    test('jetzt genau 11:00 (Ende): kein Knopf, Hinweis morgen ab 4', () {
      final r = _run(outside, nowHour: 11);
      for (final reason in [_hrv(r)!, _rhr(r)!]) {
        expect(reason.catchUp, [ReadinessCatchUp.nextMorningWindow]);
        expect(reason.nextWindowStartHour, 4);
        expect(reason.nextWindowToday, isFalse);
      }
    });

    test('jetzt genau 4:00 (Beginn): Knopf', () {
      final r = _run(_history(1, 20), nowHour: 4);
      expect(_hrv(r)!.catchUp, [ReadinessCatchUp.startMorning]);
      expect(r.missingReasons[sleep]!.catchUp, [
        ReadinessCatchUp.sleepAtMorning,
        ReadinessCatchUp.startMorning,
      ]);
    });

    test('keine Messung heute, jetzt 14:00: überall Hinweis, Health Connect '
        'bleibt', () {
      final hc = deviationForSeries(
        byDay: {_back(1): 40, _back(2): 41},
        today: _today,
        factor: ReadinessFactor.hrv,
        source: ReadinessSource.healthConnect,
        rules: DeviationRules.hrv,
      );
      final r = _run(_history(1, 20), hrvHc: hc, nowHour: 14);
      expect(
        _hrv(r),
        const ReadinessMissingReason(
          ReadinessMissingCode.noMeasurementToday,
          catchUp: [
            ReadinessCatchUp.nextMorningWindow,
            ReadinessCatchUp.healthConnectSync,
          ],
          nextWindowStartHour: 4,
        ),
      );
      expect(
        _rhr(r),
        const ReadinessMissingReason(
          ReadinessMissingCode.noMeasurementToday,
          catchUp: [ReadinessCatchUp.nextMorningWindow],
          nextWindowStartHour: 4,
        ),
      );
      expect(
        r.missingReasons[sleep],
        const ReadinessMissingReason(
          ReadinessMissingCode.sleepNoEntry,
          catchUp: [
            ReadinessCatchUp.sleepAtMorning,
            ReadinessCatchUp.nextMorningWindow,
          ],
          nextWindowStartHour: 4,
        ),
      );
      for (final reason in r.missingReasons.values) {
        expect(reason.catchUp, isNot(contains(ReadinessCatchUp.startMorning)));
      }
    });

    test(
      'vor Fensterbeginn (jetzt 3:00, keine Messung): Hinweis heute ab 4',
      () {
        final r = _run(_history(1, 20), nowHour: 3);
        for (final reason in [_hrv(r)!, _rhr(r)!, r.missingReasons[sleep]!]) {
          expect(reason.catchUp, contains(ReadinessCatchUp.nextMorningWindow));
          expect(
            reason.catchUp,
            isNot(contains(ReadinessCatchUp.startMorning)),
          );
          expect(reason.nextWindowStartHour, 4);
          expect(reason.nextWindowToday, isTrue);
        }
      },
    );

    test('unbrauchbare Messung heute, jetzt 12:00: Hinweis statt Knopf', () {
      final r = _run([
        ..._history(1, 20),
        _m(_today, quality: PpgQuality.unusable),
      ], nowHour: 12);
      expect(
        _hrv(r),
        const ReadinessMissingReason(
          ReadinessMissingCode.cameraQualityUnusable,
          catchUp: [ReadinessCatchUp.nextMorningWindow],
          nextWindowStartHour: 4,
        ),
      );
    });

    test('eigenes Fenster 6–9 wirkt auf Knopf und Hinweis', () {
      const w = MorningWindow(6, 9);
      ReadinessMissingReason at(int hour, {int minute = 0}) => _hrv(
        _run(_history(1, 20), window: w, nowHour: hour, nowMinute: minute),
      )!;
      expect(at(5, minute: 59).catchUp, [ReadinessCatchUp.nextMorningWindow]);
      expect(at(5, minute: 59).nextWindowStartHour, 6);
      expect(at(5, minute: 59).nextWindowToday, isTrue);
      expect(at(6).catchUp, [ReadinessCatchUp.startMorning]);
      expect(at(8, minute: 59).catchUp, [ReadinessCatchUp.startMorning]);
      // Im Standardfenster wäre 10:00 noch offen.
      expect(at(10).catchUp, [ReadinessCatchUp.nextMorningWindow]);
      expect(at(10).nextWindowStartHour, 6);
      expect(at(10).nextWindowToday, isFalse);
      expect(at(9).catchUp, [ReadinessCatchUp.nextMorningWindow]);
    });

    test('Versatz +1 h und +2 h: Grenze in Ortszeit', () {
      // Derselbe UTC-Zeitpunkt 9:30 ist bei +1 h 10:30 (offen), bei +2 h
      // 11:30 (zu).
      final nowUtc = DateTime.utc(2026, 11, 14, 9, 30);
      ReadinessMissingReason at(Duration offset) => _hrv(
        computeReadiness(
          ReadinessInputs(
            today: _today,
            now: nowUtc,
            utcOffset: offset,
            dayStart: _today.subtract(offset),
            cameraDeviations: cameraDeviations(_history(1, 20), today: _today),
            morningMeasurements: _history(1, 20),
            release: _dev,
          ),
        ),
      )!;
      expect(at(_cet).catchUp, [ReadinessCatchUp.startMorning]);
      expect(at(_cest).catchUp, [ReadinessCatchUp.nextMorningWindow]);
      expect(at(_cest).nextWindowStartHour, 4);
    });

    test(
      'Sommerzeitwechsel: Fensterbeginn folgt dem Versatz am Umstelltag',
      () {
        // 29.03.2026: Beginn der Sommerzeit (02:00 → 03:00). 02:30 UTC ist
        // 4:30 Sommerzeit (offen); mit dem Winterversatz wäre es 3:30 (zu).
        final dst = DateTime.utc(2026, 3, 29);
        final nowUtc = DateTime.utc(2026, 3, 29, 2, 30);
        final history = [
          for (var i = 1; i <= 20; i++)
            _m(
              dst.subtract(Duration(days: i)),
              hr: 54.0 + (i % 5) * 2,
              rmssd: 36.0 + (i % 5) * 4,
            ),
        ];
        ReadinessMissingReason at(Duration offset) => _hrv(
          computeReadiness(
            ReadinessInputs(
              today: dst,
              now: nowUtc,
              utcOffset: offset,
              dayStart: dst.subtract(_cet),
              cameraDeviations: cameraDeviations(history, today: dst),
              morningMeasurements: history,
              release: _dev,
            ),
          ),
        )!;
        expect(at(_cest).catchUp, [ReadinessCatchUp.startMorning]);
        expect(at(_cet).catchUp, [ReadinessCatchUp.nextMorningWindow]);
        expect(at(_cet).nextWindowToday, isTrue);
      },
    );
  });

  group('Validierungssperre ohne Entwicklermodus (K62)', () {
    const locked = CameraRelease(developerMode: false, rmssdOptIn: false);

    test('keine Knöpfe und kein Kamerabezug', () {
      final r = _run([
        ..._history(1, 20),
        _m(_today, hour: 11, minute: 30, outside: true),
      ], release: locked);
      expect(
        _hrv(r),
        const ReadinessMissingReason(ReadinessMissingCode.noMeasurement),
      );
      expect(
        r.missingReasons[ReadinessFactorId.sleep],
        const ReadinessMissingReason(ReadinessMissingCode.sleepNoHealthConnect),
      );
      for (final reason in r.missingReasons.values) {
        expect(reason.catchUp, isNot(contains(ReadinessCatchUp.startMorning)));
        expect(reason.catchUp, isNot(contains(ReadinessCatchUp.enterSleep)));
        expect(reason.code.name, isNot(startsWith('camera')));
      }
    });

    test(
      'außerhalb des Fensters: auch kein Hinweis auf die nächste Messung',
      () {
        for (final hour in [3, 12]) {
          final r = _run(_history(1, 20), release: locked, nowHour: hour);
          for (final reason in r.missingReasons.values) {
            expect(
              reason.catchUp,
              isNot(contains(ReadinessCatchUp.nextMorningWindow)),
            );
            expect(reason.nextWindowStartHour, isNull);
          }
        }
      },
    );
  });

  group('Schlaf', () {
    test('heutige Morgenmessung: Knopf „Schlaf angeben“', () {
      final r = _run([_m(_today)]);
      expect(
        r.missingReasons[ReadinessFactorId.sleep],
        const ReadinessMissingReason(
          ReadinessMissingCode.sleepNoEntry,
          catchUp: [ReadinessCatchUp.enterSleep],
        ),
      );
    });

    test('ohne heutige Morgenmessung: Hinweis und Morgenmessung', () {
      final r = _run([_m(_back(1))]);
      expect(r.missingReasons[ReadinessFactorId.sleep]!.catchUp, [
        ReadinessCatchUp.sleepAtMorning,
        ReadinessCatchUp.startMorning,
      ]);
    });

    test('nur außerhalb des Fensters gemessen: kein „Schlaf angeben“', () {
      final r = _run([_m(_today, hour: 12, outside: true)], nowHour: 13);
      expect(
        r.missingReasons[ReadinessFactorId.sleep]!.catchUp,
        isNot(contains(ReadinessCatchUp.enterSleep)),
      );
    });

    test('Selbstangabe vorhanden: Schlaf fehlt nicht', () {
      final r = computeReadiness(
        ReadinessInputs(
          today: _today,
          now: _today.add(const Duration(hours: 12)),
          release: _dev,
          sleepBand: SleepBand.from7to8,
          morningMeasurements: [_m(_today)],
        ),
      );
      expect(r.missingReasons.containsKey(ReadinessFactorId.sleep), isFalse);
    });
  });

  group('Befinden', () {
    test('vor 5 Tagen: vor 5 Tagen, zählt 3', () {
      final r = _run(
        const [],
        wellbeing: ReadinessWellbeing(level: 3, day: _back(5)),
      );
      expect(
        r.missingReasons[ReadinessFactorId.wellbeing],
        const ReadinessMissingReason(
          ReadinessMissingCode.wellbeingTooOld,
          count: 5,
          required: 3,
          catchUp: [ReadinessCatchUp.wellbeingAfterRun],
        ),
      );
    });

    test('keine Angabe', () {
      final r = _run(const []);
      expect(
        r.missingReasons[ReadinessFactorId.wellbeing]!.code,
        ReadinessMissingCode.wellbeingNone,
      );
    });
  });

  group('Belastung', () {
    ReadinessMissingReason? load(ReadinessResult r) =>
        r.missingReasons[ReadinessFactorId.load];

    test('nicht berechnet: nur bei der erweiterten Einschätzung', () {
      expect(
        load(_run(const [], loadRequested: false))!.code,
        ReadinessMissingCode.loadOnlyExtended,
      );
    });

    test('ohne Verlauf', () {
      expect(load(_run(const []))!.code, ReadinessMissingCode.loadNoHistory);
      expect(
        load(_run(const [], loadDay: _loadDay(atlValue: null)))!.code,
        ReadinessMissingCode.loadNoHistory,
      );
    });

    test('zu kurze Historie: 126 Tage (PAR-089)', () {
      final r = _run(
        const [],
        loadDay: _loadDay(ctl: {LoadProvisionalReason.startup}),
      );
      expect(
        load(r),
        const ReadinessMissingReason(
          ReadinessMissingCode.loadHistoryShort,
          required: 126,
        ),
      );
      expect(load(r)!.catchUp, isEmpty);
    });

    test('ohne Zusage, Lücken, ohne 7-Tage-Mittel', () {
      expect(
        load(
          _run(
            const [],
            loadDay: _loadDay(ctl: {LoadProvisionalReason.noCommitment}),
          ),
        )!.code,
        ReadinessMissingCode.loadNoCommitment,
      );
      expect(
        load(
          _run(
            const [],
            loadDay: _loadDay(ctl: {LoadProvisionalReason.missingUnits}),
          ),
        ),
        const ReadinessMissingReason(
          ReadinessMissingCode.loadMissingUnits,
          count: 42,
          required: 10,
        ),
      );
      expect(
        load(_run(const [], loadDay: _loadDay())),
        const ReadinessMissingReason(
          ReadinessMissingCode.loadNoMean,
          required: 7,
        ),
      );
    });
  });

  test('Gründe ändern die Berechnung nicht', () {
    final all = [..._history(1, 20), _m(_today)];
    final a = _run(all);
    final b = computeReadiness(
      ReadinessInputs(
        today: _today,
        now: _today.add(const Duration(hours: 12)),
        dayStart: _today.subtract(_cet),
        cameraDeviations: cameraDeviations(all, today: _today),
        release: _dev,
      ),
    );
    expect(a.state, b.state);
    expect(a.value, b.value);
    expect(a.missing, b.missing);
    expect(a.levelReasons, b.levelReasons);
    expect(a.missingReasons.keys, a.missing);
  });
}
