import 'dart:async';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/plan/plan_controller.dart';
import 'package:running_app/features/plan/plan_data_reader.dart';
import 'package:running_app/features/plan/plan_screen.dart';
import 'package:running_app/features/settings/app_settings.dart';
import 'package:running_app/l10n/app_localizations.dart';
import 'package:running_app/offload_scope.dart';
import 'package:running_app/ui/ui.dart';

import 'history_summary_test.dart' show key, started;

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
    '${u.day.toIso8601String().substring(0, 10)}/${u.kind.name}/${u.pinned}',
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
        child: MaterialApp(
          theme: brightness == Brightness.light
              ? RamuriTheme.light
              : RamuriTheme.dark,
          locale: Locale(locale),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
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
}
