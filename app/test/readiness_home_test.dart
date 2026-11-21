import 'dart:async';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/home/home_recovery.dart';
import 'package:running_app/features/home/home_screen.dart';
import 'package:running_app/features/measure/morning_trend_screen.dart';
import 'package:running_app/features/readiness/readiness_service.dart';
import 'package:running_app/features/readiness/readiness_texts.dart';
import 'package:running_app/l10n/app_localizations_de.dart';
import 'package:running_app/l10n/app_localizations_en.dart';

import 'app_harness.dart';
import 'history_summary_test.dart' show seedRun;
import 'support/settle_storage.dart';

// WP34 Teil D1: Dienst (Eingaben aus den Ports, Einwilligung) und Karte
// „Erholung“ auf „Heute“ in den vier Fällen, mit Warnsignal davor und mit
// Entwicklermodus. Alle Werte sind erfunden. Heute ist Samstag, 14.11.2026,
// mittags Ortszeit (Versatz der Zone des Prozesses); die Tage sind lokale
// Mitternächte wie in den Tests des Modells.

final Uint8List _appKey = Uint8List.fromList(List.filled(32, 7));
// Mittag Ortszeit; die Uhr trägt den Versatz der Zeitzone des Prozesses, wie
// die echte Uhr (die Tage bildet localDayRanges in derselben Zone).
final DateTime _now = DateTime(2026, 11, 14, 12).toUtc();
final Duration _offset = _now.toLocal().timeZoneOffset;

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
  _GrantedPort({this.granted});

  /// Erteilte Rechte; `null` = alle. Leer: Recht fehlt, die Löschfrage steht an.
  final Set<HealthDataKind>? granted;

  @override
  Future<HealthSdkStatus> sdkStatus() async => HealthSdkStatus.available;

  @override
  Future<Set<HealthDataKind>> grantedKinds() async =>
      granted ?? HealthDataKind.values.toSet();

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

/// Wie [_GrantedPort], aber das Lesen wartet, bis der Test [release] ruft:
/// ein verzögerter Import beim Öffnen von „Heute“.
class _HeldPort extends _GrantedPort {
  final Completer<void> _gate = Completer<void>();
  int reads = 0;
  bool get released => _gate.isCompleted;
  void release() {
    if (!_gate.isCompleted) _gate.complete();
  }

  @override
  Future<HealthPage> readPage({
    required HealthDataKind kind,
    required DateTime from,
    required DateTime to,
    String? pageToken,
    int? pageSize,
  }) async {
    reads++;
    await _gate.future;
    return const HealthPage([], null);
  }
}

Future<StorageSession> _preopen(
  Device d, {
  Set<HealthDataKind>? granted,
}) async {
  d.healthConnect = _GrantedPort(granted: granted);
  d.clock.set(_now);
  d.clock.utcOffset = _offset;
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

/// Hält die Übergabe des [call]-ten Ladelaufs der Erholung auf „Heute“ zurück
/// ([HomeScreen.debugWrapReadiness]), bis der Test [release] ruft. Der Lauf
/// rechnet sofort; nur sein Ergebnis wartet. Setzt den Haken beim Abbau zurück.
class _ReadinessHold {
  _ReadinessHold(this.call) {
    HomeScreen.debugWrapReadiness = (n, load) {
      calls = n;
      if (n != call) return load;
      load.then(
        (_) => loaded.complete(true),
        onError: (Object _) {
          loaded.complete(false);
        },
      );
      return _gate.future.then((_) => load);
    };
    addTearDown(() => HomeScreen.debugWrapReadiness = null);
  }

  final int call;
  final Completer<void> _gate = Completer<void>();

  /// Ergebnis des zurückgehaltenen Laufs liegt vor (`false` bei Fehler).
  final Completer<bool> loaded = Completer<bool>();
  int calls = 0;

  /// Lauf [call] hat begonnen und ist noch nicht freigegeben.
  bool get held => calls >= call && !_gate.isCompleted;
  void release() => _gate.complete();
}

/// Beantwortet die offenen Löschfragen mit „Behalten“ (widerruft je Art).
Future<void> _keepAll(WidgetTester tester) async {
  for (
    var i = 0;
    i < 3 && _key('health_delete_keep').evaluate().isNotEmpty;
    i++
  ) {
    await tester.tap(_key('health_delete_keep'));
    await settleStorage(
      tester,
      what: 'Antwort auf die Löschfrage gespeichert',
      frame: const Duration(milliseconds: 100),
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

/// Morgenmessungen der Kamera an [days] Tagen bis heute (07:00 Ortszeit),
/// Werte mit Streuung; die von heute trägt [todayBand].
MorningMeasurement _cam(int i, {int days = 29, SleepBand? todayBand}) =>
    MorningMeasurement(
      measuredAt: DateTime(2026, 10, 17 + i, 7).toUtc(),
      utcOffset: DateTime(2026, 10, 17 + i, 7).timeZoneOffset,
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
                ? 'HRV (RMSSD): Heute noch keine Messung.'
                : 'HRV (RMSSD): No measurement today yet.',
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
            // Nennt der Grund die Sperre (Kamera-HRV), steht bei der HRV-Tatsache
            // nur die Markierung, sonst mit „geht in keine Zahl ein“ (Befund 3).
            final named = f.kind == ReadinessFactKind.hrvDeviation;
            expect(
              text,
              contains(
                named
                    ? morningMarkText(l, f.mark)!
                    : readinessMarkText(l, f.mark)!,
              ),
            );
          }
        }
      },
    );

    test(
      'Grund nennt die Sperre nicht (HC-HRV ohne z): markierte Kamera-Tatsache '
      'trägt „geht in keine Zahl ein“ (PAR-171K)',
      () {
        const fact = ReadinessFact(
          kind: ReadinessFactKind.hrvDeviation,
          source: ReadinessFactorSource.camera,
          z: -1,
          mark: MorningRmssdMark.notEnabled,
        );
        const r = ReadinessResult(
          state: ReadinessState.limited,
          value: null,
          band: null,
          capped: false,
          factors: [],
          missing: [],
          blockers: [],
          facts: [],
          markedFacts: [fact],
          hasFreshMeasurement: true,
          level: ReadinessLevel.notDeterminable,
          levelReasons: [
            ReadinessLevelReason(ReadinessLevelReasonCode.hrvNoSeries),
          ],
          explanation: ReadinessExplanation(
            code: ReadinessExplanationCode.noNumber,
            drivers: [],
            used: [],
            missing: [],
            cappedWithoutLoad: false,
          ),
        );
        for (final l in [AppLocalizationsDe(), AppLocalizationsEn()]) {
          expect(
            readinessCardText(l, r),
            contains(readinessMarkText(l, fact.mark)!),
          );
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
          utcOffset: _offset,
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
            utcOffset: _offset,
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

    testWidgets('Warnsignal aufheben: Erholungskarte fehlt in keinem Frame', (
      tester,
    ) async {
      final d = Device();
      final s = await _preopen(d);
      await _seedHealth(s);
      await _grant(s, _allKinds);
      await (s as WarningStorage).warning.set(
        WarningSignal(
          reportedOn: DateTime.utc(2026, 11, 4),
          source: WarningSource.manual,
        ),
      );
      await _start(tester, d);
      expect(_key('readiness_card'), findsOneWidget);
      final lift = _key('home_warning_lift');
      expect(lift, findsOneWidget);
      await tester.ensureVisible(lift);
      await tester.tap(lift);
      var gone = 0;
      await observeFrames(
        tester,
        120,
        onFrame: (_) {
          if (_key('readiness_card').evaluate().isEmpty) gone++;
        },
      );
      expect(_key('home_warning_reminder'), findsNothing);
      expect(_key('readiness_card'), findsOneWidget);
      expect(gone, 0, reason: 'Karte fehlte in $gone Frames beim Neuladen');
    });

    testWidgets('Warnsignal aufheben am Listenende, Import verzögert: '
        'Erholungskarte fehlt in keinem Frame (FR-0105, FR-0203)', (
      tester,
    ) async {
      final d = Device();
      final s = await _preopen(d);
      // Der Import beim Öffnen hängt, bis der Test ihn freigibt; danach lädt
      // „Heute“ die Erholung neu, während das Aufheben noch nachlädt.
      final port = _HeldPort();
      d.healthConnect = port;
      await _seedHealth(s);
      await _grant(s, _allKinds);
      await (s as WarningStorage).warning.set(
        WarningSignal(
          reportedOn: DateTime.utc(2026, 11, 4),
          source: WarningSource.manual,
        ),
      );
      await _start(tester, d);
      // Kleines Fenster: Der Aufheben-Knopf liegt am Ende der Liste. Fällt die
      // Erinnerung weg, wird die Liste kürzer, die Position springt zurück
      // und die Liste baut die Karten neu auf.
      tester.view.physicalSize = const Size(411, 500);
      await tester.pumpAndSettle();
      expect(_key('readiness_card'), findsOneWidget);
      expect(port.reads, greaterThan(0), reason: 'Import wartet');
      final lift = _key('home_warning_lift');
      await tester.ensureVisible(lift);
      await tester.pumpAndSettle();
      await tester.tap(lift);
      var gone = 0;
      var split = 0;
      await observeFrames(
        tester,
        120,
        onFrame: (i) {
          // Der Import endet nach zwei Frames.
          if (i == 1) port.release();
          if (_key('readiness_card').evaluate().isEmpty) gone++;
          // Planstand und Hinweise wechseln zusammen: keine Warnsignal-Karte
          // mehr, sobald die Erinnerung fehlt.
          if (_key('home_warning_reminder').evaluate().isEmpty &&
              _key('home_recovery_card').evaluate().isNotEmpty) {
            split++;
          }
        },
      );
      expect(port.released, isTrue);
      expect(split, 0, reason: 'Erinnerung weg, Warnsignal-Karte noch da');
      expect(_key('home_warning_reminder'), findsNothing);
      expect(_key('home_recovery_card'), findsNothing);
      expect(_key('readiness_card'), findsOneWidget);
      expect(gone, 0, reason: 'Karte fehlte in $gone Frames beim Neuladen');
    });

    testWidgets('Hinweise: Öffnen und Neuladen lesen sie je genau einmal', (
      tester,
    ) async {
      final d = Device();
      final s = await _preopen(d);
      await (s as WarningStorage).warning.set(
        WarningSignal(
          reportedOn: DateTime.utc(2026, 11, 13),
          source: WarningSource.manual,
        ),
      );
      HomeHints.debugLoadCount = 0;
      addTearDown(() => HomeHints.debugLoadCount = 0);
      await _start(tester, d);
      await settleStorage(
        tester,
        what: 'Hinweise geladen',
        frame: const Duration(milliseconds: 50),
      );
      expect(HomeHints.debugLoadCount, 1, reason: 'Öffnen');
      expect(_key('home_recovery_card'), findsOneWidget);
      // Neuer Tag beim Fortsetzen: „Heute“ lädt neu (_reload).
      d.clock.set(_now.add(const Duration(days: 1)));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await settleStorage(
        tester,
        what: 'Hinweise geladen',
        frame: const Duration(milliseconds: 50),
      );
      expect(HomeHints.debugLoadCount, 2, reason: 'Neuladen');
      expect(_key('home_recovery_card'), findsOneWidget);
    });

    testWidgets('Löschfrage auf Heute widerruft: keine Health-Connect-Werte '
        'mehr auf der erweiterten Karte (fail-closed, SEC-0007)', (
      tester,
    ) async {
      final d = Device();
      // Recht in Health Connect fehlt: die Löschfragen stehen beim Öffnen an.
      final s = await _preopen(d, granted: const {});
      await _seedHealth(s);
      await _grant(s, _allKinds);
      await _start(tester, d);
      // Solange die Frage offen ist, gilt die Einwilligung noch.
      expect(_key('health_delete_dialog'), findsOneWidget);
      expect(_key('readiness_card'), findsOneWidget);
      // Je Art „Behalten“: das widerruft die Einwilligung (answerDeleteQuestion).
      for (
        var i = 0;
        i < 3 && _key('health_delete_keep').evaluate().isNotEmpty;
        i++
      ) {
        await tester.tap(_key('health_delete_keep'));
        await settleStorage(
          tester,
          what: 'Antwort auf die Löschfrage gespeichert',
          frame: const Duration(milliseconds: 100),
        );
      }
      expect(_key('health_delete_dialog'), findsNothing);
      for (final k in _allKinds) {
        expect(
          await tester.runAsync(
            () => ConsentService(
              s.consents,
              d.clock,
            ).isGranted(healthSourceKey(k)),
          ),
          isFalse,
          reason: '${k.key} widerrufen',
        );
      }
      // Ohne Einwilligung und ohne Kamera/Entwicklermodus: Basisstufe.
      expect(_key('readiness_card'), findsNothing);
    });

    testWidgets('Löschfrage auf Heute: älterer Erholungslauf endet zuletzt '
        'und bringt keine widerrufenen Werte zurück (SEC-0007)', (
      tester,
    ) async {
      final hold = _ReadinessHold(2);
      final d = Device();
      final s = await _preopen(d, granted: const {});
      await _seedHealth(s);
      await _grant(s, _allKinds);
      await _start(tester, d);
      // Lauf A (nach dem Import, mit Einwilligung) hängt an der Übergabe.
      expect(hold.calls, 2, reason: 'Öffnen, Lauf A nach dem Import');
      expect(hold.held, isTrue, reason: 'Lauf A zurückgehalten');
      // Lauf A hat den Lauf beim Öffnen abgelöst; einen Kartenstand mit
      // Einwilligung gibt es nur über ihn.
      expect(_key('health_delete_dialog'), findsOneWidget);
      await _keepAll(tester);
      expect(_key('health_delete_dialog'), findsNothing);
      // Lauf B (ohne Einwilligung) ist durch: Basisstufe.
      expect(hold.calls, 3, reason: 'Lauf B nach der Löschfrage');
      expect(_key('readiness_card'), findsNothing);
      // Vor der Freigabe: Lauf A hängt noch, sein Ergebnis liegt vor.
      expect(hold.held, isTrue, reason: 'Lauf A noch zurückgehalten');
      expect(
        await tester.runAsync(() => hold.loaded.future),
        isTrue,
        reason: 'Lauf A hat zu seinem Start gerechnet',
      );
      hold.release();
      var card = 0;
      var value = 0;
      await observeFrames(
        tester,
        20,
        frame: const Duration(milliseconds: 100),
        onFrame: (_) {
          if (_key('readiness_card').evaluate().isNotEmpty) card++;
          if (_key('readiness_value').evaluate().isNotEmpty) value++;
        },
      );
      expect(hold.held, isFalse, reason: 'Lauf A freigegeben');
      expect(card, 0, reason: 'erweiterte Karte in $card Frames zurück');
      expect(value, 0, reason: 'Zahl in $value Frames zurück');
      expect(_key('readiness_card'), findsNothing);
    });

    testWidgets('Löschfrage auf Heute: Erholungslauf endet erst nach dem '
        'Verlassen von Heute, ohne Ausnahme', (tester) async {
      final hold = _ReadinessHold(2);
      final d = Device();
      final s = await _preopen(d, granted: const {});
      await _seedHealth(s);
      await _grant(s, _allKinds);
      await _start(tester, d);
      expect(hold.held, isTrue, reason: 'Lauf A zurückgehalten');
      // „Heute“ verlassen (dispose), solange Lauf A hängt.
      await tester.pumpWidget(const SizedBox());
      expect(find.byKey(const Key('health_delete_dialog')), findsNothing);
      hold.release();
      await settleStorage(
        tester,
        what: 'Lauf A beendet',
        frame: const Duration(milliseconds: 100),
      );
      expect(hold.held, isFalse, reason: 'Lauf A freigegeben');
      expect(tester.takeException(), isNull);
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

    // Wege zum Nachholen über die App-Verdrahtung (FR-0111, PAR-164K): die
    // Karte auf „Heute“ reicht die Aktionen an die Detailseite weiter, die
    // Schlafangabe landet an der heutigen Morgenmessung, und die Karte lädt
    // danach neu.
    Future<void> openDetail(WidgetTester tester) async {
      await tester.ensureVisible(_key('readiness_where_from'));
      await tester.tap(_key('readiness_where_from'));
      await tester.pumpAndSettle();
      expect(_key('readiness_detail'), findsOneWidget);
    }

    Future<void> tapKey(WidgetTester tester, String k) async {
      await tester.ensureVisible(_key(k));
      await tester.pumpAndSettle();
      await tester.tap(_key(k));
      await tester.pumpAndSettle();
    }

    testWidgets('Heute → Detailseite: „Schlaf angeben“ speichert an der '
        'Morgenmessung, Karte lädt neu', (tester) async {
      final d = Device();
      final s = await _preopen(d);
      await SettingsDeveloperModeStore(s.settings, d.clock).set(true);
      await _seedCamera(s);
      await _start(tester, d);
      expect(_key('readiness_card'), findsOneWidget);

      await openDetail(tester);
      expect(_key('readiness_detail_missing_sleep'), findsOneWidget);
      expect(_key('readiness_detail_enter_sleep'), findsOneWidget);
      await tapKey(tester, 'readiness_detail_enter_sleep');
      expect(_key('readiness_sleep_sheet'), findsOneWidget);
      await tapKey(tester, 'readiness_sleep_from7to8');
      await tapKey(tester, 'readiness_sleep_done');
      await tester.runAsync(() async {});
      await tester.pumpAndSettle();

      // Gespeichert an der heutigen (einzigen) Morgenmessung des Ortstags.
      final stored = (await tester.runAsync(
        (s as MorningStorage).morning.list,
      ))!;
      final today = stored.singleWhere(
        (e) => e.value.measuredAt == _cam(28).measuredAt,
      );
      expect(today.value.sleepBand, SleepBand.from7to8);
      expect(stored.where((e) => e.value.sleepBand != null), hasLength(1));

      // Zurück auf „Heute“: die Karte hat neu geladen, ihre Detailseite zeigt
      // Schlaf als Selbstangabe statt als fehlend.
      Navigator.of(tester.element(_key('readiness_detail'))).pop();
      await tester.pumpAndSettle();
      expect(_key('readiness_detail'), findsNothing);
      await openDetail(tester);
      expect(_key('readiness_detail_missing_sleep'), findsNothing);
      expect(_key('readiness_detail_factor_sleep'), findsOneWidget);
      expect(
        find.descendant(
          of: _key('readiness_detail_factor_sleep'),
          matching: find.text(
            readinessSourceName(
              AppLocalizationsDe(),
              ReadinessFactorSource.selfReport,
            ),
          ),
        ),
        findsOneWidget,
      );
      expect(_key('readiness_detail_change_sleep'), findsOneWidget);
    });

    testWidgets('Heute → Detailseite ohne heutige Messung: „Morgenmessung '
        'starten“ steht da', (tester) async {
      final d = Device();
      final s = await _preopen(d);
      // Im Morgenfenster (4–11 Uhr Ortszeit), sonst steht statt des Knopfs
      // der Hinweis auf die nächste Messung.
      d.clock.set(DateTime(2026, 11, 14, 9).toUtc());
      await SettingsDeveloperModeStore(s.settings, d.clock).set(true);
      for (var i = 0; i < 28; i++) {
        await (s as MorningStorage).morning.add(_cam(i));
      }
      await _start(tester, d);
      await openDetail(tester);
      expect(_key('readiness_detail_missing_hrv'), findsOneWidget);
      expect(_key('readiness_detail_start_morning_hrv'), findsOneWidget);
      expect(_key('readiness_detail_enter_sleep'), findsNothing);
    });

    testWidgets('Heute → Detailseite ohne Entwicklermodus (Sperre, K62): '
        'kein „Schlaf angeben“, kein „Morgenmessung starten“', (tester) async {
      final d = Device();
      final s = await _preopen(d);
      // Zahl aus Health Connect ohne Schlaf; heutige Morgenmessung gespeichert,
      // vor der Freigabe aber gesperrt.
      await _seedHealth(s, sleepDays: 0);
      await _grant(s, _allKinds);
      await _seedCamera(s);
      await _start(tester, d);
      expect(_key('readiness_card'), findsOneWidget);
      await openDetail(tester);
      expect(_key('readiness_detail_missing_sleep'), findsOneWidget);
      expect(_key('readiness_detail_enter_sleep'), findsNothing);
      expect(_key('readiness_detail_change_sleep'), findsNothing);
      expect(
        find.descendant(
          of: _key('readiness_detail_missing'),
          matching: find.byType(TextButton),
        ),
        findsNothing,
      );
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
