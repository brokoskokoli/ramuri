import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/run/run_controller.dart';
import 'package:running_app/features/run/run_ports.dart';
import 'package:running_app/features/run/voice_texts.dart';
import 'package:running_app/features/sensors/run_heart_rate.dart';
import 'package:running_app/features/sensors/sensor_manager.dart';
import 'package:running_app/l10n/app_localizations.dart';

final _t0 = DateTime.utc(2031, 3, 1, 10);

const _twoParts = [
  PlanSegment(kind: PlanSegmentKind.easy, minutes: 1),
  PlanSegment(kind: PlanSegmentKind.interval, minutes: 1),
];

/// Pulsgrenze 140 in einem langen Abschnitt (PAR-107: Pulsansage erst ab 3:30).
const _withLimit = [
  PlanSegment(
    kind: PlanSegmentKind.easy,
    minutes: 10,
    intensity: PlanTargetIntensity(hrMaxBpm: 140),
  ),
];

/// Sprachausgabe, die schon beim Aufruf wirft (nicht erst in der Future).
class _SyncThrowingVoice implements VoicePort {
  int calls = 0;

  @override
  Future<void> speak(String text, {String? languageTag}) {
    calls++;
    throw StateError('sofort');
  }

  @override
  Future<bool> available({String? languageTag}) => throw StateError('sofort');

  @override
  Future<void> stop() => throw StateError('sofort');
}

class _World {
  _World(this.clock, this.session);
  final FakeClock clock;
  final StorageSession session;
  final location = FakeLocationSource();
  final voice = FakeVoice();
  int _i = 0;
  final _live = <RunController>[];

  /// Beendet einen Controller (Timer weg) vor dem Testende.
  void drop(RunController c) {
    if (_live.remove(c)) c.dispose();
  }

  void close() => _live.toList().forEach(drop);

  static final all = <_World>[];

  static Future<_World> create() async {
    final w = _World(FakeClock(_t0), await FakeStorage().open(Uint8List(32)));
    all.add(w);
    return w;
  }

  RunController controller({
    List<PlanSegment>? segments,
    int? resume,
    PlanUnitKind? kind,
    RunHeartRate? sensors,
    RecordingServicePort? service,
    VoicePort? voicePort,
    List<EasyRunExposure> easy = const [],
    Future<List<EasyRunExposure>> Function(
      StorageSession, {
      required DateTime today,
    })?
    easyFn,
  }) => _own(
    RunController(
      clock: clock,
      storage: session,
      location: location,
      sensors: sensors,
      service: service,
      resumeRunId: resume,
      voice: voicePort ?? voice,
      voiceTexts: VoiceTexts(lookupAppLocalizations(const Locale('de'))),
      guidedSegments: segments,
      guidedKind: kind,
      recentEasyRuns: easyFn ?? (s, {required today}) async => easy,
    ),
  );

  RunController _own(RunController c) {
    _live.add(c);
    return c;
  }

  /// Eine Sekunde: Uhr, Punkt (etwa 3 m/s), Takt.
  Future<void> second(WidgetTester tester, {RunHeartRate? hr, int? bpm}) async {
    clock.advance(const Duration(seconds: 1));
    location.emit(
      LocationSample(
        time: clock.now(),
        latitude: 50 + _i++ * 0.000027,
        longitude: 8,
        accuracyMeters: 5,
      ),
    );
    if (hr != null && bpm != null) {
      hr.handle(HeartRateReading('s', clock.now(), bpm));
    }
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> seconds(
    WidgetTester tester,
    int n, {
    RunHeartRate? hr,
    int? bpm,
  }) async {
    for (var i = 0; i < n; i++) {
      await second(tester, hr: hr, bpm: bpm);
    }
  }
}

RunHeartRate _hr(FakeClock clock) {
  final run = SensorManager(
    sensor: FakeHeartRateSensor(),
    clock: clock,
  ).beginRun();
  run.handle(const HeartRateConnected('s'));
  return run;
}

void guided(String name, Future<void> Function(WidgetTester tester) body) =>
    testWidgets(name, (tester) async {
      try {
        await body(tester);
      } finally {
        // Timer weg, bevor der Test endet (sonst meldet Flutter offene Timer).
        for (final w in _World.all) {
          w.close();
        }
        _World.all.clear();
      }
    });

void main() {
  guided('Abschnittswechsel wird angesagt, Schnappschuss gespeichert', (
    tester,
  ) async {
    final w = await _World.create();
    final c = w.controller(segments: _twoParts);
    await c.start();
    await w.seconds(tester, 61);
    expect(w.voice.spoken, [
      'In 10 Sekunden: Intervall.',
      'Intervall, 1 Minute 0 Sekunden.',
    ]);
    expect(w.voice.languages, ['de', 'de']);
    final stored = GuidedUnitSnapshot.decode(
      await w.session.settings.get(SettingKeys.guidedUnitSnapshot),
    );
    expect(stored!.runId, c.runId);
    expect(stored.segments, hasLength(2));
  });

  guided('Hängende Vorbereitung blockiert den Start nie (Review 1, M1)', (
    tester,
  ) async {
    final w = await _World.create();
    final never = Completer<List<EasyRunExposure>>();
    final c = w.controller(
      segments: _withLimit,
      easyFn: (s, {required today}) => never.future,
    );
    await c.start();
    expect(c.runId, isNotNull);
    expect(w.location.hasListeners, isTrue);
    await w.seconds(tester, 5);
    expect(c.snapshot.movingTime, isNotNull);
    expect(c.snapshot.movingTime!.inSeconds, greaterThanOrEqualTo(4));
    expect(c.snapshot.distanceMeters, isNotNull);
    await c.finish();
    expect(c.phase, RecordingPhase.finished);
  });

  guided('Schnappschuss steht vor dem Dienststart (Review 2, S4)', (
    tester,
  ) async {
    final w = await _World.create();
    final gate = Completer<void>();
    final c = w.controller(
      segments: _twoParts,
      service: FakeRecordingServicePort()..startGate = gate.future,
    );
    unawaited(c.start()); // hängt im Dienststart
    await tester.pump(const Duration(milliseconds: 10));
    expect(c.runId, isNotNull);
    final stored = GuidedUnitSnapshot.decode(
      await w.session.settings.get(SettingKeys.guidedUnitSnapshot),
    );
    expect(stored?.runId, c.runId);
    gate.complete();
    await tester.pump();
  });

  guided('Ende vor der Vorbereitung: kein Ereignisgeber, kein Schnappschuss '
      '(Review 2, M3)', (tester) async {
    final w = await _World.create();
    final late = Completer<List<EasyRunExposure>>();
    const above = EasyRunExposure(
      aboveUpper: Duration(minutes: 30),
      known: Duration(minutes: 30),
    );
    final c = w.controller(
      segments: _withLimit,
      easyFn: (s, {required today}) => late.future,
    );
    await c.start();
    await w.seconds(tester, 3);
    await c.finish(); // die Vorbereitung hängt noch
    late.complete(const [above, above, above]);
    await tester.pump(const Duration(milliseconds: 10));
    // Mit Ereignisgeber wäre die Pulsumstellung aktiv (drei Läufe über Grenze).
    expect(c.guidedPulseHintsSuppressed, isFalse);
    expect(
      GuidedUnitSnapshot.decode(
        await w.session.settings.get(SettingKeys.guidedUnitSnapshot),
      ),
      isNull,
    );
  });

  group('Schnappschuss am Laufende (Review 1, S5)', () {
    Future<String?> stored(_World w) =>
        w.session.settings.get(SettingKeys.guidedUnitSnapshot);

    guided('Ende leert den Schnappschuss', (tester) async {
      final w = await _World.create();
      final c = w.controller(segments: _twoParts);
      await c.start();
      await w.seconds(tester, 5);
      expect(GuidedUnitSnapshot.decode(await stored(w)), isNotNull);
      await c.finish();
      expect(GuidedUnitSnapshot.decode(await stored(w)), isNull);
    });

    guided('Ende nach Wiederanlauf leert ihn ebenfalls', (tester) async {
      final w = await _World.create();
      final first = w.controller(segments: _twoParts);
      await first.start();
      await w.seconds(tester, 5);
      final id = first.runId!;
      w.drop(first);
      final second = w.controller(resume: id);
      await second.start();
      await w.seconds(tester, 5);
      expect(GuidedUnitSnapshot.decode(await stored(w)), isNotNull);
      await second.finish();
      expect(GuidedUnitSnapshot.decode(await stored(w)), isNull);
    });
  });

  group('Schalter', () {
    Future<List<String>> run(
      WidgetTester tester,
      Map<String, String> settings,
    ) async {
      final w = await _World.create();
      for (final e in settings.entries) {
        await w.session.settings.set(e.key, e.value, at: _t0);
      }
      final c = w.controller(segments: _twoParts);
      await c.start();
      await w.seconds(tester, 61);
      return w.voice.spoken;
    }

    guided('Vorgabe: an', (tester) async {
      expect(await run(tester, {}), isNotEmpty);
    });

    guided('Hauptschalter aus: kein speak', (tester) async {
      expect(await run(tester, {SettingKeys.guidanceEnabled: '0'}), isEmpty);
    });

    guided('Schalter Abschnitte aus: kein speak', (tester) async {
      expect(await run(tester, {SettingKeys.guidanceSegments: '0'}), isEmpty);
    });

    guided('anderer Einzelschalter aus: Abschnitte kommen weiter', (
      tester,
    ) async {
      expect(
        await run(tester, {SettingKeys.guidanceKilometer: '0'}),
        isNotEmpty,
      );
    });
  });

  group('Sprachausgabe fehlt (Hinweis beim Start)', () {
    guided('fehlt sie: einmaliger Hinweis, Lauf und Ansagen laufen weiter', (
      tester,
    ) async {
      final w = await _World.create();
      w.voice.isAvailable = false;
      final c = w.controller(segments: _twoParts);
      expect(c.voiceUnavailable, isFalse);
      await c.start();
      await w.seconds(tester, 61);
      expect(c.voiceUnavailable, isTrue);
      expect(w.voice.availableCalls, 1);
      expect(w.voice.availableLanguages, ['de']);
      expect(c.phase, RecordingPhase.running);
    });

    guided('vorhanden: kein Hinweis', (tester) async {
      final w = await _World.create();
      final c = w.controller(segments: _twoParts);
      await c.start();
      await w.seconds(tester, 2);
      expect(w.voice.availableCalls, 1);
      expect(c.voiceUnavailable, isFalse);
    });

    guided('Hauptschalter aus: nicht gefragt, kein Hinweis', (tester) async {
      final w = await _World.create();
      await w.session.settings.set(SettingKeys.guidanceEnabled, '0', at: _t0);
      w.voice.isAvailable = false;
      final c = w.controller(segments: _twoParts);
      await c.start();
      await w.seconds(tester, 5);
      expect(w.voice.availableCalls, 0);
      expect(c.voiceUnavailable, isFalse);
    });

    guided('alle Einzelschalter aus: nicht gefragt', (tester) async {
      final w = await _World.create();
      for (final k in [
        SettingKeys.guidanceKilometer,
        SettingKeys.guidanceHeartRate,
        SettingKeys.guidanceSegments,
      ]) {
        await w.session.settings.set(k, '0', at: _t0);
      }
      w.voice.isAvailable = false;
      final c = w.controller(segments: _twoParts);
      await c.start();
      await w.seconds(tester, 5);
      expect(w.voice.availableCalls, 0);
      expect(c.voiceUnavailable, isFalse);
    });

    guided('Fortsetzen nach Absturz: Schnappschuss, dann wird gefragt', (
      tester,
    ) async {
      final w = await _World.create();
      final first = w.controller(segments: _twoParts);
      await first.start();
      await w.seconds(tester, 5);
      final id = first.runId!;
      w.drop(first);
      w.voice.isAvailable = false;
      final calls = w.voice.availableCalls;
      final second = w.controller(resume: id);
      await second.start();
      await w.seconds(tester, 5);
      expect(w.voice.availableCalls, calls + 1);
      expect(second.voiceUnavailable, isTrue);
    });

    guided('ohne geführte Einheit wird nicht gefragt', (tester) async {
      final w = await _World.create();
      w.voice.isAvailable = false;
      final c = w.controller();
      await c.start();
      await w.seconds(tester, 2);
      expect(w.voice.availableCalls, 0);
      expect(c.voiceUnavailable, isFalse);
    });

    guided('Fehler der Abfrage: kein Hinweis (unbekannt)', (tester) async {
      final w = await _World.create();
      w.voice.error = StateError('weg');
      final c = w.controller(segments: _twoParts);
      await c.start();
      await w.seconds(tester, 2);
      expect(c.voiceUnavailable, isFalse);
      expect(c.phase, RecordingPhase.running);
    });
  });

  group('Fehler der Sprachausgabe stören die Aufzeichnung nie', () {
    for (final error in <Object>[
      StateError('weg'),
      Exception('x'),
      'Zeichenkette',
    ]) {
      guided('werfender Fake (${error.runtimeType})', (tester) async {
        final w = await _World.create();
        w.voice.error = error;
        final c = w.controller(segments: _twoParts);
        await c.start();
        await w.seconds(tester, 70);
        expect(w.voice.spoken, isNotEmpty); // es wurde versucht
        expect(c.phase, RecordingPhase.running);
        expect(c.snapshot.movingTime!.inSeconds, greaterThanOrEqualTo(69));
        expect(c.writeFailure, isNull);
        await c.finish();
        expect(c.phase, RecordingPhase.finished);
        expect((await w.session.runs.get(c.runId!))!.state, RunState.finished);
      });
    }

    guided('Sprachausgabe wirft synchron beim Aufruf', (tester) async {
      final w = await _World.create();
      final v = _SyncThrowingVoice();
      final c = w.controller(segments: _twoParts, voicePort: v);
      await c.start();
      await w.seconds(tester, 70);
      expect(v.calls, greaterThan(0));
      expect(c.phase, RecordingPhase.running);
      expect(c.snapshot.movingTime!.inSeconds, greaterThanOrEqualTo(69));
      await c.finish();
      expect(c.phase, RecordingPhase.finished);
    });

    guided('Sprachausgabe hängt: Aufzeichnung und weitere Ansagen laufen', (
      tester,
    ) async {
      final w = await _World.create();
      final never = Completer<void>();
      w.voice.hang = never.future;
      final c = w.controller(
        segments: const [
          PlanSegment(kind: PlanSegmentKind.easy, minutes: 1),
          PlanSegment(kind: PlanSegmentKind.interval, minutes: 1),
          PlanSegment(kind: PlanSegmentKind.easy, minutes: 1),
        ],
      );
      await c.start();
      await w.seconds(tester, 125);
      expect(w.voice.spoken.last, 'Locker laufen, 1 Minute 0 Sekunden.');
      expect(w.voice.spoken, hasLength(4)); // zweiter Wechsel trotz Hängen
      expect(c.snapshot.movingTime!.inSeconds, greaterThanOrEqualTo(124));
      await c.finish();
      expect(c.phase, RecordingPhase.finished);
    });

    guided('Beenden stoppt die Sprachausgabe, Pause nicht (E2E-Befund NB9)', (
      tester,
    ) async {
      final w = await _World.create();
      final c = w.controller(segments: _twoParts);
      await c.start();
      await w.seconds(tester, 5);
      await c.pause();
      expect(c.phase, RecordingPhase.paused);
      expect(w.voice.stopCalls, 0); // Pause lässt die Ansage ausklingen
      await c.resume();
      await c.finish();
      expect(c.phase, RecordingPhase.finished);
      // Schon vor dem Schließen der Seite (dispose): laufende Ansage und
      // Warteschlange sind verworfen.
      expect(w.voice.stopCalls, 1);
    });

    guided('Fehler der Textbildung oder beim Stoppen stört nicht', (
      tester,
    ) async {
      final w = await _World.create();
      final c = w.controller(segments: _twoParts);
      await c.start();
      w.voice.error = StateError('weg');
      await w.seconds(tester, 61);
      w.drop(c); // stop wirft: kein Fehler nach außen
      await tester.pump();
      expect(w.voice.stopCalls, 1);
    });
  });

  guided('ohne Sprachausgabe: Lauf normal, Schnappschuss trotzdem da', (
    tester,
  ) async {
    final w = await _World.create();
    final c = RunController(
      clock: w.clock,
      storage: w.session,
      location: w.location,
      guidedSegments: _twoParts,
    );
    w._live.add(c);
    await c.start();
    await w.seconds(tester, 61);
    expect(c.phase, RecordingPhase.running);
    // Die Führung (Seite, Wiederanlauf) hängt nicht an der Sprachausgabe.
    expect(
      await w.session.settings.get(SettingKeys.guidedUnitSnapshot),
      isNotNull,
    );
  });

  group('Wiederanlauf (Festlegung 3)', () {
    guided('Schnappschuss führt die Einheit weiter, Plan egal', (tester) async {
      final w = await _World.create();
      final first = w.controller(segments: _twoParts);
      await first.start();
      await w.seconds(tester, 30);
      final id = first.runId!;
      w.drop(first);
      w.clock.advance(const Duration(seconds: 10));
      final second = w.controller(resume: id); // ohne Abschnitte
      await second.start();
      expect(second.phase, RecordingPhase.running);
      await w.seconds(tester, 40);
      // Vorankündigung stammt aus dem Schnappschuss, nicht aus dem Plan.
      expect(w.voice.spoken, [
        'In 10 Sekunden: Intervall.',
        'Intervall, 1 Minute 0 Sekunden.',
      ]);
    });

    guided('Art der Einheit überlebt den Wiederanlauf (Kopfzeile)', (
      tester,
    ) async {
      final w = await _World.create();
      final first = w.controller(
        segments: _twoParts,
        kind: PlanUnitKind.intervals,
      );
      await first.start();
      await w.seconds(tester, 1);
      expect(first.guidedUnitKind, PlanUnitKind.intervals);
      final id = first.runId!;
      w.drop(first);
      w.clock.advance(const Duration(seconds: 10));
      final second = w.controller(resume: id); // ohne Art und Abschnitte
      await second.start();
      await w.seconds(
        tester,
        1,
      ); // der Schnappschuss wird nach dem Start gelesen
      expect(second.guidedUnitKind, PlanUnitKind.intervals);
    });

    guided('Schnappschuss eines anderen Laufs wird ignoriert', (tester) async {
      final w = await _World.create();
      final first = w.controller(segments: _twoParts);
      await first.start();
      await w.seconds(tester, 1); // Vorbereitung läuft nach dem Start
      final id = first.runId!;
      w.drop(first);
      w.clock.advance(const Duration(seconds: 10));
      await w.session.settings.set(
        SettingKeys.guidedUnitSnapshot,
        GuidedUnitSnapshot(runId: id + 99, segments: _twoParts).encode(),
        at: _t0,
      );
      final second = w.controller(resume: id);
      await second.start();
      await w.seconds(tester, 70);
      expect(second.snapshot.movingTime!.inSeconds, greaterThan(60));
      expect(w.voice.spoken, isEmpty);
    });

    /// Hinweis kommt im ersten Teil; danach Wiederanlauf. [forgetHint] löscht
    /// den gespeicherten Merker (Kontrolle: dann kommt der Hinweis erneut).
    Future<List<String>> hintAcrossResume(
      WidgetTester tester, {
      required bool forgetHint,
    }) async {
      final w = await _World.create();
      const above = EasyRunExposure(
        aboveUpper: Duration(minutes: 30),
        known: Duration(minutes: 30),
      );
      final hr = _hr(w.clock);
      final first = w.controller(
        segments: _withLimit,
        sensors: hr,
        easy: const [above, above, above],
      );
      await first.start();
      await w.seconds(tester, 215, hr: hr, bpm: 170);
      final hint = lookupAppLocalizations(const Locale('de'))
          .voiceWalkBreakHint;
      expect(w.voice.spoken, [hint]);
      final stored = GuidedUnitSnapshot.decode(
        await w.session.settings.get(SettingKeys.guidedUnitSnapshot),
      )!;
      expect(stored.walkBreakHintGiven, isTrue);
      if (forgetHint) {
        await w.session.settings.set(
          SettingKeys.guidedUnitSnapshot,
          GuidedUnitSnapshot(
            runId: stored.runId,
            segments: stored.segments,
          ).encode(),
          at: _t0,
        );
      }
      final id = first.runId!;
      w.drop(first);
      w.clock.advance(const Duration(seconds: 10));
      final hr2 = _hr(w.clock);
      final second = w.controller(
        resume: id,
        sensors: hr2,
        easy: const [above, above, above],
      );
      await second.start();
      await w.seconds(tester, 120, hr: hr2, bpm: 170);
      expect(second.snapshot.movingTime!.inSeconds, greaterThan(300));
      return w.voice.spoken;
    }

    guided('Gehpausen-Hinweis: einmal, auch nach Wiederanlauf', (tester) async {
      final spoken = await hintAcrossResume(tester, forgetHint: false);
      expect(spoken, hasLength(1)); // nicht noch einmal
    });

    guided(
      'Kontrolle: ohne gemerkten Hinweis kommt er nach Wiederanlauf erneut',
      (tester) async {
        final spoken = await hintAcrossResume(tester, forgetHint: true);
        expect(spoken, hasLength(2));
      },
    );

    guided('ohne Beleg: Pulsansage statt Hinweis', (tester) async {
      final w = await _World.create();
      final hr = _hr(w.clock);
      final c = w.controller(segments: _withLimit, sensors: hr);
      await c.start();
      await w.seconds(tester, 215, hr: hr, bpm: 170);
      expect(w.voice.spoken, [
        lookupAppLocalizations(const Locale('de'))
            .voiceHeartRateAbove('170', '140'),
      ]);
    });
  });

  test('keine Werte in Logs: neue Dateien ohne print, debugPrint, log', () {
    final files = [
      'lib/features/run/run_controller.dart',
      'lib/features/run/voice_texts.dart',
      'packages/adapters/lib/src/voice/method_channel_voice.dart',
      'packages/core/lib/src/guidance/guidance_announcer.dart',
      'packages/core/lib/src/guidance/guided_unit_snapshot.dart',
      'packages/core/lib/src/guidance/guidance_settings.dart',
      'packages/core/lib/src/guidance/walk_break_evidence.dart',
      'packages/core/lib/ports/voice.dart',
      'packages/core/lib/fakes/fake_voice.dart',
      'android/app/src/main/kotlin/io/github/brokoskokoli/ramuri/VoiceChannel.kt',
    ];
    final log = RegExp(
      r'\bprint\s*\(|debugPrint|developer\.log|\blog\s*\(|Log\.[dviwe]\(|println|Timber',
    );
    for (final f in files) {
      final code = File(f).readAsStringSync().replaceAll(RegExp(r'//.*'), '');
      expect(log.hasMatch(code), isFalse, reason: f);
    }
  });
}
