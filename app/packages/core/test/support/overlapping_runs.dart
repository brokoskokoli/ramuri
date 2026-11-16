import 'dart:typed_data';

import 'package:core/core.dart';

/// Zwei Läufe, die sich nach einem Rücksprung der Wanduhr überlappen
/// (ADR-0005 Punkt 7 „Zeitbasis“). Synthetische Daten, aufgezeichnet mit dem
/// echten [RunRecorder] auf [FakeStorage]:
///
/// - Lauf A startet bei [overlapStart], läuft 20 min; nach 10 min springt die
///   Wanduhr um −10 min. A endet nach Sitzungszeit bei Start + 20 min, die
///   Wanduhr zeigt dann Start + 10 min.
/// - 2 min später (Wanduhr) startet Lauf B und läuft 3 min: B beginnt bei
///   Start + 12 min, also vor dem Ende von A, und endet bei Start + 15 min,
///   ebenfalls vor dem Ende von A.
class OverlappingRuns {
  OverlappingRuns._(this.session, this.clock, this.a, this.b);

  final StorageSession session;
  final FakeClock clock;

  /// Lauf-Ids von A (mit Sprung) und B (danach gestartet).
  final int a;
  final int b;

  Future<StoredRun> runA() async => (await session.runs.get(a))!;
  Future<StoredRun> runB() async => (await session.runs.get(b))!;
}

/// Start von Lauf A (UTC).
final DateTime overlapStart = DateTime.utc(2030, 1, 16, 7);

/// Rücksprung der Wanduhr in Lauf A.
const Duration overlapJump = Duration(minutes: -10);

/// Zeichnet die beiden Läufe auf. [start] legt den Start von A fest,
/// [utcOffsetA] bzw. [utcOffsetB] den lokalen Versatz der Uhr am Ende von A
/// bzw. B. Positionen jede Sekunde mit 3 m/s nach Norden, Puls jede Sekunde
/// mit [bpm].
Future<OverlappingRuns> recordOverlappingRuns({
  DateTime? start,
  Duration utcOffsetA = Duration.zero,
  Duration utcOffsetB = Duration.zero,
  int bpm = 150,
  StorageSession? session,
}) async {
  final s =
      session ??
      await FakeStorage().open(Uint8List.fromList(List.generate(32, (i) => i)));
  final clock = FakeClock(start ?? overlapStart, utcOffset: utcOffsetA);
  var north = 0.0;

  RunRecorder recorder() => RunRecorder(
    clock: clock,
    runs: s.runs,
    rawData: s.rawData,
    markers: s.markers,
    session: RecordingSession(clock: clock),
  );

  Future<void> move(RunRecorder r, int seconds) async {
    for (var i = 0; i < seconds; i++) {
      clock.advance(const Duration(seconds: 1));
      north += 3;
      r.addPosition(
        LocationSample(
          time: clock.now(),
          latitude: 10 + north / 111195,
          longitude: 20,
          accuracyMeters: 5,
        ),
      );
      r.addHeartRate(
        HeartRateReading(
          'strap',
          clock.now(),
          bpm,
          contact: SensorContact.good,
        ),
      );
    }
    await r.flush();
  }

  final ra = recorder();
  _ok(await ra.start());
  await move(ra, 10 * 60);
  clock.set(clock.now().add(overlapJump));
  await move(ra, 10 * 60);
  _ok(await ra.finish());
  final a = ra.runId!;

  clock.advance(const Duration(minutes: 2));
  clock.utcOffset = utcOffsetB;
  final rb = recorder();
  _ok(await rb.start());
  await move(rb, 3 * 60);
  _ok(await rb.finish());
  return OverlappingRuns._(s, clock, a, rb.runId!);
}

void _ok(CommandResult r) {
  if (r != CommandResult.ok) throw StateError('Befehl abgelehnt: $r');
}
