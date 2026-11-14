import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/measure/morning_entry.dart';
import 'package:running_app/features/measure/morning_trend_screen.dart';
import 'package:running_app/features/measure/resting_measure_launcher.dart';
import 'package:running_app/l10n/app_localizations.dart';
import 'package:running_app/ui/ui.dart';

import '../history_summary_test.dart' show started;
import 'measure_support.dart';

// Sichtbarkeit der Morgenmessung (FR-0217, K62 Punkt 1) und ihre Einstiege auf
// Heute und im Profil. Alle Werte synthetisch.

Map<ValidationQuantity, ValidationState> _state(
  ValidationState hr,
  ValidationState supine,
  ValidationState sitting,
) => {
  ValidationQuantity.restingHr: hr,
  ValidationQuantity.lnRmssdSupine: supine,
  ValidationQuantity.lnRmssdSitting: sitting,
};

final _clock = FakeClock(DateTime.utc(2026, 11, 10, 8, 0));

Future<StorageSession> _session({required bool dev}) async {
  final s = await FakeStorage().open(testKey);
  if (dev) await SettingsDeveloperModeStore(s.settings, _clock).set(true);
  return s;
}

MorningMeasurement _today({double bpm = 52.4, double? rmssd = 48}) =>
    MorningMeasurement(
      measuredAt: DateTime.utc(2026, 11, 10, 6, 42),
      utcOffset: Duration.zero,
      posture: RestingPosture.lying,
      deviceManufacturer: 'T',
      deviceModel: 'M',
      method: ppgMethod,
      methodVersion: ppgMethodVersion,
      quality: PpgQuality.good,
      restingHrBpm: bpm,
      rmssdMs: rmssd,
      cameraIntervalsMs: const [],
      beforeValidation: true,
      outsideWindow: false,
    );

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  required bool dark,
  bool camera = true,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  Widget home = Scaffold(body: SingleChildScrollView(child: child));
  if (camera) home = PpgCameraScope(camera: FakePpgCamera(), child: home);
  await tester.pumpWidget(
    MaterialApp(
      theme: dark ? RamuriTheme.dark : RamuriTheme.light,
      locale: const Locale('de'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: home,
    ),
  );
  for (var i = 0; i < 3; i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
  }
}

void main() {
  // Alle Stände von lnRMSSD liegend, je mit und ohne Entwicklermodus. Für alle
  // erst bei „bestanden“; im Entwicklermodus immer.
  for (final supine in ValidationState.values) {
    for (final dev in [false, true]) {
      final shown = dev || supine == ValidationState.passed;
      final label =
          'lnRMSSD liegend ${supine.name}, Modus ${dev ? 'an' : 'aus'}';
      testWidgets('Heute: $label -> Karte ${shown ? 'da' : 'weg'}', (
        tester,
      ) async {
        final s = await _session(dev: dev);
        await _pump(
          tester,
          MorningCard(
            session: s,
            clock: _clock,
            validationState: _state(
              ValidationState.passed,
              supine,
              ValidationState.passed,
            ),
          ),
          dark: false,
        );
        expect(
          find.byKey(const Key('morning_card')),
          shown ? findsOneWidget : findsNothing,
        );
      });

      testWidgets('Profil: $label -> Eintrag ${shown ? 'da' : 'weg'}', (
        tester,
      ) async {
        final s = await _session(dev: dev);
        await _pump(
          tester,
          MorningTile(
            session: s,
            clock: _clock,
            validationState: _state(
              ValidationState.passed,
              supine,
              ValidationState.passed,
            ),
          ),
          dark: false,
        );
        expect(
          find.byKey(const Key('overview_morning')),
          shown ? findsOneWidget : findsNothing,
        );
      });
    }
  }

  testWidgets('Ruhepuls und sitzend bestanden, lnRMSSD liegend nicht: '
      'ohne Modus nirgends', (tester) async {
    final s = await _session(dev: false);
    final st = _state(
      ValidationState.passed,
      ValidationState.failed,
      ValidationState.passed,
    );
    await _pump(
      tester,
      Column(
        children: [
          MorningCard(session: s, clock: _clock, validationState: st),
          MorningTile(session: s, clock: _clock, validationState: st),
        ],
      ),
      dark: false,
    );
    expect(find.byKey(const Key('morning_card')), findsNothing);
    expect(find.byKey(const Key('overview_morning')), findsNothing);
  });

  testWidgets('ohne Kamera kein Einstieg', (tester) async {
    final s = await _session(dev: true);
    await _pump(
      tester,
      Column(
        children: [
          MorningCard(session: s, clock: _clock),
          MorningTile(session: s, clock: _clock),
        ],
      ),
      dark: false,
      camera: false,
    );
    expect(find.byKey(const Key('morning_card')), findsNothing);
    expect(find.byKey(const Key('overview_morning')), findsNothing);
  });

  for (final dark in [false, true]) {
    final mode = dark ? 'dunkel' : 'hell';

    testWidgets('Karte offen ($mode): Text, Start, Hinweis Entwicklermodus', (
      tester,
    ) async {
      final s = await _session(dev: true);
      await _pump(
        tester,
        MorningCard(session: s, clock: _clock),
        dark: dark,
      );
      expect(find.text('Morgenmessung'), findsOneWidget);
      expect(
        find.text(
          'Heute noch nicht gemessen. 2 min Ruhe, dann 60 s mit der Kamera.',
        ),
        findsOneWidget,
      );
      expect(find.text('Jetzt messen'), findsOneWidget);
      expect(find.byKey(const Key('morning_dev_hint')), findsOneWidget);
      expect(find.text('Entwicklermodus aktiv'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('morning_card_history')));
      await tester.tap(find.byKey(const Key('morning_card_history')));
      await tester.pumpAndSettle();
      expect(find.byType(MorningTrendScreen), findsOneWidget);
      await tester.tap(find.byKey(const Key('measure_back')));
      await tester.pumpAndSettle();
      final size = tester.getSize(find.byKey(const Key('morning_card_start')));
      expect(size.height, greaterThanOrEqualTo(48));

      await tester.tap(find.byKey(const Key('morning_card_start')));
      await tester.pumpAndSettle();
      // Der Ablauf beginnt mit dem Einstieg der Morgenmessung.
      expect(find.byKey(const Key('morning_start')), findsOneWidget);
    });

    testWidgets('Karte mit heutiger Messung ($mode), ohne Modus kein Hinweis', (
      tester,
    ) async {
      final s = await _session(dev: false);
      await (s as MorningStorage).morning.add(_today());
      await _pump(
        tester,
        MorningCard(
          session: s,
          clock: _clock,
          validationState: _state(
            ValidationState.passed,
            ValidationState.passed,
            ValidationState.passed,
          ),
        ),
        dark: dark,
      );
      expect(find.text('Heute 06:42, liegend'), findsOneWidget);
      expect(find.text('52,4'), findsOneWidget);
      expect(find.text('48'), findsOneWidget);
      expect(find.byKey(const Key('morning_card_start')), findsNothing);
      expect(find.byKey(const Key('morning_dev_hint')), findsNothing);
    });
  }

  testWidgets('Messung von gestern: Karte ist wieder offen', (tester) async {
    final s = await _session(dev: true);
    final y = _today();
    await (s as MorningStorage).morning.add(
      MorningMeasurement(
        measuredAt: y.measuredAt.subtract(const Duration(days: 1)),
        utcOffset: y.utcOffset,
        posture: y.posture,
        deviceManufacturer: y.deviceManufacturer,
        deviceModel: y.deviceModel,
        method: y.method,
        methodVersion: y.methodVersion,
        quality: y.quality,
        restingHrBpm: y.restingHrBpm,
        rmssdMs: y.rmssdMs,
        cameraIntervalsMs: const [],
        beforeValidation: true,
        outsideWindow: false,
      ),
    );
    await _pump(tester, MorningCard(session: s, clock: _clock), dark: false);
    expect(find.byKey(const Key('morning_card_start')), findsOneWidget);
  });

  testWidgets('App: ohne Entwicklermodus nirgends, mit Modus auf Heute und in '
      'der Übersicht', (tester) async {
    final d = await started(tester);
    expect(find.byKey(const Key('morning_card')), findsNothing);
    await tester.tap(find.byKey(const Key('home_overview')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('overview_morning')), findsNothing);

    await SettingsDeveloperModeStore(d.session.settings, d.clock).set(true);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('home_overview')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('overview_morning')), findsOneWidget);
    await tester.tap(find.byKey(const Key('overview_morning_values')));
    await tester.pumpAndSettle();
    expect(find.byType(MorningTrendScreen), findsOneWidget);
    await tester.tap(find.byKey(const Key('measure_back')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('overview_morning')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('morning_start')), findsOneWidget);
    await tester.tap(find.byKey(const Key('measure_back')));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('morning_card')), findsOneWidget);
    expect(find.text('Entwicklermodus aktiv'), findsOneWidget);

    // Modus aus: Einstieg verschwindet wieder.
    await SettingsDeveloperModeStore(d.session.settings, d.clock).set(false);
    await tester.tap(find.byKey(const Key('home_overview')));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('morning_card')), findsNothing);
  });
}
