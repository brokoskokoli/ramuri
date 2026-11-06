import 'dart:io';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:test/test.dart';

/// Synthetische Testläufe für den Export (keine echten Daten).
final DateTime xStart = DateTime.utc(2030, 1, 1, 8);
const double xMetersPerDegree = earthRadiusMeters * 3.141592653589793 / 180;

DateTime xAt(num seconds) =>
    xStart.add(Duration(microseconds: (seconds * 1e6).round()));

double xLat(num i) => 10 + i * 3.0 / xMetersPerDegree;
const double xLon = 20.5;
double xEle(num i) => 100.25 + i;
int xBpm(int i) => 140 + i;

/// Sekunden des Hauptlaufs mit Position und Höhe: 0..20 ohne Pause [8, 11) und
/// ohne Positionsverlust [14, 17).
const List<int> xPositionSeconds = [
  0, 1, 2, 3, 4, 5, 6, 7, 11, 12, 13, 17, 18, 19, 20, //
];

/// Sekunden, an denen (um 0,4 s versetzt) Puls kommt; ohne [3, 5) und ohne
/// Pause. Der Wert bei 20,4 s liegt nach dem Laufende.
const List<int> xHeartSeconds = [
  0, 1, 2, 5, 6, 7, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, //
];

Future<StorageSession> xSession() =>
    FakeStorage().open(Uint8List.fromList(List.generate(32, (i) => i)));

/// Hauptlauf (20 s, Ortszeit UTC+1): Runde bei 6 s, manuelle Pause [8, 11),
/// Positionsverlust [14, 17), Pulsverlust [3, 5). Dazu Störwerte, die nicht
/// exportiert werden dürfen: geschätzte Position, verworfener Puls, Position
/// in der Pause, zweite Position in derselben Millisekunde. Höhe bei
/// 18,123456 s ohne Position (Mikrosekunden werden abgeschnitten).
Future<int> seedMainRun(StorageSession s) async {
  final run = await s.runs.create(startedAt: xStart);
  final id = run.id;
  await s.rawData.append(
    id,
    RawBatch(
      positions: [
        for (final i in xPositionSeconds)
          RawPosition(
            time: xAt(i),
            source: 'gps',
            latitude: xLat(i),
            longitude: xLon,
            accuracyMeters: 4,
          ),
        RawPosition(
          time: xAt(1).add(const Duration(microseconds: 300)),
          source: 'gps',
          latitude: 50,
          longitude: 50,
        ),
        RawPosition(
          time: xAt(2.5),
          source: 'gps',
          latitude: 51,
          longitude: 51,
          state: MeasurementState.estimated,
        ),
        RawPosition(time: xAt(9.5), source: 'gps', latitude: 52, longitude: 52),
      ],
      altitudes: [
        for (final i in xPositionSeconds)
          RawAltitude(time: xAt(i), source: 'gps', meters: xEle(i)),
        RawAltitude(time: xAt(18.123456), source: 'gps', meters: 777.5),
      ],
      heartRates: [
        for (final i in xHeartSeconds)
          RawHeartRate(time: xAt(i + 0.4), source: 'strap', bpm: xBpm(i)),
        RawHeartRate(
          time: xAt(6.7),
          source: 'strap',
          bpm: 250,
          state: MeasurementState.discarded,
        ),
      ],
    ),
  );
  await s.markers.addLap(
    id,
    StoredLap(index: 1, markedAt: xAt(6), lapTime: const Duration(seconds: 6)),
  );
  final pause = await s.markers.openGap(id, RunGapKind.manualPause, xAt(8));
  await s.markers.closeGap(pause, xAt(11));
  final loss = await s.markers.openGap(id, RunGapKind.positionLoss, xAt(14));
  await s.markers.closeGap(loss, xAt(17));
  final hrLoss = await s.markers.openGap(id, RunGapKind.heartRateLoss, xAt(3));
  await s.markers.closeGap(hrLoss, xAt(5));
  await s.runs.setState(
    id,
    RunState.finished,
    endedAt: xAt(20),
    endedUtcOffset: const Duration(hours: 1),
  );
  return id;
}

/// Beendeter Lauf von [seconds] s mit den gegebenen Rohwerten.
Future<int> seedRun(
  StorageSession s, {
  int seconds = 10,
  RawBatch batch = const RawBatch(),
  List<(RunGapKind, num, num?)> gaps = const [],
}) async {
  final run = await s.runs.create(startedAt: xStart);
  if (!batch.isEmpty) await s.rawData.append(run.id, batch);
  for (final (kind, from, to) in gaps) {
    final g = await s.markers.openGap(run.id, kind, xAt(from));
    if (to != null) await s.markers.closeGap(g, xAt(to));
  }
  await s.runs.setState(run.id, RunState.finished, endedAt: xAt(seconds));
  return run.id;
}

/// Positionen und Höhen je Sekunde in [from, to], Puls optional.
RawBatch steadyBatch(int from, int to, {bool heartRate = true}) => RawBatch(
  positions: [
    for (var i = from; i <= to; i++)
      RawPosition(
        time: xAt(i),
        source: 'gps',
        latitude: xLat(i),
        longitude: xLon,
      ),
  ],
  altitudes: [
    for (var i = from; i <= to; i++)
      RawAltitude(time: xAt(i), source: 'gps', meters: xEle(i)),
  ],
  heartRates: [
    if (heartRate)
      for (var i = from; i <= to; i++)
        RawHeartRate(time: xAt(i), source: 'strap', bpm: xBpm(i)),
  ],
);

/// Vergleicht [actual] mit `test/export/goldens/<name>`; mit
/// `UPDATE_GOLDENS=1` wird die Datei neu geschrieben.
void expectGolden(String actual, String name) {
  final file = File('test/export/goldens/$name');
  if (Platform.environment['UPDATE_GOLDENS'] == '1') {
    file
      ..createSync(recursive: true)
      ..writeAsStringSync(actual);
  }
  expect(actual, file.readAsStringSync(), reason: 'Golden $name');
}
