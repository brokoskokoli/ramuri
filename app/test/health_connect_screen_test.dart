import 'package:core/core.dart';
import 'package:core/fakes/fake_storage_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/health/health_connect_controller.dart';
import 'package:running_app/features/health/health_connect_screen.dart';

import 'helpers/widget_helpers.dart';

/// Port mit festem Zustand; liest nie etwas (die Seite fragt nur Zustand und Rechte).
class _Port implements HealthConnectPort {
  _Port(this.status, [Set<HealthDataKind>? granted])
    : granted = granted ?? HealthDataKind.values.toSet();
  HealthSdkStatus status;
  Set<HealthDataKind> granted;
  Set<HealthDataKind>? requested;

  @override
  Future<HealthSdkStatus> sdkStatus() async => status;

  @override
  Future<Set<HealthDataKind>> grantedKinds() async => granted;

  @override
  Future<Set<HealthDataKind>> requestPermissions(
    Set<HealthDataKind> kinds,
  ) async {
    requested = kinds;
    return kinds;
  }

  @override
  Future<HealthPage> readPage({
    required HealthDataKind kind,
    required DateTime from,
    required DateTime to,
    String? pageToken,
    int? pageSize,
  }) async => const HealthPage([], null);
}

HealthRecord _rec(HealthDataKind kind, String id) => HealthRecord(
  kind: kind,
  id: id,
  origin: 'x',
  start: DateTime.utc(2026, 11, 1),
  end: DateTime.utc(2026, 11, 1, 1),
  value: 50,
  unit: 'bpm',
);

Future<(HealthConnectController, FakeStorage, _Port)> _setup(
  WidgetTester tester, {
  HealthSdkStatus status = HealthSdkStatus.available,
  Set<HealthDataKind>? granted,
  Set<HealthDataKind> consented = const {},
  Map<HealthDataKind, int> stored = const {},
  Brightness brightness = Brightness.light,
}) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final storage = FakeStorage();
  final clock = FakeClock(DateTime.utc(2026, 11, 14, 12));
  final port = _Port(status, granted);
  final c = HealthConnectController(
    port: port,
    store: storage.data.health,
    settings: FakeSettingsStore(storage.data),
    consentStore: FakeConsentStore(storage.data),
    clock: clock,
  );
  for (final k in consented) {
    await c.consents.grant(healthSourceKey(k));
  }
  for (final e in stored.entries) {
    await storage.data.health.upsertValues([
      for (var i = 0; i < e.value; i++) _rec(e.key, '${e.key.key}$i'),
    ]);
  }
  await tester.pumpWidget(
    localizedApp(
      brightness: brightness,
      home: HealthConnectScreen(controller: c),
    ),
  );
  await tester.pumpAndSettle();
  return (c, storage, port);
}

void main() {
  testWidgets('Schalter ändert nur die eigene Art', (tester) async {
    final (c, _, _) = await _setup(tester);
    await tapKey(tester, 'health_switch_sleep');
    expect(c.enabled, {HealthDataKind.sleep});
    expect(
      await c.consents.isGranted(healthSourceKey(HealthDataKind.sleep)),
      isTrue,
    );
    for (final k in HealthDataKind.values.where(
      (k) => k != HealthDataKind.sleep,
    )) {
      expect(await c.consents.isGranted(healthSourceKey(k)), isFalse);
    }
    expect(
      tester.widget<SwitchListTile>(key('health_switch_sleep')).value,
      isTrue,
    );
    expect(
      tester.widget<SwitchListTile>(key('health_switch_vo2_max')).value,
      isFalse,
    );
  });

  testWidgets('Weiter fordert nur eingeschaltete Arten an', (tester) async {
    final (c, _, port) = await _setup(
      tester,
      granted: const {},
      consented: {HealthDataKind.sleep, HealthDataKind.hrvRmssd},
    );
    await tapKey(tester, 'health_continue');
    expect(port.requested, {HealthDataKind.sleep, HealthDataKind.hrvRmssd});
    expect(c.permitted, port.requested);
  });

  testWidgets('Widerruf zeigt Löschfrage; Behalten lässt die Daten', (
    tester,
  ) async {
    final (c, storage, _) = await _setup(
      tester,
      consented: {HealthDataKind.sleep, HealthDataKind.vo2Max},
      stored: {HealthDataKind.sleep: 2, HealthDataKind.vo2Max: 1},
    );
    await tapKey(tester, 'health_switch_sleep');
    expect(key('health_delete_dialog'), findsOneWidget);
    // Ab jetzt gilt der Widerruf, auch bevor geantwortet ist.
    expect(
      await c.consents.isGranted(healthSourceKey(HealthDataKind.sleep)),
      isFalse,
    );
    await tapKey(tester, 'health_delete_keep');
    expect(key('health_delete_dialog'), findsNothing);
    expect(await storage.data.health.count(HealthDataKind.sleep), 2);
    expect(
      await c.consents.isDeleteQuestionOpen(
        healthSourceKey(HealthDataKind.sleep),
      ),
      isFalse,
    );
  });

  testWidgets('Löschen leert nur die Daten dieser Art', (tester) async {
    final (c, storage, _) = await _setup(
      tester,
      consented: {HealthDataKind.sleep, HealthDataKind.vo2Max},
      stored: {HealthDataKind.sleep: 2, HealthDataKind.vo2Max: 1},
    );
    await tapKey(tester, 'health_switch_sleep');
    // Vor der Bestätigung ist noch nichts gelöscht.
    expect(await storage.data.health.count(HealthDataKind.sleep), 2);
    await tapKey(tester, 'health_delete_confirm');
    expect(await storage.data.health.count(HealthDataKind.sleep), 0);
    expect(await storage.data.health.count(HealthDataKind.vo2Max), 1);
    expect(c.enabled, {HealthDataKind.vo2Max});
  });

  testWidgets('Abbrechen schaltet wieder ein und löscht nichts', (
    tester,
  ) async {
    final (c, storage, _) = await _setup(
      tester,
      consented: {HealthDataKind.sleep},
      stored: {HealthDataKind.sleep: 2},
    );
    await tapKey(tester, 'health_switch_sleep');
    await tapKey(tester, 'health_delete_cancel');
    expect(await storage.data.health.count(HealthDataKind.sleep), 2);
    expect(c.enabled, {HealthDataKind.sleep});
    expect(
      await c.consents.isGranted(healthSourceKey(HealthDataKind.sleep)),
      isTrue,
    );
  });

  testWidgets('Fehlendes Recht in Health Connect: Löschfrage beim Öffnen', (
    tester,
  ) async {
    final (c, storage, _) = await _setup(
      tester,
      granted: HealthDataKind.values.toSet()..remove(HealthDataKind.sleep),
      consented: {HealthDataKind.sleep, HealthDataKind.vo2Max},
      stored: {HealthDataKind.sleep: 1, HealthDataKind.vo2Max: 1},
    );
    expect(key('health_delete_dialog'), findsOneWidget);
    await tapKey(tester, 'health_delete_confirm');
    expect(key('health_delete_dialog'), findsNothing);
    expect(await storage.data.health.count(HealthDataKind.sleep), 0);
    expect(await storage.data.health.count(HealthDataKind.vo2Max), 1);
    expect(
      await c.consents.isDeleteQuestionOpen(
        healthSourceKey(HealthDataKind.sleep),
      ),
      isFalse,
    );
  });

  testWidgets('Fehlendes Recht ohne importierte Daten: keine Frage', (
    tester,
  ) async {
    await _setup(tester, granted: const {}, consented: {HealthDataKind.sleep});
    expect(key('health_delete_dialog'), findsNothing);
  });

  for (final (status, k) in [
    (HealthSdkStatus.updateRequired, 'health_unavailable_install'),
    (HealthSdkStatus.unavailable, 'health_unavailable_unsupported'),
  ]) {
    testWidgets('Nicht verfügbar ($status): ohne Absturz, dunkel', (
      tester,
    ) async {
      await _setup(tester, status: status, brightness: Brightness.dark);
      expect(key(k), findsOneWidget);
      expect(key('health_switch_sleep'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Jetzt abrufen zeigt den Zeitpunkt', (tester) async {
    final (c, _, _) = await _setup(tester, consented: {HealthDataKind.sleep});
    expect(find.text('Noch nie'), findsOneWidget);
    await tapKey(tester, 'health_fetch');
    expect(find.text('Noch nie'), findsNothing);
    expect(c.lastImport, isNotNull);
  });
}
