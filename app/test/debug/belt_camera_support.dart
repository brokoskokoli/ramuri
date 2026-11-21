import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/debug/debug_test_ppg_camera.dart';
import 'package:running_app/debug/debug_test_sensor.dart';

/// Ergebnis eines gemeinsamen Laufs von Fake-Kamera und Test-Gurt.
typedef BeltCameraRun = ({
  List<PpgFrame> frames,
  List<HeartRateReading> readings,
});

/// Takt des Test-Gurts in den Tests (künstliche Zeit), wie im E2E (Standard 1 s).
const beltTakt = Duration(seconds: 1);

/// Lässt Fake-Kamera (Szenario `goodPulse`, Zeitraffer [speed]) und Test-Gurt
/// gemeinsam in künstlicher Zeit laufen (testWidgets = FakeAsync, keine
/// Wanduhr): Die Kamera-Wanduhr steht, je Takt der Kamera kommt genau ein Bild.
/// [follow] schaltet die RR-Art „passend zur Fake-Kamera“ ein.
Future<BeltCameraRun> runCameraWithBelt(
  WidgetTester tester, {
  required bool follow,
  bool sendRr = true,
  double speed = 30,
}) async {
  final cam = DebugTestPpgCamera(speed: speed, wallClock: () => Duration.zero);
  final sensor = DebugTestSensor(
    FakeClock(DateTime.utc(2030)),
    interval: beltTakt,
    sendRr: sendRr,
  )..rrFollowsPpgCamera = follow ? cam : null;
  final readings = <HeartRateReading>[];
  final sub = sensor.connect('fake-gurt-1').listen((e) {
    if (e is HeartRateReading) readings.add(e);
  });
  final events = <PpgCameraEvent>[];
  var done = false;
  cam.start().listen(events.add, onDone: () => done = true);
  while (!done) {
    await tester.pump(beltTakt);
  }
  // Ein Takt nach dem Ende der Aufnahme.
  await tester.pump(beltTakt);
  // Abmelden ohne await: die Zukunft von cancel() stammt nicht aus der
  // künstlichen Zone und würde dort nie fertig; pump() führt es aus.
  unawaited(sub.cancel());
  await tester.pump();
  return (
    frames: [for (final e in events.whereType<PpgCameraFrame>()) e.frame],
    readings: readings,
  );
}

/// Pakete mit RR, wie sie der Recorder der Morgenmessung speichert.
List<RrPacket> rrPackets(List<HeartRateReading> readings) => [
  for (final r in readings)
    if (r.rrIntervals.isNotEmpty)
      RrPacket(time: r.time, source: r.deviceId, intervals: r.rrIntervals),
];
