import 'dart:io';

import 'package:adapters/adapters.dart';
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

final DateTime t0 = DateTime.utc(2030, 1, 1, 12);

LocationSample fix(int sec, double north, {double? speed}) => LocationSample(
  time: t0.add(Duration(seconds: sec)),
  latitude: 10 + north / 111195,
  longitude: 20,
  accuracyMeters: 5,
  speedMetersPerSecond: speed,
);

/// RunRecorder gegen die echte verschlüsselte Datenbank: ein beendeter Lauf
/// mit Lücke ist über den Speicherzugriff lesbar (FR-0028, FR-0194, K12).
void main() {
  late Directory dir;
  setUp(() => dir = tempDir());
  tearDown(() => dir.deleteSync(recursive: true));

  test(
    'Lauf mit GPS-Lücke, Pause und Runde wird vollständig gespeichert',
    () async {
      final storage = EncryptedStorage('${dir.path}/app.db');
      final s = await storage.open(testKey());
      addTearDown(s.close);
      final clock = FakeClock(t0);
      final rec = RunRecorder(
        clock: clock,
        runs: s.runs,
        rawData: s.rawData,
        markers: s.markers,
      );
      await rec.start();
      for (var i = 1; i <= 5; i++) {
        clock.advance(const Duration(seconds: 1));
        rec.addPosition(fix(i, i * 3.0, speed: i == 2 ? null : 3));
      }
      await rec.lap();
      clock.advance(const Duration(seconds: 20)); // Lücke
      rec.tick();
      clock.advance(const Duration(seconds: 1));
      rec.addPosition(fix(26, 15.0, speed: 0));
      await rec.pause();
      clock.advance(const Duration(seconds: 5));
      await rec.resume();
      await rec.finish();

      final id = rec.runId!;
      final run = (await s.runs.get(id))!;
      expect(run.state, RunState.finished);
      expect(run.endedAt, t0.add(const Duration(seconds: 31)));
      final raw = await s.rawData.read(id);
      expect(raw.positions, hasLength(6));
      final speeds = raw.positions.map((p) => p.value.speedMetersPerSecond);
      expect(speeds, [3, null, 3, 3, 3, 0]);
      final gaps = await s.markers.gaps(id);
      expect(gaps.map((g) => g.kind), [
        RunGapKind.positionLoss,
        RunGapKind.manualPause,
      ]);
      expect(gaps.every((g) => g.end != null), isTrue);
      expect((await s.markers.laps(id)).single.index, 1);
    },
  );
}
