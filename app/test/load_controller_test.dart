import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/statistics/load_controller.dart';
import 'package:running_app/features/statistics/load_view_state.dart';

/// Controller und Ausgabe des Belastungsstands (WP19 C4a), ohne Widgets.
final DateTime _now = DateTime.utc(2030, 3, 1, 12);
final Uint8List _key = Uint8List.fromList(List.generate(32, (i) => i));

ComputedValue _trimp(double value) => ComputedValue(
  key: trimpRunValueKey,
  value: value,
  unit: pointsUnit,
  computedAt: _now,
  measurementCount: 1,
  sources: const [],
  method: 'edwards-trimp',
  methodVersion: 1,
  parameterVersion: 1,
  quality: ValueQuality.good,
);

Future<void> _addRun(
  StorageSession s,
  DateTime end,
  double? trimp, {
  int? rpe,
}) async {
  final run = await s.runs.create(
    startedAt: end.subtract(const Duration(minutes: 30)),
  );
  await s.runs.setState(run.id, RunState.finished, endedAt: end);
  if (trimp != null) {
    await s.values.createOriginals(ValueOwner.run(run.id), [_trimp(trimp)]);
  }
  if (rpe != null) {
    await s.subjective.save(
      run.id,
      RunSubjective(rpe: rpe),
      srpe: SrpeLoad.compute(duration: const Duration(minutes: 30), rpe: rpe),
    );
  }
}

void main() {
  late StorageSession session;
  late FakeClock clock;
  late LoadController controller;
  final changes = _Changes();

  TrainingLoadService service() => TrainingLoadService(
    session: session,
    clock: clock,
    calculation: ValueCalculationService(session: session, clock: clock),
    recalculation: RecalculationService(
      session: session,
      clock: clock,
      calculation: ValueCalculationService(session: session, clock: clock),
    ),
  );

  setUp(() async {
    session = await FakeStorage().open(_key);
    await session.profile.save(
      const ProfileRecord(maxHeartRateBpm: 190, restingHeartRateBpm: 60),
    );
    clock = FakeClock(_now);
  });

  tearDown(() => controller.dispose());

  Future<void> settle() async {
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  test(
    'Ohne Einheiten: geladen, keine Aussage, kein niedriges Niveau',
    () async {
      controller = LoadController(service: service());
      expect(controller.state.phase, LoadPhase.loading);
      await settle();
      final s = controller.state;
      expect(s.phase, LoadPhase.ready);
      expect(s.hasStatement, isFalse);
      expect(s.current, isNull);
      expect(s.days, isEmpty);
      expect(s.factorStatus, LoadFactorStatus.missing);
      expect(s.profile, LoadProfile.edwards);
    },
  );

  test('Mit Läufen: Verlauf, aktuelle Werte, Vorläufigkeit, Kennzeichen, '
      'Grundlage', () async {
    await _addRun(session, DateTime.utc(2030, 2, 25, 8), 60);
    await _addRun(session, DateTime.utc(2030, 2, 26, 8), null); // unbewertet
    await _addRun(session, DateTime.utc(2030, 2, 27, 8), 40);
    controller = LoadController(service: service());
    await settle();
    final s = controller.state;
    expect(s.hasStatement, isTrue);
    expect(s.days.first.day, DateTime.utc(2030, 2, 25));
    expect(s.seriesEnd, DateTime.utc(2030, 2, 28)); // heute leer: gestern
    expect(s.todayEmpty, isTrue);
    expect(s.dataThrough, DateTime.utc(2030, 2, 27));
    expect(s.unratedDays, [DateTime.utc(2030, 2, 26)]);
    expect(s.atlProvisional, isTrue);
    expect(s.ctlProvisionalReasons, contains(LoadProvisionalReason.startup));
    // Vorläufig: keine TSB%-Schwellen.
    expect(s.tsbPercentMean7, isNull);
    expect(s.current!.atl, isNotNull);
    expect(s.factorStatus, LoadFactorStatus.missing);
    expect(s.report!.series.method, trainingLoadMethod);
  });

  test('Neuladen auf Meldung: neuer Nachtrag erscheint', () async {
    await _addRun(session, DateTime.utc(2030, 2, 27, 8), 40);
    controller = LoadController(service: service(), changes: changes);
    await settle();
    expect(controller.state.report!.series.summary.convertedUnits, 0);
    var notified = 0;
    controller.addListener(() => notified++);
    await _addRun(session, DateTime.utc(2030, 2, 28, 8), 70);
    changes.fire();
    await settle();
    expect(controller.state.dataThrough, DateTime.utc(2030, 2, 28));
    expect(notified, greaterThan(0));
  });

  test(
    'Mehrere Anstöße während des Ladens: höchstens ein weiterer Lauf',
    () async {
      await _addRun(session, DateTime.utc(2030, 2, 27, 8), 40);
      controller = LoadController(service: service(), changes: changes);
      changes.fire();
      changes.fire();
      changes.fire();
      await settle();
      expect(controller.state.phase, LoadPhase.ready);
    },
  );

  test('Laden läuft über die Reihe der Neuberechnung (serialize): nicht '
      'parallel zu Bestätigen und Ablehnen', () async {
    await _addRun(session, DateTime.utc(2030, 2, 27, 8), 40);
    final release = Completer<void>();
    var calls = 0;
    Future<T> serialize<T>(Future<T> Function() action) async {
      calls++;
      await release.future;
      return action();
    }

    controller = LoadController(service: service(), serialize: serialize);
    await settle();
    // Die Reihe hält das Laden zurück: noch kein Ergebnis, nichts gelesen.
    expect(calls, 1);
    expect(controller.state.phase, LoadPhase.loading);
    release.complete();
    await settle();
    expect(controller.state.phase, LoadPhase.ready);
    expect(controller.state.dataThrough, DateTime.utc(2030, 2, 27));
  });

  test(
    'Fehler beim Laden: failed, ohne Inhalt; danach erholt sich der Stand',
    () async {
      final broken = _BrokenRuns(session);
      controller = LoadController(
        service: TrainingLoadService(
          session: broken,
          clock: clock,
          calculation: ValueCalculationService(session: session, clock: clock),
          recalculation: RecalculationService(
            session: session,
            clock: clock,
            calculation: ValueCalculationService(
              session: session,
              clock: clock,
            ),
          ),
        ),
      );
      await settle();
      expect(controller.state.phase, LoadPhase.failed);
      expect(controller.state.report, isNull);
      broken.fail = false;
      await controller.reload();
      expect(controller.state.phase, LoadPhase.ready);
      broken.fail = true;
      await controller.reload();
      expect(controller.state.phase, LoadPhase.failed);
    },
  );
}

class _Changes extends ChangeNotifier {
  void fire() => notifyListeners();
}

class _BrokenRuns implements StorageSession {
  _BrokenRuns(this.inner);
  final StorageSession inner;
  bool fail = true;

  @override
  RunStore get runs => fail ? throw StateError('x') : inner.runs;
  @override
  RunMarkerStore get markers => inner.markers;
  @override
  RawDataStore get rawData => inner.rawData;
  @override
  PreprocessingStore get preprocessing => inner.preprocessing;
  @override
  RatedSectionStore get sections => inner.sections;
  @override
  ComputedValueStore get values => inner.values;
  @override
  ProfileStore get profile => inner.profile;
  @override
  SettingsStore get settings => inner.settings;
  @override
  KnownDeviceStore get devices => inner.devices;
  @override
  ConsentStore get consents => inner.consents;
  @override
  RunSubjectiveStore get subjective => inner.subjective;
  @override
  ManualTrainingStore get manualTrainings => inner.manualTrainings;
  @override
  Future<void> deleteRun(int runId) => inner.deleteRun(runId);
  @override
  Future<void> deleteAll() => inner.deleteAll();
  @override
  Future<void> close() => inner.close();
}
