import 'package:adapters/adapters.dart';
import 'package:core/core.dart';
import 'package:drift/native.dart';
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
        for (final s in store.records(HealthDataKind.sleep)) sleepSessionOf(s),
      ];
      // Die Debug-Quelle legt das Aufwachen auf 06:30 UTC; Ortstag hier UTC.
      final main = p.mainSleep(
        sessions,
        now,
        dayStart: DateTime.utc(2026, 11, 14),
      )!;
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

  test(
    'Debug-Quelle durch den Import in den echten Store: alle Arten > 0',
    () async {
      final hc = DebugTestHealthConnect(now: () => now);
      await hc.requestPermissions(HealthDataKind.values.toSet());
      final clock = FakeClock(now);
      final consents = ConsentService(_Consents(), clock);
      for (final k in HealthDataKind.values) {
        await consents.grant(healthSourceKey(k));
      }
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final store = DriftHealthStore(db);
      final r = await HealthImportService(
        port: hc,
        store: store,
        consents: consents,
        clock: clock,
      ).run(HealthImportTrigger.manual);
      expect(r.status, HealthImportStatus.done);
      for (final k in HealthDataKind.values) {
        expect(
          r.kinds[k]!.status,
          isNot(HealthKindStatus.failed),
          reason: k.key,
        );
        // Pulsverlauf liegt je Training, nicht je Art; alle anderen Arten haben Zeilen.
        if (k != HealthDataKind.heartRate) {
          expect(await store.count(k), greaterThan(0), reason: k.key);
        }
      }
    },
  );

  // Der HRV-Wert 20 min nach dem Ende der Nacht (06:30 UTC) liegt vor 06:50 UTC in der Zukunft
  // und wird nicht gelesen: kein Fehler, aber 11 statt 12 gespeicherte Werte (E2E-Befund WP32).
  for (final (at, expected) in [
    (DateTime.utc(2026, 11, 14, 5, 21), 11),
    (DateTime.utc(2026, 11, 14, 9), 12),
  ]) {
    test('HRV-Werte der Debug-Quelle um $at: $expected', () async {
      final hc = DebugTestHealthConnect(now: () => at);
      await hc.requestPermissions(HealthDataKind.values.toSet());
      final clock = FakeClock(at);
      final consents = ConsentService(_Consents(), clock);
      await consents.grant(healthSourceKey(HealthDataKind.hrvRmssd));
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final store = DriftHealthStore(db);
      await HealthImportService(
        port: hc,
        store: store,
        consents: consents,
        clock: clock,
      ).run(HealthImportTrigger.manual);
      expect(await store.count(HealthDataKind.hrvRmssd), expected);
    });
  }

  // VO2max und Training der Debug-Quelle liegen nie in der Zukunft: um 00:04 UTC lag der Wert bei
  // 02:00 UTC hinter "jetzt" und wurde nicht gelesen (E2E-Lauf 43655339912, Health Connect 1/2).
  for (final at in [
    DateTime.utc(2026, 11, 15, 0, 4),
    DateTime.utc(2026, 11, 15, 1, 59),
    DateTime.utc(2026, 11, 14, 9),
  ]) {
    test('VO2max und Training der Debug-Quelle um $at je 1 Wert', () async {
      final hc = DebugTestHealthConnect(now: () => at);
      await hc.requestPermissions(HealthDataKind.values.toSet());
      final clock = FakeClock(at);
      final consents = ConsentService(_Consents(), clock);
      for (final k in [HealthDataKind.vo2Max, HealthDataKind.exercise]) {
        await consents.grant(healthSourceKey(k));
      }
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final store = DriftHealthStore(db);
      await HealthImportService(
        port: hc,
        store: store,
        consents: consents,
        clock: clock,
      ).run(HealthImportTrigger.manual);
      expect(await store.count(HealthDataKind.vo2Max), 1);
      expect(await store.count(HealthDataKind.exercise), 1);
    });
  }

  // Kurz nach Mitternacht UTC: kein Satz der Debug-Quelle liegt nach "jetzt", und HRV, Ruhepuls und VO2max der
  // Nacht davor sind schon vollständig da (bei den alten Versätzen fehlten sie bis 01:30 bzw. 02:00 UTC).
  for (final at in [
    DateTime.utc(2026, 11, 15),
    DateTime.utc(2026, 11, 15, 0, 30),
    DateTime.utc(2026, 11, 15, 1, 59),
  ]) {
    test('kein Zeitstempel der Debug-Quelle nach $at', () async {
      final hc = DebugTestHealthConnect(now: () => at);
      await hc.requestPermissions(HealthDataKind.values.toSet());
      for (final k in HealthDataKind.values) {
        // Lesefenster bewusst über "jetzt" hinaus: die Quelle selbst darf nichts Späteres liefern.
        final page = await hc.readPage(
          kind: k,
          from: at.subtract(const Duration(days: 30)),
          to: at.add(const Duration(days: 2)),
        );
        expect(page.records, isNotEmpty, reason: k.key);
        for (final r in page.records) {
          final times = [
            r.start,
            r.end,
            for (final st in r.stages) ...[st.start, st.end],
            for (final hr in r.samples) hr.time,
          ];
          for (final x in times) {
            expect(x.isAfter(at), isFalse, reason: '${r.id}: $x nach $at');
          }
        }
      }
    });

    test(
      'HRV, Ruhepuls und VO2max der Debug-Quelle um $at vollständig',
      () async {
        final hc = DebugTestHealthConnect(now: () => at);
        await hc.requestPermissions(HealthDataKind.values.toSet());
        final clock = FakeClock(at);
        final consents = ConsentService(_Consents(), clock);
        for (final k in HealthDataKind.values) {
          await consents.grant(healthSourceKey(k));
        }
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        final store = DriftHealthStore(db);
        final r = await HealthImportService(
          port: hc,
          store: store,
          consents: consents,
          clock: clock,
        ).run(HealthImportTrigger.manual);
        expect(r.status, HealthImportStatus.done);
        // HRV: 3 Nächte × 3 Werte in der Schlafphase + Rückfallwerte der zwei Nächte davor (der von heute liegt
        // erst um 06:50 UTC); je Nacht zwei ungültige verworfen.
        expect(await store.count(HealthDataKind.hrvRmssd), 11);
        expect(r.kinds[HealthDataKind.hrvRmssd]!.rejected, 6);
        // Ruhepuls: ein gültiger Wert je Tag, der ungültige je Tag verworfen.
        expect(await store.count(HealthDataKind.restingHeartRate), 3);
        expect(r.kinds[HealthDataKind.restingHeartRate]!.rejected, 3);
        expect(await store.count(HealthDataKind.vo2Max), 1);
        // Die Nacht vor heute endet erst um 06:30 UTC und fehlt noch.
        expect(await store.count(HealthDataKind.sleep), 4);
      },
    );
  }
}
