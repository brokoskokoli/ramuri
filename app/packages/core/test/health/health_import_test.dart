import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:test/test.dart';

/// Attrappe des Ports: zählt Aufrufe, liefert vorgegebene Sätze je Art.
class _Port implements HealthConnectPort {
  HealthSdkStatus status = HealthSdkStatus.available;
  Set<HealthDataKind> granted = {...HealthDataKind.values};
  final data = <HealthDataKind, List<HealthRecord>>{};
  final reads = <HealthDataKind>[];
  final windows = <(DateTime, DateTime)>[];
  int statusCalls = 0;
  int grantedCalls = 0;
  Object? failWith;

  @override
  Future<HealthSdkStatus> sdkStatus() async {
    statusCalls++;
    return status;
  }

  @override
  Future<Set<HealthDataKind>> grantedKinds() async {
    grantedCalls++;
    return granted;
  }

  @override
  Future<Set<HealthDataKind>> requestPermissions(
    Set<HealthDataKind> kinds,
  ) async => granted;

  @override
  Future<bool> openInstall() async => false;
  @override
  Future<HealthPage> readPage({
    required HealthDataKind kind,
    required DateTime from,
    required DateTime to,
    String? pageToken,
    int? pageSize,
  }) async {
    reads.add(kind);
    windows.add((from, to));
    if (failWith != null) throw failWith!;
    return HealthPage(data[kind] ?? const [], null);
  }
}

final _t0 = DateTime.utc(2026, 11, 10, 8);

HealthRecord _value(
  HealthDataKind k,
  String id,
  double v, {
  String origin = 'app.a',
}) => HealthRecord(
  kind: k,
  id: id,
  origin: origin,
  start: _t0,
  end: _t0,
  value: v,
);

HealthRecord _sleep(String id) => HealthRecord(
  kind: HealthDataKind.sleep,
  id: id,
  origin: 'app.a',
  start: _t0.subtract(const Duration(hours: 8)),
  end: _t0,
);

HealthRecord _exercise(String id) => HealthRecord(
  kind: HealthDataKind.exercise,
  id: id,
  origin: 'app.a',
  start: _t0.subtract(const Duration(hours: 1)),
  end: _t0,
  exerciseType: 56,
);

void main() {
  late _Port port;
  late FakeHealthImportStore store;
  late ConsentService consents;
  late FakeClock clock;
  late HealthImportService svc;

  Future<void> grantAll() async {
    for (final k in HealthDataKind.values) {
      await consents.grant(healthSourceKey(k));
    }
  }

  setUp(() {
    port = _Port();
    store = FakeHealthImportStore();
    clock = FakeClock(_t0);
    consents = ConsentService(_Consents(), clock);
    svc = HealthImportService(
      port: port,
      store: store,
      consents: consents,
      clock: clock,
    );
  });

  test('ohne Einwilligung kein Port-Lesen und kein Speichern', () async {
    port.data[HealthDataKind.sleep] = [_sleep('s1')];
    final r = await svc.run(HealthImportTrigger.manual);
    expect(r.status, HealthImportStatus.done);
    expect(port.reads, isEmpty);
    expect(store.upsertCalls, 0);
    expect(
      r.kinds.values.every((k) => k.status == HealthKindStatus.notConsented),
      isTrue,
    );
  });

  test('Einwilligung einer Art liest keine andere', () async {
    await consents.grant(healthSourceKey(HealthDataKind.sleep));
    port.data[HealthDataKind.sleep] = [_sleep('s1')];
    port.data[HealthDataKind.hrvRmssd] = [
      _value(HealthDataKind.hrvRmssd, 'h1', 50),
    ];
    final r = await svc.run(HealthImportTrigger.manual);
    expect(port.reads, [HealthDataKind.sleep]);
    expect(await store.count(HealthDataKind.sleep), 1);
    expect(await store.count(HealthDataKind.hrvRmssd), 0);
    expect(
      r.kinds[HealthDataKind.hrvRmssd]!.status,
      HealthKindStatus.notConsented,
    );
  });

  test(
    'Recht fehlt trotz Einwilligung: nichts lesen, Löschfrage offen',
    () async {
      await grantAll();
      port.granted = {...HealthDataKind.values}..remove(HealthDataKind.sleep);
      port.data[HealthDataKind.sleep] = [_sleep('s1')];
      final r = await svc.run(HealthImportTrigger.manual);
      expect(port.reads, isNot(contains(HealthDataKind.sleep)));
      expect(
        r.kinds[HealthDataKind.sleep]!.status,
        HealthKindStatus.permissionMissing,
      );
      expect(
        await consents.isDeleteQuestionOpen(
          healthSourceKey(HealthDataKind.sleep),
        ),
        isTrue,
      );
      expect(
        await consents.isDeleteQuestionOpen(
          healthSourceKey(HealthDataKind.hrvRmssd),
        ),
        isFalse,
      );
      // Die Einwilligung selbst bleibt unberührt.
      expect(
        await consents.isGranted(healthSourceKey(HealthDataKind.sleep)),
        isTrue,
      );
    },
  );

  test('Recht fehlt, aber keine Einwilligung: keine Löschfrage', () async {
    port.granted = {};
    await svc.run(HealthImportTrigger.manual);
    for (final k in HealthDataKind.values) {
      expect(await consents.isDeleteQuestionOpen(healthSourceKey(k)), isFalse);
    }
  });

  test('Rechte und Status werden vor jedem Lauf frisch geprüft', () async {
    await grantAll();
    await svc.run(HealthImportTrigger.manual);
    await svc.run(HealthImportTrigger.manual);
    expect(port.statusCalls, 2);
    expect(port.grantedCalls, 2);
  });

  test('Health Connect nicht verfügbar: nichts gelesen', () async {
    await grantAll();
    for (final s in [
      HealthSdkStatus.unavailable,
      HealthSdkStatus.updateRequired,
    ]) {
      port.status = s;
      final r = await svc.run(HealthImportTrigger.manual);
      expect(r.status, HealthImportStatus.unavailable);
    }
    expect(port.reads, isEmpty);
    expect(port.grantedCalls, 0);
  });

  test('Sperre 15 min; Jetzt abrufen umgeht sie', () async {
    await grantAll();
    expect(
      (await svc.run(HealthImportTrigger.appStart)).status,
      HealthImportStatus.done,
    );
    clock.advance(const Duration(minutes: 14, seconds: 59));
    expect(
      (await svc.run(HealthImportTrigger.todayOpened)).status,
      HealthImportStatus.throttled,
    );
    expect(
      (await svc.run(HealthImportTrigger.manual)).status,
      HealthImportStatus.done,
    );
    // Der manuelle Lauf setzt die Sperre neu.
    clock.advance(const Duration(minutes: 14));
    expect(
      (await svc.run(HealthImportTrigger.todayOpened)).status,
      HealthImportStatus.throttled,
    );
    clock.advance(const Duration(minutes: 1));
    expect(
      (await svc.run(HealthImportTrigger.todayOpened)).status,
      HealthImportStatus.done,
    );
  });

  test('Wiederholung: Upsert ohne Duplikate', () async {
    await grantAll();
    port.data[HealthDataKind.sleep] = [_sleep('s1')];
    port.data[HealthDataKind.hrvRmssd] = [
      _value(HealthDataKind.hrvRmssd, 'h1', 50),
      _value(HealthDataKind.hrvRmssd, 'h2', 60),
    ];
    port.data[HealthDataKind.exercise] = [_exercise('e1')];
    await svc.run(HealthImportTrigger.manual);
    await svc.run(HealthImportTrigger.manual);
    expect(await store.count(HealthDataKind.sleep), 1);
    expect(await store.count(HealthDataKind.hrvRmssd), 2);
    expect(await store.count(HealthDataKind.exercise), 1);
  });

  test(
    'zweites Fenster beginnt nach dem ersten Lesen, nie vor 30 Tagen',
    () async {
      await consents.grant(healthSourceKey(HealthDataKind.sleep));
      await svc.run(HealthImportTrigger.manual);
      expect(port.windows.last.$1, _t0.subtract(const Duration(days: 30)));
      clock.advance(const Duration(days: 5));
      await svc.run(HealthImportTrigger.manual);
      expect(port.windows.last.$1, _t0.subtract(const Duration(days: 2)));
    },
  );

  test('Werte außerhalb PAR-162 und PAR-017 werden verworfen', () async {
    await grantAll();
    port.data[HealthDataKind.hrvRmssd] = [
      _value(HealthDataKind.hrvRmssd, 'ok1', 1),
      _value(HealthDataKind.hrvRmssd, 'ok2', 200),
      _value(HealthDataKind.hrvRmssd, 'lo', 0.5),
      _value(HealthDataKind.hrvRmssd, 'hi', 200.5),
      _value(HealthDataKind.hrvRmssd, 'nan', double.nan),
    ];
    port.data[HealthDataKind.restingHeartRate] = [
      _value(HealthDataKind.restingHeartRate, 'r1', 30),
      _value(HealthDataKind.restingHeartRate, 'r2', 120),
      _value(HealthDataKind.restingHeartRate, 'r3', 29),
      _value(HealthDataKind.restingHeartRate, 'r4', 121),
    ];
    final r = await svc.run(HealthImportTrigger.manual);
    expect(r.kinds[HealthDataKind.hrvRmssd]!.stored, 2);
    expect(r.kinds[HealthDataKind.hrvRmssd]!.rejected, 3);
    expect(r.kinds[HealthDataKind.restingHeartRate]!.stored, 2);
    expect(r.kinds[HealthDataKind.restingHeartRate]!.rejected, 2);
    expect(store.records(HealthDataKind.hrvRmssd).map((x) => x.id).toSet(), {
      'ok1',
      'ok2',
    });
  });

  test('Pulsverlauf nur mit eigener Einwilligung für Puls', () async {
    await consents.grant(healthSourceKey(HealthDataKind.exercise));
    port.data[HealthDataKind.exercise] = [_exercise('e1')];
    port.data[HealthDataKind.heartRate] = [
      HealthRecord(
        kind: HealthDataKind.heartRate,
        id: 'p1',
        origin: 'app.a',
        start: _t0,
        end: _t0,
        samples: [HealthHeartRateSample(_t0, 140)],
      ),
    ];
    await svc.run(HealthImportTrigger.manual);
    expect(port.reads, [HealthDataKind.exercise]);
    expect((await store.exerciseHeartRate('e1')), isEmpty);

    await consents.grant(healthSourceKey(HealthDataKind.heartRate));
    final r = await svc.run(HealthImportTrigger.manual);
    expect(r.kinds[HealthDataKind.heartRate]!.stored, 1);
    expect((await store.exerciseHeartRate('e1')), hasLength(1));
  });

  test('Sperre gilt über einen Neustart; Jetzt abrufen umgeht sie', () async {
    await grantAll();
    final stored = await FakeStorage().open(Uint8List(32));
    HealthImportService fresh() => HealthImportService(
      port: port,
      store: store,
      consents: consents,
      clock: clock,
      settings: stored.settings,
    );
    expect(
      (await fresh().run(HealthImportTrigger.appStart)).status,
      HealthImportStatus.done,
    );
    // Neuer Dienst = neuer Prozess: kein Stand im Arbeitsspeicher, auch die
    // monotone Uhr beginnt neu.
    clock.advance(const Duration(minutes: 14, seconds: 59));
    final restarted = fresh();
    final reads = port.reads.length;
    expect(
      (await restarted.run(HealthImportTrigger.appStart)).status,
      HealthImportStatus.throttled,
    );
    expect(port.reads.length, reads);
    expect(
      (await restarted.run(HealthImportTrigger.manual)).status,
      HealthImportStatus.done,
    );
    // Der manuelle Lauf hat den Zeitpunkt erneuert.
    clock.advance(const Duration(minutes: 14));
    expect(
      (await fresh().run(HealthImportTrigger.todayOpened)).status,
      HealthImportStatus.throttled,
    );
    clock.advance(const Duration(minutes: 1));
    expect(
      (await fresh().run(HealthImportTrigger.todayOpened)).status,
      HealthImportStatus.done,
    );
  });

  test(
    'Merker der Sperre: unlesbar oder in der Zukunft sperrt nicht',
    () async {
      await grantAll();
      for (final v in ['kaputt', '${_t0.millisecondsSinceEpoch + 60000}']) {
        final stored = await FakeStorage().open(Uint8List(32));
        await stored.settings.set(
          HealthImportService.lastImportKey,
          v,
          at: _t0,
        );
        final s = HealthImportService(
          port: port,
          store: store,
          consents: consents,
          clock: clock,
          settings: stored.settings,
        );
        expect(
          (await s.run(HealthImportTrigger.appStart)).status,
          HealthImportStatus.done,
        );
      }
    },
  );

  test('ohne Einwilligung oder Recht bleibt der Speicher unberührt', () async {
    final stored = await FakeStorage().open(Uint8List(32));
    HealthImportService build() => HealthImportService(
      port: port,
      store: store,
      consents: consents,
      clock: clock,
      settings: stored.settings,
    );
    await build().run(HealthImportTrigger.appStart);
    // Eingewilligt, aber ohne Recht in Health Connect: auch nichts gelesen.
    await grantAll();
    port.granted = {};
    await build().run(HealthImportTrigger.appStart);
    expect(await stored.settings.all(), isEmpty);
    port.granted = {HealthDataKind.sleep};
    await build().run(HealthImportTrigger.appStart);
    expect(
      await stored.settings.all(),
      contains(HealthImportService.lastImportKey),
    );
  });

  test('Merker der Sperre liegt nicht im Archiv', () {
    expect(
      archiveExcludedSettingKeys,
      contains(HealthImportService.lastImportKey),
    );
  });

  test('Widerruf während des Lesens: nichts gespeichert', () async {
    await consents.grant(healthSourceKey(HealthDataKind.sleep));
    port.data[HealthDataKind.sleep] = [_sleep('s1')];
    final revoking = _RevokingPort(port, () async {
      await consents.revoke(healthSourceKey(HealthDataKind.sleep));
    });
    final s = HealthImportService(
      port: revoking,
      store: store,
      consents: consents,
      clock: clock,
    );
    final r = await s.run(HealthImportTrigger.manual);
    expect(
      r.kinds[HealthDataKind.sleep]!.status,
      HealthKindStatus.revokedWhileReading,
    );
    expect(await store.count(HealthDataKind.sleep), 0);
  });

  test(
    'Widerruf des Pulsverlaufs während des Lesens: nichts gespeichert',
    () async {
      await consents.grant(healthSourceKey(HealthDataKind.exercise));
      await consents.grant(healthSourceKey(HealthDataKind.heartRate));
      port.data[HealthDataKind.exercise] = [_exercise('e1')];
      port.data[HealthDataKind.heartRate] = [
        HealthRecord(
          kind: HealthDataKind.heartRate,
          id: 'p1',
          origin: 'app.a',
          start: _t0,
          end: _t0,
          samples: [HealthHeartRateSample(_t0, 140)],
        ),
      ];
      final revoking = _RevokingPort(port, () async {
        await consents.revoke(healthSourceKey(HealthDataKind.heartRate));
      }, onlyKind: HealthDataKind.heartRate);
      final s = HealthImportService(
        port: revoking,
        store: store,
        consents: consents,
        clock: clock,
      );
      final r = await s.run(HealthImportTrigger.manual);
      expect(
        r.kinds[HealthDataKind.heartRate]!.status,
        HealthKindStatus.revokedWhileReading,
      );
      expect(await store.exerciseHeartRate('e1'), isEmpty);
    },
  );

  test('Fehler beim Lesen: Art scheitert, andere laufen weiter', () async {
    await grantAll();
    port.failWith = const HealthReadException(HealthReadError.busy);
    var r = await svc.run(HealthImportTrigger.manual);
    expect(r.kinds[HealthDataKind.sleep]!.status, HealthKindStatus.failed);
    expect(port.reads.toSet().length, greaterThan(1));
    port.reads.clear();
    port.failWith = const HealthReadException(HealthReadError.rateLimited);
    r = await svc.run(HealthImportTrigger.manual);
    expect(port.reads, hasLength(1)); // Rate-Limit: Rest wird nicht versucht.
    port.failWith = const HealthReadException(
      HealthReadError.permissionMissing,
    );
    r = await svc.run(HealthImportTrigger.manual);
    expect(
      r.kinds[HealthDataKind.sleep]!.status,
      HealthKindStatus.permissionMissing,
    );
    expect(
      await consents.isDeleteQuestionOpen(
        healthSourceKey(HealthDataKind.sleep),
      ),
      isTrue,
    );
  });

  test(
    'Einwilligung und Löschfrage stehen nicht im Archiv-Rahmen der Quellen',
    () async {
      expect(healthSourceKey(HealthDataKind.hrvRmssd), 'health.hrv_rmssd');
      expect(deleteQuestionKey('health.sleep'), 'health.sleep.delete_question');
      await consents.grant(healthSourceKey(HealthDataKind.sleep));
      expect(await consents.isGranted(mapProviderSourceKey), isFalse);
    },
  );

  test('ArchiveRestoreService.isEmpty kennt Importdaten', () async {
    final storage = FakeStorage();
    final session = await storage.open(Uint8List(32));
    expect(await ArchiveRestoreService.isEmpty(session), isTrue);
    final health = (session as HealthStorage).health;
    await health.upsertSleep([_sleep('s1')]);
    expect(await ArchiveRestoreService.isEmpty(session), isFalse);
    await health.deleteKind(HealthDataKind.sleep);
    expect(await ArchiveRestoreService.isEmpty(session), isTrue);
  });
}

class _Consents implements ConsentStore {
  final data = <String, ConsentState>{};
  @override
  Future<ConsentState?> get(String k) async => data[k];
  @override
  Future<Map<String, ConsentState>> all() async => data;
  @override
  Future<void> set(String k, ConsentState s, {required DateTime at}) async =>
      data[k] = s;
}

class _RevokingPort implements HealthConnectPort {
  _RevokingPort(this._inner, this._onRead, {this.onlyKind});
  final _Port _inner;
  final HealthDataKind? onlyKind;
  final Future<void> Function() _onRead;

  @override
  Future<HealthSdkStatus> sdkStatus() => _inner.sdkStatus();
  @override
  Future<Set<HealthDataKind>> grantedKinds() => _inner.grantedKinds();
  @override
  Future<Set<HealthDataKind>> requestPermissions(Set<HealthDataKind> k) =>
      _inner.requestPermissions(k);
  @override
  Future<bool> openInstall() async => false;
  @override
  Future<HealthPage> readPage({
    required HealthDataKind kind,
    required DateTime from,
    required DateTime to,
    String? pageToken,
    int? pageSize,
  }) async {
    final p = await _inner.readPage(kind: kind, from: from, to: to);
    if (onlyKind == null || onlyKind == kind) await _onRead();
    return p;
  }
}
