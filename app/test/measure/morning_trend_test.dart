import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/measure/morning_trend_logic.dart';
import 'package:running_app/features/measure/morning_trend_screen.dart';
import 'package:running_app/features/plan/plan_recovery_trigger.dart';
import 'package:running_app/l10n/app_localizations.dart';
import 'package:running_app/ui/ui.dart';

import 'measure_support.dart';

// Seite Morgenwerte (FR-0215, K-1, K67, FR-0217): Markierungen je Stand und
// Modus, eine Reihe mit Punkten nach Haltung, Liste, nur zählende Messungen,
// Morgenfenster. Alle Werte synthetisch.

Map<ValidationQuantity, ValidationState> _state({
  ValidationState hr = ValidationState.passed,
  ValidationState supine = ValidationState.passed,
}) => {
  ValidationQuantity.restingHr: hr,
  ValidationQuantity.lnRmssdSupine: supine,
};

final _clock = FakeClock(DateTime.utc(2026, 11, 10, 8, 0));

Future<({String manufacturer, String model})> _device() async =>
    (manufacturer: 'T', model: 'M');

MorningMeasurement _m(
  DateTime at, {
  double bpm = 52.4,
  double? rmssd = 48,
  RestingPosture posture = RestingPosture.lying,
  String model = 'M',
  bool outside = false,
}) => MorningMeasurement(
  measuredAt: at,
  utcOffset: Duration.zero,
  posture: posture,
  deviceManufacturer: 'T',
  deviceModel: model,
  method: ppgMethod,
  methodVersion: ppgMethodVersion,
  quality: PpgQuality.good,
  restingHrBpm: bpm,
  rmssdMs: rmssd,
  cameraIntervalsMs: const [],
  beforeValidation: true,
  outsideWindow: outside,
);

DateTime _day(int back, {int hour = 6}) =>
    DateTime.utc(2026, 11, 10 - back, hour, 30);

/// Puls außerhalb PAR-017 im Entwicklermodus gestern im Fenster: unbrauchbar
/// gespeichert (an dem Tag zählt sonst nichts).
MorningMeasurement _outOfRange(double bpm) => buildMorningMeasurement(
  result: PpgMeasurement(
    quality: PpgQuality.good,
    reasons: const [],
    bpm: bpm,
    rmssdMs: 40,
    timingNoiseMs: 10,
    intervalsMs: const [450, 460],
  ),
  measuredAt: _day(1),
  utcOffset: Duration.zero,
  posture: RestingPosture.lying,
  deviceManufacturer: 'T',
  deviceModel: 'M',
  keepUnusable: true,
)!;

/// Eine Reihe: 5 liegende und 2 sitzende zählende Tage (heute 52,4); dazu
/// Nicht-Zählendes: zweite Messung heute (70), außerhalb des Fensters gestern
/// (99), anderes Gerät, ältere als 14 Tage; mit [dev] eine unbrauchbare.
Future<StorageSession> _session({required bool dev, bool optIn = false}) async {
  final s = await FakeStorage().open(testKey);
  if (optIn) {
    await s.settings.set(
      SettingKeys.morningCameraRmssdOptIn,
      '1',
      at: _clock.now(),
    );
  }
  if (dev) await SettingsDeveloperModeStore(s.settings, _clock).set(true);
  final store = (s as MorningStorage).morning;
  for (final (back, bpm) in [(0, 52.4), (2, 54.0), (3, 53.0), (5, 55.0)]) {
    await store.add(_m(_day(back), bpm: bpm));
  }
  await store.add(_m(_day(9), bpm: 56.0));
  await store.add(_m(_day(0, hour: 7), bpm: 70)); // zweite des Tages
  await store.add(_m(_day(1, hour: 14), bpm: 99, outside: true));
  await store.add(_m(_day(4), bpm: 88, model: 'Other'));
  await store.add(_m(_day(20), bpm: 77)); // älter als 14 Tage
  await store.add(_m(_day(6), bpm: 58.4, posture: RestingPosture.sitting));
  await store.add(_m(_day(7), bpm: 59.0, posture: RestingPosture.sitting));
  if (dev) {
    await store.add(
      MorningMeasurement(
        measuredAt: _day(0, hour: 5),
        utcOffset: Duration.zero,
        posture: RestingPosture.lying,
        deviceManufacturer: 'T',
        deviceModel: 'M',
        method: ppgMethod,
        methodVersion: ppgMethodVersion,
        quality: PpgQuality.unusable,
        unusableReason: MorningUnusableReason.tooManyDisturbances,
        cameraIntervalsMs: const [],
        beforeValidation: true,
        outsideWindow: false,
      ),
    );
  }
  return s;
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
  }
}

Future<void> _pump(
  WidgetTester tester,
  StorageSession s, {
  required Map<ValidationQuantity, ValidationState> state,
  bool dark = false,
  PlanRecoveryTrigger? recovery,
}) async {
  tester.view.physicalSize = const Size(390, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: dark ? RamuriTheme.dark : RamuriTheme.light,
      locale: const Locale('de'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MorningTrendScreen(
        session: s,
        clock: _clock,
        validationState: state,
        device: _device,
        recovery: recovery,
      ),
    ),
  );
  await _settle(tester);
}

/// Zählt die Prüfungen des Plans nach einer Wahl (FR-0157); den Plan selbst
/// prüft `plan_recovery_wiring_test.dart`.
class _CountingRecovery extends PlanRecoveryTrigger {
  _CountingRecovery(StorageSession s)
    : super(session: s, clock: _clock, readinessToday: (_) async => null);
  int calls = 0;

  @override
  Future<bool> recheck() async {
    calls++;
    return false;
  }
}

/// Sitzung, deren Wahl scheitert; alles andere geht an [inner].
class _FailingChooseSession implements StorageSession, MorningStorage {
  _FailingChooseSession(this.inner);
  final StorageSession inner;

  @override
  SettingsStore get settings => inner.settings;

  @override
  late final MorningStore morning = _FailingChoose(
    (inner as MorningStorage).morning,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FailingChoose implements MorningStore {
  _FailingChoose(this.inner);
  final MorningStore inner;

  @override
  Future<void> choose(int measurementId) =>
      throw const StorageException(StorageFailure.failed);

  @override
  Future<List<StoredMorningMeasurement>> list() => inner.list();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Key _row(DateTime at) => Key('morning_row_${at.millisecondsSinceEpoch}');
Key _choose(DateTime at) => Key('morning_choose_${at.millisecondsSinceEpoch}');

/// Status-Text einer Zeile der Liste.
Finder _rowText(DateTime at, String text) =>
    find.descendant(of: find.byKey(_row(at)), matching: find.text(text));

Future<void> _chooseRow(WidgetTester tester, DateTime at) async {
  await tester.ensureVisible(find.byKey(_choose(at)));
  await tester.tap(find.byKey(_choose(at)));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('morning_choose_confirm')));
  await _settle(tester);
  await tester.pumpAndSettle();
}

const _later = 'zählt nicht, an diesem Morgen zählt eine andere';

String _text(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key))).data!;

void main() {
  group('Markierungen (Logik)', () {
    const states = ValidationState.values;
    for (final supine in states) {
      test('Entwicklermodus: keine Markierung (${supine.name})', () {
        final m = morningTrendMarks(
          developerMode: true,
          optIn: false,
          state: _state(supine: supine, hr: ValidationState.failed),
        );
        expect(m.rmssd, MorningRmssdMark.none);
        expect(m.optInVisible, isFalse);
        expect(m.hrInaccurate, isFalse);
        expect(m.rmssdLocked, isFalse);
      });
    }

    test('bestanden: ohne Opt-in zählt RMSSD nicht, mit Opt-in zählt sie '
        '(ein Schalter, keine Haltung)', () {
      final off = morningTrendMarks(
        developerMode: false,
        optIn: false,
        state: _state(),
      );
      expect(off.rmssd, MorningRmssdMark.notEnabled);
      expect(off.rmssdLocked, isTrue);
      expect(off.optInVisible, isTrue);
      final on = morningTrendMarks(
        developerMode: false,
        optIn: true,
        state: _state(),
      );
      expect(on.rmssd, MorningRmssdMark.experimental);
      expect(on.rmssdLocked, isFalse);
      expect(on.optInVisible, isTrue);
    });

    test('Entwicklermodus ohne Opt-in: RMSSD zählt', () {
      final m = morningTrendMarks(
        developerMode: true,
        optIn: false,
        state: _state(),
      );
      expect(m.rmssdLocked, isFalse);
      expect(m.optInVisible, isFalse);
    });

    test('ein Stand für alle Haltungen: eingeschränkt, nicht bestanden, '
        'ungeprüft (Opt-in ändert nichts, kein Schalter)', () {
      MorningTrendMarks marks(ValidationState s) => morningTrendMarks(
        developerMode: false,
        optIn: true,
        state: _state(supine: s),
      );
      for (final s in [ValidationState.limited, ValidationState.failed]) {
        expect(marks(s).rmssd, MorningRmssdMark.inaccurate);
        expect(marks(s).rmssdLocked, isTrue);
        expect(marks(s).optInVisible, isFalse);
      }
      expect(
        marks(ValidationState.notChecked).rmssd,
        MorningRmssdMark.notChecked,
      );
    });

    test('Ruhepuls: nur bei nicht bestanden markiert', () {
      for (final s in states) {
        expect(
          morningTrendMarks(
            developerMode: false,
            optIn: false,
            state: _state(hr: s),
          ).hrInaccurate,
          s == ValidationState.failed,
        );
      }
    });

    test('ungeprüft: noch nicht geprüft', () {
      final m = morningTrendMarks(developerMode: false, optIn: false);
      expect(m.rmssd, MorningRmssdMark.notChecked);
    });
  });

  group('Verlauf und Liste (Logik)', () {
    test(
      'eine Reihe, nur zählende Messungen, nur 14 Tage, mit Haltung',
      () async {
        final s = await _session(dev: true);
        final all = [
          for (final e in await (s as MorningStorage).morning.list()) e.value,
        ];
        final v = morningTrendValues(
          all,
          manufacturer: 'T',
          model: 'M',
          nowUtc: _clock.now(),
          utcOffset: Duration.zero,
          pick: (m) => m.restingHrBpm,
        );
        expect(
          [for (final e in v) e.value],
          [56.0, 59.0, 58.4, 55.0, 53.0, 54.0, 52.4],
        );
        expect([for (final e in v) e.dayIndex], [4, 6, 7, 8, 10, 11, 13]);
        expect(
          [for (final e in v) e.posture == RestingPosture.sitting],
          [false, true, true, false, false, false, false],
        );
        expect(
          morningTrendMean(v, fromDay: 7),
          closeTo((58.4 + 55 + 53 + 54 + 52.4) / 5, 1e-9),
        );
      },
    );

    test(
      'Liste: Status je Zeile, unbrauchbar nur im Entwicklermodus',
      () async {
        final s = await _session(dev: true);
        final all = [
          for (final e in await (s as MorningStorage).morning.list()) e.value,
        ];
        List<MorningRow> rows(bool dev) => morningRecentRows(
          all,
          manufacturer: 'T',
          model: 'M',
          developerMode: dev,
          limit: 4,
        );
        final dev = rows(true);
        // neueste zuerst: heute 7:30 (zweite), 6:30 (zählt), 5:30 (unbrauchbar)
        expect(
          [for (final r in dev) r.status],
          [
            MorningRowStatus.later,
            MorningRowStatus.counts,
            MorningRowStatus.unusable,
            MorningRowStatus.outside,
          ],
        );
        final user = rows(false);
        expect(user.any((r) => r.status == MorningRowStatus.unusable), isFalse);
        expect(user.first.status, MorningRowStatus.later);
      },
    );
  });

  group('Puls außerhalb PAR-017 (Entwicklermodus)', () {
    for (final bpm in [29.0, 121.0]) {
      test(
        '$bpm bpm: kein Trendwert, Zeile unbrauchbar, Reihe ohne den Tag',
        () async {
          final s = await _session(dev: true);
          final store = (s as MorningStorage).morning;
          await store.add(_outOfRange(bpm));
          final all = [for (final e in await store.list()) e.value];
          final x = all.singleWhere(
            (m) =>
                m.unusableReason == MorningUnusableReason.restingHrOutOfRange,
          );
          expect(x.restingHrBpm, isNull);
          for (final pick in <double? Function(MorningMeasurement)>[
            (m) => m.roundedRestingHr,
            (m) => m.rmssdMs,
          ]) {
            final v = morningTrendValues(
              all,
              manufacturer: 'T',
              model: 'M',
              nowUtc: _clock.now(),
              utcOffset: Duration.zero,
              pick: pick,
            );
            expect(v.any((e) => e.dayIndex == 12), isFalse);
          }
          expect(countingMorningMeasurements(all), isNot(contains(x)));
          final row = morningRecentRows(
            all,
            manufacturer: 'T',
            model: 'M',
            developerMode: true,
          ).singleWhere((r) => identical(r.m, x));
          expect(row.status, MorningRowStatus.unusable);
        },
      );
    }

    testWidgets('Liste zeigt unbrauchbar mit Grund, ohne Wert', (tester) async {
      final s = await _session(dev: true);
      await (s as MorningStorage).morning.add(_outOfRange(121));
      await _pump(tester, s, state: _state(supine: ValidationState.failed));
      expect(
        find.textContaining(
          'unbrauchbar, zählt nicht · Grund: Puls außerhalb von 30 bis 120',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('121'), findsNothing);
    });
  });

  group('Seite', () {
    for (final dark in [false, true]) {
      final mode = dark ? 'dunkel' : 'hell';

      testWidgets('Entwicklermodus ($mode): Hinweis, keine Markierung, '
          'Legende, unbrauchbare Zeile', (tester) async {
        final s = await _session(dev: true);
        await _pump(
          tester,
          s,
          dark: dark,
          state: _state(supine: ValidationState.failed),
        );
        expect(find.byKey(const Key('morning_dev_hint')), findsOneWidget);
        expect(find.byKey(const Key('morning_rmssd_mark')), findsNothing);
        expect(find.byKey(const Key('morning_hr_mark')), findsNothing);
        expect(find.byKey(const Key('morning_legend')), findsOneWidget);
        expect(find.text('liegend'), findsWidgets);
        expect(find.text('sitzend'), findsWidgets);
        expect(
          find.textContaining(
            'unbrauchbar, zählt nicht · Grund: zu wenige gültige Schläge',
          ),
          findsOneWidget,
        );
      });

      testWidgets('bestanden ohne Opt-in ($mode): nicht eingeschaltet, ein '
          'Schalter', (tester) async {
        final s = await _session(dev: false);
        await _pump(tester, s, dark: dark, state: _state());
        expect(find.byKey(const Key('morning_dev_hint')), findsNothing);
        expect(
          _text(tester, 'morning_rmssd_mark'),
          'experimentell, nicht eingeschaltet',
        );
        expect(find.text('Kamera-RMSSD einbeziehen'), findsOneWidget);
        expect(find.byType(SwitchListTile), findsOneWidget);
      });

      testWidgets('bestanden mit Opt-in ($mode): experimentell, mit einem '
          'Brustgurt verglichen, für beide Haltungen', (tester) async {
        final s = await _session(dev: false, optIn: true);
        await _pump(tester, s, dark: dark, state: _state());
        expect(
          _text(tester, 'morning_rmssd_mark'),
          'experimentell, mit einem Brustgurt verglichen (ein Handy)',
        );
        expect(find.byType(SwitchListTile), findsOneWidget);
        expect(
          tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
          isTrue,
        );
        // Die Reihe enthält sitzende Punkte; es gibt nur diesen Schalter.
        expect(find.text('sitzend'), findsWidgets);
      });
    }

    testWidgets('Schalter setzt und löscht den Opt-in', (tester) async {
      final s = await _session(dev: false);
      await _pump(tester, s, state: _state());
      await tester.tap(find.byKey(const Key('morning_optin')));
      await _settle(tester);
      expect(await s.settings.get(SettingKeys.morningCameraRmssdOptIn), '1');
      expect(
        _text(tester, 'morning_rmssd_mark'),
        'experimentell, mit einem Brustgurt verglichen (ein Handy)',
      );
      await tester.tap(find.byKey(const Key('morning_optin')));
      await _settle(tester);
      expect(await s.settings.get(SettingKeys.morningCameraRmssdOptIn), '0');
    });

    testWidgets('Entwicklermodus: kein Schalter, auch ohne Opt-in', (
      tester,
    ) async {
      final s = await _session(dev: true);
      await _pump(tester, s, state: _state());
      expect(find.byKey(const Key('morning_optin')), findsNothing);
      expect(find.byKey(const Key('morning_rmssd_mark')), findsNothing);
    });

    testWidgets('Ruhepuls nicht bestanden: markiert', (tester) async {
      final s = await _session(dev: false);
      await _pump(tester, s, state: _state(hr: ValidationState.failed));
      expect(_text(tester, 'morning_hr_mark'), 'ungenauer als erwartet');
    });

    testWidgets('lnRMSSD liegend nicht bestanden ohne Modus: nichts, auch '
        'nichts Gespeichertes', (tester) async {
      final s = await _session(dev: false);
      await _pump(tester, s, state: _state(supine: ValidationState.failed));
      expect(find.byKey(const Key('morning_series_info')), findsNothing);
      expect(find.byKey(const Key('morning_hr_card')), findsNothing);
      expect(find.byKey(const Key('morning_window')), findsNothing);
    });

    testWidgets('eine Reihe: liegende und sitzende Morgen zusammen, nur '
        'zählende, Punkte nach Haltung', (tester) async {
      final s = await _session(dev: false);
      await _pump(tester, s, state: _state());
      expect(find.text('Liegend'), findsNothing); // kein Umschalter mehr
      expect(
        _text(tester, 'morning_series_info'),
        'Eine Reihe mit diesem Handy · letzte 14 Tage · 7 gültige Morgen',
      );
      // heute die erste Messung (52,4; nicht 70)
      expect(_text(tester, 'morning_hr_card_last'), '52,4');
      expect(
        find.textContaining('Mittel der letzten 7 Morgen, 54,6'),
        findsWidgets,
      );
      // Screenreader: Zahl der sitzenden Punkte im Diagramm-Label
      final label = tester
          .getSemantics(find.byKey(const Key('morning_hr_card_chart')))
          .label;
      expect(label, contains('2 Punkte sitzend'));
      // Liste: Haltung je Zeile und Status; Unbrauchbare fehlt ohne Modus
      expect(find.textContaining('· sitzend'), findsNWidgets(1));
      expect(find.text('zählt, in derselben Reihe'), findsNWidgets(1));
      expect(find.textContaining('unbrauchbar'), findsNothing);
    });

    testWidgets('Markierung der Punkte: gefüllt liegend, hohl sitzend', (
      tester,
    ) async {
      final s = await _session(dev: false);
      await _pump(tester, s, state: _state());
      final dots = tester
          .widgetList<Container>(
            find.descendant(
              of: find.byKey(const Key('morning_list')),
              matching: find.byType(Container),
            ),
          )
          .map((c) => c.decoration)
          .whereType<BoxDecoration>()
          .where((d) => d.shape == BoxShape.circle)
          .toList();
      final c = RamuriColors.light;
      // 7 neueste Zeilen: 6 liegend (gefüllt), 1 sitzend (hohl)
      expect(dots.length, 7);
      expect(dots.where((d) => d.color != c.surface).length, 6);
      expect(dots.where((d) => d.color == c.surface).length, 1);
    });

    testWidgets('Markierung: unbrauchbare liegende Zeile hohl, brauchbare '
        'liegende gefüllt', (tester) async {
      final s = await _session(dev: true);
      await _pump(tester, s, state: _state());
      BoxDecoration dotOf(DateTime at) {
        final row = find.byKey(Key('morning_row_${at.millisecondsSinceEpoch}'));
        expect(row, findsOneWidget);
        return tester
            .widgetList<Container>(
              find.descendant(of: row, matching: find.byType(Container)),
            )
            .map((c) => c.decoration)
            .whereType<BoxDecoration>()
            .singleWhere((d) => d.shape == BoxShape.circle);
      }

      final c = RamuriColors.light;
      final unusable = dotOf(_day(0, hour: 5)); // liegend, unbrauchbar
      expect(unusable.color, c.surface);
      expect((unusable.border! as Border).top.color, c.textMuted);
      final usable = dotOf(_day(0)); // liegend, zählt
      expect(usable.color, c.accent);
    });

    testWidgets('leere Reihe: Hinweis statt Diagramm', (tester) async {
      final s = await FakeStorage().open(testKey);
      await SettingsDeveloperModeStore(s.settings, _clock).set(true);
      await _pump(tester, s, state: _state());
      expect(find.byKey(const Key('morning_trend_empty')), findsOneWidget);
      expect(find.byKey(const Key('morning_hr_card')), findsNothing);
    });

    testWidgets('Wahl: nur „zählt nicht“ bietet die Aktion an; danach zählt '
        'die gewählte in Liste und Kurve, heute prüft den Plan (FR-0215)', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final s = await _session(dev: true);
      final recovery = _CountingRecovery(s);
      await _pump(tester, s, state: _state(), recovery: recovery);
      final first = _day(0); // zählt (52,4)
      final second = _day(0, hour: 7); // zählt nicht (70)
      expect(_rowText(second, _later), findsOneWidget);
      expect(_text(tester, 'morning_hr_card_last'), '52,4');
      // Genau eine Zeile mit Aktion: nicht die zählende, nicht außerhalb des
      // Fensters, nicht unbrauchbar.
      expect(find.byKey(_choose(second)), findsOneWidget);
      expect(find.byKey(_choose(first)), findsNothing);
      expect(find.byKey(_choose(_day(1, hour: 14))), findsNothing);
      expect(find.byKey(_choose(_day(0, hour: 5))), findsNothing);
      expect(
        find.byWidgetPredicate((w) => '${w.key}'.contains('morning_choose_1')),
        findsOneWidget,
      );
      expect(find.text('Als gültige Messung des Tages verwenden'), findsOne);
      // Tippfläche ≥ 48 dp, Screenreader: Knopf mit Ansage der Aktion.
      expect(
        tester.getSize(find.byKey(_choose(second))).height,
        greaterThanOrEqualTo(48),
      );
      final data = tester
          .getSemantics(find.byKey(_choose(second)))
          .getSemanticsData();
      expect(data.flagsCollection.isButton, isTrue);
      expect([
        for (final id in data.customSemanticsActionIds ?? const <int>[])
          CustomSemanticsAction.getAction(id)?.hint,
      ], contains('Als gültige Messung des Tages verwenden'));

      // Abbrechen ändert nichts.
      await tester.ensureVisible(find.byKey(_choose(second)));
      await tester.tap(find.byKey(_choose(second)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('morning_choose_cancel')));
      await tester.pumpAndSettle();
      expect(recovery.calls, 0);
      expect(
        (await tester.runAsync(() => (s as MorningStorage).morning.list()))!
            .every((e) => !e.value.chosen),
        isTrue,
      );

      await _chooseRow(tester, second);
      expect(_rowText(second, 'zählt'), findsOneWidget);
      expect(_rowText(first, _later), findsOneWidget);
      expect(_text(tester, 'morning_hr_card_last'), '70,0');
      expect(find.byKey(_choose(first)), findsOneWidget);
      expect(find.byKey(_choose(second)), findsNothing);
      expect(recovery.calls, 1);

      // Zurück zur ersten: wieder wie vorher.
      await _chooseRow(tester, first);
      expect(_rowText(first, 'zählt'), findsOneWidget);
      expect(_rowText(second, _later), findsOneWidget);
      expect(_text(tester, 'morning_hr_card_last'), '52,4');
      expect(recovery.calls, 2);
      semantics.dispose();
    });

    testWidgets('Wahl an einem früheren Tag: Liste neu, Plan nicht geprüft', (
      tester,
    ) async {
      final s = await _session(dev: false);
      final older = _day(2, hour: 8);
      await (s as MorningStorage).morning.add(_m(older, bpm: 61));
      final recovery = _CountingRecovery(s);
      await _pump(tester, s, state: _state(), recovery: recovery);
      expect(_rowText(older, _later), findsOneWidget);
      await _chooseRow(tester, older);
      expect(_rowText(older, 'zählt'), findsOneWidget);
      expect(_rowText(_day(2), _later), findsOneWidget);
      expect(recovery.calls, 0);
    });

    testWidgets('Wahl scheitert: Fehler der Seite, Liste unverändert', (
      tester,
    ) async {
      final inner = await _session(dev: false);
      final recovery = _CountingRecovery(inner);
      await _pump(
        tester,
        _FailingChooseSession(inner),
        state: _state(),
        recovery: recovery,
      );
      final second = _day(0, hour: 7);
      await _chooseRow(tester, second);
      expect(find.byKey(const Key('morning_setting_failed')), findsOneWidget);
      expect(_rowText(second, _later), findsOneWidget);
      expect(_rowText(_day(0), 'zählt'), findsOneWidget);
      expect(_text(tester, 'morning_hr_card_last'), '52,4');
      expect(recovery.calls, 0);
    });

    testWidgets('Morgenfenster: Vorgabe, ändern, ungültig gesperrt', (
      tester,
    ) async {
      final s = await _session(dev: true);
      await _pump(tester, s, state: _state());
      expect(_text(tester, 'morning_window_value'), '4 bis 11 Uhr');
      expect(find.byKey(const Key('morning_reminder_slot')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('morning_window')));
      await tester.tap(find.byKey(const Key('morning_window')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('morning_window_start')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('12').last);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('morning_window_invalid')), findsOneWidget);
      expect(
        tester
            .widget<TextButton>(find.byKey(const Key('morning_window_save')))
            .onPressed,
        isNull,
      );
      await tester.tap(find.byKey(const Key('morning_window_start')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('5').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('morning_window_save')));
      await _settle(tester);
      expect(await s.settings.get(SettingKeys.morningWindow), '5-11');
      expect(_text(tester, 'morning_window_value'), '5 bis 11 Uhr');
    });
  });
}
