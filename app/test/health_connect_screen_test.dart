import 'dart:async';

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

  int installOpened = 0;
  bool installResult = true;

  @override
  Future<bool> openInstall() async {
    installOpened++;
    return installResult;
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

/// Einwilligungsspeicher, der das Lesen der Löschfragen zurückhalten kann: Solange [hold] gesetzt ist, liefert jedes
/// Lesen eines Eintrags „Löschfrage offen“ den Stand vom Aufruf erst, wenn [hold] erfüllt ist.
class _HeldConsentStore extends FakeConsentStore {
  _HeldConsentStore(super.d);
  Completer<void>? hold;
  int held = 0;

  @override
  Future<ConsentState?> get(String sourceKey) async {
    final value = await super.get(sourceKey);
    final h = hold;
    if (h != null && sourceKey.endsWith('.delete_question')) {
      held++;
      await h.future;
    }
    return value;
  }
}

Future<(HealthConnectController, FakeStorage, _Port)> _setup(
  WidgetTester tester, {
  HealthSdkStatus status = HealthSdkStatus.available,
  Set<HealthDataKind>? granted,
  Set<HealthDataKind> consented = const {},
  Map<HealthDataKind, int> stored = const {},
  Brightness brightness = Brightness.light,
  FakeStorage? storage,
  ConsentStore? consentStore,
}) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  storage ??= FakeStorage();
  final clock = FakeClock(DateTime.utc(2026, 11, 14, 12));
  final port = _Port(status, granted);
  final c = healthConnectSession(
    port: port,
    store: storage.data.health,
    settings: FakeSettingsStore(storage.data),
    consentStore: consentStore ?? FakeConsentStore(storage.data),
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

  // Import beim Öffnen von „Heute“, der erst nach dem Ausschalten fertig wird und dann die offenen Löschfragen stellt.
  Future<Completer<void>> startDelayedImport(
    WidgetTester tester,
    HealthConnectController c,
  ) async {
    final gate = Completer<void>();
    final context = tester.element(find.byType(HealthConnectScreen));
    unawaited(() async {
      await gate.future;
      await c.importThenLoad(HealthImportTrigger.todayOpened);
      if (context.mounted) {
        await askOpenHealthQuestions(context, c, skipDeferred: true);
      }
    }());
    return gate;
  }

  for (final (answer, deleted, onAgain) in [
    ('health_delete_keep', false, false),
    ('health_delete_confirm', true, false),
    ('health_delete_cancel', false, true),
  ]) {
    testWidgets('Widerruf während verzögertem Import: genau eine Löschfrage '
        '($answer)', (tester) async {
      final (c, storage, _) = await _setup(
        tester,
        consented: {HealthDataKind.sleep, HealthDataKind.vo2Max},
        stored: {HealthDataKind.sleep: 2, HealthDataKind.vo2Max: 1},
      );
      final gate = await startDelayedImport(tester, c);
      await tapKey(tester, 'health_switch_sleep');
      expect(key('health_delete_dialog'), findsOneWidget);
      // Der Import endet, während die Frage des Schalters offen ist.
      gate.complete();
      await tester.pumpAndSettle();
      expect(key('health_delete_dialog'), findsOneWidget);
      await tapKey(tester, answer);
      await tester.pumpAndSettle();
      // Die Antwort gilt einmal: keine weitere Frage zu dieser Art.
      expect(key('health_delete_dialog'), findsNothing);
      expect(c.questions, isNot(contains(HealthDataKind.sleep)));
      expect(
        await c.consents.isDeleteQuestionOpen(
          healthSourceKey(HealthDataKind.sleep),
        ),
        isFalse,
      );
      expect(
        await storage.data.health.count(HealthDataKind.sleep),
        deleted ? 0 : 2,
      );
      expect(await storage.data.health.count(HealthDataKind.vo2Max), 1);
      expect(
        await c.consents.isGranted(healthSourceKey(HealthDataKind.sleep)),
        onAgain,
      );
      expect(c.enabled.contains(HealthDataKind.sleep), onAgain);
    });
  }

  testWidgets('Widerruf während verzögertem Import: andere Art danach', (
    tester,
  ) async {
    final (c, storage, port) = await _setup(
      tester,
      consented: {HealthDataKind.sleep, HealthDataKind.vo2Max},
      stored: {HealthDataKind.sleep: 2, HealthDataKind.vo2Max: 1},
    );
    final gate = await startDelayedImport(tester, c);
    await tapKey(tester, 'health_switch_sleep');
    // Während die Frage offen ist, fehlt in Health Connect das Recht einer anderen Art.
    port.granted = HealthDataKind.values.toSet()..remove(HealthDataKind.vo2Max);
    gate.complete();
    await tester.pumpAndSettle();
    expect(key('health_delete_dialog'), findsOneWidget);
    await tapKey(tester, 'health_delete_keep');
    await tester.pumpAndSettle();
    // Die Frage der anderen Art kommt danach, allein.
    expect(key('health_delete_dialog'), findsOneWidget);
    expect(c.questions, [HealthDataKind.vo2Max]);
    await tapKey(tester, 'health_delete_confirm');
    await tester.pumpAndSettle();
    expect(key('health_delete_dialog'), findsNothing);
    expect(await storage.data.health.count(HealthDataKind.sleep), 2);
    expect(await storage.data.health.count(HealthDataKind.vo2Max), 0);
  });

  testWidgets('Zwei Aufrufe derselben Löschfrage: nur ein Dialog', (
    tester,
  ) async {
    final (c, storage, _) = await _setup(
      tester,
      consented: {HealthDataKind.sleep},
      stored: {HealthDataKind.sleep: 2},
    );
    await c.disable(HealthDataKind.sleep);
    final context = tester.element(find.byType(HealthConnectScreen));
    final first = askHealthDeleteQuestion(
      context,
      c,
      HealthDataKind.sleep,
      fromSwitch: false,
    );
    final second = askHealthDeleteQuestion(
      context,
      c,
      HealthDataKind.sleep,
      fromSwitch: false,
    );
    await tester.pumpAndSettle();
    expect(key('health_delete_dialog'), findsOneWidget);
    expect(await second, isFalse);
    await tapKey(tester, 'health_delete_keep');
    expect(await first, isTrue);
    expect(key('health_delete_dialog'), findsNothing);
    expect(await storage.data.health.count(HealthDataKind.sleep), 2);
  });

  BuildContext screenContext(WidgetTester tester) =>
      tester.element(find.byType(HealthConnectScreen));

  testWidgets('Neue Frage während der Abfolge: in derselben Sitzung gefragt', (
    tester,
  ) async {
    final (c, storage, port) = await _setup(
      tester,
      granted: HealthDataKind.values.toSet()..remove(HealthDataKind.sleep),
      consented: {HealthDataKind.sleep, HealthDataKind.vo2Max},
      stored: {HealthDataKind.sleep: 2, HealthDataKind.vo2Max: 1},
    );
    // Die Abfolge der Seite steht bei der Frage zu Schlaf.
    expect(key('health_delete_dialog'), findsOneWidget);
    expect(c.asking, isTrue);
    // Ein späteres Laden öffnet die Frage zu VO2max; der zweite Aufruf kehrt sofort zurück.
    port.granted = port.granted.difference({HealthDataKind.vo2Max});
    await c.load();
    expect(c.questions, [HealthDataKind.sleep, HealthDataKind.vo2Max]);
    await askOpenHealthQuestions(screenContext(tester), c, skipDeferred: true);
    expect(key('health_delete_dialog'), findsOneWidget);
    await tapKey(tester, 'health_delete_keep');
    await tester.pumpAndSettle();
    // Danach genau ein Dialog zu VO2max, ohne die Seite neu zu öffnen.
    expect(key('health_delete_dialog'), findsOneWidget);
    expect(c.questions, [HealthDataKind.vo2Max]);
    await tapKey(tester, 'health_delete_confirm');
    await tester.pumpAndSettle();
    expect(key('health_delete_dialog'), findsNothing);
    expect(c.asking, isFalse);
    expect(await storage.data.health.count(HealthDataKind.sleep), 2);
    expect(await storage.data.health.count(HealthDataKind.vo2Max), 0);
  });

  for (final (secondSkips, asked) in [(false, true), (true, false)]) {
    testWidgets('Zurückgestellte Frage während der Abfolge von „Heute“: '
        'zweiter Aufruf skipDeferred: $secondSkips', (tester) async {
      final (c, _, port) = await _setup(
        tester,
        consented: {HealthDataKind.sleep, HealthDataKind.vo2Max},
        stored: {HealthDataKind.sleep: 2, HealthDataKind.vo2Max: 1},
      );
      // VO2max wurde beim Öffnen der App schon zurückgestellt.
      c.deferred.add(HealthDataKind.vo2Max);
      port.granted = HealthDataKind.values.toSet().difference({
        HealthDataKind.sleep,
        HealthDataKind.vo2Max,
      });
      await c.load();
      expect(c.questions, [HealthDataKind.sleep, HealthDataKind.vo2Max]);
      final context = screenContext(tester);
      final run = askOpenHealthQuestions(context, c, skipDeferred: true);
      await tester.pumpAndSettle();
      expect(key('health_delete_dialog'), findsOneWidget);
      await askOpenHealthQuestions(context, c, skipDeferred: secondSkips);
      await tapKey(tester, 'health_delete_keep');
      await tester.pumpAndSettle();
      expect(
        key('health_delete_dialog'),
        asked ? findsOneWidget : findsNothing,
      );
      if (asked) {
        expect(c.questions, [HealthDataKind.vo2Max]);
        await tapKey(tester, 'health_delete_keep');
        await tester.pumpAndSettle();
        expect(key('health_delete_dialog'), findsNothing);
      } else {
        expect(c.questions, [HealthDataKind.vo2Max]);
      }
      await run;
      expect(c.asking, isFalse);
    });
  }

  testWidgets('Abbrechen in der Abfolge: Frage bleibt offen, Lauf endet', (
    tester,
  ) async {
    final (c, storage, _) = await _setup(
      tester,
      granted: HealthDataKind.values.toSet()..remove(HealthDataKind.sleep),
      consented: {HealthDataKind.sleep},
      stored: {HealthDataKind.sleep: 2},
    );
    expect(key('health_delete_dialog'), findsOneWidget);
    await tapKey(tester, 'health_delete_cancel');
    await tester.pumpAndSettle();
    // Im selben Lauf nicht noch einmal gefragt; die Abfolge ist zu Ende.
    expect(key('health_delete_dialog'), findsNothing);
    expect(c.asking, isFalse);
    expect(c.questions, [HealthDataKind.sleep]);
    expect(
      await c.consents.isDeleteQuestionOpen(
        healthSourceKey(HealthDataKind.sleep),
      ),
      isTrue,
    );
    expect(await storage.data.health.count(HealthDataKind.sleep), 2);
  });

  // Die Frage zu Schlaf ist offen, die Abfolge hält ihre Sperre und liest gerade, ob sie offen ist.
  Future<(HealthConnectController, FakeStorage, _HeldConsentStore)>
  holdSleepCheck(WidgetTester tester, {required bool closedInStore}) async {
    final storage = FakeStorage();
    final consents = _HeldConsentStore(storage.data);
    final (c, _, _) = await _setup(
      tester,
      storage: storage,
      consentStore: consents,
      consented: {HealthDataKind.sleep, HealthDataKind.vo2Max},
      stored: {HealthDataKind.sleep: 2, HealthDataKind.vo2Max: 1},
    );
    final sleepKey = healthSourceKey(HealthDataKind.sleep);
    await c.consents.openDeleteQuestion(sleepKey);
    await c.load();
    expect(c.questions, [HealthDataKind.sleep]);
    // Randfall: Gespeichert ist die Frage schon geschlossen, die Liste kennt sie noch.
    if (closedInStore) await c.consents.closeDeleteQuestion(sleepKey);
    consents.hold = Completer<void>();
    unawaited(askOpenHealthQuestions(screenContext(tester), c));
    await tester.pumpAndSettle();
    expect(consents.held, 1);
    expect(key('health_delete_dialog'), findsNothing);
    // Der Nutzer schaltet Schlaf aus, solange die Abfolge prüft.
    await tapKey(tester, 'health_switch_sleep');
    expect(key('health_delete_dialog'), findsNothing);
    consents.hold!.complete();
    consents.hold = null;
    await tester.pumpAndSettle();
    return (c, storage, consents);
  }

  for (final (answer, deleted, onAgain) in [
    ('health_delete_cancel', false, true),
    ('health_delete_keep', false, false),
    ('health_delete_confirm', true, false),
  ]) {
    testWidgets('Ausschalten während die Abfolge prüft: Dialog des Schalters '
        '($answer)', (tester) async {
      final (c, storage, _) = await holdSleepCheck(
        tester,
        closedInStore: false,
      );
      expect(key('health_delete_dialog'), findsOneWidget);
      await tapKey(tester, answer);
      await tester.pumpAndSettle();
      expect(key('health_delete_dialog'), findsNothing);
      expect(c.asking, isFalse);
      final sleepKey = healthSourceKey(HealthDataKind.sleep);
      expect(await c.consents.isGranted(sleepKey), onAgain);
      expect(c.enabled.contains(HealthDataKind.sleep), onAgain);
      expect(
        tester.widget<SwitchListTile>(key('health_switch_sleep')).value,
        onAgain,
      );
      expect(await c.consents.isDeleteQuestionOpen(sleepKey), isFalse);
      expect(c.questions, isEmpty);
      expect(
        await storage.data.health.count(HealthDataKind.sleep),
        deleted ? 0 : 2,
      );
      expect(await storage.data.health.count(HealthDataKind.vo2Max), 1);
      expect(c.enabled.contains(HealthDataKind.vo2Max), isTrue);
    });
  }

  testWidgets('Ausschalten während die Abfolge prüft: nicht offen, '
      'dann fragt der Schalter selbst', (tester) async {
    final (c, storage, _) = await holdSleepCheck(tester, closedInStore: true);
    // Die Abfolge zeigt keinen Dialog; der Schalter fragt danach genau einmal.
    expect(key('health_delete_dialog'), findsOneWidget);
    await tapKey(tester, 'health_delete_cancel');
    await tester.pumpAndSettle();
    expect(key('health_delete_dialog'), findsNothing);
    expect(c.enabled.contains(HealthDataKind.sleep), isTrue);
    expect(await storage.data.health.count(HealthDataKind.sleep), 2);
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

  testWidgets('Installieren: öffnet den Play Store, nur bei fehlender App', (
    tester,
  ) async {
    final (_, _, port) = await _setup(
      tester,
      status: HealthSdkStatus.updateRequired,
    );
    await tapKey(tester, 'health_install');
    expect(port.installOpened, 1);
    expect(find.byType(SnackBar), findsNothing);
    port.installResult = false;
    await tapKey(tester, 'health_install');
    expect(port.installOpened, 2);
    expect(find.byType(SnackBar), findsOneWidget); // Fallback ohne Absturz
    expect(tester.takeException(), isNull);
  });

  testWidgets('Nicht unterstützt: kein Installieren-Knopf', (tester) async {
    await _setup(tester, status: HealthSdkStatus.unavailable);
    expect(key('health_install'), findsNothing);
  });

  testWidgets('Jetzt abrufen zeigt den Zeitpunkt', (tester) async {
    final (c, _, _) = await _setup(tester, consented: {HealthDataKind.sleep});
    expect(find.text('Noch nie'), findsOneWidget);
    await tapKey(tester, 'health_fetch');
    expect(find.text('Noch nie'), findsNothing);
    expect(c.lastImport, isNotNull);
  });
}
