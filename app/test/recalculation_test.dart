import 'dart:async';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_harness.dart';

final _key = Uint8List.fromList(List.filled(32, 7));
const _metersPerDegree = earthRadiusMeters * 3.141592653589793 / 180;

/// Werte, deren Tausch sich steuern lässt: Fehler oder Warten.
class _Gate {
  bool fail = false;
  Completer<void>? hold;
  int swaps = 0;
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
  Future<void> writeAll({
    Map<ValueOwner, List<ComputedValue>> create = const {},
    Map<ValueOwner, List<ComputedValue>> swap = const {},
  }) async {
    gate.swaps++;
    await gate.hold?.future;
    if (gate.fail) throw const StorageException(StorageFailure.failed);
    return inner.writeAll(create: create, swap: swap);
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
  SettingsStore get settings => inner.settings;
  @override
  KnownDeviceStore get devices => inner.devices;
  @override
  ConsentStore get consents => inner.consents;
  @override
  Future<void> deleteRun(int runId) => inner.deleteRun(runId);
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
Future<void> _seed(Device d) async {
  final s = await d.storage.open(_key);
  await s.profile.save(
    const ProfileRecord(maxHeartRateBpm: 190, restingHeartRateBpm: 60),
  );
  final calc = ValueCalculationService(session: s, clock: d.clock);
  for (final start in [
    DateTime.utc(2026, 5, 10, 8),
    DateTime.utc(2026, 5, 17, 8),
  ]) {
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
    await calc.calculateAfterRun(run.id);
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
  await tester.tap(find.byKey(const Key('home_profile')));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('profile_max')), '180');
  await tester.tap(find.byKey(const Key('profile_save')));
  await tester.pumpAndSettle();
  await tester.tap(find.byType(BackButton));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('home_settings')));
  await tester.pumpAndSettle();
}

Future<Device> _start(
  WidgetTester tester, {
  Locale locale = const Locale('de'),
  _Gate? gate,
}) async {
  final d = Device();
  await _seed(d);
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

  testWidgets('Profiländerung ohne Einfluss auf die Basis bietet nichts an', (
    tester,
  ) async {
    await _start(tester);
    await tester.tap(find.byKey(const Key('home_profile')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('profile_weight')), '70');
    await tester.tap(find.byKey(const Key('profile_save')));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
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
    expect(find.textContaining('Neuberechnet: 2 Läufe'), findsOneWidget);
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
      expect(await _dump(d.session), before);
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
      tester.view.physicalSize = const Size(411, 914);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(const Key('recalc_confirm')));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('recalc_progress')), findsOneWidget);
      expect(find.textContaining('Please wait'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('recalc_confirm')))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(const Key('recalc_decline')))
            .onPressed,
        isNull,
      );
      // Zurück ist gesperrt.
      await tester.tap(find.byType(BackButton));
      await tester.pump();
      expect(find.byKey(const Key('recalc_dialog')), findsOneWidget);
      expect(tester.takeException(), isNull);

      gate.hold!.complete();
      await tester.pumpAndSettle();
      expect(find.textContaining('Recalculated: 2 runs'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
