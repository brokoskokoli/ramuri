import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Tristate;

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/statistics/fitness_section.dart'
    show fitnessNumber;
import 'package:running_app/features/statistics/load_card.dart';
import 'package:running_app/features/statistics/load_view_state.dart';
import 'package:running_app/features/statistics/statistics_screen.dart';
import 'package:running_app/l10n/app_localizations.dart';
import 'package:running_app/ui/ui.dart';

import 'history_summary_test.dart' show seedRun, started;
import 'statistics_test.dart' show openStats;

/// Karte „Belastung“ (WP19 C4b): Verlauf ATL/CTL, aktuelle Werte, TSB ohne
/// Wertung, Vorläufigkeit, Kennzeichen, Grundlage, Leerzustand. Keine
/// Bewertung (PAR-072, PAR-174), kein „Fitness“ (FR-0100, FR-0104).

Finder k(String key) => find.byKey(Key(key));

final DateTime _end = DateTime.utc(2030, 3, 1);
DateTime _d(int back) => _end.subtract(Duration(days: back));

TrainingLoadReport report({
  required List<LoadUnit> units,
  bool confirms = false,
  double? factor,
  LoadFactorState? factorState,
  LoadProfile profile = LoadProfile.edwards,
  List<LoadProfileIssue> issues = const [],
  DateTime? today,
}) {
  final series = computeTrainingLoad(
    profile: profile,
    units: units,
    factor: factor,
    confirmsAllRecorded: confirms,
    today: today ?? _end,
  );
  return TrainingLoadReport(
    series: series,
    profile: profile,
    profileIssues: issues,
    factor:
        factorState ??
        LoadFactorState(
          profile: profile,
          value: factor,
          runCount: 25,
          eligibleRuns: 25,
          unavailable: null,
          adoptedDay: null,
          offered: null,
        ),
    today: _end,
    seriesEnd: _end,
    todayEmpty: false,
    calculatedAt: DateTime.utc(2030, 3, 1, 12),
  );
}

/// 60 Tage: Läufe mit TRIMP, ein Nachtrag mit Faktor (umgerechnet), eine
/// unbewertete Einheit, Lücken (leer, ohne Zusage).
TrainingLoadReport mixed() => report(
  factor: 1.2,
  units: [
    for (var i = 0; i < 60; i += 2)
      if (i == 10)
        LoadUnit.manual(day: _d(i), srpePoints: 50)
      else if (i == 20)
        LoadUnit.run(day: _d(i))
      else
        LoadUnit.run(day: _d(i), trimp: 40.0 + i),
  ],
);

TrainingLoadReport settled() => report(
  confirms: true,
  factor: 1.0,
  units: [for (var i = 0; i < 200; i++) LoadUnit.run(day: _d(i), trimp: 60)],
);

Future<void> pump(
  WidgetTester tester,
  Widget child, {
  String locale = 'de',
  Brightness brightness = Brightness.light,
  double width = 411,
  double textScale = 1,
  double height = 1800,
}) async {
  tester.view.physicalSize = Size(width, height);
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
      home: MediaQuery.withClampedTextScaling(
        minScaleFactor: textScale,
        maxScaleFactor: textScale,
        child: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: child,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

String allText(WidgetTester tester) => [
  for (final t in tester.widgetList<Text>(find.byType(Text)))
    t.textSpan?.toPlainText() ?? t.data ?? '',
].join('\n');

/// Wörter, die eine Bewertung, Erholungs-, Risiko- oder Fitnessaussage wären
/// (PAR-072, PAR-174, FR-0100, FR-0101, FR-0104).
final List<RegExp> banned = [
  RegExp(r'fitness|fitter|\bform\b|\bshape\b', caseSensitive: false),
  RegExp(r'zu wenig|zu viel|too little|too much|\bgut\b|\bgood\b'),
  RegExp(r'empfohlen|recommended|optimal|ausgewogen|balanced'),
  RegExp(r'erholt|erholung|recover|rested|ausgeruht|frisch|fresh'),
  RegExp(r'risiko|risk|verletz|injur|überlast|overload|overtrain'),
  RegExp(r'%'),
];

void main() {
  group('Inhalt', () {
    for (final locale in ['de', 'en']) {
      for (final brightness in Brightness.values) {
        testWidgets('$locale ${brightness.name}: Verlauf, Werte, vorläufig, '
            'Kennzeichen, Grundlage', (tester) async {
          await pump(
            tester,
            LoadCardBody(
              initiallyExpanded: true,
              state: LoadViewState.ready(mixed()),
            ),
            locale: locale,
            brightness: brightness,
          );
          final l10n = AppLocalizations.of(tester.element(k('load_card')));
          expect(find.text(l10n.loadTitle), findsOneWidget);
          expect(k('load_chart'), findsOneWidget);
          expect(find.text(l10n.loadAtlLabel), findsOneWidget);
          // Englisch: Kurz- und Langname sind gleich (Anzeige und Grundlage).
          expect(find.text(l10n.loadCtlLabel), findsWidgets);
          expect(find.text(l10n.loadFigCtl), findsWidgets);
          expect(find.text(l10n.loadTsbLabel), findsOneWidget);
          // Frühe Phase: alle drei vorläufig, mit Gründen.
          expect(k('load_atl_provisional'), findsOneWidget);
          expect(k('load_ctl_provisional'), findsOneWidget);
          expect(k('load_tsb_provisional'), findsOneWidget);
          expect(find.text(l10n.loadProvAtlCommitment), findsOneWidget);
          expect(find.text(l10n.loadProvStartup), findsOneWidget);
          expect(find.text(l10n.loadProvCommitment), findsOneWidget);
          // Alle drei Kennzeichen sind in der Legende erkennbar.
          expect(k('load_legend_converted'), findsOneWidget);
          expect(k('load_legend_unrated'), findsOneWidget);
          expect(k('load_legend_empty'), findsOneWidget);
          // Grundlage.
          expect(find.text(l10n.loadProfileEdwards), findsOneWidget);
          expect(k('load_factor'), findsOneWidget);
          expect(find.text(l10n.loadDataNote), findsOneWidget);
          expect(k('load_empty'), findsNothing);
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('keine Bewertung, kein Fitness, keine Prozentzahl '
        '(de und en, alle Zustände)', (tester) async {
      for (final locale in ['de', 'en']) {
        for (final state in [
          LoadViewState.ready(mixed()),
          LoadViewState.ready(settled()),
          LoadViewState.ready(report(units: const [])),
          const LoadViewState.failed(),
          const LoadViewState.loading(),
        ]) {
          await pump(
            tester,
            LoadCardBody(initiallyExpanded: true, state: state),
            locale: locale,
          );
          final text = allText(tester);
          for (final re in banned) {
            expect(re.hasMatch(text), isFalse, reason: '$locale: $re in $text');
          }
        }
      }
    });

    testWidgets('eingeschwungen (126 Tage, Zusage): nichts vorläufig', (
      tester,
    ) async {
      await pump(
        tester,
        LoadCardBody(
          initiallyExpanded: true,
          state: LoadViewState.ready(settled()),
        ),
      );
      expect(k('load_atl'), findsOneWidget);
      expect(k('load_atl_provisional'), findsNothing);
      expect(k('load_ctl_provisional'), findsNothing);
      expect(k('load_tsb_provisional'), findsNothing);
      expect(k('load_provisional_reason'), findsNothing);
      // Keine Kennzeichen, daher keine Legende dazu.
      expect(k('load_legend_unrated'), findsNothing);
      expect(k('load_legend_converted'), findsNothing);
      expect(k('load_legend_empty'), findsNothing);
      // 200 Tage, gezeigt werden zwölf Wochen.
      final chart = tester.widget<LoadChart>(k('load_chart'));
      expect(chart.days, hasLength(LoadCardBody.chartDays));
    });

    testWidgets(
      'Leerzustand: keine Zahl, kein Diagramm, keine Fitnessaussage',
      (tester) async {
        await pump(
          tester,
          LoadCardBody(
            initiallyExpanded: true,
            state: LoadViewState.ready(report(units: const [])),
          ),
        );
        final l10n = AppLocalizations.of(tester.element(k('load_card')));
        expect(find.text(l10n.loadEmpty), findsOneWidget);
        expect(k('load_chart'), findsNothing);
        expect(k('load_atl'), findsNothing);
        expect(k('load_ctl'), findsNothing);
        expect(k('load_tsb'), findsNothing);
        // Die Grundlage bleibt sichtbar; ohne Einheit steht „noch keine“.
        expect(find.text(l10n.loadDataNone), findsOneWidget);
      },
    );

    testWidgets('nur unbewertete Einheiten: wie leer, keine Zahl', (
      tester,
    ) async {
      await pump(
        tester,
        LoadCardBody(
          initiallyExpanded: true,
          state: LoadViewState.ready(
            report(
              units: [
                LoadUnit.run(day: _d(3)),
                LoadUnit.run(day: _d(1)),
              ],
            ),
          ),
        ),
      );
      expect(k('load_empty'), findsOneWidget);
      expect(k('load_atl'), findsNothing);
    });

    for (final locale in ['de', 'en']) {
      testWidgets('$locale: nur unbewertete Einheiten: Leerzustand nennt '
          'Anzahl und Grund, ohne Fitnessaussage (FR-0102)', (tester) async {
        await pump(
          tester,
          LoadCardBody(
            initiallyExpanded: true,
            state: LoadViewState.ready(
              report(
                units: [
                  // Ohne Puls und ohne RPE.
                  LoadUnit.run(day: _d(3)),
                  // RPE da, Faktor fehlt.
                  LoadUnit.manual(day: _d(2), srpePoints: 120),
                  LoadUnit.run(day: _d(1), srpePoints: 90),
                ],
              ),
            ),
          ),
          locale: locale,
        );
        final l10n = AppLocalizations.of(tester.element(k('load_card')));
        final text = tester.widget<Text>(k('load_empty_unrated')).data!;
        expect(
          text,
          [
            l10n.loadEmptyUnrated(3),
            l10n.loadEmptyUnratedNoRpe(1),
            l10n.loadEmptyUnratedNoFactor(2),
          ].join(' '),
        );
        expect(text, contains('3'));
        expect(k('load_atl'), findsNothing);
        for (final b in banned) {
          expect(b.hasMatch(text), isFalse, reason: '$b in "$text"');
        }
      });
    }

    testWidgets('Leerzustand: Einzahl und kein Hinweis ohne unbewertete', (
      tester,
    ) async {
      await pump(
        tester,
        LoadCardBody(
          initiallyExpanded: true,
          state: LoadViewState.ready(report(units: [LoadUnit.run(day: _d(1))])),
        ),
      );
      final l10n = AppLocalizations.of(tester.element(k('load_card')));
      final text = tester.widget<Text>(k('load_empty_unrated')).data!;
      expect(text, startsWith(l10n.loadEmptyUnrated(1)));
      expect(text, contains(l10n.loadEmptyUnratedNoRpe(1)));
      expect(text, isNot(contains(l10n.loadEmptyUnratedNoFactor(1))));
    });

    testWidgets('Leerzustand ohne Einheit: kein Hinweis auf Unbewertete', (
      tester,
    ) async {
      await pump(
        tester,
        LoadCardBody(
          initiallyExpanded: true,
          state: LoadViewState.ready(report(units: const [])),
        ),
      );
      expect(k('load_empty_unrated'), findsNothing);
    });

    // E2E 36: Grund der Vorläufigkeit passt zur Ursache (PAR-088/089/090).
    group('Grund der Vorläufigkeit je Ursache', () {
      List<LoadUnit> daily(int from, int to) => [
        for (var i = from; i <= to; i++) LoadUnit.run(day: _d(i), trimp: 60),
      ];

      Future<AppLocalizations> reasons(
        WidgetTester tester,
        TrainingLoadReport r,
        String locale,
      ) async {
        await pump(
          tester,
          LoadCardBody(initiallyExpanded: true, state: LoadViewState.ready(r)),
          locale: locale,
        );
        return AppLocalizations.of(tester.element(k('load_card')));
      }

      for (final locale in ['de', 'en']) {
        testWidgets('$locale: Anlauf (kurz, mit Zusage): nur Verlauf kurz', (
          tester,
        ) async {
          final l = await reasons(
            tester,
            report(confirms: true, units: daily(0, 10)),
            locale,
          );
          expect(find.text(l.loadProvAtl), findsOneWidget);
          expect(find.text(l.loadProvStartup), findsOneWidget);
          expect(find.text(l.loadProvAtlCommitment), findsNothing);
          expect(find.text(l.loadProvCommitment), findsNothing);
          expect(find.text(l.loadProvMissing), findsNothing);
        });

        testWidgets('$locale: Anlauf ohne Zusage: beide Gründe', (
          tester,
        ) async {
          final l = await reasons(tester, report(units: daily(0, 10)), locale);
          expect(find.text(l.loadProvAtl), findsOneWidget);
          expect(find.text(l.loadProvStartup), findsOneWidget);
          expect(find.text(l.loadProvAtlCommitment), findsOneWidget);
          expect(find.text(l.loadProvCommitment), findsOneWidget);
        });

        testWidgets('$locale: lange Historie ohne Zusage: nur fehlende Zusage, '
            'nicht "Verlauf kurz"', (tester) async {
          final l = await reasons(tester, report(units: daily(0, 300)), locale);
          expect(find.text(l.loadProvAtlCommitment), findsOneWidget);
          expect(find.text(l.loadProvCommitment), findsOneWidget);
          expect(find.text(l.loadProvAtl), findsNothing);
          expect(find.text(l.loadProvStartup), findsNothing);
          expect(find.text(l.loadProvMissing), findsNothing);
        });

        testWidgets('$locale: lange Historie mit Zusage, viele unbewertet '
            '(Rückfall PAR-090): nur CTL/TSB, ATL nicht', (tester) async {
          final units = [
            for (var i = 0; i <= 300; i++)
              if (i < 20 && i.isEven)
                LoadUnit.run(day: _d(i))
              else
                LoadUnit.run(day: _d(i), trimp: 60),
          ];
          final l = await reasons(
            tester,
            report(confirms: true, units: units),
            locale,
          );
          expect(find.text(l.loadProvMissing), findsOneWidget);
          expect(find.text(l.loadProvAtl), findsNothing);
          expect(find.text(l.loadProvAtlCommitment), findsNothing);
          expect(find.text(l.loadProvStartup), findsNothing);
          expect(find.text(l.loadProvCommitment), findsNothing);
        });
      }
    });

    // E2E 36: "Pkt. Punkte" und doppelter Punkt nach dem abgekürzten Datum.
    for (final locale in ['de', 'en']) {
      testWidgets('$locale: Diagramm-Semantik als fertiger Text', (
        tester,
      ) async {
        final handle = tester.ensureSemantics();
        final r = settled();
        await pump(
          tester,
          LoadCardBody(initiallyExpanded: true, state: LoadViewState.ready(r)),
          locale: locale,
        );
        final label = tester.getSemantics(k('load_chart')).label;
        final cur = r.series.summary.current!;
        final german = locale == 'de';
        final end = MaterialLocalizations.of(tester.element(k('load_card')))
            .formatMediumDate(DateTime.utc(2030, 3, 1));
        final atl = fitnessNumber(german, cur.atl!);
        final ctl = fitnessNumber(german, cur.ctl!);
        expect(
          label,
          german
              ? 'Verlauf der kurzfristigen Belastung und des langfristigen '
                    'Belastungsniveaus, 84 Tage bis $end; zuletzt $atl und '
                    '$ctl Punkte.'
              : 'Course of the short-term load and the long-term load '
                    'level, 84 days up to $end; latest $atl and $ctl points.',
        );
        expect(label, isNot(contains('Pkt')));
        expect(label, isNot(contains('..')));
        expect(label, isNot(contains('pts')));
        handle.dispose();
      });
    }

    testWidgets('Faktor: fehlt, wenig gesichert, angewandt, nicht mehr '
        'gestützt, Angebot', (tester) async {
      LoadFactorState fs({
        double? value,
        int runs = 0,
        FactorUnavailableReason? unavailable,
        LoadFactorRecord? offered,
      }) => LoadFactorState(
        profile: LoadProfile.edwards,
        value: value,
        runCount: runs,
        eligibleRuns: runs,
        unavailable: unavailable,
        adoptedDay: null,
        offered: offered,
      );
      final units = [LoadUnit.run(day: _d(1), trimp: 50)];
      final cases = <(LoadFactorState, String Function(AppLocalizations))>[
        (fs(), (l) => l.loadFactorMissing),
        (fs(value: 1.234, runs: 12), (l) => l.loadFactorTentative('1,23', 12)),
        (fs(value: 1.234, runs: 20), (l) => l.loadFactorSecured('1,23', 20)),
        (
          fs(
            value: 1.234,
            runs: 20,
            unavailable: FactorUnavailableReason.tooFewRuns,
          ),
          (l) => l.loadFactorUnsupported('1,23'),
        ),
      ];
      for (final (state, expected) in cases) {
        await pump(
          tester,
          LoadCardBody(
            initiallyExpanded: true,
            state: LoadViewState.ready(
              report(units: units, factorState: state),
            ),
          ),
        );
        final l10n = AppLocalizations.of(tester.element(k('load_card')));
        expect(find.text(expected(l10n)), findsOneWidget);
        expect(k('load_factor_offered'), findsNothing);
      }
      await pump(
        tester,
        LoadCardBody(
          initiallyExpanded: true,
          state: LoadViewState.ready(
            report(
              units: units,
              factorState: fs(
                value: 1.2,
                runs: 20,
                offered: LoadFactorRecord(
                  profile: LoadProfile.edwards,
                  value: 2.0,
                  runs: 20,
                  day: DateTime.utc(2030, 3, 1),
                ),
              ),
            ),
          ),
        ),
      );
      expect(k('load_factor_offered'), findsOneWidget);
    });

    testWidgets(
      'Profil nicht anwendbar: Grund sichtbar, kein stiller Wechsel',
      (tester) async {
        await pump(
          tester,
          LoadCardBody(
            initiallyExpanded: true,
            state: LoadViewState.ready(
              report(
                units: [LoadUnit.run(day: _d(1), trimp: 50)],
                profile: LoadProfile.banister,
                issues: const [
                  LoadProfileIssue.missingRestingHeartRate,
                  LoadProfileIssue.missingCoefficients,
                ],
              ),
            ),
          ),
        );
        final l10n = AppLocalizations.of(tester.element(k('load_card')));
        expect(
          find.text(
            l10n.loadProfileNotApplicable(
              l10n.loadProfileNameBanister,
              '${l10n.loadIssueRestingHr}, ${l10n.loadIssueCoefficients}',
            ),
          ),
          findsOneWidget,
        );
        expect(find.text(l10n.loadFactorNotApplicable), findsOneWidget);
        expect(find.text(l10n.loadProfileEdwards), findsNothing);
      },
    );

    testWidgets('Banister angewandt: Profil mit Angabe', (tester) async {
      await pump(
        tester,
        LoadCardBody(
          initiallyExpanded: true,
          state: LoadViewState.ready(
            report(
              units: [LoadUnit.run(day: _d(1), trimp: 50)],
              profile: LoadProfile.banister,
            ),
          ),
        ),
      );
      final l10n = AppLocalizations.of(tester.element(k('load_card')));
      expect(find.text(l10n.loadProfileBanister), findsOneWidget);
    });
  });

  group('Fehler und Laden', () {
    testWidgets('Fehler: Text und Wiederholen mit mindestens 48 dp', (
      tester,
    ) async {
      var retried = 0;
      await pump(
        tester,
        LoadCardBody(
          state: const LoadViewState.failed(),
          onRetry: () => retried++,
        ),
      );
      final size = tester.getSize(k('load_retry'));
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
      await tester.tap(k('load_retry'));
      expect(retried, 1);
      expect(k('load_chart'), findsNothing);
    });

    testWidgets('Laden: Text, keine Zahl', (tester) async {
      await pump(tester, const LoadCardBody(state: LoadViewState.loading()));
      expect(k('load_loading'), findsOneWidget);
      expect(k('load_atl'), findsNothing);
    });
  });

  group('Bedienbarkeit', () {
    testWidgets('Semantik: Diagramm mit Werten, Kennzahl mit „vorläufig“', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pump(tester, LoadCardBody(state: LoadViewState.ready(mixed())));
      final l10n = AppLocalizations.of(tester.element(k('load_card')));
      final series = mixed().series;
      final cur = series.summary.current!;
      expect(
        find.bySemanticsLabel(RegExp('^${RegExp.escape(l10n.loadCtlLabel)}, ')),
        findsOneWidget,
      );
      final ctl = tester.getSemantics(
        find.bySemanticsLabel(RegExp('^${RegExp.escape(l10n.loadCtlLabel)}, ')),
      );
      expect(ctl.label, endsWith(l10n.loadProvisionalMark));
      expect(
        find.bySemanticsLabel(RegExp('^Verlauf der kurzfristigen')),
        findsOneWidget,
      );
      expect(cur.atl, isNotNull);
      // Die Titelzeile ist eine Überschrift.
      expect(
        tester.getSemantics(find.text(l10n.loadTitle)).flagsCollection.isHeader,
        isTrue,
      );
      handle.dispose();
    });

    testWidgets('eingeklappt höchstens 560 dp hoch bei 390 dp Breite', (
      tester,
    ) async {
      // Grenze: Ein Telefon ist rund 844 dp hoch; davon gehen Statuszeile,
      // Kopf und Navigation ab. 560 dp (zwei Drittel) lassen die Karte auf einen Bildschirm
      // passen und daneben ein Stück der Nachbarkarte sehen. Vorher waren es
      // rund 2,5 Bildschirme. Die Testschrift (Ahem) ist breiter als die
      // echte und bricht eher um, die Grenze ist also eher streng.
      for (final (state, locale) in [
        (LoadViewState.ready(mixed()), 'de'),
        (LoadViewState.ready(settled()), 'de'),
        (LoadViewState.ready(mixed()), 'en'),
        (LoadViewState.ready(settled()), 'en'),
      ]) {
        await pump(
          tester,
          LoadCardBody(state: state),
          width: 390,
          height: 844,
          locale: locale,
        );
        final h = tester.getSize(find.byType(RamuriCard)).height;
        expect(h, lessThanOrEqualTo(560), reason: 'Höhe $h');
        expect(k('load_chart'), findsOneWidget);
        expect(k('load_legend'), findsOneWidget);
        expect(k('load_tsb'), findsOneWidget);
        expect(k('load_basis'), findsNothing);
        // FR-0197: das verwendete Profil steht auch eingeklappt da.
        expect(k('load_profile_short'), findsOneWidget);
        expect(
          find.text(locale == 'de' ? 'Edwards-TRIMP' : 'Edwards TRIMP'),
          findsOneWidget,
        );
      }
      final banister = report(
        profile: LoadProfile.banister,
        units: [
          for (var i = 0; i < 60; i += 2) LoadUnit.run(day: _d(i), trimp: 50),
        ],
      );
      await pump(
        tester,
        LoadCardBody(state: LoadViewState.ready(banister)),
        width: 390,
        height: 844,
      );
      expect(find.text('Banister-TRIMP'), findsOneWidget);
    });

    testWidgets('Grundlage: Schalter mit 48 dp und Semantik, klappt auf und '
        'zu, nichts geht verloren', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(
        tester,
        LoadCardBody(state: LoadViewState.ready(mixed())),
        width: 390,
        height: 844,
      );
      final l10n = AppLocalizations.of(tester.element(k('load_card')));
      final size = tester.getSize(k('load_basis_toggle'));
      expect(size.height, greaterThanOrEqualTo(48));
      expect(size.width, greaterThanOrEqualTo(48));
      final sem = tester.getSemantics(k('load_basis_toggle'));
      expect(sem.label, l10n.loadBasisTitle);
      expect(sem.flagsCollection.isButton, isTrue);
      expect(sem.flagsCollection.isExpanded, Tristate.isFalse);
      // Eingeklappt steht nur der kurze Hinweis, nicht die Gründe.
      expect(k('load_hint_provisional'), findsOneWidget);
      expect(k('load_provisional_reason'), findsNothing);
      expect(find.text(l10n.loadDataNote), findsNothing);

      await tester.tap(k('load_basis_toggle'));
      await tester.pump();
      expect(
        tester.getSemantics(k('load_basis_toggle')).flagsCollection.isExpanded,
        Tristate.isTrue,
      );
      expect(k('load_basis'), findsOneWidget);
      for (final t in [
        l10n.loadProvAtlCommitment,
        l10n.loadProvStartup,
        l10n.loadProvCommitment,
        l10n.loadProfileEdwards,
        l10n.loadDataNote,
        l10n.loadAtlLabel,
        l10n.loadCtlLabel,
        l10n.loadTsbLabel,
        l10n.loadFlagConverted,
        l10n.loadFlagUnrated,
        l10n.loadFlagEmpty,
      ]) {
        expect(
          find.text(t),
          t == l10n.loadCtlLabel ? findsWidgets : findsOneWidget,
          reason: t,
        );
      }
      expect(k('load_scale'), findsOneWidget);

      await tester.tap(k('load_basis_toggle'));
      await tester.pump();
      expect(k('load_basis'), findsNothing);
      handle.dispose();
    });

    testWidgets('Legende: Kennzeichen nur, wenn im Zeitraum vorhanden', (
      tester,
    ) async {
      await pump(tester, LoadCardBody(state: LoadViewState.ready(settled())));
      expect(k('load_legend'), findsOneWidget);
      expect(k('load_legend_converted'), findsNothing);
    });

    for (final width in [320.0, 411.0]) {
      testWidgets('große Schrift, aufgeklappt, ${width}px: kein Überlauf', (
        tester,
      ) async {
        await pump(
          tester,
          LoadCardBody(
            state: LoadViewState.ready(mixed()),
            initiallyExpanded: true,
          ),
          width: width,
          textScale: 2,
          locale: 'en',
        );
        expect(tester.takeException(), isNull);
      });
    }

    for (final width in [320.0, 411.0]) {
      testWidgets('große Schrift, ${width}px: kein Überlauf', (tester) async {
        await pump(
          tester,
          LoadCardBody(state: LoadViewState.ready(mixed())),
          width: width,
          textScale: 2,
          locale: 'en',
        );
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('Diagramm', () {
    LoadDay day(
      int i, {
      double? atl,
      double? ctl,
      Set<LoadDayFlag> flags = const {},
    }) => LoadDay(
      day: _d(10 - i),
      load: null,
      atl: atl,
      ctl: ctl,
      tsb: null,
      tsbPercentMean7: null,
      flags: flags,
      atlProvisionalReasons: const {},
      ctlProvisionalReasons: const {},
      unitCount: 0,
      ratedUnits: 0,
      convertedUnits: 0,
      unratedUnits: 0,
    );

    test('eine Skala: Obergrenze aus dem größten Wert beider Linien', () {
      expect(LoadChart.scaleFor([day(0, atl: 12.2, ctl: 80.1)]), 81);
      expect(LoadChart.scaleFor([day(0, atl: 120.4, ctl: 8)]), 121);
      expect(LoadChart.scaleFor([day(0)]), 1);
    });

    test('Linien reißen an Tagen ohne Wert ab', () {
      final days = [
        day(0),
        day(1, atl: 1, ctl: 1),
        day(2, atl: 2, ctl: 2),
        day(3),
        day(4, atl: 3, ctl: 3),
      ];
      expect(LoadChartPainter.runs(days, (d) => d.atl), [
        [1, 2],
        [4],
      ]);
    });

    test('Höhere Werte liegen oben, 0 an der Grundlinie', () {
      final low = LoadChartPainter.yOf(10, 100, 100);
      final high = LoadChartPainter.yOf(90, 100, 100);
      expect(high, lessThan(low));
      expect(LoadChartPainter.yOf(0, 100, 100), greaterThan(low));
    });

    for (final (flag, circles, paths, lines) in [
      (LoadDayFlag.converted, 1, 0, 2),
      (LoadDayFlag.unrated, 0, 1, 2),
      (LoadDayFlag.emptyUnchanged, 0, 0, 3),
    ]) {
      testWidgets('Kennzeichen ${flag.name} hat eine eigene Form', (
        tester,
      ) async {
        await pump(
          tester,
          LoadChart(
            key: const Key('c'),
            scaleMax: 10,
            days: [
              day(0, flags: {flag}),
            ],
          ),
        );
        final box = tester.renderObject(
          find.descendant(of: k('c'), matching: find.byType(CustomPaint)).first,
        );
        // Zwei Gitterlinien, dazu genau das Zeichen dieser Art.
        expect(box, paintsExactlyCountTimes(#drawCircle, circles));
        expect(box, paintsExactlyCountTimes(#drawPath, paths));
        expect(box, paintsExactlyCountTimes(#drawLine, lines));
      });
    }

    testWidgets('keine Farben außerhalb des Themes', (tester) async {
      final src = File('lib/features/statistics/load_card.dart')
          .readAsStringSync();
      expect(RegExp(r'Color\(0x|(?<!Ramuri)Colors\.').hasMatch(src), isFalse);
    });
  });

  group('Texte', () {
    Map<String, String> arb(String locale) {
      final json = jsonDecode(
        File('lib/l10n/app_$locale.arb').readAsStringSync(),
      ) as Map<String, dynamic>;
      return {
        for (final e in json.entries)
          if (!e.key.startsWith('@') &&
              (e.key.startsWith('load') || e.key.startsWith('recalcCauseLoad')))
            e.key: e.value as String,
      };
    }

    final words = [
      RegExp(r'fitness|fitter|\bform\b|\bshape\b', caseSensitive: false),
      RegExp(r'empfohlen|recommended|optimal|ausgewogen|balanced|zu wenig'),
      RegExp(r'erholt|erholung|recover|rested|ausgeruht|frisch|fresh'),
      RegExp(r'risiko|risk|verletz|injur|überlast|overload|overtrain'),
      RegExp(r'ermüd|fatigue|schwelle|threshold|genauigkeit|accura'),
    ];

    test('arb load*/recalcCauseLoad*: keine verbotenen Wörter, de = en', () {
      final de = arb('de');
      final en = arb('en');
      expect(de.keys.toSet(), en.keys.toSet());
      expect(de.keys.where((k) => k.startsWith('load')), isNotEmpty);
      for (final m in [de, en]) {
        m.forEach((key, text) {
          for (final re in words) {
            expect(re.hasMatch(text), isFalse, reason: '$key: $text');
          }
        });
      }
    });

    test('CTL heißt langfristiges Belastungsniveau, nie Fitness (FR-0100)', () {
      // Jeder load*-Text, der CTL benennt (außer dem bloßen Kürzel der Legende),
      // nennt das ausgeschriebene Belastungsniveau.
      final names = {
        'de': RegExp('(Langfristiges|Langfr\\.) Belastungsniveau'),
        'en': RegExp('Long-term load level'),
      };
      for (final lang in ['de', 'en']) {
        final m = arb(lang);
        final ctl = [
          for (final e in m.entries)
            if (e.key.startsWith('load') &&
                !e.key.startsWith('@') &&
                e.value.contains('CTL') &&
                e.value != 'CTL')
              e.key,
        ];
        expect(ctl, containsAll(['loadCtlLabel', 'loadFigCtl']), reason: lang);
        for (final key in ctl) {
          expect(
            names[lang]!.hasMatch(m[key]!),
            isTrue,
            reason: '$lang $key: ${m[key]}',
          );
        }
      }
    });

    test('Hinweis zum Datenstand macht keine Zusage „alles erfasst“', () {
      for (final m in [arb('de'), arb('en')]) {
        final t = m['loadDataNote']!.toLowerCase();
        expect(t.contains('vollständig'), isFalse);
        expect(t.contains('complete'), isFalse);
        expect(t.contains('alles erfasst'), isFalse);
        expect(t.contains('everything is recorded'), isFalse);
      }
    });
  });

  group('Einbau in Fortschritt', () {
    for (final locale in ['de', 'en']) {
      testWidgets('$locale: Karte in der App, Leerzustand ohne Einheit', (
        tester,
      ) async {
        final d = await started(tester, locale: locale);
        await openStats(d, tester);
        await tester.scrollUntilVisible(
          k('load_card'),
          300,
          scrollable: find.descendant(
            of: k('stat_list'),
            matching: find.byType(Scrollable),
          ),
        );
        expect(k('load_card'), findsOneWidget);
        expect(k('load_empty'), findsOneWidget);
        expect(k('load_atl'), findsNothing);
      });
    }

    testWidgets('mit bewertetem Lauf: Verlauf und Werte aus der Datenbank', (
      tester,
    ) async {
      final d = await started(tester);
      d.clock.set(DateTime.utc(2026, 6, 3, 12));
      final run = await seedRun(d.session, DateTime.utc(2026, 6, 2, 8));
      await d.session.values.createOriginals(ValueOwner.run(run), [
        ComputedValue(
          key: trimpRunValueKey,
          value: 55,
          unit: pointsUnit,
          computedAt: DateTime.utc(2026, 6, 2, 9),
          measurementCount: 1,
          sources: const [],
          method: 'edwards-trimp',
          methodVersion: 1,
          parameterVersion: 1,
          quality: ValueQuality.good,
        ),
      ]);
      await openStats(d, tester);
      await tester.scrollUntilVisible(
        k('load_card'),
        300,
        scrollable: find.descendant(
          of: k('stat_list'),
          matching: find.byType(Scrollable),
        ),
      );
      expect(k('load_chart'), findsOneWidget);
      expect(k('load_atl'), findsOneWidget);
      expect(k('load_atl_provisional'), findsOneWidget);
      expect(k('load_empty'), findsNothing);
    });

    testWidgets('Seite ohne Neuberechnung (ältere Tests): keine Karte', (
      tester,
    ) async {
      final d = await started(tester);
      tester.view.physicalSize = const Size(411, 914);
      final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
      nav.push(
        MaterialPageRoute<void>(
          builder: (_) => StatisticsScreen(session: d.session, clock: d.clock),
        ),
      );
      await tester.pumpAndSettle();
      expect(k('progress_title'), findsOneWidget);
      expect(k('load_card'), findsNothing);
    });
  });
}
