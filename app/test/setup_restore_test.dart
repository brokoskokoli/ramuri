import 'dart:async';
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

/// Sitzung, die alles an [inner] weitergibt; nur das Schreiben von
/// `setup.done` ist abfangbar ([failSetupDone], [onSetupDone]) und das Lesen der
/// Merker der Neuberechnung anhaltbar ([holdPendingRead]).
class _WrapSession implements StorageSession {
  _WrapSession(this.inner);
  final StorageSession inner;
  bool failSetupDone = false;
  void Function()? onSetupDone;
  Future<void>? holdPendingRead;

  @override
  SettingsStore get settings => _WrapSettings(inner.settings, this);
  @override
  RunStore get runs => inner.runs;
  @override
  RunMarkerStore get markers => inner.markers;
  @override
  RawDataStore get rawData => inner.rawData;
  @override
  PreprocessingStore get preprocessing => inner.preprocessing;
  @override
  RatedSectionStore get sections => inner.sections;
  @override
  ComputedValueStore get values => inner.values;
  @override
  ProfileStore get profile => inner.profile;
  @override
  KnownDeviceStore get devices => inner.devices;
  @override
  ConsentStore get consents => inner.consents;
  @override
  Future<void> deleteRun(int runId) => inner.deleteRun(runId);
  @override
  Future<void> deleteAll() => inner.deleteAll();
  @override
  Future<void> close() => inner.close();
}

class _WrapSettings implements SettingsStore {
  _WrapSettings(this.inner, this.owner);
  final SettingsStore inner;
  final _WrapSession owner;

  @override
  Future<String?> get(String key) async {
    if (key == ValueCalculationService.refreshPendingKey) {
      await owner.holdPendingRead;
    }
    return inner.get(key);
  }

  @override
  Future<Map<String, String>> all() => inner.all();

  @override
  Future<void> set(String key, String value, {required DateTime at}) async {
    if (key == SettingKeys.setupDone) {
      owner.onSetupDone?.call();
      if (owner.failSetupDone) {
        throw const StorageException(StorageFailure.unreadable);
      }
    }
    await inner.set(key, value, at: at);
  }
}

class _WrapStorage implements Storage {
  _WrapStorage(this.inner, {this.hold});
  final Storage inner;
  final Future<void>? hold;
  @override
  Future<StorageSession> open(Uint8List key) async =>
      _WrapSession(await inner.open(key))..holdPendingRead = hold;
}

Future<(Device, _Restore)> _setup(
  WidgetTester tester, {
  Storage Function(Storage)? wrap,
}) async {
  final restore = _Restore();
  final d = Device()..archiveRestore = restore.factory;
  if (wrap != null) d.storageOverride = wrap(d.storage);
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
    await openOverview(tester);
    await tester.tap(find.byKey(const Key('home_settings')));
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

  testWidgets('setup.done lässt sich auf der neuen Sitzung nicht schreiben: '
      'sie wird trotzdem übernommen (alte ist geschlossen), Einrichtung '
      'erscheint erneut', (tester) async {
    final (d, restore) = await _setup(tester);
    final fresh = _WrapSession(await _archived(setupDone: false))
      ..failSetupDone = true;
    restore.result = fresh;
    d.fileHandoff.nextPick = const FilePickResult.completed(_path);
    await _tap(tester, 'setup_restore');
    await _tap(tester, 'archive_import_confirm');
    await _enterPassword(tester, _pw);
    expect(d.session, same(fresh));
    expect(d.fileHandoff.discardCount, 1);
    expect(find.byKey(const Key('archive_import_error')), findsNothing);
    // Reimport aus der Ersteinrichtung: kein zweites Willkommen (FR-0207),
    // obwohl die neue Sitzung noch ohne Merker ist.
    expect(find.byKey(const Key('welcome_screen')), findsNothing);
    expect(find.byKey(const Key('setup_skip')), findsOneWidget);
    // Die eingespielten Daten sind da.
    expect(
      await fresh.settings.get(SettingKeys.distanceUnit),
      DistanceUnit.miles.storageValue,
    );
    await d.stop(tester);
  });

  testWidgets('setup.done wird geschrieben, bevor die neue Sitzung übernommen '
      'wird', (tester) async {
    final (d, restore) = await _setup(tester);
    final fresh = _WrapSession(await _archived(setupDone: false));
    var adoptedAtWrite = true;
    var writes = 0;
    fresh.onSetupDone = () {
      writes++;
      adoptedAtWrite = identical(d.session, fresh);
    };
    restore.result = fresh;
    d.fileHandoff.nextPick = const FilePickResult.completed(_path);
    await _tap(tester, 'setup_restore');
    await _tap(tester, 'archive_import_confirm');
    await _enterPassword(tester, _pw);
    expect(writes, 1);
    expect(adoptedAtWrite, isFalse);
    expect(d.session, same(fresh));
    await d.stop(tester);
  });

  testWidgets('Wiederherstellen läuft über serialize: hinter dem Nachholen '
      'der Neuberechnung beim Start', (tester) async {
    final hold = Completer<void>();
    final (d, restore) = await _setup(
      tester,
      // Der Start der Neuberechnung (ReadyRoot) liest den Merker und bleibt
      // hängen, bis [hold] frei ist.
      wrap: (inner) => _WrapStorage(inner, hold: hold.future),
    );
    restore.result = await _archived(setupDone: true);
    d.fileHandoff.nextPick = const FilePickResult.completed(_path);
    await _tap(tester, 'setup_restore');
    await _tap(tester, 'archive_import_confirm');
    await tester.enterText(
      find.byKey(const Key('archive_import_password')),
      _pw,
    );
    await tester.tap(find.byKey(const Key('archive_import_password_ok')));
    await tester.pump();
    await tester.pump();
    expect(restore.calls, isEmpty);
    hold.complete();
    await tester.pumpAndSettle();
    expect(restore.calls, hasLength(1));
    expect(find.byKey(const Key('home_start_run')), findsOneWidget);
    await d.stop(tester);
  });
}
