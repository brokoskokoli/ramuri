import 'dart:async';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:running_app/features/plan/plan_controller.dart';
import 'package:running_app/features/plan/plan_data_reader.dart';
import 'package:running_app/features/plan/plan_screen.dart';
import 'package:running_app/features/settings/app_settings.dart';
import 'package:running_app/offload_scope.dart';
import 'package:running_app/ui/ui.dart';

import 'app_harness.dart';
import 'history_summary_test.dart' show started;

final Uint8List _key = Uint8List.fromList(List.generate(32, (i) => i));

/// Mittwoch, 11.11.2026, mittags; die Woche beginnt am Montag, 9.11.
final _now = DateTime.utc(2026, 11, 11, 12);
final _mon = DateTime.utc(2026, 11, 9);
DateTime _d(int n) => _mon.add(Duration(days: n));

TrainingGoal _goal({double capMinutes = 240}) => TrainingGoal(
  type: GoalType.distance,
  distance: GoalDistance.tenKilometers,
  targetDate: DateTime.utc(2027, 3, 14),
  runDays: const {1, 2, 4, 6},
  maxSessionSeconds: 7200,
  weeklyCapSeconds: capMinutes * 60,
  createdAt: DateTime.utc(2026, 11, 1),
  canRun30: ContinuousRun30.yes,
  hardSessionEnabled: false,
);

PlanUnit _u(int day, PlanUnitKind kind, int minutes) => PlanUnit(
  day: _d(day),
  kind: kind,
  phase: PlanPhase.build,
  weekIndex: day ~/ 7,
  minutes: minutes,
  segments: [PlanSegment(kind: PlanSegmentKind.easy, minutes: minutes)],
);

/// Controller ohne wöchentliche Prüfung beim Öffnen (die gespeicherten
/// Einheiten bleiben, wie der Test sie anlegt).
class _NoCheck extends PlanController {
  _NoCheck(StorageSession session, Clock clock)
    : super(session: session, clock: clock);
  @override
  Future<void> open() => reload();
}

/// Wie [_NoCheck]; [gate] hält das Lesen der Einheiten an, [fail] lässt es
/// scheitern (Speicherfehler).
class _Gated extends _NoCheck {
  _Gated(super.session, super.clock);
  Completer<void>? gate;
  bool fail = false;
  @override
  Future<List<PlanUnit>> unitsBetween(DateTime from, DateTime to) async {
    if (fail) throw StateError('Speicher nicht lesbar');
    final g = gate;
    if (g != null) await g.future;
    return super.unitsBetween(from, to);
  }
}

/// Wie [_NoCheck], merkt sich die ändernden Aufrufe; [fail] lässt sie
/// scheitern, ohne den Speicher zu berühren, [failCheck] die Prüfungen.
class _Spy extends _NoCheck {
  _Spy(super.session, super.clock);
  final calls = <String>[];

  /// Die beim Ruhetag übergebene gesehene Einheit (FR-0176).
  final seenUnitIds = <int?>[];
  bool fail = false;
  bool failCheck = false;

  /// Hält die Prüfung des Ersetzens je Art an (Rennen beim Artwechsel).
  final replaceGates = <PlanUnitKind, Completer<void>>{};

  /// Ersetzt das Ergebnis der Prüfungen (gesperrte Fälle).
  PlanReplaceCheck Function(PlanUnitKind kind)? replaceResult;
  PlanRestDayCheck Function(DateTime day)? restResult;

  @override
  Future<PlanReplaceCheck?> checkReplace(
    PlanUnit unit,
    PlanUnitKind kind,
  ) async {
    if (failCheck) throw StateError('Prüfung gescheitert');
    final gate = replaceGates[kind];
    if (gate != null) await gate.future;
    final r = replaceResult;
    return r != null ? r(kind) : super.checkReplace(unit, kind);
  }

  @override
  Future<PlanRestDayCheck?> checkRestDay(DateTime day) async {
    final r = restResult;
    return r != null ? r(day) : super.checkRestDay(day);
  }

  @override
  Future<PlanActionResult> replaceUnit(int unitId, PlanUnitKind kind) async {
    calls.add('replace $unitId ${kind.name}');
    return fail ? PlanActionResult.failed : super.replaceUnit(unitId, kind);
  }

  @override
  Future<PlanActionResult> setRestDay(
    DateTime day, {
    required int? expectedUnitId,
    DateTime? moveUnitTo,
  }) async {
    calls.add(
      'rest ${_iso(day)} ${moveUnitTo == null ? '-' : _iso(moveUnitTo)}',
    );
    seenUnitIds.add(expectedUnitId);
    return fail
        ? PlanActionResult.failed
        : super.setRestDay(
            day,
            expectedUnitId: expectedUnitId,
            moveUnitTo: moveUnitTo,
          );
  }

  @override
  Future<PlanActionResult> clearRestDay(DateTime day) async {
    calls.add('clear ${_iso(day)}');
    return fail ? PlanActionResult.failed : super.clearRestDay(day);
  }
}

String _iso(DateTime d) => d.toIso8601String().substring(0, 10);

/// Schlüsselteil des Tags [n] ab Montag, 9.11.
String _k(int n) => '2026-11-${(9 + n).toString().padLeft(2, '0')}';

/// Tag [n] antippen und im Blatt [action] wählen.
Future<void> _sheet(WidgetTester tester, int n, String action) async {
  await tester.tap(key('calendar_day_${_k(n)}'));
  await tester.pumpAndSettle();
  await tester.tap(key(action));
  await tester.pumpAndSettle();
}

/// Plan mit festen Einheiten: Mo 9.11. locker (erledigt), Di 10.11. locker
/// (ausgefallen), Do 12.11. Intervalle, Sa 14.11. lang; Folgewoche Di
/// locker, Do Intervalle, Sa lang. Mi 11.11. (heute) und So sind frei.
///
/// [extra]: weitere Einheiten; [freeRuns]: Läufe ohne Einheit je Tag (ab
/// Montag 9.11.) mit RPE-Angabe (`null` = keine).
Future<(StorageSession, FakeClock)> _seed({
  double capMinutes = 240,
  List<PlanUnit> extra = const [],
  Map<int, int?> freeRuns = const {},
}) async {
  final session = await FakeStorage().open(_key);
  final clock = FakeClock(_now);
  final goal = _goal(capMinutes: capMinutes);
  await (session as GoalStorage).goals.save(goal, today: _d(0));
  final plans = (session as PlanStorage).plans;
  final inputs = PlanInputs(
    anchor: _mon,
    startWeeklyMinutes: 145,
    today: _d(0),
    easyPaceSecondsPerKm: 360,
    easyRunCount: 4,
  );
  await plans.writeVersion(
    PlanVersionDraft(
      createdAt: _d(0),
      validFrom: _d(0),
      trigger: PlanTrigger.create,
      reason: 'start',
      version: const PlanVersion(),
      inputs: inputs,
      summary: const {'larger': false, 'changedUnitCount': 7},
      units: [
        _u(0, PlanUnitKind.easy, 30),
        _u(1, PlanUnitKind.easy, 30),
        _u(3, PlanUnitKind.intervals, 45),
        _u(5, PlanUnitKind.long, 70),
        _u(8, PlanUnitKind.easy, 30),
        _u(10, PlanUnitKind.intervals, 45),
        _u(12, PlanUnitKind.long, 70),
        ...extra,
      ],
      readState: planUnitsFingerprint(
        await plans.unitsBetween(_mon, planFarFuture),
      ),
    ),
  );
  final run = await session.runs.create(
    startedAt: _d(0).add(const Duration(hours: 8)),
  );
  await session.runs.setState(
    run.id,
    RunState.finished,
    endedAt: _d(0).add(const Duration(hours: 9)),
    endedUtcOffset: Duration.zero,
  );
  await plans.assignRun((await plans.unitOn(_d(0)))!.id!, run.id);
  for (final MapEntry(key: day, value: rpe) in freeRuns.entries) {
    final free = await session.runs.create(
      startedAt: _d(day).add(const Duration(hours: 7)),
    );
    await session.runs.setState(
      free.id,
      RunState.finished,
      endedAt: _d(day).add(const Duration(hours: 8)),
      endedUtcOffset: Duration.zero,
    );
    if (rpe != null) {
      await session.subjective.save(free.id, RunSubjective(rpe: rpe));
    }
  }
  return (session, clock);
}

/// Termine als Text, um „unverändert“ zu prüfen.
Future<String> _schedule(StorageSession s) async => [
  for (final u in await (s as PlanStorage).plans.unitsBetween(
    _mon,
    planFarFuture,
  ))
    '${u.day.toIso8601String().substring(0, 10)}/${u.kind.name}/${u.pinned}/'
        '${u.fixed.name}/${u.minutes}',
].join(';');

Future<void> _pump(
  WidgetTester tester,
  StorageSession session,
  Clock clock, {
  String locale = 'de',
  Brightness brightness = Brightness.light,
  PlanController? controller,
  double width = 411,
}) async {
  tester.view.physicalSize = Size(width, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final settings = await AppSettings.load(session.settings, clock);
  final holder = AppSettingsHolder()..attach(settings);
  controller ??= _NoCheck(session, clock);
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    OffloadScope(
      offload: inlineOffload,
      child: AppSettingsScope(
        holder: holder,
        child: localizedApp(
          locale: Locale(locale),
          brightness: brightness,
          home: PlanScreen(
            session: session,
            clock: clock,
            controller: controller,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(key('plan_open_calendar'));
  await tester.pumpAndSettle();
}

/// Einheit am Tag [from] antippen, „Verschieben“, im Datumsfeld Tag [to]
/// (November) wählen und bestätigen: der Bestätigungsdialog ist offen.
Future<void> _startMove(WidgetTester tester, int from, int to) async {
  await tester.tap(
    key('calendar_day_2026-11-${(9 + from).toString().padLeft(2, '0')}'),
  );
  await tester.pumpAndSettle();
  await tester.tap(key('calendar_move'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('${9 + to}'));
  await tester.pumpAndSettle();
  final ok = MaterialLocalizations.of(
    tester.element(find.byType(DatePickerDialog)),
  ).okButtonLabel;
  await tester.tap(find.text(ok));
  await tester.pumpAndSettle();
  expect(key('calendar_move_dialog'), findsOneWidget);
}

void main() {
  group('Kalender (FR-0171 bis FR-0173)', () {
    for (final (locale, brightness) in [
      ('de', Brightness.light),
      ('de', Brightness.dark),
      ('en', Brightness.light),
      ('en', Brightness.dark),
    ]) {
      testWidgets('Woche und Monat mit geplant, erledigt, ausgefallen und '
          'Ruhetag ($locale, ${brightness.name})', (tester) async {
        final (session, clock) = await _seed();
        await _pump(
          tester,
          session,
          clock,
          locale: locale,
          brightness: brightness,
        );
        final de = locale == 'de';
        expect(key('calendar_week'), findsOneWidget);
        Finder inDay(String day, String text) => find.descendant(
          of: key('calendar_day_2026-11-$day'),
          matching: find.textContaining(text),
        );
        expect(inDay('09', de ? 'erledigt' : 'done'), findsOneWidget);
        expect(inDay('10', de ? 'ausgefallen' : 'missed'), findsOneWidget);
        expect(inDay('12', de ? 'geplant' : 'planned'), findsOneWidget);
        expect(inDay('12', de ? 'Intervalle' : 'Interval'), findsOneWidget);
        expect(inDay('11', de ? 'Ruhetag' : 'Rest day'), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.tap(key('calendar_mode_month'));
        await tester.pumpAndSettle();
        expect(key('calendar_month'), findsOneWidget);
        expect(
          find.text(de ? 'November 2026' : 'November 2026'),
          findsOneWidget,
        );
        expect(
          tester.getSemantics(key('calendar_day_2026-11-10')).label,
          contains(de ? 'ausgefallen' : 'missed'),
        );
        expect(
          tester.getSemantics(key('calendar_day_2026-11-09')).label,
          contains(de ? 'erledigt' : 'done'),
        );
        expect(key('calendar_day_2026-11-30'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('vergangene und erledigte Einheiten lassen sich nicht '
        'verschieben', (tester) async {
      final (session, clock) = await _seed();
      await _pump(tester, session, clock);
      for (final day in ['09', '10']) {
        await tester.tap(key('calendar_day_2026-11-$day'));
        await tester.pumpAndSettle();
        expect(key('calendar_frozen'), findsOneWidget);
        expect(key('calendar_move'), findsNothing);
        await tester.tap(key('calendar_details'));
        await tester.pumpAndSettle();
        expect(key('calendar_list'), findsNothing);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(key('calendar_list'), findsOneWidget);
      }
    });
  });

  group('Verschieben (FR-0176 bis FR-0178, PAR-060)', () {
    testWidgets('ohne Bestätigung ändert sich kein Termin (Abbrechen, '
        'Zurück, Datumswahl abgebrochen)', (tester) async {
      final (session, clock) = await _seed();
      final before = await _schedule(session);
      await _pump(tester, session, clock);

      await _startMove(tester, 3, 4);
      await tester.tap(key('calendar_move_cancel'));
      await tester.pumpAndSettle();
      expect(key('calendar_move_dialog'), findsNothing);
      expect(await _schedule(session), before);

      await _startMove(tester, 3, 4);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(key('calendar_move_dialog'), findsNothing);
      expect(key('calendar_list'), findsOneWidget);
      expect(await _schedule(session), before);

      await tester.tap(key('calendar_day_2026-11-12'));
      await tester.pumpAndSettle();
      await tester.tap(key('calendar_move'));
      await tester.pumpAndSettle();
      final cancel = MaterialLocalizations.of(
        tester.element(find.byType(DatePickerDialog)),
      ).cancelButtonLabel;
      await tester.tap(find.text(cancel));
      await tester.pumpAndSettle();
      expect(key('calendar_move_dialog'), findsNothing);
      expect(await _schedule(session), before);
      expect(key('calendar_move_result'), findsNothing);
    });

    testWidgets('Verschieben: Datumsdialog beginnt beim nächsten freien Tag '
        'nach der Einheit, nicht ab heute', (tester) async {
      final (session, clock) = await _seed();
      await _pump(tester, session, clock);
      await tester.tap(key('calendar_day_2026-11-14'));
      await tester.pumpAndSettle();
      await tester.tap(key('calendar_move'));
      await tester.pumpAndSettle();
      final dialog = tester.widget<DatePickerDialog>(
        find.byType(DatePickerDialog),
      );
      // Sa 14.11. ist die Einheit; der Dialog steht danach, nicht am
      // ersten freien Tag ab heute (Fr 13.11.).
      expect(dialog.initialDate!.isAfter(DateTime(2026, 11, 14)), isTrue);
      expect(dialog.selectableDayPredicate!(dialog.initialDate!), isTrue);
      final cancel = MaterialLocalizations.of(
        tester.element(find.byType(DatePickerDialog)),
      ).cancelButtonLabel;
      await tester.tap(find.text(cancel));
      await tester.pumpAndSettle();
    });

    testWidgets('Konflikt: kein voller Tag zur langen Einheit, Alternative '
        'genannt, trotzdem bestätigen verschiebt', (tester) async {
      final (session, clock) = await _seed();
      await _pump(tester, session, clock);
      await _startMove(tester, 3, 4); // Do -> Fr, neben Sa (lang)
      expect(key('calendar_move_conflict_2026-11-14'), findsOneWidget);
      expect(key('calendar_move_alternatives'), findsOneWidget);
      // Frei ab heute: Mi 11. (3 Tage vor Sa) passt, So 15. liegt neben Sa.
      expect(key('calendar_alternative_2026-11-11'), findsOneWidget);
      expect(key('calendar_alternative_2026-11-15'), findsNothing);
      expect(key('calendar_move_regulator'), findsNothing);
      expect(
        find.descendant(
          of: key('calendar_move_confirm'),
          matching: find.text('Trotzdem verschieben'),
        ),
        findsOneWidget,
      );
      await tester.tap(key('calendar_move_confirm'));
      await tester.pumpAndSettle();
      final plans = (session as PlanStorage).plans;
      expect(await plans.unitOn(_d(3)), isNull);
      final moved = (await plans.unitOn(_d(4)))!;
      expect(moved.kind, PlanUnitKind.intervals);
      expect(moved.pinned, isTrue);
      expect(find.text('Termin verschoben.'), findsOneWidget);
    });

    testWidgets('Alternative wählen prüft neu und verschiebt dorthin', (
      tester,
    ) async {
      final (session, clock) = await _seed();
      await _pump(tester, session, clock);
      await _startMove(tester, 3, 4);
      await tester.tap(key('calendar_alternative_2026-11-11'));
      await tester.pumpAndSettle();
      expect(key('calendar_move_conflict_2026-11-14'), findsNothing);
      expect(
        find.descendant(
          of: key('calendar_move_confirm'),
          matching: find.text('Verschieben'),
        ),
        findsOneWidget,
      );
      await tester.tap(key('calendar_move_confirm'));
      await tester.pumpAndSettle();
      final moved = (await (session as PlanStorage).plans.unitOn(_d(2)))!;
      expect(moved.kind, PlanUnitKind.intervals);
      expect(moved.pinned, isTrue);
    });

    testWidgets('Regler überschritten: Hinweis statt Sperre (en)', (
      tester,
    ) async {
      final (session, clock) = await _seed(capMinutes: 180);
      await _pump(tester, session, clock, locale: 'en');
      // Langer Lauf von Sa 21.11. auf So 15.11.: diese Woche 175 + 70 min
      // über 180 min, und Sa 14.11. (lang) liegt daneben.
      await tester.tap(key('calendar_next'));
      await tester.pumpAndSettle();
      await tester.tap(key('calendar_day_2026-11-21'));
      await tester.pumpAndSettle();
      await tester.tap(key('calendar_move'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('15'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(key('calendar_move_regulator'), findsOneWidget);
      expect(key('calendar_move_conflict_2026-11-14'), findsOneWidget);
      expect(find.text('Move anyway'), findsOneWidget);
      await tester.tap(key('calendar_move_confirm'));
      await tester.pumpAndSettle();
      final moved = (await (session as PlanStorage).plans.unitOn(_d(6)))!;
      expect(moved.kind, PlanUnitKind.long);
    });
  });

  testWidgets('Zeitraum und Scrollposition bleiben über Tab-Wechsel, Zurück '
      'führt zur Plan-Seite', (tester) async {
    final d = await started(tester);
    // Niedrig genug, dass der Monat scrollt.
    tester.view.physicalSize = const Size(411, 480);
    await tester.pumpAndSettle();
    final c = PlanController(
      session: d.session,
      clock: d.clock,
      reader: PlanDataReader(
        session: d.session,
        clock: d.clock,
        loadRuns: () async => const [],
      ),
    );
    await tester.runAsync(
      () => c.saveGoal(
        TrainingGoal(
          type: GoalType.distance,
          distance: GoalDistance.tenKilometers,
          targetDate: DateTime.utc(2026, 10, 4),
          runDays: const {2, 4, 6},
          maxSessionSeconds: 7200,
          weeklyCapSeconds: 240 * 60.0,
          createdAt: DateTime.utc(2026, 6, 1),
          canRun30: ContinuousRun30.yes,
          hardSessionEnabled: false,
        ),
      ),
    );
    c.dispose();
    await tester.tap(key('home_plan'));
    await tester.pumpAndSettle();
    await tester.tap(key('plan_open_calendar'));
    await tester.pumpAndSettle();
    await tester.tap(key('calendar_mode_month'));
    await tester.pumpAndSettle();
    await tester.tap(key('calendar_next'));
    await tester.pumpAndSettle();
    final period = tester.widget<Text>(key('calendar_period')).data;
    await tester.drag(key('calendar_list'), const Offset(0, -120));
    await tester.pumpAndSettle();
    double offset() => tester
        .state<ScrollableState>(
          find.descendant(
            of: key('calendar_list'),
            matching: find.byType(Scrollable),
          ),
        )
        .position
        .pixels;
    final before = offset();
    expect(before, greaterThan(0));

    await tester.tap(key('home_history'));
    await tester.pumpAndSettle();
    expect(key('calendar_list'), findsNothing);
    await tester.tap(key('home_plan'));
    await tester.pumpAndSettle();
    expect(key('calendar_month'), findsOneWidget);
    expect(tester.widget<Text>(key('calendar_period')).data, period);
    expect(offset(), before);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(key('calendar_list'), findsNothing);
    expect(key('plan_list'), findsOneWidget);
  });

  group('Nachbesserung E', () {
    testWidgets('Lauf ohne Einheit erscheint als erledigt, der Tag ist kein '
        'Ruhetag (FR-0171, FR-0172)', (tester) async {
      // Heute (Mi 11.11.) frei gelaufen, ohne Einheit.
      final (session, clock) = await _seed(freeRuns: {2: null});
      await _pump(tester, session, clock);
      Finder inDay(String text) => find.descendant(
        of: key('calendar_day_2026-11-11'),
        matching: find.textContaining(text),
      );
      expect(inDay('Lauf ohne Plan'), findsOneWidget);
      expect(inDay('erledigt'), findsOneWidget);
      expect(inDay('Ruhetag'), findsNothing);
      // Sonntag ohne Lauf bleibt Ruhetag.
      expect(
        find.descendant(
          of: key('calendar_day_2026-11-15'),
          matching: find.textContaining('Ruhetag'),
        ),
        findsOneWidget,
      );
      await tester.tap(key('calendar_mode_month'));
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(key('calendar_day_2026-11-11')).label,
        allOf(contains('Lauf ohne Plan'), isNot(contains('Ruhetag'))),
      );
    });

    testWidgets('Lauf ohne Einheit an einem Tag mit gespeicherter Ruhe-'
        'Einheit: Lauf ohne Plan, nie Ruhetag', (tester) async {
      // Heute (Mi 11.11.) ist als Ruhetag gespeichert und frei gelaufen.
      final (session, clock) = await _seed(
        extra: [
          PlanUnit(
            day: _d(2),
            kind: PlanUnitKind.rest,
            phase: PlanPhase.build,
            weekIndex: 0,
            minutes: 0,
            segments: const [],
          ),
        ],
        freeRuns: {2: null},
      );
      expect(
        (await (session as PlanStorage).plans.unitOn(_d(2)))!.kind,
        PlanUnitKind.rest,
      );
      await _pump(tester, session, clock);
      Finder inDay(String text) => find.descendant(
        of: key('calendar_day_2026-11-11'),
        matching: find.textContaining(text),
      );
      expect(inDay('Lauf ohne Plan'), findsOneWidget);
      expect(inDay('Ruhetag'), findsNothing);
    });

    testWidgets('Lauf ohne Einheit neben einer offenen Einheit: eigene Zeile', (
      tester,
    ) async {
      // Di 10.11.: Einheit ausgefallen, aber frei gelaufen.
      final (session, clock) = await _seed(freeRuns: {1: null});
      await _pump(tester, session, clock);
      expect(key('calendar_free_run_2026-11-10'), findsOneWidget);
      // Der Lauf am Mo 9.11. ist der Einheit zugeordnet: keine eigene Zeile.
      expect(key('calendar_free_run_2026-11-09'), findsNothing);
    });

    testWidgets('Wochengrenze: intensive Einheit auf einen Montag neben einer '
        'intensiven am Sonntag davor ist ein Konflikt (PAR-059)', (
      tester,
    ) async {
      final (session, clock) = await _seed(
        extra: [_u(6, PlanUnitKind.tempo, 40)],
      );
      await _pump(tester, session, clock);
      await tester.tap(key('calendar_next'));
      await tester.pumpAndSettle();
      // Intervalle Do 19.11. auf Mo 16.11., Tempo am So 15.11.
      await _startMove(tester, 10, 7);
      expect(key('calendar_move_conflict_2026-11-15'), findsOneWidget);
    });

    testWidgets('absolvierter harter Lauf ohne Einheit zählt für den Abstand '
        '(PAR-058: RPE ab 7)', (tester) async {
      // Di 10.11. frei gelaufen mit RPE 8; Intervalle Do 12.11. auf Mi 11.11.
      final (session, clock) = await _seed(freeRuns: {1: 8});
      await _pump(tester, session, clock);
      await _startMove(tester, 3, 2);
      expect(key('calendar_move_conflict_2026-11-10'), findsOneWidget);
    });

    testWidgets('lockerer Lauf ohne Einheit (RPE 4) ist kein Konflikt', (
      tester,
    ) async {
      final (session, clock) = await _seed(freeRuns: {1: 4});
      await _pump(tester, session, clock);
      await _startMove(tester, 3, 2);
      expect(key('calendar_move_conflict_2026-11-10'), findsNothing);
    });

    testWidgets('nach Tipp auf eine Alternative ist Bestätigen gesperrt, bis '
        'die neue Prüfung fertig ist', (tester) async {
      final (session, clock) = await _seed();
      final controller = _Gated(session, clock);
      await _pump(tester, session, clock, controller: controller);
      await _startMove(tester, 3, 4);
      controller.gate = Completer<void>();
      await tester.tap(key('calendar_alternative_2026-11-11'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      FilledButton confirm() =>
          tester.widget<FilledButton>(key('calendar_move_confirm'));
      expect(confirm().onPressed, isNull);
      controller.gate!.complete();
      controller.gate = null;
      await tester.pumpAndSettle();
      expect(confirm().onPressed, isNotNull);
    });

    testWidgets('Speicherfehler beim Verschieben: Hinweis, kein Termin '
        'geändert', (tester) async {
      final (session, clock) = await _seed();
      final controller = _Gated(session, clock);
      await _pump(tester, session, clock, controller: controller);
      final before = await _schedule(session);
      await tester.tap(key('calendar_day_2026-11-12'));
      await tester.pumpAndSettle();
      controller.fail = true;
      await tester.tap(key('calendar_move'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(DatePickerDialog), findsNothing);
      expect(key('calendar_move_result'), findsOneWidget);
      controller.fail = false;
      expect(await _schedule(session), before);
    });

    for (final locale in ['de', 'en']) {
      testWidgets('Wochenkalender: Datum bricht bei Schrift 1.0 nicht um, '
          'Zeilen gleich hoch ($locale)', (tester) async {
        final (session, clock) = await _seed();
        await _pump(tester, session, clock, locale: locale, width: 600);
        final heights = <double>{};
        for (var i = 0; i < 7; i++) {
          final label = DateFormat.MEd(locale)
              .format(DateTime(2026, 11, 9 + i));
          final f = find.descendant(
            of: key(
              'calendar_day_2026-11-${(9 + i).toString().padLeft(2, '0')}',
            ),
            matching: find.text(label),
          );
          expect(f, findsOneWidget, reason: label);
          expect(
            tester
                .renderObject<RenderParagraph>(f)
                .getBoxesForSelection(
                  TextSelection(baseOffset: 0, extentOffset: label.length),
                ),
            hasLength(1),
            reason: label,
          );
          heights.add(tester.getSize(f).height);
        }
        expect(heights, hasLength(1));
      });
    }
    testWidgets('Monatsraster unter 360 dp: Tage mindestens 48 dp breit', (
      tester,
    ) async {
      final (session, clock) = await _seed();
      await _pump(tester, session, clock, width: 320);
      await tester.tap(key('calendar_mode_month'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(key('calendar_day_2026-11-12')).width,
        greaterThanOrEqualTo(48),
      );
    });
  });

  group('Ersetzen und Ruhetag (FR-0173, Festlegungen WP22)', () {
    testWidgets('harte Einheit locker ersetzt (fixed = easyForHard): '
        'Markierung „Art ersetzt“ wie bei kind', (tester) async {
      final (session, clock) = await _seed();
      final plans = (session as PlanStorage).plans;
      final hard = (await plans.unitOn(_d(10)))!;
      expect(hard.isHard, isTrue);
      await plans.replaceUnit(
        hard.id!,
        PlanUnit(
          day: hard.day,
          kind: PlanUnitKind.easy,
          phase: hard.phase,
          weekIndex: hard.weekIndex,
          minutes: 45,
          segments: const [
            PlanSegment(kind: PlanSegmentKind.easy, minutes: 45),
          ],
        ),
        today: _d(2),
      );
      expect((await plans.unitOn(_d(10)))!.fixed, PlanUnitFixed.easyForHard);
      await _pump(tester, session, clock);
      await tester.tap(key('calendar_next'));
      await tester.pumpAndSettle();
      expect(key('calendar_replaced_${_k(10)}'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    // Festlegung WP22 (Review E2a Runde 3, Befund 4).
    for (final (locale, text) in [
      ('de', 'Diese Einheit ersetzt die harte Einheit ihrer Woche.'),
      ('en', 'This run replaces the hard session of its week.'),
    ]) {
      testWidgets('hart -> locker verschieben: in der eigenen Woche ohne, in '
          'eine andere Woche mit Hinweis, danach fixed = kind ($locale)', (
        tester,
      ) async {
        final (session, clock) = await _seed();
        final plans = (session as PlanStorage).plans;
        final hard = (await plans.unitOn(_d(3)))!; // Do 12., Intervalle
        await plans.replaceUnit(
          hard.id!,
          PlanUnit(
            day: hard.day,
            kind: PlanUnitKind.easy,
            phase: hard.phase,
            weekIndex: hard.weekIndex,
            minutes: 45,
            segments: const [
              PlanSegment(kind: PlanSegmentKind.easy, minutes: 45),
            ],
          ),
          today: _d(2),
        );
        expect((await plans.unitOn(_d(3)))!.fixed, PlanUnitFixed.easyForHard);
        await _pump(tester, session, clock, locale: locale);

        await _startMove(tester, 3, 4); // Fr 13., gleiche Woche
        expect(key('calendar_move_ends_hard_replacement'), findsNothing);
        await tester.tap(key('calendar_move_cancel'));
        await tester.pumpAndSettle();

        // Mi 18., andere Woche: im Datumsdialog frei, bis zur Prüfung aber
        // belegt (Di 17. dorthin verschoben). Gesperrt, kein Hinweis.
        await tester.tap(key('calendar_day_2026-11-12'));
        await tester.pumpAndSettle();
        await tester.tap(key('calendar_move'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('18'));
        await tester.pumpAndSettle();
        await plans.confirmMove(
          (await plans.unitOn(_d(8)))!.id!,
          _d(9),
          today: _d(2),
        );
        await tester.tap(
          find.text(
            MaterialLocalizations.of(
              tester.element(find.byType(DatePickerDialog)),
            ).okButtonLabel,
          ),
        );
        await tester.pumpAndSettle();
        expect(key('calendar_move_dialog'), findsOneWidget);
        expect(key('calendar_move_taken'), findsOneWidget);
        expect(key('calendar_move_ends_hard_replacement'), findsNothing);
        await tester.tap(key('calendar_move_cancel'));
        await tester.pumpAndSettle();

        await _startMove(tester, 3, 7); // Mo 16., nächste Woche
        expect(key('calendar_move_ends_hard_replacement'), findsOneWidget);
        expect(find.textContaining(text), findsOneWidget);
        await tester.tap(key('calendar_move_confirm'));
        await tester.pumpAndSettle();
        expect(await plans.unitOn(_d(3)), isNull);
        final moved = (await plans.unitOn(_d(7)))!;
        expect(moved.id, hard.id);
        expect(moved.kind, PlanUnitKind.easy);
        expect(moved.fixed, PlanUnitFixed.kind);
        expect(moved.weekIndex, 1);
        // Die harte Einheit der Zielwoche bleibt.
        expect((await plans.unitOn(_d(10)))!.kind, PlanUnitKind.intervals);
        expect(tester.takeException(), isNull);
      });
    }

    for (final (locale, brightness) in [
      ('de', Brightness.light),
      ('en', Brightness.dark),
    ]) {
      testWidgets('Ersetzen: Art wählen, Hinweis, bestätigen ersetzt mit '
          'heute und markiert Woche und Monat ($locale, ${brightness.name})', (
        tester,
      ) async {
        final (session, clock) = await _seed();
        final spy = _Spy(session, clock);
        await _pump(
          tester,
          session,
          clock,
          locale: locale,
          brightness: brightness,
          controller: spy,
        );
        final de = locale == 'de';
        final plans = (session as PlanStorage).plans;
        final easy = (await plans.unitOn(_d(8)))!;
        // Folgewoche: Di 17.11. locker durch Tempo, Do 19.11. Intervalle.
        await tester.tap(key('calendar_next'));
        await tester.pumpAndSettle();
        await _sheet(tester, 8, 'calendar_replace');
        expect(key('calendar_replace_dialog'), findsOneWidget);
        expect(key('calendar_replace_kind_easy'), findsNothing);
        // Lockere Art: keine zweite harte Einheit, kein Hinweis.
        await tester.tap(key('calendar_replace_kind_long'));
        await tester.pumpAndSettle();
        expect(key('calendar_replace_new'), findsOneWidget);
        expect(key('calendar_replace_other_hard_easy'), findsNothing);
        await tester.tap(key('calendar_replace_kind_tempo'));
        await tester.pumpAndSettle();
        expect(key('calendar_replace_new'), findsOneWidget);
        expect(key('calendar_replace_second_hard_2026-11-19'), findsOneWidget);
        // Die andere harte Einheit wird zum lockeren Lauf (Festlegung WP22).
        expect(
          tester.widget<Text>(key('calendar_replace_other_hard_easy')).data,
          de
              ? 'Die andere harte Einheit dieser Woche wird zum lockeren Lauf.'
              : 'The other hard session this week becomes an easy run.',
        );
        expect(
          find.descendant(
            of: key('calendar_replace_confirm'),
            matching: find.text(de ? 'Trotzdem ersetzen' : 'Replace anyway'),
          ),
          findsOneWidget,
        );
        expect(spy.calls, isEmpty);
        await tester.tap(key('calendar_replace_confirm'));
        await tester.pumpAndSettle();
        expect(spy.calls, ['replace ${easy.id} tempo']);
        final replaced = (await plans.unitOn(_d(8)))!;
        expect(replaced.kind, PlanUnitKind.tempo);
        expect(replaced.fixed, PlanUnitFixed.kind);
        expect(
          find.text(de ? 'Einheit ersetzt.' : 'Session replaced.'),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: key('calendar_replaced_${_k(8)}'),
            matching: find.text(
              de ? 'Art von dir ersetzt' : 'Type replaced by you',
            ),
          ),
          findsOneWidget,
        );
        expect(key('calendar_replaced_${_k(10)}'), findsNothing);

        await tester.tap(key('calendar_mode_month'));
        await tester.pumpAndSettle();
        expect(key('calendar_replaced_${_k(8)}'), findsOneWidget);
        expect(
          tester.getSemantics(key('calendar_day_${_k(8)}')).label,
          contains(de ? 'Art von dir ersetzt' : 'Type replaced by you'),
        );
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('ohne Bestätigung ändert sich nichts (Abbrechen, Zurück), '
        'vergangene Tage ohne Aktionen', (tester) async {
      final (session, clock) = await _seed();
      final spy = _Spy(session, clock);
      final before = await _schedule(session);
      await _pump(tester, session, clock, controller: spy);

      await _sheet(tester, 3, 'calendar_replace');
      await tester.tap(key('calendar_replace_kind_tempo'));
      await tester.pumpAndSettle();
      await tester.tap(key('calendar_replace_cancel'));
      await tester.pumpAndSettle();
      expect(key('calendar_replace_dialog'), findsNothing);

      await _sheet(tester, 3, 'calendar_replace');
      await tester.tap(key('calendar_replace_kind_long'));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(key('calendar_replace_dialog'), findsNothing);
      expect(key('calendar_list'), findsOneWidget);

      await _sheet(tester, 3, 'calendar_rest_set');
      await tester.tap(key('calendar_rest_cancel'));
      await tester.pumpAndSettle();
      await _sheet(tester, 6, 'calendar_rest_set');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(key('calendar_rest_dialog'), findsNothing);
      expect(key('calendar_list'), findsOneWidget);
      expect(spy.calls, isEmpty);
      expect(await _schedule(session), before);
      expect(key('calendar_change_result'), findsNothing);

      // Vergangen bzw. erledigt: weder Ersetzen noch Ruhetag.
      for (final day in [0, 1]) {
        await tester.tap(key('calendar_day_${_k(day)}'));
        await tester.pumpAndSettle();
        expect(key('calendar_frozen'), findsOneWidget);
        expect(key('calendar_replace'), findsNothing);
        expect(key('calendar_rest_set'), findsNothing);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
      }
    });

    testWidgets('Ruhetag auf einer Einheit: Alternativtag derselben Woche, '
        'bestätigen verlegt die Einheit', (tester) async {
      final (session, clock) = await _seed();
      final spy = _Spy(session, clock);
      await _pump(tester, session, clock, controller: spy);
      // Do 12.11. Intervalle: Mi 11.11. passt; Fr 13. und So 15. liegen
      // neben dem langen Lauf am Sa 14.11.
      await _sheet(tester, 3, 'calendar_rest_set');
      expect(key('calendar_rest_unit_moves'), findsOneWidget);
      expect(key('calendar_rest_alternative_${_k(2)}'), findsOneWidget);
      expect(key('calendar_rest_alternative_${_k(4)}'), findsNothing);
      expect(key('calendar_rest_alternative_${_k(6)}'), findsNothing);
      expect(spy.calls, isEmpty);
      await tester.tap(key('calendar_rest_alternative_${_k(2)}'));
      await tester.pumpAndSettle();
      await tester.tap(key('calendar_rest_confirm'));
      await tester.pumpAndSettle();
      expect(spy.calls, ['rest ${_iso(_d(3))} ${_iso(_d(2))}']);
      final plans = (session as PlanStorage).plans;
      expect(spy.seenUnitIds, [(await plans.unitOn(_d(2)))!.id]);
      final rest = (await plans.unitOn(_d(3)))!;
      expect(rest.isRestDay, isTrue);
      expect(rest.fixed, PlanUnitFixed.day);
      final moved = (await plans.unitOn(_d(2)))!;
      expect(moved.kind, PlanUnitKind.intervals);
      expect(moved.pinned, isTrue);
      expect(find.text('Ruhetag festgelegt.'), findsOneWidget);
      expect(key('calendar_rest_fixed_${_k(3)}'), findsOneWidget);
    });

    testWidgets('Ruhetag ohne passenden Tag: die Einheit entfällt erst nach '
        'Bestätigung', (tester) async {
      // Höchste Wochenzeit 60 min: jeder andere Tag läge über dem Regler.
      final (session, clock) = await _seed(capMinutes: 60);
      final spy = _Spy(session, clock);
      await _pump(tester, session, clock, controller: spy);
      await _sheet(tester, 3, 'calendar_rest_set');
      expect(key('calendar_rest_unit_drops'), findsOneWidget);
      expect(find.byType(ChoiceChip), findsNothing);
      final plans = (session as PlanStorage).plans;
      final unit = (await plans.unitOn(_d(3)))!;
      expect(unit.kind, PlanUnitKind.intervals);
      await tester.tap(key('calendar_rest_confirm'));
      await tester.pumpAndSettle();
      expect(spy.calls, ['rest ${_iso(_d(3))} -']);
      expect(spy.seenUnitIds, [unit.id]);
      expect((await plans.unitOn(_d(3)))!.isRestDay, isTrue);
      final week = await plans.unitsBetween(_d(0), _d(6));
      expect(week.where((u) => u.kind == PlanUnitKind.intervals), isEmpty);
    });

    for (final (locale, brightness) in [
      ('de', Brightness.light),
      ('en', Brightness.dark),
    ]) {
      testWidgets('freier Tag wird Ruhetag, markiert, aufheben nur nach '
          'Bestätigung ($locale, ${brightness.name})', (tester) async {
        final (session, clock) = await _seed();
        final spy = _Spy(session, clock);
        await _pump(
          tester,
          session,
          clock,
          locale: locale,
          brightness: brightness,
          controller: spy,
        );
        final de = locale == 'de';
        final plans = (session as PlanStorage).plans;
        // So 15.11. ist frei.
        await _sheet(tester, 6, 'calendar_rest_set');
        expect(key('calendar_rest_unit_moves'), findsNothing);
        expect(key('calendar_rest_unit_drops'), findsNothing);
        await tester.tap(key('calendar_rest_confirm'));
        await tester.pumpAndSettle();
        expect(spy.calls, ['rest ${_iso(_d(6))} -']);
        expect(spy.seenUnitIds, [null]);
        expect((await plans.unitOn(_d(6)))!.isRestDay, isTrue);
        final mark = find.descendant(
          of: key('calendar_rest_fixed_${_k(6)}'),
          matching: find.text(de ? 'von dir festgelegt' : 'set by you'),
        );
        expect(mark, findsOneWidget);
        expect(
          tester.widget<Text>(mark).style?.color,
          RamuriColors.of(tester.element(mark)).textMuted,
        );
        expect(key('calendar_rest_fixed_${_k(2)}'), findsNothing);

        await tester.tap(key('calendar_mode_month'));
        await tester.pumpAndSettle();
        final icon = key('calendar_rest_fixed_${_k(6)}');
        expect(icon, findsOneWidget);
        expect(
          tester.widget<Icon>(icon).color,
          RamuriColors.of(tester.element(icon)).textMuted,
        );
        expect(
          tester.getSemantics(key('calendar_day_${_k(6)}')).label,
          contains(de ? 'von dir festgelegt' : 'set by you'),
        );

        // Aufheben: Abbrechen ändert nichts, Bestätigen hebt auf.
        await _sheet(tester, 6, 'calendar_rest_clear');
        expect(key('calendar_rest_clear_dialog'), findsOneWidget);
        await tester.tap(key('calendar_rest_clear_cancel'));
        await tester.pumpAndSettle();
        expect((await plans.unitOn(_d(6)))!.isRestDay, isTrue);
        expect(spy.calls, hasLength(1));
        await _sheet(tester, 6, 'calendar_rest_clear');
        await tester.tap(key('calendar_rest_clear_confirm'));
        await tester.pumpAndSettle();
        expect(spy.calls.last, 'clear ${_iso(_d(6))}');
        expect(await plans.unitOn(_d(6)), isNull);
        expect(
          find.text(de ? 'Ruhetag aufgehoben.' : 'Rest day removed.'),
          findsOneWidget,
        );
        expect(key('calendar_rest_fixed_${_k(6)}'), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }

    for (final aLast in [true, false]) {
      testWidgets('Artwechsel während der Prüfung: Bestätigen liefert die '
          'zuletzt gewählte Art (${aLast ? 'erste' : 'zweite'} Prüfung '
          'endet zuletzt, R1)', (tester) async {
        final (session, clock) = await _seed();
        final spy = _Spy(session, clock);
        final long = spy.replaceGates[PlanUnitKind.long] = Completer<void>();
        final tempo = spy.replaceGates[PlanUnitKind.tempo] = Completer<void>();
        await _pump(tester, session, clock, controller: spy);
        final unit = (await (session as PlanStorage).plans.unitOn(_d(3)))!;
        await _sheet(tester, 3, 'calendar_replace');
        await tester.tap(key('calendar_replace_kind_long'));
        await tester.pump();
        await tester.tap(key('calendar_replace_kind_tempo'));
        await tester.pump();
        final order = aLast ? [tempo, long] : [long, tempo];
        order.first.complete();
        await tester.pump();
        await tester.pump();
        order.last.complete();
        await tester.pumpAndSettle();
        expect(
          tester.widget<Text>(key('calendar_replace_new')).data,
          contains('Tempodauerlauf'),
        );
        await tester.tap(key('calendar_replace_confirm'));
        await tester.pumpAndSettle();
        expect(spy.calls, ['replace ${unit.id} tempo']);
      });
    }

    testWidgets('gesperrte Prüfung: Bestätigen bleibt aus, nichts ändert '
        'sich (Ersetzen R2, Ruhetag R3)', (tester) async {
      final (session, clock) = await _seed();
      final spy = _Spy(session, clock)
        ..replaceResult = ((k) => PlanReplaceCheck(
          kind: k,
          blocked: PlanReplaceBlock.exceedsMaxSession,
        ))
        ..restResult = ((d) =>
            PlanRestDayCheck(day: d, blocked: PlanRestDayBlock.unitHasRun));
      final before = await _schedule(session);
      await _pump(tester, session, clock, controller: spy);

      await _sheet(tester, 3, 'calendar_replace');
      await tester.tap(key('calendar_replace_kind_tempo'));
      await tester.pumpAndSettle();
      expect(key('calendar_replace_blocked'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(key('calendar_replace_confirm')).onPressed,
        isNull,
      );
      await tester.tap(key('calendar_replace_confirm'));
      await tester.pumpAndSettle();
      expect(key('calendar_replace_dialog'), findsOneWidget);
      await tester.tap(key('calendar_replace_cancel'));
      await tester.pumpAndSettle();

      await _sheet(tester, 6, 'calendar_rest_set');
      expect(key('calendar_rest_blocked'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(key('calendar_rest_confirm')).onPressed,
        isNull,
      );
      await tester.tap(key('calendar_rest_confirm'));
      await tester.pumpAndSettle();
      expect(key('calendar_rest_dialog'), findsOneWidget);
      expect(spy.calls, isEmpty);
      expect(await _schedule(session), before);
    });

    testWidgets('vergangener Ruhetag des Nutzers: kein Blatt, kein Aufheben '
        '(R4)', (tester) async {
      final (session, clock) = await _seed(
        extra: [
          PlanUnit(
            day: _d(2),
            kind: PlanUnitKind.rest,
            phase: PlanPhase.build,
            weekIndex: 0,
            minutes: 0,
            segments: const [],
            pinned: true,
            fixed: PlanUnitFixed.day,
          ),
        ],
      );
      // Heute ist Freitag, 13.11.: der Ruhetag am Mi 11.11. ist vergangen.
      clock.set(DateTime.utc(2026, 11, 13, 12));
      final spy = _Spy(session, clock);
      await _pump(tester, session, clock, controller: spy);
      expect(key('calendar_rest_fixed_${_k(2)}'), findsOneWidget);
      await tester.tap(key('calendar_day_${_k(2)}'));
      await tester.pumpAndSettle();
      expect(key('calendar_actions'), findsNothing);
      expect(key('calendar_rest_clear'), findsNothing);
      // Gegenprobe: ein künftiger freier Tag hat das Blatt.
      await tester.tap(key('calendar_day_${_k(6)}'));
      await tester.pumpAndSettle();
      expect(key('calendar_rest_set'), findsOneWidget);
      expect(spy.calls, isEmpty);
    });

    testWidgets('freier Tag nach dem Plan: keine Aktion (R5)', (tester) async {
      final (session, clock) = await _seed();
      final spy = _Spy(session, clock);
      await _pump(tester, session, clock, controller: spy);
      await tester.tap(key('calendar_mode_month'));
      await tester.pumpAndSettle();
      // Zieldatum So 14.03.2027: die letzte Planwoche endet an dem Tag.
      for (var i = 0; i < 4; i++) {
        await tester.tap(key('calendar_next'));
        await tester.pumpAndSettle();
      }
      await tester.tap(key('calendar_day_2027-03-20'));
      await tester.pumpAndSettle();
      expect(key('calendar_actions'), findsNothing);
      expect(key('calendar_rest_set'), findsNothing);
      // Gegenprobe: ein freier Tag in der letzten Planwoche.
      await tester.tap(key('calendar_day_2027-03-10'));
      await tester.pumpAndSettle();
      expect(key('calendar_rest_set'), findsOneWidget);
      expect(spy.calls, isEmpty);
    });

    testWidgets('Ruhe-Einheit mit Lauf: kein „Ruhetag festlegen“ '
        '(Befund 3)', (tester) async {
      final (session, clock) = await _seed(
        extra: [
          PlanUnit(
            day: _d(2),
            kind: PlanUnitKind.rest,
            phase: PlanPhase.build,
            weekIndex: 0,
            minutes: 0,
            segments: const [],
          ),
        ],
      );
      final plans = (session as PlanStorage).plans;
      final run = await session.runs.create(
        startedAt: _d(2).add(const Duration(hours: 7)),
      );
      await session.runs.setState(
        run.id,
        RunState.finished,
        endedAt: _d(2).add(const Duration(hours: 8)),
        endedUtcOffset: Duration.zero,
      );
      await plans.assignRun((await plans.unitOn(_d(2)))!.id!, run.id);
      final spy = _Spy(session, clock);
      await _pump(tester, session, clock, controller: spy);
      await tester.tap(key('calendar_day_${_k(2)}'));
      await tester.pumpAndSettle();
      expect(key('calendar_actions'), findsOneWidget);
      expect(key('calendar_frozen'), findsOneWidget);
      expect(key('calendar_rest_set'), findsNothing);
      expect(key('calendar_rest_clear'), findsNothing);
      expect(spy.calls, isEmpty);
    });

    testWidgets('nicht festgelegte Ruhe-Einheit lässt sich festlegen und '
        'wieder aufheben (Festlegung WP22, OQ-0011)', (tester) async {
      final (session, clock) = await _seed(
        extra: [
          PlanUnit(
            day: _d(6),
            kind: PlanUnitKind.rest,
            phase: PlanPhase.build,
            weekIndex: 0,
            minutes: 0,
            segments: const [],
          ),
        ],
      );
      final plans = (session as PlanStorage).plans;
      final gen = (await plans.unitOn(_d(6)))!;
      expect(gen.isRestDay, isFalse);
      final spy = _Spy(session, clock);
      await _pump(tester, session, clock, controller: spy);
      expect(key('calendar_rest_fixed_${_k(6)}'), findsNothing);
      await _sheet(tester, 6, 'calendar_rest_set');
      expect(key('calendar_rest_unit_moves'), findsNothing);
      expect(key('calendar_rest_unit_drops'), findsNothing);
      expect(key('calendar_rest_blocked'), findsNothing);
      await tester.tap(key('calendar_rest_confirm'));
      await tester.pumpAndSettle();
      expect(spy.calls, ['rest ${_iso(_d(6))} -']);
      expect(spy.seenUnitIds, [gen.id]);
      final rest = (await plans.unitOn(_d(6)))!;
      expect(rest.isRestDay, isTrue);
      expect(rest.fixed, PlanUnitFixed.day);
      expect(find.text('Ruhetag festgelegt.'), findsOneWidget);
      expect(key('calendar_rest_fixed_${_k(6)}'), findsOneWidget);
      await _sheet(tester, 6, 'calendar_rest_clear');
      await tester.tap(key('calendar_rest_clear_confirm'));
      await tester.pumpAndSettle();
      expect(spy.calls.last, 'clear ${_iso(_d(6))}');
      expect(await plans.unitOn(_d(6)), isNull);
    });

    testWidgets('Fehler sind sichtbar und ändern nichts', (tester) async {
      final (session, clock) = await _seed();
      final spy = _Spy(session, clock)..failCheck = true;
      final before = await _schedule(session);
      await _pump(tester, session, clock, controller: spy);

      await _sheet(tester, 3, 'calendar_replace');
      await tester.tap(key('calendar_replace_kind_tempo'));
      await tester.pumpAndSettle();
      expect(key('calendar_check_failed'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(key('calendar_replace_confirm')).onPressed,
        isNull,
      );
      await tester.tap(key('calendar_replace_cancel'));
      await tester.pumpAndSettle();

      spy
        ..failCheck = false
        ..fail = true;
      await _sheet(tester, 3, 'calendar_replace');
      await tester.tap(key('calendar_replace_kind_tempo'));
      await tester.pumpAndSettle();
      await tester.tap(key('calendar_replace_confirm'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Die Einheit ließ sich nicht ersetzen. Der Plan ist unverändert.',
        ),
        findsOneWidget,
      );
      await _sheet(tester, 6, 'calendar_rest_set');
      await tester.tap(key('calendar_rest_confirm'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Der Ruhetag ließ sich nicht festlegen. Der Plan ist unverändert.',
        ),
        findsOneWidget,
      );
      expect(await _schedule(session), before);
    });
  });
}
