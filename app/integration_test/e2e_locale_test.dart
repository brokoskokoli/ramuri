// E2E: ein Durchlauf auf Englisch mit Meilen (NFR-0006). Die Sprache der App
// folgt der Geraetesprache (resolveAppLocale in lib/app.dart); der Test setzt
// sie auf Englisch (localesTestValue, wie bei einer englischen Geraetesprache),
// die Meilen ueber die Einstellungen. Danach: Lauf mit Test-Sensor und dem GPS,
// das tool/ci_e2e.sh per `adb emu geo fix` bewegt, Zusammenfassung mit `mi` und
// `min/mi`, Verlauf und Fortschritt in Meilen, an den geprueften Stellen
// englischer Text aus der Uebersetzung und nicht der deutsche. Am Ende stellt
// der Test Kilometer wieder ein. Synthetische Daten, Ausgabe nur Zaehler.
import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:running_app/features/home/app_shell.dart';
import 'package:running_app/l10n/app_localizations.dart';
import 'package:running_app/ui/value_tile.dart';

import 'support/e2e_support.dart';

const _belt = 'fake-gurt-1';

/// Sichtbarer Text unter [f] (auch Text.rich), ohne Wortverbinder und mit
/// normalem statt geschuetztem Leerzeichen (unbreakable_unit.dart).
String _plain(Finder f) => find
    .descendant(of: f, matching: find.byType(RichText), matchRoot: true)
    .evaluate()
    .map((e) => (e.widget as RichText).text.toPlainText())
    .join(' | ')
    .replaceAll('⁠', '')
    .replaceAll(' ', ' ');

String _plainKey(String key) => _plain(find.byKey(Key(key)));

final _umlaut = RegExp('[äöüÄÖÜß]');

/// Strecke in Meilen, englisches Dezimaltrennzeichen: `0.04 mi`.
final _miles = RegExp(r'^\d+\.\d{2} mi$');

/// Pace in Minuten je Meile: `12:34 min/mi`.
final _pacePerMile = RegExp(r'^\d+:\d{2} min/mi$');

Finder _vertical() => find.byWidgetPredicate(
  (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
);

/// [en] steht an der geprueften Stelle, [de] nirgends auf der Seite (ausser er
/// ist Teil des englischen Textes).
void _english(String where, String en, String de) {
  expect(
    find.textContaining(en, findRichText: true),
    findsWidgets,
    reason: '$where englischer Text',
  );
  if (!en.contains(de)) {
    expect(
      find.textContaining(de, findRichText: true),
      findsNothing,
      reason: '$where kein deutscher Text',
    );
  }
}

/// Gepruefter Text ohne deutsche Sonderzeichen.
void _noUmlaut(String where, String text) =>
    expect(_umlaut.hasMatch(text), isFalse, reason: '$where ohne Umlaut');

AppLocalizations _l10n(WidgetTester t, String key) =>
    AppLocalizations.of(t.element(find.byKey(Key(key))));

/// Waehlt die Einheit in den Einstellungen ueber das Segment mit [label].
Future<void> _setUnit(
  WidgetTester t,
  DistanceUnit unit,
  String Function(AppLocalizations) label,
) async {
  await tapKey(t, 'home_overview');
  await tapKey(t, 'home_settings');
  await waitFor(
    t,
    () => !has('home_settings'),
    'Einstellungen offen (home_settings verdeckt)',
  );
  await t.scrollUntilVisible(
    find.byKey(const Key('settings_unit')),
    200,
    scrollable: _vertical().first,
  );
  await pumpFor(t, const Duration(milliseconds: 300));
  final l10n = _l10n(t, 'settings_unit');
  bool selected() =>
      maybeWidget<SegmentedButton<DistanceUnit>>(
        find.byKey(const Key('settings_unit')),
      )?.selected.contains(unit) ??
      false;
  if (!selected()) {
    await tapUntil(
      t,
      find.descendant(
        of: find.byKey(const Key('settings_unit')),
        matching: find.text(label(l10n)),
      ),
      selected,
      'Einheit waehlen',
    );
  }
  expect(selected(), isTrue, reason: 'Einheit gewaehlt');
  await back(t);
  await back(t);
  await waitFor(t, () => has('home_start_run'), 'Heute');
}

/// Datenstand der App-Huelle (zaehlt nach jeder Datenmeldung hoch).
int _revision() =>
    (find.byType(AppShell, skipOffstage: false).evaluate().first.widget
            as AppShell)
        .changes
        .revision;

/// Schliesst die Zusammenfassung und wartet, bis der Ablauf nach dem Lauf
/// fertig ist (Datenmeldung). Ist heute eine Plan-Einheit offen (Plan aus
/// frueheren Gruppen der Sammlung), zaehlt der freie Lauf ohne Rueckfrage als
/// diese Einheit (PAR-207): „Heute“ zeigt danach „Heute erledigt.“ statt der
/// offenen Einheit.
Future<void> _closeSummary(WidgetTester t) async {
  final before = _revision();
  await tapKey(t, 'run_done_close');
  await waitFor(t, () => _revision() > before, 'Datenmeldung');
  await waitFor(
    t,
    () => has('home_start_run') && !has('home_today_unit'),
    'Heute nach dem Lauf ohne offene Einheit',
  );
  if (has('home_today_done')) log('LOCALE plan_einheit_erledigt');
}

/// Verbindet den Test-Gurt; ist er schon verbunden (bekannt aus frueheren
/// Gruppen der Sammlung), bleibt es dabei.
Future<void> _belted(WidgetTester t) async {
  await tapKey(t, 'home_overview');
  await tapKey(t, 'overview_sensors');
  await tapKey(t, 'sensors_scan');
  await waitFor(t, () => has('sensor_$_belt'), 'Test-Gurt gefunden');
  if (has('sensor_connect_$_belt')) await tapKey(t, 'sensor_connect_$_belt');
  await waitFor(t, () => has('sensor_bpm_$_belt'), 'Test-Gurt verbunden');
  await back(t);
  await back(t);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Englisch und Meilen: Lauf, Zusammenfassung, Verlauf, Fortschritt',
    reportingFailures((t) async {
      step('LOCALE start');
      // Geraetesprache Englisch, unabhaengig von der Sprache des Emulators.
      t.platformDispatcher.localesTestValue = const [Locale('en', 'US')];
      addTearDown(t.platformDispatcher.clearLocalesTestValue);
      final w = buildWorld();
      await startApp(t, w);
      await setupIfShown(t);
      final s = await session(t, w);
      expect(
        Localizations.localeOf(
          t.element(find.byKey(const Key('home_start_run'))),
        ).languageCode,
        'en',
        reason: 'App auf Englisch',
      );

      step('LOCALE meilen');
      await _setUnit(t, DistanceUnit.miles, (l) => l.settingsUnitMi);

      step('LOCALE lauf');
      await _belted(t);
      await startRun(t);
      // Genug Strecke fuer eine Pace (GPS des Emulators, ca. 3 m/s).
      await pumpFor(t, const Duration(seconds: 30));
      await finishRun(t);

      step('LOCALE zusammenfassung');
      await waitFor(
        t,
        () => has('sum_header') && has('run_avg_pace'),
        'Zusammenfassung geladen',
      );
      final en = _l10n(t, 'run_distance');
      final de = lookupAppLocalizations(const Locale('de'));
      final distance = _plainKey('run_distance');
      final paceTile = _plain(
        find.ancestor(
          of: find.byKey(const Key('run_avg_pace')),
          matching: find.byType(RamuriValueTile),
        ),
      );
      log(
        'LOCALE sum distance_len=${distance.length} pace_len=${paceTile.length}',
      );
      expect(_miles.hasMatch(distance), isTrue, reason: 'Strecke in mi');
      expect(
        RegExp(r'^\d+:\d{2}$').hasMatch(_plainKey('run_avg_pace')),
        isTrue,
        reason: 'Pace als Zahl',
      );
      expect(paceTile, contains('min/mi'), reason: 'Pace in min/mi');
      expect(paceTile, isNot(contains('min/km')), reason: 'Pace nicht in km');
      _english('Pace', en.summaryAvgPace, de.summaryAvgPace);
      _english('Bewegungszeit', en.runMovingTime, de.runMovingTime);
      _english('Gesamtzeit', en.sumTotalTime, de.sumTotalTime);
      _english('Gespeichert', en.runDoneSaved, de.runDoneSaved);
      _noUmlaut('Strecke', distance);
      _noUmlaut('Pace', paceTile);
      await shot(t, 'locale_zusammenfassung');
      await _closeSummary(t);

      step('LOCALE verlauf');
      final id = (await t.runAsync(() async {
        final runs = await s.runs.list();
        return runs.map((r) => r.id).reduce((a, b) => a > b ? a : b);
      }))!;
      await tapKey(t, 'home_history');
      await waitFor(t, () => has('history_title'), 'Verlauf');
      await t.scrollUntilVisible(
        find.byKey(Key('history_pace_$id')),
        300,
        scrollable: _vertical().first,
      );
      await pumpFor(t, const Duration(milliseconds: 300));
      final hDistance = _plainKey('history_distance_$id');
      final hPace = _plainKey('history_pace_$id');
      expect(_miles.hasMatch(hDistance), isTrue, reason: 'Verlauf Strecke mi');
      expect(_pacePerMile.hasMatch(hPace), isTrue, reason: 'Verlauf min/mi');
      _noUmlaut('Verlauf Strecke', hDistance);
      _noUmlaut('Verlauf Pace', hPace);
      await t.scrollUntilVisible(
        find.byKey(const Key('history_title')),
        -300,
        scrollable: _vertical().first,
      );
      expect(_plainKey('history_title'), en.histTitle, reason: 'Titel');
      _english('Verlauf Titel', en.histTitle, de.histTitle);
      await shot(t, 'locale_verlauf');

      step('LOCALE fortschritt');
      await tapKey(t, 'home_statistics');
      await waitFor(t, () => has('progress_week_title'), 'Fortschritt');
      expect(
        _plainKey('progress_week_title'),
        en.progressWeekTitleMi,
        reason: 'Wochentitel in Meilen',
      );
      _english('Wochentitel', en.progressWeekTitleMi, de.progressWeekTitleMi);
      _english('Zeitraum', en.progressLast8, de.progressLast8);
      _noUmlaut('Wochenfuss', _plainKey('progress_week_footer'));
      // Die Seite baut alles auf einmal (SingleChildScrollView).
      await t.ensureVisible(find.byKey(const Key('stat_avg_pace_value')));
      await pumpFor(t, const Duration(milliseconds: 300));
      final sDistance = _plainKey('stat_distance_value');
      final sPace = _plainKey('stat_avg_pace_value');
      expect(_miles.hasMatch(sDistance), isTrue, reason: 'Fortschritt mi');
      expect(
        _pacePerMile.hasMatch(sPace),
        isTrue,
        reason: 'Fortschritt min/mi',
      );
      _english('Strecke', en.runDistance, de.runDistance);
      _noUmlaut('Fortschritt Strecke', sDistance);
      _noUmlaut('Fortschritt Pace', sPace);
      await shot(t, 'locale_fortschritt');

      step('LOCALE kilometer_zurueck');
      // Folgende Laeufe der Sammlung und Stufen erwarten Kilometer.
      await tapKey(t, 'home_today');
      await waitFor(t, () => has('home_start_run'), 'Heute');
      await _setUnit(t, DistanceUnit.kilometers, (l) => l.settingsUnitKm);
    }),
    timeout: const Timeout(Duration(minutes: 6)),
  );
}
