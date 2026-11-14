import 'package:core/core.dart';
import 'package:running_app/debug/debug_test_health_connect.dart';
import 'package:flutter_test/flutter_test.dart';

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

void main() {
  final now = DateTime.utc(2026, 11, 14, 9);

  test('ohne Recht: Lesen wirft permissionMissing', () async {
    final hc = DebugTestHealthConnect(now: () => now);
    expect(
      () => hc.readPage(
        kind: HealthDataKind.sleep,
        from: now.subtract(const Duration(days: 30)),
        to: now,
      ),
      throwsA(isA<HealthReadException>()),
    );
  });

  test(
    'Import der Debug-Quelle: Quellen, Verwerfen, Rückfall, Pulsverlauf',
    () async {
      final hc = DebugTestHealthConnect(now: () => now);
      await hc.requestPermissions(HealthDataKind.values.toSet());
      final clock = FakeClock(now);
      final consents = ConsentService(_Consents(), clock);
      for (final k in HealthDataKind.values) {
        await consents.grant(healthSourceKey(k));
      }
      final store = FakeHealthImportStore();
      final r = await HealthImportService(
        port: hc,
        store: store,
        consents: consents,
        clock: clock,
      ).run(HealthImportTrigger.manual);
      expect(r.status, HealthImportStatus.done);
      expect(r.kinds[HealthDataKind.hrvRmssd]!.rejected, 6); // 2 je Nacht
      expect(r.kinds[HealthDataKind.restingHeartRate]!.rejected, 3);
      expect(store.records(HealthDataKind.sleep).map((s) => s.origin).toSet(), {
        'debug.app.a',
        'debug.app.b',
      });
      expect((await store.exerciseHeartRate('debug-exercise-0')), isNotEmpty);

      // Aufbereitung: Hauptschlafphase der Quelle mit Phasen, Rückfall der anderen App.
      const p = HealthProcessing();
      final sessions = [
        for (final s in store.records(HealthDataKind.sleep))
          SleepSession(
            origin: s.origin,
            start: s.start,
            end: s.end,
            stages: [
              for (final st in s.stages)
                SleepStage(
                  kind: SleepStageKind.light,
                  start: st.start,
                  end: st.end,
                ),
            ],
          ),
      ];
      final main = p.mainSleep(sessions, now)!;
      expect(main.origin, 'debug.app.a');
      final samples = [
        for (final v in store.records(HealthDataKind.hrvRmssd))
          HealthSample(time: v.start, value: v.value!, origin: v.origin),
      ];
      final daily = p.hrvDaily(samples, main);
      expect(daily['debug.app.a']!.isFallback, isFalse);
      expect(daily['debug.app.b']!.isFallback, isTrue);
    },
  );
}
