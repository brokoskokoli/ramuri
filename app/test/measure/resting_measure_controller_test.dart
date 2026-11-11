import 'dart:async';

import 'package:running_app/features/measure/resting_measure_controller.dart';
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'measure_support.dart';

// Alle Werte synthetisch. Messfenster: Einschwingen bis 5 s, Auswertung bis 65 s,
// Daten bis 66,5 s (ppgStandardWindow).

class Rig {
  Rig._(this.cam, this.session, this.clock, this.profile, this.signal, this.c);

  final HoldingCamera cam;
  final StorageSession session;
  final FakeClock clock;
  final SpyProfileService profile;
  final RecordingSignal signal;
  final RestingMeasureController c;

  static Future<Rig> make({PpgEvaluate? evaluate, ProfileRecord? start}) async {
    final cam = HoldingCamera();
    final session = await FakeStorage().open(testKey);
    final clock = FakeClock(DateTime.utc(2026, 11, 10, 7, 0));
    if (start != null) await session.profile.save(start);
    final profile = SpyProfileService(
      session.profile,
      clock,
      settings: session.settings,
    );
    final signal = RecordingSignal();
    final c = RestingMeasureController(
      camera: cam,
      profile: profile,
      settings: session.settings,
      clock: clock,
      signal: signal,
      evaluate: evaluate ?? evalFinalOnly,
      autoTick: false,
    );
    return Rig._(cam, session, clock, profile, signal, c);
  }

  /// Misst sofort und spielt eine vollständige Aufnahme ein.
  Future<FrameSource> measureFully({bool weak = false}) async {
    await c.startNow();
    final src = FrameSource(weak: weak);
    await src.emitUntil(cam, 66.6);
    await pump();
    return src;
  }
}

void main() {
  group('Ruhephase', () {
    test('Vorgabe 5 min, einstellbar von 1 bis 15 min', () async {
      final r = await Rig.make();
      expect(r.c.restMinutes, 5);
      r.c.setRestMinutes(0);
      expect(r.c.restMinutes, 1);
      r.c.setRestMinutes(99);
      expect(r.c.restMinutes, 15);
      r.c.setRestMinutes(7);
      expect(r.c.restMinutes, 7);
    });

    test(
      'keine Kamera und kein Recht vor Ende der Ruhephase; Signal am Ende',
      () async {
        final r = await Rig.make();
        r.c.setRestMinutes(2);
        r.c.startRest();
        expect(r.c.phase, RestingMeasurePhase.resting);
        r.clock.advance(const Duration(seconds: 30));
        r.c.tick();
        expect(r.c.restRemaining, const Duration(seconds: 90));
        expect(r.cam.permissionRequests, 0);
        expect(r.cam.startCount, 0);
        expect(r.signal.calls, 0);
        r.clock.advance(const Duration(seconds: 90));
        r.c.tick();
        await pump();
        expect(r.signal.calls, 1);
        expect(r.cam.permissionRequests, 1);
        expect(r.cam.startCount, 1);
        expect(r.c.phase, RestingMeasurePhase.measuring);
        r.c.tick(); // weitere Ticks lösen nichts mehr aus
        expect(r.signal.calls, 1);
        expect(r.cam.permissionRequests, 1);
      },
    );

    test('vorzeitig messen: Ruhephase wird mit Dauer festgehalten', () async {
      final r = await Rig.make();
      r.c.startRest();
      r.clock.advance(const Duration(seconds: 100));
      await r.c.skipRest();
      expect(r.c.phase, RestingMeasurePhase.measuring);
      await FrameSource().emitUntil(r.cam, 66.6);
      await pump();
      expect(r.c.result!.restElapsed, const Duration(seconds: 100));
      expect(r.signal.calls, 0);
    });

    test('sofort messen: keine Ruhephase im Ergebnis', () async {
      final r = await Rig.make();
      await r.measureFully();
      expect(r.c.result!.restElapsed, isNull);
    });

    test('Haltung und Dauer nur im Einstieg änderbar', () async {
      final r = await Rig.make();
      r.c.setPosture(RestingPosture.lying);
      r.c.startRest();
      r.c.setPosture(RestingPosture.sitting);
      r.c.setRestMinutes(9);
      expect(r.c.posture, RestingPosture.lying);
      expect(r.c.restMinutes, 5);
    });
  });

  group('Kamera-Recht und Start', () {
    test('Doppelstart fragt das Recht nur einmal und startet einmal', () async {
      final r = await Rig.make();
      await Future.wait([r.c.startNow(), r.c.startNow(), r.c.retry()]);
      expect(r.cam.permissionRequests, 1);
      expect(r.cam.startCount, 1);
    });

    test('Abbruch während der Rechteanfrage startet keine Kamera', () async {
      final r = await Rig.make();
      r.cam.hold = Completer<PpgCameraAvailability>();
      final f = r.c.startNow();
      await pump();
      expect(r.c.phase, RestingMeasurePhase.starting);
      await r.c.cancel();
      r.cam.hold!.complete(PpgCameraAvailability.available);
      await f;
      expect(r.cam.startCount, 0);
      expect(r.c.phase, RestingMeasurePhase.stopped);
      expect(r.c.stopCause, RestingStopCause.userCancelled);
    });

    test(
      'Hintergrund während der Rechteanfrage: kein Start, Grund Hintergrund',
      () async {
        final r = await Rig.make();
        r.cam.hold = Completer<PpgCameraAvailability>();
        final f = r.c.startNow();
        await pump();
        await r.c.onBackground();
        r.cam.hold!.complete(PpgCameraAvailability.available);
        await f;
        expect(r.cam.startCount, 0);
        expect(r.c.stopCause, RestingStopCause.background);
      },
    );

    test('Recht verweigert, keine Kamera, kein Blitz: Endzustand mit Grund, kein „Noch einmal“', () async {
      for (final (a, cause) in [
        (
          PpgCameraAvailability.permissionDenied,
          RestingStopCause.permissionDenied,
        ),
        (PpgCameraAvailability.noCamera, RestingStopCause.noCamera),
        (PpgCameraAvailability.noFlash, RestingStopCause.noFlash),
      ]) {
        final r = await Rig.make();
        r.cam.availabilityState = a;
        await r.c.startNow();
        expect(r.c.phase, RestingMeasurePhase.stopped);
        expect(r.c.stopCause, cause);
        expect(r.c.canRetry, isFalse);
        expect(r.cam.startCount, 0);
        expect(r.cam.torchOn, isFalse);
      }
    });
  });

  group('Messung', () {
    test(
      'Einschwingen, Fortschritt und laufender Puls kommen aus der Auswertung',
      () async {
        final r = await Rig.make(
          evaluate: (f, w) async => evaluatePpg(f, window: w),
        );
        await r.c.startNow();
        final src = FrameSource();
        await src.emitUntil(r.cam, 2);
        expect(r.c.settling, isTrue);
        expect(r.c.progress, 0);
        expect(r.c.livePulse, isNull);
        await src.emitUntil(r.cam, 35);
        await pump();
        expect(r.c.settling, isFalse);
        expect(r.c.progress, closeTo(0.5, 0.02));
        expect(r.c.curve, isNotEmpty);
        expect(r.c.curve.length, lessThanOrEqualTo(30 * 5 + 2));
        expect(r.c.livePulse, isNotNull);
        expect(
          r.c.livePulse!,
          inInclusiveRange(66, 75),
        ); // synthetisch ca. 70,6
        expect(r.c.phase, RestingMeasurePhase.measuring);
      },
    );

    test('Ende nach dem Messfenster: Ergebnis mit Wert, Kamera gestoppt, Zeitpunkt', () async {
      final r = await Rig.make();
      await r.measureFully();
      expect(r.c.phase, RestingMeasurePhase.result);
      final res = r.c.result!;
      expect(res.hasValue, isTrue);
      expect(res.bpm!, inInclusiveRange(66, 75));
      expect(res.quality, isNot(PpgQuality.unusable));
      expect(res.measuredAt, r.clock.now());
      expect(r.cam.torchOn, isFalse);
      expect(r.cam.stopCount, greaterThan(0));
      expect(r.c.canRetry, isFalse); // mit Wert nur Übernehmen oder Verwerfen
      expect(r.c.canAdopt, isTrue);
    });

    test(
      'schlechtes Signal: die Uhr läuft weiter, am Ende kein Wert mit Grund',
      () async {
        final r = await Rig.make();
        await r.c.startNow();
        final src = FrameSource(weak: true);
        await src.emitUntil(r.cam, 40);
        expect(r.c.phase, RestingMeasurePhase.measuring);
        expect(r.c.progress, closeTo(35 / 60, 0.02));
        await src.emitUntil(r.cam, 66.6);
        await pump();
        expect(r.c.phase, RestingMeasurePhase.result);
        expect(r.c.result!.hasValue, isFalse);
        expect(r.c.result!.reasons, isNotEmpty);
        expect(r.c.canRetry, isTrue);
        expect(r.c.canAdopt, isFalse);
        expect(r.cam.torchOn, isFalse);
      },
    );

    test(
      '„Noch einmal“ ohne neue Ruhephase und ohne Signal; danach Wert',
      () async {
        final r = await Rig.make();
        r.c.startRest();
        r.clock.advance(const Duration(minutes: 5));
        r.c.tick();
        await pump();
        await FrameSource(weak: true).emitUntil(r.cam, 66.6);
        await pump();
        expect(r.c.result!.hasValue, isFalse);
        final signals = r.signal.calls;
        await r.c.retry();
        expect(r.c.phase, RestingMeasurePhase.measuring);
        expect(r.c.result, isNull);
        expect(r.signal.calls, signals);
        expect(r.cam.startCount, 2);
        await FrameSource().emitUntil(r.cam, 66.6);
        await pump();
        expect(r.c.result!.hasValue, isTrue);
        expect(r.c.result!.restElapsed, const Duration(minutes: 5));
      },
    );

    test('Hinweise nur aus den Gründen der Auswertung', () async {
      var reasons = [PpgQualityReason.weakSignal];
      var quality = PpgQuality.unusable;
      final r = await Rig.make(
        evaluate: (f, w) async => PpgMeasurement(
          quality: quality,
          reasons: reasons,
          bpm: quality == PpgQuality.unusable ? null : 70,
        ),
      );
      await r.c.startNow();
      final src = FrameSource();
      await src.emitUntil(r.cam, 8);
      await pump();
      expect(r.c.liveHint, RestingLiveHint.weakSignal);
      expect(r.c.livePulse, isNull);
      reasons = [PpgQualityReason.flatSignal];
      await src.emitUntil(r.cam, 10);
      await pump();
      expect(r.c.liveHint, RestingLiveHint.flatSignal);
      reasons = [PpgQualityReason.tooManyDisturbances];
      await src.emitUntil(r.cam, 12);
      await pump();
      expect(r.c.liveHint, RestingLiveHint.disturbances);
      reasons = [PpgQualityReason.insufficientData];
      await src.emitUntil(r.cam, 14);
      await pump();
      expect(r.c.liveHint, isNull);
      quality = PpgQuality.limited;
      reasons = [PpgQualityReason.lowSignalQuality];
      await src.emitUntil(r.cam, 16);
      await pump();
      expect(r.c.liveHint, isNull);
      expect(r.c.livePulse, 70);
      expect(r.c.liveQuality, PpgQuality.limited);
    });
  });

  group('Abbruch, Hintergrund, Kamerafehler: Kamera gestoppt', () {
    test('Abbruch während der Messung', () async {
      final r = await Rig.make();
      await r.c.startNow();
      await FrameSource().emitUntil(r.cam, 10);
      expect(r.cam.torchOn, isTrue);
      await r.c.cancel();
      expect(r.cam.torchOn, isFalse);
      expect(r.c.phase, RestingMeasurePhase.stopped);
      expect(r.c.stopCause, RestingStopCause.userCancelled);
      expect(r.c.canRetry, isFalse);
      // Späte Bilder ändern nichts mehr.
      r.cam.emitFrame(FrameSource().next());
      await pump();
      expect(r.c.phase, RestingMeasurePhase.stopped);
    });

    test('Abbruch in der Ruhephase: nie eine Kamera gestartet', () async {
      final r = await Rig.make();
      r.c.startRest();
      await r.c.cancel();
      expect(r.c.stopCause, RestingStopCause.userCancelled);
      r.clock.advance(const Duration(minutes: 6));
      r.c.tick();
      await pump();
      expect(r.cam.startCount, 0);
      expect(r.signal.calls, 0);
    });

    test('Hintergrund während der Messung', () async {
      final r = await Rig.make();
      await r.c.startNow();
      await FrameSource().emitUntil(r.cam, 10);
      await r.c.onBackground();
      expect(r.cam.torchOn, isFalse);
      expect(r.c.stopCause, RestingStopCause.background);
      expect(r.c.canRetry, isTrue);
    });

    test('Hintergrund-Abbruch der Kamera selbst (Ereignis Stopped)', () async {
      final r = await Rig.make();
      await r.c.startNow();
      await FrameSource().emitUntil(r.cam, 10);
      await r.cam.abort(PpgCameraStopReason.background);
      await pump();
      expect(r.c.stopCause, RestingStopCause.background);
      expect(r.cam.torchOn, isFalse);
    });

    test('Kamera getrennt oder belegt mitten in der Messung', () async {
      for (final (reason, cause) in [
        (PpgCameraStopReason.disconnected, RestingStopCause.disconnected),
        (PpgCameraStopReason.busy, RestingStopCause.busy),
        (PpgCameraStopReason.frameRate, RestingStopCause.frameRate),
        (PpgCameraStopReason.error, RestingStopCause.cameraError),
      ]) {
        final r = await Rig.make();
        await r.c.startNow();
        await FrameSource().emitUntil(r.cam, 10);
        await r.cam.abort(reason);
        await pump();
        expect(r.c.phase, RestingMeasurePhase.stopped, reason: '$reason');
        expect(r.c.stopCause, cause);
        expect(r.cam.torchOn, isFalse);
        expect(r.c.canRetry, isTrue);
      }
    });

    test('Strom endet ohne Ereignis: Fehler, keine hängende Messung', () async {
      final r = await Rig.make();
      await r.c.startNow();
      await r.cam.stop(); // beendet den Strom ohne Stopped
      await pump();
      expect(r.c.stopCause, RestingStopCause.cameraError);
    });

    test('Auswertung scheitert: Endzustand statt Absturz', () async {
      final r = await Rig.make(evaluate: (f, w) => throw StateError('x'));
      await r.measureFully();
      expect(r.c.phase, RestingMeasurePhase.stopped);
      expect(r.c.stopCause, RestingStopCause.cameraError);
      expect(r.cam.torchOn, isFalse);
    });

    test(
      'Ruhephase läuft im Hintergrund weiter; Messung erst bei Rückkehr',
      () async {
        final r = await Rig.make();
        r.c.startRest();
        await r.c.onBackground();
        expect(r.c.phase, RestingMeasurePhase.resting);
        r.clock.advance(const Duration(minutes: 5));
        r.c.tick();
        await pump();
        expect(r.signal.calls, 1);
        expect(r.c.waitingForForeground, isTrue);
        expect(r.cam.permissionRequests, 0);
        expect(r.cam.startCount, 0);
        await r.c.onForeground();
        await pump();
        expect(r.c.phase, RestingMeasurePhase.measuring);
        expect(r.cam.startCount, 1);
        expect(r.signal.calls, 1);
      },
    );

    test('dispose stoppt eine laufende Kamera', () async {
      final r = await Rig.make();
      await r.c.startNow();
      await FrameSource().emitUntil(r.cam, 10);
      r.c.dispose();
      await pump();
      expect(r.cam.torchOn, isFalse);
    });
  });

  group('Bildlücke (Maintainer 2026-11-11: höchstens 1 s)', () {
    test(
      'länger als 1 s kein Bild: Messung unterbrochen, Kamera gestoppt',
      () async {
        final r = await Rig.make();
        await r.c.startNow();
        final src = FrameSource();
        await src.emitUntil(r.cam, 10);
        r.clock.advance(const Duration(milliseconds: 1000));
        r.c.checkFrameGap(); // genau 1 s ist erlaubt
        await pump();
        expect(r.c.phase, RestingMeasurePhase.measuring);
        r.clock.advance(const Duration(milliseconds: 1));
        r.c.checkFrameGap();
        await pump();
        expect(r.c.phase, RestingMeasurePhase.stopped);
        expect(r.c.stopCause, RestingStopCause.interrupted);
        expect(r.cam.torchOn, isFalse);
        expect(r.c.canRetry, isTrue);
      },
    );

    test('Bilder setzen die Frist zurück', () async {
      final r = await Rig.make();
      await r.c.startNow();
      final src = FrameSource();
      for (var t = 1.0; t <= 6; t++) {
        await src.emitUntil(r.cam, t);
        r.clock.advance(const Duration(milliseconds: 900));
        r.c.checkFrameGap();
      }
      await pump();
      expect(r.c.phase, RestingMeasurePhase.measuring);
    });

    test('nach dem Start kommt gar kein Bild', () async {
      final r = await Rig.make();
      await r.c.startNow();
      await pump();
      r.clock.advance(const Duration(milliseconds: 1500));
      r.c.checkFrameGap();
      await pump();
      expect(r.c.stopCause, RestingStopCause.interrupted);
      expect(r.cam.torchOn, isFalse);
    });

    test('Lücke in der Sensorzeit zwischen zwei Bildern', () async {
      final r = await Rig.make();
      await r.c.startNow();
      final src = FrameSource();
      await src.emitUntil(r.cam, 10);
      final late = FrameSource()..emitSkip(30 * 12);
      r.cam.emitFrame(late.next());
      await pump();
      expect(r.c.stopCause, RestingStopCause.interrupted);
      expect(r.cam.torchOn, isFalse);
    });

    test(
      'keine Prüfung während der Auswertung oder in der Ruhephase',
      () async {
        final r = await Rig.make();
        r.c.startRest();
        r.clock.advance(const Duration(minutes: 1));
        r.c.checkFrameGap();
        expect(r.c.phase, RestingMeasurePhase.resting);
        await r.cam.stop();
      },
    );
  });

  group('Übernahme nur auf Bestätigung', () {
    test('ohne Bestätigung bleibt das Profil unberührt', () async {
      final r = await Rig.make(
        start: const ProfileRecord(restingHeartRateBpm: 64, birthYear: 1986),
      );
      await r.measureFully();
      expect(r.c.result!.hasValue, isTrue);
      expect(r.profile.saves, 0);
      expect((await r.session.profile.read()).restingHeartRateBpm, 64);
      expect(await RestingHrOrigin.read(r.session.settings), isNull);
      expect(await r.session.settings.all(), isEmpty);
    });

    test('Übernehmen: Wert über den Profildienst, übrige Felder bleiben, Herkunft gespeichert', () async {
      final r = await Rig.make(
        start: const ProfileRecord(
          restingHeartRateBpm: 64,
          birthYear: 1986,
          maxHeartRateBpm: 190,
          weeklyRunMinutes: 120,
        ),
      );
      r.c.setPosture(RestingPosture.lying);
      await r.measureFully();
      final bpm = r.c.result!.bpm!;
      expect(r.c.previousRestingBpm, 64);
      expect(r.c.previousOrigin, isNull);
      expect(await r.c.adopt(), isTrue);
      expect(r.c.phase, RestingMeasurePhase.adopted);
      expect(r.profile.saves, 1);
      final p = await r.session.profile.read();
      expect(p.restingHeartRateBpm, bpm);
      expect(p.birthYear, 1986);
      expect(p.maxHeartRateBpm, 190);
      expect(p.weeklyRunMinutes, 120);
      final o = (await RestingHrOrigin.read(r.session.settings))!;
      expect(o.posture, RestingPosture.lying);
      expect(o.measuredAt, r.c.result!.measuredAt);
      expect(o.source, RestingHrSource.camera);
      expect(await r.c.adopt(), isFalse); // nicht doppelt
      expect(r.profile.saves, 1);
    });

    test('Verwerfen speichert nichts', () async {
      final r = await Rig.make(
        start: const ProfileRecord(restingHeartRateBpm: 64),
      );
      await r.measureFully();
      r.c.discard();
      expect(r.c.phase, RestingMeasurePhase.discarded);
      expect(await r.c.adopt(), isFalse);
      expect(r.profile.saves, 0);
      expect((await r.session.profile.read()).restingHeartRateBpm, 64);
      expect(await r.session.settings.all(), isEmpty);
    });

    test('ohne Wert gibt es nichts zu übernehmen', () async {
      final r = await Rig.make();
      await r.measureFully(weak: true);
      expect(await r.c.adopt(), isFalse);
      r.c.discard();
      expect(r.c.phase, RestingMeasurePhase.result);
      expect(r.profile.saves, 0);
    });

    test(
      'Prüfung des Profils lehnt ab: nichts gespeichert, Ergebnis bleibt',
      () async {
        final r = await Rig.make(
          start: const ProfileRecord(restingHeartRateBpm: 64),
          evaluate: (f, w) async => const PpgMeasurement(
            quality: PpgQuality.good,
            reasons: [],
            bpm: 300,
          ),
        );
        await r.measureFully();
        expect(await r.c.adopt(), isFalse);
        expect(r.c.adoptRejection, isNotNull);
        expect(r.c.phase, RestingMeasurePhase.result);
        expect((await r.session.profile.read()).restingHeartRateBpm, 64);
        expect(await r.session.settings.all(), isEmpty);
      },
    );

    test('Herkunft einer früheren Messung wird beim Ergebnis angezeigt und bei neuem Wert ersetzt', () async {
      final r = await Rig.make();
      await r.measureFully();
      await r.c.adopt();
      final first = (await RestingHrOrigin.read(r.session.settings))!;
      r.clock.advance(const Duration(days: 1));
      final c2 = RestingMeasureController(
        camera: r.cam,
        profile: r.profile,
        settings: r.session.settings,
        clock: r.clock,
        evaluate: evalFinalOnly,
        autoTick: false,
      )..setPosture(RestingPosture.lying);
      await c2.startNow();
      await FrameSource().emitUntil(r.cam, 66.6);
      await pump();
      expect(c2.previousOrigin!.measuredAt, first.measuredAt);
      expect(c2.previousOrigin!.posture, RestingPosture.sitting);
      await c2.adopt();
      final second = (await RestingHrOrigin.read(r.session.settings))!;
      expect(second.posture, RestingPosture.lying);
      expect(second.measuredAt.isAfter(first.measuredAt), isTrue);
    });

    test('manuelle Änderung danach entfernt die Herkunft', () async {
      final r = await Rig.make();
      await r.measureFully();
      await r.c.adopt();
      expect(await RestingHrOrigin.read(r.session.settings), isNotNull);
      final p = await r.profile.load();
      await r.profile.save(
        ProfileRecord(restingHeartRateBpm: p.restingHeartRateBpm! + 3),
      );
      expect(await RestingHrOrigin.read(r.session.settings), isNull);
    });
  });
}
