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
  String day = '2026-06-03',
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
        day: day,
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
          // Hero ganzzahlig nach dem Design (FR-0205).
          expect(plain(tester, 'progress_vo2'), '46 ml/kg/min');
          expect(
            plain(tester, 'progress_vo2_basis'),
            locale == 'de'
                ? '9 verwertbare Läufe in den 8 Wochen bis zum Stand · $de'
                : '9 usable runs in the 8 weeks up to the as-of date · $en',
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

    testWidgets('Link zur Erklärung: Tippziel mindestens 48 dp', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpCards(
        tester,
        overview(longTerm: stored(vo2maxLongTermValueKey, 46.04)),
      );
      expect(k('progress_vo2_explain'), findsOneWidget);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      // Bei 411 dp bricht der Text der Testschrift um, und zwei Zeilen
      // ergeben von selbst 48 dp. Breit genug für eine Zeile prüft das Tippziel
      // selbst (Mindesthöhe und Padding des Buttons).
      tester.view.physicalSize = const Size(700, 1400);
      await tester.pumpAndSettle();
      final label = find.descendant(
        of: k('progress_vo2_explain'),
        matching: find.byType(Text),
      );
      expect(
        tester.getSize(label).height,
        lessThan(30),
        reason: 'Text muss einzeilig sein, sonst ist der Test blind',
      );
      expect(
        tester.getSize(k('progress_vo2_explain')).height,
        greaterThanOrEqualTo(48),
      );
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      handle.dispose();
    });

    testWidgets('Zahl 0 verwertbare Läufe im Fenster: eigener Text, kein '
        '„0 Läufe“ neben dem Wert', (tester) async {
      for (final (locale, text) in [
        ('de', 'Keine verwertbaren Läufe in den letzten 8 Wochen'),
        ('en', 'No usable runs in the last 8 weeks'),
      ]) {
        await pumpCards(
          tester,
          overview(
            longTerm: stored(
              vo2maxLongTermValueKey,
              46.04,
              quality: ValueQuality.provisional,
              count: 0,
            ),
            weeks: _weeks,
          ),
          locale: locale,
        );
        expect(plain(tester, 'progress_vo2_basis'), startsWith(text));
        expect(plain(tester, 'progress_vo2_basis'), isNot(contains('0 ')));
      }
    });

    testWidgets('Hero gerundet, Sichten darunter mit einer Stelle', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpCards(
        tester,
        overview(
          longTerm: stored(vo2maxLongTermValueKey, 45.5),
          weeks: const [('2026-05-25', 44.0), ('2026-06-01', 45.5)],
        ),
      );
      expect(plain(tester, 'progress_vo2'), '46 ml/kg/min');
      expect(
        tester.getSemantics(k('progress_vo2_semantics')).label,
        contains('46 ml/kg/min'),
      );
      expect(
        tester.getSemantics(k('progress_vo2_sparkline')).label,
        contains('44,0, 45,5 ml/kg/min'),
      );
      handle.dispose();
    });

    testWidgets('Hero folgt dem angezeigten Wert: 45,46 steht als 45,5 und '
        'oben als 46', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpCards(
        tester,
        overview(
          longTerm: stored(vo2maxLongTermValueKey, 45.46),
          weeks: const [('2026-05-25', 44.0), ('2026-06-01', 45.46)],
        ),
      );
      expect(
        tester.getSemantics(k('progress_vo2_sparkline')).label,
        contains('44,0, 45,5 ml/kg/min'),
      );
      expect(plain(tester, 'progress_vo2'), '46 ml/kg/min');
      handle.dispose();
    });

    testWidgets('Zahl 1 verwertbarer Lauf: Einzahl in de und en', (
      tester,
    ) async {
      for (final (locale, text) in [
        ('de', '1 verwertbarer Lauf in den 8 Wochen bis zum Stand'),
        ('en', '1 usable run in the 8 weeks up to the as-of date'),
      ]) {
        await pumpCards(
          tester,
          overview(
            longTerm: stored(vo2maxLongTermValueKey, 46.04, count: 1),
            weeks: _weeks,
          ),
          locale: locale,
        );
        expect(plain(tester, 'progress_vo2_basis'), startsWith(text));
      }
    });

    for (final (locale, estimate, current, asOf) in [
      ('de', 'Schätzung', 'Aktuelle langfristige VO₂max-Schätzung', 'Stand '),
      ('en', 'estimate', 'Current long-term VO₂max estimate', 'As of '),
    ]) {
      testWidgets('$locale: langfristiger Wert benannt, mit Datum, in Text '
          'und Vorlesetext (FR-0081, CON-0009, FR-0067)', (tester) async {
        final handle = tester.ensureSemantics();
        await pumpCards(
          tester,
          overview(longTerm: stored(vo2maxLongTermValueKey, 46.04)),
          locale: locale,
        );
        expect(plain(tester, 'progress_vo2_current'), current);
        expect(plain(tester, 'progress_vo2_asof'), startsWith(asOf));
        final label = tester.getSemantics(k('progress_vo2_semantics')).label;
        expect(label, startsWith('VO₂max, $estimate: 46 ml/kg/min'));
        expect(label, contains(current));
        expect(label, contains(plain(tester, 'progress_vo2_asof')));
        expect(label, contains('46 ml/kg/min'));
        handle.dispose();
      });
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
      // Reihenfolge der Linie: ältester Wert zuerst (Anstieg bleibt Anstieg).
      expect(
        tester.widget<RamuriSparkline>(k('progress_vo2_sparkline')).values,
        [44.0, 46.04],
      );
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
      expect(plain(tester, 'progress_efficiency'), '\u22123,4 %');
      // Rundet auf 0,0: weder „-0,0“ noch „+0,0“.
      for (final v in [-0.04, 0.04]) {
        await pumpCards(
          tester,
          overview(efficiency: stored(aerobicEfficiencyValueKey, v)),
        );
        expect(plain(tester, 'progress_efficiency'), '0,0 %', reason: '$v');
      }
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
      // Lesefehler ist nicht „noch kein Wert gespeichert“.
      await pumpCards(tester, overview(failed: true));
      expect(
        plain(tester, 'progress_efficiency_reason'),
        'Die Fitnesswerte konnten nicht gelesen werden.',
      );
    });

    for (final (locale, estimated, asOf) in [
      ('de', 'geschätzt', 'Stand '),
      ('en', 'estimated', 'As of '),
    ]) {
      testWidgets('$locale: Vorlesetext nennt Schätzung und Stand (CON-0009)', (
        tester,
      ) async {
        final handle = tester.ensureSemantics();
        await pumpCards(
          tester,
          overview(efficiency: stored(aerobicEfficiencyValueKey, 5.56)),
          locale: locale,
        );
        final label = tester
            .getSemantics(k('progress_efficiency_compare'))
            .label;
        expect(label, contains(estimated));
        expect(label, contains(asOf));
        expect(label, contains(locale == 'de' ? '+5,6 %' : '+5.6 %'));
        handle.dispose();
      });
    }
  });

  for (final (locale, expected) in [
    ('de', 'Stand Mo., 3. Juni 2024'),
    ('en', 'As of Mon, Jun 3, 2024'),
  ]) {
    testWidgets('$locale: Stand aus dem Vorjahr nennt das Jahr auf Karte und '
        'Effizienzkachel (FR-0059)', (tester) async {
      await pumpCards(
        tester,
        overview(
          longTerm: stored(vo2maxLongTermValueKey, 46.04),
          efficiency: stored(aerobicEfficiencyValueKey, 5.56),
          day: '2024-06-03',
        ),
        locale: locale,
      );
      expect(plain(tester, 'progress_vo2_asof'), expected);
      expect(find.textContaining(expected), findsWidgets);
      expect(
        find.descendant(
          of: find.byType(EfficiencyCard),
          matching: find.textContaining(expected),
        ),
        findsWidgets,
      );
    });
  }

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
