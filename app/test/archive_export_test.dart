import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/archive/archive_export_action.dart';
import 'package:running_app/l10n/app_localizations.dart';

import 'app_harness.dart';

const String _pw = 'korrekt pferd batterie';

ExportFile _file() => ExportFile.inExportDirectory(
  fileName: 'running-archiv-20260601.runarch',
  mimeType: archiveMimeType,
  path: '/cache/exports/running-archiv-20260601.runarch',
);

/// Ersatz für den Export: merkt Passwort und Abbruchmarke, wartet auf
/// [gate], wenn gesetzt, und liefert dann [result] oder wirft [error].
class _FakeRunner {
  final List<String> passwords = [];
  ArchiveCancel? cancel;
  Completer<void>? gate;
  Object? error;
  bool ignoreCancel = false;

  Future<ExportFile> call({
    required String password,
    ArchiveCancel? cancel,
  }) async {
    passwords.add(password);
    this.cancel = cancel;
    await gate?.future;
    if (!ignoreCancel && (cancel?.isCancelled ?? false)) {
      throw const ArchiveExportException(ArchiveExportFailure.cancelled);
    }
    if (error != null) throw error!;
    return _file();
  }
}

Future<Device> _open(
  WidgetTester tester,
  _FakeRunner runner, {
  bool wired = true,
}) async {
  final d = Device();
  if (wired) d.archiveExport = (_) => runner.call;
  await d.start(tester, const Locale('de'));
  await d.skipSetup(tester);
  await openOverview(tester);
  await tester.tap(find.byKey(const Key('overview_data')));
  await tester.pumpAndSettle();
  return d;
}

Future<void> _openDialog(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('archive_export')));
  await tester.pumpAndSettle();
}

Future<void> _fill(WidgetTester tester, String a, String b) async {
  await tester.enterText(find.byKey(const Key('archive_password')), a);
  await tester.enterText(find.byKey(const Key('archive_password_repeat')), b);
}

TextField _field(WidgetTester tester, String key) =>
    tester.widget<TextField>(find.byKey(Key(key)));

void main() {
  testWidgets('ohne Verdrahtung kein Eintrag im Daten-Bildschirm', (
    tester,
  ) async {
    final d = await _open(tester, _FakeRunner(), wired: false);
    expect(find.byKey(const Key('archive_export')), findsNothing);
    await d.stop(tester);
  });

  testWidgets('Dialog: Hinweis zum vergessenen Passwort, verdeckte Felder ohne '
      'Autofill', (tester) async {
    final d = await _open(tester, _FakeRunner());
    expect(find.text('Archiv exportieren'), findsOneWidget);
    await _openDialog(tester);

    final warning = find.byKey(const Key('archive_warning'));
    expect(warning, findsOneWidget);
    expect(find.textContaining('unbrauchbar'), findsOneWidget);
    expect(find.textContaining('keinen Weg'), findsOneWidget);
    for (final key in ['archive_password', 'archive_password_repeat']) {
      final f = _field(tester, key);
      expect(f.obscureText, isTrue, reason: key);
      expect(f.autofillHints, isEmpty, reason: key);
      expect(f.enableSuggestions, isFalse, reason: key);
      expect(f.autocorrect, isFalse, reason: key);
      expect(f.enableIMEPersonalizedLearning, isFalse, reason: key);
    }
    await d.stop(tester);
  });

  testWidgets('Passwortregel: 15 Zeichen, zweite Eingabe gleich', (
    tester,
  ) async {
    final runner = _FakeRunner();
    final d = await _open(tester, runner);
    await _openDialog(tester);

    // 14 Zeichen: zu kurz.
    await _fill(tester, '12345678901234', '12345678901234');
    await tester.tap(find.byKey(const Key('archive_share')));
    await tester.pumpAndSettle();
    expect(
      find.text('Das Passwort braucht mindestens 15 Zeichen.'),
      findsOneWidget,
    );
    // Zählt Zeichen, nicht UTF-16-Einheiten: 8 Emoji sind 16 Einheiten.
    await _fill(tester, '😀' * 8, '😀' * 8);
    await tester.tap(find.byKey(const Key('archive_share')));
    await tester.pumpAndSettle();
    expect(
      find.text('Das Passwort braucht mindestens 15 Zeichen.'),
      findsOneWidget,
    );
    // Lang genug, Wiederholung weicht ab (auch nur durch ein Leerzeichen).
    await _fill(tester, _pw, '$_pw ');
    await tester.tap(find.byKey(const Key('archive_share')));
    await tester.pumpAndSettle();
    expect(
      find.text('Die beiden Eingaben stimmen nicht überein.'),
      findsOneWidget,
    );
    expect(runner.passwords, isEmpty);
    expect(d.fileHandoff.shared, isEmpty);
    // Genau 15 Zeichen und gleich: Der Export läuft.
    await _fill(tester, '123456789012345', '123456789012345');
    await tester.tap(find.byKey(const Key('archive_share')));
    await tester.pumpAndSettle();
    expect(runner.passwords, ['123456789012345']);
    await d.stop(tester);
  });

  testWidgets('Teilen: Export mit Passwort, Übergabe der Datei, Meldung', (
    tester,
  ) async {
    final runner = _FakeRunner();
    final d = await _open(tester, runner);
    await _openDialog(tester);
    await _fill(tester, _pw, _pw);
    await tester.tap(find.byKey(const Key('archive_share')));
    await tester.pumpAndSettle();

    expect(runner.passwords, [_pw]);
    expect(
      d.fileHandoff.shared.single.fileName,
      'running-archiv-20260601.runarch',
    );
    expect(d.fileHandoff.saved, isEmpty);
    expect(find.byKey(const Key('archive_dialog')), findsNothing);
    expect(find.text('Archiv an das gewählte Ziel übergeben.'), findsOneWidget);
    await d.stop(tester);
  });

  testWidgets('Speichern geht an save, nicht an share', (tester) async {
    final runner = _FakeRunner();
    final d = await _open(tester, runner);
    await _openDialog(tester);
    await _fill(tester, _pw, _pw);
    await tester.tap(find.byKey(const Key('archive_save')));
    await tester.pumpAndSettle();

    expect(d.fileHandoff.saved, hasLength(1));
    expect(d.fileHandoff.shared, isEmpty);
    expect(find.text('Archiv gespeichert.'), findsOneWidget);
    await d.stop(tester);
  });

  testWidgets('Fortschritt: Dialog bleibt, Passwort nicht mehr im Feld, '
      'Außentippen schließt nicht', (tester) async {
    final runner = _FakeRunner()..gate = Completer<void>();
    final d = await _open(tester, runner);
    await _openDialog(tester);
    await _fill(tester, _pw, _pw);
    await tester.tap(find.byKey(const Key('archive_share')));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('archive_progress')), findsOneWidget);
    expect(find.byKey(const Key('archive_password')), findsNothing);
    await tester.tapAt(const Offset(2, 2));
    await tester.pump();
    // Auch die Zurück-Taste des Systems schließt den Dialog nicht.
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byKey(const Key('archive_working')), findsOneWidget);
    // Ein zweiter Start ist nicht möglich: kein Knopf mehr.
    expect(find.byKey(const Key('archive_share')), findsNothing);

    runner.gate!.complete();
    await tester.pumpAndSettle();
    expect(runner.passwords, hasLength(1));
    expect(d.fileHandoff.shared, hasLength(1));
    await d.stop(tester);
  });

  testWidgets('Abbruch: Marke gesetzt, nichts übergeben, Meldung', (
    tester,
  ) async {
    final runner = _FakeRunner()..gate = Completer<void>();
    final d = await _open(tester, runner);
    await _openDialog(tester);
    await _fill(tester, _pw, _pw);
    await tester.tap(find.byKey(const Key('archive_share')));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byKey(const Key('archive_abort')));
    await tester.pump();
    expect(runner.cancel!.isCancelled, isTrue);
    runner.gate!.complete();
    await tester.pumpAndSettle();

    expect(d.fileHandoff.shared, isEmpty);
    expect(d.fileHandoff.saved, isEmpty);
    expect(find.byKey(const Key('archive_dialog')), findsNothing);
    expect(find.text('Export abgebrochen.'), findsOneWidget);
    await d.stop(tester);
  });

  testWidgets('Abbruch nach fertigem Export übergibt nichts', (tester) async {
    final runner = _FakeRunner()
      ..gate = Completer<void>()
      ..ignoreCancel = true;
    final d = await _open(tester, runner);
    await _openDialog(tester);
    await _fill(tester, _pw, _pw);
    await tester.tap(find.byKey(const Key('archive_share')));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byKey(const Key('archive_abort')));
    // Der Export war schon fertig und ignoriert die Marke.
    runner.gate!.complete();
    await tester.pumpAndSettle();
    expect(runner.cancel!.isCancelled, isTrue);
    expect(d.fileHandoff.shared, isEmpty);
    expect(find.text('Export abgebrochen.'), findsOneWidget);
    await d.stop(tester);
  });

  testWidgets('Fehler im Export: Meldung im Dialog ohne Inhalte, Felder leer', (
    tester,
  ) async {
    final runner = _FakeRunner()
      ..error = const ArchiveExportException(ArchiveExportFailure.writeFailed);
    final d = await _open(tester, runner);
    await _openDialog(tester);
    await _fill(tester, _pw, _pw);
    await tester.tap(find.byKey(const Key('archive_share')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('archive_error')), findsOneWidget);
    expect(find.text('Archiv-Export fehlgeschlagen.'), findsOneWidget);
    expect(find.textContaining('writeFailed'), findsNothing);
    expect(find.textContaining(_pw), findsNothing);
    // Das Passwort ist aus beiden Controllern gelöscht.
    expect(_field(tester, 'archive_password').controller!.text, isEmpty);
    expect(_field(tester, 'archive_password_repeat').controller!.text, isEmpty);
    expect(d.fileHandoff.shared, isEmpty);

    // Neuer Versuch ist möglich.
    runner.error = null;
    await _fill(tester, _pw, _pw);
    await tester.tap(find.byKey(const Key('archive_share')));
    await tester.pumpAndSettle();
    expect(d.fileHandoff.shared, hasLength(1));
    await d.stop(tester);
  });

  testWidgets(
    'Unerwarteter Fehler und Fehler der Übergabe: Meldung im Dialog',
    (tester) async {
      final runner = _FakeRunner()..error = StateError('Pfad /geheim 4711');
      final d = await _open(tester, runner);
      await _openDialog(tester);
      await _fill(tester, _pw, _pw);
      await tester.tap(find.byKey(const Key('archive_share')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('archive_error')), findsOneWidget);
      expect(find.textContaining('geheim'), findsNothing);

      runner.error = null;
      d.fileHandoff.nextResult = FileHandoffResult.failed;
      await _fill(tester, _pw, _pw);
      await tester.tap(find.byKey(const Key('archive_save')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('archive_error')), findsOneWidget);
      expect(d.fileHandoff.saved, hasLength(1));
      await d.stop(tester);
    },
  );

  testWidgets('Abbruch im Systemdialog: still, Dialog schließt', (
    tester,
  ) async {
    final runner = _FakeRunner();
    final d = await _open(tester, runner);
    d.fileHandoff.nextResult = FileHandoffResult.cancelled;
    await _openDialog(tester);
    await _fill(tester, _pw, _pw);
    await tester.tap(find.byKey(const Key('archive_share')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('archive_dialog')), findsNothing);
    expect(find.text('Archiv-Export fehlgeschlagen.'), findsNothing);
    await d.stop(tester);
  });

  testWidgets('Schließen ohne Export ruft nichts auf', (tester) async {
    final runner = _FakeRunner();
    final d = await _open(tester, runner);
    await _openDialog(tester);
    await _fill(tester, _pw, _pw);
    await tester.tap(find.byKey(const Key('archive_close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('archive_dialog')), findsNothing);
    expect(runner.passwords, isEmpty);
    await d.stop(tester);
  });

  testWidgets('Kein Export, solange ein Lauf offen ist', (tester) async {
    final runner = _FakeRunner();
    final d = await _open(tester, runner);
    await d.session.runs.create(startedAt: DateTime.utc(2026, 6, 1));
    await _openDialog(tester);
    await _fill(tester, _pw, _pw);
    await tester.tap(find.byKey(const Key('archive_share')));
    await tester.pumpAndSettle();

    expect(runner.passwords, isEmpty);
    expect(d.fileHandoff.shared, isEmpty);
    expect(
      find.text(
        'Beende zuerst den laufenden Lauf, danach kannst du das '
        'Archiv exportieren.',
      ),
      findsOneWidget,
    );
    await d.stop(tester);
  });

  testWidgets('Export läuft nur über serialize (ausgeschlossen von Aufnahme '
      'und Neuberechnung)', (tester) async {
    final d = Device();
    await d.start(tester, const Locale('de'));
    final runner = _FakeRunner();
    final order = <String>[];
    final release = Completer<void>();
    // Eine vorher eingereihte Aktion hält die Reihe an.
    var queue = release.future;
    Future<T> serialize<T>(Future<T> Function() action) {
      order.add('eingereiht');
      final r = queue.then((_) => action());
      queue = r.then((_) {}, onError: (Object _) {});
      return r;
    }

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('de'),
        home: Scaffold(
          body: Builder(
            builder: (context) => ArchiveExportDialog(
              session: d.session,
              runner: runner.call,
              handoff: d.fileHandoff,
              serialize: serialize,
            ),
          ),
        ),
      ),
    );
    await _fill(tester, _pw, _pw);
    await tester.tap(find.byKey(const Key('archive_share')));
    await tester.pump();
    await tester.pump();
    expect(order, ['eingereiht']);
    expect(runner.passwords, isEmpty);
    release.complete();
    await tester.pumpAndSettle();
    expect(runner.passwords, [_pw]);
    await d.stop(tester);
  });
}
