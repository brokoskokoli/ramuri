import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/run/run_ports.dart';

import 'app_harness.dart';
import 'run_test.dart' show key, openRun, walk;

/// Ein Lauf, den der Prozess nicht mehr beendet: App zu, Lauf bleibt aktiv.
Future<int> crash(Device d, WidgetTester tester) async {
  await openRun(d, tester);
  await walk(d, tester, 20);
  final id = (await d.session.runs.list()).single.id;
  await d.stop(tester);
  return id;
}

Future<void> restart(Device d, WidgetTester tester) async {
  await d.start(tester, const Locale('de'));
}

void main() {
  group('Wiederaufnahme (FR-0193)', () {
    testWidgets('ohne unfertigen Lauf kein Angebot', (tester) async {
      final d = Device();
      await d.start(tester, const Locale('de'));
      await d.skipSetup(tester);
      expect(key('recover_dialog'), findsNothing);
    });

    testWidgets('nach normalem Ende kein Angebot', (tester) async {
      final d = Device();
      await openRun(d, tester);
      await walk(d, tester, 10);
      await tester.tap(key('run_finish'));
      await tester.pumpAndSettle();
      await tester.tap(key('run_finish_confirm'));
      await tester.pumpAndSettle();
      expect((await d.session.runs.list()).single.state, RunState.finished);
      await d.stop(tester);
      await restart(d, tester);
      expect(key('recover_dialog'), findsNothing);
    });

    testWidgets('unfertiger Lauf: Angebot; Speichern beendet ihn, danach '
        'kein Angebot mehr', (tester) async {
      final d = Device();
      await crash(d, tester);
      d.clock.advance(const Duration(hours: 1));
      await restart(d, tester);
      expect(key('recover_dialog'), findsOneWidget);
      await tester.tap(key('recover_save'));
      await tester.pumpAndSettle();
      expect(key('recover_dialog'), findsNothing);
      final runs = await d.session.runs.list();
      expect(runs.single.state, RunState.finished);
      expect(runs.single.endedAt, isNot(d.clock.now()));
      expect(runs.single.endedUtcOffset, isNotNull);
      await d.stop(tester);
      await restart(d, tester);
      expect(key('recover_dialog'), findsNothing);
    });

    testWidgets('Fortsetzen nach 400 Tagen: gleicher Lauf, Lücke markiert', (
      tester,
    ) async {
      final d = Device();
      final id = await crash(d, tester);
      d.clock.advance(const Duration(days: 400));
      await restart(d, tester);
      expect(key('recover_dialog'), findsOneWidget);
      await tester.tap(key('recover_resume'));
      await tester.pumpAndSettle();
      expect(key('recover_dialog'), findsNothing);
      final runs = await d.session.runs.list();
      expect(runs.single.id, id);
      expect(runs.single.state, RunState.active);
      final gaps = await d.session.markers.gaps(id);
      expect(gaps.map((g) => g.kind), contains(RunGapKind.interruption));
      // Lauf läuft weiter: der Bildschirm zeigt die Steuerung.
      expect(key('run_pause'), findsOneWidget);
    });

    testWidgets('mit laufendem Dienst kein Angebot', (tester) async {
      final d = Device();
      await crash(d, tester);
      d.recordingService = FakeRecordingServicePort()..running = true;
      await restart(d, tester);
      expect(key('recover_dialog'), findsNothing);
    });

    testWidgets('ohne Standortrecht: Fortsetzen blockiert, Speichern geht', (
      tester,
    ) async {
      final d = Device();
      await crash(d, tester);
      d.locationAccess.current = LocationAccess.denied;
      await restart(d, tester);
      await tester.tap(key('recover_resume'));
      await tester.pumpAndSettle();
      expect(key('run_block_permissionDenied'), findsOneWidget);
      expect((await d.session.runs.list()).single.state, RunState.active);
      await d.stop(tester);
      await restart(d, tester);
      await tester.tap(key('recover_save'));
      await tester.pumpAndSettle();
      expect((await d.session.runs.list()).single.state, RunState.finished);
    });
  });
}
