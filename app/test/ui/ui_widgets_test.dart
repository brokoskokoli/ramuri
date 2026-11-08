import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/l10n/app_localizations.dart';
import 'package:running_app/ui/ui.dart';

const modes = [ThemeMode.light, ThemeMode.dark];

RamuriColors colorsOf(ThemeMode mode) =>
    mode == ThemeMode.dark ? RamuriColors.night : RamuriColors.light;

Future<void> pumpUi(
  WidgetTester tester,
  Widget child, {
  required ThemeMode mode,
  Locale locale = const Locale('de'),
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: RamuriTheme.light,
      darkTheme: RamuriTheme.dark,
      themeMode: mode,
      locale: locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Align(alignment: Alignment.topLeft, child: child),
      ),
    ),
  );
}

Color? materialColor(WidgetTester tester, Finder within) => tester
    .widget<Material>(
      find.descendant(of: within, matching: find.byType(Material)).first,
    )
    .color;

void expectTarget(WidgetTester tester, Finder finder, {String? reason}) {
  final size = tester.getSize(finder);
  expect(size.height, greaterThanOrEqualTo(48), reason: reason);
  expect(size.width, greaterThanOrEqualTo(48), reason: reason);
}

/// Die Zahl einer Wertkachel (erster Text-Abschnitt mit Inhalt).
TextSpan valueSpan(RichText rich) {
  var span = rich.text as TextSpan;
  while (span.text == null) {
    span = span.children!.first as TextSpan;
  }
  return span;
}

void main() {
  for (final mode in modes) {
    final c = colorsOf(mode);
    group('${mode.name}:', () {
      testWidgets('Karte: Farbe je Ton, Tipp-Fläche mindestens 48 dp', (
        tester,
      ) async {
        final tones = {
          RamuriCardTone.surface: c.surface,
          RamuriCardTone.accent: c.accentPanel,
          RamuriCardTone.panel: c.panel,
        };
        for (final e in tones.entries) {
          await pumpUi(
            tester,
            RamuriCard(
              key: const Key('card'),
              tone: e.key,
              child: const Text('x'),
            ),
            mode: mode,
          );
          expect(
            materialColor(tester, find.byKey(const Key('card'))),
            e.value,
            reason: e.key.name,
          );
        }
        var taps = 0;
        await pumpUi(
          tester,
          RamuriCard(
            key: const Key('card'),
            onTap: () => taps++,
            padding: EdgeInsets.zero,
            child: const SizedBox(width: 10, height: 10),
          ),
          mode: mode,
        );
        expectTarget(tester, find.byKey(const Key('card')));
        await tester.tap(find.byKey(const Key('card')));
        expect(taps, 1);
      });

      testWidgets('Karte: dunkle Karte gibt dem Inhalt das dunkle Theme', (
        tester,
      ) async {
        late RamuriColors inside;
        late Color textColor;
        await pumpUi(
          tester,
          RamuriCard(
            tone: RamuriCardTone.panel,
            child: Builder(
              builder: (context) {
                inside = RamuriColors.of(context);
                textColor = DefaultTextStyle.of(context).style.color!;
                return const Text('x');
              },
            ),
          ),
          mode: mode,
        );
        expect(inside, same(RamuriColors.night));
        expect(textColor, c.onPanel);
      });

      testWidgets('Haupt- und Nebenknopf: 56 dp hoch, antwortet, Farben', (
        tester,
      ) async {
        var primary = 0;
        var secondary = 0;
        await pumpUi(
          tester,
          Row(
            children: [
              RamuriPrimaryButton(
                label: 'Start',
                icon: Icons.play_arrow,
                onPressed: () => primary++,
              ),
              RamuriSecondaryButton(
                label: 'Frei',
                onPressed: () => secondary++,
              ),
            ],
          ),
          mode: mode,
        );
        final p = find.byType(FilledButton);
        final s = find.byType(OutlinedButton);
        expectTarget(tester, p);
        expectTarget(tester, s);
        expect(tester.getSize(p).height, 56);
        expect(tester.getSize(s).height, 56);
        final theme = Theme.of(tester.element(p));
        expect(
          theme.filledButtonTheme.style!.backgroundColor!.resolve({}),
          c.action,
        );
        expect(
          theme.filledButtonTheme.style!.foregroundColor!.resolve({}),
          c.onAction,
        );
        await tester.tap(p);
        await tester.tap(s);
        expect([primary, secondary], [1, 1]);
      });

      testWidgets('Knöpfe ohne Aktion sind deaktiviert', (tester) async {
        await pumpUi(
          tester,
          const RamuriPrimaryButton(label: 'Aus', onPressed: null),
          mode: mode,
        );
        expect(
          tester.widget<FilledButton>(find.byType(FilledButton)).enabled,
          isFalse,
        );
      });

      testWidgets('Umschalter: Abschnitte mindestens 48 dp, Wahl und Zustand', (
        tester,
      ) async {
        var value = 'werte';
        await pumpUi(
          tester,
          StatefulBuilder(
            builder: (context, setState) => RamuriSegmentedToggle<String>(
              semanticLabel: 'Ansicht',
              selected: value,
              onChanged: (v) => setState(() => value = v),
              segments: const [
                RamuriSegment(value: 'werte', label: 'Werte'),
                RamuriSegment(value: 'karte', label: 'Karte'),
              ],
            ),
          ),
          mode: mode,
        );
        for (final label in ['Werte', 'Karte']) {
          expectTarget(
            tester,
            find.ancestor(of: find.text(label), matching: find.byType(InkWell)),
            reason: label,
          );
        }
        expect(
          tester.getSemantics(find.text('Werte')),
          isSemantics(
            label: 'Werte',
            isButton: true,
            isSelected: true,
            hasSelectedState: true,
            isInMutuallyExclusiveGroup: true,
            hasTapAction: true,
          ),
        );
        await tester.tap(find.text('Karte'));
        await tester.pump();
        expect(value, 'karte');
        final selectedText = tester.widget<Text>(find.text('Karte'));
        expect(selectedText.style!.color, c.action);
      });

      testWidgets('Chip: mindestens 48 dp, gewählt getönt, antwortet', (
        tester,
      ) async {
        var taps = 0;
        await pumpUi(
          tester,
          Column(
            children: [
              RamuriChip(
                key: const Key('on'),
                label: 'Woche',
                selected: true,
                onPressed: () => taps++,
              ),
              const RamuriChip(
                key: Key('off'),
                label: 'Monat',
                selected: false,
                onPressed: null,
              ),
            ],
          ),
          mode: mode,
        );
        expectTarget(tester, find.byKey(const Key('on')));
        expectTarget(tester, find.byKey(const Key('off')));
        Color? fill(String key) =>
            (tester
                        .widget<DecoratedBox>(
                          find
                              .descendant(
                                of: find.byKey(Key(key)),
                                matching: find.byType(DecoratedBox),
                              )
                              .first,
                        )
                        .decoration
                    as BoxDecoration)
                .color;
        expect(fill('on'), c.tint);
        expect(fill('off'), c.surface);
        await tester.tap(find.byKey(const Key('on')));
        expect(taps, 1);
      });

      testWidgets('Glutpunkt: Farbe, Größe, ohne Semantik', (tester) async {
        await pumpUi(tester, const EmberDot(), mode: mode);
        final box = tester.widget<DecoratedBox>(
          find
              .descendant(
                of: find.byType(EmberDot),
                matching: find.byType(DecoratedBox),
              )
              .first,
        );
        expect((box.decoration as BoxDecoration).color, c.emberDot);
        expect(tester.getSize(find.byType(EmberDot)), const Size(7, 7));
      });

      testWidgets('Geschätzt: Text aus der Lokalisierung, Punkt davor', (
        tester,
      ) async {
        await pumpUi(tester, const EstimatedMark(), mode: mode);
        expect(find.text('geschätzt'), findsOneWidget);
        expect(find.byType(EmberDot), findsOneWidget);
        expect(
          tester.widget<Text>(find.text('geschätzt')).style!.color,
          c.textMuted,
        );
        await pumpUi(
          tester,
          const EstimatedMark(),
          mode: mode,
          locale: const Locale('en'),
        );
        expect(find.text('estimated'), findsOneWidget);
      });

      testWidgets(
        'Wertkachel: Zahl in Sora tabellarisch, Einheit, Beschriftung',
        (tester) async {
          await pumpUi(
            tester,
            const RamuriValueTile(label: 'Ø Pace', value: '5:44', unit: '/km'),
            mode: mode,
          );
          expect(find.text('Ø Pace'), findsOneWidget);
          final rich = tester.widget<RichText>(
            find.descendant(
              of: find.byType(RamuriValueTile),
              matching: find.byWidgetPredicate(
                (w) => w is RichText && w.text.toPlainText() == '5:44 /km',
              ),
            ),
          );
          final value = valueSpan(rich);
          expect(value.text, '5:44');
          expect(value.style!.fontFamily, 'Sora');
          expect(value.style!.fontSize, 22);
          expect(value.style!.color, c.text);
          expect(
            value.style!.fontFeatures,
            contains(const FontFeature.tabularFigures()),
          );
          expect(find.byType(EstimatedMark), findsNothing);
          expect(
            tester.getSize(find.byType(RamuriValueTile)).height,
            greaterThan(40),
          );
        },
      );

      testWidgets('Wertkachel: geschätzt zeigt Kennzeichnung, groß 28', (
        tester,
      ) async {
        await pumpUi(
          tester,
          const RamuriValueTile(
            label: 'VO₂max',
            value: '46',
            estimated: true,
            size: RamuriValueSize.large,
          ),
          mode: mode,
        );
        expect(find.byType(EstimatedMark), findsOneWidget);
        expect(find.text('geschätzt'), findsOneWidget);
        final rich = tester.widget<RichText>(
          find.byWidgetPredicate(
            (w) => w is RichText && w.text.toPlainText() == '46',
          ),
        );
        expect(valueSpan(rich).style!.fontSize, 28);
      });

      testWidgets('Wertkachel auf dunkler Karte: Panel-Farben', (tester) async {
        await pumpUi(
          tester,
          const RamuriValueTile(
            label: 'Läufe',
            value: '6',
            tone: RamuriCardTone.panel,
          ),
          mode: mode,
        );
        final label = tester.widget<Text>(find.text('Läufe'));
        expect(label.style!.color, RamuriColors.night.textMuted);
        final rich = tester.widget<RichText>(
          find.byWidgetPredicate(
            (w) => w is RichText && w.text.toPlainText() == '6',
          ),
        );
        expect(valueSpan(rich).style!.color, RamuriColors.night.text);
      });

      testWidgets('Zonenbalken: Breiten nach Anteil, Farben, Beschreibung', (
        tester,
      ) async {
        await pumpUi(
          tester,
          const SizedBox(
            width: 400,
            child: ZoneBar(
              semanticLabel: 'Zone 1: 8 Minuten, Zone 2: 24 Minuten',
              segments: [
                ZoneBarSegment(zone: 1, weight: 8),
                ZoneBarSegment(zone: 2, weight: 24),
                ZoneBarSegment(zone: 4, weight: 0),
                ZoneBarSegment(zone: 3, weight: 8),
              ],
            ),
          ),
          mode: mode,
        );
        final boxes = find.descendant(
          of: find.byType(ZoneBar),
          matching: find.byType(DecoratedBox),
        );
        expect(boxes, findsNWidgets(3), reason: 'Zone ohne Anteil entfällt');
        final widths = [
          for (var i = 0; i < 3; i++) tester.getSize(boxes.at(i)).width,
        ];
        // 400 - 2 Lücken à 3 = 394, verteilt 8 : 24 : 8.
        expect(widths[1] / widths[0], closeTo(3, 0.01));
        expect(widths[2], closeTo(widths[0], 0.01));
        expect(widths.reduce((a, b) => a + b), closeTo(394, 0.01));
        expect(tester.getSize(boxes.first).height, 14);
        final colors = [
          for (var i = 0; i < 3; i++)
            ((tester.widget<DecoratedBox>(boxes.at(i))).decoration
                    as BoxDecoration)
                .color,
        ];
        expect(colors, [c.zone1, c.zone2, c.zone3]);
        expect(
          find.bySemanticsLabel('Zone 1: 8 Minuten, Zone 2: 24 Minuten'),
          findsOneWidget,
        );
      });

      testWidgets(
        'Abschnittsüberschrift: Kopfzeile, Eyebrow in Großbuchstaben',
        (tester) async {
          await pumpUi(
            tester,
            const Column(
              children: [
                SectionHeading('Zeit in Zonen', trailing: Text('mehr')),
                SectionHeading('Heute geplant', eyebrow: true),
              ],
            ),
            mode: mode,
          );
          expect(find.text('Zeit in Zonen'), findsOneWidget);
          expect(find.text('mehr'), findsOneWidget);
          expect(find.text('HEUTE GEPLANT'), findsOneWidget);
          final heading = tester.widget<Text>(find.text('Zeit in Zonen'));
          expect(heading.style!.fontSize, 15);
          expect(heading.style!.color, c.text);
          final eyebrow = tester.widget<Text>(find.text('HEUTE GEPLANT'));
          expect(eyebrow.style!.color, c.accent);
          expect(
            tester.getSemantics(find.text('Zeit in Zonen')),
            isSemantics(label: 'Zeit in Zonen', isHeader: true),
          );
        },
      );
    });
  }

  testWidgets('Dunkel-Fläche: dunkles Theme und Grund auch im hellen Modus', (
    tester,
  ) async {
    late RamuriColors inside;
    late Brightness brightness;
    await pumpUi(
      tester,
      SizedBox(
        width: 100,
        height: 100,
        child: RamuriDarkScope(
          key: const Key('scope'),
          child: Builder(
            builder: (context) {
              inside = RamuriColors.of(context);
              brightness = Theme.of(context).brightness;
              return const SizedBox.expand();
            },
          ),
        ),
      ),
      mode: ThemeMode.light,
    );
    expect(inside, same(RamuriColors.night));
    expect(brightness, Brightness.dark);
    expect(
      materialColor(tester, find.byKey(const Key('scope'))),
      RamuriColors.night.background,
    );
  });

  testWidgets('App-Theme: Systemeinstellung bestimmt hell oder dunkel', (
    tester,
  ) async {
    for (final b in Brightness.values) {
      tester.platformDispatcher.platformBrightnessTestValue = b;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await pumpUi(
        tester,
        Builder(builder: (context) => Text(Theme.of(context).brightness.name)),
        mode: ThemeMode.system,
      );
      await tester.pumpAndSettle(); // Themewechsel läuft animiert
      expect(find.text(b.name), findsOneWidget);
    }
  });

  testWidgets(
    'Wochenstreifen: Heute mit Lauf bleibt an der Beschriftung kenntlich',
    (tester) async {
      for (final mode in modes) {
        await pumpUi(
          tester,
          const RamuriWeekStrip(
            days: [
              RamuriWeekDay(
                label: 'Mo',
                semanticLabel: 'a',
                done: true,
                today: true,
              ),
              RamuriWeekDay(
                label: 'Di',
                semanticLabel: 'b',
                done: false,
                today: true,
              ),
              RamuriWeekDay(label: 'Mi', semanticLabel: 'c', done: false),
            ],
          ),
          mode: mode,
        );
        await tester.pumpAndSettle(); // Themewechsel läuft animiert
        final c = colorsOf(mode);
        Color? colorOf(String t) =>
            tester.widget<Text>(find.text(t)).style?.color;
        expect(find.byKey(const Key('week_dot_done')), findsOneWidget);
        expect(find.byKey(const Key('week_dot_today')), findsOneWidget);
        expect(colorOf('Mo'), c.text);
        expect(colorOf('Di'), c.text);
        expect(colorOf('Mi'), isNot(c.text));
      }
    },
  );
}
