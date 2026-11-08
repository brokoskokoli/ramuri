import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/app.dart';
import 'package:running_app/app_dependencies.dart';

import 'storage_world.dart';

/// Verdrahtung des Erscheinungsbilds (WP14): Dinge, die ein Test der Bausteine allein nicht sieht,
/// weil er sie selbst aufbaut (Lizenzen, Benachrichtigungssymbol, Themenwahl).
void main() {
  /// Quelltext ohne Zeilenkommentare.
  String code(String path) =>
      File(path)
          .readAsStringSync()
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');

  for (final entry in ['lib/main.dart', 'lib/main_debug.dart']) {
    test('$entry registriert die Schriftlizenzen vor dem Start', () {
      final source = code(entry);
      expect(source, contains('registerFontLicenses();'));
      expect(
        source.indexOf('registerFontLicenses();'),
        lessThan(source.indexOf('runApp(')),
        reason: 'Lizenzen vor runApp',
      );
    });
  }

  test('Benachrichtigung des Aufnahmedienstes nutzt ic_stat_ramuri', () {
    const dir = 'android/app/src/main/kotlin/io/github/brokoskokoli/ramuri';
    final service = code('$dir/RecordingService.kt');
    expect(service, contains('.setSmallIcon(R.drawable.ic_stat_ramuri)'));
    expect(service, isNot(contains('ic_launcher')));
    // Das Symbol existiert als Ressource (nicht nur als Name).
    final icons = Directory('android/app/src/main/res')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.uri.pathSegments.last.startsWith('ic_stat_ramuri.'));
    expect(icons, isNotEmpty);
  });

  test(
    'pubspec bündelt Assets einzeln, keine Ordner (keine README im APK)',
    () {
      final entries = RegExp(
        r'^\s+- (assets/\S+)$',
        multiLine: true,
      ).allMatches(code('pubspec.yaml')).map((m) => m.group(1)!).toList();
      expect(entries, contains('assets/brand/ramuri-logo-stacked-on-dark.png'));
      for (final e in entries) {
        expect(e.endsWith('/'), isFalse, reason: '$e ist ein Ordner');
        expect(File(e).existsSync(), isTrue, reason: '$e fehlt');
      }
    },
  );

  for (final (brightness, expected) in [
    (Brightness.dark, Brightness.dark),
    (Brightness.light, Brightness.light),
  ]) {
    testWidgets('RunningApp folgt dem System: $brightness', (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = brightness;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      final w = World();
      await w.seed(fileKey: keyOf(1), storedKey: keyOf(1));
      await tester.pumpWidget(
        RunningApp(dependencies: AppDependencies(storageStart: w.controller())),
      );
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(Navigator).first);
      expect(Theme.of(context).brightness, expected);
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.system,
      );
    });
  }
}
