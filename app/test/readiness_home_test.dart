import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/readiness/readiness_service.dart';
import 'package:running_app/features/readiness/readiness_texts.dart';
import 'package:running_app/l10n/app_localizations_de.dart';
import 'package:running_app/l10n/app_localizations_en.dart';

import 'app_harness.dart';
import 'history_summary_test.dart' show seedRun;

// WP34 Teil D1: Dienst (Eingaben aus den Ports, Einwilligung) und Karte
// „Erholung“ auf „Heute“ in den vier Fällen, mit Warnsignal davor und mit
// Entwicklermodus. Alle Werte sind erfunden. Heute ist Samstag, 14.11.2026,
// mittags (Versatz 0); die Tage sind lokale Mitternächte wie in den Tests des
// Modells.

final Uint8List _appKey = Uint8List.fromList(List.filled(32, 7));
final DateTime _now = DateTime.utc(2026, 11, 14, 12);

DateTime _at(int dayIdx, int h) => DateTime(2026, 10, 17 + dayIdx, h).toUtc();

HealthRecord _hrv(int i, double v) => HealthRecord(
  kind: HealthDataKind.hrvRmssd,
  id: 'hrv$i',
  origin: 'app.a',
  start: _at(i, 3),
  end: _at(i, 3),
  value: v,
  unit: 'ms',
);

HealthRecord _rhr(int i, double v) => HealthRecord(
  kind: HealthDataKind.restingHeartRate,
  id: 'rhr$i',
  origin: 'app.a',
  start: _at(i, 7),
  end: _at(i, 7),
  value: v,
  unit: 'bpm',
);

HealthRecord _sleep(int i) => HealthRecord(
  kind: HealthDataKind.sleep,
  id: 'sl$i',
  origin: 'app.a',
  start: _at(i - 1, 22),
  end: _at(i, 6),
);

/// 29 Tage Werte (letzter = heute), [hrvDays] Tage HRV ab Tag 0.
Future<void> _seedHealth(
  StorageSession s, {
  int hrvDays = 29,
  int rhrDays = 29,
  int sleepDays = 29,
}) async {
  final h = (s as HealthStorage).health;
  await h.upsertValues([
    for (var i = 0; i < hrvDays; i++) _hrv(i, 40.0 + (i % 6) * 3),
    for (var i = 0; i < rhrDays; i++) _rhr(i, 55.0 + (i % 5) * 2),
  ]);
  await h.upsertSleep([for (var i = 29 - sleepDays; i < 29; i++) _sleep(i)]);
}

Future<void> _grant(StorageSession s, Iterable<HealthDataKind> kinds) async {
  for (final k in kinds) {
    await s.consents.set(healthSourceKey(k), ConsentState.granted, at: _now);
  }
}

const _allKinds = [
  HealthDataKind.hrvRmssd,
  HealthDataKind.restingHeartRate,
  HealthDataKind.sleep,
];

/// Health Connect mit allen Rechten, ohne neue Daten: der Import ändert den
/// Speicher nicht, und es steht keine Löschfrage (SEC-0007) offen.
class _GrantedPort implements HealthConnectPort {
  @override
  Future<HealthSdkStatus> sdkStatus() async => HealthSdkStatus.available;

  @override
  Future<Set<HealthDataKind>> grantedKinds() async =>
      HealthDataKind.values.toSet();

  @override
  Future<Set<HealthDataKind>> requestPermissions(
    Set<HealthDataKind> kinds,
  ) async => kinds;

  @override
  Future<bool> openInstall() async => false;

  @override
  Future<HealthPage> readPage({
    required HealthDataKind kind,
    required DateTime from,
    required DateTime to,
    String? pageToken,
    int? pageSize,
  }) async => const HealthPage([], null);
}

Future<StorageSession> _preopen(Device d) async {
  d.healthConnect = _GrantedPort();
  d.clock.set(_now);
  final s = await d.storage.open(_appKey);
  await s.settings.set(SettingKeys.setupDone, '1', at: DateTime.utc(2026));
  return s;
}

Finder _key(String k) => find.byKey(Key(k));
String _text(String k) => (_key(k).evaluate().single.widget as Text).data!;

/// Ein Belastungstag ohne Sperre mit [tsbPercent] (PAR-073).
LoadDay _loadDay(double tsbPercent) => LoadDay(
  day: DateTime.utc(2026, 11, 14),
  load: 40,
  atl: 30,
  ctl: 50,
  tsb: -7,
  tsbPercentMean7: tsbPercent,
  flags: const {},
  atlProvisionalReasons: const {},
  ctlProvisionalReasons: const {},
  unitCount: 1,
  ratedUnits: 1,
  convertedUnits: 0,
  unratedUnits: 0,
);

/// Zwölf geeignete Läufe (TRIMP und RPE): der Belastungsdienst würde daraus
/// beim Rechnen einen persönlichen Faktor übernehmen (FR-0097).
Future<void> _seedFactorRuns(StorageSession s) async {
  for (var i = 0; i < 12; i++) {
    final rpe = const [3, 7, 5][i % 3];
    final end = _now.subtract(Duration(days: 60 - i, hours: -8));
    final run = await s.runs.create(
      startedAt: end.subtract(const Duration(minutes: 30)),
    );
    await s.runs.setState(run.id, RunState.finished, endedAt: end);
    await s.values.createOriginals(ValueOwner.run(run.id), [
      ComputedValue(
        key: trimpRunValueKey,
        value: 2.0 * 30 * rpe,
        unit: pointsUnit,
        computedAt: _now,
        measurementCount: 1,
        sources: const [],
        method: 'edwards-trimp',
        methodVersion: 1,
        parameterVersion: 1,
        quality: ValueQuality.good,
      ),
    ]);
    await s.subjective.save(
      run.id,
      RunSubjective(rpe: rpe),
      srpe: SrpeLoad.compute(duration: const Duration(minutes: 30), rpe: rpe),
    );
  }
}

ReadinessService _service(Device d, StorageSession s) =>
    ReadinessService(session: s, clock: d.clock);

Future<void> _start(
  WidgetTester tester,
  Device d, {
  String locale = 'de',
  bool dark = false,
  double width = 411,
  double scale = 1,
}) async {
  await d.start(tester, Locale(locale));
  tester.view.physicalSize = Size(width, 2600);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  if (dark) {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
  }
  await tester.pumpAndSettle();
}

/// Morgenmessungen der Kamera an [days] Tagen bis heute (Versatz 0, 07:00),
/// Werte mit Streuung; die von heute trägt [todayBand].
MorningMeasurement _cam(int i, {int days = 29, SleepBand? todayBand}) =>
    MorningMeasurement(
      measuredAt: DateTime.utc(2026, 10, 17 + i, 7),
      utcOffset: Duration.zero,
      posture: RestingPosture.lying,
      deviceManufacturer: 'H',
      deviceModel: 'M1',
      method: 'ppg',
      methodVersion: 1,
      quality: PpgQuality.good,
      restingHrBpm: 55.0 + (i % 5) * 2,
      rmssdMs: 40.0 + (i % 6) * 3,
      timingNoiseMs: 10,
      cameraIntervalsMs: const [],
      beforeValidation: false,
      outsideWindow: false,
      sleepBand: i == days - 1 ? todayBand : null,
    );

Future<void> _seedCamera(StorageSession s, {SleepBand? todayBand}) async {
  for (var i = 0; i < 29; i++) {
    await (s as MorningStorage).morning.add(_cam(i, todayBand: todayBand));
  }
}

void main() {
  group('Dienst: Eingaben aus den Ports', () {
    testWidgets('ohne Einwilligung keine Health-Connect-Daten (SEC-0001)', (
      tester,
    ) async {
      final d = Device();
      final s = await _preopen(d);
      await _seedHealth(s);
      final snap = await _service(d, s).load();
      expect(snap.extended, isFalse);
      expect(snap.result.state, ReadinessState.insufficient);
      expect(snap.result.factors, isEmpty);
      expect(snap.result.facts, isEmpty);
    });

    testWidgets('mit Einwilligung für alle drei Arten: Zahl mit Stufe', (
      tester,
    ) async {
      final d = Device();
      final s = await _preopen(d);
      await _seedHealth(s);
      await _grant(s, _allKinds);
      final snap = await _service(d, s).load();
      expect(snap.extended, isTrue);
      expect(snap.result.state, ReadinessState.number);
      expect(snap.result.value, isNotNull);
      expect(snap.result.level, isNot(ReadinessLevel.notDeterminable));
      // Dieselbe Quelle seit 28 Tagen: kommt aus den Tageswerten, nicht 0.
      expect(
        snap.result.levelReasons.map((r) => r.code),
        isNot(contains(ReadinessLevelReasonCode.sourceTooShort)),
      );
    });

    testWidgets('Einwilligung gilt je Art: nur Ruhepuls geht ein', (
      tester,
    ) async {
      final d = Device();
      final s = await _preopen(d);
      await _seedHealth(s);
      await _grant(s, [HealthDataKind.restingHeartRate]);
      final snap = await _service(d, s).load();
      expect(snap.extended, isTrue);
      final ids = snap.result.factors.map((f) => f.id).toSet();
      expect(ids, {ReadinessFactorId.restingHeartRate});
    });

    testWidgets('Befinden des letzten Laufs und Belastung gehen ein', (
      tester,
    ) async {
      final d = Device();
      final s = await _preopen(d);
      await _seedHealth(s);
      await _grant(s, _allKinds);
      final id = await seedRun(s, _now.subtract(const Duration(days: 2)));
      await s.subjective.save(id, RunSubjective(wellbeing: 4));
      final snap = await ReadinessService(
        session: s,
        clock: d.clock,
        loadToday: () async => _loadDay(-14),
      ).load();
      final ids = snap.result.factors.map((f) => f.id).toSet();
      expect(ids, contains(ReadinessFactorId.wellbeing));
      expect(ids, contains(ReadinessFactorId.load));
    });
  });

  for (final (name, dark, locale, width, scale) in [
    ('hell, de', false, 'de', 411.0, 1.0),
    ('dunkel, en, 320 dp, Schrift 2.0', true, 'en', 320.0, 2.0),
  ]) {
    final de = locale == 'de';
    group('Karte „Erholung“ ($name)', () {
      testWidgets('Zahl: Ring, Zahl, Zustand, Stufe, Ursachen, 48 dp', (
        tester,
      ) async {
        final d = Device();
        final s = await _preopen(d);
        await _seedHealth(s);
        await _grant(s, _allKinds);
        await _start(
          tester,
          d,
          locale: locale,
          dark: dark,
          width: width,
          scale: scale,
        );
        expect(_key('readiness_card'), findsOneWidget);
        expect(_key('readiness_card_case_number'), findsOneWidget);
        expect(_key('readiness_value'), findsOneWidget);
        expect(
          _text('readiness_stage'),
          de ? 'ERHOLUNG · ERWEITERT' : 'RECOVERY · EXTENDED',
        );
        final bands = de
            ? ['Gut erholt', 'Normal belastbar', 'Erhöhte Belastung']
            : ['Well recovered', 'Normal load', 'Elevated load'];
        expect(bands, contains(_text('readiness_title')));
        expect(find.text(de ? 'geschätzt' : 'estimated'), findsOneWidget);
        // Stufe und Grund (PAR-159); keine Diagnose, kein „erholt“ im Satz.
        final body = _text('readiness_text');
        expect(body, startsWith(de ? 'Datenlage ' : 'Data basis: '));
        expect(body.contains('erholt'), isFalse);
        expect(body.toLowerCase().contains('diagnos'), isFalse);
        expect(find.text('Entwicklermodus aktiv'), findsNothing);
        await tester.ensureVisible(_key('readiness_where_from'));
        expect(
          tester.getSize(_key('readiness_where_from')).height,
          greaterThanOrEqualTo(48),
        );
        // Basis-Karte gibt es daneben nicht.
        expect(_key('home_recovery_card'), findsNothing);
        await tester.tap(_key('readiness_where_from'));
        await tester.pumpAndSettle();
        expect(_key('readiness_detail'), findsOneWidget);
        expect(_key('readiness_detail_case_number'), findsOneWidget);
        await tester.ensureVisible(_key('readiness_detail_series_link'));
        await tester.tap(_key('readiness_detail_series_link'));
        await tester.pumpAndSettle();
        expect(_key('readiness_history'), findsOneWidget);
        // Reihen der drei Einwilligungen: HRV und Ruhepuls getrennt.
        expect(_key('readiness_series_hc_hrv_0'), findsOneWidget);
        expect(_key('readiness_series_hc_restingHeartRate_1'), findsOneWidget);
      });

      testWidgets('Eingeschränkt: keine Zahl, Grund und Tatsache', (
        tester,
      ) async {
        final d = Device();
        final s = await _preopen(d);
        // HRV fehlt heute, Ruhepuls und Schlaf liegen vor.
        await _seedHealth(s, hrvDays: 28);
        await _grant(s, _allKinds);
        await _start(
          tester,
          d,
          locale: locale,
          dark: dark,
          width: width,
          scale: scale,
        );
        expect(_key('readiness_value'), findsNothing);
        expect(_key('readiness_card_case_limited'), findsOneWidget);
        expect(
          _text('readiness_title'),
          de ? 'Eingeschränkte Einschätzung' : 'Limited estimate',
        );
        expect(
          _text('readiness_text'),
          startsWith(
            de
                ? 'Heute fehlt der HRV-Wert der letzten Nacht.'
                : 'Today there is no HRV value from last night.',
          ),
        );
        // Die Tatsachen stehen auf der Karte (PAR-171K), nicht nur der Grund.
        expect(
          _text('readiness_text'),
          contains(de ? 'Ruhepuls heute' : 'Resting heart rate today'),
        );
        expect(
          _text('readiness_text'),
          contains(de ? 'rund 8 Stunden geschlafen' : 'slept about 8 hours'),
        );
        expect(
          _text('readiness_stage'),
          de ? 'ERHOLUNG · ERWEITERT' : 'RECOVERY · EXTENDED',
        );
      });

      testWidgets('Unzureichend: keine Zahl, fester Satz', (tester) async {
        final d = Device();
        final s = await _preopen(d);
        await _grant(s, _allKinds);
        await _start(
          tester,
          d,
          locale: locale,
          dark: dark,
          width: width,
          scale: scale,
        );
        expect(_key('readiness_value'), findsNothing);
        expect(_key('readiness_card_case_insufficient'), findsOneWidget);
        expect(
          _text('readiness_title'),
          de ? 'Unzureichende Daten' : 'Insufficient data',
        );
        expect(
          _text('readiness_text'),
          de
              ? 'Heute liegen weder Schlaf noch eine frische Messung vor.'
              : 'Today there is neither sleep data nor a fresh measurement.',
        );
      });

      testWidgets('Basis: ohne Gesundheitsdaten nur Text, Stufe erkennbar', (
        tester,
      ) async {
        final d = Device();
        final s = await _preopen(d);
        // Daten da, aber keine Einwilligung: es gibt keine Zahl.
        await _seedHealth(s);
        final id = await seedRun(s, _now.subtract(const Duration(days: 1)));
        await s.subjective.save(id, RunSubjective(wellbeing: 1));
        await _start(
          tester,
          d,
          locale: locale,
          dark: dark,
          width: width,
          scale: scale,
        );
        expect(_key('readiness_card'), findsNothing);
        expect(_key('home_recovery_card'), findsOneWidget);
        expect(
          find.text(de ? 'ERHOLUNG · BASIS' : 'RECOVERY · BASIC'),
          findsOneWidget,
        );
        expect(
          _text('readiness_basis_note'),
          de
              ? 'Ohne Gesundheitsdaten zeigt ramuri nur Hinweise, keine Zahl '
                    'und keinen Zustand.'
              : 'Without health data, ramuri only shows notes, no number and '
                    'no state.',
        );
      });
    });
  }

  group('Heute schreibt nichts, Basisstufe (Nachbesserung Runde 2)', () {
    testWidgets('Öffnen von Heute übernimmt keinen Belastungsfaktor', (
      tester,
    ) async {
      final d = Device();
      final s = await _preopen(d);
      await _seedHealth(s);
      await _grant(s, _allKinds);
      await _seedFactorRuns(s);
      await _start(tester, d);
      expect(_key('readiness_card'), findsOneWidget);
      // Der Belastungsdienst würde den Faktor beim Rechnen übernehmen und
      // speichern; Heute liest nur.
      expect(await LoadSettings.factor(s.settings), isNull);
      expect(await LoadSettings.pendingFactor(s.settings), isNull);
    });

    testWidgets(
      'Entwicklermodus ohne Messung und ohne Einwilligung: Basisstufe',
      (tester) async {
        final d = Device();
        final s = await _preopen(d);
        await SettingsDeveloperModeStore(s.settings, d.clock).set(true);
        final snap = await _service(d, s).load();
        expect(snap.developerMode, isTrue);
        expect(snap.extended, isFalse);
        await _start(tester, d);
        expect(_key('readiness_card'), findsNothing);
      },
    );

    testWidgets('Messung gespeichert, Entwicklermodus aus: Basisstufe (K62)', (
      tester,
    ) async {
      final d = Device();
      final s = await _preopen(d);
      await _seedCamera(s);
      final id = await seedRun(s, _now.subtract(const Duration(days: 1)));
      await s.subjective.save(id, RunSubjective(wellbeing: 1));
      final snap = await _service(d, s).load();
      expect(snap.developerMode, isFalse);
      expect(snap.extended, isFalse);
      await _start(tester, d);
      expect(_key('readiness_card'), findsNothing);
      expect(_key('home_recovery_card'), findsOneWidget);
      expect(find.text('ERHOLUNG · BASIS'), findsOneWidget);
    });

    testWidgets(
      'Kamerapfad: Morgenmessungen gehen bis in den Faktor (Dienst, K62)',
      (tester) async {
        final d = Device();
        final s = await _preopen(d);
        await SettingsDeveloperModeStore(s.settings, d.clock).set(true);
        await _seedCamera(s, todayBand: SleepBand.from7to8);
        final snap = await _service(d, s).load();
        expect(snap.extended, isTrue);
        final r = snap.result;
        // Kamerareihen sind eingegangen: HRV und Ruhepuls mit Quelle Kamera.
        expect(r.state, isNot(ReadinessState.insufficient));
        final cam = r.factors
            .where((f) => f.source == ReadinessFactorSource.camera)
            .map((f) => f.id)
            .toSet();
        expect(cam, contains(ReadinessFactorId.hrv));
        expect(cam, contains(ReadinessFactorId.restingHeartRate));
        // Die Schlafstufe der heutigen Messung geht als Selbstangabe ein.
        expect(r.factors.map((f) => f.id), contains(ReadinessFactorId.sleep));
        expect(
          r.factors.firstWhere((f) => f.id == ReadinessFactorId.sleep).source,
          ReadinessFactorSource.selfReport,
        );
      },
    );

    testWidgets(
      'markierte Kamera-Tatsachen stehen auf der Karte mit Markierung (PAR-171K)',
      (tester) async {
        final d = Device();
        final s = await _preopen(d);
        await _seedCamera(s);
        // Morgenmessung freigeschaltet (RMSSD liegend bestanden), aber ohne
        // Opt-in und mit „nicht bestandenem“ Ruhepuls: beide Kamerareihen sind
        // gesperrt und nur markierte Tatsachen (nie in der Zahl).
        final service = ReadinessService(
          session: s,
          clock: d.clock,
          validationState: const {
            ValidationQuantity.restingHr: ValidationState.failed,
            ValidationQuantity.lnRmssdSupine: ValidationState.passed,
            ValidationQuantity.lnRmssdSitting: ValidationState.notChecked,
          },
        );
        final snap = await service.load();
        expect(snap.result.state, ReadinessState.limited);
        expect(snap.result.markedFacts, hasLength(2));
        for (final l in [AppLocalizationsDe(), AppLocalizationsEn()]) {
          final text = readinessCardText(l, snap.result);
          for (final f in snap.result.markedFacts) {
            expect(
              text,
              contains(readinessFactText(l, f).replaceAll(RegExp(r'\.$'), '')),
            );
            expect(text, contains(readinessMarkText(l, f.mark)!));
          }
        }
      },
    );

    testWidgets('Entwicklermodus mit gespeicherter Messung: erweiterte Stufe', (
      tester,
    ) async {
      final d = Device();
      final s = await _preopen(d);
      await SettingsDeveloperModeStore(s.settings, d.clock).set(true);
      await (s as MorningStorage).morning.add(
        MorningMeasurement(
          measuredAt: _now.subtract(const Duration(hours: 5)),
          utcOffset: Duration.zero,
          posture: RestingPosture.lying,
          deviceManufacturer: 'H',
          deviceModel: 'M1',
          method: 'ppg',
          methodVersion: 1,
          quality: PpgQuality.good,
          restingHrBpm: 58,
          rmssdMs: 42,
          timingNoiseMs: 10,
          cameraIntervalsMs: const [],
          beforeValidation: false,
          outsideWindow: false,
        ),
      );
      final snap = await _service(d, s).load();
      expect(snap.extended, isTrue);
      // Die Kamerareihe steht für den Verlauf bereit (HRV und Ruhepuls).
      expect(snap.series.map((r) => r.source).toSet(), {
        ReadinessSource.camera,
      });
      expect(snap.series, hasLength(2));
      expect(snap.series.first.byDay, isNotEmpty);
    });

    testWidgets(
      'Verlauf: Kamerareihe ohne Zulassung nicht, HC je Einwilligung',
      (tester) async {
        final d = Device();
        final s = await _preopen(d);
        await _seedHealth(s);
        await _grant(s, [HealthDataKind.hrvRmssd]);
        // Gespeicherte Messung, aber kein Entwicklermodus und nicht freigegeben.
        await (s as MorningStorage).morning.add(
          MorningMeasurement(
            measuredAt: _now.subtract(const Duration(hours: 5)),
            utcOffset: Duration.zero,
            posture: RestingPosture.lying,
            deviceManufacturer: 'H',
            deviceModel: 'M1',
            method: 'ppg',
            methodVersion: 1,
            quality: PpgQuality.good,
            restingHrBpm: 58,
            rmssdMs: 42,
            timingNoiseMs: 10,
            cameraIntervalsMs: const [],
            beforeValidation: false,
            outsideWindow: false,
          ),
        );
        final snap = await _service(d, s).load();
        // Nur die eingewilligte HRV aus Health Connect, kein Ruhepuls, keine
        // Kamera (SEC-0001, K62 Punkt 1).
        expect(snap.series.map((r) => (r.source, r.factor)), [
          (ReadinessSource.healthConnect, ReadinessFactor.hrv),
        ]);
      },
    );
  });

  group('Warnsignal und Entwicklermodus', () {
    testWidgets('Warnsignal steht vor der Einschätzung', (tester) async {
      final d = Device();
      final s = await _preopen(d);
      await _seedHealth(s);
      await _grant(s, _allKinds);
      await (s as WarningStorage).warning.set(
        WarningSignal(
          reportedOn: DateTime.utc(2026, 11, 13),
          source: WarningSource.manual,
        ),
      );
      await _start(tester, d);
      expect(_key('home_recovery_card'), findsOneWidget);
      expect(_key('readiness_card'), findsOneWidget);
      expect(
        tester.getTopLeft(_key('home_recovery_card')).dy,
        lessThan(tester.getTopLeft(_key('readiness_card')).dy),
      );
      expect(
        find.textContaining('Diese App stellt keine Diagnose'),
        findsOneWidget,
      );
    });

    testWidgets('Entwicklermodus an: nur der Hinweis, Zahl unverändert', (
      tester,
    ) async {
      final off = Device();
      final so = await _preopen(off);
      await _seedHealth(so);
      await _grant(so, _allKinds);
      final base = await _service(off, so).load();
      expect(base.developerMode, isFalse);

      final d = Device();
      final s = await _preopen(d);
      await _seedHealth(s);
      await _grant(s, _allKinds);
      await SettingsDeveloperModeStore(s.settings, d.clock).set(true);
      final dev = await _service(d, s).load();
      expect(dev.developerMode, isTrue);
      // Keine Kennzeichnung, keine andere Zahl (K62 Punkt 6).
      expect(dev.result.value, base.result.value);
      expect(dev.result.level, base.result.level);
      await _start(tester, d);
      // Der Hinweis steht einmal (Karte der Morgenmessung, WP33).
      expect(find.text('Entwicklermodus aktiv'), findsOneWidget);
      expect(_key('readiness_value'), findsOneWidget);
    });

    testWidgets('Entwicklermodus ohne Gesundheitsdaten: keine Zahl', (
      tester,
    ) async {
      final d = Device();
      final s = await _preopen(d);
      await SettingsDeveloperModeStore(s.settings, d.clock).set(true);
      await _start(tester, d);
      expect(_key('readiness_value'), findsNothing);
      expect(find.text('Entwicklermodus aktiv'), findsOneWidget);
    });
  });
}
