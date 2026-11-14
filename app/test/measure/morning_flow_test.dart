import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/measure/device_info.dart';
import 'package:running_app/features/measure/morning_belt.dart';
import 'package:running_app/features/measure/morning_launcher.dart';
import 'package:running_app/features/measure/morning_measure_controller.dart';
import 'package:running_app/features/measure/morning_measure_screen.dart';
import 'package:running_app/features/measure/resting_measure_controller.dart';
import 'package:running_app/l10n/app_localizations.dart';
import 'package:running_app/ui/ui.dart';

import 'measure_support.dart';

// Ablauf der Morgenmessung (FR-0215) mit der Fake-Kamera aus WP27. Alle Werte
// synthetisch, die Auswertung ist gescriptet.

const _good = PpgMeasurement(
  quality: PpgQuality.good,
  reasons: [],
  bpm: 52.4,
  rmssdMs: 48.2,
  timingNoiseMs: 12,
  intervalsMs: [1140, 1150, 1135],
);
const _limited = PpgMeasurement(
  quality: PpgQuality.limited,
  reasons: [PpgQualityReason.someDisturbances],
  bpm: 55.0,
  timingNoiseMs: 30,
  intervalsMs: [1090, 1100],
);
const _bad = PpgMeasurement(
  quality: PpgQuality.unusable,
  reasons: [PpgQualityReason.weakSignal],
);

/// Speicher, dessen Schreiben scheitern kann.
class _FlakyStore implements MorningStore {
  _FlakyStore(this.inner);
  final MorningStore inner;
  bool failAdd = false;
  bool failSleep = false;

  @override
  Future<int> add(
    MorningMeasurement measurement, {
    List<RrPacket> beltPackets = const [],
  }) {
    if (failAdd) throw const StorageException(StorageFailure.failed);
    return inner.add(measurement, beltPackets: beltPackets);
  }

  @override
  Future<List<StoredMorningMeasurement>> list() => inner.list();

  @override
  Future<void> setSleepBand(int id, SleepBand? band) {
    if (failSleep) throw const StorageException(StorageFailure.failed);
    return inner.setSleepBand(id, band);
  }

  @override
  Future<List<StoredRrPacket>> beltPackets(int id) => inner.beltPackets(id);
}

class _Rig {
  _Rig._(this.cam, this.session, this.clock, this.store, this.c, this.readings);

  final HoldingCamera cam;
  final StorageSession session;
  final FakeClock clock;
  final _FlakyStore store;
  final MorningMeasureController c;
  final StreamController<HeartRateReading> readings;
  final ValueNotifier<bool> sound = ValueNotifier(true);
  int closed = 0;
  double _t = 0;
  PpgMeasurement next = _good;
  final restStarts = <DateTime>[];
  final measureEnds = <DateTime>[];

  static Future<_Rig> make({
    DateTime? now,
    StorageSession? session,
    Duration offset = Duration.zero,
    Map<ValidationQuantity, ValidationState>? state,
    bool withBelt = false,
    bool developerMode = false,
    bool strapConnected = true,
    bool deviceFails = false,
  }) async {
    final cam = HoldingCamera();
    final s = session ?? await FakeStorage().open(testKey);
    final clock = FakeClock(
      now ?? DateTime.utc(2026, 11, 10, 5, 30),
      utcOffset: offset,
    );
    final store = _FlakyStore((s as MorningStorage).morning);
    late _Rig rig;
    final readings = StreamController<HeartRateReading>.broadcast();
    MorningBelt? belt;
    if (withBelt) {
      await SettingsDeveloperModeStore(s.settings, clock).set(developerMode);
      belt = MorningBelt(
        readings: readings.stream,
        connected: () => strapConnected,
        developerMode: SettingsDeveloperModeStore(s.settings, clock).read,
      );
      await belt.init();
    }
    final c = MorningMeasureController(
      camera: cam,
      store: store,
      windowStore: SettingsMorningWindowStore(s.settings, clock),
      clock: clock,
      device: () async {
        if (deviceFails) throw StateError('Gerät nicht lesbar');
        return (manufacturer: 'Testhersteller', model: 'Modell 1');
      },
      belt: belt,
      hooks: MorningMeasureHooks(
        onRestStarted: (t) => rig.restStarts.add(t),
        onMeasurementEnded: (t) => rig.measureEnds.add(t),
      ),
      evaluate: (frames, window) async => identical(window, ppgStandardWindow)
          ? rig.next
          : const PpgMeasurement(quality: PpgQuality.unusable, reasons: []),
      autoTick: false,
      marksFor: state == null
          ? null
          : morningMarksReader(s.settings, clock, state),
    );
    rig = _Rig._(cam, s, clock, store, c, readings);
    return rig;
  }

  Future<void> show(
    WidgetTester tester, {
    required bool dark,
    String lang = 'de',
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(c.dispose);
    addTearDown(readings.close);
    await tester.pumpWidget(
      MaterialApp(
        theme: dark ? RamuriTheme.dark : RamuriTheme.light,
        locale: Locale(lang),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MorningMeasureScreen(
          controller: c,
          soundOn: sound,
          onClose: () => closed++,
        ),
      ),
    );
  }

  Future<void> feed(WidgetTester tester, double until) async {
    var k = 0;
    while (_t <= until) {
      cam.emitFrame(
        PpgFrame(
          t: _t,
          r: 200,
          g: 40,
          r16: List.filled(16, 200),
          g16: List.filled(16, 40),
        ),
      );
      _t += 0.5;
      if (++k % 10 == 0) await tester.pump();
    }
    await _settle(tester);
  }

  /// Ruhephase starten, ablaufen lassen und die Messung bis zum Ergebnis führen.
  Future<void> runThrough(WidgetTester tester) async {
    await _tap(tester, 'morning_start');
    clock.advance(const Duration(seconds: 121));
    c.engine.tick();
    await tester.pump();
    await _settle(tester);
    _t = 0;
    await feed(tester, 67);
  }

  Future<List<MorningMeasurement>> stored(WidgetTester tester) async =>
      (await tester.runAsync(() => store.list()))!.map((e) => e.value).toList();
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
  }
}

Future<void> _tap(WidgetTester tester, String key) async {
  final f = find.byKey(Key(key));
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await _settle(tester);
}

Finder _text(String s) => find.text(s);

HeartRateReading _rr(DateTime t, int rr) =>
    HeartRateReading('gurt-1', t, 60, rrIntervals: [rr]);

void main() {
  group('Gurt-RR zur Morgenmessung (Teil E)', () {
    testWidgets('Entwicklermodus: nur Pakete von Ruhephase bis Messende', (
      tester,
    ) async {
      final r = await _Rig.make(withBelt: true, developerMode: true);
      await r.show(tester, dark: false);
      final t0 = r.clock.now();
      r.readings.add(_rr(t0.subtract(const Duration(seconds: 1)), 700));
      await _tap(tester, 'morning_start');
      r.readings.add(_rr(t0.subtract(const Duration(seconds: 1)), 701));
      r.readings.add(_rr(t0.add(const Duration(seconds: 5)), 900));
      r.clock.advance(const Duration(seconds: 121));
      r.readings.add(_rr(r.clock.now(), 910));
      r.c.engine.tick();
      await tester.pump();
      await _settle(tester);
      r._t = 0;
      await r.feed(tester, 67);
      final end = r.measureEnds.single;
      expect(r.c.outcome, MorningOutcome.good);
      final id = (await tester.runAsync(() => r.store.list()))!.single.id;
      final packets = (await tester.runAsync(() => r.store.beltPackets(id)))!;
      expect([for (final p in packets) p.value.intervals.single], [900, 910]);
      expect(packets.first.value.time, t0.add(const Duration(seconds: 5)));
      expect(packets.every((p) => !p.value.time.isAfter(end)), isTrue);
    });

    testWidgets('ohne Entwicklermodus wird nichts gespeichert', (tester) async {
      final r = await _Rig.make(withBelt: true);
      await r.show(tester, dark: false);
      await _tap(tester, 'morning_start');
      r.readings.add(_rr(r.clock.now(), 900));
      expect(find.byKey(const Key('morning_belt_hint')), findsNothing);
      r.clock.advance(const Duration(seconds: 121));
      r.c.engine.tick();
      await tester.pump();
      await _settle(tester);
      r._t = 0;
      await r.feed(tester, 67);
      expect(r.c.outcome, MorningOutcome.good);
      final id = (await tester.runAsync(() => r.store.list()))!.single.id;
      expect(await tester.runAsync(() => r.store.beltPackets(id)), isEmpty);
    });

    testWidgets('ohne Gurt läuft alles normal, kein Hinweis', (tester) async {
      final r = await _Rig.make(
        withBelt: true,
        developerMode: true,
        strapConnected: false,
      );
      await r.show(tester, dark: false);
      expect(find.byKey(const Key('morning_belt_hint')), findsNothing);
      await r.runThrough(tester);
      expect(r.c.outcome, MorningOutcome.good);
      final id = (await tester.runAsync(() => r.store.list()))!.single.id;
      expect(await tester.runAsync(() => r.store.beltPackets(id)), isEmpty);
    });

    testWidgets('Hinweis Pulsgurt im Einstieg und in der Ruhephase', (
      tester,
    ) async {
      final r = await _Rig.make(withBelt: true, developerMode: true);
      await r.show(tester, dark: false);
      expect(
        _text(
          'Pulsgurt verbunden. Seine RR-Werte werden zur Messung '
          'mitgespeichert (Entwicklermodus).',
        ),
        findsOneWidget,
      );
      await _tap(tester, 'morning_start');
      expect(_text('Pulsgurt zeichnet mit.'), findsOneWidget);
    });

    testWidgets('Abbruch: nichts gespeichert, keine verwaisten RR', (
      tester,
    ) async {
      final r = await _Rig.make(withBelt: true, developerMode: true);
      await r.show(tester, dark: false);
      await _tap(tester, 'morning_start');
      r.readings.add(_rr(r.clock.now(), 900));
      await _tap(tester, 'measure_cancel');
      expect(await tester.runAsync(() => r.store.list()), isEmpty);
      expect(r.c.belt!.packets, hasLength(1)); // nur im Speicher, nie in der DB
    });

    testWidgets('Noch einmal: Gurt-RR durchgehend bis Ende der Wiederholung', (
      tester,
    ) async {
      final r = await _Rig.make(withBelt: true, developerMode: true);
      r.next = _bad;
      await r.show(tester, dark: false);
      await _tap(tester, 'morning_start');
      r.readings.add(_rr(r.clock.now(), 900)); // Ruhephase
      r.clock.advance(const Duration(seconds: 121));
      r.c.engine.tick();
      await tester.pump();
      await _settle(tester);
      r._t = 0;
      await r.feed(tester, 67);
      expect(r.c.outcome, MorningOutcome.unusable);
      r.clock.advance(const Duration(seconds: 10));
      r.readings.add(_rr(r.clock.now(), 910)); // Lücke nach dem Ende
      await _settle(tester);
      r.next = _good;
      await _tap(tester, 'morning_again');
      r.clock.advance(const Duration(seconds: 10));
      r.readings.add(_rr(r.clock.now(), 920)); // Wiederholung
      await _settle(tester);
      r._t = 0;
      await r.feed(tester, 67);
      expect(r.c.outcome, MorningOutcome.good);
      final id = (await tester.runAsync(() => r.store.list()))!.single.id;
      final packets = (await tester.runAsync(() => r.store.beltPackets(id)))!;
      expect(
        [for (final p in packets) p.value.intervals.single],
        [900, 910, 920],
      );
    });

    testWidgets('gültige Messung: Recorder gestoppt, Pakete bleiben', (
      tester,
    ) async {
      final r = await _Rig.make(withBelt: true, developerMode: true);
      await r.show(tester, dark: false);
      await _tap(tester, 'morning_start');
      r.readings.add(_rr(r.clock.now(), 900));
      r.clock.advance(const Duration(seconds: 121));
      r.c.engine.tick();
      await tester.pump();
      await _settle(tester);
      r._t = 0;
      await r.feed(tester, 67);
      expect(r.c.outcome, MorningOutcome.good);
      expect(r.readings.hasListener, isFalse);
      r.readings.add(_rr(r.clock.now(), 999));
      await _settle(tester);
      expect(r.c.belt!.packets.single.intervals.single, 900);
    });

    testWidgets('Fehler vor dem Speichern (saveFailed): Recorder gestoppt', (
      tester,
    ) async {
      final r = await _Rig.make(
        withBelt: true,
        developerMode: true,
        deviceFails: true,
      );
      await r.show(tester, dark: false);
      await _tap(tester, 'morning_start');
      r.readings.add(_rr(r.clock.now(), 900));
      r.clock.advance(const Duration(seconds: 121));
      r.c.engine.tick();
      await tester.pump();
      await _settle(tester);
      r._t = 0;
      await r.feed(tester, 67);
      expect(r.c.outcome, MorningOutcome.saveFailed);
      expect(r.readings.hasListener, isFalse);
      r.readings.add(_rr(r.clock.now(), 999));
      await _settle(tester);
      expect(r.c.belt!.packets.single.intervals.single, 900);
    });

    testWidgets('verworfene Messung (unbrauchbar): nichts gespeichert', (
      tester,
    ) async {
      final r = await _Rig.make(withBelt: true, developerMode: true);
      r.next = _bad;
      await r.show(tester, dark: false);
      await _tap(tester, 'morning_start');
      r.readings.add(_rr(r.clock.now(), 900));
      r.clock.advance(const Duration(seconds: 121));
      r.c.engine.tick();
      await tester.pump();
      await _settle(tester);
      r._t = 0;
      await r.feed(tester, 67);
      expect(r.c.outcome, MorningOutcome.unusable);
      expect(await tester.runAsync(() => r.store.list()), isEmpty);
    });
  });

  for (final dark in [false, true]) {
    final mode = dark ? 'dunkel' : 'hell';

    group('Morgenmessung ($mode)', () {
      testWidgets('Einstieg: liegend als Vorgabe, Hinweise, feste Ruhephase', (
        tester,
      ) async {
        final r = await _Rig.make();
        await r.show(tester, dark: dark);
        expect(_text('Morgenmessung'), findsOneWidget);
        expect(
          _text('Gleich nach dem Aufwachen, erst zur Toilette.'),
          findsOneWidget,
        );
        expect(_text('Vor Kaffee und Frühstück messen.'), findsOneWidget);
        expect(
          _text('2 min ruhig bleiben, dann 60 s messen. Atme ganz normal.'),
          findsOneWidget,
        );
        expect(r.c.engine.posture, RestingPosture.lying);
        expect(
          _text('Empfohlen. Bleib jeden Morgen bei derselben Haltung.'),
          findsOneWidget,
        );
        // Keine Dauerwahl, kein sofortiges Messen, kein Atemtempo.
        expect(find.byKey(const Key('measure_minutes_plus')), findsNothing);
        expect(find.byKey(const Key('measure_mode_now')), findsNothing);
        expect(find.text('Stehend'), findsNothing);
        await tester.tap(_text('Sitzend'));
        await tester.pump();
        expect(r.c.engine.posture, RestingPosture.sitting);
        expect(find.byKey(const Key('morning_pose_note')), findsOneWidget);
        expect(find.textContaining('eigene Reihe'), findsOneWidget);
        expect(r.cam.permissionRequests, 0);

        await _tap(tester, 'morning_start');
        expect(r.c.engine.phase, RestingMeasurePhase.resting);
        expect(r.c.engine.restMinutes, 2);
        expect(_text('2:00'), findsOneWidget);
        expect(find.byKey(const Key('measure_skip_rest')), findsNothing);
        expect(r.cam.permissionRequests, 0);
        expect(r.restStarts, hasLength(1));
      });

      testWidgets('gut: speichert mit Gerät, Schlafstufe nachtragbar', (
        tester,
      ) async {
        final r = await _Rig.make();
        await r.show(tester, dark: dark);
        await r.runThrough(tester);
        expect(r.c.outcome, MorningOutcome.good);
        expect(_text('Gespeichert'), findsOneWidget);
        expect(_text('Heute 05:32, liegend'), findsOneWidget);
        expect(find.byKey(const Key('morning_hr')), findsOneWidget);
        expect(_text('52,4'), findsOneWidget);
        expect(_text('48'), findsOneWidget);
        expect(_text('geschätzt · Signal gut'), findsOneWidget);
        expect(find.byKey(const Key('morning_no_rmssd')), findsNothing);
        expect(
          _text(
            'Heute zählt diese Messung. Eine weitere am selben Tag ist nicht nötig.',
          ),
          findsOneWidget,
        );
        expect(r.cam.permissionRequests, 1);
        expect(r.measureEnds, hasLength(1));
        // Wiederholung nur bei zu schlechter Qualität.
        expect(r.c.canRepeat, isFalse);
        expect(find.byKey(const Key('morning_again')), findsNothing);
        await r.c.repeat();
        expect(r.cam.permissionRequests, 1);
        var list = await r.stored(tester);
        expect(list, hasLength(1));
        final m = list.single;
        expect(m.restingHrBpm, 52.4);
        expect(m.rmssdMs, 48.2);
        expect(m.posture, RestingPosture.lying);
        expect(m.deviceManufacturer, 'Testhersteller');
        expect(m.deviceModel, 'Modell 1');
        expect(m.outsideWindow, isFalse);
        expect(m.quality, PpgQuality.good);
        expect(m.cameraIntervalsMs, [1140, 1150, 1135]);
        expect(m.sleepBand, isNull);

        await _tap(tester, 'morning_sleep_from6to7');
        list = await r.stored(tester);
        expect(list.single.sleepBand, SleepBand.from6to7);
        expect(list, hasLength(1));
        await _tap(tester, 'morning_sleep_over8');
        expect((await r.stored(tester)).single.sleepBand, SleepBand.over8);
        await _tap(tester, 'morning_sleep_over8');
        expect((await r.stored(tester)).single.sleepBand, isNull);

        await _tap(tester, 'morning_done');
        expect(r.closed, 1);
      });

      testWidgets('Qualität gut, aber RMSSD ungültig (250): nur Ruhepuls', (
        tester,
      ) async {
        final r = await _Rig.make();
        r.next = const PpgMeasurement(
          quality: PpgQuality.good,
          reasons: [],
          bpm: 52.4,
          rmssdMs: 250,
          timingNoiseMs: 12,
          intervalsMs: [1140, 1150, 1135],
        );
        await r.show(tester, dark: dark);
        await r.runThrough(tester);
        expect(r.c.outcome, MorningOutcome.limited);
        expect(r.c.stored!.rmssdMs, isNull);
        expect(find.byKey(const Key('morning_no_rmssd')), findsOneWidget);
      });

      testWidgets('Ergebnis nach Freischaltung: Markierung wie Morgenwerte, im '
          'Modus ohne', (tester) async {
        final passed = {
          ValidationQuantity.restingHr: ValidationState.passed,
          ValidationQuantity.lnRmssdSupine: ValidationState.passed,
          ValidationQuantity.lnRmssdSitting: ValidationState.passed,
        };
        final r = await _Rig.make(state: passed);
        await r.show(tester, dark: dark);
        await r.runThrough(tester);
        expect(r.c.outcome, MorningOutcome.good);
        expect(
          tester.widget<Text>(find.byKey(const Key('morning_rmssd_mark'))).data,
          'experimentell, nicht eingeschaltet',
        );

        final d = await _Rig.make(state: passed);
        await SettingsDeveloperModeStore(d.session.settings, d.clock).set(true);
        await d.show(tester, dark: dark);
        await d.runThrough(tester);
        expect(d.c.outcome, MorningOutcome.good);
        expect(find.byKey(const Key('morning_rmssd_mark')), findsNothing);
      });

      testWidgets('eingeschränkt: Ruhepuls zählt, RMSSD bleibt leer', (
        tester,
      ) async {
        final r = await _Rig.make();
        r.next = _limited;
        await r.show(tester, dark: dark);
        await r.runThrough(tester);
        expect(r.c.outcome, MorningOutcome.limited);
        expect(_text('Gespeichert'), findsOneWidget);
        expect(_text('55,0'), findsOneWidget);
        expect(find.byKey(const Key('morning_rmssd')), findsOneWidget);
        expect(
          tester.widget<Text>(find.byKey(const Key('morning_rmssd'))).data,
          '–',
        );
        expect(_text('geschätzt · Signal eingeschränkt'), findsOneWidget);
        expect(
          _text('RMSSD braucht ein gutes Signal. Der Ruhepuls zählt trotzdem.'),
          findsOneWidget,
        );
        final m = (await r.stored(tester)).single;
        expect(m.quality, PpgQuality.limited);
        expect(m.rmssdMs, isNull);
      });

      testWidgets('außerhalb des Fensters: gespeichert, zählt nicht', (
        tester,
      ) async {
        final r = await _Rig.make(now: DateTime.utc(2026, 11, 10, 14, 5));
        await r.show(tester, dark: dark);
        await r.runThrough(tester);
        expect(r.c.outcome, MorningOutcome.outsideWindow);
        expect(find.byKey(const Key('morning_note_outside')), findsOneWidget);
        expect(
          find.textContaining('Außerhalb deines Morgenfensters (4 bis 11 Uhr)'),
          findsOneWidget,
        );
        expect((await r.stored(tester)).single.outsideWindow, isTrue);
        // Kein Widerspruch zum Hinweis oben.
        expect(find.byKey(const Key('morning_footer')), findsNothing);
        expect(find.textContaining('Heute zählt diese Messung'), findsNothing);
      });

      testWidgets('Ortszeit entscheidet über das Fenster', (tester) async {
        // 5:30 UTC ist bei +7 h 12:30 Ortszeit: außerhalb.
        final r = await _Rig.make(offset: const Duration(hours: 7));
        await r.show(tester, dark: dark);
        await r.runThrough(tester);
        expect(r.c.outcome, MorningOutcome.outsideWindow);
      });

      testWidgets(
        'unbrauchbar: nichts gespeichert, Wiederholung ohne Ruhephase',
        (tester) async {
          final r = await _Rig.make();
          r.next = _bad;
          await r.show(tester, dark: dark);
          await r.runThrough(tester);
          expect(r.c.outcome, MorningOutcome.unusable);
          expect(_text('Messung zu ungenau'), findsOneWidget);
          expect(find.byKey(const Key('morning_no_value')), findsOneWidget);
          expect(find.byKey(const Key('morning_hr')), findsNothing);
          expect(find.byKey(const Key('morning_sleep_under5')), findsNothing);
          expect(
            _text(
              'Es zählt die erste Messung des Tages mit ausreichender Qualität.',
            ),
            findsOneWidget,
          );
          expect(await r.stored(tester), isEmpty);
          expect(r.restStarts, hasLength(1));

          r.next = _good;
          await _tap(tester, 'morning_again');
          // Keine neue Ruhephase: direkt Kamera, zweite Rechteanfrage.
          expect(r.c.engine.phase, isNot(RestingMeasurePhase.resting));
          expect(r.cam.permissionRequests, 2);
          r._t = 0;
          await r.feed(tester, 67);
          expect(r.c.outcome, MorningOutcome.good);
          expect(r.restStarts, hasLength(1));
          expect(r.measureEnds, hasLength(2));
          final list = await r.stored(tester);
          expect(list, hasLength(1));
          expect(list.single.restingHrBpm, 52.4);
        },
      );

      testWidgets('unbrauchbar: „Heute nicht mehr“ schließt', (tester) async {
        final r = await _Rig.make();
        r.next = _bad;
        await r.show(tester, dark: dark);
        await r.runThrough(tester);
        await _tap(tester, 'morning_not_again');
        expect(r.closed, 1);
        expect(await r.stored(tester), isEmpty);
      });

      testWidgets('Puls außerhalb 30 bis 120 wird wie unbrauchbar verworfen', (
        tester,
      ) async {
        final r = await _Rig.make();
        r.next = const PpgMeasurement(
          quality: PpgQuality.good,
          reasons: [],
          bpm: 140,
          rmssdMs: 30,
          timingNoiseMs: 10,
        );
        await r.show(tester, dark: dark);
        await r.runThrough(tester);
        expect(r.c.outcome, MorningOutcome.unusable);
        expect(r.c.canRepeat, isTrue);
        expect(await r.stored(tester), isEmpty);

        // „Noch einmal messen“ startet wirklich eine neue Messung.
        r.next = _good;
        await _tap(tester, 'morning_again');
        expect(r.c.engine.phase, isNot(RestingMeasurePhase.result));
        r._t = 0;
        await r.feed(tester, 67);
        expect(r.c.outcome, MorningOutcome.good);
        expect(await r.stored(tester), hasLength(1));
      });

      testWidgets('zweite Messung am selben Tag zählt nicht', (tester) async {
        final r = await _Rig.make();
        await r.show(tester, dark: dark);
        await r.runThrough(tester);
        expect(r.c.outcome, MorningOutcome.good);

        final again = await _Rig.make(
          session: r.session,
          now: DateTime.utc(2026, 11, 10, 6, 10),
        );
        await again.show(tester, dark: dark);
        await again.runThrough(tester);
        expect(again.c.outcome, MorningOutcome.notCounted);
        expect(
          find.byKey(const Key('morning_note_not_counted')),
          findsOneWidget,
        );
        expect(await again.stored(tester), hasLength(2));
        expect(find.byKey(const Key('morning_footer')), findsNothing);
        expect(find.textContaining('Heute zählt diese Messung'), findsNothing);
      });

      testWidgets('liegend und sitzend am selben Morgen zählen beide', (
        tester,
      ) async {
        final r = await _Rig.make();
        await r.show(tester, dark: dark);
        await r.runThrough(tester);
        expect(r.c.outcome, MorningOutcome.good);

        final again = await _Rig.make(
          session: r.session,
          now: DateTime.utc(2026, 11, 10, 6, 10),
        );
        await again.show(tester, dark: dark);
        await tester.tap(_text('Sitzend'));
        await tester.pump();
        await again.runThrough(tester);
        expect(again.c.outcome, MorningOutcome.good);
        expect(again.c.stored!.posture, RestingPosture.sitting);
      });

      testWidgets('Speichern scheitert: Hinweis, erneut speichern', (
        tester,
      ) async {
        final r = await _Rig.make();
        r.store.failAdd = true;
        await r.show(tester, dark: dark);
        await r.runThrough(tester);
        expect(r.c.outcome, MorningOutcome.saveFailed);
        expect(find.byKey(const Key('morning_save_failed')), findsOneWidget);
        expect(find.byKey(const Key('morning_hr')), findsNothing);
        r.store.failAdd = false;
        await _tap(tester, 'morning_save_retry');
        expect(r.c.outcome, MorningOutcome.good);
        expect(await r.stored(tester), hasLength(1));
      });

      testWidgets('Schlafstufe scheitert: Hinweis, Messung bleibt', (
        tester,
      ) async {
        final r = await _Rig.make();
        await r.show(tester, dark: dark);
        await r.runThrough(tester);
        r.store.failSleep = true;
        await _tap(tester, 'morning_sleep_under5');
        expect(find.byKey(const Key('morning_sleep_failed')), findsOneWidget);
        final list = await r.stored(tester);
        expect(list, hasLength(1));
        expect(list.single.sleepBand, isNull);
      });

      testWidgets('Abbrechen in der Ruhephase: nichts gespeichert, schließt', (
        tester,
      ) async {
        final r = await _Rig.make();
        await r.show(tester, dark: dark);
        await _tap(tester, 'morning_start');
        await _tap(tester, 'measure_cancel');
        expect(r.closed, 1);
        expect(r.cam.permissionRequests, 0);
        expect(await r.stored(tester), isEmpty);
      });

      testWidgets('Englisch: Ergebnis und Einstieg', (tester) async {
        final r = await _Rig.make();
        await r.show(tester, dark: dark, lang: 'en');
        expect(_text('Morning measurement'), findsOneWidget);
        expect(_text('Start rest phase'), findsOneWidget);
        await r.runThrough(tester);
        expect(_text('Saved'), findsOneWidget);
        expect(find.textContaining('Today 5:32'), findsOneWidget);
        expect(_text('52.4'), findsOneWidget);
      });
    });
  }

  test('Gerätekanal: Wert ohne Text (TypeError) ergibt leere Angabe', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    const ch = MethodChannel('test/device_info');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          ch,
          (_) async => <String, Object?>{'manufacturer': 5, 'model': 'M'},
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(ch, null),
    );
    final d = await readDeviceInfo(ch);
    expect(d.manufacturer, '');
    expect(d.model, 'M');
  });

  test('Gerätekanal: fehlende Plattform ergibt leere Angaben', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final d = await readDeviceInfo();
    expect(d.manufacturer, '');
    expect(d.model, '');
  });
}
