import 'dart:convert';

import 'package:core/core.dart';
import 'package:core/fakes/fake_storage_morning.dart';
import 'package:test/test.dart';

import 'export_support.dart';

const _header =
    'format_version,morning_id,row_type,key,seq,sub,time,value,unit\r\n';

final _t0 = DateTime.utc(2030, 1, 1, 6, 30);

/// Synthetischer Morgen: Kamera und Gurt im selben Zeitfenster
/// (Ruhephase ab 06:28, Messung 06:30 bis 06:31).
MorningMeasurement _m({
  DateTime? at,
  RestingPosture posture = RestingPosture.lying,
  List<double> ibi = const [810.5, double.nan, 805.25],
  double? rmssd = 41.5,
  double? noise,
}) => MorningMeasurement(
  measuredAt: at ?? _t0,
  utcOffset: const Duration(hours: 1),
  posture: posture,
  deviceManufacturer: 'Testhersteller',
  deviceModel: 'Test, "Modell"',
  method: ppgMethod,
  methodVersion: ppgMethodVersion,
  quality: PpgQuality.good,
  restingHrBpm: 58.04,
  rmssdMs: rmssd,
  timingNoiseMs: noise,
  cameraIntervalsMs: ibi,
  beforeValidation: true,
  outsideWindow: false,
);

RrPacket _p(int seconds, List<int> rr) => RrPacket(
  time: DateTime.utc(2030, 1, 1, 6, 28).add(Duration(seconds: seconds)),
  source: 'gurt-1',
  intervals: rr,
);

void main() {
  test('Kopfzeile ohne Morgen, CRLF, kein BOM', () {
    final csv = encodeMorningPairsCsv(const []);
    expect(csv, _header);
    expect(utf8.encode(csv).take(3), isNot([0xEF, 0xBB, 0xBF]));
  });

  test('Golden: ein Morgen mit Kamera und Gurt im selben Fenster', () {
    final csv = encodeMorningPairsCsv([
      MorningPair(
        id: 7,
        measurement: _m(),
        beltPackets: [
          _p(5, [900, 910]),
          _p(7, [915]),
          _p(125, [880, 885, 890]),
        ],
      ),
    ]);
    expectGolden(csv, 'morning_pairs.csv');
  });

  test('ungültiges Kamera-Intervall ist ein leeres Feld, nie NaN', () {
    final csv = encodeMorningPairsCsv([MorningPair(id: 1, measurement: _m())]);
    expect(csv, contains('1,1,camera_ibi,ibi,2,,,,ms\r\n'));
    expect(csv.toLowerCase(), isNot(contains('nan')));
  });

  test('fehlende RMSSD und Zeitrauschen sind leer, nie 0', () {
    final csv = encodeMorningPairsCsv([
      MorningPair(id: 1, measurement: _m(rmssd: null)),
    ]);
    expect(csv, contains('1,1,camera,rmssd,,,,,ms\r\n'));
    expect(csv, contains('1,1,camera,timing_noise,,,,,ms\r\n'));
  });

  test('Sortierung nach Zeitpunkt, dann Id; Feld mit Komma in Anführungen', () {
    final csv = encodeMorningPairsCsv([
      MorningPair(id: 2, measurement: _m(at: _t0.add(const Duration(days: 1)))),
      MorningPair(id: 9, measurement: _m()),
    ]);
    final ids = [
      for (final l in csv.split('\r\n').skip(1))
        if (l.contains(',meta,measured_at,')) l.split(',')[1],
    ];
    expect(ids, ['9', '2']);
    expect(csv, contains('"Test, ""Modell"""'));
  });

  test(
    'buildMorningPairsCsvFile: Name, Typ, Zählung mit und ohne Gurt',
    () async {
      final store = FakeMorningStore(FakeStorageData());
      await store.add(
        _m(),
        beltPackets: [
          _p(5, [900]),
        ],
      );
      await store.add(_m(at: _t0.add(const Duration(days: 1))));
      final file = await buildMorningPairsCsvFile(
        store,
        now: DateTime.utc(2031, 2, 3),
      );
      expect(file.fileName, 'running-morgenpaare-20310203.csv');
      expect(file.mimeType, 'text/csv');
      final text = utf8.decode(file.bytes!);
      expect(text, contains(',belt_rr,rr,1,1,2030-01-01T06:28:05.000Z,900,'));
      expect(text, contains(',meta,belt_packets,,,,1,'));
      final n = await countMorningPairs(store);
      expect((n.withBelt, n.without), (1, 1));
    },
  );
}
