// FR-0223: Diagnose-Export ohne Werte – Inhalt (nur Typ, Ort, Anzahl,
// App-Version, Zeitraum; SEC-0008), Dateiname, Teilen erst nach Bestätigung
// im Dialog (FR-0201).
import 'dart:convert';

import 'package:core/core.dart';
import 'package:core/fakes/fake_storage_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/error_counter.dart';
import 'package:running_app/features/export/diagnostics_export_action.dart';
import 'package:running_app/features/export/file_handoff_scope.dart';
import 'package:running_app/l10n/app_localizations.dart';
import 'package:running_app/ui/ui.dart';

/// Synthetischer Zahlenwert in der Fehlernachricht; er darf nie in die Datei.
const _number = '4711';

class _ValueError implements Exception {
  @override
  String toString() => 'Ruhepuls $_number bpm gemessen';
}

/// Stack wie aus der App, mit Zeile, Spalte und einem Rahmen mit Argument.
StackTrace _stack() => StackTrace.fromString(
  '#0      Element.rebuild (package:flutter/src/widgets/framework.dart:5000:7)\n'
  '#1      Measure.run (package:running_app/features/measure/x.dart:12:3)\n'
  '#2      Baz.qux (package:core/src/other.dart:3:1)\n',
);

/// Zähler mit einem gezählten [_ValueError] am 2026-11-03 und einem zweiten
/// am 2026-11-09 (lokaler Tag, Versatz +1 h).
Future<(ErrorCounter, FakeStorage)> _counted() async {
  final storage = FakeStorage();
  final clock = FakeClock(
    DateTime.utc(2026, 11, 3, 8),
    utcOffset: const Duration(hours: 1),
  );
  final c = ErrorCounter()..attach(FakeSettingsStore(storage.data), clock);
  c.record(_ValueError(), _stack());
  await c.idle;
  clock.advanceTo(DateTime.utc(2026, 11, 9, 23, 30));
  c.record(_ValueError(), _stack());
  await c.idle;
  return (c, storage);
}

void main() {
  group('Inhalt', () {
    test('Fehler mit Zahlenwert in der Nachricht: Datei enthält Typ, Ort, '
        'Anzahl, App-Version und Zeitraum, aber weder Nachricht noch Wert '
        'noch Stack', () async {
      final (c, _) = await _counted();
      final text = diagnosticsJson(await c.read(), appVersion: '0.1.0 (12)');
      final json = jsonDecode(text) as Map<String, Object?>;
      expect(json, {
        'format': 'ramuri-diagnose',
        'formatVersion': 1,
        'appVersion': '0.1.0 (12)',
        'from': '2026-11-03',
        // 23:30 UTC + 1 h: lokal schon der 10.
        'to': '2026-11-10',
        'errors': [
          {
            'type': '_ValueError',
            'place': 'package:running_app/features/measure/x.dart',
            'count': 2,
          },
        ],
      });
      expect(text, isNot(contains(_number)));
      expect(text, isNot(contains('Ruhepuls')));
      expect(text, isNot(contains('bpm')));
      expect(text, isNot(contains('#1')));
      expect(text, isNot(contains('framework.dart')));
      expect(text, isNot(contains('Measure.run')));
      expect(text, isNot(contains(':12')));
      expect(text, isNot(contains('other.dart')));
    });

    test('nur die festgelegten Felder; Einträge nach Anzahl absteigend', () {
      final text = diagnosticsJson(const [
        ErrorCount(type: 'A', place: 'p1', count: 1, firstDay: '2026-11-05'),
        ErrorCount(type: 'B', place: 'p2', count: 3, lastDay: '2026-11-07'),
        ErrorCount(type: 'A', place: 'p0', count: 3),
      ], appVersion: null);
      final json = jsonDecode(text) as Map<String, Object?>;
      expect(json.keys.toSet(), {
        'format',
        'formatVersion',
        'appVersion',
        'from',
        'to',
        'errors',
      });
      expect(json['appVersion'], isNull);
      expect(json['from'], '2026-11-05');
      expect(json['to'], '2026-11-07');
      final errors = (json['errors']! as List).cast<Map<String, Object?>>();
      for (final e in errors) {
        expect(e.keys.toSet(), {'type', 'place', 'count'});
      }
      expect(
        [for (final e in errors) '${e['type']}/${e['place']}'],
        ['A/p0', 'B/p2', 'A/p1'],
      );
    });

    test('ohne Einträge: leere Liste, Zeitraum null', () {
      final json = jsonDecode(
        diagnosticsJson(const [], appVersion: 'v'),
      ) as Map<String, Object?>;
      expect(json['errors'], isEmpty);
      expect(json['from'], isNull);
      expect(json['to'], isNull);
    });

    test('Dateiname ramuri-diagnose-JJJJMMTT.json, JSON, UTF-8', () {
      expect(
        diagnosticsFileName(DateTime(2031, 2, 3, 23, 59)),
        'ramuri-diagnose-20310203.json',
      );
      final f = diagnosticsFile('{"ä":1}', now: DateTime(2026, 11, 24));
      expect(f.fileName, 'ramuri-diagnose-20261124.json');
      expect(f.mimeType, 'application/json');
      expect(utf8.decode(f.bytes!), '{"ä":1}');
    });
  });

  group('Teilen', () {
    Future<(FakeFileHandoff, ErrorCounter)> pump(
      WidgetTester tester, {
      String locale = 'de',
      FakeFileHandoff? handoff,
    }) async {
      final (c, _) = await _counted();
      final h = handoff ?? FakeFileHandoff();
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale(locale),
          theme: RamuriTheme.light,
          home: Scaffold(
            body: FileHandoffScope(
              handoff: h,
              child: DiagnosticsExportAction(
                errors: c,
                appVersion: () async => '0.1.0 (12)',
                clock: () => DateTime(2031, 2, 3),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return (h, c);
    }

    testWidgets('Dialog zeigt den Inhalt; Abbrechen erzeugt keine Datei', (
      tester,
    ) async {
      final (h, _) = await pump(tester);
      await tester.tap(find.text('Diagnose teilen'));
      await tester.pumpAndSettle();
      expect(find.text('Diagnose teilen?'), findsOneWidget);
      final content = tester
          .widget<SelectableText>(
            find.byKey(const Key('dev_errors_share_content')),
          )
          .data!;
      expect(content, contains('"type": "_ValueError"'));
      expect(content, contains('"appVersion": "0.1.0 (12)"'));
      expect(content, isNot(contains(_number)));
      expect(h.shared, isEmpty);
      await tester.tap(find.byKey(const Key('dev_errors_share_cancel')));
      await tester.pumpAndSettle();
      expect(find.text('Diagnose teilen?'), findsNothing);
      expect(h.shared, isEmpty);
      expect(h.saved, isEmpty);
    });

    testWidgets('Teilen erst nach Bestätigen; Datei = gezeigter Inhalt', (
      tester,
    ) async {
      final (h, _) = await pump(tester);
      await tester.tap(find.text('Diagnose teilen'));
      await tester.pumpAndSettle();
      final content = tester
          .widget<SelectableText>(
            find.byKey(const Key('dev_errors_share_content')),
          )
          .data!;
      expect(h.shared, isEmpty);
      await tester.tap(find.byKey(const Key('dev_errors_share_confirm')));
      await tester.pumpAndSettle();
      final file = h.shared.single;
      expect(file.fileName, 'ramuri-diagnose-20310203.json');
      expect(file.mimeType, 'application/json');
      expect(utf8.decode(file.bytes!), content);
      expect(h.saved, isEmpty);
      expect(
        find.text('Datei an das gewählte Ziel übergeben.'),
        findsOneWidget,
      );
    });

    testWidgets('Englisch', (tester) async {
      await pump(tester, locale: 'en');
      await tester.tap(find.text('Share diagnostics'));
      await tester.pumpAndSettle();
      expect(find.text('Share diagnostics?'), findsOneWidget);
      expect(find.text('Share'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('ohne Übergabe (kein Scope) kein Knopf', (tester) async {
      final c = ErrorCounter();
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: DiagnosticsExportAction(
            errors: c,
            appVersion: () async => null,
          ),
        ),
      );
      expect(find.byKey(const Key('dev_errors_share')), findsNothing);
    });
  });
}
