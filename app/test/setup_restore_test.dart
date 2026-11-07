import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/archive/archive_wiring.dart';

import 'app_harness.dart';

// Aus dem Archiv wiederherstellen in der Ersteinrichtung (WP12 D3, FR-0198,
// Vertrag 4.6). Der Wiederherstellungsdienst ist ein Fake; die Leer-Prüfung
// ist die echte (`ArchiveRestoreService.isEmpty` über dem Fake-Speicher).

const String _pw = 'synthetisches Testpasswort';
const String _path = '/cache/imports/archive.bin';

class _Restore {
  final List<({String password, bool reset})> calls = [];
  final List<Object> errors = [];
  StorageSession? result;

  Future<ArchiveRestoreRunner> factory(
    StorageSession session,
    SerializeAction serialize,
  ) async =>
      ({
        required path,
        required password,
        bool resetConfirmed = false,
        ArchiveCancel? cancel,
      }) => serialize(() async {
        calls.add((password: password, reset: resetConfirmed));
        if (errors.isNotEmpty) throw errors.removeAt(0);
        return result!;
      });
}

/// Sitzung, die der Fake nach dem "Tausch" liefert (Meilen); [setupDone]
/// steuert, ob das Archiv die Einrichtung als erledigt trägt.
Future<StorageSession> _archived({required bool setupDone}) async {
  final s = await FakeStorage().open(Uint8List(32)..fillRange(0, 32, 9));
  await s.settings.set(
    SettingKeys.distanceUnit,
    DistanceUnit.miles.storageValue,
    at: DateTime.utc(2030),
  );
  if (setupDone) {
    await s.settings.set(SettingKeys.setupDone, '1', at: DateTime.utc(2030));
  }
  return s;
}

Future<(Device, _Restore)> _setup(WidgetTester tester) async {
  final restore = _Restore();
  final d = Device()..archiveRestore = restore.factory;
  await d.start(tester, const Locale('de'));
  expect(find.byKey(const Key('setup_skip')), findsOneWidget);
  return (d, restore);
}

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

Future<void> _enterPassword(WidgetTester tester, String pw) async {
  await tester.enterText(find.byKey(const Key('archive_import_password')), pw);
  await _tap(tester, 'archive_import_password_ok');
}

/// Nichts geschrieben, Einrichtung weiter offen.
Future<void> _expectUntouched(WidgetTester tester, Device d) async {
  expect(find.byKey(const Key('setup_skip')), findsOneWidget);
  expect(find.byKey(const Key('home_start_run')), findsNothing);
  expect(await d.session.settings.all(), isEmpty);
  expect(await ArchiveRestoreService.isEmpty(d.session), isTrue);
}

void main() {
  testWidgets('Hinweis sichtbar, App wirklich leer: keine Ersetzen-Warnung, '
      'Erfolg übernimmt Einstellungen und überspringt die Einrichtung', (
    tester,
  ) async {
    final (d, restore) = await _setup(tester);
    restore.result = await _archived(setupDone: true);
    expect(
      await ArchiveRestoreService.isEmpty(d.session),
      isTrue,
      reason: 'beim ersten Bildschirm gilt die App als leer (4.6)',
    );
    expect(find.text('Aus Archiv wiederherstellen'), findsOneWidget);
    d.fileHandoff.nextPick = const FilePickResult.completed(_path);
    await _tap(tester, 'setup_restore');
    expect(
      find.textContaining('Ein älteres Archiv kann Daten'),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('archive_import_replace_warning')),
      findsNothing,
    );
    await _tap(tester, 'archive_import_confirm');
    await _enterPassword(tester, _pw);
    expect(restore.calls.single.password, _pw);
    expect(restore.calls.single.reset, isFalse);
    expect(d.session, same(restore.result));
    expect(d.fileHandoff.discardCount, 1);
    expect(find.byKey(const Key('setup_skip')), findsNothing);
    expect(find.byKey(const Key('home_start_run')), findsOneWidget);
    await tester.tap(find.text('Einstellungen'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<SegmentedButton<DistanceUnit>>(
            find.byKey(const Key('settings_unit')),
          )
          .selected,
      {DistanceUnit.miles},
    );
    await d.stop(tester);
  });

  testWidgets('Archiv ohne Merker setup.done: wird gesetzt, Einrichtung '
      'erscheint nicht erneut', (tester) async {
    final (d, restore) = await _setup(tester);
    restore.result = await _archived(setupDone: false);
    d.fileHandoff.nextPick = const FilePickResult.completed(_path);
    await _tap(tester, 'setup_restore');
    await _tap(tester, 'archive_import_confirm');
    await _enterPassword(tester, _pw);
    expect(await restore.result!.settings.get(SettingKeys.setupDone), '1');
    expect(find.byKey(const Key('setup_skip')), findsNothing);
    expect(find.byKey(const Key('home_start_run')), findsOneWidget);
    await d.stop(tester);
  });

  testWidgets('falsches Passwort: Fehler im Dialog, zweiter Versuch gelingt', (
    tester,
  ) async {
    final (d, restore) = await _setup(tester);
    restore.result = await _archived(setupDone: true);
    restore.errors.add(
      const ArchiveImportException(ArchiveImportFailure.wrongPasswordOrDamaged),
    );
    d.fileHandoff.nextPick = const FilePickResult.completed(_path);
    await _tap(tester, 'setup_restore');
    await _tap(tester, 'archive_import_confirm');
    await _enterPassword(tester, 'falsch');
    expect(
      find.textContaining('Falsches Passwort oder beschädigter Anfang'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('home_start_run')), findsNothing);
    await _enterPassword(tester, _pw);
    expect(restore.calls.map((c) => c.password), ['falsch', _pw]);
    expect(find.byKey(const Key('home_start_run')), findsOneWidget);
    await d.stop(tester);
  });

  testWidgets('falsches Passwort, dann Abbruch: zurück in der Einrichtung, '
      'nichts geschrieben', (tester) async {
    final (d, restore) = await _setup(tester);
    restore.errors.add(
      const ArchiveImportException(ArchiveImportFailure.wrongPasswordOrDamaged),
    );
    d.fileHandoff.nextPick = const FilePickResult.completed(_path);
    await _tap(tester, 'setup_restore');
    await _tap(tester, 'archive_import_confirm');
    await _enterPassword(tester, 'falsch');
    await _tap(tester, 'archive_import_password_cancel');
    await _expectUntouched(tester, d);
    expect(d.fileHandoff.discardCount, 1);
    await d.stop(tester);
  });

  testWidgets('Fehler beim Einlesen: Meldung, zurück in der Einrichtung, '
      'nichts geschrieben', (tester) async {
    final (d, restore) = await _setup(tester);
    restore.errors.add(
      const ArchiveImportException(ArchiveImportFailure.damaged),
    );
    d.fileHandoff.nextPick = const FilePickResult.completed(_path);
    await _tap(tester, 'setup_restore');
    await _tap(tester, 'archive_import_confirm');
    await _enterPassword(tester, _pw);
    expect(find.byKey(const Key('archive_import_error')), findsOneWidget);
    await _tap(tester, 'archive_import_error_close');
    await _expectUntouched(tester, d);
    expect(d.fileHandoff.discardCount, 1);
    await d.stop(tester);
  });

  testWidgets('Abbruch am Hinweis: nichts gewählt, nichts geschrieben', (
    tester,
  ) async {
    final (d, restore) = await _setup(tester);
    await _tap(tester, 'setup_restore');
    await _tap(tester, 'archive_import_cancel');
    await _expectUntouched(tester, d);
    expect(d.fileHandoff.pickCount, 0);
    expect(restore.calls, isEmpty);
    await d.stop(tester);
  });

  testWidgets('Dateiwahl abgebrochen: zurück in der Einrichtung, Kopie '
      'entsorgt', (tester) async {
    final (d, restore) = await _setup(tester);
    await _tap(tester, 'setup_restore');
    await _tap(tester, 'archive_import_confirm');
    await _expectUntouched(tester, d);
    expect(restore.calls, isEmpty);
    expect(d.fileHandoff.discardCount, 1);
    await d.stop(tester);
  });

  testWidgets('Abbruch am Passwortdialog: zurück in der Einrichtung, '
      'nichts geschrieben', (tester) async {
    final (d, restore) = await _setup(tester);
    d.fileHandoff.nextPick = const FilePickResult.completed(_path);
    await _tap(tester, 'setup_restore');
    await _tap(tester, 'archive_import_confirm');
    await _tap(tester, 'archive_import_password_cancel');
    await _expectUntouched(tester, d);
    expect(restore.calls, isEmpty);
    expect(d.fileHandoff.discardCount, 1);
    await d.stop(tester);
  });
}
