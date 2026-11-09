import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/profile/profile_screen.dart';
import 'package:running_app/features/recalculation/recalculation_controller.dart';
import 'package:running_app/l10n/app_localizations.dart';
import 'package:running_app/ui/ui.dart';

import 'app_harness.dart';

/// Einstellungen und Profil für das Belastungsprofil (WP19 C4c, FR-0197,
/// FR-0103, FR-0002): Banister nur wählbar, wenn anwendbar (sonst mit Grund),
/// die Wahl wird erst nach der Bestätigung aktiv, Ablehnen lässt sie
/// verfallen, die Koeffizienten-Angabe ist optional und entfernbar.
final _key = Uint8List.fromList(List.filled(32, 7));
const _metersPerDegree = earthRadiusMeters * 3.141592653589793 / 180;

/// Synthetischer Zustand vor dem Start: Profil und zwei berechnete Läufe
/// (30 min, 3 m/s, 150 bpm), falls [runs].
Future<void> _seed(
  Device d, {
  ProfileRecord profile = const ProfileRecord(
    maxHeartRateBpm: 190,
    restingHeartRateBpm: 60,
  ),
  LoadCoefficients? coefficients,
  bool runs = true,
}) async {
  final s = await d.storage.open(_key);
  await s.profile.save(profile);
  if (coefficients != null) {
    await LoadSettings.writeCoefficients(
      s.settings,
      coefficients,
      at: d.clock.now(),
    );
  }
  final calc = ValueCalculationService(session: s, clock: d.clock);
  for (final start in [
    if (runs) ...[DateTime.utc(2026, 5, 10, 8), DateTime.utc(2026, 5, 17, 8)],
  ]) {
    final run = await s.runs.create(startedAt: start);
    final positions = <RawPosition>[];
    final hrs = <RawHeartRate>[];
    for (var i = 0; i <= 1800; i++) {
      final t = start.add(Duration(seconds: i));
      positions.add(
        RawPosition(
          time: t,
          source: 'gps',
          latitude: 10 + i * 3.0 / _metersPerDegree,
          longitude: 20,
          accuracyMeters: 5,
        ),
      );
      hrs.add(
        RawHeartRate(
          time: t,
          source: 'strap',
          bpm: 150,
          contact: SensorContact.good,
        ),
      );
    }
    await s.rawData.append(
      run.id,
      RawBatch(positions: positions, heartRates: hrs, altitudes: const []),
    );
    final end = start.add(const Duration(minutes: 30));
    await s.runs.setState(run.id, RunState.finished, endedAt: end);
    d.clock.set(end.add(const Duration(minutes: 1)));
    await calc.calculateAfterRun(run.id);
  }
  d.clock.set(DateTime.utc(2026, 6, 1));
  await s.close();
}

Future<Device> _start(
  WidgetTester tester, {
  Locale locale = const Locale('de'),
  ProfileRecord profile = const ProfileRecord(
    maxHeartRateBpm: 190,
    restingHeartRateBpm: 60,
  ),
  LoadCoefficients? coefficients,
  bool runs = true,
}) async {
  final d = Device();
  await _seed(d, profile: profile, coefficients: coefficients, runs: runs);
  await d.start(tester, locale);
  await d.skipSetup(tester);
  return d;
}

Future<void> _openSettings(WidgetTester tester) async {
  await openOverview(tester);
  await tester.tap(find.byKey(const Key('home_settings')));
  await tester.pumpAndSettle();
}

Future<void> _openProfile(WidgetTester tester) async {
  await openOverview(tester);
  await tester.tap(find.byKey(const Key('home_profile')));
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, String key) async {
  final f = find.byKey(Key(key));
  await tester.ensureVisible(f);
  await tester.tap(f);
  await tester.pumpAndSettle();
}

/// Wie [_tap], wartet aber auf echte Zeit: ohne die Harness der App läuft das
/// Speichern über echte Futures, die `pumpAndSettle` nicht abwartet.
Future<void> _tapAndWait(WidgetTester tester, String key) async {
  final f = find.byKey(Key(key));
  await tester.ensureVisible(f);
  await tester.tap(f);
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 200)),
  );
  await tester.pumpAndSettle();
}

Future<LoadProfile> _active(Device d) =>
    LoadSettings.activeProfile(d.session.settings);

void main() {
  group('Einstellungen: Banister nur wählbar, wenn anwendbar', () {
    testWidgets('ohne Ruhepuls: deaktiviert mit Grund und Weg zum Profil', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final d = await _start(
        tester,
        profile: const ProfileRecord(maxHeartRateBpm: 190),
        coefficients: LoadCoefficients.male,
      );
      await _openSettings(tester);
      expect(find.text('Banister ist nicht wählbar:'), findsOneWidget);
      expect(find.textContaining('Der Ruhepuls fehlt.'), findsOneWidget);
      expect(find.textContaining('Koeffizienten-Angabe fehlt'), findsNothing);
      // Für Screenreader deaktiviert, Tippen bewirkt nichts (auch keine
      // Meldung "nicht anwendbar": der Versuch findet gar nicht statt).
      expect(
        tester.getSemantics(find.byKey(const Key('load_profile_banister'))),
        isSemantics(hasEnabledState: true, isEnabled: false),
      );
      await tester.tap(find.byKey(const Key('load_profile_banister')));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
      expect(await _active(d), LoadProfile.edwards);
      expect(await LoadSettings.pendingProfile(d.session.settings), isNull);
      expect(find.byKey(const Key('recalc_dialog')), findsNothing);
      // Der Weg dorthin: Profil.
      await _tap(tester, 'load_open_profile');
      expect(find.byKey(const Key('profile_resting')), findsOneWidget);
      handle.dispose();
    });

    testWidgets('ohne Koeffizienten-Angabe: Grund nennt die Angabe', (
      tester,
    ) async {
      await _start(tester);
      await _openSettings(tester);
      expect(find.textContaining('Die Koeffizienten-Angabe fehlt.'), findsOne);
      expect(find.textContaining('Ruhepuls fehlt'), findsNothing);
    });

    testWidgets(
      'Reserve unbrauchbar (HFmax nicht über Ruhepuls): Grund Reserve',
      (tester) async {
        await _start(
          tester,
          profile: const ProfileRecord(
            maxHeartRateBpm: 100,
            restingHeartRateBpm: 80,
          ),
          coefficients: LoadCoefficients.female,
        );
        await _openSettings(tester);
        expect(find.textContaining('keine brauchbare Reserve'), findsOneWidget);
        expect(find.textContaining('Ruhepuls fehlt'), findsNothing);
      },
    );

    testWidgets('anwendbar: kein Grund, Wahl möglich (en)', (tester) async {
      await _start(
        tester,
        locale: const Locale('en'),
        coefficients: LoadCoefficients.male,
      );
      await _openSettings(tester);
      expect(find.byKey(const Key('load_banister_blocked')), findsNothing);
      expect(find.byKey(const Key('load_open_profile')), findsNothing);
      expect(find.text('Active: Edwards'), findsOneWidget);
    });
  });

  group('Wahl, Angebot, Ablehnen', () {
    testWidgets('Wahl bietet an statt sofort zu gelten; Ablehnen lässt sie '
        'verfallen', (tester) async {
      final d = await _start(tester, coefficients: LoadCoefficients.male);
      await _openSettings(tester);
      expect(find.byKey(const Key('load_chosen')), findsNothing);
      await _tap(tester, 'load_profile_banister');
      // Angebot in der Karte der Neuberechnung, aktives Profil unverändert.
      expect(find.byKey(const Key('recalc_cause_loadProfile')), findsOne);
      expect(await _active(d), LoadProfile.edwards);
      expect(
        await LoadSettings.pendingProfile(d.session.settings),
        LoadProfile.banister,
      );
      // Aktiv und gewählt-unbestätigt sind getrennt zu lesen.
      expect(find.text('Aktiv: Edwards'), findsOneWidget);
      expect(
        find.textContaining('Gewählt, noch nicht bestätigt: Banister'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<Icon>(
              find.descendant(
                of: find.byKey(const Key('load_profile_banister')),
                matching: find.byType(Icon),
              ),
            )
            .icon,
        Icons.radio_button_checked,
      );

      await _tap(tester, 'recalc_decline');
      expect(find.byKey(const Key('recalc_dialog')), findsNothing);
      expect(find.byKey(const Key('load_chosen')), findsNothing);
      expect(find.text('Aktiv: Edwards'), findsOneWidget);
      expect(
        tester
            .widget<Icon>(
              find.descendant(
                of: find.byKey(const Key('load_profile_edwards')),
                matching: find.byType(Icon),
              ),
            )
            .icon,
        Icons.radio_button_checked,
      );
      expect(await LoadSettings.pendingProfile(d.session.settings), isNull);
      expect(await _active(d), LoadProfile.edwards);
    });

    testWidgets('Knopf „Zur Bestätigung“ bringt das Angebot ins Bild, 48 dp', (
      tester,
    ) async {
      await _start(tester, coefficients: LoadCoefficients.male);
      tester.view.physicalSize = const Size(390, 520);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await _openSettings(tester);
      expect(find.byKey(const Key('load_show_offer')), findsNothing);
      await _tap(tester, 'load_profile_banister');
      // Das Angebot ist erreichbar, wenn sein Anfang im Bild liegt.
      final offer = find.byKey(const Key('recalc_cause_loadProfile'));
      final viewport = tester.getRect(find.byType(Scaffold));
      bool inView() {
        // Außerhalb gebaut wird die Karte der ListView gar nicht erst.
        if (offer.evaluate().isEmpty) return false;
        final r = tester.getRect(offer);
        // Die Liste beginnt unter der Titelleiste.
        return r.top >= viewport.top + kToolbarHeight &&
            r.top < viewport.bottom;
      }

      // Der Nutzer liest weiter unten: das Angebot ist aus dem Bild.
      await tester.drag(find.byType(ListView), const Offset(0, -3000));
      await tester.pumpAndSettle();
      expect(inView(), isFalse, reason: 'Testaufbau: Angebot liegt außerhalb');
      expect(
        tester.getSize(find.byKey(const Key('load_show_offer'))).height,
        greaterThanOrEqualTo(48),
      );
      await tester.ensureVisible(find.byKey(const Key('load_show_offer')));
      await tester.pumpAndSettle();
      await _tap(tester, 'load_show_offer');
      expect(inView(), isTrue);
    });

    testWidgets('Bestätigen macht die Wahl aktiv', (tester) async {
      final d = await _start(tester, coefficients: LoadCoefficients.female);
      await _openSettings(tester);
      await _tap(tester, 'load_profile_banister');
      await _tap(tester, 'recalc_confirm');
      expect(await _active(d), LoadProfile.banister);
      expect(find.text('Aktiv: Banister'), findsOneWidget);
      expect(find.byKey(const Key('load_chosen')), findsNothing);
    });

    testWidgets('Rückwahl des aktiven Profils nimmt die Wahl und das Angebot '
        'zurück', (tester) async {
      final d = await _start(tester, coefficients: LoadCoefficients.male);
      await _openSettings(tester);
      await _tap(tester, 'load_profile_banister');
      expect(find.byKey(const Key('recalc_dialog')), findsOneWidget);
      await _tap(tester, 'load_profile_edwards');
      expect(find.byKey(const Key('recalc_dialog')), findsNothing);
      expect(find.byKey(const Key('load_chosen')), findsNothing);
      expect(await LoadSettings.pendingProfile(d.session.settings), isNull);
    });

    testWidgets('ohne Läufe gilt die Wahl sofort, ohne Angebot', (
      tester,
    ) async {
      final d = await _start(
        tester,
        coefficients: LoadCoefficients.male,
        runs: false,
      );
      await _openSettings(tester);
      await _tap(tester, 'load_profile_banister');
      expect(find.byKey(const Key('recalc_dialog')), findsNothing);
      expect(await _active(d), LoadProfile.banister);
      expect(find.text('Aktiv: Banister'), findsOneWidget);
    });
  });

  group('Zusage "alles erfasst"', () {
    testWidgets('Schalter speichert, erklärt ohne Wertung und bleibt', (
      tester,
    ) async {
      final d = await _start(tester);
      await _openSettings(tester);
      expect(find.textContaining('trainingsfrei'), findsOneWidget);
      expect(await LoadSettings.allRecorded(d.session.settings), isFalse);
      await _tap(tester, 'load_all_recorded');
      expect(await LoadSettings.allRecorded(d.session.settings), isTrue);
      expect(
        tester
            .widget<SwitchListTile>(find.byKey(const Key('load_all_recorded')))
            .value,
        isTrue,
      );
      await _tap(tester, 'load_all_recorded');
      expect(await LoadSettings.allRecorded(d.session.settings), isFalse);
    });

    testWidgets('48 dp hoch und mit Semantik', (tester) async {
      final handle = tester.ensureSemantics();
      await _start(tester, coefficients: LoadCoefficients.male);
      await _openSettings(tester);
      for (final k in [
        'load_all_recorded',
        'load_profile_edwards',
        'load_profile_banister',
      ]) {
        expect(
          tester.getSize(find.byKey(Key(k))).height,
          greaterThanOrEqualTo(48),
          reason: k,
        );
      }
      expect(
        tester.getSemantics(find.byKey(const Key('load_profile_banister'))),
        matchesSemantics(
          label:
              'Banister. Gewichtet die Zeit nach der Herzfrequenzreserve, '
              'mit Koeffizienten-Angabe.',
          isInMutuallyExclusiveGroup: true,
          hasCheckedState: true,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
        ),
      );
      handle.dispose();
    });
  });

  group('Profil: Koeffizienten-Angabe', () {
    testWidgets('optional, setzbar, entfernbar, mit Erklärung', (tester) async {
      final d = await _start(tester, runs: false);
      await _openProfile(tester);
      expect(find.textContaining('nicht als Geschlechtsangabe'), findsOne);
      for (final k in [
        'profile_coef_male',
        'profile_coef_female',
        'profile_coef_none',
      ]) {
        expect(
          tester.getSize(find.byKey(Key(k))).height,
          greaterThanOrEqualTo(48),
          reason: k,
        );
      }
      // Ohne Angabe speichern: nichts gesetzt, Profil trotzdem gespeichert.
      await _tap(tester, 'profile_save');
      expect(find.text('Profil gespeichert.'), findsOneWidget);
      expect(await LoadSettings.coefficients(d.session.settings), isNull);

      await _tap(tester, 'profile_coef_female');
      await _tap(tester, 'profile_save');
      expect(
        await LoadSettings.coefficients(d.session.settings),
        LoadCoefficients.female,
      );

      await _tap(tester, 'profile_coef_none');
      await _tap(tester, 'profile_save');
      expect(await LoadSettings.coefficients(d.session.settings), isNull);
    });

    testWidgets('bei aktivem Banister gilt die Änderung erst nach der '
        'Bestätigung (Angebot in den Einstellungen)', (tester) async {
      final d = await _start(tester, coefficients: LoadCoefficients.male);
      await _openSettings(tester);
      await _tap(tester, 'load_profile_banister');
      await _tap(tester, 'recalc_confirm');
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await _openProfile(tester);
      expect(find.byKey(const Key('profile_coef_active_note')), findsOne);
      await _tap(tester, 'profile_coef_female');
      await _tap(tester, 'profile_save');
      // Noch die alte Angabe, bis bestätigt.
      expect(
        await LoadSettings.coefficients(d.session.settings),
        LoadCoefficients.male,
      );
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await _openSettings(tester);
      expect(find.byKey(const Key('recalc_cause_loadCoefficients')), findsOne);
      await _tap(tester, 'recalc_confirm');
      expect(
        await LoadSettings.coefficients(d.session.settings),
        LoadCoefficients.female,
      );
    });

    testWidgets('abgewiesene Angabe: alter Chip wieder gewählt, nichts '
        'gespeichert, Banner (Review 3 Befund 4)', (tester) async {
      final d = await _start(tester, coefficients: LoadCoefficients.male);
      await _openSettings(tester);
      await _tap(tester, 'load_profile_banister');
      await _tap(tester, 'recalc_confirm');
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await _openProfile(tester);
      bool selected(String k) =>
          tester.widget<ChoiceChip>(find.byKey(Key(k))).selected;
      expect(selected('profile_coef_male'), isTrue);
      // Ruhepuls entfernen und Angabe ändern im selben Speichern.
      await tester.enterText(find.byKey(const Key('profile_resting')), '');
      await _tap(tester, 'profile_coef_female');
      expect(selected('profile_coef_female'), isTrue);
      await _tap(tester, 'profile_save');
      expect(
        find.text(
          AppLocalizations.of(
            tester.element(find.byKey(const Key('profile_save'))),
          ).loadCoefficientsNotApplied,
        ),
        findsOneWidget,
      );
      expect(selected('profile_coef_male'), isTrue);
      expect(selected('profile_coef_female'), isFalse);
      expect(
        await LoadSettings.coefficients(d.session.settings),
        LoadCoefficients.male,
      );
    });
  });

  group('Karte Belastung lädt neu', () {
    test(
      'jede Änderung der Belastungseinstellungen meldet eine Datenänderung',
      () async {
        final session = await FakeStorage().open(_key);
        await session.profile.save(
          const ProfileRecord(maxHeartRateBpm: 190, restingHeartRateBpm: 60),
        );
        final clock = FakeClock(DateTime.utc(2026, 6, 1, 12));
        var changed = 0;
        final controller = RecalculationController(
          _SpyService(session, clock),
          onDataChanged: () => changed++,
        );
        addTearDown(controller.dispose);
        await controller.setAllRecorded(true);
        expect(changed, 1);
        await controller.requestLoadCoefficients(LoadCoefficients.male);
        expect(changed, 2);
        await controller.requestLoadProfile(LoadProfile.banister);
        expect(changed, 3);
        await controller.loadBasisChanged();
        expect(changed, 4);
      },
    );
  });

  group('Profiländerung ruft loadBasisChanged', () {
    late StorageSession session;
    late FakeClock clock;
    late _SpyService service;
    late RecalculationController controller;

    setUp(() async {
      session = await FakeStorage().open(_key);
      await session.profile.save(
        const ProfileRecord(maxHeartRateBpm: 190, restingHeartRateBpm: 60),
      );
      clock = FakeClock(DateTime.utc(2026, 6, 1, 12));
      service = _SpyService(session, clock);
      controller = RecalculationController(service);
    });

    tearDown(() => controller.dispose());

    Future<void> pumpProfile(WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('de'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: RamuriTheme.light,
          home: ProfileScreen(
            session: session,
            clock: clock,
            recalculation: controller,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('nach Änderung von Ruhepuls oder HFmax', (tester) async {
      await pumpProfile(tester);
      await tester.enterText(find.byKey(const Key('profile_resting')), '55');
      await _tapAndWait(tester, 'profile_save');
      expect(service.basisChanged, 1);
      await tester.enterText(find.byKey(const Key('profile_max')), '185');
      await _tapAndWait(tester, 'profile_save');
      expect(service.basisChanged, 2);
    });

    testWidgets('nicht bei Änderung anderer Felder', (tester) async {
      await pumpProfile(tester);
      await tester.enterText(find.byKey(const Key('profile_weight')), '70');
      await _tapAndWait(tester, 'profile_save');
      expect(find.text('Profil gespeichert.'), findsOneWidget);
      expect(service.basisChanged, 0);
    });
  });
}

class _SpyService extends RecalculationService {
  _SpyService(StorageSession session, Clock clock)
    : super(
        session: session,
        clock: clock,
        calculation: ValueCalculationService(session: session, clock: clock),
      );

  int basisChanged = 0;

  @override
  Future<RecalculationOffer?> loadBasisChanged() {
    basisChanged++;
    return super.loadBasisChanged();
  }
}
