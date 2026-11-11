import 'dart:async';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:running_app/features/plan/plan_controller.dart';
import 'package:running_app/features/plan/plan_data_reader.dart';
import 'package:running_app/features/plan/plan_screen.dart';
import 'package:running_app/features/settings/app_settings.dart';
import 'package:running_app/l10n/app_localizations.dart';
import 'package:running_app/offload_scope.dart';
import 'package:running_app/ui/ui.dart';

final Uint8List _key = Uint8List.fromList(List.generate(32, (i) => i));

/// Mittwoch, 11.11.2026, mittags.
final _now = DateTime.utc(2026, 11, 11, 12);
final _today = DateTime.utc(2026, 11, 11);

TrainingGoal _goal({
  DateTime? target,
  Set<int> days = const {2, 4, 6},
  DateTime? createdAt,
  ContinuousRun30 canRun30 = ContinuousRun30.yes,
}) => TrainingGoal(
  type: GoalType.distance,
  distance: GoalDistance.tenKilometers,
  targetDate: target ?? DateTime.utc(2027, 3, 14),
  runDays: days,
  maxSessionSeconds: 120 * 60,
  weeklyCapSeconds: 4 * 3600,
  createdAt: createdAt ?? DateTime.utc(2026, 11, 1),
  hardSessionEnabled: false,
  canRun30: canRun30,
);

PlanController _controller(
  StorageSession session,
  Clock clock, {
  List<RunFigures> runs = const [],
}) => PlanController(
  session: session,
  clock: clock,
  reader: PlanDataReader(
    session: session,
    clock: clock,
    loadRuns: () async => runs,
  ),
);

/// Controller mit festem Ergebnis von [saveGoal] (Rückmeldungen).
class _Scripted extends PlanController {
  _Scripted(StorageSession session, Clock clock, this.result)
    : super(
        session: session,
        clock: clock,
        reader: PlanDataReader(
          session: session,
          clock: clock,
          loadRuns: () async => const [],
        ),
      );
  final PlanActionResult result;
  int saves = 0;
  @override
  Future<PlanActionResult> saveGoal(TrainingGoal goal) async {
    saves++;
    return result;
  }
}

/// Controller mit eigener Einschätzung ([checkGoal]) für Rennen und Fehler.
class _Checking extends PlanController {
  _Checking(StorageSession session, Clock clock, this.check)
    : super(
        session: session,
        clock: clock,
        reader: PlanDataReader(
          session: session,
          clock: clock,
          loadRuns: () async => const [],
        ),
      );
  final Future<GoalDraftCheck> Function(TrainingGoal draft) check;
  final saved = <TrainingGoal>[];
  @override
  Future<GoalDraftCheck> checkGoal(TrainingGoal draft) => check(draft);
  @override
  Future<PlanActionResult> saveGoal(TrainingGoal goal) async {
    saved.add(goal);
    return PlanActionResult.done;
  }
}

/// Lese-Adapter mit fester Grundlage für Zeitziele (Referenz, Läufe).
class _BasisReader extends PlanDataReader {
  _BasisReader(StorageSession session, Clock clock, this.basis)
    : super(session: session, clock: clock, loadRuns: () async => const []);
  final TimeGoalBasis basis;
  @override
  Future<TimeGoalBasis> timeGoalBasis({
    required TrainingGoal goal,
    required DateTime today,
    FeasibilityParameters feasibility = const FeasibilityParameters(),
  }) async => goal.type == GoalType.time ? basis : const TimeGoalBasis();
}

Future<void> _pump(
  WidgetTester tester, {
  required StorageSession session,
  required Clock clock,
  required PlanController controller,
  String locale = 'de',
  Brightness brightness = Brightness.light,
}) async {
  tester.view.physicalSize = const Size(411, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  addTearDown(controller.dispose);
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
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<(StorageSession, FakeClock)> _empty() async =>
    (await FakeStorage().open(_key), FakeClock(_now));

/// Speicher mit Ziel und erster Fassung, angelegt am Tag von [clock].
Future<StorageSession> _withPlan(TrainingGoal goal, FakeClock clock) async {
  final session = await FakeStorage().open(_key);
  final c = _controller(session, clock);
  expect(await c.saveGoal(goal), PlanActionResult.done);
  c.dispose();
  return session;
}

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

Future<void> _enter(WidgetTester tester, String key, String text) async {
  final f = find.byKey(Key(key));
  await tester.ensureVisible(f);
  await tester.enterText(f, text);
  await tester.pumpAndSettle();
}

/// Trägt im Datumsdialog den Tag [day] des gezeigten Monats ein.
Future<void> _pickDay(WidgetTester tester, int day) async {
  await _tap(tester, find.byKey(const Key('plan_form_date_pick')));
  await tester.tap(find.text('$day'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
}

String _error(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('plan_form_error'))).data!;

bool _chipSelected(WidgetTester tester, int weekday) => tester
    .widget<FilterChip>(find.byKey(Key('plan_form_day_$weekday')))
    .selected;

void main() {
  late AppLocalizations de;
  late AppLocalizations en;
  setUpAll(() async {
    de = await AppLocalizations.delegate.load(const Locale('de'));
    en = await AppLocalizations.delegate.load(const Locale('en'));
  });

  testWidgets('Anlegen aus dem leeren Zustand: Profil vorbelegt, '
      'Einschätzung vor dem Speichern, gespeichert mit heute', (tester) async {
    final (session, clock) = await _empty();
    await session.profile.save(
      const ProfileRecord(
        trainingDaysMask: 0x15, // Mo, Mi, Fr
        usualTrainingMinutes: 50,
        weeklyRunMinutes: 120,
      ),
    );
    final c = _controller(session, clock);
    await _pump(tester, session: session, clock: clock, controller: c);
    await _tap(tester, find.byKey(const Key('plan_create_goal')));

    expect(find.text(de.planFormTitleNew), findsOneWidget);
    // OQ-0038: Lauftage, Minuten je Einheit und Stand aus dem Profil.
    expect(
      [for (var d = 1; d <= 7; d++) _chipSelected(tester, d)],
      [true, false, true, false, true, false, false],
    );
    expect(find.text('50'), findsOneWidget);
    expect(find.text('120'), findsOneWidget);
    // Stand genannt: die Frage zu 30 min entfällt (PAR-192).
    expect(find.byKey(const Key('plan_form_can30')), findsNothing);

    await _tap(tester, find.text(de.planDistance10k));
    await _pickDay(tester, 28);
    // Erst prüfen, dann speichern.
    expect(find.byKey(const Key('plan_form_save')), findsNothing);
    await _tap(tester, find.byKey(const Key('plan_form_check')));
    expect(find.byKey(const Key('plan_form_assessment')), findsOneWidget);
    expect(find.byKey(const Key('plan_form_assessment_basis')), findsOneWidget);
    await _tap(tester, find.byKey(const Key('plan_form_save')));

    // Zurück auf der Plan-Seite mit Meldung.
    expect(find.byKey(const Key('plan_form')), findsNothing);
    expect(find.text(de.planGoalSaved), findsOneWidget);
    expect(find.byKey(const Key('plan_goal_card')), findsOneWidget);
    final goal = (await (session as GoalStorage).goals.goal())!;
    expect(goal.type, GoalType.distance);
    expect(goal.distance, GoalDistance.tenKilometers);
    expect(goal.targetDate, DateTime.utc(2026, 11, 28));
    expect(goal.runDays, {1, 3, 5});
    expect(goal.maxSessionSeconds, 50 * 60);
    expect(goal.currentWeeklySeconds, 120 * 60);
    expect(goal.weeklyCapSeconds, 4 * 3600);
    expect(goal.hardSessionEnabled, isFalse);
    final history = await (session as PlanStorage).plans.history();
    expect(history.single.inputs.today, _today);
  });

  testWidgets('Ändern: Formular vorbelegt, Änderung rechnet mit goalChange', (
    tester,
  ) async {
    final clock = FakeClock(_now);
    final session = await _withPlan(_goal(), clock);
    final c = _controller(session, clock);
    await _pump(tester, session: session, clock: clock, controller: c);
    await _tap(tester, find.byKey(const Key('plan_edit_goal')));

    expect(find.text(de.planFormTitleEdit), findsOneWidget);
    expect(
      [for (var d = 1; d <= 7; d++) _chipSelected(tester, d)],
      [false, true, false, true, false, true, false],
    );
    expect(find.text('120'), findsOneWidget); // max. Minuten je Einheit
    expect(
      tester.widget<Text>(find.byKey(const Key('plan_form_date'))).data,
      DateFormat.yMMMd('de').format(DateTime.utc(2027, 3, 14)),
    );
    expect(find.text(de.planFormRegulatorValue('4')), findsWidgets);
    expect(tester.widget<Slider>(find.byType(Slider)).value, 4);

    await _tap(tester, find.byKey(const Key('plan_form_day_1')));
    await _tap(tester, find.byKey(const Key('plan_form_check')));
    await _tap(tester, find.byKey(const Key('plan_form_save')));

    final goal = (await (session as GoalStorage).goals.goal())!;
    expect(goal.runDays, {1, 2, 4, 6});
    expect(goal.createdAt, DateTime.utc(2026, 11, 1));
    expect(goal.targetDate, DateTime.utc(2027, 3, 14));
    final history = await (session as PlanStorage).plans.history();
    expect(history.length, 2);
    expect(history.last.trigger, PlanTrigger.goalChange);
  });

  testWidgets('Pflichtfelder: ohne Lauftage, Minuten, Stand oder Zielzeit '
      'wird nichts gespeichert', (tester) async {
    final (session, clock) = await _empty();
    final c = _Scripted(session, clock, PlanActionResult.done);
    await _pump(tester, session: session, clock: clock, controller: c);
    await _tap(tester, find.byKey(const Key('plan_create_goal')));
    final check = find.byKey(const Key('plan_form_check'));

    await _tap(tester, check);
    expect(_error(tester), de.planFormErrorRunDays);
    await _tap(tester, find.byKey(const Key('plan_form_day_2')));
    await _tap(tester, check);
    expect(_error(tester), de.planFormErrorMaxSession);
    await _enter(tester, 'plan_form_max_session', '45');
    await _tap(tester, check);
    expect(_error(tester), de.planFormErrorStand);
    await _enter(tester, 'plan_form_weekly', '60');
    await _tap(tester, find.text(de.planFormTypeTime));
    await _tap(tester, check);
    expect(_error(tester), de.planFormErrorTime);
    expect(find.byKey(const Key('plan_form_save')), findsNothing);
    expect(c.saves, 0);

    await _enter(tester, 'plan_form_minutes', '28');
    await _tap(tester, check);
    expect(find.byKey(const Key('plan_form_error')), findsNothing);
    expect(find.byKey(const Key('plan_form_save')), findsOneWidget);
  });

  testWidgets('Minuten je Einheit: Fehler steht am Feld und verschwindet '
      'mit der Eingabe', (tester) async {
    final (session, clock) = await _empty();
    final c = _Scripted(session, clock, PlanActionResult.done);
    await _pump(tester, session: session, clock: clock, controller: c);
    await _tap(tester, find.byKey(const Key('plan_create_goal')));
    await _tap(tester, find.byKey(const Key('plan_form_day_2')));
    String? fieldError() => tester
        .widget<TextField>(find.byKey(const Key('plan_form_max_session')))
        .decoration!
        .errorText;
    expect(fieldError(), isNull);
    await _tap(tester, find.byKey(const Key('plan_form_check')));
    expect(fieldError(), de.planFormErrorMaxSession);
    expect(
      find.descendant(
        of: find.byKey(const Key('plan_form_max_session')),
        matching: find.text(de.planFormErrorMaxSession),
      ),
      findsOneWidget,
    );
    await _enter(tester, 'plan_form_max_session', '45');
    expect(fieldError(), isNull);
  });

  testWidgets('Zielzeit fehlt: Fehler unter den Zeitfeldern', (tester) async {
    final (session, clock) = await _empty();
    final c = _Scripted(session, clock, PlanActionResult.done);
    await _pump(tester, session: session, clock: clock, controller: c);
    await _tap(tester, find.byKey(const Key('plan_create_goal')));
    await _tap(tester, find.text(de.planFormTypeTime));
    await _tap(tester, find.byKey(const Key('plan_form_day_2')));
    await _enter(tester, 'plan_form_max_session', '45');
    expect(find.byKey(const Key('plan_form_time_error')), findsNothing);
    await _tap(tester, find.byKey(const Key('plan_form_check')));
    final error = find.byKey(const Key('plan_form_time_error'));
    expect(error, findsOneWidget);
    expect(tester.widget<Text>(error).data, de.planFormErrorTime);
    expect(
      tester.getTopLeft(error).dy,
      greaterThan(
        tester.getBottomLeft(find.byKey(const Key('plan_form_hours'))).dy,
      ),
    );
    await _enter(tester, 'plan_form_minutes', '25');
    expect(error, findsNothing);
  });

  testWidgets('Wochenminuten ungültig: Fehler steht am Feld', (tester) async {
    final (session, clock) = await _empty();
    final c = _Scripted(session, clock, PlanActionResult.done);
    await _pump(tester, session: session, clock: clock, controller: c);
    await _tap(tester, find.byKey(const Key('plan_create_goal')));
    await _tap(tester, find.byKey(const Key('plan_form_day_2')));
    await _enter(tester, 'plan_form_max_session', '45');
    await _enter(tester, 'plan_form_weekly', '0');
    String? fieldError() => tester
        .widget<TextField>(find.byKey(const Key('plan_form_weekly')))
        .decoration!
        .errorText;
    await _tap(tester, find.byKey(const Key('plan_form_check')));
    expect(fieldError(), de.planFormErrorWeekly);
    await _enter(tester, 'plan_form_weekly', '60');
    expect(fieldError(), isNull);
  });

  testWidgets('Nach dem Datumsdialog bleibt die Tastatur zu (kein Fokus '
      'zurück ins zuletzt bearbeitete Feld)', (tester) async {
    final (session, clock) = await _empty();
    final c = _Scripted(session, clock, PlanActionResult.done);
    await _pump(tester, session: session, clock: clock, controller: c);
    await _tap(tester, find.byKey(const Key('plan_create_goal')));
    await _tap(tester, find.text(de.planFormTypeTime));
    await _tap(tester, find.byKey(const Key('plan_form_seconds')));
    await tester.enterText(find.byKey(const Key('plan_form_seconds')), '0');
    await tester.pumpAndSettle();
    final seconds = find.descendant(
      of: find.byKey(const Key('plan_form_seconds')),
      matching: find.byType(EditableText),
    );
    expect(tester.widget<EditableText>(seconds).focusNode.hasFocus, isTrue);
    await _pickDay(tester, 20);
    expect(tester.widget<EditableText>(seconds).focusNode.hasFocus, isFalse);
    expect(tester.testTextInput.isVisible, isFalse);
    expect(
      tester.widget<Text>(find.byKey(const Key('plan_form_date'))).data,
      DateFormat.yMMMd('de').format(DateTime(2026, 11, 20)),
    );
  });

  testWidgets('Nach dem Referenzdialog bleibt die Tastatur zu (kein Fokus '
      'zurück ins zuletzt bearbeitete Feld)', (tester) async {
    final (session, clock) = await _empty();
    final c = _Scripted(session, clock, PlanActionResult.done);
    await _pump(tester, session: session, clock: clock, controller: c);
    await _tap(tester, find.byKey(const Key('plan_create_goal')));
    await _tap(tester, find.text(de.planFormTypeTime));
    await _tap(tester, find.byKey(const Key('plan_form_minutes')));
    await tester.enterText(find.byKey(const Key('plan_form_minutes')), '30');
    await tester.pumpAndSettle();
    final minutes = find.descendant(
      of: find.byKey(const Key('plan_form_minutes')),
      matching: find.byType(EditableText),
    );
    expect(tester.widget<EditableText>(minutes).focusNode.hasFocus, isTrue);
    await _tap(tester, find.byKey(const Key('plan_form_reference_add')));
    await tester.enterText(
      find.byKey(const Key('prediction_form_minutes')),
      '50',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('prediction_form_save')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('prediction_form')), findsNothing);
    expect(tester.widget<EditableText>(minutes).focusNode.hasFocus, isFalse);
    expect(tester.testTextInput.isVisible, isFalse);
    final refs = await (session as PredictionStorage).prediction.references();
    expect(refs, hasLength(1));
  });

  testWidgets('Nach dem Hinweisdialog (Geh-Lauf) bleibt die Tastatur zu', (
    tester,
  ) async {
    final (session, clock) = await _empty();
    final c = _controller(session, clock);
    await _pump(tester, session: session, clock: clock, controller: c);
    await _tap(tester, find.byKey(const Key('plan_create_goal')));
    await _tap(tester, find.byKey(const Key('plan_form_day_2')));
    await _tap(tester, find.byKey(const Key('plan_form_day_4')));
    await _tap(tester, find.byKey(const Key('plan_form_day_6')));
    await _tap(tester, find.text(de.planFormNo));
    await _tap(tester, find.byKey(const Key('plan_form_max_session')));
    await tester.enterText(
      find.byKey(const Key('plan_form_max_session')),
      '45',
    );
    await tester.pumpAndSettle();
    final field = find.descendant(
      of: find.byKey(const Key('plan_form_max_session')),
      matching: find.byType(EditableText),
    );
    expect(tester.widget<EditableText>(field).focusNode.hasFocus, isTrue);
    await _tap(tester, find.byKey(const Key('plan_form_check')));
    expect(tester.widget<EditableText>(field).focusNode.hasFocus, isTrue);
    await _tap(tester, find.byKey(const Key('plan_form_save')));
    expect(find.byKey(const Key('plan_form_care')), findsOneWidget);
    await _tap(tester, find.byKey(const Key('plan_form_care_cancel')));
    expect(tester.widget<EditableText>(field).focusNode.hasFocus, isFalse);
    expect(tester.testTextInput.isVisible, isFalse);
  });

  testWidgets('Zieldatum vor heute wird mit heute geprüft, nicht mit dem '
      'Anlegetag', (tester) async {
    // Angelegt am 1.11. mit Zieldatum 5.11.; heute ist der 11.11.
    final clock = FakeClock(DateTime.utc(2026, 11, 1, 12));
    final session = await _withPlan(
      _goal(
        target: DateTime.utc(2026, 11, 5),
        createdAt: DateTime.utc(2026, 11, 1),
      ),
      clock,
    );
    clock.set(_now);
    final c = _Scripted(session, clock, PlanActionResult.done);
    await _pump(tester, session: session, clock: clock, controller: c);
    await _tap(tester, find.byKey(const Key('plan_edit_goal')));
    await _tap(tester, find.byKey(const Key('plan_form_check')));
    expect(_error(tester), de.planFormErrorDatePast);
    expect(c.saves, 0);
  });

  testWidgets('PAR-115: vor dem Geh-Lauf-Plan Hinweis bestätigen; Abbrechen '
      'speichert nichts', (tester) async {
    final (session, clock) = await _empty();
    final c = _controller(session, clock);
    await _pump(tester, session: session, clock: clock, controller: c);
    await _tap(tester, find.byKey(const Key('plan_create_goal')));
    await _tap(tester, find.byKey(const Key('plan_form_day_2')));
    await _tap(tester, find.byKey(const Key('plan_form_day_4')));
    await _tap(tester, find.byKey(const Key('plan_form_day_6')));
    await _enter(tester, 'plan_form_max_session', '45');
    await _tap(tester, find.text(de.planFormNo));
    await _tap(tester, find.byKey(const Key('plan_form_check')));
    await _tap(tester, find.byKey(const Key('plan_form_save')));

    expect(find.byKey(const Key('plan_form_care')), findsOneWidget);
    expect(find.text(de.planHintWalkRunCare), findsOneWidget);
    await _tap(tester, find.byKey(const Key('plan_form_care_cancel')));
    expect(await (session as GoalStorage).goals.goal(), isNull);
    expect(find.byKey(const Key('plan_form')), findsOneWidget);

    await _tap(tester, find.byKey(const Key('plan_form_save')));
    await _tap(tester, find.byKey(const Key('plan_form_care_confirm')));
    final goal = (await (session as GoalStorage).goals.goal())!;
    expect(goal.canRun30, ContinuousRun30.no);
    final units = await (session as PlanStorage).plans.unitsBetween(
      _today,
      planFarFuture,
    );
    expect(units.any((u) => u.kind == PlanUnitKind.walkRun), isTrue);
  });

  testWidgets('PAR-115: ohne Geh-Lauf kein Hinweis', (tester) async {
    final (session, clock) = await _empty();
    final c = _controller(session, clock);
    await _pump(tester, session: session, clock: clock, controller: c);
    await _tap(tester, find.byKey(const Key('plan_create_goal')));
    await _tap(tester, find.byKey(const Key('plan_form_day_2')));
    await _tap(tester, find.byKey(const Key('plan_form_day_4')));
    await _enter(tester, 'plan_form_max_session', '45');
    await _tap(tester, find.text(de.planFormYes));
    await _tap(tester, find.byKey(const Key('plan_form_check')));
    await _tap(tester, find.byKey(const Key('plan_form_save')));
    expect(find.byKey(const Key('plan_form_care')), findsNothing);
    expect(await (session as GoalStorage).goals.goal(), isNotNull);
  });

  testWidgets('Einschätzung „knapp“ mit Angebot eines Datums; Übernehmen '
      'setzt das Datum und schätzt neu ein', (tester) async {
    final clock = FakeClock(_now);
    final session = await _withPlan(
      _goal(target: _today.add(const Duration(days: 14))),
      clock,
    );
    final c = _controller(session, clock);
    await _pump(tester, session: session, clock: clock, controller: c);
    await _tap(tester, find.byKey(const Key('plan_edit_goal')));
    await _tap(tester, find.byKey(const Key('plan_form_check')));

    final check = await c.checkGoal(
      (await (session as GoalStorage).goals.goal())!,
    );
    final offer = check.assessment.fitsFrom!;
    final offerText = DateFormat.yMMMd('de').format(offer);
    expect(
      tester
          .widget<Text>(find.byKey(const Key('plan_form_assessment_main')))
          .data,
      de.planAssessTightFrom(offerText),
    );
    await _tap(tester, find.byKey(const Key('plan_form_accept_date')));
    expect(
      tester.widget<Text>(find.byKey(const Key('plan_form_date'))).data,
      offerText,
    );
    expect(
      tester
          .widget<Text>(find.byKey(const Key('plan_form_assessment_main')))
          .data,
      de.planAssessFits,
    );
  });

  testWidgets('Mit Läufen entfällt die Frage nach dem Stand (PAR-192)', (
    tester,
  ) async {
    final (session, clock) = await _empty();
    String dayText(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
    final runs = [
      for (var i = 0; i < 3; i++)
        RunFigures(
          runId: i + 1,
          endedAt: _today
              .subtract(Duration(days: 1 + 2 * i))
              .add(const Duration(hours: 8)),
          day: dayText(_today.subtract(Duration(days: 1 + 2 * i))),
          distanceMeters: 5000,
          movingTime: const Duration(minutes: 30),
          totalTime: const Duration(minutes: 30),
        ),
    ];
    final c = _controller(session, clock, runs: runs);
    await _pump(tester, session: session, clock: clock, controller: c);
    await _tap(tester, find.byKey(const Key('plan_create_goal')));
    expect(find.byKey(const Key('plan_form_stand_runs')), findsOneWidget);
    expect(find.byKey(const Key('plan_form_weekly')), findsNothing);
    expect(find.byKey(const Key('plan_form_can30')), findsNothing);
    await _tap(tester, find.byKey(const Key('plan_form_day_2')));
    await _enter(tester, 'plan_form_max_session', '45');
    await _tap(tester, find.byKey(const Key('plan_form_check')));
    expect(find.byKey(const Key('plan_form_error')), findsNothing);
    expect(find.byKey(const Key('plan_form_save')), findsOneWidget);
  });

  Future<void> fillAndSave(WidgetTester tester) async {
    await _tap(tester, find.byKey(const Key('plan_create_goal')));
    await _tap(tester, find.byKey(const Key('plan_form_day_2')));
    await _enter(tester, 'plan_form_max_session', '45');
    await _tap(tester, find.text(de.planFormYes));
    await _tap(tester, find.byKey(const Key('plan_form_check')));
    await _tap(tester, find.byKey(const Key('plan_form_save')));
  }

  testWidgets('Ergebnis savedNotPlanned steht als Meldung da', (tester) async {
    final (session, clock) = await _empty();
    await _pump(
      tester,
      session: session,
      clock: clock,
      controller: _Scripted(session, clock, PlanActionResult.savedNotPlanned),
    );
    await fillAndSave(tester);
    expect(find.byKey(const Key('plan_form')), findsNothing);
    expect(find.text(de.planGoalSavedNotPlanned), findsOneWidget);
  });

  testWidgets('Ablehnung und Fehler bleiben im Formular sichtbar', (
    tester,
  ) async {
    final (session, clock) = await _empty();
    await _pump(
      tester,
      session: session,
      clock: clock,
      controller: _Scripted(session, clock, PlanActionResult.rejected),
    );
    await fillAndSave(tester);
    expect(find.byKey(const Key('plan_form')), findsOneWidget);
    expect(_error(tester), de.planFormSaveRejected);
  });

  testWidgets('Ändern: Stand nur Anzeige, keine Frage zu 30 min', (
    tester,
  ) async {
    final clock = FakeClock(_now);
    final session = await _withPlan(_goal(), clock);
    final c = _controller(session, clock);
    await _pump(tester, session: session, clock: clock, controller: c);
    await _tap(tester, find.byKey(const Key('plan_edit_goal')));
    expect(
      tester.widget<Text>(find.byKey(const Key('plan_form_stand_kept'))).data,
      de.planFormStandKeptYes,
    );
    expect(find.byKey(const Key('plan_form_can30')), findsNothing);
    expect(find.byKey(const Key('plan_form_weekly')), findsNothing);
    await _tap(tester, find.byKey(const Key('plan_form_check')));
    await _tap(tester, find.byKey(const Key('plan_form_save')));
    final goal = (await (session as GoalStorage).goals.goal())!;
    expect(goal.canRun30, ContinuousRun30.yes);
  });

  test(
    'Ändern: checkGoal rechnet mit den Eingaben des Speicherns '
    '(Geh-Lauf der letzten Fassung), Hinweis und Plan stimmen überein',
    () async {
      final clock = FakeClock(_now);
      final session = await _withPlan(_goal(), clock);
      final c = _controller(session, clock);
      addTearDown(c.dispose);
      // Ein Entwurf mit „Nein“: Beim Ändern bleibt der Start der Fassung.
      final draft = _goal(canRun30: ContinuousRun30.no);
      final check = await c.checkGoal(draft);
      expect(check.walkRun, isFalse);
      expect(await c.saveGoal(draft), PlanActionResult.done);
      final history = await (session as PlanStorage).plans.history();
      expect(history.last.trigger, PlanTrigger.goalChange);
      final units = await (session as PlanStorage).plans.unitsBetween(
        _today,
        planFarFuture,
      );
      expect(units.any((u) => u.kind == PlanUnitKind.walkRun), check.walkRun);
    },
  );

  testWidgets('PAR-115 beim Ändern: Geh-Lauf-Plan verlangt die Bestätigung', (
    tester,
  ) async {
    final clock = FakeClock(_now);
    final session = await _withPlan(_goal(canRun30: ContinuousRun30.no), clock);
    final c = _controller(session, clock);
    await _pump(tester, session: session, clock: clock, controller: c);
    await _tap(tester, find.byKey(const Key('plan_edit_goal')));
    expect(
      tester.widget<Text>(find.byKey(const Key('plan_form_stand_kept'))).data,
      de.planFormStandKeptNo,
    );
    await _tap(tester, find.byKey(const Key('plan_form_day_1')));
    await _tap(tester, find.byKey(const Key('plan_form_check')));
    await _tap(tester, find.byKey(const Key('plan_form_save')));
    expect(find.byKey(const Key('plan_form_care')), findsOneWidget);
    await _tap(tester, find.byKey(const Key('plan_form_care_confirm')));
    final goal = (await (session as GoalStorage).goals.goal())!;
    expect(goal.runDays, {1, 2, 4, 6});
    final units = await (session as PlanStorage).plans.unitsBetween(
      _today,
      planFarFuture,
    );
    expect(units.any((u) => u.kind == PlanUnitKind.walkRun), isTrue);
  });

  testWidgets('Rennen: Änderung während der Einschätzung verwirft das '
      'Ergebnis, gespeichert wird der neu geprüfte Entwurf', (tester) async {
    final (session, clock) = await _empty();
    final pending = <Completer<GoalDraftCheck>>[];
    final c = _Checking(session, clock, (draft) {
      final done = Completer<GoalDraftCheck>();
      pending.add(done);
      return done.future;
    });
    await _pump(tester, session: session, clock: clock, controller: c);
    await _tap(tester, find.byKey(const Key('plan_create_goal')));
    await _tap(tester, find.byKey(const Key('plan_form_day_2')));
    await _enter(tester, 'plan_form_max_session', '45');
    await _tap(tester, find.text(de.planFormYes));
    await _tap(tester, find.byKey(const Key('plan_form_check')));
    // Noch in der Rechnung: ein weiterer Lauftag.
    await _tap(tester, find.byKey(const Key('plan_form_day_4')));
    const walk = GoalDraftCheck(
      assessment: GoalAssessment(
        feasibility: null,
        reason: FeasibilityReason.showRegularity,
      ),
      walkRun: false,
    );
    pending.single.complete(walk);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('plan_form_assessment')), findsNothing);
    expect(find.byKey(const Key('plan_form_save')), findsNothing);

    await _tap(tester, find.byKey(const Key('plan_form_check')));
    pending.last.complete(walk);
    await tester.pumpAndSettle();
    await _tap(tester, find.byKey(const Key('plan_form_save')));
    expect(c.saved.single.runDays, {2, 4});
  });

  testWidgets('Misslungene Einschätzung: Fehlertext, kein Speichern', (
    tester,
  ) async {
    final (session, clock) = await _empty();
    final c = _Checking(session, clock, (_) async => throw StateError('x'));
    await _pump(tester, session: session, clock: clock, controller: c);
    await _tap(tester, find.byKey(const Key('plan_create_goal')));
    await _tap(tester, find.byKey(const Key('plan_form_day_2')));
    await _enter(tester, 'plan_form_max_session', '45');
    await _tap(tester, find.text(de.planFormYes));
    await _tap(tester, find.byKey(const Key('plan_form_check')));
    expect(_error(tester), de.planFormAssessFailed);
    expect(find.byKey(const Key('plan_form_save')), findsNothing);
    expect(c.saved, isEmpty);
  });

  testWidgets('Zeitziel mit Referenz: Einschätzung aus der Grundlage', (
    tester,
  ) async {
    final (session, clock) = await _empty();
    final c = PlanController(
      session: session,
      clock: clock,
      // Aktuell 30:00 auf 5 km aus 6 Läufen; Ziel 29:50 ist eine kleine
      // Verbesserung.
      reader: _BasisReader(
        session,
        clock,
        const TimeGoalBasis(currentSeconds: 30 * 60, runsInWindow: 6),
      ),
    );
    await _pump(tester, session: session, clock: clock, controller: c);
    await _tap(tester, find.byKey(const Key('plan_create_goal')));
    await _tap(tester, find.text(de.planFormTypeTime));
    await _enter(tester, 'plan_form_minutes', '29');
    await _enter(tester, 'plan_form_seconds', '50');
    await _pickDay(tester, 28);
    await _tap(tester, find.byKey(const Key('plan_form_day_2')));
    await _tap(tester, find.byKey(const Key('plan_form_day_4')));
    await _enter(tester, 'plan_form_max_session', '45');
    await _tap(tester, find.text(de.planFormYes));
    await _tap(tester, find.byKey(const Key('plan_form_check')));
    expect(
      tester
          .widget<Text>(find.byKey(const Key('plan_form_assessment_main')))
          .data,
      de.planAssessFits,
    );
    expect(
      tester
          .widget<Text>(find.byKey(const Key('plan_form_assessment_basis')))
          .data,
      de.planAssessBasisTime,
    );
  });

  testWidgets('Regler: geänderter Wert wird gespeichert', (tester) async {
    final clock = FakeClock(_now);
    final session = await _withPlan(_goal(), clock);
    final c = _controller(session, clock);
    await _pump(tester, session: session, clock: clock, controller: c);
    await _tap(tester, find.byKey(const Key('plan_edit_goal')));
    final slider = find.byKey(const Key('plan_form_regulator'));
    await tester.ensureVisible(slider);
    tester.widget<Slider>(slider).onChanged!(6.2);
    await tester.pumpAndSettle();
    expect(tester.widget<Slider>(slider).value, 6);
    await _tap(tester, find.byKey(const Key('plan_form_check')));
    await _tap(tester, find.byKey(const Key('plan_form_save')));
    final goal = (await (session as GoalStorage).goals.goal())!;
    expect(goal.weeklyCapSeconds, 6 * 3600);
  });

  testWidgets('Regler unter der Zielspitze: Hinweis im Wortlaut', (
    tester,
  ) async {
    final (session, clock) = await _empty();
    final c = _controller(session, clock);
    await _pump(tester, session: session, clock: clock, controller: c);
    await _tap(tester, find.byKey(const Key('plan_create_goal')));
    await _tap(tester, find.text(de.planDistanceHalf));
    await _pickDay(tester, 28);
    await _tap(tester, find.byKey(const Key('plan_form_day_2')));
    await _tap(tester, find.byKey(const Key('plan_form_day_4')));
    await _tap(tester, find.byKey(const Key('plan_form_day_6')));
    await _enter(tester, 'plan_form_max_session', '120');
    await _tap(tester, find.text(de.planFormYes));
    final slider = find.byKey(const Key('plan_form_regulator'));
    await tester.ensureVisible(slider);
    tester.widget<Slider>(slider).onChanged!(1);
    await tester.pumpAndSettle();
    await _tap(tester, find.byKey(const Key('plan_form_check')));
    expect(
      tester
          .widget<Text>(find.byKey(const Key('plan_form_assessment_regulator')))
          .data,
      de.planAssessRegulator,
    );
  });

  testWidgets('Streckenziel ohne Datum: kein Text zum offenen Ziel', (
    tester,
  ) async {
    final (session, clock) = await _empty();
    final c = _controller(session, clock);
    await _pump(tester, session: session, clock: clock, controller: c);
    await _tap(tester, find.byKey(const Key('plan_create_goal')));
    await _tap(tester, find.byKey(const Key('plan_form_day_2')));
    await _enter(tester, 'plan_form_max_session', '45');
    await _tap(tester, find.text(de.planFormYes));
    await _tap(tester, find.byKey(const Key('plan_form_check')));
    expect(
      tester
          .widget<Text>(
            find.byKey(const Key('plan_form_assessment_regularity')),
          )
          .data,
      de.planFormAssessNoDate,
    );
  });

  testWidgets('Offenes Ziel: Einschätzung nennt das offene Ziel', (
    tester,
  ) async {
    final (session, clock) = await _empty();
    final c = _controller(session, clock);
    await _pump(tester, session: session, clock: clock, controller: c);
    await _tap(tester, find.byKey(const Key('plan_create_goal')));
    await _tap(tester, find.text(de.planFormTypeOpen));
    await _tap(tester, find.byKey(const Key('plan_form_day_2')));
    await _enter(tester, 'plan_form_max_session', '45');
    await _tap(tester, find.text(de.planFormYes));
    await _tap(tester, find.byKey(const Key('plan_form_check')));
    expect(find.byKey(const Key('plan_form_error')), findsNothing);
    expect(
      tester
          .widget<Text>(
            find.byKey(const Key('plan_form_assessment_regularity')),
          )
          .data,
      de.planFormAssessOpen,
    );
  });

  testWidgets('Ändern ohne Stand am Ziel und ohne Läufe: Einschätzen und '
      'Speichern gehen', (tester) async {
    final clock = FakeClock(_now);
    // Angelegt mit Stand aus Läufen: weder Wochenumfang noch 30 min.
    final session = await _withPlan(
      _goal(canRun30: ContinuousRun30.unknown),
      clock,
    );
    final stored = (await (session as GoalStorage).goals.goal())!;
    expect(stored.currentWeeklySeconds, isNull);
    expect(stored.canRun30, ContinuousRun30.unknown);
    final c = _controller(session, clock);
    await _pump(tester, session: session, clock: clock, controller: c);
    await _tap(tester, find.byKey(const Key('plan_edit_goal')));
    expect(find.byKey(const Key('plan_form_stand_runs')), findsNothing);
    await _tap(tester, find.byKey(const Key('plan_form_day_1')));
    await _tap(tester, find.byKey(const Key('plan_form_check')));
    expect(find.byKey(const Key('plan_form_error')), findsNothing);
    await _tap(tester, find.byKey(const Key('plan_form_save')));
    // Ohne Stand beginnt der Plan mit Geh-Lauf (PAR-115): erst bestätigen.
    expect(find.byKey(const Key('plan_form_care')), findsOneWidget);
    await _tap(tester, find.byKey(const Key('plan_form_care_confirm')));
    final goal = (await (session as GoalStorage).goals.goal())!;
    expect(goal.runDays, {1, 2, 4, 6});
    final history = await (session as PlanStorage).plans.history();
    expect(history.last.trigger, PlanTrigger.goalChange);
  });

  testWidgets('Fehler beim Speichern bleibt im Formular sichtbar', (
    tester,
  ) async {
    final (session, clock) = await _empty();
    await _pump(
      tester,
      session: session,
      clock: clock,
      controller: _Scripted(session, clock, PlanActionResult.failed),
    );
    await fillAndSave(tester);
    expect(find.byKey(const Key('plan_form')), findsOneWidget);
    expect(_error(tester), de.planFormSaveFailed);
  });

  testWidgets('Nur unbrauchbare Referenz gespeichert: ungueltig mit Grund', (
    tester,
  ) async {
    // Importiert (Speicher-Prüfung umgangen): 10 km in 10 Minuten, Tempo
    // außerhalb der Spanne.
    final storage = FakeStorage();
    final session = await storage.open(_key);
    final clock = FakeClock(_now);
    storage.data.references.add(
      StoredReference(
        id: 1,
        reference: ReferencePerformance(
          kind: ReferenceKind.race,
          distanceMeters: 10000,
          seconds: 10 * 60,
          date: DateTime.utc(2026, 10, 4),
          createdAt: _now,
        ),
      ),
    );
    final c = _controller(session, clock);
    await _pump(tester, session: session, clock: clock, controller: c);
    await _tap(tester, find.byKey(const Key('plan_create_goal')));
    final text = tester
        .widget<Text>(find.byKey(const Key('plan_form_reference')))
        .data!;
    expect(text, isNot(contains('Noch keine')));
    expect(text, contains('ungültig'));
    expect(text, contains('wird nicht verwendet'));
  });

  testWidgets('Bisherige Wettkampfzeit steht als Referenz im Formular', (
    tester,
  ) async {
    final (session, clock) = await _empty();
    await (session as PredictionStorage).prediction.addReference(
      ReferencePerformance(
        kind: ReferenceKind.race,
        distanceMeters: 10000,
        seconds: 52 * 60 + 30,
        date: DateTime.utc(2026, 10, 4),
        createdAt: _now,
      ),
    );
    final c = _controller(session, clock);
    await _pump(tester, session: session, clock: clock, controller: c);
    await _tap(tester, find.byKey(const Key('plan_create_goal')));
    final text = tester
        .widget<Text>(find.byKey(const Key('plan_form_reference')))
        .data!;
    expect(text, startsWith('Gilt: 10'));
    expect(
      text,
      contains(DateFormat.yMMMd('de').format(DateTime(2026, 10, 4))),
    );
    expect(find.byKey(const Key('plan_form_reference_add')), findsOneWidget);
  });

  for (final brightness in Brightness.values) {
    testWidgets('englisch, ${brightness.name}: Formular und Einstieg', (
      tester,
    ) async {
      final clock = FakeClock(_now);
      final session = await _withPlan(_goal(), clock);
      final c = _controller(session, clock);
      await _pump(
        tester,
        session: session,
        clock: clock,
        controller: c,
        locale: 'en',
        brightness: brightness,
      );
      expect(find.text(en.planEditGoal), findsOneWidget);
      await _tap(tester, find.byKey(const Key('plan_edit_goal')));
      expect(find.text(en.planFormTitleEdit), findsOneWidget);
      expect(find.text(en.planFormRunDays), findsOneWidget);
      expect(find.text(en.planFormRegulatorRelaxed), findsOneWidget);
      expect(find.text(en.planFormHard), findsOneWidget);
      expect(find.text(en.planFormReferences), findsOneWidget);
      await _tap(tester, find.byKey(const Key('plan_form_check')));
      expect(find.text(en.planFormAssessment.toUpperCase()), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('deutsch, dunkel: Anlegen ohne Überlauf', (tester) async {
    final (session, clock) = await _empty();
    final c = _controller(session, clock);
    await _pump(
      tester,
      session: session,
      clock: clock,
      controller: c,
      brightness: Brightness.dark,
    );
    await _tap(tester, find.byKey(const Key('plan_create_goal')));
    await _tap(tester, find.text(de.planFormTypeTime));
    expect(find.byKey(const Key('plan_form_hours')), findsOneWidget);
    expect(
      tester
          .widget<SwitchListTile>(find.byKey(const Key('plan_form_hard')))
          .value,
      isTrue, // PAR-198: Standard an bei Zeitzielen
    );
    expect(tester.takeException(), isNull);
  });
}
