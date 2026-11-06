import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/app.dart';
import 'package:running_app/app_dependencies.dart';
import 'package:running_app/features/storage/storage_start.dart';

Future<void> _pump(WidgetTester tester, Locale locale) async {
  tester.platformDispatcher.localesTestValue = [locale];
  addTearDown(tester.platformDispatcher.clearLocalesTestValue);
  final controller = StorageStartController(
    keyStore: FakeKeyStore(),
    generateKey: () => Uint8List.fromList(List.filled(32, 7)),
    wire: () async =>
        StorageWiring(storage: FakeStorage(), files: FakeDatabaseFiles()),
  );
  await tester.pumpWidget(
    RunningApp(dependencies: AppDependencies(storageStart: controller)),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Startbildschirm auf Deutsch', (tester) async {
    await _pump(tester, const Locale('de'));
    expect(find.text('Willkommen bei der Lauf-App'), findsOneWidget);
  });

  testWidgets('Startbildschirm auf Englisch', (tester) async {
    await _pump(tester, const Locale('en'));
    expect(find.text('Welcome to the running app'), findsOneWidget);
    expect(find.text('Willkommen bei der Lauf-App'), findsNothing);
  });
}
