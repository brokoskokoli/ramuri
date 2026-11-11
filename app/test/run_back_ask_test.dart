// WP17 A (OQ-0076, FR-0028): Zurück im laufenden Lauf fragt „Lauf pausieren?“. Die Aufzeichnung ist ein Zähler hinter
// dem echten Recorder: Jeder Befehl wird gezählt. Ohne Antwort, bei „Weiterlaufen“, außerhalb und bei erneutem Zurück
// geht kein Befehl hinaus; „Pausieren“ sendet genau einen Pause-Befehl (wie der Pause-Knopf).
import 'dart:async';
import 'dart:typed_data';

import 'package:adapters/adapters.dart';
import 'package:adapters/map_testing.dart';
import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/map/map_consent_controller.dart';
import 'package:running_app/features/map/map_consent_scope.dart';
import 'package:running_app/features/map/map_services.dart';
import 'package:running_app/features/run/live_run_view.dart';
import 'package:running_app/features/run/run_controller.dart';
import 'package:running_app/features/settings/unit_format.dart';
import 'package:running_app/l10n/app_localizations.dart';
import 'package:running_app/ui/ui.dart';

import 'helpers/widget_helpers.dart';

class _Consents implements ConsentStore {
  final Map<String, ConsentState> data = {};
  @override
  Future<ConsentState?> get(String k) async => data[k];
  @override
  Future<Map<String, ConsentState>> all() async => Map.of(data);
  @override
  Future<void> set(String k, ConsentState s, {required DateTime at}) async =>
      data[k] = s;
}

class _Cache implements MapCacheAdmin {
  @override
  Future<int> sizeBytes() async => 0;
  @override
  Future<void> delete() async {}
}

/// Echter Recorder, der jeden Befehl zählt.
class _CountingRecorder extends RunRecorder {
  _CountingRecorder({
    required super.clock,
    required super.runs,
    required super.rawData,
    required super.markers,
  });

  final commands = <String>[];

  /// Hält `pause()` fest, bis der Completer fertig ist (Schreibfenster).
  Completer<void>? holdPause;

  @override
  Future<CommandResult> pause() async {
    commands.add('pause');
    final hold = holdPause;
    if (hold != null) await hold.future;
    return super.pause();
  }

  @override
  Future<CommandResult> resume() {
    commands.add('resume');
    return super.resume();
  }

  @override
  Future<CommandResult> lap() {
    commands.add('lap');
    return super.lap();
  }

  @override
  Future<CommandResult> finish() {
    commands.add('finish');
    return super.finish();
  }
}

const _fmt = UnitFormatter(
  unit: DistanceUnit.kilometers,
  languageCode: 'de',
  distanceLabel: 'km',
  paceLabel: 'min/km',
  elevationLabel: 'm',
);

class _World {
  final clock = FakeClock(DateTime.utc(2030, 1, 1, 12));
  final location = FakeLocationSource();
  late final _CountingRecorder recorder;
  late final RunController run;
  late final MapConsentHolder holder;
  int _i = 0;

  Future<void> start({bool autoPause = false, ConsentState? consent}) async {
    final session = await FakeStorage().open(Uint8List(32));
    recorder = _CountingRecorder(
      clock: clock,
      runs: session.runs,
      rawData: session.rawData,
      markers: session.markers,
    );
    run = RunController(
      clock: clock,
      storage: session,
      location: location,
      initialAutoPause: autoPause,
      recorder: recorder,
    );
    final consents = _Consents();
    if (consent != null) consents.data[mapProviderSourceKey] = consent;
    final map = MapConsentController(
      store: consents,
      clock: clock,
      services: MapServices(
        gate: (c) => MapGate(
          provider: MapProvider.openFreeMap,
          consent: c,
          inner: FakeInner(),
        ),
        cache: _Cache(),
        attribution: MapProvider.openFreeMap.attribution,
      ),
    );
    holder = MapConsentHolder()..bind(map);
    await run.start();
  }

  Future<void> step(
    WidgetTester tester, {
    int n = 1,
    bool still = false,
  }) async {
    for (var k = 0; k < n; k++) {
      clock.advance(const Duration(seconds: 1));
      location.emit(
        LocationSample(
          time: clock.now(),
          latitude: 50 + (still ? _i : _i++) * 0.000027,
          longitude: 8,
          accuracyMeters: 5,
        ),
      );
      await tester.pump(const Duration(seconds: 1));
    }
  }

  Widget app() => MaterialApp(
    locale: const Locale('de'),
    theme: RamuriTheme.light,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: MapConsentScope(
      holder: holder,
      child: ListenableBuilder(
        listenable: run,
        builder: (context, _) => LiveRunView(controller: run, formatter: _fmt),
      ),
    ),
  );
}

void main() {
  late _World w;

  Future<void> open(
    WidgetTester tester, {
    bool autoPause = false,
    ConsentState? consent,
  }) async {
    w = _World();
    await w.start(autoPause: autoPause, consent: consent);
    await tester.pumpWidget(w.app());
    await w.step(tester, n: 5);
  }

  Future<void> back(WidgetTester tester) async {
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> end(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    w.run.dispose();
  }

  testWidgets('Zurück im laufenden Lauf: Rückfrage, noch kein Befehl', (
    tester,
  ) async {
    await open(tester);
    await back(tester);
    expect(find.text('Lauf pausieren?'), findsOneWidget);
    expect(find.text('Pausieren'), findsOneWidget);
    expect(find.text('Weiterlaufen'), findsOneWidget);
    expect(w.recorder.commands, isEmpty);
    expect(w.run.phase, RecordingPhase.running);
    await end(tester);
  });

  testWidgets('Weiterlaufen: Lauf läuft, kein Befehl', (tester) async {
    await open(tester);
    await back(tester);
    await tester.tap(keyed('run_pause_ask_stay'));
    await tester.pumpAndSettle();
    expect(find.text('Lauf pausieren?'), findsNothing);
    expect(w.recorder.commands, isEmpty);
    expect(w.run.phase, RecordingPhase.running);
    await end(tester);
  });

  testWidgets('Tippen außerhalb und erneutes Zurück schließen ohne Befehl', (
    tester,
  ) async {
    await open(tester);
    await back(tester);
    await tester.tapAt(const Offset(2, 2));
    await tester.pumpAndSettle();
    expect(find.text('Lauf pausieren?'), findsNothing);
    await back(tester);
    expect(find.text('Lauf pausieren?'), findsOneWidget);
    await back(tester); // zweites Zurück schließt die Rückfrage
    expect(find.text('Lauf pausieren?'), findsNothing);
    expect(w.recorder.commands, isEmpty);
    expect(w.run.phase, RecordingPhase.running);
    await end(tester);
  });

  testWidgets('Doppel-Zurück im selben Takt: ein Dialog, kein Befehl', (
    tester,
  ) async {
    await open(tester);
    // Beide Zurück kommen, bevor der Navigator das erste ausgewertet hat. Das
    // zweite verwirft der Navigator selbst: maybePop prüft nach dem Warten auf
    // willPop, ob sich die Route ganz oben geändert hat (navigator.dart,
    // `lastEntry != newLastEntry`), und das hat das erste mit dem Dialog.
    // Dieser Fall braucht den Wächter `_asking` also nicht (siehe nächster Test).
    unawaited(tester.binding.handlePopRoute());
    unawaited(tester.binding.handlePopRoute());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Lauf pausieren?'), findsOneWidget);
    expect(w.recorder.commands, isEmpty);
    await end(tester);
  });

  testWidgets(
    'Zurück im Schreibfenster nach Pausieren: keine zweite Rückfrage',
    (tester) async {
      await open(tester);
      final hold = Completer<void>();
      w.recorder.holdPause = hold;
      await back(tester);
      await tester.tap(keyed('run_pause_ask_confirm'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      // Der Pause-Befehl ist unterwegs, die Phase noch „laufend“: Der Dialog ist
      // zu, aber `_asking` hält. Ein Zurück darf keine neue Rückfrage öffnen.
      expect(w.recorder.commands, ['pause']);
      expect(w.run.phase, RecordingPhase.running);
      expect(find.text('Lauf pausieren?'), findsNothing);
      await back(tester);
      expect(find.text('Lauf pausieren?'), findsNothing);
      hold.complete();
      await tester.pumpAndSettle();
      expect(w.recorder.commands, ['pause']);
      expect(w.run.phase, RecordingPhase.paused);
      await end(tester);
    },
  );

  testWidgets('Pausieren: genau ein Pause-Befehl, danach pausiert', (
    tester,
  ) async {
    await open(tester);
    await back(tester);
    await tester.tap(keyed('run_pause_ask_confirm'));
    await tester.pumpAndSettle();
    expect(w.recorder.commands, ['pause']);
    expect(w.run.phase, RecordingPhase.paused);
    expect(keyed('run_resume'), findsOneWidget);
    await end(tester);
  });

  testWidgets('Autopause zählt wie laufend: Rückfrage, Pausieren pausiert', (
    tester,
  ) async {
    await open(tester, autoPause: true);
    await w.step(tester, n: 20, still: true);
    expect(w.run.phase, RecordingPhase.autoPaused);
    await back(tester);
    expect(find.text('Lauf pausieren?'), findsOneWidget);
    expect(w.recorder.commands, isEmpty);
    await tester.tap(keyed('run_pause_ask_confirm'));
    await tester.pumpAndSettle();
    expect(w.recorder.commands, ['pause']);
    expect(w.run.phase, RecordingPhase.paused);
    await end(tester);
  });

  testWidgets('Zustandswechsel bei offenem Dialog: Autopause endet, '
      'Pausieren pausiert weiterhin genau einmal', (tester) async {
    await open(tester, autoPause: true);
    await w.step(tester, n: 20, still: true);
    expect(w.run.phase, RecordingPhase.autoPaused);
    await back(tester);
    await w.step(tester, n: 10); // der Läufer läuft wieder los
    expect(w.run.phase, RecordingPhase.running);
    expect(find.text('Lauf pausieren?'), findsOneWidget);
    await tester.tap(keyed('run_pause_ask_confirm'));
    await tester.pumpAndSettle();
    expect(w.recorder.commands, ['pause']);
    expect(w.run.phase, RecordingPhase.paused);
    await end(tester);
  });

  testWidgets('Lauf wird bei offenem Dialog pausiert: Dialog schließt, kein '
      'zweiter Pause-Befehl', (tester) async {
    await open(tester);
    await back(tester);
    await w.run
        .pause(); // z. B. Kopfhörertaste; ein Befehl, nicht von der Rückfrage
    await tester.pumpAndSettle();
    expect(find.text('Lauf pausieren?'), findsNothing);
    expect(w.recorder.commands, ['pause']);
    expect(w.run.phase, RecordingPhase.paused);
    await end(tester);
  });

  testWidgets('Lauf endet bei offenem Dialog: Dialog schließt, kein Pause-'
      'Befehl danach', (tester) async {
    await open(tester);
    await back(tester);
    await w.run.finish();
    await tester.pumpAndSettle();
    expect(find.text('Lauf pausieren?'), findsNothing);
    expect(w.recorder.commands, ['finish']);
    expect(w.run.phase, RecordingPhase.finished);
    await end(tester);
  });

  testWidgets('Pausiert unverändert: Zurück fragt nach dem Beenden, nicht '
      'nach der Pause', (tester) async {
    await open(tester);
    await tester.tap(keyed('run_pause'));
    await tester.pump();
    expect(w.recorder.commands, ['pause']);
    await back(tester);
    expect(find.text('Lauf beenden?'), findsOneWidget);
    expect(find.text('Lauf pausieren?'), findsNothing);
    await tester.tap(keyed('run_finish_cancel'));
    await tester.pumpAndSettle();
    expect(w.recorder.commands, ['pause']);
    await end(tester);
  });

  testWidgets('Kartenseite mit Einwilligung: Zurück fragt dort genauso, ohne '
      'Befehl vor der Antwort; Weiterlaufen bleibt auf der Karte', (
    tester,
  ) async {
    await open(tester, consent: ConsentState.granted);
    await tester.tap(keyed('run_tab_1'));
    await tester.pumpAndSettle();
    await back(tester);
    expect(find.text('Lauf pausieren?'), findsOneWidget);
    expect(w.recorder.commands, isEmpty);
    await tester.tap(keyed('run_pause_ask_stay'));
    await tester.pumpAndSettle();
    expect(w.recorder.commands, isEmpty);
    expect(w.run.phase, RecordingPhase.running);
    await end(tester);
  });

  testWidgets('Kartenseite, Einwilligungsfrage offen: Zurück schließt nur die '
      'Frage, kein Befehl, keine Pause-Rückfrage', (tester) async {
    await open(tester);
    await tester.tap(keyed('run_tab_1'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog).evaluate().length, 1);
    await back(tester);
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(find.text('Lauf pausieren?'), findsNothing);
    expect(w.recorder.commands, isEmpty);
    expect(w.run.phase, RecordingPhase.running);
    await end(tester);
  });
}
