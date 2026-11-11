// WP18 Auftrag 3: Angaben zum Lauf in Zusammenfassung und Detail (FR-0038,
// FR-0095, FR-0096, PAR-105). Synthetische Daten.

import 'dart:async';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/history/run_detail_page.dart';
import 'package:running_app/features/settings/unit_format.dart';
import 'package:running_app/features/summary/run_summary_body.dart';
import 'package:running_app/features/summary/run_summary_page.dart';
import 'package:running_app/features/summary/subjective_section.dart';
import 'package:running_app/offload_scope.dart';
import 'package:running_app/l10n/app_localizations.dart';
import 'package:running_app/ui/ui.dart';

import 'history_summary_test.dart' show started;
import 'run_detail_test.dart' show seedDetailRun;
import 'app_harness.dart';

/// Wortlaut nach PAR-105 (`docs/phase-2-3-rules.md`), unabhängig von der arb.
const _rpeDe = [
  'In Ruhe',
  'Kaum Anstrengung, wie gemütliches Gehen',
  'Locker, Reden ohne Mühe',
  'Locker, aber spürbar, Reden ohne Pause',
  'Fordert etwas, ganze Sätze gehen noch',
  'Anstrengend, Gespräch schwer',
  'Deutlich anstrengend, nur noch kurze Sätze',
  'Schwer durchzuhalten, nur noch wenige Wörter',
  'Kaum durchzuhalten, nur noch einzelne Wörter',
  'Fast am Limit, Reden geht nicht mehr',
  'Maximal, mehr geht nicht',
];
const _rpeEn = [
  'At rest',
  'Barely any effort, like a gentle walk',
  'Relaxed, talking takes no effort',
  'Relaxed but noticeable, you can talk without pausing',
  'Some work, full sentences are still fine',
  'Tiring, conversation is difficult',
  'Clearly tiring, short sentences only',
  'Tough to keep up, only a few words',
  'You can barely keep going, single words only',
  'Almost at your limit, no talking',
  'All out, nothing left',
];
const _moodDe = ['sehr schlecht', 'schlecht', 'mittel', 'gut', 'sehr gut'];
const _moodEn = ['very bad', 'bad', 'okay', 'good', 'very good'];

/// Sitzung, deren Lesen der Angaben sich ausfallen lässt.
class _FlakySession implements StorageSession {
  _FlakySession(this.s);
  final StorageSession s;
  bool failRead = false;

  /// Hält das Lesen an, bis der Completer erfüllt ist.
  Completer<void>? gate;
  @override
  RunSubjectiveStore get subjective => _FlakySubjective(this, s.subjective);
  @override
  SettingsStore get settings => s.settings;
  @override
  ProfileStore get profile => s.profile;
  @override
  RunStore get runs => s.runs;
  @override
  RunMarkerStore get markers => s.markers;
  @override
  RawDataStore get rawData => s.rawData;
  @override
  PreprocessingStore get preprocessing => s.preprocessing;
  @override
  RatedSectionStore get sections => s.sections;
  @override
  ComputedValueStore get values => s.values;
  @override
  KnownDeviceStore get devices => s.devices;
  @override
  ConsentStore get consents => s.consents;
  @override
  ManualTrainingStore get manualTrainings => s.manualTrainings;
  @override
  Future<void> deleteRun(int runId) => s.deleteRun(runId);
  @override
  Future<void> deleteAll() => s.deleteAll();
  @override
  Future<void> close() => s.close();
}

class _FlakySubjective implements RunSubjectiveStore {
  _FlakySubjective(this.o, this.inner);
  final _FlakySession o;
  final RunSubjectiveStore inner;
  @override
  Future<StoredRunSubjective?> read(int runId) {
    if (o.failRead) {
      return Future.error(const StorageException(StorageFailure.failed));
    }
    final gate = o.gate;
    return gate == null
        ? inner.read(runId)
        : gate.future.then((_) => inner.read(runId));
  }

  @override
  Future<Map<int, StoredRunSubjective>> readAll() => inner.readAll();
  @override
  Future<void> save(int runId, RunSubjective subjective, {SrpeLoad? srpe}) =>
      inner.save(runId, subjective, srpe: srpe);
  @override
  Future<bool> setSrpe(
    int runId,
    SrpeLoad? srpe, {
    required int? expectedRpe,
  }) => inner.setSrpe(runId, srpe, expectedRpe: expectedRpe);
}

class _World {
  _World(this.session, this.runId)
    : service = SubjectiveService(
        session: session,
        clock: FakeClock(DateTime.utc(2030, 1, 2)),
      );
  final StorageSession session;
  final int runId;
  final SubjectiveService service;

  static Future<_World> create({Duration? moving}) async {
    final session = await FakeStorage().open(Uint8List(32));
    final run = await session.runs.create(startedAt: DateTime.utc(2030, 1, 1));
    if (moving != null) {
      await session.preprocessing.replace(
        run.id,
        StoredPreprocessing(
          summary: PreprocessingSummary(
            method: 'preprocessing',
            methodVersion: 1,
            parameterVersion: 2,
            computedAt: DateTime.utc(2030, 1, 1, 9),
            totalTime: moving + const Duration(minutes: 5),
            movingTime: moving,
          ),
        ),
      );
    }
    return _World(session, run.id);
  }

  Future<RunSubjective?> stored() async =>
      (await session.subjective.read(runId))?.subjective;
}

Widget _app(
  Widget Function(BuildContext) body, {
  String lang = 'de',
  bool dark = false,
  double scale = 1,
  Size size = const Size(360, 640),
}) => MaterialApp(
  theme: dark ? RamuriTheme.dark : RamuriTheme.light,
  locale: Locale(lang),
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: MediaQuery(
    data: MediaQueryData(size: size, textScaler: TextScaler.linear(scale)),
    child: Scaffold(
      body: Builder(
        builder: (context) => SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: body(context),
        ),
      ),
    ),
  ),
);

Future<void> _pump(
  WidgetTester tester,
  _World w, {
  String lang = 'de',
  bool dark = false,
  double scale = 1,
  Size size = const Size(360, 640),
  bool srpe = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    _app(
      (_) =>
          SubjectiveSection(service: w.service, runId: w.runId, showSrpe: srpe),
      lang: lang,
      dark: dark,
      scale: scale,
      size: size,
    ),
  );
  await tester.pumpAndSettle();
}

String _t(WidgetTester tester, String k) => tester.widget<Text>(key(k)).data!;

void main() {
  for (final (lang, words) in [('de', _rpeDe), ('en', _rpeEn)]) {
    testWidgets('RPE-Wortlaut aller 11 Stufen ($lang) nach PAR-105', (
      tester,
    ) async {
      final w = await _World.create();
      await _pump(tester, w, lang: lang);
      for (var n = 0; n <= 10; n++) {
        await tapKey(tester, 'subjective_rpe_$n');
        expect(_t(tester, 'subjective_rpe_label'), '$n · ${words[n]}');
        expect((await w.stored())!.rpe, n);
      }
      expect(words, hasLength(11));
    });
  }

  for (final (lang, words) in [('de', _moodDe), ('en', _moodEn)]) {
    testWidgets('Befinden: 5 Stufen ($lang), Stufe n speichert n', (
      tester,
    ) async {
      final w = await _World.create();
      await _pump(tester, w, lang: lang);
      expect(key('subjective_wellbeing_0'), findsNothing);
      expect(key('subjective_wellbeing_6'), findsNothing);
      for (var n = 1; n <= 5; n++) {
        expect(
          find.descendant(
            of: key('subjective_wellbeing_$n'),
            matching: find.text(words[n - 1]),
          ),
          findsOneWidget,
        );
        await tapKey(tester, 'subjective_wellbeing_$n');
        expect((await w.stored())!.wellbeing, n);
      }
    });
  }

  testWidgets('nichts vorausgewählt; "Fertig" ohne Angaben speichert nichts', (
    tester,
  ) async {
    final w = await _World.create();
    final handle = tester.ensureSemantics();
    await _pump(tester, w);
    expect(_t(tester, 'subjective_rpe_label'), 'Keine Angabe');
    for (var n = 0; n <= 10; n++) {
      expect(
        tester.getSemantics(key('subjective_rpe_$n')),
        isSemantics(isButton: true, hasSelectedState: true, isSelected: false),
        reason: 'RPE $n',
      );
    }
    for (var n = 1; n <= 5; n++) {
      expect(
        tester.getSemantics(key('subjective_wellbeing_$n')),
        isSemantics(isButton: true, hasSelectedState: true, isSelected: false),
      );
    }
    expect(key('subjective_warn_question'), findsNothing);
    // Schließen wie mit "Fertig": nichts wird geschrieben.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(await w.session.subjective.read(w.runId), isNull);
    expect(await w.session.subjective.readAll(), isEmpty);
    handle.dispose();
  });

  testWidgets('Auswahl, Abwahl, Änderung landen im Speicher; Semantik', (
    tester,
  ) async {
    final w = await _World.create();
    final handle = tester.ensureSemantics();
    await _pump(tester, w);
    await tapKey(tester, 'subjective_rpe_4');
    expect((await w.stored())!.rpe, 4);
    expect(
      tester.getSemantics(key('subjective_rpe_4')),
      isSemantics(isButton: true, hasSelectedState: true, isSelected: true),
    );
    await tapKey(tester, 'subjective_rpe_7');
    expect((await w.stored())!.rpe, 7);
    expect(
      tester.getSemantics(key('subjective_rpe_4')),
      isSemantics(isButton: true, hasSelectedState: true, isSelected: false),
    );
    await tapKey(tester, 'subjective_wellbeing_4');
    await tapKey(tester, 'subjective_wellbeing_2');
    expect((await w.stored())!.wellbeing, 2);
    expect((await w.stored())!.rpe, 7);
    // Erneutes Tippen hebt auf.
    await tapKey(tester, 'subjective_rpe_7');
    expect((await w.stored())!.rpe, isNull);
    expect((await w.stored())!.wellbeing, 2);
    await tapKey(tester, 'subjective_wellbeing_2');
    expect(await w.session.subjective.read(w.runId), isNull);
    handle.dispose();
  });

  testWidgets('Warnsignal-Frage nur bei Beschwerden, Antwort gespeichert', (
    tester,
  ) async {
    final w = await _World.create();
    await _pump(tester, w);
    expect(key('subjective_warn_question'), findsNothing);
    await tapKey(tester, 'subjective_complaints_button');
    // Textfeld offen, aber noch nichts getippt: keine Frage.
    expect(key('subjective_complaints'), findsOneWidget);
    expect(key('subjective_warn_question'), findsNothing);
    await tester.enterText(key('subjective_complaints'), 'Knie links');
    await tester.pumpAndSettle();
    expect(key('subjective_warn_question'), findsOneWidget);
    expect(find.text('Als Warnsignal melden?'), findsOneWidget);
    await tapKey(tester, 'subjective_warn_yes');
    var s = (await w.stored())!;
    expect(s.complaints, 'Knie links');
    expect(s.warningAnswer, WarningAnswer.yes);
    await tapKey(tester, 'subjective_warn_no');
    expect((await w.stored())!.warningAnswer, WarningAnswer.no);
    await tapKey(tester, 'subjective_warn_no');
    expect((await w.stored())!.warningAnswer, isNull);
    await tapKey(tester, 'subjective_warn_yes');
    // Beschwerden entfernt: Frage weg, Antwort zurückgesetzt.
    await tester.enterText(key('subjective_complaints'), '');
    await tester.pumpAndSettle();
    expect(key('subjective_warn_question'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(await w.stored(), isNull);
  });

  testWidgets('Beschwerden ohne Antwort bleiben ohne Antwort gespeichert', (
    tester,
  ) async {
    final w = await _World.create();
    await _pump(tester, w);
    await tapKey(tester, 'subjective_complaints_button');
    await tester.enterText(key('subjective_complaints'), 'Wade');
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    final s = (await w.stored())!;
    expect(s.complaints, 'Wade');
    expect(s.warningAnswer, isNull);
  });

  testWidgets(
    'sRPE-Grundlage zeigt die Bewegungszeit mit Sekunden, nachrechenbar',
    (tester) async {
      final w = await _World.create(moving: const Duration(seconds: 96));
      await _pump(tester, w, srpe: true);
      await tapKey(tester, 'subjective_rpe_7');
      // 96 s = 1,6 min; 1,6 * 7 = 11,2 -> 11 Punkte, Dauer nicht auf 2 min gerundet.
      expect(_t(tester, 'subjective_srpe_value'), '11 Punkte');
      expect(
        _t(tester, 'subjective_srpe_basis'),
        'Grundlage: Dauer 1:36 · Anstrengung 7',
      );
    },
  );

  testWidgets('sRPE im Detail: Wert nach RPE und Bewegungszeit, getrennt', (
    tester,
  ) async {
    final w = await _World.create(moving: const Duration(minutes: 45));
    await _pump(tester, w, srpe: true);
    // Ohne RPE kein Wert und keine 0.
    expect(key('subjective_srpe_none'), findsOneWidget);
    expect(key('subjective_srpe_value'), findsNothing);
    expect(find.textContaining('0 Punkte'), findsNothing);
    await tapKey(tester, 'subjective_rpe_5');
    expect(_t(tester, 'subjective_srpe_value'), '225 Punkte');
    expect(
      _t(tester, 'subjective_srpe_basis'),
      'Grundlage: Dauer 45:00 · Anstrengung 5',
    );
    expect(find.textContaining('Schätzung'), findsOneWidget);
    // Das Ergebnis folgt der Angabe und steht nicht bei den Laufwerten (TRIMP).
    await tapKey(tester, 'subjective_rpe_6');
    expect(_t(tester, 'subjective_srpe_value'), '270 Punkte');
    expect((await w.session.subjective.read(w.runId))!.srpe!.points, 270);
    await tapKey(tester, 'subjective_rpe_6');
    expect(key('subjective_srpe_value'), findsNothing);
    expect(key('subjective_srpe_none'), findsOneWidget);
  });

  testWidgets('sRPE ohne Bewegungszeit: kein Wert', (tester) async {
    final w = await _World.create();
    await _pump(tester, w, srpe: true);
    await tapKey(tester, 'subjective_rpe_5');
    expect(key('subjective_srpe_value'), findsNothing);
    expect(key('subjective_srpe_none'), findsOneWidget);
    expect((await w.stored())!.rpe, 5);
  });

  testWidgets('Detail: gespeicherte Angaben werden geladen und sind änderbar', (
    tester,
  ) async {
    final w = await _World.create(moving: const Duration(minutes: 30));
    await w.service.save(
      w.runId,
      RunSubjective(rpe: 3, wellbeing: 5, complaints: 'Fuß', note: 'ok'),
    );
    await _pump(tester, w, srpe: true);
    expect(_t(tester, 'subjective_rpe_label'), '3 · ${_rpeDe[3]}');
    expect(_t(tester, 'subjective_srpe_value'), '90 Punkte');
    expect(key('subjective_warn_question'), findsOneWidget);
    expect(
      tester.widget<TextField>(key('subjective_note')).controller!.text,
      'ok',
    );
    await tapKey(tester, 'subjective_rpe_8');
    final s = (await w.stored())!;
    expect((s.rpe, s.wellbeing, s.complaints, s.note), (8, 5, 'Fuß', 'ok'));
  });

  // Review 1, Befund 2: Zusammenfassung -> Details -> zurück. Die
  // Zusammenfassung darf weder den alten Stand zeigen noch schreiben.
  testWidgets(
    'Detail ändert RPE, zurück: Zusammenfassung zeigt und behält es',
    (tester) async {
      final w = await _World.create(moving: const Duration(minutes: 30));
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _app(
          (context) => Column(
            children: [
              SubjectiveSection(service: w.service, runId: w.runId),
              FilledButton(
                key: const Key('details'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => Scaffold(
                      body: SingleChildScrollView(
                        child: SubjectiveSection(
                          service: w.service,
                          runId: w.runId,
                          showSrpe: true,
                        ),
                      ),
                    ),
                  ),
                ),
                child: const Text('Details'),
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tapKey(tester, 'details');
      await tapKey(tester, 'subjective_rpe_6');
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();
      // Der Stand der Zusammenfassung ist neu geladen.
      expect(_t(tester, 'subjective_rpe_label'), '6 · ${_rpeDe[6]}');
      await tapKey(tester, 'subjective_wellbeing_4');
      await tester.enterText(key('subjective_note'), 'Beine frisch');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      final s = (await w.stored())!;
      expect((s.rpe, s.wellbeing, s.note), (6, 4, 'Beine frisch'));
      expect((await w.session.subjective.read(w.runId))!.srpe!.points, 180);
    },
  );

  // Review 2, Soll 4: Zusammenfassung -> Details -> zurück; das Neuladen wird
  // angehalten. Zurück baut eine eigene Sitzung mit angehaltenem Lesen auf.
  Future<({_FlakySession session, SubjectiveService service, int runId})>
  reloadWorld(WidgetTester tester, {String? note}) async {
    final base = await FakeStorage().open(Uint8List(32));
    final session = _FlakySession(base);
    final run = await base.runs.create(startedAt: DateTime.utc(2030, 1, 1));
    final service = SubjectiveService(
      session: session,
      clock: FakeClock(DateTime.utc(2030, 1, 2)),
    );
    if (note != null) await service.save(run.id, RunSubjective(note: note));
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _app(
        (context) => Column(
          children: [
            SubjectiveSection(service: service, runId: run.id),
            FilledButton(
              key: const Key('details'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const Scaffold(body: Text('Detail')),
                ),
              ),
              child: const Text('Details'),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (session: session, service: service, runId: run.id);
  }

  testWidgets(
    'Tippen während des Neuladens: Eingabe bleibt, wird gespeichert',
    (tester) async {
      final w = await reloadWorld(tester, note: 'alt');
      await tapKey(tester, 'details');
      w.session.gate = Completer<void>();
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();
      // Das Neuladen hängt; die Notiz wird getippt.
      await tester.enterText(key('subjective_note'), 'neu getippt');
      final gate = w.session.gate!;
      w.session.gate = null;
      gate.complete();
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(key('subjective_note')).controller!.text,
        'neu getippt',
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      expect(
        (await w.session.subjective.read(w.runId))!.subjective.note,
        'neu getippt',
      );
    },
  );

  testWidgets('Neuladen mit gleichem Text lässt den Cursor stehen', (
    tester,
  ) async {
    final w = await reloadWorld(tester, note: 'abcdef');
    final controller = tester
        .widget<TextField>(key('subjective_note'))
        .controller!;
    controller.selection = const TextSelection.collapsed(offset: 2);
    await tapKey(tester, 'details');
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();
    expect(w.session.gate, isNull);
    expect(controller.text, 'abcdef');
    expect(controller.selection, const TextSelection.collapsed(offset: 2));
  });

  // Auch ohne Neuladen schreibt eine Ansicht nur das geänderte Feld.
  testWidgets('veralteter Stand überschreibt fremde Änderung nicht', (
    tester,
  ) async {
    final w = await _World.create();
    await _pump(tester, w);
    await w.service.save(w.runId, RunSubjective(rpe: 7, note: 'anderswo'));
    await tapKey(tester, 'subjective_wellbeing_2');
    final s = (await w.stored())!;
    expect((s.rpe, s.wellbeing, s.note), (7, 2, 'anderswo'));
  });

  // Review 1, Befund 3: Lesefehler ist fail-closed.
  testWidgets(
    'Lesefehler: keine Felder, nichts wird überschrieben, Wiederholen',
    (tester) async {
      final base = await FakeStorage().open(Uint8List(32));
      final session = _FlakySession(base);
      final run = await base.runs.create(startedAt: DateTime.utc(2030, 1, 1));
      final service = SubjectiveService(
        session: session,
        clock: FakeClock(DateTime.utc(2030, 1, 2)),
      );
      final saved = RunSubjective(
        rpe: 4,
        wellbeing: 3,
        complaints: 'Knie',
        note: 'ALT',
      );
      await service.save(run.id, saved);
      session.failRead = true;
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _app((_) => SubjectiveSection(service: service, runId: run.id)),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Die Angaben konnten nicht geladen werden.'),
        findsOneWidget,
      );
      expect(key('subjective_save_failed'), findsNothing);
      expect(key('subjective_rpe_5'), findsNothing);
      expect(key('subjective_note'), findsNothing);
      // Erneut versuchen, weiter kaputt: bleibt gesperrt.
      await tapKey(tester, 'subjective_load_retry');
      expect(key('subjective_load_failed'), findsOneWidget);
      expect(key('subjective_rpe_5'), findsNothing);
      expect((await base.subjective.read(run.id))!.subjective, saved);
      // Lesen geht wieder: Felder mit den gespeicherten Werten.
      session.failRead = false;
      await tapKey(tester, 'subjective_load_retry');
      expect(key('subjective_load_failed'), findsNothing);
      expect(_t(tester, 'subjective_rpe_label'), '4 · ${_rpeDe[4]}');
      expect(
        tester.widget<TextField>(key('subjective_note')).controller!.text,
        'ALT',
      );
    },
  );

  testWidgets('Notiz geht nicht verloren: Tippen, sofort "Fertig"', (
    tester,
  ) async {
    final w = await _World.create();
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _app(
        (context) => Column(
          children: [
            SubjectiveSection(service: w.service, runId: w.runId),
            FilledButton(
              key: const Key('done'),
              onPressed: () => Navigator.of(context).pushReplacement(
                MaterialPageRoute<void>(builder: (_) => const SizedBox()),
              ),
              child: const Text('Fertig'),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(key('subjective_note'), 'Beine frisch');
    // Kein Fokuswechsel vorher: gespeichert wird beim Schließen.
    await tapKey(tester, 'done');
    expect((await w.stored())!.note, 'Beine frisch');
  });

  testWidgets('Notiz wird beim Verlassen des Felds gespeichert', (
    tester,
  ) async {
    final w = await _World.create();
    await _pump(tester, w);
    await tester.enterText(key('subjective_note'), 'abc');
    expect(await w.stored(), isNull);
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    expect((await w.stored())!.note, 'abc');
  });

  for (final dark in [false, true]) {
    for (final size in [const Size(360, 640), const Size(320, 640)]) {
      testWidgets('Schriftfaktor 1,3 bei ${size.width.toInt()} dp, '
          '${dark ? 'dunkel' : 'hell'}: kein Überlauf, Tasten ab 48 dp', (
        tester,
      ) async {
        final w = await _World.create(moving: const Duration(minutes: 45));
        await w.service.save(
          w.runId,
          RunSubjective(
            rpe: 5,
            wellbeing: 1,
            complaints: 'Knie links, seit gestern',
            warningAnswer: WarningAnswer.yes,
            note: 'Beine fühlten sich frisch an',
          ),
        );
        await _pump(tester, w, dark: dark, scale: 1.3, size: size, srpe: true);
        expect(tester.takeException(), isNull);
        final keys = [
          for (var n = 0; n <= 10; n++) 'subjective_rpe_$n',
          for (var n = 1; n <= 5; n++) 'subjective_wellbeing_$n',
          'subjective_complaints_button',
          'subjective_warn_yes',
          'subjective_warn_no',
        ];
        for (final k in keys) {
          final box = tester.getSize(key(k));
          expect(box.height, greaterThanOrEqualTo(48), reason: k);
          expect(box.width, greaterThanOrEqualTo(48), reason: k);
        }
        // Alles liegt innerhalb der Breite.
        final right = key('subjective_section');
        expect(tester.getRect(right).right, lessThanOrEqualTo(size.width));
        expect(find.byType(Scrollable), findsWidgets);
      });
    }
  }

  const km = UnitFormatter(
    unit: DistanceUnit.kilometers,
    languageCode: 'de',
    distanceLabel: 'km',
    paceLabel: 'min/km',
    elevationLabel: 'm',
  );

  for (final detail in [false, true]) {
    testWidgets(
      'eingebaut in ${detail ? 'Detail (mit sRPE)' : 'Zusammenfassung (ohne sRPE)'}',
      (tester) async {
        final d = await started(tester);
        final id = await seedDetailRun(d.session, DateTime.utc(2030, 1, 1, 8));
        final service = SubjectiveService(session: d.session, clock: d.clock);
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            theme: RamuriTheme.light,
            locale: const Locale('de'),
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: OffloadScope(
              offload: inlineOffload,
              child: Scaffold(
                body: SingleChildScrollView(
                  child: RunSummaryBody(
                    session: d.session,
                    clock: d.clock,
                    runId: id,
                    splitUnitMeters: detail ? kilometerMeters : null,
                    fallback: () => const [],
                    contentBuilder: (context, summary, data, splits) => detail
                        ? RunDetailPage(
                            summary: summary,
                            detail: data,
                            splits: splits,
                            formatter: km,
                            session: d.session,
                            runId: id,
                            subjective: service,
                          )
                        : RunSummaryPage(
                            summary: summary,
                            detail: data,
                            formatter: km,
                            session: d.session,
                            runId: id,
                            subjective: service,
                          ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(key('subjective_section'), findsOneWidget);
        expect(key('subjective_srpe'), detail ? findsOneWidget : findsNothing);
        await tapKey(tester, 'subjective_rpe_5');
        expect((await d.session.subjective.read(id))!.subjective.rpe, 5);
        if (detail) {
          // 10 min Bewegung, RPE 5: 50 Punkte, getrennt von TRIMP.
          expect(_t(tester, 'subjective_srpe_value'), '50 Punkte');
        }
      },
    );
  }
}
