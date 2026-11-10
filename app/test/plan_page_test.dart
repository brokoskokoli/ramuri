import 'dart:convert';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/plan/plan_controller.dart';
import 'package:running_app/features/plan/plan_data_reader.dart';
import 'package:running_app/features/plan/plan_screen.dart';
import 'package:running_app/features/plan/plan_texts.dart';
import 'package:running_app/features/settings/app_settings.dart';
import 'package:running_app/l10n/app_localizations.dart';
import 'package:running_app/offload_scope.dart';
import 'package:running_app/ui/ui.dart';

import 'history_summary_test.dart' show key, started;

final Uint8List _key = Uint8List.fromList(List.generate(32, (i) => i));

/// Mittwoch, 11.11.2026, mittags.
final _now = DateTime.utc(2026, 11, 11, 12);
final _today = DateTime.utc(2026, 11, 11);
final _monday = DateTime.utc(2026, 11, 9);

TrainingGoal _goal({
  GoalType type = GoalType.distance,
  DateTime? target,
  Set<int> days = const {2, 4, 6},
  DateTime? createdAt,
  ContinuousRun30 canRun30 = ContinuousRun30.yes,
}) => TrainingGoal(
  type: type,
  distance: type == GoalType.open ? null : GoalDistance.tenKilometers,
  targetSeconds: type == GoalType.time ? 55 * 60.0 : null,
  targetDate: type == GoalType.open
      ? null
      : (target ?? DateTime.utc(2027, 3, 14)),
  runDays: days,
  maxSessionSeconds: 7200,
  weeklyCapSeconds: 240 * 60.0,
  createdAt: createdAt ?? DateTime.utc(2026, 11, 1),
  hardSessionEnabled: type == GoalType.time,
  canRun30: canRun30,
);

/// Controller mit festem Stand (für Hinweise, die ein echter Plan selten
/// zugleich hat).
class _Fixed extends PlanController {
  _Fixed(StorageSession session, Clock clock, this.fixed)
    : super(session: session, clock: clock);
  final PlanViewState fixed;
  @override
  PlanViewState get state => fixed;
  @override
  Future<void> open() async {}
  @override
  Future<List<PlanUnit>> unitsBetween(DateTime from, DateTime to) async =>
      const [];
}

Future<void> _pump(
  WidgetTester tester, {
  required StorageSession session,
  required Clock clock,
  PlanController? controller,
  String locale = 'de',
  Brightness brightness = Brightness.light,
  VoidCallback? onCreateGoal,
}) async {
  tester.view.physicalSize = const Size(411, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final settings = await AppSettings.load(session.settings, clock);
  final holder = AppSettingsHolder()..attach(settings);
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
            onCreateGoal: onCreateGoal,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Speicher mit Ziel und erster Fassung (über den echten Controller).
Future<(StorageSession, FakeClock)> _withPlan(TrainingGoal goal) async {
  final session = await FakeStorage().open(_key);
  final clock = FakeClock(_now);
  final c = PlanController(
    session: session,
    clock: clock,
    reader: PlanDataReader(
      session: session,
      clock: clock,
      loadRuns: () async => const [],
    ),
  );
  expect(await c.saveGoal(goal), PlanActionResult.done);
  c.dispose();
  return (session, clock);
}

PlanViewState _hintState({required bool ruleVersionOld}) => _state(
  ruleVersionOld: ruleVersionOld,
  unplacedByWeek: const {0: 15},
  hardOmissions: const {0: HardOmission.noRecoveryDay},
  droppedDaysByWeek: {
    0: [_monday.add(const Duration(days: 4))],
  },
  pinnedConflicts: [
    PinnedConflict(
      kind: PinnedConflictKind.spacing,
      day: _today,
      otherDay: _today.add(const Duration(days: 1)),
    ),
  ],
  walkRunStaysAtWeek: 3,
  hardFit: HardFitStatus.partialAtPeak,
);

/// Fester Stand mit 6 Planwochen (2 Einstieg, 3 Aufbau, 1 Reduktion), die
/// [firstWeekOffset] Wochen vor (negativ) oder nach dieser Woche beginnen.
PlanViewState _state({
  bool ruleVersionOld = false,
  GoalType type = GoalType.time,
  int firstWeekOffset = 0,
  Map<int, int> unplacedByWeek = const {},
  Map<int, HardOmission> hardOmissions = const {},
  Map<int, List<DateTime>> droppedDaysByWeek = const {},
  List<PinnedConflict> pinnedConflicts = const [],
  int? walkRunStaysAtWeek,
  bool walkRunNoWeekFits = false,
  HardFitStatus hardFit = HardFitStatus.notApplicable,
  GoalAssessment? assessment,
  List<PlanUnit> weekUnits = const [],
  double? easyPaceSecondsPerKm,
  int easyRunCount = 0,
  int anchorWeeksEarlier = 0,
  List<int>? weekMinutes,
}) {
  final goal = _goal(type: type);
  final base = PlanInputs.forNewGoal(goal, _today);
  final first = _monday.add(Duration(days: 7 * firstWeekOffset));
  // Wie die Rechnung: die Wochen beginnen mit [first], der Anker liegt
  // [anchorWeeksEarlier] Wochen davor (Nummern ab dem Anker).
  final inputs = PlanInputs(
    anchor: first.subtract(Duration(days: 7 * anchorWeeksEarlier)),
    startWeeklyMinutes: base.startWeeklyMinutes,
    today: _today,
    easyPaceSecondsPerKm: easyPaceSecondsPerKm,
    easyRunCount: easyRunCount,
  );
  final weeks = [
    for (var i = 0; i < 6; i++)
      PlanWeek(
        index: i + anchorWeeksEarlier,
        start: first.add(Duration(days: 7 * i)),
        minutes: weekMinutes?[i] ?? 120,
        phase: i < 2
            ? PlanPhase.entry
            : (i < 5 ? PlanPhase.build : PlanPhase.reduction),
        kind: WeekKind.climbing,
      ),
  ];
  final version = PlanVersionRecord(
    id: 1,
    goalId: 1,
    createdAt: _now,
    validFrom: _today,
    trigger: PlanTrigger.create,
    reason: 'create',
    version: ruleVersionOld
        ? const PlanVersion(parameterVersion: 0)
        : PlanVersion.current,
    inputsJson: jsonEncode(inputs.toJson()),
    summaryJson: '{}',
  );
  final hints = GeneratedPlan(
    version: PlanVersion.current,
    weeks: weeks,
    units: const [],
    frozenUnits: const [],
    unplacedByWeek: unplacedByWeek,
    hardOmissions: hardOmissions,
    droppedDaysByWeek: droppedDaysByWeek,
    pinnedConflicts: pinnedConflicts,
    walkRunStaysAtWeek: walkRunStaysAtWeek,
    walkRunNoWeekFits: walkRunNoWeekFits,
    hardFit: hardFit,
  );
  return PlanViewState.ready(
    goal: goal,
    version: version,
    hints: hints,
    lastChange: null,
    weekUnits: weekUnits,
    assessment: assessment,
  );
}

void main() {
  group('Navigation (FR-0208)', () {
    testWidgets('vier Bereiche, Plan an zweiter Stelle', (tester) async {
      await started(tester);
      final labels = tester
          .widgetList<NavigationDestination>(find.byType(NavigationDestination))
          .map((d) => d.label)
          .toList();
      expect(labels, ['Heute', 'Plan', 'Verlauf', 'Fortschritt']);
      await tester.tap(key('home_plan'));
      await tester.pumpAndSettle();
      expect(key('plan_empty'), findsOneWidget);
      expect(key('plan_create_goal'), findsOneWidget);
      // Zurück aus Plan führt zu Heute.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(key('home_screen'), findsOneWidget);
    });

    testWidgets('englisch: Today, Plan, History, Progress', (tester) async {
      await started(tester, locale: 'en');
      final labels = tester
          .widgetList<NavigationDestination>(find.byType(NavigationDestination))
          .map((d) => d.label)
          .toList();
      expect(labels[1], 'Plan');
      expect(labels, hasLength(4));
    });

    testWidgets('Woche und Scrollposition bleiben beim Tab-Wechsel', (
      tester,
    ) async {
      final d = await started(tester);
      // Niedrig genug, dass die Plan-Seite scrollt.
      tester.view.physicalSize = const Size(411, 640);
      await tester.pumpAndSettle();
      // Montag, 1.6.2026: Ziel mit Plan anlegen.
      final c = PlanController(
        session: d.session,
        clock: d.clock,
        reader: PlanDataReader(
          session: d.session,
          clock: d.clock,
          loadRuns: () async => const [],
        ),
      );
      expect(
        await tester.runAsync(
          () => c.saveGoal(
            _goal(
              target: DateTime.utc(2026, 10, 4),
              createdAt: DateTime.utc(2026, 6, 1),
            ),
          ),
        ),
        PlanActionResult.done,
      );
      c.dispose();
      await tester.tap(key('home_plan'));
      await tester.pumpAndSettle();
      expect(key('plan_list'), findsOneWidget);
      expect(find.text('Woche 1'), findsOneWidget);
      await tester.tap(key('plan_week_next'));
      await tester.pumpAndSettle();
      expect(find.text('Woche 2'), findsOneWidget);
      await tester.drag(key('plan_list'), const Offset(0, -150));
      await tester.pumpAndSettle();
      final offset = tester
          .state<ScrollableState>(
            find.descendant(
              of: key('plan_list'),
              matching: find.byType(Scrollable),
            ),
          )
          .position
          .pixels;
      expect(offset, greaterThan(0));
      await tester.tap(key('home_history'));
      await tester.pumpAndSettle();
      expect(key('plan_list'), findsNothing);
      await tester.tap(key('home_plan'));
      await tester.pumpAndSettle();
      expect(find.text('Woche 2'), findsOneWidget);
      final again = tester
          .state<ScrollableState>(
            find.descendant(
              of: key('plan_list'),
              matching: find.byType(Scrollable),
            ),
          )
          .position
          .pixels;
      expect(again, offset);
    });
  });

  group('Plan-Seite', () {
    for (final brightness in Brightness.values) {
      testWidgets('leer: Einstieg „Ziel anlegen“ (${brightness.name})', (
        tester,
      ) async {
        final session = await FakeStorage().open(_key);
        var taps = 0;
        await _pump(
          tester,
          session: session,
          clock: FakeClock(_now),
          brightness: brightness,
          onCreateGoal: () => taps++,
        );
        expect(find.text('Noch kein Plan'), findsOneWidget);
        await tester.tap(key('plan_create_goal'));
        expect(taps, 1);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('leer, englisch', (tester) async {
      final session = await FakeStorage().open(_key);
      await _pump(
        tester,
        session: session,
        clock: FakeClock(_now),
        locale: 'en',
      );
      expect(find.text('No plan yet'), findsOneWidget);
      expect(find.text('Set a goal'), findsOneWidget);
    });

    for (final (locale, brightness) in [
      ('de', Brightness.light),
      ('de', Brightness.dark),
      ('en', Brightness.light),
      ('en', Brightness.dark),
    ]) {
      testWidgets('mit Plan: Ziel, Phasen, Einschätzung, Woche '
          '($locale, ${brightness.name})', (tester) async {
        final (session, clock) = await tester.runAsync(
          () => _withPlan(_goal()),
        ) as (StorageSession, FakeClock);
        await _pump(
          tester,
          session: session,
          clock: clock,
          locale: locale,
          brightness: brightness,
        );
        final de = locale == 'de';
        expect(
          find.text(de ? '10 km durchlaufen' : 'Run 10 km'),
          findsOneWidget,
        );
        // Phasenbalken mit Kurzformen (OQ-0077).
        expect(key('plan_phase_bar'), findsOneWidget);
        expect(key('plan_phase_build'), findsOneWidget);
        expect(find.text(de ? 'Reduktion' : 'Taper'), findsOneWidget);
        // Einschätzung mit Grundlage (PAR-206).
        expect(key('plan_assessment'), findsOneWidget);
        expect(key('plan_assessment_basis'), findsOneWidget);
        // Woche: Wochenziel als Zeit, ohne lockeres Tempo keine Kilometer.
        expect(find.text(de ? 'Woche 1' : 'Week 1'), findsOneWidget);
        final summary = tester.widget<Text>(key('plan_week_summary')).data!;
        expect(summary, matches(RegExp(r'· \d+(:\d\d)? (min|h)$')));
        expect(summary, isNot(contains('km')));
        // Mo (9.11.) ohne Lauf: Ruhetag; Lauftage Di, Do, Sa ab heute (Mi).
        expect(
          find.descendant(
            of: key('plan_day_2026-11-09'),
            matching: find.text(de ? 'Ruhetag' : 'Rest day'),
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('Tap auf eine Einheit: Beschreibung und Grundlage (FR-0143)', (
      tester,
    ) async {
      final (session, clock) = await tester.runAsync(
        () => _withPlan(_goal()),
      ) as (StorageSession, FakeClock);
      await _pump(tester, session: session, clock: clock);
      // Donnerstag, 12.11., ist ein Lauftag ab heute.
      await tester.tap(key('plan_day_2026-11-12'));
      await tester.pumpAndSettle();
      expect(key('plan_unit_detail'), findsOneWidget);
      expect(key('plan_unit_purpose'), findsOneWidget);
      expect(key('plan_unit_duration'), findsOneWidget);
      expect(key('plan_unit_basis'), findsWidgets);
      expect(find.textContaining('Vorgabe nach Gefühl'), findsWidgets);
      expect(find.textContaining('Anstrengung'), findsWidgets);
    });

    testWidgets('Zeitziel: Einschätzung ohne Daten', (tester) async {
      final (session, clock) = await tester.runAsync(
        () => _withPlan(_goal(type: GoalType.time)),
      ) as (StorageSession, FakeClock);
      await _pump(tester, session: session, clock: clock);
      expect(find.text('10 km unter 55 min'), findsOneWidget);
      expect(
        find.text('Noch nicht genug Daten für eine Einschätzung'),
        findsOneWidget,
      );
      expect(
        find.text(
          'Grundlage: deine Referenzzeit oder deine Läufe der letzten 4 Wochen',
        ),
        findsOneWidget,
      );
    });

    testWidgets('offenes Ziel: Regelmäßigkeit statt Einschätzung', (
      tester,
    ) async {
      final (session, clock) = await tester.runAsync(
        () => _withPlan(_goal(type: GoalType.open)),
      ) as (StorageSession, FakeClock);
      await _pump(tester, session: session, clock: clock);
      expect(find.text('Fitter werden'), findsOneWidget);
      expect(find.textContaining('Diese Woche: 0 von'), findsOneWidget);
    });
  });

  group('Hinweise aus dem Controller', () {
    for (final locale in ['de', 'en']) {
      testWidgets('alle als ruhige Zeilen ($locale)', (tester) async {
        final session = await FakeStorage().open(_key);
        final clock = FakeClock(_now);
        await _pump(
          tester,
          session: session,
          clock: clock,
          locale: locale,
          controller: _Fixed(session, clock, _hintState(ruleVersionOld: true)),
        );
        for (final k in [
          'plan_hint_rule_version',
          'plan_hint_conflict_0',
          'plan_hint_hard_fit',
          'plan_hint_walk_run_stays',
          'plan_hint_dropped',
          'plan_hint_unplaced',
          'plan_hint_hard_omission',
        ]) {
          expect(key(k), findsOneWidget, reason: k);
        }
        final de = locale == 'de';
        expect(
          find.text(
            de
                ? 'Die harte Einheit passt nur in einen Teil der Wochen, weil '
                      'nicht jede Form in deine maximale Zeit je Einheit passt.'
                : 'The hard session fits only some weeks, because not every '
                      'form fits your maximum time per session.',
          ),
          findsOneWidget,
        );
        expect(
          find.text(
            de
                ? 'Die Geh-Lauf-Abfolge bleibt bei Woche 4, weil die nächste '
                      'nicht in deine maximale Zeit je Einheit passt.'
                : 'The walk-run sequence stays at week 4, because the next '
                      'one does not fit your maximum time per session.',
          ),
          findsOneWidget,
        );
        // Der wegfallende Freitag steht in der Woche.
        expect(
          find.descendant(
            of: key('plan_day_2026-11-13'),
            matching: find.text(
              de ? 'Lauftag entfällt' : 'Running day dropped',
            ),
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('aktuelle Regelversion: kein Hinweis darauf', (tester) async {
      final session = await FakeStorage().open(_key);
      final clock = FakeClock(_now);
      await _pump(
        tester,
        session: session,
        clock: clock,
        controller: _Fixed(session, clock, _hintState(ruleVersionOld: false)),
      );
      expect(key('plan_hint_rule_version'), findsNothing);
      expect(key('plan_hint_conflict_0'), findsOneWidget);
    });
  });

  group('Nachbesserung Teil B', () {
    PlanUnit unit(DateTime day, {int? runId}) => PlanUnit(
      day: day,
      kind: PlanUnitKind.easy,
      phase: PlanPhase.entry,
      weekIndex: 0,
      minutes: 30,
      segments: const [],
      runId: runId,
    );

    Future<void> pumpFixed(
      WidgetTester tester,
      PlanViewState state, {
      String locale = 'de',
      Brightness brightness = Brightness.light,
    }) async {
      final session = await FakeStorage().open(_key);
      final clock = FakeClock(_now);
      await _pump(
        tester,
        session: session,
        clock: clock,
        locale: locale,
        brightness: brightness,
        controller: _Fixed(session, clock, state),
      );
    }

    for (final locale in ['de', 'en']) {
      testWidgets('Geh-Lauf-Plan: Hinweis nach PAR-115 im Wortlaut ($locale)', (
        tester,
      ) async {
        final (session, clock) = await tester.runAsync(
          () => _withPlan(_goal(canRun30: ContinuousRun30.no)),
        ) as (StorageSession, FakeClock);
        await _pump(tester, session: session, clock: clock, locale: locale);
        expect(
          find.descendant(
            of: key('plan_hint_walk_run_care'),
            matching: find.text(
              locale == 'de'
                  ? 'Hör auf, wenn sich etwas nicht richtig anfühlt. Wenn du '
                        'dir Sorgen um deine Gesundheit machst, sprich vorher '
                        'mit einer Ärztin oder einem Arzt.'
                  : "Stop if something doesn't feel right. If you are "
                        'worried about your health, talk to a doctor first.',
            ),
          ),
          findsOneWidget,
        );
      });
    }

    testWidgets('Plan ohne Geh-Lauf: kein PAR-115-Hinweis', (tester) async {
      final (session, clock) = await tester.runAsync(
        () => _withPlan(_goal()),
      ) as (StorageSession, FakeClock);
      await _pump(tester, session: session, clock: clock);
      expect(key('plan_hint_walk_run_care'), findsNothing);
    });

    testWidgets('keine Geh-Lauf-Woche passt: eigener Hinweis, kein „bleibt“', (
      tester,
    ) async {
      await pumpFixed(
        tester,
        _state(walkRunNoWeekFits: true, walkRunStaysAtWeek: 3),
      );
      expect(
        find.text(
          'Schon die erste Woche der Geh-Lauf-Abfolge passt nicht in deine '
          'maximale Zeit je Einheit.',
        ),
        findsOneWidget,
      );
      expect(key('plan_hint_walk_run_no_week'), findsOneWidget);
      expect(key('plan_hint_walk_run_stays'), findsNothing);
    });

    testWidgets('fehlende harte Einheit: Grund im Wortlaut', (tester) async {
      await pumpFixed(
        tester,
        _state(hardOmissions: const {0: HardOmission.noRecoveryDay}),
      );
      expect(
        find.descendant(
          of: key('plan_hint_hard_omission'),
          matching: find.text(
            'Keine harte Einheit diese Woche: Kein Lauftag hat einen vollen '
            'Tag Abstand zum langen Lauf.',
          ),
        ),
        findsOneWidget,
      );
    });

    for (final (status, text) in [
      (
        HardFitStatus.regulatorBelowFit,
        'Für die harte Einheit reicht deine maximale Wochenzeit nicht; der '
            'Plan bleibt ohne sie.',
      ),
      (
        HardFitStatus.neverFits,
        'Mit deinen Lauftagen und deiner maximalen Zeit je Einheit passt die '
            'harte Einheit in keine Woche.',
      ),
    ]) {
      testWidgets('harte Einheit ${status.name}: Wortlaut', (tester) async {
        await pumpFixed(tester, _state(hardFit: status));
        expect(
          find.descendant(
            of: key('plan_hint_hard_fit'),
            matching: find.text(text),
          ),
          findsOneWidget,
        );
      });
    }

    testWidgets('Einschätzung „passt“ mit Grundlage im Wortlaut', (
      tester,
    ) async {
      await pumpFixed(
        tester,
        _state(
          type: GoalType.distance,
          assessment: const GoalAssessment(
            feasibility: GoalFeasibility.fits,
            reason: FeasibilityReason.peakReached,
          ),
        ),
      );
      expect(
        tester.widget<Text>(key('plan_assessment')).data,
        'Passt zum Zieldatum',
      );
      expect(
        tester.widget<Text>(key('plan_assessment_basis')).data,
        'Grundlage: deine Wochenzeit, so wie der Plan sie steigert',
      );
    });

    for (final locale in ['de', 'en']) {
      testWidgets('Einschätzung „knapp“ mit Datum ($locale)', (tester) async {
        await pumpFixed(
          tester,
          locale: locale,
          _state(
            type: GoalType.distance,
            assessment: GoalAssessment(
              feasibility: GoalFeasibility.tight,
              reason: FeasibilityReason.peakTooLate,
              fitsFrom: DateTime.utc(2027, 4, 4),
            ),
          ),
        );
        expect(
          tester.widget<Text>(key('plan_assessment')).data,
          locale == 'de'
              ? 'Das wird knapp, ab etwa 4. Apr. 2027 passt es'
              : 'This will be tight; from about Apr 4, 2027 it fits',
        );
      });
    }

    testWidgets('Wochenziel „ca. N km“ mit bekanntem lockerem Tempo', (
      tester,
    ) async {
      // 6:00 min/km, genug lockere Läufe (PAR-205): 120 min = ca. 20 km.
      await pumpFixed(
        tester,
        _state(
          easyPaceSecondsPerKm: 360,
          easyRunCount: const PlanParameters().peakMinEasyRuns,
        ),
      );
      final summary = tester.widget<Text>(key('plan_week_summary')).data!;
      expect(summary, endsWith(' · ca. 20 km'));
    });

    testWidgets('Wochenkopf ab der dritten Woche nach dem Anker: Zeit und '
        'Nummer der Woche von heute (Nachbesserung E)', (tester) async {
      // Anker zwei Wochen vor dieser Woche; die Rechnung beginnt mit dieser
      // Woche (Nummer 3). Jede Woche hat eine eigene Zeit.
      await pumpFixed(
        tester,
        _state(
          anchorWeeksEarlier: 2,
          weekMinutes: [100, 110, 120, 130, 140, 150],
        ),
      );
      expect(tester.widget<Text>(key('plan_week_title')).data, 'Woche 3');
      final summary = tester.widget<Text>(key('plan_week_summary')).data!;
      expect(summary, contains('1:40 h'));
      await tester.tap(key('plan_week_next'));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(key('plan_week_title')).data, 'Woche 4');
      expect(
        tester.widget<Text>(key('plan_week_summary')).data!,
        contains('1:50 h'),
      );
    });

    test('planWeekMinutes: Woche über den Montag, nicht über die Position ab '
        'dem Anker (Nachbesserung E)', () {
      final s = _state(
        anchorWeeksEarlier: 2,
        weekMinutes: [100, 110, 120, 130, 140, 150],
      );
      int at(int weeks) => planWeekMinutes(
        hints: s.hints,
        monday: _monday.add(Duration(days: 7 * weeks)),
        units: const [],
      );
      expect(at(0), 100);
      expect(at(1), 110);
      expect(at(5), 150);
      // Außerhalb der Rechnung: Summe der Einheiten (hier keine).
      expect(at(6), 0);
      expect(at(-1), 0);
    });

    testWidgets('zu wenige lockere Läufe: keine Kilometer', (tester) async {
      await pumpFixed(
        tester,
        _state(
          easyPaceSecondsPerKm: 360,
          easyRunCount: const PlanParameters().peakMinEasyRuns - 1,
        ),
      );
      final summary = tester.widget<Text>(key('plan_week_summary')).data!;
      expect(summary, isNot(contains('km')));
    });

    for (final locale in ['de', 'en']) {
      testWidgets(
        'Phasenbalken: voller Phasenname für Screenreader ($locale)',
        (tester) async {
          final handle = tester.ensureSemantics();
          // Diese Woche ist die sechste und letzte: Reduktion.
          await pumpFixed(tester, locale: locale, _state(firstWeekOffset: -5));
          // Die Karte fasst ihre Semantik zusammen; der Balken steht darin.
          expect(
            tester.getSemantics(key('plan_phase_bar')).label,
            contains(
              locale == 'de'
                  ? 'Phase Reduktion vor Wettkampf, Woche 6 von 6'
                  : 'Phase Taper before the race, week 6 of 6',
            ),
          );
          handle.dispose();
        },
      );
    }

    testWidgets('heutige Einheit hebt sich ab (dunkel)', (tester) async {
      await pumpFixed(
        tester,
        brightness: Brightness.dark,
        _state(
          weekUnits: [unit(_today), unit(_today.add(const Duration(days: 1)))],
        ),
      );
      RamuriCardTone tone(String k) => tester.widget<RamuriCard>(key(k)).tone;
      expect(tone('plan_day_2026-11-11'), RamuriCardTone.panel);
      expect(tone('plan_day_2026-11-12'), RamuriCardTone.surface);
    });

    testWidgets('Regelmäßigkeit zählt nur Einheiten bis heute', (tester) async {
      // Mo gelaufen, Mi (heute) offen, Fr und So noch nicht dran.
      await pumpFixed(
        tester,
        _state(
          type: GoalType.open,
          assessment: const GoalAssessment(
            feasibility: null,
            reason: FeasibilityReason.showRegularity,
          ),
          weekUnits: [
            unit(_monday, runId: 1),
            unit(_today),
            unit(_monday.add(const Duration(days: 4))),
            unit(_monday.add(const Duration(days: 6))),
          ],
        ),
      );
      expect(
        tester.widget<Text>(key('plan_assessment')).data,
        'Diese Woche: 1 von 2 Einheiten gelaufen',
      );
    });

    testWidgets('Woche lässt sich nicht laden: Fehlerzeile statt Spinner', (
      tester,
    ) async {
      final session = await FakeStorage().open(_key);
      final clock = FakeClock(_now);
      await _pump(
        tester,
        session: session,
        clock: clock,
        controller: _Failing(session, clock, _state()),
      );
      await tester.tap(key('plan_week_next'));
      await tester.pumpAndSettle();
      expect(key('plan_week_failed'), findsOneWidget);
      expect(find.text('Der Plan ließ sich nicht laden.'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    for (final locale in ['de', 'en']) {
      testWidgets('Ziel der Einheit nach PAR-109 ($locale)', (tester) async {
        await pumpFixed(
          tester,
          locale: locale,
          _state(weekUnits: [unit(_today.add(const Duration(days: 1)))]),
        );
        await tester.tap(key('plan_day_2026-11-12'));
        await tester.pumpAndSettle();
        expect(
          tester.widget<Text>(key('plan_unit_purpose')).data,
          locale == 'de' ? 'Aerobe Grundlage.' : 'Aerobic base.',
        );
      });
    }
  });
}

/// Wie [_Fixed], aber andere Wochen lassen sich nicht laden.
class _Failing extends _Fixed {
  _Failing(super.session, super.clock, super.fixed);
  @override
  Future<List<PlanUnit>> unitsBetween(DateTime from, DateTime to) =>
      Future.error(const StorageException(StorageFailure.notFound));
}
