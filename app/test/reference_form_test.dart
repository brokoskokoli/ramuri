import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:running_app/ui/format/unit_format.dart';
import 'package:running_app/features/statistics/reference_form.dart';
import 'package:running_app/l10n/app_localizations.dart';

import 'helpers/widget_helpers.dart';

/// Mittwoch, 11.11.2026, mittags Ortszeit.
final _now = DateTime(2026, 11, 11, 12);

/// Lokale Mitternacht des Kalendertags [daysAgo] Tage vor dem 11.11.2026.
/// Kalenderarithmetik statt `n × 24 h`: Liegt ein Sommerzeitende dazwischen
/// (Berlin 25.10., Los Angeles 01.11.), bleibt es Mitternacht (PAR-164).
DateTime _day(int daysAgo) => DateTime(2026, 11, 11 - daysAgo);

PredictionRun _run(
  String id, {
  required int daysAgo,
  double meters = 5000,
  double seconds = 25 * 60,
  int? rpe,
}) => PredictionRun(
  id: id,
  date: _day(daysAgo),
  movingSeconds: seconds,
  distanceMeters: meters,
  rpe: rpe,
);

UnitFormatter _formatter(String lang, {bool miles = false}) => UnitFormatter(
  unit: miles ? DistanceUnit.miles : DistanceUnit.kilometers,
  languageCode: lang,
  distanceLabel: miles ? 'mi' : 'km',
  paceLabel: miles ? 'min/mi' : 'min/km',
  elevationLabel: miles ? 'ft' : 'm',
);

/// Öffnet das Referenzformular mit [runs] als Lauf-Übersicht; das Ergebnis
/// steht nach dem Schließen in [result].
class _Host {
  ReferencePerformance? result;
  bool closed = false;
}

Future<_Host> _open(
  WidgetTester tester, {
  required List<PredictionRun> runs,
  String lang = 'de',
  bool miles = false,
  double scale = 1,
  Size size = const Size(411, 900),
  bool failing = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final host = _Host();
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(scale)),
      child: localizedApp(
        locale: Locale(lang),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                key: const Key('open'),
                onPressed: () async {
                  host.result = await showReferenceForm(
                    context,
                    now: _now,
                    formatter: _formatter(lang, miles: miles),
                    loadRuns: () async {
                      if (failing) throw StateError('nicht lesbar');
                      return runs;
                    },
                  );
                  host.closed = true;
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const Key('open')));
  await tester.pumpAndSettle();
  return host;
}

Future<void> _tapKey(WidgetTester tester, String key) =>
    tapFinderAfterSettle(tester, find.byKey(Key(key)));

String _text(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key))).data!;

String _buttonText(WidgetTester tester, String key) => tester
    .widget<Text>(
      find.descendant(of: find.byKey(Key(key)), matching: find.byType(Text)),
    )
    .data!;

void main() {
  late AppLocalizations de;
  late AppLocalizations en;
  setUpAll(() async {
    de = await AppLocalizations.delegate.load(const Locale('de'));
    en = await AppLocalizations.delegate.load(const Locale('en'));
  });

  group('Aus einem Lauf übernehmen (FR-0129)', () {
    testWidgets('Liste: nur Läufe ab 3 km der letzten 12 Wochen, neueste '
        'zuerst, mit Datum, Distanz, Zeit, Tempo und RPE', (tester) async {
      await _open(
        tester,
        runs: [
          _run('kurz', daysAgo: 1, meters: 2900, seconds: 15 * 60),
          _run('mitte', daysAgo: 20, meters: 8000, seconds: 44 * 60, rpe: 6),
          _run('alt', daysAgo: 90, meters: 10000, seconds: 50 * 60),
          _run('neu', daysAgo: 2, meters: 5000, seconds: 25 * 60, rpe: 9),
        ],
      );
      await _tapKey(tester, 'prediction_form_from_run');
      expect(find.byKey(const Key('reference_run_picker')), findsOneWidget);
      expect(find.byKey(const Key('reference_run_2')), findsNothing);
      expect(
        _text(tester, 'reference_run_0_text'),
        '5,00 km in 25:00 · '
        '5:00 min/km',
      );
      expect(_text(tester, 'reference_run_0_rpe'), de.referenceRunRpe(9));
      expect(
        _text(tester, 'reference_run_1_text'),
        '8,00 km in 44:00 · '
        '5:30 min/km',
      );
      expect(_text(tester, 'reference_run_1_rpe'), de.referenceRunRpe(6));
      expect(find.text(DateFormat.yMMMd('de').format(_day(2))), findsOneWidget);
      expect(
        find.text(DateFormat.yMMMd('de').format(_day(20))),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('Auswahl eines harten Laufs: ohne Hinweis übernommen als '
        'bestätigter Lauf mit Lauf-ID, Distanz, Zeit und Datum', (
      tester,
    ) async {
      final host = await _open(
        tester,
        runs: [_run('7', daysAgo: 3, seconds: 24 * 60 + 30, rpe: 8)],
      );
      await _tapKey(tester, 'prediction_form_from_run');
      await _tapKey(tester, 'reference_run_0');
      expect(find.byKey(const Key('reference_run_loose')), findsNothing);
      expect(host.closed, isTrue);
      final r = host.result!;
      expect(r.kind, ReferenceKind.confirmedRun);
      expect(r.runId, '7');
      expect(r.distanceMeters, 5000);
      expect(r.seconds, 24 * 60 + 30);
      expect(r.date, _day(3));
      expect(r.createdAt, _now);
    });

    testWidgets('Meilen-Einstellung: Liste in Meilen, übernommen in Metern', (
      tester,
    ) async {
      final host = await _open(
        tester,
        lang: 'en',
        miles: true,
        runs: [
          _run('3', daysAgo: 1, meters: 8046.72, seconds: 40 * 60, rpe: 9),
        ],
      );
      await _tapKey(tester, 'prediction_form_from_run');
      expect(
        _text(tester, 'reference_run_0_text'),
        '5.00 mi in 40:00 · '
        '8:00 min/mi',
      );
      expect(_text(tester, 'reference_run_0_rpe'), en.referenceRunRpe(9));
      await _tapKey(tester, 'reference_run_0');
      expect(host.result!.distanceMeters, 8046.72);
    });

    for (final rpe in [5, null]) {
      testWidgets('Lauf mit RPE $rpe: Hinweis; Abbrechen übernimmt nichts, '
          'Trotzdem übernehmen übernimmt (FR-0131)', (tester) async {
        final host = await _open(
          tester,
          runs: [_run('5', daysAgo: 4, rpe: rpe)],
        );
        await _tapKey(tester, 'prediction_form_from_run');
        await _tapKey(tester, 'reference_run_0');
        expect(find.byKey(const Key('reference_run_loose')), findsOneWidget);
        expect(find.text(de.referenceLooseBody), findsOneWidget);
        await _tapKey(tester, 'reference_run_loose_cancel');
        // Zurück in der Liste, nichts übernommen.
        expect(find.byKey(const Key('reference_run_loose')), findsNothing);
        expect(find.byKey(const Key('reference_run_picker')), findsOneWidget);
        expect(host.closed, isFalse);
        await _tapKey(tester, 'reference_run_cancel');
        await _tapKey(tester, 'prediction_form_cancel');
        expect(host.closed, isTrue);
        expect(host.result, isNull);

        await tester.tap(find.byKey(const Key('open')));
        await tester.pumpAndSettle();
        await _tapKey(tester, 'prediction_form_from_run');
        await _tapKey(tester, 'reference_run_0');
        await _tapKey(tester, 'reference_run_loose_confirm');
        expect(host.result!.kind, ReferenceKind.confirmedRun);
        expect(host.result!.runId, '5');
      });
    }

    testWidgets('Ohne Läufe ab 3 km: leere Liste mit Text', (tester) async {
      await _open(tester, runs: [_run('kurz', daysAgo: 1, meters: 2500)]);
      await _tapKey(tester, 'prediction_form_from_run');
      expect(
        _text(tester, 'reference_run_empty'),
        de.referenceRunPickerEmpty('3,00 km', 12),
      );
      expect(find.byKey(const Key('reference_run_0')), findsNothing);
    });

    testWidgets('Läufe nicht lesbar: Fehlertext ohne Inhalt des Fehlers', (
      tester,
    ) async {
      await _open(tester, runs: const [], failing: true);
      await _tapKey(tester, 'prediction_form_from_run');
      expect(
        _text(tester, 'reference_run_failed'),
        de.referenceRunPickerFailed,
      );
      expect(find.textContaining('nicht lesbar'), findsNothing);
    });

    testWidgets('Ungültige Referenz (Tempo außerhalb, PAR-208): Fehler im '
        'Formular mit Werten und Datum des Laufs, nichts übernommen', (
      tester,
    ) async {
      // 5 km in 10 min: schneller als 2:30 min/km. Der Lauf liegt klar vor
      // heute, damit das Datumsfeld nicht zufällig stimmt.
      final host = await _open(
        tester,
        runs: [_run('9', daysAgo: 20, seconds: 10 * 60, rpe: 9)],
      );
      final runDay = DateFormat.yMMMd('de').format(_day(20));
      expect(runDay, isNot(DateFormat.yMMMd('de').format(_day(0))));
      // Der Lauf liegt vor dem Sommerzeitende (Mitteleuropa 25.10., Los
      // Angeles 01.11.); erwartet wird trotzdem lokale Mitternacht seines
      // Kalendertags.
      expect(_day(20), DateTime(2026, 10, 22));
      await _tapKey(tester, 'prediction_form_from_run');
      await _tapKey(tester, 'reference_run_0');
      expect(host.closed, isFalse);
      expect(find.byKey(const Key('prediction_form_error')), findsOneWidget);
      // Die Felder zeigen die Werte des Laufs, auch das Datum.
      expect(find.text('5,00'), findsOneWidget);
      expect(find.text('10'), findsOneWidget);
      expect(_buttonText(tester, 'prediction_form_date'), runDay);
      // Nach einer Korrektur von Hand trägt die Referenz das Laufdatum.
      await tester.enterText(
        find.byKey(const Key('prediction_form_minutes')),
        '25',
      );
      await _tapKey(tester, 'prediction_form_save');
      expect(host.closed, isTrue);
      expect(host.result!.seconds, 25 * 60);
      expect(host.result!.date, _day(20));
      expect(host.result!.date, DateTime(2026, 10, 22));
    });

    for (final lang in ['de', 'en']) {
      testWidgets('$lang, große Schrift: Formular, Liste und Hinweis ohne '
          'Überlauf', (tester) async {
        await _open(
          tester,
          lang: lang,
          scale: 2,
          size: const Size(320, 640),
          runs: [
            for (var i = 0; i < 6; i++)
              _run('$i', daysAgo: 1 + i, meters: 12345.6, rpe: i == 0 ? 4 : 9),
          ],
        );
        expect(tester.takeException(), isNull);
        await _tapKey(tester, 'prediction_form_from_run');
        expect(tester.takeException(), isNull);
        await _tapKey(tester, 'reference_run_0');
        expect(find.byKey(const Key('reference_run_loose')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  testWidgets('Ohne Lauf-Übersicht kein Weg „Aus einem Lauf übernehmen“', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(411, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      localizedApp(
        home: Builder(
          builder: (context) => TextButton(
            key: const Key('open'),
            onPressed: () => showReferenceForm(
              context,
              now: _now,
              formatter: _formatter('de'),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('open')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('prediction_form')), findsOneWidget);
    expect(find.byKey(const Key('prediction_form_from_run')), findsNothing);
  });
}
