import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/statistics/fitness_section.dart';
import 'package:running_app/features/statistics/progress_header.dart';
import 'package:running_app/l10n/app_localizations.dart';
import 'package:running_app/ui/ui.dart';

/// Karten des Fortschrittskopfs einzeln, in Hell und Dunkel, Deutsch und
/// Englisch (WP15 Teil B): VO₂max ohne „±“ und ohne Genauigkeitsangabe,
/// Qualitätsstufen nach FR-0053, Effizienz nach FR-0087.

Finder k(String key) => find.byKey(Key(key));

String plain(WidgetTester tester, String key) {
  final t = tester.widget<Text>(k(key));
  return t.textSpan?.toPlainText() ?? t.data!;
}

/// Speicher, den die Karten nicht anfassen (nur der Weg zur Erklärung braucht
/// ihn, und den tippen diese Tests nicht an).
class _NoSession implements StorageSession {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Speicher nicht erwartet: ${invocation.memberName}');
}

ComputedValue stored(
  String key,
  double? v, {
  ValueQuality quality = ValueQuality.good,
  int count = 9,
  UnavailableReason? reason,
}) => ComputedValue(
  key: key,
  value: v,
  unit: 'u',
  unavailableReason: v == null
      ? (reason ?? UnavailableReason.insufficientData)
      : null,
  computedAt: DateTime.utc(2026, 6, 3),
  measurementCount: count,
  sources: const ['strap'],
  method: 'm',
  methodVersion: 1,
  parameterVersion: 1,
  quality: quality,
);

FitnessOverview overview({
  ComputedValue? longTerm,
  ComputedValue? efficiency,
  List<(String, double)> weeks = const [],
  bool failed = false,
}) => failed
    ? FitnessOverview.failed()
    : FitnessOverview(
        runEstimates: const [],
        longTerm: longTerm,
        efficiency: efficiency,
        pendingRuns: 0,
        longTermByDay: [
          for (final (day, v) in weeks)
            DayEstimate(day: day, value: stored(vo2maxLongTermValueKey, v)),
        ],
        day: '2026-06-03',
      );

Future<void> pumpCards(
  WidgetTester tester,
  FitnessOverview f, {
  String locale = 'de',
  Brightness brightness = Brightness.light,
}) async {
  tester.view.physicalSize = const Size(411, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: brightness == Brightness.light
          ? RamuriTheme.light
          : RamuriTheme.dark,
      locale: Locale(locale),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(
          child: Column(
            children: [
              Vo2ProgressCard(
                fitness: f,
                session: _NoSession(),
                onExplain: (context, valueKey, {runId, day}) {},
              ),
              EfficiencyCard(fitness: f),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

const _weeks = [('2026-05-25', 44.0), ('2026-06-01', 46.04)];

void main() {
  group('VO₂max-Karte (FR-0067, FR-0072, FR-0053)', () {
    for (final locale in ['de', 'en']) {
      for (final (quality, de, en) in [
        (
          ValueQuality.provisional,
          'Qualitätsstufe: vorläufig',
          'Quality level: provisional',
        ),
        (
          ValueQuality.sufficient,
          'Qualitätsstufe: ausreichend',
          'Quality level: sufficient',
        ),
        (ValueQuality.good, 'Qualitätsstufe: gut', 'Quality level: good'),
      ]) {
        testWidgets('$locale ${quality.name}: Wert, Läufe, Stufe, kein ±', (
          tester,
        ) async {
          await pumpCards(
            tester,
            overview(
              longTerm: stored(
                vo2maxLongTermValueKey,
                46.04,
                quality: quality,
                count: 9,
              ),
              weeks: _weeks,
            ),
            locale: locale,
          );
          final decimal = locale == 'de' ? '46,0' : '46.0';
          expect(plain(tester, 'progress_vo2'), startsWith(decimal));
          expect(plain(tester, 'progress_vo2'), endsWith(' ml/kg/min'));
          expect(
            plain(tester, 'progress_vo2_basis'),
            locale == 'de'
                ? '9 verwertbare Läufe · $de'
                : '9 usable runs · $en',
          );
          // Stufen sind Einteilungen, keine Genauigkeit (FR-0054, FR-0072).
          final everything = find
              .byType(Text)
              .evaluate()
              .map((e) => (e.widget as Text))
              .map((t) => t.textSpan?.toPlainText() ?? t.data ?? '')
              .join('\n');
          for (final word in ['±', 'Genauigkeit', 'accuracy', 'precision']) {
            expect(everything, isNot(contains(word)), reason: word);
          }
        });
      }
    }

    testWidgets(
      'Stufe „nicht bestimmbar“: Grund statt Zahl, keine Stufenzeile',
      (tester) async {
        await pumpCards(
          tester,
          overview(
            longTerm: stored(
              vo2maxLongTermValueKey,
              null,
              quality: ValueQuality.undeterminable,
              reason: UnavailableReason.insufficientData,
            ),
          ),
        );
        expect(k('progress_vo2'), findsNothing);
        expect(k('progress_vo2_basis'), findsNothing);
        expect(
          plain(tester, 'progress_vo2_reason'),
          isNot(matches(RegExp(r'\d'))),
        );
        expect(
          plain(tester, 'progress_vo2_reason'),
          contains('nicht verfügbar'),
        );
      },
    );

    testWidgets('kein gespeicherter Wert und Lesefehler: Grund', (
      tester,
    ) async {
      await pumpCards(tester, overview());
      expect(k('progress_vo2'), findsNothing);
      expect(
        plain(tester, 'progress_vo2_reason'),
        'nicht verfügbar (noch keine Schätzung gespeichert)',
      );
      await pumpCards(tester, overview(failed: true));
      expect(
        plain(tester, 'progress_vo2_reason'),
        'Die Fitnesswerte konnten nicht gelesen werden.',
      );
    });

    testWidgets('Sparkline: Werte in der Beschreibung, keine Trendbewertung', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpCards(
        tester,
        overview(
          longTerm: stored(vo2maxLongTermValueKey, 46.04),
          weeks: _weeks,
        ),
      );
      final label = tester.getSemantics(k('progress_vo2_sparkline')).label;
      expect(label, contains('44,0, 46,0 ml/kg/min'));
      for (final word in ['steigend', 'fallend', 'besser', 'Trend leicht']) {
        expect(label, isNot(contains(word)), reason: word);
      }
      // Ein einziger Wochenwert: keine Linie.
      await pumpCards(
        tester,
        overview(
          longTerm: stored(vo2maxLongTermValueKey, 46.04),
          weeks: const [('2026-06-01', 46.0)],
        ),
      );
      expect(k('progress_vo2_sparkline'), findsNothing);
      handle.dispose();
    });

    for (final b in Brightness.values) {
      testWidgets('${b.name}: dunkle Karte, Schrift mit Kontrast', (
        tester,
      ) async {
        await pumpCards(
          tester,
          overview(
            longTerm: stored(vo2maxLongTermValueKey, 46.04),
            weeks: _weeks,
          ),
          brightness: b,
        );
        final bg = tester
            .widget<Material>(
              find
                  .descendant(
                    of: find.byType(Vo2ProgressCard),
                    matching: find.byType(Material),
                  )
                  .first,
            )
            .color!;
        final colors = b == Brightness.light
            ? RamuriColors.light
            : RamuriColors.night;
        expect(bg, colors.panel);
        double lum(Color c) => c.computeLuminance();
        double ratio(Color a, Color c) {
          final hi = lum(a) > lum(c) ? lum(a) : lum(c);
          final lo = lum(a) > lum(c) ? lum(c) : lum(a);
          return (hi + 0.05) / (lo + 0.05);
        }

        final hero =
            tester.widget<Text>(k('progress_vo2')).textSpan! as TextSpan;
        final heroColor = (hero.children!.first as TextSpan).style!.color!;
        final unitColor = (hero.children!.last as TextSpan).style!.color!;
        final basis = tester
            .widget<Text>(k('progress_vo2_basis'))
            .style!
            .color!;
        for (final (name, fg) in [
          ('hero', heroColor),
          ('Einheit', unitColor),
          ('Stufenzeile', basis),
        ]) {
          expect(ratio(fg, bg), greaterThanOrEqualTo(4.5), reason: name);
        }
        // Marke „Schätzung“: Schrift auf Glut.
        expect(find.text('Schätzung'), findsOneWidget);
      });
    }
  });

  group('Kachel aerobe Effizienz (FR-0087, FR-0088)', () {
    for (final (locale, shown, compare) in [
      ('de', '+5,6', 'Letzte 4 Wochen gegenüber den 4 Wochen davor'),
      ('en', '+5.6', 'Last 4 weeks compared with the 4 weeks before'),
    ]) {
      testWidgets('$locale: 5,56 wird $shown %, Vergleich benannt', (
        tester,
      ) async {
        await pumpCards(
          tester,
          overview(efficiency: stored(aerobicEfficiencyValueKey, 5.56)),
          locale: locale,
        );
        expect(plain(tester, 'progress_efficiency'), '$shown %');
        expect(plain(tester, 'progress_efficiency_compare'), compare);
        // Schätzung gekennzeichnet, Abgrenzung zur VO₂max bleibt (FR-0088).
        expect(
          plain(tester, 'progress_efficiency_note'),
          locale == 'de'
              ? contains('Keine Messung der VO₂max')
              : contains('measurement'),
        );
        expect(
          find.text(locale == 'de' ? 'geschätzt' : 'estimated'),
          findsWidgets,
        );
      });
    }

    testWidgets('negativ mit Vorzeichen, null ohne Plus, Grund statt Zahl', (
      tester,
    ) async {
      await pumpCards(
        tester,
        overview(efficiency: stored(aerobicEfficiencyValueKey, -3.44)),
      );
      expect(plain(tester, 'progress_efficiency'), '-3,4 %');
      await pumpCards(
        tester,
        overview(efficiency: stored(aerobicEfficiencyValueKey, 0.0)),
      );
      expect(plain(tester, 'progress_efficiency'), '0,0 %');
      await pumpCards(
        tester,
        overview(efficiency: stored(aerobicEfficiencyValueKey, null)),
      );
      expect(k('progress_efficiency'), findsNothing);
      expect(plain(tester, 'progress_efficiency_reason'), contains('nicht'));
      await pumpCards(tester, overview());
      expect(
        plain(tester, 'progress_efficiency_reason'),
        'nicht verfügbar (noch kein Wert gespeichert)',
      );
    });
  });

  group('FitnessSection bei Lesefehler', () {
    testWidgets('Hinweis bleibt und keine Zahl erfunden', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: RamuriTheme.light,
          locale: const Locale('de'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: FitnessSection(
                period: null,
                runsInPeriod: 0,
                fitness: FitnessOverview.failed(),
                session: _NoSession(),
                onExplain: null,
              ),
            ),
          ),
        ),
      );
      expect(k('stat_fitness_failed'), findsOneWidget);
      expect(k('stat_vo2_current'), findsOneWidget);
    });
  });
}
