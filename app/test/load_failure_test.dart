import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_harness.dart';

/// Speicher, dessen Einstellungen und Profil sich lesend scheitern lassen.
class _Flaky implements Storage {
  _Flaky(this.inner);
  final Storage inner;
  bool failSettings = false;
  bool failProfile = false;
  bool failProfileSave = false;

  @override
  Future<StorageSession> open(Uint8List key) async =>
      _Session(this, await inner.open(key));
}

class _Session implements StorageSession {
  _Session(this._o, this._s);
  final _Flaky _o;
  final StorageSession _s;

  @override
  SettingsStore get settings => _Settings(_o, _s.settings);
  @override
  ProfileStore get profile => _Profile(_o, _s.profile);
  @override
  RunStore get runs => _s.runs;
  @override
  RunMarkerStore get markers => _s.markers;
  @override
  RawDataStore get rawData => _s.rawData;
  @override
  PreprocessingStore get preprocessing => _s.preprocessing;
  @override
  RatedSectionStore get sections => _s.sections;
  @override
  ComputedValueStore get values => _s.values;
  @override
  KnownDeviceStore get devices => _s.devices;
  @override
  ConsentStore get consents => _s.consents;
  @override
  RunSubjectiveStore get subjective => _s.subjective;
  @override
  ManualTrainingStore get manualTrainings => _s.manualTrainings;
  @override
  Future<void> deleteRun(int runId) => _s.deleteRun(runId);
  @override
  Future<void> deleteAll() => _s.deleteAll();
  @override
  Future<void> close() => _s.close();
}

class _Settings implements SettingsStore {
  _Settings(this._o, this._s);
  final _Flaky _o;
  final SettingsStore _s;

  @override
  Future<String?> get(String key) async {
    if (_o.failSettings) throw const StorageException(StorageFailure.failed);
    return _s.get(key);
  }

  @override
  Future<Map<String, String>> all() => _s.all();
  @override
  Future<void> set(String key, String value, {required DateTime at}) =>
      _s.set(key, value, at: at);
}

class _Profile implements ProfileStore {
  _Profile(this._o, this._s);
  final _Flaky _o;
  final ProfileStore _s;

  @override
  Future<ProfileRecord> read() async {
    if (_o.failProfile) throw const StorageException(StorageFailure.failed);
    return _s.read();
  }

  @override
  Future<void> save(ProfileRecord profile) async {
    if (_o.failProfileSave) {
      throw const StorageException(StorageFailure.failed);
    }
    return _s.save(profile);
  }
}

void main() {
  testWidgets('Alles löschen: sofort Zustand wie beim ersten Start (km, '
      'Einrichtung), ohne Neustart', (tester) async {
    final d = Device();
    await d.start(tester, const Locale('en'));
    await d.skipSetup(tester);
    await openOverview(tester);
    await tester.tap(find.byKey(const Key('home_settings')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Miles'));
    await tester.pumpAndSettle();
    expect(await d.session.settings.get(SettingKeys.distanceUnit), 'mi');

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('overview_data')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete everything'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Delete everything'),
      ),
    );
    await tester.pumpAndSettle();

    expect(await d.session.settings.get(SettingKeys.setupDone), isNull);
    expect(find.byKey(const Key('setup_skip')), findsOneWidget);
    expect(find.byKey(const Key('home_start_run')), findsNothing);

    await d.skipSetup(tester);
    await openOverview(tester);
    await tester.tap(find.byKey(const Key('home_settings')));
    await tester.pumpAndSettle();
    final button = tester.widget<SegmentedButton<DistanceUnit>>(
      find.byKey(const Key('settings_unit')),
    );
    expect(button.selected, {DistanceUnit.kilometers});
  });

  testWidgets('Einstellungen nicht ladbar: Fehlertext mit Erneut-Knopf', (
    tester,
  ) async {
    final d = Device();
    final flaky = _Flaky(d.storage)..failSettings = true;
    d.storageOverride = flaky;
    await d.start(tester, const Locale('en'));
    expect(find.text('The settings could not be loaded.'), findsOneWidget);
    expect(find.byKey(const Key('setup_skip')), findsNothing);

    flaky.failSettings = false;
    await tester.tap(find.byKey(const Key('settings_load_retry')));
    await tester.pumpAndSettle();
    await d.confirmWelcome(tester);
    expect(find.byKey(const Key('setup_skip')), findsOneWidget);
  });

  testWidgets('Profil nicht ladbar: Fehlertext statt endlosem Laden, Erneut', (
    tester,
  ) async {
    final d = Device();
    final flaky = _Flaky(d.storage)..failProfile = true;
    d.storageOverride = flaky;
    await d.start(tester, const Locale('en'));
    expect(find.byKey(const Key('profile_load_failed')), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byKey(const Key('profile_save')), findsNothing);

    flaky.failProfile = false;
    await tester.tap(find.byKey(const Key('profile_load_retry')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('profile_save')), findsOneWidget);
  });

  testWidgets('Speichern scheitert nach Speichern mit Hinweisen: '
      '"Gespeichert" verschwindet, nur die Fehlermeldung', (tester) async {
    final d = Device();
    final flaky = _Flaky(d.storage);
    d.storageOverride = flaky;
    await d.start(tester, const Locale('en'));
    await d.skipSetup(tester);
    await openOverview(tester);
    await tester.tap(find.byKey(const Key('home_profile')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('profile_resting')), '35');
    await tester.tap(find.byKey(const Key('profile_save')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('profile_saved_note')), findsOneWidget);
    expect(find.text('Saved. Please check the notes.'), findsOneWidget);

    flaky.failProfileSave = true;
    await tester.tap(find.byKey(const Key('profile_save')));
    await tester.pumpAndSettle();
    expect(find.text('The profile could not be saved.'), findsOneWidget);
    expect(find.byKey(const Key('profile_saved_note')), findsNothing);
    expect(find.textContaining('Saved'), findsNothing);
  });

  testWidgets('keine Trainingstage gewählt: gespeichert als "keine Angabe" '
      '(null), nicht 0', (tester) async {
    final d = Device();
    await d.start(tester, const Locale('en'));
    await tester.enterText(find.byKey(const Key('profile_birthYear')), '1986');
    await tester.tap(find.byKey(const Key('profile_save')));
    await tester.pumpAndSettle();
    final p = await d.session.profile.read();
    expect(p.birthYear, 1986);
    expect(p.trainingDaysMask, isNull);
  });

  testWidgets('Zoneneditor: Ladefehler zeigt Fehlertext, kein Speichern, '
      'Erneut lädt', (tester) async {
    final d = Device();
    final flaky = _Flaky(d.storage);
    d.storageOverride = flaky;
    await d.start(tester, const Locale('en'));
    await d.skipSetup(tester);
    await d.session.settings.set(
      SettingKeys.reserveZoneBounds,
      '40,50,60,70,80,100',
      at: DateTime.utc(2026, 6, 1),
    );
    await openOverview(tester);
    flaky.failSettings = true;
    await tester.tap(find.byKey(const Key('overview_zones')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('zones_load_failed')), findsOneWidget);
    expect(find.byKey(const Key('zones_save')), findsNothing);
    expect(find.byKey(const Key('zone_bound_0')), findsNothing);

    flaky.failSettings = false;
    await tester.tap(find.byKey(const Key('zones_load_retry')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('zones_save')), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('zone_bound_0')))
          .controller!
          .text,
      '40',
    );
    expect(
      await d.session.settings.get(SettingKeys.reserveZoneBounds),
      '40,50,60,70,80,100',
    );
  });
}
