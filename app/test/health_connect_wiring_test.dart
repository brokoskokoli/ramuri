import 'package:core/core.dart';
import 'package:core/fakes/fake_storage_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_harness.dart';

class _CountingPort implements HealthConnectPort {
  _CountingPort([this.status = HealthSdkStatus.unavailable]);
  final HealthSdkStatus status;
  int statusCalls = 0;

  @override
  Future<HealthSdkStatus> sdkStatus() async {
    statusCalls++;
    return status;
  }

  @override
  Future<Set<HealthDataKind>> grantedKinds() async => const {};

  @override
  Future<Set<HealthDataKind>> requestPermissions(
    Set<HealthDataKind> kinds,
  ) async => const {};

  @override
  Future<bool> openInstall() async => false;

  @override
  Future<HealthPage> readPage({
    required HealthDataKind kind,
    required DateTime from,
    required DateTime to,
    String? pageToken,
    int? pageSize,
  }) async => throw const HealthReadException(HealthReadError.unavailable);
}

void main() {
  testWidgets(
    'App-Start und Heute rufen den Import einmal; Seite „nicht verfügbar“ '
    'über die Einstellungen',
    (tester) async {
      final device = Device();
      final port = _CountingPort();
      device.healthConnect = port;
      await device.start(tester, const Locale('de'));
      // In der Einrichtung (auch vor einer Wiederherstellung) wird nichts importiert.
      expect(port.statusCalls, 0);
      await device.skipSetup(tester);
      // Nach der Einrichtung laufen App-Start und Heute (Import und Zustand lesen fragen den Status).
      expect(port.statusCalls, greaterThan(0));

      await openOverview(tester);
      await tapKey(tester, 'home_settings');
      await tapKey(tester, 'settings_health');
      expect(
        find.byKey(const Key('health_unavailable_unsupported')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await device.stop(tester);
    },
  );

  testWidgets(
    'Zurück zu „Heute“ importiert erneut (Sperre greift nur nach Lesen)',
    (tester) async {
      final device = Device();
      final port = _CountingPort();
      device.healthConnect = port;
      await device.start(tester, const Locale('de'));
      await device.skipSetup(tester);
      final afterStart = port.statusCalls;
      expect(afterStart, greaterThan(0));
      await tapKey(tester, 'home_plan');
      expect(port.statusCalls, afterStart);
      await tapKey(tester, 'home_today');
      expect(port.statusCalls, greaterThan(afterStart));
      await device.stop(tester);
    },
  );

  for (final status in [
    HealthSdkStatus.available,
    HealthSdkStatus.unavailable,
  ]) {
    testWidgets('Offene Löschfrage erscheint nach dem Start (${status.name}), '
        'ohne die Health-Connect-Seite zu öffnen (SEC-0007)', (tester) async {
      final device = Device();
      // Eingewilligt mit gespeicherten Daten, aber ohne Recht in Health Connect bzw. ohne Health Connect.
      device.healthConnect = _CountingPort(status);
      final consents = FakeConsentStore(device.storage.data);
      await ConsentService(
        consents,
        device.clock,
      ).grant(healthSourceKey(HealthDataKind.vo2Max));
      await device.storage.data.health.upsertValues([
        HealthRecord(
          kind: HealthDataKind.vo2Max,
          id: 'v1',
          origin: 'x',
          start: DateTime.utc(2026, 11, 1),
          end: DateTime.utc(2026, 11, 1),
          value: 48,
        ),
      ]);
      await device.start(tester, const Locale('de'));
      expect(find.byKey(const Key('health_delete_dialog')), findsNothing);
      await device.skipSetup(tester);
      expect(find.byKey(const Key('health_delete_dialog')), findsOneWidget);
      // „Behalten“: Daten bleiben, die Frage ist beantwortet.
      await tapKey(tester, 'health_delete_keep');
      expect(find.byKey(const Key('health_delete_dialog')), findsNothing);
      expect(await device.storage.data.health.count(HealthDataKind.vo2Max), 1);
      await device.stop(tester);
    });
  }
}
