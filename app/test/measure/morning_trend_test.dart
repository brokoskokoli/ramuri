import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/measure/morning_trend_logic.dart';
import 'package:running_app/features/measure/morning_trend_screen.dart';
import 'package:running_app/l10n/app_localizations.dart';
import 'package:running_app/ui/ui.dart';

import 'measure_support.dart';

// Seite Morgenwerte (FR-0215, K-1, FR-0217): Markierungen und Opt-in je Stand
// und Modus, Reihenwechsel, nur zählende Messungen, Morgenfenster. Alle Werte
// synthetisch.

Map<ValidationQuantity, ValidationState> _state({
  ValidationState hr = ValidationState.passed,
  ValidationState supine = ValidationState.passed,
  ValidationState sitting = ValidationState.passed,
}) => {
  ValidationQuantity.restingHr: hr,
  ValidationQuantity.lnRmssdSupine: supine,
  ValidationQuantity.lnRmssdSitting: sitting,
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

/// Liegend: 5 zählende Tage (heute 52,4); dazu Nicht-Zählendes: zweite
/// Messung heute (70), außerhalb des Fensters gestern (99), anderes Gerät,
/// ältere als 14 Tage. Sitzend: 2 Tage.
Future<StorageSession> _session({required bool dev, bool optIn = false}) async {
  final s = await FakeStorage().open(testKey);
  if (dev) await SettingsDeveloperModeStore(s.settings, _clock).set(true);
  if (optIn) {
    await s.settings.set(
      SettingKeys.morningCameraRmssdOptIn,
      '1',
      at: _clock.now(),
    );
  }
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
      ),
    ),
  );
  await _settle(tester);
}

String _text(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key))).data!;

void main() {
  group('Markierungen (Logik)', () {
    const states = ValidationState.values;
    for (final supine in states) {
      for (final posture in RestingPosture.values) {
        for (final optIn in [false, true]) {
          test('Entwicklermodus: keine Markierung, kein Opt-in '
              '(${supine.name}, ${posture.name}, optIn $optIn)', () {
            final m = morningTrendMarks(
              developerMode: true,
              posture: posture,
              optIn: optIn,
              state: _state(supine: supine, hr: ValidationState.failed),
            );
            expect(m.rmssd, MorningRmssdMark.none);
            expect(m.hrInaccurate, isFalse);
            expect(m.optInVisible, isFalse);
            expect(m.rmssdLocked, isFalse);
          });
        }
      }
    }

    test('Opt-in-Schalter nur bei bestanden', () {
      for (final supine in states) {
        for (final posture in RestingPosture.values) {
          final m = morningTrendMarks(
            developerMode: false,
            posture: posture,
            optIn: false,
            state: _state(supine: supine),
          );
          expect(
            m.optInVisible,
            supine == ValidationState.passed,
            reason: '${supine.name} ${posture.name}',
          );
        }
      }
    });

    test(
      'bestanden: ohne Opt-in nicht eingeschaltet, mit Opt-in je Haltung',
      () {
        MorningRmssdMark mark(RestingPosture p, bool o) => morningTrendMarks(
          developerMode: false,
          posture: p,
          optIn: o,
          state: _state(),
        ).rmssd;
        expect(mark(RestingPosture.lying, false), MorningRmssdMark.notEnabled);
        expect(
          mark(RestingPosture.sitting, false),
          MorningRmssdMark.notEnabled,
        );
        expect(mark(RestingPosture.lying, true), MorningRmssdMark.optIn);
        expect(
          mark(RestingPosture.sitting, true),
          MorningRmssdMark.optInSitting,
        );
      },
    );

    test(
      'eingeschränkt, nicht bestanden: ungenauer als erwartet, kein Opt-in',
      () {
        for (final s in [ValidationState.limited, ValidationState.failed]) {
          final m = morningTrendMarks(
            developerMode: false,
            posture: RestingPosture.lying,
            optIn: true,
            state: _state(supine: s),
          );
          expect(m.rmssd, MorningRmssdMark.inaccurate);
          expect(m.rmssdLocked, isTrue);
          expect(m.optInVisible, isFalse);
        }
      },
    );

    test(
      'sitzend gesperrt, wenn im Sitzen eingeschränkt oder nicht bestanden',
      () {
        for (final s in [ValidationState.limited, ValidationState.failed]) {
          final st = _state(sitting: s);
          final sit = morningTrendMarks(
            developerMode: false,
            posture: RestingPosture.sitting,
            optIn: true,
            state: st,
          );
          expect(sit.rmssd, MorningRmssdMark.inaccurate);
          expect(sit.optInVisible, isFalse);
          final lie = morningTrendMarks(
            developerMode: false,
            posture: RestingPosture.lying,
            optIn: true,
            state: st,
          );
          expect(lie.rmssd, MorningRmssdMark.optIn);
        }
      },
    );

    test('Ruhepuls: nur bei nicht bestanden markiert', () {
      for (final s in states) {
        expect(
          morningTrendMarks(
            developerMode: false,
            posture: RestingPosture.lying,
            optIn: false,
            state: _state(hr: s),
          ).hrInaccurate,
          s == ValidationState.failed,
        );
      }
    });

    test('ungeprüft: noch nicht geprüft', () {
      final m = morningTrendMarks(
        developerMode: false,
        posture: RestingPosture.lying,
        optIn: false,
      );
      expect(m.rmssd, MorningRmssdMark.notChecked);
      expect(m.optInVisible, isFalse);
    });
  });

  group('Verlauf (Logik)', () {
    test('nur zählende Messungen der Reihe, nur 14 Tage', () async {
      final s = await _session(dev: true);
      final all = [
        for (final e in await (s as MorningStorage).morning.list()) e.value,
      ];
      final v = morningTrendValues(
        all,
        posture: RestingPosture.lying,
        manufacturer: 'T',
        model: 'M',
        nowUtc: _clock.now(),
        utcOffset: Duration.zero,
        pick: (m) => m.restingHrBpm,
      );
      expect([for (final e in v) e.value], [56.0, 55.0, 53.0, 54.0, 52.4]);
      expect([for (final e in v) e.dayIndex], [4, 8, 10, 11, 13]);
      expect(
        morningTrendMean(v, fromDay: 7),
        closeTo((55 + 53 + 54 + 52.4) / 4, 1e-9),
      );
    });
  });

  group('Seite', () {
    for (final dark in [false, true]) {
      final mode = dark ? 'dunkel' : 'hell';

      testWidgets('Entwicklermodus ($mode): Hinweis, keine Markierung, kein '
          'Opt-in', (tester) async {
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
        expect(find.byKey(const Key('morning_optin')), findsNothing);
        expect(
          find.byKey(const Key('morning_rmssd_card_chart')),
          findsOneWidget,
        );
      });

      testWidgets('bestanden ohne Opt-in ($mode): nicht eingeschaltet, '
          'Schalter da', (tester) async {
        final s = await _session(dev: false);
        await _pump(tester, s, dark: dark, state: _state());
        expect(find.byKey(const Key('morning_dev_hint')), findsNothing);
        expect(
          _text(tester, 'morning_rmssd_mark'),
          'experimentell, nicht eingeschaltet',
        );
        expect(find.byKey(const Key('morning_optin')), findsOneWidget);
      });
    }

    testWidgets('bestanden mit Opt-in: Kennzeichnung liegend und sitzend', (
      tester,
    ) async {
      final s = await _session(dev: false, optIn: true);
      await _pump(tester, s, state: _state());
      expect(
        _text(tester, 'morning_rmssd_mark'),
        'experimentell, mit einem Brustgurt verglichen (ein Handy)',
      );
      await tester.tap(find.text('Sitzend'));
      await tester.pump();
      expect(
        _text(tester, 'morning_rmssd_mark'),
        'experimentell, liegend verglichen',
      );
    });

    testWidgets('Opt-in-Schalter schreibt die Einstellung', (tester) async {
      final s = await _session(dev: false);
      await _pump(tester, s, state: _state());
      await tester.tap(find.byKey(const Key('morning_optin')));
      await _settle(tester);
      expect(await s.settings.get(SettingKeys.morningCameraRmssdOptIn), '1');
      expect(
        _text(tester, 'morning_rmssd_mark'),
        'experimentell, mit einem Brustgurt verglichen (ein Handy)',
      );
    });

    testWidgets('sitzend im Sitzen eingeschränkt: ungenauer als erwartet, '
        'kein Schalter; Ruhepuls nicht bestanden ebenso', (tester) async {
      final s = await _session(dev: false, optIn: true);
      await _pump(
        tester,
        s,
        state: _state(
          sitting: ValidationState.limited,
          hr: ValidationState.failed,
        ),
      );
      await tester.tap(find.text('Sitzend'));
      await tester.pump();
      expect(_text(tester, 'morning_rmssd_mark'), 'ungenauer als erwartet');
      expect(_text(tester, 'morning_hr_mark'), 'ungenauer als erwartet');
      expect(find.byKey(const Key('morning_optin')), findsNothing);
    });

    testWidgets('lnRMSSD liegend nicht bestanden ohne Modus: nichts, auch '
        'nichts Gespeichertes', (tester) async {
      final s = await _session(dev: false);
      await _pump(tester, s, state: _state(supine: ValidationState.failed));
      expect(find.byKey(const Key('morning_series_info')), findsNothing);
      expect(find.byKey(const Key('morning_hr_card')), findsNothing);
      expect(find.byKey(const Key('morning_window')), findsNothing);
    });

    testWidgets('nicht zählende Messungen fehlen; Reihenwechsel', (
      tester,
    ) async {
      final s = await _session(dev: true);
      await _pump(tester, s, state: _state());
      // liegend: 5 Tage, heute die erste Messung (52,4; nicht 70).
      expect(
        _text(tester, 'morning_series_info'),
        'Reihe mit diesem Handy · letzte 14 Tage · 5 gültige Morgen',
      );
      expect(_text(tester, 'morning_hr_card_last'), '52,4');
      expect(
        find.textContaining('Mittel der letzten 7 Morgen, 53,6'),
        findsWidgets,
      );
      await tester.tap(find.text('Sitzend'));
      await tester.pump();
      expect(
        _text(tester, 'morning_series_info'),
        'Reihe mit diesem Handy · letzte 14 Tage · 2 gültige Morgen',
      );
      expect(_text(tester, 'morning_hr_card_last'), '58,4');
    });

    testWidgets('leere Reihe: Hinweis statt Diagramm', (tester) async {
      final s = await FakeStorage().open(testKey);
      await SettingsDeveloperModeStore(s.settings, _clock).set(true);
      await _pump(tester, s, state: _state());
      expect(find.byKey(const Key('morning_trend_empty')), findsOneWidget);
      expect(find.byKey(const Key('morning_hr_card')), findsNothing);
    });

    testWidgets('Morgenfenster: Vorgabe, ändern, ungültig gesperrt', (
      tester,
    ) async {
      final s = await _session(dev: true);
      await _pump(tester, s, state: _state());
      expect(_text(tester, 'morning_window_value'), '4 bis 11 Uhr');
      expect(find.byKey(const Key('morning_reminder_slot')), findsOneWidget);
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
