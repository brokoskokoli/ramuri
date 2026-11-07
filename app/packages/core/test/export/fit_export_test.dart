import 'dart:convert';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:test/test.dart';

import '../recalculation/recalc_support.dart';
import 'export_support.dart';
import 'fit_reader.dart';

// Globale Nachrichtennummern (FIT-Profil).
const fileId = 0, session = 18, lap = 19, record = 20, event = 21;
const activity = 34;
const fitEpochUnix = 631065600;
const invalidSint32 = 0x7FFFFFFF, invalidUint16 = 0xFFFF, invalidUint8 = 0xFF;

int fitSeconds(DateTime t) => t.millisecondsSinceEpoch ~/ 1000 - fitEpochUnix;
int semi(double deg) => (deg * 2147483648 / 180).round();

/// Ein `record` nach dem Rücklesen; `null` = Invalid-Wert des Typs.
typedef FitPoint = ({int time, int? lat, int? lon, double? ele, int? hr});

List<FitPoint> fitPoints(FitFile f) => [
  for (final m in f.of(record))
    (
      time: m.fields[253]!,
      lat: m.fields[0] == invalidSint32 ? null : m.fields[0],
      lon: m.fields[1] == invalidSint32 ? null : m.fields[1],
      ele: m.fields[2] == invalidUint16 ? null : m.fields[2]! / 5 - 500,
      hr: m.fields[3] == invalidUint8 ? null : m.fields[3],
    ),
];

/// Timer-Ereignisse als (Sekunde ab Start, Typ 0 = start, 4 = stop_all).
List<(int, int)> timerEvents(FitFile f) => [
  for (final m in f.of(event))
    if (m.fields[0] == 0) (m.fields[253]! - fitSeconds(xStart), m.fields[1]!),
];

DateTime sec(DateTime t) => DateTime.fromMillisecondsSinceEpoch(
  t.millisecondsSinceEpoch - t.millisecondsSinceEpoch % 1000,
  isUtc: true,
);

/// Erwartete Punkte aus den Rohwerten, unabhängig von der Abbildung:
/// nur `present`, nur in [0, 8) ∪ [11, 20], erster Wert je Kanal und Sekunde.
Map<int, ({double? lat, double? lon, double? ele, int? hr})> expectedFit(
  StoredRawData raw,
) {
  bool active(DateTime t) {
    final s = t.difference(xStart).inMicroseconds / 1e6;
    return s >= 0 && s < 8 || s >= 11 && s <= 20;
  }

  final pos = <int, (double, double)>{};
  final ele = <int, double>{};
  final hr = <int, int>{};
  for (final r in raw.positions) {
    final v = r.value;
    if (v.state != MeasurementState.present || !active(v.time)) continue;
    pos.putIfAbsent(fitSeconds(sec(v.time)), () => (v.latitude, v.longitude));
  }
  for (final r in raw.altitudes) {
    final v = r.value;
    if (v.state != MeasurementState.present || !active(v.time)) continue;
    ele.putIfAbsent(fitSeconds(sec(v.time)), () => v.meters);
  }
  for (final r in raw.heartRates) {
    final v = r.value;
    if (v.state != MeasurementState.present || !active(v.time)) continue;
    hr.putIfAbsent(fitSeconds(sec(v.time)), () => v.bpm);
  }
  return {
    for (final t in {...pos.keys, ...ele.keys, ...hr.keys})
      t: (lat: pos[t]?.$1, lon: pos[t]?.$2, ele: ele[t], hr: hr[t]),
  };
}

/// Erlaubte Nachrichten und Felder (Vertrag `docs/contracts/file-export.md`).
const fitFields = {
  fileId: {0, 1, 4},
  event: {253, 0, 1},
  record: {253, 0, 1, 2, 3},
  lap: {254, 253, 0, 1, 2, 7, 8, 9, 24, 25},
  session: {254, 253, 0, 1, 2, 5, 6, 7, 8, 9, 25, 26, 28},
  activity: {253, 0, 1, 2, 3, 4},
};

void main() {
  late StorageSession s;
  setUp(() async => s = await xSession());

  Future<ExportRun> load(int id) async =>
      (await RunExportService(session: s).load(id, resolution: exportSecond))!;
  Future<FitFile> fit(int id) async => readFit(encodeFit(await load(id)));

  group('Golden', () {
    test('Hauptlauf, leerer Lauf, Lauf mit einem Punkt', () async {
      final main = await load(await seedMainRun(s));
      expect(main.fileName('fit'), 'run-20300101-090000.fit');
      expectGoldenBytes(encodeFit(main), 'main.fit');
      expectGoldenBytes(encodeFit(await load(await seedRun(s))), 'empty.fit');
      final one = await load(await seedRun(s, batch: steadyBatch(3, 3)));
      expectGoldenBytes(encodeFit(one), 'one-point.fit');
    });
  });

  group('Rücklesen = Werte des Laufs (FR-0183)', () {
    test('Kopf, file_id und Reihenfolge der Nachrichten', () async {
      final f = await fit(await seedMainRun(s));
      expect((f.headerSize, f.protocol, f.profile), (14, 0x20, 2140));
      expect(f.messages.first.global, fileId);
      expect(f.messages.first.fields, {0: 4, 1: 255, 4: fitSeconds(xStart)});
      expect(f.messages.map((m) => m.global).toList().sublist(1), [
        event, ...List.filled(6, record), lap, //
        ...List.filled(2, record), event, event, //
        ...List.filled(10, record), event, lap, session, activity,
      ]);
      final times = [
        for (final m in f.messages.skip(1))
          if (m.global != lap) m.fields[253]!,
      ];
      expect(times, orderedEquals([...times]..sort()));
    });

    test('jeder record genau mit den gemessenen Werten', () async {
      final id = await seedMainRun(s);
      final expected = expectedFit(await s.rawData.read(id));
      final points = fitPoints(await fit(id));
      expect(
        points.map((p) => p.time).toList(),
        expected.keys.toList()..sort(),
      );
      for (final p in points) {
        final e = expected[p.time]!;
        expect(
          p.lat,
          e.lat == null ? isNull : semi(e.lat!),
          reason: '${p.time}',
        );
        expect(p.lon, e.lon == null ? isNull : semi(e.lon!));
        if (e.lat != null) {
          expect(p.lat! * 180 / 2147483648, closeTo(e.lat!, 1e-7));
        }
        if (e.ele == null) {
          expect(p.ele, isNull);
        } else {
          expect(p.ele, closeTo(e.ele!, 0.1));
        }
        expect(p.hr, e.hr);
      }
    });

    test('Timer, Runden, Sitzung und Aktivität', () async {
      final f = await fit(await seedMainRun(s));
      final t0 = fitSeconds(xStart);
      expect(timerEvents(f), [(0, 0), (8, 4), (11, 0), (20, 4)]);
      final laps = f.of(lap).toList();
      expect(laps.map((l) => l.fields[254]), [0, 1]);
      expect(laps.map((l) => l.fields[2]! - t0), [0, 6]);
      expect(laps.map((l) => l.fields[253]! - t0), [6, 20]);
      expect(laps.map((l) => l.fields[7]), [6000, 14000]);
      expect(laps.map((l) => l.fields[8]), [6000, 11000]);
      // 5 × 3 m; dann 2 × 3 + 2 × 3 + 12 (Positionsverlust gerade) + 3 × 3 m
      // (der Abstand 5→6 zählt zur Runde des Punkts bei 6 s).
      expect(laps[0].fields[9]! / 100, closeTo(15, 0.01));
      expect(laps[1].fields[9]! / 100, closeTo(33, 0.01));
      expect(laps.map((l) => (l.fields[0], l.fields[1])), [(9, 1), (9, 1)]);
      expect(laps.map((l) => (l.fields[24], l.fields[25])), [(0, 1), (7, 1)]);
      final se = f.of(session).single.fields;
      expect(se[2], t0);
      expect(se[253], t0 + 20);
      expect((se[0], se[1], se[5], se[6], se[28]), (8, 1, 1, 0, 0));
      expect((se[7], se[8], se[25], se[26]), (20000, 17000, 0, 2));
      expect(se[9]! / 100, closeTo(48, 0.02));
      final a = f.of(activity).single.fields;
      expect(a, {253: t0 + 20, 0: 17000, 1: 1, 2: 0, 3: 26, 4: 1});
    });
  });

  group('Negativfälle', () {
    test('ohne Puls: heart_rate ist Invalid 0xFF, nie 0', () async {
      final f = await fit(
        await seedRun(s, batch: steadyBatch(0, 5, heartRate: false)),
      );
      final raw = [for (final m in f.of(record)) m.fields[3]];
      expect(raw, hasLength(6));
      expect(raw, everyElement(invalidUint8));
    });

    test('Pulsverlust: Punkte ohne Puls tragen 0xFF', () async {
      final points = fitPoints(await fit(await seedMainRun(s)));
      final t0 = fitSeconds(xStart);
      final noHr = [
        for (final p in points)
          if (p.hr == null) p.time - t0,
      ];
      // 3 und 4: Pulsverlust; 20: der Wert bei 20,4 s liegt nach dem Ende.
      expect(noHr, [3, 4, 20]);
      expect(points.map((p) => p.hr), isNot(contains(0)));
    });

    test('GPS-Lücke: keine erfundenen Positionen', () async {
      final full = steadyBatch(0, 10);
      final id = await seedRun(
        s,
        batch: RawBatch(
          positions: [
            for (final p in full.positions)
              if (p.time.isBefore(xAt(3)) || !p.time.isBefore(xAt(7))) p,
          ],
          altitudes: full.altitudes,
          heartRates: full.heartRates,
        ),
        gaps: [(RunGapKind.positionLoss, 3, 7)],
      );
      final f = await fit(id);
      final t0 = fitSeconds(xStart);
      final points = fitPoints(f);
      expect(points, hasLength(11));
      for (final p in points) {
        final i = p.time - t0;
        final inGap = i >= 3 && i < 7;
        expect(p.lat, inGap ? isNull : semi(xLat(i)), reason: '$i');
        expect(p.lon, inGap ? isNull : semi(xLon));
        expect(p.hr, xBpm(i));
      }
      for (final m in f.of(record)) {
        if (m.fields[0] == invalidSint32) {
          expect(m.fields[1], invalidSint32);
        }
      }
      expect(timerEvents(f), [(0, 0), (10, 4)]);
    });

    test(
      'Pause und Unterbrechung: Timer stop_all/start, Werte darin fehlen',
      () async {
        final id = await seedRun(
          s,
          seconds: 30,
          batch: steadyBatch(0, 30),
          gaps: [
            (RunGapKind.manualPause, 5, 10),
            (RunGapKind.interruption, 15, 20),
            (RunGapKind.positionLoss, 22, 24),
            (RunGapKind.manualPause, 27, null),
          ],
        );
        final f = await fit(id);
        final t0 = fitSeconds(xStart);
        expect(timerEvents(f), [
          (0, 0), (5, 4), (10, 0), (15, 4), (20, 0), (27, 4), //
        ]);
        expect(fitPoints(f).map((p) => p.time - t0), [
          0, 1, 2, 3, 4, 10, 11, 12, 13, 14, 20, 21, 22, 23, 24, 25, 26, //
        ]);
        final l = f.of(lap).single.fields;
        expect((l[7], l[8]), (30000, 17000));
        expect(f.of(session).single.fields[8], 17000);
      },
    );

    test('Pause unter einer Sekunde: ein record je Sekunde, '
        'erster Wert je Kanal', () async {
      final id = await seedRun(
        s,
        batch: RawBatch(
          positions: [
            RawPosition(
              time: xAt(4.2),
              source: 'gps',
              latitude: xLat(1),
              longitude: xLon,
            ),
            RawPosition(
              time: xAt(4.7),
              source: 'gps',
              latitude: xLat(2),
              longitude: xLon,
            ),
          ],
          heartRates: [RawHeartRate(time: xAt(4.8), source: 's', bpm: 150)],
        ),
        gaps: [(RunGapKind.manualPause, 4.4, 4.6)],
      );
      final f = await fit(id);
      final p = fitPoints(f).single;
      expect((p.time, p.lat, p.hr), (fitSeconds(xAt(4)), semi(xLat(1)), 150));
      expect(timerEvents(f), [(0, 0), (4, 4), (4, 0), (10, 4)]);
      final kinds = [
        for (final m in f.messages)
          if (m.global == record || m.global == event) m.global,
      ];
      expect(kinds, [event, record, event, event, event]);
    });

    test('leerer Lauf: gültige Datei ohne records', () async {
      final f = await fit(await seedRun(s, seconds: 7));
      expect(f.messages.map((m) => m.global), [
        fileId, event, event, lap, session, activity, //
      ]);
      expect(timerEvents(f), [(0, 0), (7, 4)]);
      final l = f.of(lap).single.fields;
      expect((l[7], l[8], l[9]), (7000, 7000, 0));
      // Lauf ganz in Pause: kein Abschnitt, Timer start/stop_all am Start.
      final paused = await fit(
        await seedRun(s, gaps: [(RunGapKind.manualPause, 0, null)]),
      );
      expect(paused.of(record), isEmpty);
      expect(timerEvents(paused), [(0, 0), (0, 4)]);
      expect(paused.of(session).single.fields[8], 0);
    });

    test('Lauf mit einem Punkt', () async {
      final f = await fit(await seedRun(s, batch: steadyBatch(3, 3)));
      final p = fitPoints(f).single;
      expect(
        (p.time, p.lat, p.lon, p.hr),
        (fitSeconds(xAt(3)), semi(xLat(3)), semi(xLon), xBpm(3)),
      );
      expect(p.ele, closeTo(xEle(3), 0.1));
      expect(f.of(lap).single.fields[9], 0);
    });

    test(
      'Höhe und Puls außerhalb des Wertebereichs: Invalid, kein Umlauf',
      () async {
        // Sekunde -> (Höhe, Puls). Grenzen: Höhe −500…12 606,8 m (uint16,
        // 0xFFFF Invalid), Puls 1…254 (uint8, 0xFF Invalid).
        const values = <int, (double, int)>{
          0: (-500, 1),
          1: (12606.8, 254),
          2: (12607, 255),
          3: (20000, 255),
          4: (-500.2, 0),
          5: (-1000, 300),
        };
        final full = steadyBatch(0, 5);
        final id = await seedRun(
          s,
          seconds: 5,
          batch: RawBatch(
            positions: full.positions,
            altitudes: [
              for (final MapEntry(key: i, value: (m, _)) in values.entries)
                RawAltitude(time: xAt(i), source: 'gps', meters: m),
            ],
            heartRates: [
              for (final MapEntry(key: i, value: (_, bpm)) in values.entries)
                RawHeartRate(time: xAt(i), source: 'strap', bpm: bpm),
            ],
          ),
        );
        final f = await fit(id);
        final raw = [for (final m in f.of(record)) (m.fields[2], m.fields[3])];
        expect(raw, [
          (0, 1),
          (65534, 254),
          (invalidUint16, invalidUint8),
          (invalidUint16, invalidUint8),
          (invalidUint16, invalidUint8),
          (invalidUint16, invalidUint8),
        ]);
      },
    );

    test('Zeiten mit Sekundenbruchteilen werden abgelehnt', () async {
      final id = await seedMainRun(s);
      final ms = (await RunExportService(session: s).load(id))!;
      expect(() => encodeFit(ms), throwsArgumentError);
    });

    test('keine Profil- oder berechneten Werte, nur erlaubte Felder', () async {
      final w = await RecalcWorld.create();
      final id = await w.seedRun(DateTime.utc(2030, 1, 10, 8), minutes: 5);
      await w.calc().calculateAfterRun(id);
      expect(await w.session.values.read(ValueOwner.run(id)), isNotEmpty);
      final run = (await RunExportService(session: w.session)
          .load(id, resolution: exportSecond))!;
      final f = readFit(encodeFit(run));
      for (final m in f.messages) {
        expect(fitFields.keys, contains(m.global));
        expect(m.fields.keys.toSet(), fitFields[m.global]);
      }
      final raw = await w.session.rawData.read(id);
      final bpms = {for (final h in raw.heartRates) h.value.bpm};
      for (final p in fitPoints(f)) {
        if (p.hr != null) expect(bpms, contains(p.hr));
      }
      expect(fitPoints(f).where((p) => p.hr != null), isNotEmpty);
      expect(latin1.decode(encodeFit(run)), isNot(contains('strap')));
    });
  });

  group('Prüfsummen', () {
    test('CRC-16 gegen Referenzwert (CRC-16/ARC, "123456789" = 0xBB3D)', () {
      final check = ascii.encode('123456789');
      expect(fitCrc16(check), 0xBB3D);
      expect(testCrc(check), 0xBB3D);
      expect(fitCrc16(<int>[]), 0);
      expect(fitCrc16(check.skip(4), fitCrc16(check.take(4))), 0xBB3D);
      // Daten samt angehängter Summe (little-endian) ergeben 0.
      expect(fitCrc16([...check, 0x3D, 0xBB]), 0);
    });

    test('Kopf- und Datei-CRC der Goldens stimmen', () async {
      final bytes = encodeFit(await load(await seedMainRun(s)));
      expect(bytes[12] | bytes[13] << 8, fitCrc16(bytes.take(12)));
      final n = bytes.length;
      expect(bytes[n - 2] | bytes[n - 1] << 8, fitCrc16(bytes.take(n - 2)));
      expect(fitCrc16(bytes), 0);
    });

    test('gekipptes Bit: Prüfung schlägt fehl', () async {
      final bytes = encodeFit(await load(await seedMainRun(s)));
      readFit(bytes);
      Matcher fails(String what) => throwsA(
        isA<FitFormatException>().having((e) => e.message, 'message', what),
      );
      Uint8List flip(int at, [int mask = 0x01]) =>
          Uint8List.fromList(bytes)..[at] ^= mask;
      expect(() => readFit(flip(2)), fails('Kopf-CRC'));
      expect(() => readFit(flip(bytes.length ~/ 2)), fails('Datei-CRC'));
      expect(() => readFit(flip(bytes.length - 1)), fails('Datei-CRC'));
      for (var i = 0; i < bytes.length; i++) {
        for (final mask in [0x01, 0x80]) {
          expect(
            () => readFit(flip(i, mask)),
            throwsA(isA<FitFormatException>()),
            reason: 'Byte $i',
          );
        }
      }
    });
  });
}
