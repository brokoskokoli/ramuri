import 'dart:async';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/archive/archive_import_action.dart';
import 'package:running_app/features/archive/archive_import_flow.dart';
import 'package:running_app/features/archive/archive_scope.dart';
import 'package:running_app/features/archive/archive_wiring.dart';
import 'package:running_app/features/export/file_handoff_scope.dart';
import 'package:running_app/features/storage/storage_start.dart';
import 'package:running_app/l10n/app_localizations.dart';

import 'app_harness.dart';

const String _pw = 'synthetisches Testpasswort';
const String _path = '/cache/imports/archive.bin';

/// Ersatz für den Wiederherstellungsdienst: merkt Aufrufe, wartet auf [gate]
/// und liefert [result] oder wirft [error]. Ruft wie der echte Dienst
/// `serialize` und achtet auf die Abbruchmarke.
class _FakeRestore {
  final List<({String path, String password, bool reset})> calls = [];
  final List<String> events = [];
  Completer<void>? gate;

  /// Fehler je Aufruf (nach der Reihenfolge); danach Erfolg.
  final List<Object> errors = [];
  StorageSession? result;
  Object? factoryError;
  Future<void> Function()? beforeFactory;
  SerializeAction? serialize;

  Future<ArchiveRestoreRunner> factory(
    StorageSession session,
    SerializeAction serialize,
  ) async {
    events.add('factory');
    this.serialize = serialize;
    await beforeFactory?.call();
    if (factoryError != null) throw factoryError!;
    return ({
      required path,
      required password,
      bool resetConfirmed = false,
      ArchiveCancel? cancel,
    }) => serialize(() async {
      events.add('restore');
      calls.add((path: path, password: password, reset: resetConfirmed));
      await gate?.future;
      if (cancel?.isCancelled ?? false) {
        throw const ArchiveImportException(ArchiveImportFailure.cancelled);
      }
      if (errors.isNotEmpty) throw errors.removeAt(0);
      return result!;
    });
  }
}

Future<Device> _open(
  WidgetTester tester,
  _FakeRestore restore, {
  bool wired = true,
  bool finishedRun = false,
}) async {
  final d = Device();
  if (wired) d.archiveRestore = restore.factory;
  await d.start(tester, const Locale('de'));
  await d.skipSetup(tester);
  // Neue Sitzung, die der Fake nach dem "Tausch" liefert: eigener Speicher mit
  // einer Einstellung (Meilen), an der sich das Neuladen zeigt.
  final other = await FakeStorage().open(List.filled(32, 9).toUint8());
  await other.settings.set(
    SettingKeys.distanceUnit,
    DistanceUnit.miles.storageValue,
    at: DateTime.utc(2030),
  );
  await other.settings.set(SettingKeys.setupDone, '1', at: DateTime.utc(2030));
  restore.result = other;
  if (finishedRun) {
    final run = await d.session.runs.create(startedAt: DateTime.utc(2030));
    await d.session.runs.setState(
      run.id,
      RunState.finished,
      endedAt: DateTime.utc(2030, 1, 1, 1),
    );
  }
  await openOverview(tester);
  await tester.tap(find.byKey(const Key('overview_data')));
  await tester.pumpAndSettle();
  return d;
}

extension on List<int> {
  Uint8List toUint8() => Uint8List.fromList(this);
}

Future<void> _tapKey(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

/// Hinweis bestätigen, Datei wählen, Passwort eingeben.
Future<void> _walk(
  WidgetTester tester,
  Device d, {
  String password = _pw,
  bool enterPassword = true,
  bool settle = true,
}) async {
  d.fileHandoff.nextPick = const FilePickResult.completed(_path);
  await _tapKey(tester, 'archive_import');
  await _tapKey(tester, 'archive_import_confirm');
  if (!enterPassword) return;
  await tester.enterText(
    find.byKey(const Key('archive_import_password')),
    password,
  );
  if (settle) {
    await _tapKey(tester, 'archive_import_password_ok');
  } else {
    // Der Fortschrittsbalken animiert ohne Ende: nur ein paar Bilder.
    await tester.tap(find.byKey(const Key('archive_import_password_ok')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }
}

const String _noticeStart = 'Ein älteres Archiv kann Daten zurückbringen';

void main() {
  testWidgets('ohne Verdrahtung kein Eintrag im Daten-Bildschirm', (
    tester,
  ) async {
    final d = await _open(tester, _FakeRestore(), wired: false);
    expect(find.byKey(const Key('archive_import')), findsNothing);
    await d.stop(tester);
  });

  testWidgets('leere App: Hinweis OQ-0050 ohne Ersetzen-Warnung, kein '
      'resetConfirmed, Passwortfeld verdeckt, neue Sitzung übernommen', (
    tester,
  ) async {
    final d = Device();
    await d.start(tester, const Locale('de'));
    final restore = _FakeRestore();
    // Eine leere Sitzung (die Ersteinrichtung schreibt schon Einstellungen).
    final empty = await FakeStorage().open(Uint8List(32));
    restore.result = d.session;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('de'),
        home: FileHandoffScope(
          handoff: d.fileHandoff,
          child: ArchiveScope(
            restore: restore.factory,
            start: d.controller,
            child: Scaffold(
              body: ArchiveImportAction(
                session: empty,
                serialize: <T>(a) => a(),
              ),
            ),
          ),
        ),
      ),
    );
    d.fileHandoff.nextPick = const FilePickResult.completed(_path);
    await _tapKey(tester, 'archive_import');
    expect(find.textContaining(_noticeStart), findsOneWidget);
    expect(
      find.byKey(const Key('archive_import_replace_warning')),
      findsNothing,
    );
    expect(find.text('Datei wählen'), findsOneWidget);
    expect(d.fileHandoff.pickCount, 0, reason: 'erst nach der Bestätigung');
    await _tapKey(tester, 'archive_import_confirm');
    expect(d.fileHandoff.pickCount, 1);
    final field = tester.widget<TextField>(
      find.byKey(const Key('archive_import_password')),
    );
    expect(field.obscureText, isTrue);
    expect(field.enableSuggestions, isFalse);
    expect(field.autocorrect, isFalse);
    expect(field.enableIMEPersonalizedLearning, isFalse);
    expect(field.autofillHints, anyOf(isNull, isEmpty));
    await tester.enterText(
      find.byKey(const Key('archive_import_password')),
      _pw,
    );
    await _tapKey(tester, 'archive_import_password_ok');
    expect(restore.calls.single.path, _path);
    expect(restore.calls.single.password, _pw);
    expect(restore.calls.single.reset, isFalse);
    expect(d.session, same(restore.result));
    expect(d.fileHandoff.discardCount, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('nicht leere App: Warnung plus Hinweis, ausdrückliche '
      'Bestätigung setzt resetConfirmed', (tester) async {
    final restore = _FakeRestore();
    final d = await _open(tester, restore, finishedRun: true);
    d.fileHandoff.nextPick = const FilePickResult.completed(_path);
    await _tapKey(tester, 'archive_import');
    expect(
      find.textContaining('Beim Import werden alle vorhandenen Daten'),
      findsOneWidget,
    );
    expect(find.textContaining(_noticeStart), findsOneWidget);
    expect(find.text('Alle Daten ersetzen'), findsOneWidget);
    await _tapKey(tester, 'archive_import_confirm');
    await tester.enterText(
      find.byKey(const Key('archive_import_password')),
      _pw,
    );
    await _tapKey(tester, 'archive_import_password_ok');
    expect(restore.calls.single.reset, isTrue);
    expect(d.session, same(restore.result), reason: 'neue Sitzung gilt');
    expect(d.fileHandoff.discardCount, 1);
    // Zurück auf der Startseite; Einstellungen kommen aus der neuen Sitzung.
    expect(find.byKey(const Key('archive_import')), findsNothing);
    expect(
      find.textContaining('Archiv importiert. Einwilligungen sind nicht'),
      findsOneWidget,
    );
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

  testWidgets('Abbruch am Hinweis: nichts gewählt, nichts importiert', (
    tester,
  ) async {
    final restore = _FakeRestore();
    final d = await _open(tester, restore, finishedRun: true);
    await _tapKey(tester, 'archive_import');
    await _tapKey(tester, 'archive_import_cancel');
    expect(d.fileHandoff.pickCount, 0);
    expect(restore.events, isEmpty);
    // Tippen daneben schließt ohne Antwort und importiert ebenfalls nichts.
    await _tapKey(tester, 'archive_import');
    await tester.tapAt(const Offset(2, 2));
    await tester.pumpAndSettle();
    expect(d.fileHandoff.pickCount, 0);
    expect(restore.events, isEmpty);
    await d.stop(tester);
  });

  testWidgets('Dateiwahl abgebrochen: kein Passwortdialog, Kopie entsorgt', (
    tester,
  ) async {
    final restore = _FakeRestore();
    final d = await _open(tester, restore);
    await _tapKey(tester, 'archive_import');
    await _tapKey(tester, 'archive_import_confirm');
    expect(find.byKey(const Key('archive_import_password')), findsNothing);
    expect(restore.events, isEmpty);
    expect(d.fileHandoff.discardCount, 1);
    await d.stop(tester);
  });

  testWidgets('Dateiwahl fehlgeschlagen: Meldung, nichts importiert', (
    tester,
  ) async {
    final restore = _FakeRestore();
    final d = await _open(tester, restore);
    d.fileHandoff.nextPick = const FilePickResult.failed();
    await _tapKey(tester, 'archive_import');
    await _tapKey(tester, 'archive_import_confirm');
    expect(
      find.text('Die Datei konnte nicht geöffnet werden.'),
      findsOneWidget,
    );
    expect(restore.events, isEmpty);
    expect(d.fileHandoff.discardCount, 1);
    await d.stop(tester);
  });

  testWidgets('Abbruch am Passwortdialog: nichts importiert, Kopie entsorgt', (
    tester,
  ) async {
    final restore = _FakeRestore();
    final d = await _open(tester, restore);
    final before = d.session;
    await _walk(tester, d, enterPassword: false);
    await _tapKey(tester, 'archive_import_password_cancel');
    expect(restore.events, isEmpty);
    expect(d.fileHandoff.discardCount, 1);
    expect(d.session, same(before));
    await d.stop(tester);
  });

  testWidgets('falsches Passwort: Fehler im Passwortdialog, zweiter Versuch '
      'gelingt, Datei bleibt bis dahin', (tester) async {
    final restore = _FakeRestore()
      ..errors.add(
        const ArchiveImportException(
          ArchiveImportFailure.wrongPasswordOrDamaged,
        ),
      );
    final d = await _open(tester, restore);
    await _walk(tester, d);
    expect(
      find.textContaining('Falsches Passwort oder beschädigter Anfang'),
      findsOneWidget,
    );
    expect(d.fileHandoff.discardCount, 0, reason: 'Datei wird noch gebraucht');
    await tester.enterText(
      find.byKey(const Key('archive_import_password')),
      'anderes Passwort',
    );
    await _tapKey(tester, 'archive_import_password_ok');
    expect(restore.calls.map((c) => c.password), [_pw, 'anderes Passwort']);
    expect(d.session, same(restore.result));
    expect(d.fileHandoff.discardCount, 1);
    await d.stop(tester);
  });

  for (final (name, error, text) in <(String, Object, String)>[
    (
      'beschädigt',
      const ArchiveImportException(ArchiveImportFailure.damaged),
      'Das Archiv ist beschädigt. Es wurde nichts geändert.',
    ),
    (
      'keine Archivdatei',
      const ArchiveImportException(ArchiveImportFailure.notAnArchive),
      'Das ist keine Archivdatei. Es wurde nichts geändert.',
    ),
    (
      'neuere Version',
      const ArchiveImportException(ArchiveImportFailure.newerSchema),
      'aktualisiere die App. Es wurde nichts geändert.',
    ),
    (
      'unbekannte Formatversion',
      const ArchiveImportException(ArchiveImportFailure.unsupportedVersion),
      'aktualisiere die App. Es wurde nichts geändert.',
    ),
    (
      'Lesen der Datei',
      const ArchiveImportException(ArchiveImportFailure.readFailed),
      'Die Datei konnte nicht gelesen werden.',
    ),
    (
      'Zwischendatenbank',
      const ArchiveImportException(ArchiveImportFailure.targetFailed),
      'zum Beispiel weil der Speicher voll ist',
    ),
    (
      'nicht leer',
      const ArchiveRestoreException(ArchiveRestoreFailure.notEmpty),
      'Der Import ist fehlgeschlagen. Es wurde nichts geändert.',
    ),
    (
      'Tausch fehlgeschlagen (Prüfung)',
      const ArchiveRestoreException(ArchiveRestoreFailure.swapFailed),
      'Die bisherigen Daten sind erhalten.',
    ),
    (
      'unbekannter Fehler',
      StateError('x'),
      'Der Import ist fehlgeschlagen. Es wurde nichts geändert.',
    ),
  ]) {
    testWidgets('Fehler $name: Meldung, Sitzung unverändert, Kopie entsorgt', (
      tester,
    ) async {
      final restore = _FakeRestore()..errors.add(error);
      final d = await _open(tester, restore);
      final before = d.session;
      await _walk(tester, d);
      expect(
        find.byKey(const Key('archive_import_error_dialog')),
        findsOneWidget,
      );
      expect(find.textContaining(text), findsOneWidget);
      expect(find.textContaining(_pw), findsNothing);
      expect(d.session, same(before));
      await _tapKey(tester, 'archive_import_error_close');
      expect(d.fileHandoff.discardCount, 1);
      expect(find.byKey(const Key('archive_import')), findsOneWidget);
      await d.stop(tester);
    });
  }

  testWidgets('Tausch gescheitert mit neu geöffneter Sitzung: sie gilt', (
    tester,
  ) async {
    final restore = _FakeRestore();
    final d = await _open(tester, restore);
    final reopened = restore.result!;
    restore.errors.add(
      ArchiveRestoreException(
        ArchiveRestoreFailure.swapFailed,
        session: reopened,
      ),
    );
    await _walk(tester, d);
    expect(
      find.textContaining('Die bisherigen Daten sind erhalten.'),
      findsOneWidget,
    );
    await _tapKey(tester, 'archive_import_error_close');
    // Die bisherige Sitzung ist geschlossen: die übergebene wird übernommen.
    expect(d.session, same(reopened));
    expect(find.byKey(const Key('home_screen')), findsOneWidget);
    expect(d.fileHandoff.discardCount, 1);
    await d.stop(tester);
  });

  testWidgets('Öffnen nach dem Tausch gescheitert: Start lädt neu', (
    tester,
  ) async {
    final restore = _FakeRestore()
      ..errors.add(
        const ArchiveRestoreException(ArchiveRestoreFailure.reopenFailed),
      );
    final d = await _open(tester, restore);
    final before = d.session;
    await _walk(tester, d);
    expect(find.textContaining('Die App lädt sie neu.'), findsOneWidget);
    await _tapKey(tester, 'archive_import_error_close');
    expect(d.controller.state, isA<StorageReady>());
    expect(d.session, isNot(same(before)), reason: 'neu geöffnet');
    expect(d.fileHandoff.discardCount, 1);
    await d.stop(tester);
  });

  testWidgets('Schlüssel nicht lesbar (Fabrik wirft): Meldung, nichts '
      'geändert', (tester) async {
    final restore = _FakeRestore()
      ..factoryError = const ArchiveRestoreException(
        ArchiveRestoreFailure.keyUnavailable,
      );
    final d = await _open(tester, restore);
    final before = d.session;
    await _walk(tester, d);
    expect(
      find.textContaining('Der Import ist fehlgeschlagen. Es wurde nichts'),
      findsOneWidget,
    );
    expect(d.session, same(before));
    await _tapKey(tester, 'archive_import_error_close');
    expect(d.fileHandoff.discardCount, 1);
    await d.stop(tester);
  });

  testWidgets('Abbruch während des Imports: Meldung, nichts geändert', (
    tester,
  ) async {
    final restore = _FakeRestore()..gate = Completer<void>();
    final d = await _open(tester, restore);
    final before = d.session;
    await _walk(tester, d, settle: false);
    expect(find.byKey(const Key('archive_import_working')), findsOneWidget);
    await tester.tap(find.byKey(const Key('archive_import_abort')));
    await tester.pump();
    restore.gate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Import abgebrochen.'), findsOneWidget);
    expect(find.byKey(const Key('archive_import_working')), findsNothing);
    expect(d.session, same(before));
    expect(d.fileHandoff.discardCount, 1);
    await d.stop(tester);
  });

  testWidgets('Während des Imports nicht schließbar (Zurück, daneben)', (
    tester,
  ) async {
    final restore = _FakeRestore()..gate = Completer<void>();
    final d = await _open(tester, restore);
    await _walk(tester, d, settle: false);
    await tester.tapAt(const Offset(2, 2));
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byKey(const Key('archive_import_working')), findsOneWidget);
    restore.gate!.complete();
    await tester.pumpAndSettle();
    await d.stop(tester);
  });

  testWidgets('Offener Lauf: Absage vor der Dateiwahl', (tester) async {
    final restore = _FakeRestore();
    final d = await _open(tester, restore);
    await d.session.runs.create(startedAt: DateTime.utc(2031));
    await _tapKey(tester, 'archive_import');
    expect(find.byKey(const Key('archive_import_notice_dialog')), findsNothing);
    expect(
      find.text(
        'Beende zuerst den laufenden Lauf, danach kannst du ein Archiv '
        'importieren.',
      ),
      findsOneWidget,
    );
    expect(d.fileHandoff.pickCount, 0);
    expect(restore.events, isEmpty);
    await d.stop(tester);
  });

  testWidgets('Lauf beginnt nach der Bestätigung: der Import ist über '
      'serialize ausgeschlossen', (tester) async {
    final restore = _FakeRestore();
    final d = await _open(tester, restore);
    restore.beforeFactory = () async {
      await d.session.runs.create(startedAt: DateTime.utc(2031));
    };
    final before = d.session;
    await _walk(tester, d);
    expect(restore.calls, isEmpty, reason: 'Dienst nicht aufgerufen');
    expect(
      find.textContaining('Beende zuerst den laufenden Lauf'),
      findsOneWidget,
    );
    expect(d.session, same(before));
    expect(d.fileHandoff.discardCount, 1);
    await d.stop(tester);
  });

  testWidgets('Import läuft nur über serialize (hinter Aufnahme und '
      'Neuberechnung)', (tester) async {
    final d = Device();
    await d.start(tester, const Locale('de'));
    final restore = _FakeRestore();
    final release = Completer<void>();
    var queue = release.future;
    final order = <String>[];
    Future<T> serialize<T>(Future<T> Function() action) {
      order.add('eingereiht');
      final r = queue.then((_) => action());
      queue = r.then((_) {}, onError: (Object _) {});
      return r;
    }

    restore.result = d.session;
    d.fileHandoff.nextPick = const FilePickResult.completed(_path);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('de'),
        home: FileHandoffScope(
          handoff: d.fileHandoff,
          child: ArchiveScope(
            restore: restore.factory,
            start: d.controller,
            child: Scaffold(
              body: ArchiveImportAction(
                session: d.session,
                serialize: serialize,
              ),
            ),
          ),
        ),
      ),
    );
    await _tapKey(tester, 'archive_import');
    await _tapKey(tester, 'archive_import_confirm');
    await tester.enterText(
      find.byKey(const Key('archive_import_password')),
      _pw,
    );
    await tester.tap(find.byKey(const Key('archive_import_password_ok')));
    await tester.pump();
    await tester.pump();
    expect(order, ['eingereiht']);
    expect(restore.calls, isEmpty);
    release.complete();
    await tester.pumpAndSettle();
    expect(restore.calls, hasLength(1));
    await d.stop(tester);
  });

  testWidgets('Meldungen: falsches Passwort und beschädigter Anfang in einer '
      'Meldung (ADR-0008 Punkt 5), ohne Passwort', (tester) async {
    final d = await _open(tester, _FakeRestore());
    final l10n = AppLocalizations.of(
      tester.element(find.byType(Scaffold).first),
    );
    final wrong = archiveImportMessage(
      l10n,
      const ArchiveImportException(ArchiveImportFailure.wrongPasswordOrDamaged),
    );
    expect(wrong, contains('Falsches Passwort oder beschädigter Anfang'));
    expect(wrong, isNot(contains(_pw)));
    for (final f in ArchiveImportFailure.values) {
      expect(
        archiveImportMessage(l10n, ArchiveImportException(f)),
        isNot(contains(_pw)),
      );
    }
    await d.stop(tester);
  });
}
