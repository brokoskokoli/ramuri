import 'dart:io';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:adapters/adapters.dart';

import 'app_harness.dart';

Future<void> openPermissions(WidgetTester tester) async {
  await openOverview(tester);
  await tester.tap(find.byKey(const Key('overview_permissions')));
  await tester.pumpAndSettle();
}

String _stateOf(WidgetTester tester, AppPermission p) {
  final tile = tester.widget<ListTile>(find.byKey(Key('permission_${p.name}')));
  return (tile.trailing! as Text).data!;
}

void main() {
  testWidgets('Stand je Berechtigung aus dem Port, deutsch', (tester) async {
    final d = Device();
    d.permissions.states = {
      AppPermission.location: PermissionState.granted,
      AppPermission.bluetooth: PermissionState.denied,
      AppPermission.activityRecognition: PermissionState.unknown,
    };
    await d.start(tester, const Locale('de'));
    await d.skipSetup(tester);
    await openPermissions(tester);
    expect(_stateOf(tester, AppPermission.location), 'Erteilt');
    expect(_stateOf(tester, AppPermission.bluetooth), 'Nicht erteilt');
    expect(_stateOf(tester, AppPermission.activityRecognition), 'Unbekannt');
    expect(find.text('Schritterkennung'), findsOneWidget);
    await d.stop(tester);
  });

  testWidgets('englisch, Knopf öffnet die Systemeinstellungen', (tester) async {
    final d = Device();
    await d.start(tester, const Locale('en'));
    await d.skipSetup(tester);
    await openPermissions(tester);
    expect(_stateOf(tester, AppPermission.location), 'Not granted');
    expect(d.permissions.openSettingsCount, 0);
    await tester.tap(find.byKey(const Key('permissions_open_settings')));
    await tester.pump();
    expect(d.permissions.openSettingsCount, 1);
    await d.stop(tester);
  });

  testWidgets('Rückkehr aus dem System liest den Stand neu', (tester) async {
    final d = Device();
    await d.start(tester, const Locale('en'));
    await d.skipSetup(tester);
    await openPermissions(tester);
    expect(_stateOf(tester, AppPermission.bluetooth), 'Not granted');
    d.permissions.states[AppPermission.bluetooth] = PermissionState.granted;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(_stateOf(tester, AppPermission.bluetooth), 'Granted');
    await d.stop(tester);
  });

  testWidgets('Lesefehler zeigt Unbekannt statt zu scheitern', (tester) async {
    final d = Device();
    d.permissions.failStatus = true;
    await d.start(tester, const Locale('en'));
    await d.skipSetup(tester);
    await openPermissions(tester);
    expect(_stateOf(tester, AppPermission.location), 'Unknown');
    await d.stop(tester);
  });

  testWidgets('zeigt nur im Manifest angeforderte Berechtigungen', (
    tester,
  ) async {
    final d = Device();
    d.permissions.requestedSet = {AppPermission.location};
    await d.start(tester, const Locale('de'));
    await d.skipSetup(tester);
    await openPermissions(tester);
    expect(find.byKey(const Key('permission_location')), findsOneWidget);
    expect(find.byKey(const Key('permission_bluetooth')), findsNothing);
    expect(
      find.byKey(const Key('permission_activityRecognition')),
      findsNothing,
    );
    expect(find.byKey(const Key('permissions_none')), findsNothing);
    await d.stop(tester);
  });

  testWidgets('ohne angeforderte Berechtigung: Hinweis statt Liste', (
    tester,
  ) async {
    final d = Device();
    d.permissions.requestedSet = {};
    await d.start(tester, const Locale('de'));
    await d.skipSetup(tester);
    await openPermissions(tester);
    expect(find.byKey(const Key('permissions_none')), findsOneWidget);
    expect(
      find.text('Die App fordert noch keine Berechtigungen an.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('permission_location')), findsNothing);
    expect(find.byKey(const Key('permissions_open_settings')), findsOneWidget);
    await d.stop(tester);
  });

  testWidgets('Manifest nicht lesbar: alle zeigen, nie eine leere Seite', (
    tester,
  ) async {
    final d = Device();
    d.permissions.requestedSet = {};
    d.permissions.failRequested = true;
    await d.start(tester, const Locale('en'));
    await d.skipSetup(tester);
    await openPermissions(tester);
    expect(find.byKey(const Key('permissions_none')), findsNothing);
    expect(find.byKey(const Key('permission_bluetooth')), findsOneWidget);
    await d.stop(tester);
  });

  test('Kanalname und requestedKeys-Schlüssel stehen gleich in Dart und MainActivity.kt', () {
    final kt = File(
      'android/app/src/main/kotlin/io/github/brokoskokoli/ramuri/MainActivity.kt',
    ).readAsStringSync();
    expect(permissionChannel.name, permissionChannelName);
    expect(
      kt,
      contains(
        'MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "$permissionChannelName")',
      ),
    );

    // requestedKeys() liefert die Schlüssel der Berechtigungsseite; ein Tippfehler blendet den Eintrag still aus.
    final fn = kt.substring(kt.indexOf('fun requestedKeys'));
    final added = RegExp(r'keys\.add\("([^"]+)"\)')
        .allMatches(fn)
        .map((m) => m.group(1))
        .toList();
    expect(added, unorderedEquals(MethodChannelPermissionStatus.keys.values));
  });

  group('MethodChannelPermissionStatus', () {
    const channel = permissionChannel; // echter Kanalname
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    test(
      'übersetzt Stand, fehlende und fremde Werte werden unbekannt',
      () async {
        messenger.setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'status');
          return {
            'location': 'granted',
            'bluetooth': 'denied',
            'activity_recognition': 'weird',
          };
        });
        final s = await MethodChannelPermissionStatus().status();
        expect(s[AppPermission.location], PermissionState.granted);
        expect(s[AppPermission.bluetooth], PermissionState.denied);
        expect(s[AppPermission.activityRecognition], PermissionState.unknown);
      },
    );

    test(
      'requested: bekannte Schlüssel, fremde und fehlende entfallen',
      () async {
        messenger.setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'requested');
          return ['bluetooth', 'weird'];
        });
        expect(await MethodChannelPermissionStatus().requested(), {
          AppPermission.bluetooth,
        });
        messenger.setMockMethodCallHandler(channel, (call) async => null);
        expect(await MethodChannelPermissionStatus().requested(), isEmpty);
      },
    );

    test('Knopf ruft openAppSettings', () async {
      String? method;
      messenger.setMockMethodCallHandler(channel, (call) async {
        method = call.method;
        return null;
      });
      await MethodChannelPermissionStatus().openSystemSettings();
      expect(method, 'openAppSettings');
    });
  });
}
