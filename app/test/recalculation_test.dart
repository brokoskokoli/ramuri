import 'dart:async';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/recalculation/recalculation_card.dart';
import 'package:running_app/features/storage/deletion.dart';

import 'app_harness.dart';
import 'history_summary_test.dart' show openHistory, seedRun;

final _key = Uint8List.fromList(List.filled(32, 7));
const _metersPerDegree = earthRadiusMeters * 3.141592653589793 / 180;

/// Offload, der inline rechnet und die Läufe jeder Vorverarbeitung
/// ([replayJob]) zählt.
class _CountingOffload {
  final replayed = <int>[];

  Future<R> call<A, R>(R Function(A) job, A argument) async {
    if (identical(job, replayJob) &&
        argument
            is ({
              StoredRun run,
              DateTime end,
              StoredRawData raw,
              List<StoredGap> gaps,
              PreprocessingParameters parameters,
            })) {
      replayed.add(argument.run.id);
    }
    return job(argument);
  }
}

/// Ohne Reihe: führt die Aktion sofort aus.
Future<void> _direct(Future<void> Function() action) => action();

/// Werte, deren Tausch sich steuern lässt: Fehler oder Warten.
class _Gate {
  bool fail = false;
  Completer<void>? hold;
  bool failSettings = false;
  bool failGet = false;
  bool failGetAfterSet = false;
  bool failSettingsAfterSwap = false;
  bool deletedNotErased = false;
  bool failDelete = false;
  int swaps = 0;

  /// Schreibversuche neuer Laufwerte je Lauf (auch gescheiterte).
  final runWrites = <int, int>{};
}

class _GatedValues implements ComputedValueStore {
  _GatedValues(this.inner, this.gate);
  final ComputedValueStore inner;
  final _Gate gate;

  @override
  Future<void> createOriginals(ValueOwner o, List<ComputedValue> v) =>
      inner.createOriginals(o, v);
  @override
  Future<void> swapCurrent(ValueOwner o, List<ComputedValue> v) =>
      swapCurrentAll({o: v});
  @override
  Future<void> swapCurrentAll(Map<ValueOwner, List<ComputedValue>> c) =>
      writeAll(swap: c);
  @override
  Future<List<ValuePair>> read(ValueOwner o) => inner.read(o);
  @override
  Future<Map<int, Map<String, ComputedValue>>> readRunValues(
    Set<String> keys,
  ) => inner.readRunValues(keys);

  @override
  Future<Map<String, Map<String, ComputedValue>>> readDayValues(
    Set<String> keys,
  ) => inner.readDayValues(keys);

  @override
  Future<void> writeAll({
    Map<ValueOwner, List<ComputedValue>> create = const {},
    Map<ValueOwner, List<ComputedValue>> swap = const {},
    Set<String> removeDays = const {},
  }) async {
    gate.swaps++;
    for (final o in create.keys) {
      final id = o.runId;
      if (id != null) gate.runWrites[id] = (gate.runWrites[id] ?? 0) + 1;
    }
    await gate.hold?.future;
    if (gate.fail) throw const StorageException(StorageFailure.failed);
    return inner.writeAll(create: create, swap: swap, removeDays: removeDays);
  }
}

class _GatedSettings implements SettingsStore {
  _GatedSettings(this.inner, this.gate);
  final SettingsStore inner;
  final _Gate gate;
  @override
  Future<String?> get(String key) {
    if (gate.failGet) throw const StorageException(StorageFailure.failed);
    return inner.get(key);
  }

  @override
  Future<Map<String, String>> all() => inner.all();
  @override
  Future<void> set(String key, String value, {required DateTime at}) {
    if (gate.failSettings || (gate.failSettingsAfterSwap && gate.swaps > 0)) {
      throw const StorageException(StorageFailure.failed);
    }
    final done = inner.set(key, value, at: at);
    if (gate.failGetAfterSet) done.then((_) => gate.failGet = true);
    return done;
  }
}

class _GatedSession implements StorageSession {
  _GatedSession(this.inner, this.gate);
  final StorageSession inner;
  final _Gate gate;
  @override
  late final ComputedValueStore values = _GatedValues(inner.values, gate);
  @override
  RunStore get runs => inner.runs;
  @override
  RunMarkerStore get markers => inner.markers;
  @override
  RawDataStore get rawData => inner.rawData;
  @override
  PreprocessingStore get preprocessing => inner.preprocessing;
  @override
  RatedSectionStore get sections => inner.sections;
  @override
  ProfileStore get profile => inner.profile;
  @override
  late final SettingsStore settings = _GatedSettings(inner.settings, gate);
  @override
  KnownDeviceStore get devices => inner.devices;
  @override
  ConsentStore get consents => inner.consents;
  @override
  RunSubjectiveStore get subjective => inner.subjective;
  @override
  ManualTrainingStore get manualTrainings => inner.manualTrainings;
  @override
  Future<void> deleteRun(int runId) async {
    if (gate.failDelete) throw const StorageException(StorageFailure.failed);
    await inner.deleteRun(runId);
    if (gate.deletedNotErased) {
      throw const StorageException(StorageFailure.deletedNotErased);
    }
  }

  @override
  Future<void> deleteAll() => inner.deleteAll();
  @override
  Future<void> close() => inner.close();
}

class _GatedStorage implements Storage {
  _GatedStorage(this.inner, this.gate);
  final Storage inner;
  final _Gate gate;
  @override
  Future<StorageSession> open(Uint8List key) async =>
      _GatedSession(await inner.open(key), gate);
}

/// Synthetischer Zustand vor dem App-Start: Profil HFmax 190 / Ruhe 60 und
/// zwei beendete, berechnete Läufe (30 min, 3 m/s, 150 bpm).
/// [calculateLast]: ohne, bleibt der letzte Lauf ohne Werte (holt der Start
/// nach).
Future<void> _seed(
  Device d, {
  List<DateTime>? starts,
  bool calculateLast = true,
}) async {
  final s = await d.storage.open(_key);
  await s.profile.save(
    const ProfileRecord(maxHeartRateBpm: 190, restingHeartRateBpm: 60),
  );
  final calc = ValueCalculationService(
    algorithms: AlgorithmRegistry.standard(),
    session: s,
    clock: d.clock,
  );
  final seedStarts =
      starts ?? [DateTime.utc(2026, 5, 10, 8), DateTime.utc(2026, 5, 17, 8)];
  for (final start in seedStarts) {
    final run = await s.runs.create(startedAt: start);
    final positions = <RawPosition>[];
    final hrs = <RawHeartRate>[];
    final alts = <RawAltitude>[];
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
      alts.add(
        RawAltitude(
          time: t,
          source: 'baro',
          meters: 100,
          verticalAccuracyMeters: 3,
        ),
      );
    }
    await s.rawData.append(
      run.id,
      RawBatch(positions: positions, heartRates: hrs, altitudes: alts),
    );
    final end = start.add(const Duration(minutes: 30));
    await s.runs.setState(run.id, RunState.finished, endedAt: end);
    d.clock.set(end.add(const Duration(minutes: 1)));
    if (calculateLast || start != seedStarts.last) {
      await calc.calculateAfterRun(run.id);
    }
  }
  d.clock.set(DateTime.utc(2026, 6, 1));
  await s.close();
}

/// Alle Werte der Läufe und Tage als Text (Vergleich vorher/nachher).
Future<String> _dump(StorageSession s) async {
  final out = StringBuffer();
  final owners = <ValueOwner>[
    for (final r in await s.runs.list()) ValueOwner.run(r.id),
    for (final r in await s.runs.list())
      if (r.endedAt != null) ValueOwner.day(dayOfRun(r)),
  ];
  for (final o in owners) {
    for (final p in await s.values.read(o)) {
      out.writeln(
        '${o.runId}/${o.day} ${p.original.key}${p.original.value}@${p.original.heartRateBasis?.maxBpm}'
        ' || ${p.current.value}@${p.current.heartRateBasis?.maxBpm}',
      );
    }
  }
  return out.toString();
}

/// Ändert HFmax im Profil auf 180 über die Oberfläche und geht zurück in die
/// Einstellungen.
Future<void> _changeMaxAndOpenSettings(WidgetTester tester) async {
  await openOverview(tester);
  await tester.tap(find.byKey(const Key('home_profile')));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('profile_max')), '180');
  await tester.tap(find.byKey(const Key('profile_save')));
  await tester.pumpAndSettle();
  await tester.tap(find.byType(BackButton));
  await tester.pumpAndSettle();
  await openOverview(tester);
  await tester.tap(find.byKey(const Key('home_settings')));
  await tester.pumpAndSettle();
}

/// Dauer einer Snackbar ohne eigene `duration` (Standard von Flutter).
final _snackBarDuration = const SnackBar(content: SizedBox()).duration;

/// Nach erfolgreicher Neuberechnung: die Meldung steht in einer Snackbar,
/// die Karte zeigt kein Ergebnis (ohne weiteres Angebot ist sie weg).
void _expectDoneSnackBar(int runs) {
  final bar = find.byKey(const Key('recalc_done'));
  expect(bar, findsOneWidget);
  expect(
    find.descendant(
      of: bar,
      matching: find.text(
        'Neuberechnet: $runs Läufe. Die ursprünglichen Werte bleiben erhalten.',
      ),
    ),
    findsOneWidget,
  );
  expect(find.textContaining('Neuberechnet'), findsOneWidget);
  expect(find.byKey(const Key('recalc_status')), findsNothing);
  expect(find.byKey(const Key('recalc_dialog')), findsNothing);
}

Future<Device> _start(
  WidgetTester tester, {
  Locale locale = const Locale('de'),
  _Gate? gate,
  List<DateTime>? starts,
  Offload? offload,
  bool calculateLast = true,
}) async {
  final d = Device();
  if (offload != null) d.offload = offload;
  await _seed(d, starts: starts, calculateLast: calculateLast);
  if (gate != null) d.storageOverride = _GatedStorage(d.storage, gate);
  await d.start(tester, locale);
  await d.skipSetup(tester);
  return d;
}

void main() {
  testWidgets(
    'Angebot erscheint nach Profiländerung, ändert nichts (FR-0006)',
    (tester) async {
      final d = await _start(tester);
      final before = await _dump(d.session);
      expect(before, isNotEmpty);
      // Ohne Änderung: kein Angebot.
      await openOverview(tester);
      await tester.tap(find.byKey(const Key('home_settings')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('recalc_dialog')), findsNothing);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      await _changeMaxAndOpenSettings(tester);
      expect(find.byKey(const Key('recalc_dialog')), findsOneWidget);
      expect(find.byKey(const Key('recalc_cause_heartRateBasis')), findsOne);
      expect(find.textContaining('Herzfrequenz-Basis'), findsOneWidget);
      expect(find.byKey(const Key('recalc_confirm')), findsOneWidget);
      expect(find.byKey(const Key('recalc_decline')), findsOneWidget);
      expect(await _dump(d.session), before);
    },
  );

  testWidgets('Snackbar nach dem Speichern weist auf die Neuberechnung hin, '
      'verschwindet mit der Seite', (tester) async {
    await _start(tester, locale: const Locale('en'));
    await openOverview(tester);
    await tester.tap(find.byKey(const Key('home_profile')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('profile_max')), '180');
    await tester.tap(find.byKey(const Key('profile_save')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      find.text(
        'Profile saved.\nA recalculation is possible. You can find it in settings.',
      ),
      findsOneWidget,
    );
    // Beim Verlassen der Seite darf nichts stehen bleiben und den
    // Speichern-Knopf beim nächsten Besuch verdecken.
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.textContaining('Profile saved.'), findsNothing);
  });

  testWidgets('Profiländerung ohne Einfluss auf die Basis bietet nichts an', (
    tester,
  ) async {
    await _start(tester);
    await openOverview(tester);
    await tester.tap(find.byKey(const Key('home_profile')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('profile_weight')), '70');
    await tester.tap(find.byKey(const Key('profile_save')));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await openOverview(tester);
    await tester.tap(find.byKey(const Key('home_settings')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('recalc_dialog')), findsNothing);
  });

  testWidgets('Angebot überlebt den Neustart (pendingOffer beim Start)', (
    tester,
  ) async {
    final d = await _start(tester);
    await _changeMaxAndOpenSettings(tester);
    await d.stop(tester);
    await d.start(tester, const Locale('de'));
    await openOverview(tester);
    await tester.tap(find.byKey(const Key('home_settings')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('recalc_dialog')), findsOneWidget);
  });

  testWidgets(
    'Ablehnen ändert keine Werte und blendet das Angebot aus (OQ-0053)',
    (tester) async {
      final d = await _start(tester);
      final before = await _dump(d.session);
      await _changeMaxAndOpenSettings(tester);
      await tester.tap(find.byKey(const Key('recalc_decline')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('recalc_dialog')), findsNothing);
      expect(await _dump(d.session), before);
      expect(
        d.session.settings.get(RecalculationService.pendingKey),
        completion(''),
      );
    },
  );

  testWidgets('Annehmen rechnet die Vorverarbeitung jedes Laufs über den '
      'Offload der App', (tester) async {
    final offload = _CountingOffload();
    final d = await _start(tester, offload: offload.call);
    final ids = [for (final r in await d.session.runs.list()) r.id]..sort();
    await _changeMaxAndOpenSettings(tester);
    offload.replayed.clear();
    await tester.tap(find.byKey(const Key('recalc_confirm')));
    await tester.pumpAndSettle();
    _expectDoneSnackBar(2);
    expect(offload.replayed.toSet().toList()..sort(), ids);
  });

  testWidgets('Nachholen beim Start rechnet die Vorverarbeitung über den '
      'Offload der App', (tester) async {
    final offload = _CountingOffload();
    final d = await _start(tester, offload: offload.call, calculateLast: false);
    final runs = await d.session.runs.list();
    final last = runs.map((r) => r.id).reduce((a, b) => a > b ? a : b);
    expect(offload.replayed, contains(last));
    expect(await d.session.values.read(ValueOwner.run(last)), isNotEmpty);
  });

  testWidgets('Annehmen tauscht current, original bleibt (FR-0058)', (
    tester,
  ) async {
    final gate = _Gate();
    final d = await _start(tester, gate: gate);
    final before = await _dump(d.session);
    await _changeMaxAndOpenSettings(tester);
    await tester.tap(find.byKey(const Key('recalc_confirm')));
    await tester.pumpAndSettle();
    expect(gate.swaps, 1);
    expect(find.byKey(const Key('recalc_confirm')), findsNothing);
    _expectDoneSnackBar(2);
    final after = await _dump(d.session);
    expect(after, isNot(before));
    // original unverändert (Teil vor "||"), current mit neuer Basis 180.
    String originals(String t) =>
        t.split('\n').map((l) => l.split(' || ').first).join('\n');
    expect(originals(after), originals(before));
    expect(after, contains('@180'));
    expect(
      d.session.settings.get(RecalculationService.pendingKey),
      completion(''),
    );
  });

  testWidgets('Neuberechnet als Snackbar mit Standarddauer, danach weg; '
      'Karte ohne Ergebnis (FR-0058)', (tester) async {
    await _start(tester);
    await _changeMaxAndOpenSettings(tester);
    await tester.tap(find.byKey(const Key('recalc_confirm')));
    await tester.pumpAndSettle();
    _expectDoneSnackBar(2);
    // Keine eigene Dauer: wie die übrigen Bestätigungen der App.
    expect(
      tester.widget<SnackBar>(find.byKey(const Key('recalc_done'))).duration,
      _snackBarDuration,
    );
    // Kurz vor Ablauf steht sie noch, danach ist sie weg; die Karte bleibt
    // ohne Ergebnis.
    await tester.pump(_snackBarDuration - const Duration(milliseconds: 100));
    expect(find.byKey(const Key('recalc_done')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('recalc_done')), findsNothing);
    expect(find.textContaining('Neuberechnet'), findsNothing);
    expect(find.byKey(const Key('recalc_dialog')), findsNothing);
  });

  testWidgets(
    'Fehler bei der Berechnung: Meldung, alter Stand, erneut möglich',
    (tester) async {
      final gate = _Gate()..fail = true;
      final d = await _start(tester, gate: gate);
      final before = await _dump(d.session);
      await _changeMaxAndOpenSettings(tester);
      await tester.tap(find.byKey(const Key('recalc_confirm')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('recalc_status')), findsOneWidget);
      expect(find.textContaining('fehlgeschlagen'), findsOneWidget);
      expect(find.textContaining('180'), findsNothing);
      expect(find.byKey(const Key('recalc_done')), findsNothing);
      expect(await _dump(d.session), before);
      // Der Fehler ist keine Snackbar: er bleibt über deren Dauer hinaus in
      // der Karte stehen.
      await tester.pump(_snackBarDuration + const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const Key('recalc_dialog')),
          matching: find.textContaining('fehlgeschlagen'),
        ),
        findsOneWidget,
      );
      // Angebot bleibt, ein neuer Versuch gelingt.
      gate.fail = false;
      await tester.tap(find.byKey(const Key('recalc_confirm')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Neuberechnet'), findsOneWidget);
      expect(await _dump(d.session), isNot(before));
    },
  );

  testWidgets(
    'Während der Berechnung: Fortschritt, Sperre; 411x914 ohne Überlauf',
    (tester) async {
      final gate = _Gate()..hold = Completer<void>();
      await _start(tester, gate: gate, locale: const Locale('en'));
      await _changeMaxAndOpenSettings(tester);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(411, 914);
      addTearDown(tester.view.reset);
      await tester.pumpAndSettle();
      // Wirklich 411x914 logische Pixel, nicht nur physische.
      expect(
        tester.view.physicalSize / tester.view.devicePixelRatio,
        const Size(411, 914),
      );
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(const Key('recalc_confirm')));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('recalc_progress')), findsOneWidget);
      expect(find.textContaining('Please wait'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.descendant(
                of: find.byKey(const Key('recalc_confirm')),
                matching: find.byType(FilledButton),
              ),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.descendant(
                of: find.byKey(const Key('recalc_decline')),
                matching: find.byType(OutlinedButton),
              ),
            )
            .onPressed,
        isNull,
      );
      // Zurück ist gesperrt.
      await tester.tap(find.byType(BackButton));
      await tester.pump();
      expect(find.byKey(const Key('recalc_dialog')), findsOneWidget);
      // Die Einstellungen führen nicht mehr zu Sensoren, Zonen, Berechtigungen
      // und Daten; diese Einträge liegen in der Übersicht (dort gesperrt,
      // overview_test.dart).
      for (final k in [
        'overview_permissions',
        'overview_sensors',
        'overview_zones',
        'overview_data',
        'settings_permissions',
        'settings_sensors',
        'settings_zones',
        'settings_data',
      ]) {
        expect(find.byKey(Key(k)), findsNothing, reason: k);
      }
      // Die Einheit liegt unter dem Abschnitt Belastungsprofil (WP19).
      await tester.scrollUntilVisible(
        find.byKey(const Key('settings_unit')),
        200,
      );
      expect(
        tester
            .widget<SegmentedButton<DistanceUnit>>(
              find.byKey(const Key('settings_unit')),
            )
            .onSelectionChanged,
        isNull,
      );

      gate.hold!.complete();
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView), const Offset(0, 3000));
      await tester.pumpAndSettle();
      expect(find.textContaining('Recalculated: 2 runs'), findsOneWidget);
      expect(tester.takeException(), isNull);
      // Danach ist die Einheit wieder frei.
      await tester.scrollUntilVisible(
        find.byKey(const Key('settings_unit')),
        200,
      );
      expect(
        tester
            .widget<SegmentedButton<DistanceUnit>>(
              find.byKey(const Key('settings_unit')),
            )
            .onSelectionChanged,
        isNotNull,
      );
    },
  );

  testWidgets('Abgelehntes Profil löst kein Angebot aus', (tester) async {
    final d = await _start(tester);
    await openOverview(tester);
    await tester.tap(find.byKey(const Key('home_profile')));
    await tester.pumpAndSettle();
    // HFmax 400 liegt außerhalb von PAR-016 und wird abgelehnt.
    await tester.enterText(find.byKey(const Key('profile_max')), '400');
    await tester.tap(find.byKey(const Key('profile_save')));
    await tester.pumpAndSettle();
    expect((await d.session.profile.read()).maxHeartRateBpm, 190);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await openOverview(tester);
    await tester.tap(find.byKey(const Key('home_settings')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('recalc_dialog')), findsNothing);
    expect(
      d.session.settings.get(RecalculationService.pendingKey),
      completion(anyOf(isNull, isEmpty)),
    );
  });

  testWidgets(
    'Löschen eines Laufs legt die Tageswerte der übrigen Lauftage neu an',
    (tester) async {
      final d = await _start(
        tester,
        starts: [
          DateTime.utc(2026, 5, 10, 8),
          DateTime.utc(2026, 5, 17, 8),
          DateTime.utc(2026, 5, 17, 15),
        ],
      );
      final s = d.session;
      final runs = [...await s.runs.list()]
        ..sort((a, b) => a.id.compareTo(b.id));
      final dayOfRemaining = dayOfRun(runs.last);
      final doomed = runs[1].id;
      final keep = runs.last.id;
      expect(dayOfRun(runs[1]), dayOfRemaining);
      Future<String> originals() async => [
        for (final o in [ValueOwner.run(runs.first.id), ValueOwner.run(keep)])
          for (final p in await s.values.read(o)) '${p.original.value}',
      ].join(',');
      final originalsBefore = await originals();
      final rawBefore = (await s.rawData.read(keep)).positions.length;
      final rawFirstBefore = (await s.rawData.read(runs.first.id))
          .positions
          .length;
      expect(await s.values.read(ValueOwner.day(dayOfRemaining)), isNotEmpty);

      await deleteRunAndRefresh(
        algorithms: AlgorithmRegistry.standard(),
        s,
        d.clock,
        doomed,
        serialize: _direct,
      );

      expect(await s.runs.get(doomed), isNull);
      expect(
        await s.values.read(ValueOwner.day(dayOfRemaining)),
        isNotEmpty,
        reason: 'Tageswerte des verbliebenen Laufs fehlen',
      );
      expect(await originals(), originalsBefore);
      expect((await s.rawData.read(keep)).positions.length, rawBefore);
      expect(
        (await s.rawData.read(runs.first.id)).positions.length,
        rawFirstBefore,
      );
    },
  );

  testWidgets('Fehler beim Neuanlegen nach dem Löschen: Lauf weg, kein Wurf', (
    tester,
  ) async {
    final gate = _Gate();
    final d = await _start(tester, gate: gate);
    final s = d.session;
    final id = (await s.runs.list()).first.id;
    gate.fail = true;
    await deleteRunAndRefresh(
      algorithms: AlgorithmRegistry.standard(),
      s,
      d.clock,
      id,
      serialize: _direct,
    );
    expect(await s.runs.get(id), isNull);
  });

  testWidgets(
    'Gelöscht, nur der Checkpoint scheiterte: Wurf und Tageswerte wieder da',
    (tester) async {
      final gate = _Gate();
      final d = await _start(
        tester,
        gate: gate,
        starts: [
          DateTime.utc(2026, 5, 10, 8),
          DateTime.utc(2026, 5, 17, 8),
          DateTime.utc(2026, 5, 17, 15),
        ],
      );
      final s = d.session;
      final runs = [...await s.runs.list()]
        ..sort((a, b) => a.id.compareTo(b.id));
      final day = dayOfRun(runs.last);
      gate.deletedNotErased = true;
      await expectLater(
        deleteRunAndRefresh(
          algorithms: AlgorithmRegistry.standard(),
          s,
          d.clock,
          runs[1].id,
          serialize: _direct,
        ),
        throwsA(
          isA<StorageException>().having(
            (e) => e.failure,
            'failure',
            StorageFailure.deletedNotErased,
          ),
        ),
      );
      expect(await s.runs.get(runs[1].id), isNull);
      expect(await s.values.read(ValueOwner.day(day)), isNotEmpty);
      expect(
        await s.settings.get(ValueCalculationService.refreshPendingKey),
        anyOf(isNull, isEmpty),
      );
    },
  );

  testWidgets(
    'Neuanlegen scheitert: Merker bleibt, nach dem Neustart sind die Werte da',
    (tester) async {
      final gate = _Gate();
      final d = await _start(
        tester,
        gate: gate,
        starts: [
          DateTime.utc(2026, 5, 10, 8),
          DateTime.utc(2026, 5, 17, 8),
          DateTime.utc(2026, 5, 17, 15),
        ],
      );
      final s = d.session;
      final runs = [...await s.runs.list()]
        ..sort((a, b) => a.id.compareTo(b.id));
      final day = dayOfRun(runs.last);
      gate.fail = true;
      await deleteRunAndRefresh(
        algorithms: AlgorithmRegistry.standard(),
        s,
        d.clock,
        runs[1].id,
        serialize: _direct,
      );
      expect(await s.values.read(ValueOwner.day(day)), isEmpty);
      final mark = await s.settings.get(
        ValueCalculationService.refreshPendingKey,
      );
      expect(mark, startsWith('${runs[1].id}@'));

      gate.fail = false;
      await d.stop(tester);
      await d.start(tester, const Locale('de'));
      await tester.pumpAndSettle();
      expect(await d.session.values.read(ValueOwner.day(day)), isNotEmpty);
      expect(
        await d.session.settings.get(ValueCalculationService.refreshPendingKey),
        isEmpty,
      );
    },
  );

  testWidgets('Löschen mit gelungenem Neuanlegen entfernt den Merker', (
    tester,
  ) async {
    final d = await _start(tester);
    final s = d.session;
    await deleteRunAndRefresh(
      algorithms: AlgorithmRegistry.standard(),
      s,
      d.clock,
      (await s.runs.list()).first.id,
      serialize: _direct,
    );
    expect(
      await s.settings.get(ValueCalculationService.refreshPendingKey),
      anyOf(isNull, isEmpty),
    );
  });

  testWidgets(
    'Löschen und Neuanlegen laufen ganz über serialize (nichts davor)',
    (tester) async {
      final d = await _start(tester);
      final s = d.session;
      final id = (await s.runs.list()).first.id;
      Future<void> Function()? queued;
      var calls = 0;
      final done = deleteRunAndRefresh(
        algorithms: AlgorithmRegistry.standard(),
        s,
        d.clock,
        id,
        serialize: (action) {
          calls++;
          queued = action;
          return Future<void>.value();
        },
      );
      await done;
      // Eingereiht, aber noch nicht gelaufen: kein Merker, nichts gelöscht.
      expect(calls, 1);
      expect(await s.runs.get(id), isNotNull);
      expect(
        await s.settings.get(ValueCalculationService.refreshPendingKey),
        isNull,
      );
      await queued!();
      expect(await s.runs.get(id), isNull);
    },
  );

  testWidgets(
    'Löschen scheitert ohne Löschen: ein alter Merker bleibt, ein leerer wird entfernt',
    (tester) async {
      final gate = _Gate();
      final d = await _start(tester, gate: gate);
      final s = d.session;
      final id = (await s.runs.list()).first.id;
      const key = ValueCalculationService.refreshPendingKey;
      gate.failDelete = true;

      // Vorher leer: der eigene Merker wird wieder entfernt.
      await expectLater(
        deleteRunAndRefresh(
          algorithms: AlgorithmRegistry.standard(),
          s,
          d.clock,
          id,
          serialize: _direct,
        ),
        throwsA(isA<StorageException>()),
      );
      expect(await s.settings.get(key), anyOf(isNull, isEmpty));

      // Vorher ein Merker eines früheren, unvollendeten Neuanlegens: bleibt.
      await s.settings.set(
        key,
        '99@2026-01-01T00:00:00.000Z',
        at: d.clock.now(),
      );
      await expectLater(
        deleteRunAndRefresh(
          algorithms: AlgorithmRegistry.standard(),
          s,
          d.clock,
          id,
          serialize: _direct,
        ),
        throwsA(isA<StorageException>()),
      );
      expect(await s.settings.get(key), isNotEmpty);
      expect(await s.runs.get(id), isNotNull);
    },
  );

  testWidgets('Merker nicht setzbar: nichts wird gelöscht', (tester) async {
    final gate = _Gate();
    final d = await _start(tester, gate: gate);
    final s = d.session;
    final id = (await s.runs.list()).first.id;
    gate.failSettings = true;
    await expectLater(
      deleteRunAndRefresh(
        algorithms: AlgorithmRegistry.standard(),
        s,
        d.clock,
        id,
        serialize: _direct,
      ),
      throwsA(isA<StorageException>()),
    );
    expect(await s.runs.get(id), isNotNull);
  });

  testWidgets(
    'Tausch und Speichern gelungen, Lesen des Angebots scheitert: erledigt',
    (tester) async {
      final gate = _Gate();
      await _start(tester, gate: gate);
      await _changeMaxAndOpenSettings(tester);
      gate.failGetAfterSet = true;
      await tester.tap(find.byKey(const Key('recalc_confirm')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Neuberechnet: 2 Läufe'), findsOneWidget);
      expect(find.textContaining('fehlgeschlagen'), findsNothing);
      expect(find.byKey(const Key('recalc_confirm')), findsNothing);
    },
  );

  testWidgets(
    'Tausch gelungen, Angebot nicht erledigt gespeichert: erledigt, nicht fehlgeschlagen',
    (tester) async {
      final gate = _Gate();
      await _start(tester, gate: gate);
      await _changeMaxAndOpenSettings(tester);
      gate.failSettingsAfterSwap = true;
      await tester.tap(find.byKey(const Key('recalc_confirm')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Neuberechnet: 2 Läufe'), findsOneWidget);
      expect(find.textContaining('fehlgeschlagen'), findsNothing);
    },
  );

  testWidgets('Ablehnen scheitert: eigene Meldung, Angebot bleibt', (
    tester,
  ) async {
    final gate = _Gate();
    await _start(tester, gate: gate);
    await _changeMaxAndOpenSettings(tester);
    gate.failSettings = true;
    await tester.tap(find.byKey(const Key('recalc_decline')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Ablehnen konnte nicht'), findsOneWidget);
    expect(
      find.textContaining('Neuberechnung ist fehlgeschlagen'),
      findsNothing,
    );
    expect(find.byKey(const Key('recalc_confirm')), findsOneWidget);
    expect(find.text('Neu berechnen'), findsWidgets);
  });

  _uncomputableTests();
}

/// Texte der Karte „Nicht berechenbare Läufe“ (FR-0219).
const _uncomputableTexts = {
  'de': (
    title: 'Nicht berechenbare Läufe',
    intro:
        'Bei einigen Läufen ließen sich die Werte nach drei Versuchen nicht '
        'berechnen. Die Aufzeichnungen sind vollständig gespeichert.',
    button: 'Neu berechnen',
    decline: 'Nicht jetzt',
    failed:
        'Die Berechnung ist wieder fehlgeschlagen. Die Aufzeichnungen sind '
        'unverändert.',
  ),
  'en': (
    title: 'Runs that could not be calculated',
    intro:
        'The values of some runs could not be calculated after three '
        'attempts. The recordings are fully saved.',
    button: 'Recalculate',
    decline: 'Not now',
    failed: 'The calculation failed again. The recordings are unchanged.',
  ),
};

/// Wie [_start], dazu zwei Läufe ohne Werte, die nach drei gezählten
/// Fehlversuchen als nicht berechenbar gelten (der Start versucht sie nicht).
/// Mit [failures] unter drei gelten sie noch nicht so.
Future<(Device, List<int>)> _startUncomputable(
  WidgetTester tester, {
  String locale = 'de',
  _Gate? gate,
  int failures = uncomputableAfterFailures,
}) async {
  final d = Device();
  await _seed(d);
  final s = await d.storage.open(_key);
  final ids = [
    await seedRun(s, DateTime.utc(2026, 5, 20, 8)),
    await seedRun(s, DateTime.utc(2026, 5, 24, 8)),
  ];
  final counter = CalculationFailures(settings: s.settings, clock: d.clock);
  for (final id in ids) {
    for (var i = 0; i < failures; i++) {
      await counter.recordFailure(id);
    }
  }
  await s.close();
  if (gate != null) d.storageOverride = _GatedStorage(d.storage, gate);
  await d.start(tester, Locale(locale));
  await d.skipSetup(tester);
  return (d, ids);
}

/// Leere Karte ohne Angebot und ohne nicht berechenbaren Lauf. Sie hat keine
/// Höhe und gilt in der Liste darum als nicht sichtbar.
final _none = find.byKey(const Key('recalc_none'), skipOffstage: false);

Future<void> _openSettings(WidgetTester tester) async {
  await openOverview(tester);
  final tab = find.byKey(const Key('home_profile_tab'));
  if (find.byKey(const Key('home_settings')).evaluate().isEmpty &&
      tab.evaluate().isNotEmpty) {
    await tester.tap(tab);
    await tester.pumpAndSettle();
  }
  await tester.tap(find.byKey(const Key('home_settings')));
  await tester.pumpAndSettle();
}

Future<Map<int, int>> _failureCounts(Device d) =>
    CalculationFailures(settings: d.session.settings, clock: d.clock).read();

/// Löst ein Angebot direkt über den Dienst aus (Profiländerung HFmax 190 auf
/// [max]), ohne die Reihe der Berechnungen: so kommt es an, während der
/// Versuch der nicht berechenbaren Läufe noch wartet.
Future<void> _offerNow(WidgetTester tester, {int max = 180}) async {
  final controller = tester
      .widget<RecalculationCard>(find.byType(RecalculationCard))
      .controller;
  final offer = await controller.service.profileChanged(
    before: const ProfileRecord(maxHeartRateBpm: 190, restingHeartRateBpm: 60),
    after: ProfileRecord(maxHeartRateBpm: max, restingHeartRateBpm: 60),
  );
  expect(offer, isNotNull);
  await tester.pump();
}

/// Ob die Schaltfläche mit [key] die Beschriftung [label] trägt und
/// bedienbar ist.
void _expectEnabledButton(Key key, String label) {
  final button = find.byKey(key);
  expect(
    find.descendant(of: button, matching: find.text(label)),
    findsOneWidget,
  );
  final inner = find.descendant(
    of: button,
    matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
  );
  expect(
    (inner.evaluate().single.widget as ButtonStyleButton).onPressed,
    isNotNull,
    reason: '$key bedienbar',
  );
}

void _uncomputableTests() {
  group('Nicht berechenbare Läufe ohne Angebot (FR-0219)', () {
    for (final MapEntry(key: locale, value: t) in _uncomputableTexts.entries) {
      testWidgets('Karte mit Satz und Schaltfläche ($locale)', (tester) async {
        await _startUncomputable(tester, locale: locale);
        await _openSettings(tester);
        final card = find.byKey(const Key('recalc_uncomputable'));
        expect(card, findsOneWidget);
        expect(find.byKey(const Key('recalc_dialog')), findsNothing);
        expect(_none, findsNothing);
        for (final text in [t.title, t.intro]) {
          expect(
            find.descendant(of: card, matching: find.text(text)),
            findsOneWidget,
          );
        }
        final button = find.byKey(const Key('recalc_uncomputable_confirm'));
        expect(button, findsOneWidget);
        expect(
          find.descendant(of: button, matching: find.text(t.button)),
          findsOneWidget,
        );
        expect(find.byKey(const Key('recalc_status')), findsNothing);
        expect(find.byKey(const Key('recalc_progress')), findsNothing);
      });

      testWidgets('ohne nicht berechenbaren Lauf keine Karte ($locale)', (
        tester,
      ) async {
        await _start(tester, locale: Locale(locale));
        await _openSettings(tester);
        expect(_none, findsOneWidget);
        expect(find.byKey(const Key('recalc_uncomputable')), findsNothing);
        expect(find.byKey(const Key('recalc_dialog')), findsNothing);
        expect(find.text(t.title), findsNothing);
      });
    }

    testWidgets('zwei Fehlversuche: noch keine Karte', (tester) async {
      await _startUncomputable(tester, failures: 2);
      await _openSettings(tester);
      expect(_none, findsOneWidget);
      expect(find.byKey(const Key('recalc_uncomputable')), findsNothing);
    });

    testWidgets('Zähler nach dem Start erreicht: Einstellungen lesen neu', (
      tester,
    ) async {
      final d = await _start(tester);
      final id = (await d.session.runs.list()).first.id;
      final counter = CalculationFailures(
        settings: d.session.settings,
        clock: d.clock,
      );
      for (var i = 0; i < uncomputableAfterFailures; i++) {
        await counter.recordFailure(id);
      }
      await _openSettings(tester);
      expect(find.byKey(const Key('recalc_uncomputable')), findsOneWidget);
    });

    testWidgets(
      'mit Angebot nur die Neuberechnungs-Karte; sie versucht die Läufe mit',
      (tester) async {
        final gate = _Gate();
        final (d, ids) = await _startUncomputable(tester, gate: gate);
        await _changeMaxAndOpenSettings(tester);
        expect(find.byKey(const Key('recalc_dialog')), findsOneWidget);
        expect(find.byKey(const Key('recalc_uncomputable')), findsNothing);
        expect(
          find.byKey(const Key('recalc_uncomputable_confirm')),
          findsNothing,
        );
        await tester.tap(find.byKey(const Key('recalc_confirm')));
        await tester.pumpAndSettle();
        for (final id in ids) {
          expect(gate.runWrites[id], 1, reason: 'Lauf $id');
        }
        expect(await _failureCounts(d), isEmpty);
        expect(find.byKey(const Key('recalc_dialog')), findsNothing);
        expect(find.byKey(const Key('recalc_uncomputable')), findsNothing);
      },
    );

    testWidgets('Neu berechnen gelingt: ein Versuch je Lauf, Karte und '
        'Kennzeichnung weg', (tester) async {
      final gate = _Gate();
      final (d, ids) = await _startUncomputable(tester, gate: gate);
      await openHistory(d, tester);
      for (final id in ids) {
        expect(find.byKey(Key('history_uncomputable_$id')), findsOneWidget);
      }
      await _openSettings(tester);
      expect(gate.runWrites, isEmpty);
      await tester.tap(find.byKey(const Key('recalc_uncomputable_confirm')));
      await tester.pumpAndSettle();
      for (final id in ids) {
        expect(gate.runWrites[id], 1, reason: 'Lauf $id');
        expect(await d.session.values.read(ValueOwner.run(id)), isNotEmpty);
      }
      expect(await _failureCounts(d), isEmpty);
      expect(find.byKey(const Key('recalc_uncomputable')), findsNothing);
      expect(_none, findsOneWidget);
      expect(find.byKey(const Key('recalc_status')), findsNothing);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await openHistory(d, tester);
      for (final id in ids) {
        expect(find.byKey(Key('history_run_$id')), findsOneWidget);
        expect(find.byKey(Key('history_uncomputable_$id')), findsNothing);
      }
    });

    for (final MapEntry(key: locale, value: t) in _uncomputableTexts.entries) {
      testWidgets('Neu berechnen scheitert: Meldung ohne Inhalt, Zähler 1, '
          'der nächste Start versucht den Lauf ($locale)', (tester) async {
        final gate = _Gate();
        final (d, ids) = await _startUncomputable(
          tester,
          locale: locale,
          gate: gate,
        );
        await _openSettings(tester);
        gate.fail = true;
        await tester.tap(find.byKey(const Key('recalc_uncomputable_confirm')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final card = find.byKey(const Key('recalc_uncomputable'));
        expect(card, findsOneWidget);
        final status = find.byKey(const Key('recalc_status'));
        expect(find.descendant(of: card, matching: status), findsOneWidget);
        expect((status.evaluate().single.widget as Text).data, t.failed);
        expect(find.textContaining('StorageException'), findsNothing);
        expect(find.textContaining('failed.'), findsNothing);
        expect(find.byKey(const Key('recalc_progress')), findsNothing);
        // Kein Lauf ist mehr nicht berechenbar: nichts mehr zu versuchen.
        expect(
          find.byKey(const Key('recalc_uncomputable_confirm')),
          findsNothing,
        );
        expect(await _failureCounts(d), {for (final id in ids) id: 1});
        for (final id in ids) {
          expect(gate.runWrites[id], 1, reason: 'Lauf $id');
        }
        // Der nächste Start versucht die Läufe; sie gelingen jetzt.
        gate.fail = false;
        await d.stop(tester);
        await d.start(tester, Locale(locale));
        await tester.pumpAndSettle();
        for (final id in ids) {
          expect(gate.runWrites[id], 2, reason: 'Lauf $id');
          expect(await d.session.values.read(ValueOwner.run(id)), isNotEmpty);
        }
        expect(await _failureCounts(d), isEmpty);
        await _openSettings(tester);
        expect(find.byKey(const Key('recalc_uncomputable')), findsNothing);
      });
    }

    testWidgets('während des Versuchs: Fortschritt, Sperre, kein zweiter '
        'Aufruf', (tester) async {
      final gate = _Gate();
      final (d, ids) = await _startUncomputable(tester, gate: gate);
      await _openSettings(tester);
      final hold = gate.hold = Completer<void>();
      final button = find.byKey(const Key('recalc_uncomputable_confirm'));
      await tester.tap(button);
      await tester.pump();
      expect(find.byKey(const Key('recalc_progress')), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.descendant(of: button, matching: find.byType(FilledButton)),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(button, warnIfMissed: false);
      await tester.pump();
      // Die Seite ist gesperrt.
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.byKey(const Key('recalc_uncomputable')), findsOneWidget);
      hold.complete();
      gate.hold = null;
      await tester.pumpAndSettle();
      for (final id in ids) {
        expect(gate.runWrites[id], 1, reason: 'Lauf $id');
      }
      expect(await _failureCounts(d), isEmpty);
      expect(find.byKey(const Key('recalc_progress')), findsNothing);
      expect(find.byKey(const Key('recalc_uncomputable')), findsNothing);
    });
    for (final MapEntry(key: locale, value: t) in _uncomputableTexts.entries) {
      testWidgets('Neu berechnen scheitert, während ein Angebot ankommt: '
          'Meldung in der Karte des Angebots ($locale)', (tester) async {
        final gate = _Gate();
        await _startUncomputable(tester, locale: locale, gate: gate);
        await _openSettings(tester);
        gate.fail = true;
        final hold = gate.hold = Completer<void>();
        await tester.tap(find.byKey(const Key('recalc_uncomputable_confirm')));
        await tester.pump();
        expect(find.byKey(const Key('recalc_progress')), findsOneWidget);
        await _offerNow(tester);
        hold.complete();
        gate.hold = null;
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final dialog = find.byKey(const Key('recalc_dialog'));
        expect(dialog, findsOneWidget);
        expect(find.byKey(const Key('recalc_uncomputable')), findsNothing);
        final status = find.byKey(const Key('recalc_status'));
        expect(find.descendant(of: dialog, matching: status), findsOneWidget);
        expect((status.evaluate().single.widget as Text).data, t.failed);
        expect(find.textContaining('StorageException'), findsNothing);
        expect(find.textContaining('failed.'), findsNothing);
        expect(find.byKey(const Key('recalc_progress')), findsNothing);
        _expectEnabledButton(const Key('recalc_confirm'), t.button);
        _expectEnabledButton(const Key('recalc_decline'), t.decline);

        // Ein weiteres Angebot setzt die Meldung zurück.
        await _offerNow(tester, max: 175);
        await tester.pumpAndSettle();
        expect(dialog, findsOneWidget);
        expect(status, findsNothing);
      });
    }

    testWidgets('Neu berechnen gelingt, während ein Angebot ankommt: '
        'Karte des Angebots ohne Status', (tester) async {
      final gate = _Gate();
      final (d, ids) = await _startUncomputable(tester, gate: gate);
      await _openSettings(tester);
      final hold = gate.hold = Completer<void>();
      await tester.tap(find.byKey(const Key('recalc_uncomputable_confirm')));
      await tester.pump();
      await _offerNow(tester);
      hold.complete();
      gate.hold = null;
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      for (final id in ids) {
        expect(gate.runWrites[id], 1, reason: 'Lauf $id');
      }
      expect(await _failureCounts(d), isEmpty);
      expect(find.byKey(const Key('recalc_dialog')), findsOneWidget);
      expect(find.byKey(const Key('recalc_uncomputable')), findsNothing);
      expect(find.byKey(const Key('recalc_status')), findsNothing);
      expect(find.byKey(const Key('recalc_progress')), findsNothing);
    });
  });
}
