import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:test/test.dart';

// Synthetische Werte (FR-0214, ADR-0011 Punkt 8).
final _key = Uint8List.fromList(List.filled(32, 7));
final _t0 = DateTime.utc(2026, 11, 10, 7, 12);

Future<(StorageSession, ProfileService)> _setup() async {
  final s = await FakeStorage().open(_key);
  return (s, ProfileService(s.profile, FakeClock(_t0), settings: s.settings));
}

/// Einstellungen, deren Schreiben auf Wunsch scheitert.
class _FailingSettings implements SettingsStore {
  _FailingSettings(this.inner);
  final SettingsStore inner;
  bool failSet = false;

  @override
  Future<String?> get(String key) => inner.get(key);

  @override
  Future<Map<String, String>> all() => inner.all();

  @override
  Future<void> set(String key, String value, {required DateTime at}) async {
    if (failSet) throw StateError('Schreiben scheitert');
    await inner.set(key, value, at: at);
  }
}

void main() {
  test('schreiben und lesen: Haltung, Zeitpunkt, Quelle', () async {
    final (s, _) = await _setup();
    expect(await RestingHrOrigin.read(s.settings), isNull);
    await RestingHrOrigin(
      posture: RestingPosture.lying,
      measuredAt: _t0,
    ).write(s.settings, at: _t0);
    final o = (await RestingHrOrigin.read(s.settings))!;
    expect(o.posture, RestingPosture.lying);
    expect(o.measuredAt, _t0);
    expect(o.source, RestingHrSource.camera);
    expect(await s.settings.get('resting_hr.source'), 'camera');
    expect(await s.settings.get('resting_hr.posture'), 'lying');
  });

  test('unlesbarer oder fehlender Teil: keine Herkunft', () async {
    final (s, _) = await _setup();
    await s.settings.set('resting_hr.posture', 'sitting', at: _t0);
    await s.settings.set('resting_hr.measured_at', 'gestern', at: _t0);
    await s.settings.set('resting_hr.source', 'camera', at: _t0);
    expect(await RestingHrOrigin.read(s.settings), isNull);
  });

  test('manuelle Änderung des Ruhepulses entfernt die Herkunft', () async {
    final (s, svc) = await _setup();
    await svc.save(const ProfileRecord(restingHeartRateBpm: 60));
    await RestingHrOrigin(
      posture: RestingPosture.sitting,
      measuredAt: _t0,
    ).write(s.settings, at: _t0);
    await svc.save(const ProfileRecord(restingHeartRateBpm: 58));
    expect(await RestingHrOrigin.read(s.settings), isNull);
    for (final k in const [
      'resting_hr.posture',
      'resting_hr.measured_at',
      'resting_hr.source',
    ]) {
      expect(await s.settings.get(k), '', reason: k);
    }
  });

  test('Ruhepuls leeren entfernt sie ebenfalls', () async {
    final (s, svc) = await _setup();
    await svc.save(const ProfileRecord(restingHeartRateBpm: 60));
    await RestingHrOrigin(
      posture: RestingPosture.sitting,
      measuredAt: _t0,
    ).write(s.settings, at: _t0);
    await svc.save(const ProfileRecord());
    expect(await RestingHrOrigin.read(s.settings), isNull);
  });

  test('anderes Feld geändert, Ruhepuls gleich: Herkunft bleibt', () async {
    final (s, svc) = await _setup();
    await svc.save(const ProfileRecord(restingHeartRateBpm: 60));
    await RestingHrOrigin(
      posture: RestingPosture.sitting,
      measuredAt: _t0,
    ).write(s.settings, at: _t0);
    await svc.save(
      const ProfileRecord(restingHeartRateBpm: 60, birthYear: 1986),
    );
    expect(await RestingHrOrigin.read(s.settings), isNotNull);
  });

  test('abgelehntes Speichern lässt die Herkunft stehen', () async {
    final (s, svc) = await _setup();
    await svc.save(const ProfileRecord(restingHeartRateBpm: 60));
    await RestingHrOrigin(
      posture: RestingPosture.sitting,
      measuredAt: _t0,
    ).write(s.settings, at: _t0);
    final r = await svc.save(const ProfileRecord(restingHeartRateBpm: 5));
    expect(r.saved, isFalse);
    expect(await RestingHrOrigin.read(s.settings), isNotNull);
  });

  test('clear legt ohne Herkunft keine Zeilen an', () async {
    final (s, svc) = await _setup();
    await svc.save(const ProfileRecord(restingHeartRateBpm: 60));
    await svc.save(const ProfileRecord(restingHeartRateBpm: 61));
    expect(await s.settings.all(), isEmpty);
  });

  test('ohne settings bleibt das Verhalten unverändert', () async {
    final s = await FakeStorage().open(_key);
    final svc = ProfileService(s.profile, FakeClock(_t0));
    await RestingHrOrigin(
      posture: RestingPosture.sitting,
      measuredAt: _t0,
    ).write(s.settings, at: _t0);
    await svc.save(const ProfileRecord(restingHeartRateBpm: 58));
    expect(await RestingHrOrigin.read(s.settings), isNotNull);
  });

  test('Entfernen der Herkunft scheitert: Wert bleibt unverändert, nie neuer Wert mit alter Herkunft', () async {
    final s = await FakeStorage().open(_key);
    final settings = _FailingSettings(s.settings);
    final svc = ProfileService(s.profile, FakeClock(_t0), settings: settings);
    await svc.save(const ProfileRecord(restingHeartRateBpm: 60));
    await RestingHrOrigin(
      posture: RestingPosture.sitting,
      measuredAt: _t0,
    ).write(settings, at: _t0);
    settings.failSet = true;
    await expectLater(
      svc.save(const ProfileRecord(restingHeartRateBpm: 58)),
      throwsStateError,
    );
    expect((await s.profile.read()).restingHeartRateBpm, 60);
    expect(await RestingHrOrigin.read(s.settings), isNotNull);
  });
}
