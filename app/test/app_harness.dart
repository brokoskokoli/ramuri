import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/app.dart';
import 'package:running_app/app_dependencies.dart';
import 'package:running_app/features/storage/storage_start.dart';

/// "Gerät" für App-Tests: Speicher und Schlüsselablage bleiben über mehrere
/// App-Starts erhalten, wie auf dem Telefon.
class Device {
  final FakeStorage storage = FakeStorage();
  final FakeKeyStore keyStore = FakeKeyStore();
  final FakeClock clock = FakeClock(DateTime.utc(2026, 6, 1));
  final FakePermissionStatus permissions = FakePermissionStatus();
  late StorageStartController controller;

  StorageSession get session => (controller.state as StorageReady).session;

  /// Startet die App mit der Gerätesprache [locale] (neuer Prozess auf
  /// demselben Speicher).
  Future<void> start(WidgetTester tester, Locale locale) async {
    // Hoher Bildschirm, damit das ganze Formular ohne Scrollen sichtbar ist.
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.localesTestValue = [locale];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    controller = StorageStartController(
      keyStore: keyStore,
      generateKey: () => Uint8List.fromList(List.filled(32, 7)),
      wire: () async =>
          StorageWiring(storage: storage, files: FakeDatabaseFiles()),
    );
    await tester.pumpWidget(
      RunningApp(
        dependencies: AppDependencies(
          storageStart: controller,
          clock: clock,
          permissions: permissions,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Beendet die App (Sitzung zu), damit ein zweiter Start möglich ist.
  Future<void> stop(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await session.close();
  }

  /// Überspringt die Ersteinrichtung.
  Future<void> skipSetup(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('setup_skip')));
    await tester.pumpAndSettle();
  }
}
