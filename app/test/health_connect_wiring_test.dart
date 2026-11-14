import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_harness.dart';

class _CountingPort implements HealthConnectPort {
  int statusCalls = 0;

  @override
  Future<HealthSdkStatus> sdkStatus() async {
    statusCalls++;
    return HealthSdkStatus.unavailable;
  }

  @override
  Future<Set<HealthDataKind>> grantedKinds() async => const {};

  @override
  Future<Set<HealthDataKind>> requestPermissions(
    Set<HealthDataKind> kinds,
  ) async => const {};

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
      // App-Start und Öffnen von Heute laufen zusammen; die Sperre lässt einen Lauf durch.
      expect(port.statusCalls, 1);

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
}
