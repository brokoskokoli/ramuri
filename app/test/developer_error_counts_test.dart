// FR-0223: Fehlerzähler in den Entwicklereinstellungen – nur im
// Entwicklermodus, sortiert nach Anzahl, leerer Zustand, Zurücksetzen mit
// Rückfrage, „Alles löschen“ leert die Zähler (SEC-0004).

import 'package:core/core.dart';
import 'package:core/fakes/fake_storage_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/error_counter.dart';
import 'package:running_app/features/export/file_handoff_scope.dart';
import 'package:running_app/features/home/overview_screen.dart';
import 'package:running_app/features/recalculation/recalculation_controller.dart';
import 'package:running_app/features/settings/about_screen.dart';
import 'package:running_app/features/settings/developer_settings_screen.dart';
import 'package:running_app/l10n/app_localizations.dart';
import 'package:running_app/ui/ui.dart';

import 'app_harness.dart';

/// Gespeicherte Zähler (synthetisch): Anzahl 2, 7, 4 in dieser Reihenfolge.
const _entries = [
  ErrorCount(
    type: 'StateError',
    place: 'package:running_app/features/a.dart',
    count: 2,
    firstDay: '2026-11-02',
    lastDay: '2026-11-03',
  ),
  ErrorCount(
    type: 'FormatException',
    place: 'package:core/src/b.dart',
    count: 7,
    firstDay: '2026-11-01',
    lastDay: '2026-11-20',
  ),
  ErrorCount(
    type: 'RangeError',
    place: unknownErrorPlace,
    count: 4,
    firstDay: '2026-11-05',
    lastDay: '2026-11-05',
  ),
];

/// Plattformkanal mit einer anderen Version: Reicht ein Bildschirm die
/// übergebene Versionsquelle nicht weiter, steht diese im Export.
void _platformVersion() {
  const channel = MethodChannel('ramuri/permissions');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
    channel,
    (call) async => call.method == 'appVersion' ? '0.0.0 (0)' : null,
  );
  addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
}

class _Setup {
  _Setup(this.storage, this.errors, this.mode, this.handoff);
  final FakeStorage storage;
  final ErrorCounter errors;
  final DeveloperModeStore mode;
  final FakeFileHandoff handoff;

  String? get stored => storage.data.settings[SettingKeys.errorCounts];
}

Future<_Setup> _setup({
  required bool developer,
  List<ErrorCount> entries = _entries,
}) async {
  final storage = FakeStorage();
  final session = await storage.open(Uint8List(32));
  final clock = FakeClock(DateTime.utc(2026, 11, 24));
  final mode = SettingsDeveloperModeStore(session.settings, clock);
  if (developer) await mode.set(true);
  if (entries.isNotEmpty) {
    storage.data.settings[SettingKeys.errorCounts] = encodeErrorCounts(entries);
  }
  final errors = ErrorCounter()..attach(FakeSettingsStore(storage.data), clock);
  return _Setup(storage, errors, mode, FakeFileHandoff());
}

Widget _app(_Setup s, Widget home, {String locale = 'de'}) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: Locale(locale),
  theme: RamuriTheme.light,
  builder: (context, child) => FileHandoffScope(
    handoff: s.handoff,
    child: ErrorCounterScope(errors: s.errors, child: child!),
  ),
  home: home,
);

Future<void> _pump(
  WidgetTester tester,
  _Setup s, {
  String locale = 'de',
}) async {
  tester.view.physicalSize = const Size(800, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    _app(
      s,
      DeveloperSettingsScreen(
        developerMode: s.mode,
        appVersion: () async => '0.1.0 (12)',
        clock: () => DateTime(2026, 11, 24),
      ),
      locale: locale,
    ),
  );
  await tester.pumpAndSettle();
}

/// Typen der Einträge in der angezeigten Reihenfolge.
List<String> _shownTypes(WidgetTester tester) {
  final out = <String>[];
  for (var i = 0; ; i++) {
    final f = find.byKey(Key('dev_errors_entry_$i'));
    if (f.evaluate().isEmpty) return out;
    final texts = tester
        .widgetList<Text>(find.descendant(of: f, matching: find.byType(Text)))
        .map((t) => t.data)
        .toList();
    out.add(texts.first!);
  }
}

void main() {
  testWidgets('ohne Entwicklermodus weder „Fehler“ noch „Diagnose teilen“', (
    tester,
  ) async {
    final s = await _setup(developer: false);
    await _pump(tester, s);
    expect(find.byKey(const Key('dev_errors_card')), findsNothing);
    expect(find.text('Fehler'), findsNothing);
    expect(find.text('Diagnose teilen'), findsNothing);
    expect(find.text('StateError'), findsNothing);
  });

  testWidgets('mit Entwicklermodus: Liste nach Anzahl absteigend, je Eintrag '
      'Typ, Ort, Anzahl, erster und letzter Tag', (tester) async {
    final s = await _setup(developer: true);
    await _pump(tester, s);
    expect(find.byKey(const Key('dev_errors_card')), findsOneWidget);
    expect(find.text('Fehler'), findsOneWidget);
    expect(find.text('Diagnose teilen'), findsOneWidget);
    expect(find.text('Zähler zurücksetzen'), findsOneWidget);
    expect(_shownTypes(tester), [
      'FormatException',
      'RangeError',
      'StateError',
    ]);
    expect(find.text('package:core/src/b.dart'), findsOneWidget);
    expect(find.text(unknownErrorPlace), findsOneWidget);
    expect(
      find.text('7× · erstmals 2026-11-01 · zuletzt 2026-11-20'),
      findsOneWidget,
    );
    expect(
      find.text('2× · erstmals 2026-11-02 · zuletzt 2026-11-03'),
      findsOneWidget,
    );
    expect(find.text('Keine Fehler gezählt.'), findsNothing);
  });

  testWidgets('Eintrag ohne Tage (ältere Fassung) zeigt „–“', (tester) async {
    final s = await _setup(
      developer: true,
      entries: const [ErrorCount(type: 'StateError', place: 'p', count: 1)],
    );
    await _pump(tester, s);
    expect(find.text('1× · erstmals – · zuletzt –'), findsOneWidget);
  });

  testWidgets('leer: „Keine Fehler gezählt.“', (tester) async {
    final s = await _setup(developer: true, entries: const []);
    await _pump(tester, s);
    expect(find.text('Keine Fehler gezählt.'), findsOneWidget);
    expect(find.byKey(const Key('dev_errors_entry_0')), findsNothing);
  });

  testWidgets('Englisch', (tester) async {
    final s = await _setup(developer: true);
    await _pump(tester, s, locale: 'en');
    expect(find.text('Errors'), findsOneWidget);
    expect(find.text('Share diagnostics'), findsOneWidget);
    expect(find.text('Reset counts'), findsOneWidget);
    expect(
      find.text('7× · first 2026-11-01 · last 2026-11-20'),
      findsOneWidget,
    );
    final empty = await _setup(developer: true, entries: const []);
    await tester.pumpWidget(const SizedBox());
    await _pump(tester, empty, locale: 'en');
    expect(find.text('No errors counted.'), findsOneWidget);
  });

  testWidgets('gespeicherter Stand nicht lesbar: Hinweis statt Liste', (
    tester,
  ) async {
    final s = await _setup(developer: true);
    s.errors.attach(_FailingSettings(), FakeClock(DateTime.utc(2026)));
    await _pump(tester, s);
    expect(
      find.text('Die Fehlerzähler konnten nicht geladen werden.'),
      findsOneWidget,
    );
    expect(find.text('Keine Fehler gezählt.'), findsNothing);
  });

  testWidgets('Zähler zurücksetzen: Abbrechen ändert nichts', (tester) async {
    final s = await _setup(developer: true);
    await _pump(tester, s);
    final before = s.stored;
    await tester.tap(find.byKey(const Key('dev_errors_reset')));
    await tester.pumpAndSettle();
    expect(find.text('Zähler zurücksetzen?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('dev_errors_reset_cancel')));
    await tester.pumpAndSettle();
    expect(s.stored, before);
    expect(_shownTypes(tester), hasLength(3));
    expect(await s.errors.read(), hasLength(3));
  });

  testWidgets('Zähler zurücksetzen: Bestätigen leert die Liste', (
    tester,
  ) async {
    final s = await _setup(developer: true);
    await _pump(tester, s);
    await tester.tap(find.byKey(const Key('dev_errors_reset')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('dev_errors_reset_confirm')));
    await tester.pumpAndSettle();
    expect(find.text('Keine Fehler gezählt.'), findsOneWidget);
    expect(_shownTypes(tester), isEmpty);
    expect(await s.errors.read(), isEmpty);
    expect(decodeErrorCounts(s.stored), isEmpty);
  });

  testWidgets('Zähler zurücksetzen scheitert: Meldung, Liste bleibt', (
    tester,
  ) async {
    final s = await _setup(developer: true);
    await _pump(tester, s);
    s.errors.attach(_FailingSettings(), FakeClock(DateTime.utc(2026)));
    await tester.tap(find.byKey(const Key('dev_errors_reset')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('dev_errors_reset_confirm')));
    await tester.pumpAndSettle();
    expect(find.text('Zurücksetzen fehlgeschlagen.'), findsOneWidget);
    expect(decodeErrorCounts(s.stored), hasLength(3));
  });

  testWidgets('Über → Entwicklereinstellungen: Abschnitt da, App-Version im '
      'Diagnose-Export', (tester) async {
    _platformVersion();
    final s = await _setup(developer: true);
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _app(
        s,
        AboutScreen(
          developerMode: s.mode,
          appVersion: () async => '9.8.7 (65)',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('about_dev_link')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('dev_errors_card')), findsOneWidget);
    await tester.tap(find.byKey(const Key('dev_errors_share')));
    await tester.pumpAndSettle();
    final content = tester.widget<SelectableText>(
      find.byKey(const Key('dev_errors_share_content')),
    );
    expect(content.data, contains('"appVersion": "9.8.7 (65)"'));
  });

  group('in der App', () {
    testWidgets(
      'Übersicht → Entwicklereinstellungen zeigt die Zähler der App',
      (tester) async {
        final d = Device();
        await d.start(tester, const Locale('de'));
        await d.skipSetup(tester);
        await SettingsDeveloperModeStore(d.session.settings, d.clock).set(true);
        d.errors.record(StateError('Wert 4711'), null);
        await d.errors.idle;
        await openOverview(tester);
        await tester.tap(find.byKey(const Key('overview_developer')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('dev_errors_card')), findsOneWidget);
        expect(find.text('StateError'), findsOneWidget);
        expect(find.textContaining('4711'), findsNothing);
        await d.stop(tester);
      },
    );

    testWidgets('Übersicht → Entwicklereinstellungen: App-Version der '
        'Übersicht im Diagnose-Export', (tester) async {
      _platformVersion();
      final d = Device();
      await d.start(tester, const Locale('de'));
      await d.skipSetup(tester);
      await SettingsDeveloperModeStore(d.session.settings, d.clock).set(true);
      final recalculation = RecalculationController(
        RecalculationService(
          session: d.session,
          clock: d.clock,
          calculation: ValueCalculationService(
            session: d.session,
            clock: d.clock,
          ),
        ),
      );
      addTearDown(recalculation.dispose);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('de'),
          theme: RamuriTheme.light,
          builder: (context, child) => FileHandoffScope(
            handoff: d.fileHandoff,
            child: ErrorCounterScope(errors: d.errors, child: child!),
          ),
          home: OverviewScreen(
            session: d.session,
            clock: d.clock,
            permissions: d.permissions,
            recalculation: recalculation,
            sensors: d.sensors,
            appVersion: () async => '7.6.5 (43)',
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('overview_developer')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('dev_errors_share')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const Key('dev_errors_share')));
      await tester.pumpAndSettle();
      final content = tester.widget<SelectableText>(
        find.byKey(const Key('dev_errors_share_content')),
      );
      expect(content.data, contains('"appVersion": "7.6.5 (43)"'));
      await tester.pumpWidget(const SizedBox());
      await d.stop(tester);
    });

    testWidgets('nach „Alles löschen“ sind die Zähler leer (SEC-0004)', (
      tester,
    ) async {
      final d = Device();
      await d.start(tester, const Locale('de'));
      await d.skipSetup(tester);
      d.errors.record(StateError('Wert 4711'), null);
      await d.errors.idle;
      expect(await d.errors.read(), hasLength(1));
      await _deleteAll(tester);
      expect(await d.errors.read(), isEmpty);
      expect(d.storage.data.settings[SettingKeys.errorCounts], isNull);
      await d.stop(tester);
    });

    testWidgets(
      '„Alles löschen“ verwirft auch noch nicht gespeicherte Zähler',
      (tester) async {
        final d = Device();
        await d.start(tester, const Locale('de'));
        await d.skipSetup(tester);
        // Schreiben scheitert: der Zähler bleibt im Speicher.
        d.errors.attach(_FailingSettings(), d.clock);
        d.errors.record(StateError('Wert 4711'), null);
        await d.errors.idle;
        await _deleteAll(tester);
        d.errors.attach(d.session.settings, d.clock);
        await d.errors.idle;
        expect(await d.errors.read(), isEmpty);
        expect(
          decodeErrorCounts(d.storage.data.settings[SettingKeys.errorCounts]),
          isEmpty,
        );
        await d.stop(tester);
      },
    );
  });
}

Future<void> _deleteAll(WidgetTester tester) async {
  await openOverview(tester);
  await tester.tap(find.byKey(const Key('overview_data')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Alles löschen'));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(FilledButton, 'Alles löschen'));
  await tester.pumpAndSettle();
}

class _FailingSettings implements SettingsStore {
  @override
  Future<String?> get(String key) async => throw StateError('kaputt');

  @override
  Future<Map<String, String>> all() async => throw StateError('kaputt');

  @override
  Future<void> set(String key, String value, {required DateTime at}) async =>
      throw StateError('kaputt');
}
