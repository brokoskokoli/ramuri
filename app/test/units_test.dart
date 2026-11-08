import 'package:core/core.dart';
import 'package:core/testing/contract_samples.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/settings/app_settings.dart';
import 'package:running_app/features/settings/unit_format.dart';
import 'package:running_app/l10n/app_localizations.dart';

import 'app_harness.dart';

/// Alle gespeicherten Rohdaten, Läufe und das Profil als Text.
Future<String> snapshot(StorageSession s) async {
  final b = StringBuffer();
  for (final r in await s.runs.list()) {
    b.writeln(describeRun(r));
    final raw = await s.rawData.read(r.id);
    for (final p in raw.positions) {
      b.writeln(
        'P ${p.id} ${p.value.time.microsecondsSinceEpoch} '
        '${p.value.latitude} ${p.value.longitude} ${p.value.accuracyMeters}',
      );
    }
    for (final h in raw.heartRates) {
      b.writeln('H ${h.id} ${h.value.bpm}');
    }
    for (final a in raw.altitudes) {
      b.writeln('A ${a.id} ${a.value.meters}');
    }
    for (final st in raw.steps) {
      b.writeln('S ${st.id} ${st.value.count}');
    }
  }
  final p = await s.profile.read();
  b.writeln(
    'profile ${p.birthYear} ${p.bodyWeightKg} ${p.bodyHeightMeters} '
    '${p.restingHeartRateBpm} ${p.maxHeartRateBpm} ${p.weeklyRunMinutes} '
    '${p.trainingDaysMask} ${p.usualTrainingMinutes}',
  );
  return b.toString();
}

/// Seite, die per normalem Navigator.push geöffnet wird und die Einheit liest.
class _ProbePage extends StatelessWidget {
  const _ProbePage();

  @override
  Widget build(BuildContext context) {
    final f = AppSettingsScope.formatterOf(context);
    return Scaffold(
      body: Text(
        'probe ${f.distance(5000)} ${f.pace(330)} '
        '${AppLocalizations.of(context).unitMiles}',
      ),
    );
  }
}

void main() {
  testWidgets('Meilen ändern gespeicherte Rohdaten nicht (NFR-0006)', (
    tester,
  ) async {
    final d = Device();
    await d.start(tester, const Locale('en'));
    await d.skipSetup(tester);

    final run = await d.session.runs.create(startedAt: d.clock.now());
    await d.session.rawData.append(run.id, sampleBatch());
    await d.session.profile.save(
      const ProfileRecord(birthYear: 1986, bodyHeightMeters: 1.75),
    );
    final before = await snapshot(d.session);
    expect(before, contains('52.5'));

    await openOverview(tester);

    await tester.tap(find.byKey(const Key('home_settings')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Miles'));
    await tester.pumpAndSettle();

    // Nur die Einstellung hat sich geändert ...
    expect(await d.session.settings.get(SettingKeys.distanceUnit), 'mi');
    // ... die Rohdaten nicht.
    expect(await snapshot(d.session), before);

    // Zurück auf Kilometer: wieder unverändert.
    await tester.tap(find.text('Kilometers'));
    await tester.pumpAndSettle();
    expect(await d.session.settings.get(SettingKeys.distanceUnit), 'km');
    expect(await snapshot(d.session), before);
  });

  testWidgets('gewählte Einheit bleibt nach Neustart erhalten', (tester) async {
    final d = Device();
    await d.start(tester, const Locale('de'));
    await d.skipSetup(tester);
    await openOverview(tester);
    await tester.tap(find.byKey(const Key('home_settings')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Meilen'));
    await tester.pumpAndSettle();
    await d.stop(tester);
    await d.start(tester, const Locale('de'));
    await openOverview(tester);
    await tester.tap(find.byKey(const Key('home_settings')));
    await tester.pumpAndSettle();
    final button = tester.widget<SegmentedButton<DistanceUnit>>(
      find.byKey(const Key('settings_unit')),
    );
    expect(button.selected, {DistanceUnit.miles});
  });

  testWidgets('Seite per normalem Navigator.push sieht Einheit und Kürzel', (
    tester,
  ) async {
    final d = Device();
    await d.start(tester, const Locale('de'));
    await d.skipSetup(tester);
    await openOverview(tester);
    await tester.tap(find.byKey(const Key('home_settings')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Meilen'));
    await tester.pumpAndSettle();

    final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
    nav.push(MaterialPageRoute<void>(builder: (_) => const _ProbePage()));
    await tester.pumpAndSettle();
    expect(find.text('probe 3,11 mi 8:51 min/mi mi'), findsOneWidget);
  });

  group('UnitFormatter', () {
    const km = UnitFormatter(
      unit: DistanceUnit.kilometers,
      languageCode: 'en',
      distanceLabel: 'km',
      paceLabel: 'min/km',
      elevationLabel: 'm',
    );
    const mi = UnitFormatter(
      unit: DistanceUnit.miles,
      languageCode: 'en',
      distanceLabel: 'mi',
      paceLabel: 'min/mi',
      elevationLabel: 'ft',
    );
    const kmDe = UnitFormatter(
      unit: DistanceUnit.kilometers,
      languageCode: 'de',
      distanceLabel: 'km',
      paceLabel: 'min/km',
      elevationLabel: 'm',
    );

    test(
      'Kürzel kommen von außen (Übersetzung), nicht aus dem Formatierer',
      () {
        const x = UnitFormatter(
          unit: DistanceUnit.kilometers,
          languageCode: 'en',
          distanceLabel: 'XD',
          paceLabel: 'XP',
          elevationLabel: 'XE',
        );
        expect(x.distance(1000), '1.00 XD');
        expect(x.pace(330), '5:30 XP');
      },
    );

    test('Höhe: Meter bei km, Fuß bei Meilen (nur Anzeige)', () {
      expect(km.elevation(120), '120 m');
      expect(mi.elevation(100), '328 ft');
      expect(mi.elevation(null), UnitFormatter.noValue);
    });

    test('Strecke aus Metern', () {
      expect(km.distance(5230), '5.23 km');
      expect(kmDe.distance(5230), '5,23 km');
      expect(mi.distance(1609.344), '1.00 mi');
      expect(mi.distance(5000), '3.11 mi');
      expect(km.distance(0), '0.00 km');
    });

    test('Pace aus Sekunden je Kilometer', () {
      expect(km.pace(330), '5:30 min/km');
      expect(mi.pace(330), '8:51 min/mi');
      expect(km.pace(359.6), '6:00 min/km'); // Rundung mit Übertrag
      expect(km.pace(305), '5:05 min/km'); // führende Null
    });

    test('ohne Wert: Strich', () {
      for (final f in [km, mi]) {
        expect(f.distance(null), '–');
        expect(f.distance(double.nan), '–');
        expect(f.distance(-1), '–');
        expect(f.pace(null), '–');
        expect(f.pace(0), '–');
        expect(f.pace(double.infinity), '–');
      }
    });
  });
}
