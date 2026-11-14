import 'dart:async';
import 'dart:math' as math;

import 'package:adapters/adapters.dart' show MethodChannelPpgCamera;
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
    MorningRawSignal? rawSignal,
  }) {
    if (failAdd) throw const StorageException(StorageFailure.failed);
    return inner.add(
      measurement,
      beltPackets: beltPackets,
      rawSignal: rawSignal,
    );
  }

  @override
  Future<MorningRawSignal?> rawSignal(int measurementId) =>
      inner.rawSignal(measurementId);

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

/// Gescriptete Fenstersuche: Ein Bild mit `g == 41` ist schlecht, alle anderen
/// gut. Ein gutes Fenster ist 60 s ab frühestens 5 s ohne schlechtes Bild; es
/// gilt erreicht, wenn die Aufnahme bis Fensterende plus Filterrand (1,5 s)
/// reicht. Die echte Rechnung prüft `core`; hier zählen Takt, Schnappschuss,
/// Ende und Speicherung des Controllers.
double? _goodStart(List<PpgFrame> frames, {required bool strict}) {
  if (frames.isEmpty) return null;
  final last = frames.last.t;
  for (var s = 5.0; s + 60 + (strict ? 1.5 : 0) <= last + 1e-9; s += 1) {
    if (frames.every((f) => f.t < s || f.t > s + 60 || f.g != 41)) return s;
  }
  return null;
}

double _goodStretch(List<PpgFrame> frames) {
  var run = 0.0;
  double? from;
  for (final f in frames) {
    if (f.g == 41) {
      from = null;
    } else {
      from ??= f.t;
      run = f.t - from;
    }
  }
  return from == null ? 0 : run;
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

  /// Bilder mit Zeit unter dieser Grenze sind schlecht (`g == 41`).
  double badUntil = 0;
  final checkSizes = <int>[];
  final evaluated = <List<PpgFrame>>[];
  int checksRunning = 0;
  int maxChecksRunning = 0;
  Completer<void>? checkGate;

  /// Das Tor hält nur Prüfungen, deren letztes Bild mindestens so spät liegt.
  double gateAt = 0;
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
    if (developerMode) {
      await SettingsDeveloperModeStore(s.settings, clock).set(true);
    }
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
      check: (frames) async {
        rig.checkSizes.add(frames.length);
        rig.maxChecksRunning = math.max(
          rig.maxChecksRunning,
          ++rig.checksRunning,
        );
        try {
          if (frames.last.t >= rig.gateAt) await rig.checkGate?.future;
          return PpgRecordingCheck(
            goodWindowReached: _goodStart(frames, strict: true) != null,
            goodStretchSeconds: _goodStretch(frames),
          );
        } finally {
          rig.checksRunning--;
        }
      },
      evaluateBest: (frames) async {
        rig.evaluated.add(frames);
        final s = _goodStart(frames, strict: false);
        return PpgWindowedMeasurement(
          measurement: rig.next,
          windowStartSeconds: s ?? 5,
          windowEndSeconds: (s ?? 5) + 60,
          goodStretchSeconds: _goodStretch(frames),
        );
      },
      developerMode: developerMode
          ? SettingsDeveloperModeStore(s.settings, clock).read
          : null,
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
      final bad = _t < badUntil;
      cam.emitFrame(
        PpgFrame(
          t: _t,
          r: 200,
          g: bad ? 41 : 40,
          r16: List.filled(16, 200),
          g16: List.filled(16, bad ? 41 : 40),
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

/// Startet die Ruhephase, lässt sie ablaufen und setzt die Bildzeit auf 0.
Future<void> _startMeasurement(
  WidgetTester tester,
  _Rig r, {
  int restSeconds = 121,
}) async {
  await _tap(tester, 'morning_start');
  r.clock.advance(Duration(seconds: restSeconds));
  r.c.engine.tick();
  await tester.pump();
  await _settle(tester);
  r._t = 0;
}

void main() {
  group('Fenstersuche der Morgenmessung (WP37 C1)', () {
    testWidgets('30 s schlecht, dann gut: Fenster der guten Sekunden, '
        'Endergebnis auf genau den geprüften Bildern', (tester) async {
      final r = await _Rig.make();
      r.badUntil = 30;
      await r.show(tester, dark: false);
      await _startMeasurement(tester, r);
      await r.feed(tester, 100);
      final m = (await r.stored(tester)).single;
      expect(r.c.outcome, MorningOutcome.good);
      expect(m.quality, PpgQuality.good);
      expect(m.windowStartS, 30);
      expect(m.windowEndS, 90);
      expect(m.methodVersion, 2);
      // Punkt 9 (Review 1): das Endergebnis wertet genau die Bilder aus, auf
      // denen die letzte Prüfung „gut“ bestätigt hat.
      expect(r.evaluated.single.length, r.checkSizes.last);
      expect(r.evaluated.single.last.t, lessThan(95));
    });

    testWidgets('gut von Anfang an: Ende bei 66,5 s', (tester) async {
      final r = await _Rig.make();
      await r.show(tester, dark: false);
      await _startMeasurement(tester, r);
      await r.feed(tester, 80);
      expect(r.c.outcome, MorningOutcome.good);
      expect(r.evaluated.single.last.t, 66.5);
      final m = (await r.stored(tester)).single;
      expect(m.windowStartS, 5);
      expect(m.windowEndS, 65);
    });

    testWidgets('nie gut: Aufnahme endet bei 120 s mit dem besten Fenster', (
      tester,
    ) async {
      final r = await _Rig.make();
      r.badUntil = 1000;
      r.next = _limited;
      await r.show(tester, dark: false);
      await _startMeasurement(tester, r);
      await r.feed(tester, 125);
      expect(r.evaluated.single.last.t, 120);
      expect((await r.stored(tester)).single.quality, PpgQuality.limited);
      // Takt: höchstens alle 3 s eine Prüfung, nie vor 35 s.
      expect(r.checkSizes.length, lessThanOrEqualTo(30));
      expect(r.checkSizes.first, greaterThan(60));
    });

    testWidgets('höchstens eine Prüfung zugleich', (tester) async {
      final r = await _Rig.make();
      r.checkGate = Completer<void>();
      await r.show(tester, dark: false);
      await _startMeasurement(tester, r);
      await r.feed(tester, 50);
      expect(r.checkSizes, hasLength(1));
      expect(r.maxChecksRunning, 1);
      r.checkGate!.complete();
      await _settle(tester);
      await r.feed(tester, 60);
      expect(r.maxChecksRunning, 1);
      expect(r.checkSizes.length, greaterThan(1));
    });

    testWidgets('Bilder, die während der Prüfung eintreffen, zählen nicht zum '
        'Endergebnis', (tester) async {
      final r = await _Rig.make();
      r.checkGate = Completer<void>();
      r.gateAt = 66;
      await r.show(tester, dark: false);
      await _startMeasurement(tester, r);
      await r.feed(tester, 70);
      expect(r.evaluated, isEmpty);
      r.checkGate!.complete();
      await _settle(tester);
      expect(r.evaluated.single.last.t, 66.5);
      expect(r.c.engine.result!.frames.last.t, 66.5);
    });

    testWidgets(
      'Überspringen startet die Messung sofort, Vermerk gespeichert',
      (tester) async {
        final r = await _Rig.make();
        await r.show(tester, dark: false);
        await _tap(tester, 'morning_start');
        r.clock.advance(const Duration(seconds: 30));
        r.c.engine.tick();
        await tester.pump();
        expect(find.byKey(const Key('morning_skip_rest')), findsOneWidget);
        await _tap(tester, 'morning_skip_rest');
        expect(r.c.engine.phase, RestingMeasurePhase.measuring);
        r._t = 0;
        await r.feed(tester, 80);
        expect((await r.stored(tester)).single.restSkippedAfterS, 30);
      },
    );

    testWidgets('Ruhephase abgelaufen: kein Vermerk', (tester) async {
      final r = await _Rig.make();
      await r.show(tester, dark: false);
      await _startMeasurement(tester, r);
      await r.feed(tester, 80);
      expect((await r.stored(tester)).single.restSkippedAfterS, isNull);
    });

    testWidgets('Entwicklermodus: Rohsignal der ganzen Aufnahme gespeichert', (
      tester,
    ) async {
      final r = await _Rig.make(developerMode: true);
      await r.show(tester, dark: false);
      await _startMeasurement(tester, r);
      await r.feed(tester, 80);
      final id = (await tester.runAsync(() => r.store.list()))!.single.id;
      final raw = (await tester.runAsync(() => r.store.rawSignal(id)))!;
      expect(raw.frames.length, r.evaluated.single.length);
      expect(raw.frames.first.t, 0);
      expect(raw.frames.last.t, 66.5);
      expect(raw.frameGapCount, 0);
    });

    testWidgets(
      'Entwicklermodus: Kamera-Angaben vom Adapter über Rohsignal bis CSV',
      (tester) async {
        final r = await _Rig.make(developerMode: true);
        await r.show(tester, dark: false);
        await _startMeasurement(tester, r);
        // Nachrichten wie Kotlin sie sendet, durch den echten Adapter-Parser: der letzte Stand gilt.
        PpgCameraEvent? msg(Map<String, Object> m) =>
            MethodChannelPpgCamera.parse({'type': 'details', ...m});
        r.cam.emitDetails(
          msg({'iso': 50, 'saturated': 0.01}) as PpgCameraDetails,
        );
        r.cam.emitDetails(
          msg({
            'exposureNs': 8333333,
            'iso': 100,
            'timestampSource': 'realtime',
            'skewNs': 20000000,
            'saturated': 0.02,
          }) as PpgCameraDetails,
        );
        await r.feed(tester, 80);
        final id = (await tester.runAsync(() => r.store.list()))!.single;
        final raw = (await tester.runAsync(() => r.store.rawSignal(id.id)))!;
        expect(raw.exposureTimeNs, 8333333);
        expect(raw.iso, 100);
        expect(raw.timestampSource, CameraTimestampSource.realtime);
        expect(raw.rollingShutterSkewNs, 20000000);
        expect(raw.torchStrength, isNull, reason: 'Gerät lieferte keine');
        expect(raw.saturatedFraction, 0.02);
        final csv = encodeMorningPairsCsv([
          MorningPair(id: id.id, measurement: id.value, rawSignal: raw),
        ]);
        expect(csv, contains(',meta,exposure_time,,,,8333333,ns\r\n'));
        expect(csv, contains(',meta,iso,,,,100,\r\n'));
        expect(csv, contains(',meta,timestamp_source,,,,realtime,\r\n'));
        expect(csv, contains(',meta,rolling_shutter_skew,,,,20000000,ns\r\n'));
        expect(csv, contains(',meta,torch_strength,,,,,\r\n'));
        expect(csv, contains(',meta,saturated_fraction,,,,0.02,\r\n'));
      },
    );

    testWidgets('ohne Entwicklermodus: kein Rohsignal', (tester) async {
      final r = await _Rig.make();
      await r.show(tester, dark: false);
      await _startMeasurement(tester, r);
      await r.feed(tester, 80);
      final id = (await tester.runAsync(() => r.store.list()))!.single.id;
      expect(await tester.runAsync(() => r.store.rawSignal(id)), isNull);
    });

    testWidgets('unbrauchbar ohne Entwicklermodus: nichts gespeichert', (
      tester,
    ) async {
      final r = await _Rig.make();
      r.next = _bad;
      await r.show(tester, dark: false);
      await _startMeasurement(tester, r);
      await r.feed(tester, 80);
      expect(r.c.outcome, MorningOutcome.unusable);
      expect(await r.stored(tester), isEmpty);
    });

    testWidgets('unbrauchbar im Entwicklermodus: gespeichert mit Stufe, Grund '
        'und Kamera-Schlagabständen', (tester) async {
      final r = await _Rig.make(developerMode: true);
      r.next = const PpgMeasurement(
        quality: PpgQuality.unusable,
        reasons: [PpgQualityReason.weakSignal],
        intervalsMs: [1000, 1010],
      );
      await r.show(tester, dark: false);
      await _startMeasurement(tester, r);
      await r.feed(tester, 80);
      final m = (await r.stored(tester)).single;
      expect(m.quality, PpgQuality.unusable);
      expect(m.unusableReason, PpgQualityReason.weakSignal);
      expect(m.cameraIntervalsMs, [1000, 1010]);
      expect(m.windowStartS, 5);
    });
  });

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

    testWidgets(
      'Noch einmal: jede Messung trägt nur die Gurt-RR ihrer Aufnahme',
      (tester) async {
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
        // Die unbrauchbare erste Messung ist im Entwicklermodus mitgespeichert
        // (K68); jede trägt nur die RR ihrer eigenen Aufnahme (erste: Ruhephase
        // bis Ende, zweite: ab „Noch einmal“ bis Ende, ohne Lücke davor).
        final all = (await tester.runAsync(() => r.store.list()))!;
        expect(all.map((e) => e.value.quality), [
          PpgQuality.unusable,
          PpgQuality.good,
        ]);
        final first = (await tester.runAsync(
          () => r.store.beltPackets(all.first.id),
        ))!;
        expect([for (final p in first) p.value.intervals.single], [900]);
        final packets = (await tester.runAsync(
          () => r.store.beltPackets(all.last.id),
        ))!;
        expect([for (final p in packets) p.value.intervals.single], [920]);
      },
    );

    testWidgets('Ruhe übersprungen: Gurt-RR erst ab Beginn der Messung', (
      tester,
    ) async {
      final r = await _Rig.make(withBelt: true, developerMode: true);
      await r.show(tester, dark: false);
      await _tap(tester, 'morning_start');
      r.readings.add(_rr(r.clock.now(), 900)); // Ruhephase, übersprungen
      r.clock.advance(const Duration(seconds: 30));
      r.c.engine.tick();
      await tester.pump();
      await _tap(tester, 'morning_skip_rest');
      r.clock.advance(const Duration(seconds: 1));
      r.readings.add(_rr(r.clock.now(), 950)); // Messung
      await _settle(tester);
      r._t = 0;
      await r.feed(tester, 67);
      expect(r.c.outcome, MorningOutcome.good);
      final all = (await tester.runAsync(() => r.store.list()))!;
      final packets = (await tester.runAsync(
        () => r.store.beltPackets(all.single.id),
      ))!;
      expect([for (final p in packets) p.value.intervals.single], [950]);
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

    testWidgets('unbrauchbar im Entwicklermodus: gespeichert, zählt nicht', (
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
      final all = (await tester.runAsync(() => r.store.list()))!;
      expect(all.single.value.quality, PpgQuality.unusable);
      expect(all.single.value.restingHrBpm, isNull);
      expect(all.single.value.unusableReason, PpgQualityReason.weakSignal);
      final packets = (await tester.runAsync(
        () => r.store.beltPackets(all.single.id),
      ))!;
      expect([for (final p in packets) p.value.intervals.single], [900]);
      expect(r.c.stored, isNull);
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
          _text(
            '2 min ruhig bleiben (überspringbar), dann messen, bis zu 2 min. Atme ganz normal.',
          ),
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
        expect(find.textContaining('zählen in einer Reihe'), findsOneWidget);
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
        };
        final o = await _Rig.make(state: passed);
        await o.show(tester, dark: dark);
        await o.runThrough(tester);
        expect(o.c.outcome, MorningOutcome.good);
        expect(
          tester.widget<Text>(find.byKey(const Key('morning_rmssd_mark'))).data,
          'experimentell, nicht eingeschaltet',
        );

        final r = await _Rig.make(state: passed);
        await r.session.settings.set(
          SettingKeys.morningCameraRmssdOptIn,
          '1',
          at: r.clock.now(),
        );
        await r.show(tester, dark: dark);
        await r.runThrough(tester);
        expect(r.c.outcome, MorningOutcome.good);
        expect(
          tester.widget<Text>(find.byKey(const Key('morning_rmssd_mark'))).data,
          'experimentell, mit einem Brustgurt verglichen (ein Handy)',
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

      testWidgets('liegend, dann sitzend am selben Morgen: eine Reihe, nur die '
          'erste zählt (K67)', (tester) async {
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
        expect(again.c.outcome, MorningOutcome.notCounted);
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
