import 'dart:async';
import 'dart:convert';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/export/run_export_action.dart';

import 'app_harness.dart';
import 'history_summary_test.dart' show key, openHistory;
import 'run_detail_test.dart' show seedDetailRun;

final DateTime _start = DateTime.utc(2030, 1, 1, 8);

/// Startet die App, legt einen beendeten Lauf an und öffnet sein Detail.
Future<Device> _openDetail(
  WidgetTester tester, {
  void Function(Device d)? before,
  String locale = 'de',
}) async {
  final d = Device();
  before?.call(d);
  await d.start(tester, Locale(locale));
  await d.skipSetup(tester);
  final id = await seedDetailRun(d.session, _start, seconds: 120);
  await openHistory(d, tester);
  await tester.tap(key('history_run_$id'));
  await tester.pumpAndSettle();
  return d;
}

/// Öffnet die Formatwahl, wählt [format] und tippt auf [target].
Future<void> _export(
  WidgetTester tester,
  ExportFormat format,
  String target, {
  bool settle = true,
}) async {
  await tester.tap(key('detail_export'));
  await tester.pumpAndSettle();
  await tester.tap(key('export_format_${format.name}'));
  await tester.pumpAndSettle();
  await tester.tap(key(target));
  if (settle) await tester.pumpAndSettle();
}

String? _snackText() {
  final bar = find.byType(SnackBar);
  if (bar.evaluate().isEmpty) return null;
  return tester_
      .widget<Text>(find.descendant(of: bar, matching: find.byType(Text)))
      .data;
}

late WidgetTester tester_;

void main() {
  testWidgets('Detail eines beendeten Laufs: Aktion sichtbar, nichts '
      'übertragen ohne Tippen', (tester) async {
    tester_ = tester;
    final d = await _openDetail(tester);
    expect(key('detail_export'), findsOneWidget);
    expect(d.fileHandoff.shared, isEmpty);
    expect(d.fileHandoff.saved, isEmpty);
    // Auch das Öffnen der Formatwahl überträgt nichts.
    await tester.tap(key('detail_export'));
    await tester.pumpAndSettle();
    expect(key('export_share'), findsOneWidget);
    expect(d.fileHandoff.shared, isEmpty);
    expect(d.fileHandoff.saved, isEmpty);
  });

  testWidgets('Formatwahl teilt die richtige Datei je Format', (tester) async {
    tester_ = tester;
    final d = await _openDetail(tester);
    for (final (format, mime, check) in [
      (
        ExportFormat.gpx,
        'application/gpx+xml',
        (List<int> b) =>
            utf8.decode(b).startsWith('<?xml') &&
            utf8.decode(b).contains('<gpx '),
      ),
      (
        ExportFormat.tcx,
        'application/vnd.garmin.tcx+xml',
        (List<int> b) =>
            utf8.decode(b).startsWith('<?xml') &&
            utf8.decode(b).contains('<TrainingCenterDatabase '),
      ),
      (
        ExportFormat.fit,
        'application/vnd.ant.fit',
        // Kopf: 14 Byte, ab Byte 8 die Kennung ".FIT".
        (List<int> b) => b[0] == 14 && ascii.decode(b.sublist(8, 12)) == '.FIT',
      ),
    ]) {
      await _export(tester, format, 'export_share');
      final file = d.fileHandoff.shared.last;
      // Start 08:00 UTC, Ortszeit UTC+0 (seedDetailRun).
      expect(file.fileName, 'run-20300101-080000.${format.extension}');
      expect(file.mimeType, mime);
      expect(check(file.bytes!), isTrue, reason: format.name);
      expect(_snackText(), 'Datei an das gewählte Ziel übergeben.');
      // SnackBar abwarten, damit die nächste Runde sie neu sieht.
      ScaffoldMessenger.of(tester.element(key('detail_export')))
          .removeCurrentSnackBar();
      await tester.pumpAndSettle();
    }
    expect(d.fileHandoff.shared, hasLength(3));
    expect(d.fileHandoff.saved, isEmpty);
  });

  testWidgets('Speichern geht an das Dokumentenziel', (tester) async {
    tester_ = tester;
    final d = await _openDetail(tester, locale: 'en');
    await _export(tester, ExportFormat.fit, 'export_save');
    expect(d.fileHandoff.saved.single.fileName, 'run-20300101-080000.fit');
    expect(d.fileHandoff.shared, isEmpty);
    expect(_snackText(), 'File saved.');
  });

  testWidgets('Export ist der Knopf am Seitenende, nicht in der Kopfleiste', (
    tester,
  ) async {
    tester_ = tester;
    await _openDetail(tester);
    expect(
      find.descendant(of: find.byType(AppBar), matching: key('detail_export')),
      findsNothing,
    );
    final button = tester.getRect(key('detail_export'));
    final screen = tester.getSize(find.byType(Scaffold).first);
    // Volle Breite abzüglich Seitenrand 16 + 16, 52 dp hoch, unter dem Inhalt.
    expect(button.width, screen.width - 32);
    expect(button.height, 52);
    final sources = tester.getRect(key('sum_explain_sources'));
    expect(button.top, greaterThan(sources.bottom));
    expect(find.text('Exportieren (GPX · TCX · FIT)'), findsOneWidget);
  });

  testWidgets('Abbruch in der Formatwahl erzeugt und überträgt nichts', (
    tester,
  ) async {
    tester_ = tester;
    var jobs = 0;
    final d = await _openDetail(
      tester,
      before: (d) => d.offload = <A, R>(R Function(A) job, A arg) async {
        if (identical(job, exportFileJob)) jobs++;
        return job(arg);
      },
    );
    await tester.tap(key('detail_export'));
    await tester.pumpAndSettle();
    await tester.tap(key('export_cancel'));
    await tester.pumpAndSettle();
    expect(jobs, 0);
    expect(d.fileHandoff.shared, isEmpty);
    expect(d.fileHandoff.saved, isEmpty);
    expect(_snackText(), isNull);
    expect(key('detail_export'), findsOneWidget);
  });

  testWidgets('Abbruch im Teilen-Menü bleibt still', (tester) async {
    tester_ = tester;
    final d = await _openDetail(tester);
    d.fileHandoff.nextResult = FileHandoffResult.cancelled;
    await _export(tester, ExportFormat.gpx, 'export_share');
    expect(d.fileHandoff.shared, hasLength(1));
    expect(_snackText(), isNull);
    expect(key('detail_export'), findsOneWidget);
  });

  testWidgets('Fehler der Übergabe: Meldung ohne Inhalte', (tester) async {
    tester_ = tester;
    final d = await _openDetail(tester);
    d.fileHandoff.nextResult = FileHandoffResult.failed;
    await _export(tester, ExportFormat.tcx, 'export_save');
    expect(_snackText(), 'Export fehlgeschlagen.');
    expect(key('detail_export'), findsOneWidget);
  });

  testWidgets('Fehler beim Erzeugen: Meldung ohne Inhalte, nichts übertragen', (
    tester,
  ) async {
    tester_ = tester;
    final d = await _openDetail(
      tester,
      before: (d) => d.offload = <A, R>(R Function(A) job, A arg) async {
        if (identical(job, exportFileJob)) {
          throw StateError('/data/user/0/x/run.gpx 150 bpm');
        }
        return job(arg);
      },
    );
    await _export(tester, ExportFormat.gpx, 'export_share');
    expect(_snackText(), 'Export fehlgeschlagen.');
    // Weder Ausnahmetext noch Pfad oder Messwert erscheinen irgendwo.
    expect(find.textContaining('/data'), findsNothing);
    expect(find.textContaining('150 bpm'), findsNothing);
    expect(d.fileHandoff.shared, isEmpty);
  });

  testWidgets('Fortschritt während des Erzeugens, Rechnung über den Offload', (
    tester,
  ) async {
    tester_ = tester;
    final release = Completer<void>();
    final d = await _openDetail(
      tester,
      before: (d) => d.offload = <A, R>(R Function(A) job, A arg) async {
        if (identical(job, exportFileJob)) await release.future;
        return job(arg);
      },
    );
    await _export(tester, ExportFormat.gpx, 'export_share', settle: false);
    await tester.pump();
    await tester.pump();
    expect(key('export_progress'), findsOneWidget);
    expect(key('detail_export'), findsNothing);
    expect(d.fileHandoff.shared, isEmpty);
    release.complete();
    await tester.pumpAndSettle();
    expect(key('export_progress'), findsNothing);
    expect(d.fileHandoff.shared, hasLength(1));
  });

  testWidgets('kein Export für nicht beendete oder unbekannte Läufe', (
    tester,
  ) async {
    tester_ = tester;
    final d = Device();
    await d.start(tester, const Locale('de'));
    await d.skipSetup(tester);
    final active = await d.session.runs.create(startedAt: _start);
    for (final id in [active.id, 999]) {
      unawaited(
        Navigator.of(tester.element(key('home_history'))).push<void>(
          MaterialPageRoute(
            builder: (_) => Scaffold(
              appBar: AppBar(
                actions: [RunExportAction(session: d.session, runId: id)],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(RunExportAction), findsOneWidget);
      expect(key('detail_export'), findsNothing, reason: '$id');
      Navigator.of(tester.element(find.byType(RunExportAction))).pop();
      await tester.pumpAndSettle();
    }
    expect(d.fileHandoff.shared, isEmpty);
  });
}
