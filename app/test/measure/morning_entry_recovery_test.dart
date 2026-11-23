import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/measure/morning_entry.dart';
import 'package:running_app/features/measure/resting_measure_launcher.dart';
import 'package:running_app/features/plan/plan_recovery_trigger.dart';
import 'package:running_app/l10n/app_localizations.dart';
import 'package:running_app/ui/ui.dart';

import 'measure_support.dart';
import '../support/settle_storage.dart';

// Auslöser „veränderter Erholungszustand“ nach der Morgenmessung (FR-0157,
// Teil „3 (Erholung)“): Nach dem Schließen der Messseite prüft die App den
// Plan von heute genau einmal, vorher nicht. Alle Werte synthetisch.

final _clock = FakeClock(DateTime.utc(2026, 11, 10, 8, 0));

/// Zählt die Prüfungen statt den Plan zu rechnen.
class _CountingTrigger extends PlanRecoveryTrigger {
  _CountingTrigger(StorageSession s)
    : super(session: s, clock: _clock, readinessToday: (_) async => null);

  int calls = 0;

  @override
  Future<bool> recheck() async {
    calls++;
    return false;
  }
}

void main() {
  testWidgets('Morgenmessung schließen: Plan von heute wird einmal geprüft', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final s = (await tester.runAsync(() => FakeStorage().open(testKey)))!;
    final trigger = _CountingTrigger(s);
    Future<void>? opened;
    await tester.pumpWidget(
      MaterialApp(
        theme: RamuriTheme.light,
        locale: const Locale('de'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: PpgCameraScope(
          camera: FakePpgCamera(),
          child: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                key: const Key('open'),
                onPressed: () => opened = openMorningMeasurement(
                  context,
                  session: s,
                  clock: _clock,
                  recovery: trigger,
                ),
                child: const Text('Öffnen'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('open')));
    await settleStorage(
      tester,
      what: 'Seite geöffnet',
      frame: const Duration(milliseconds: 100),
    );
    expect(find.byKey(const Key('open')).hitTestable(), findsNothing);
    expect(trigger.calls, 0, reason: 'Seite offen: noch keine Prüfung');
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await settleStorage(
      tester,
      what: 'Seite geschlossen',
      frame: const Duration(milliseconds: 100),
    );
    await tester.runAsync(() => opened!);
    expect(trigger.calls, 1, reason: 'nach dem Schließen genau einmal');
  });
}
