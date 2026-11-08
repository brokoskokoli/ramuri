import 'package:core/core.dart';
import 'package:test/test.dart';

import '../recalculation/recalc_support.dart';
import 'export_support.dart';
import 'xml_reader.dart';

/// Ein GPX-Punkt nach dem Rücklesen.
typedef GpxPoint = ({
  double lat,
  double lon,
  DateTime time,
  double? ele,
  int? hr,
});

List<List<GpxPoint>> readGpx(String xml) {
  final root = parseXml(xml);
  expect(root.name, 'gpx');
  expect(root.attributes['version'], '1.1');
  return [
    for (final seg in root.all('trkseg'))
      [
        for (final p in seg.named('trkpt'))
          (
            lat: double.parse(p.attributes['lat']!),
            lon: double.parse(p.attributes['lon']!),
            time: DateTime.parse(p.child('time')!.text),
            ele: p.child('ele') == null
                ? null
                : double.parse(p.child('ele')!.text),
            hr: p.all('gpxtpx:hr').isEmpty
                ? null
                : int.parse(p.all('gpxtpx:hr').single.text),
          ),
      ],
  ];
}

/// Ein TCX-Trackpoint nach dem Rücklesen.
typedef TcxPoint = ({
  DateTime time,
  double? lat,
  double? lon,
  double? ele,
  int? hr,
});

TcxPoint readTrackpoint(XmlElement p) {
  final pos = p.child('Position');
  return (
    time: DateTime.parse(p.child('Time')!.text),
    lat: pos == null ? null : double.parse(pos.child('LatitudeDegrees')!.text),
    lon: pos == null ? null : double.parse(pos.child('LongitudeDegrees')!.text),
    ele: p.child('AltitudeMeters') == null
        ? null
        : double.parse(p.child('AltitudeMeters')!.text),
    hr: p.child('HeartRateBpm') == null
        ? null
        : int.parse(p.child('HeartRateBpm')!.child('Value')!.text),
  );
}

DateTime ms(DateTime t) =>
    DateTime.fromMillisecondsSinceEpoch(t.millisecondsSinceEpoch, isUtc: true);

/// Erwartete TCX-Punkte aus den Rohwerten, unabhängig von der Abbildung
/// gerechnet: nur `present`, nur in [0, 8) ∪ [11, 20], erster Wert je
/// Kanal und Millisekunde.
Map<DateTime, TcxPoint> expectedTcx(StoredRawData raw) {
  bool active(DateTime t) {
    final s = t.difference(xStart).inMicroseconds / 1e6;
    return s >= 0 && s < 8 || s >= 11 && s <= 20;
  }

  final out = <DateTime, TcxPoint>{};
  TcxPoint get(DateTime t) =>
      out[t] ?? (time: t, lat: null, lon: null, ele: null, hr: null);
  for (final r in raw.positions) {
    final v = r.value;
    if (v.state != MeasurementState.present || !active(v.time)) continue;
    final p = get(ms(v.time));
    if (p.lat != null) continue;
    out[p.time] = (
      time: p.time,
      lat: v.latitude,
      lon: v.longitude,
      ele: p.ele,
      hr: p.hr,
    );
  }
  for (final r in raw.altitudes) {
    final v = r.value;
    if (v.state != MeasurementState.present || !active(v.time)) continue;
    final p = get(ms(v.time));
    if (p.ele != null) continue;
    out[p.time] = (
      time: p.time,
      lat: p.lat,
      lon: p.lon,
      ele: v.meters,
      hr: p.hr,
    );
  }
  for (final r in raw.heartRates) {
    final v = r.value;
    if (v.state != MeasurementState.present || !active(v.time)) continue;
    final p = get(ms(v.time));
    if (p.hr != null) continue;
    out[p.time] = (time: p.time, lat: p.lat, lon: p.lon, ele: p.ele, hr: v.bpm);
  }
  return out;
}

/// Erlaubte Elemente je Format (Vertrag `docs/contracts/file-export.md`).
const gpxElements = {
  'metadata', 'name', 'time', 'trk', 'type', 'trkseg', 'trkpt', 'ele', //
  'extensions', 'gpxtpx:TrackPointExtension', 'gpxtpx:hr',
};
const tcxElements = {
  'Activities', 'Activity', 'Id', 'Lap', 'TotalTimeSeconds', //
  'DistanceMeters', 'Calories', 'Intensity', 'TriggerMethod', 'Track',
  'Trackpoint', 'Time', 'Position', 'LatitudeDegrees', 'LongitudeDegrees',
  'AltitudeMeters', 'HeartRateBpm', 'Value',
};

void main() {
  late StorageSession s;
  setUp(() async => s = await xSession());

  Future<ExportRun> load(int id) async =>
      (await RunExportService(session: s).load(id))!;

  group('Golden', () {
    test('Hauptlauf GPX und TCX', () async {
      final run = await load(await seedMainRun(s));
      expect(run.name, 'run-20300101-090000');
      expect(run.fileName('gpx'), 'run-20300101-090000.gpx');
      expectGolden(encodeGpx(run), 'main.gpx');
      expectGolden(encodeTcx(run), 'main.tcx');
    });

    test('leerer Lauf und Lauf mit einem Punkt', () async {
      final empty = await load(await seedRun(s));
      expectGolden(encodeGpx(empty), 'empty.gpx');
      expectGolden(encodeTcx(empty), 'empty.tcx');
      final one = await load(await seedRun(s, batch: steadyBatch(3, 3)));
      expectGolden(encodeGpx(one), 'one-point.gpx');
      expectGolden(encodeTcx(one), 'one-point.tcx');
    });
  });

  group('Rücklesen = Werte des Laufs (FR-0183)', () {
    test('GPX: Positionen, Zeit, Höhe, Puls (nächster Wert ≤ 1 s)', () async {
      final run = await load(await seedMainRun(s));
      final segs = readGpx(encodeGpx(run));
      // Puls bei i + 0,4 s; 3 und 4 ohne eigenen Puls, 3 nimmt 2,4 s
      // (0,6 s), 4 hat keinen innerhalb 1 s; 20 nimmt 19,4 s, weil 20,4 s
      // nach dem Laufende liegt.
      const hr = {
        0: 140, 1: 141, 2: 142, 3: 142, 4: null, 5: 145, 6: 146, 7: 147, //
        11: 151, 12: 152, 13: 153, 17: 157, 18: 158, 19: 159, 20: 159,
      };
      expect(segs.map((p) => p.length), [8, 7]);
      final all = segs.expand((p) => p).toList();
      expect(all.map((p) => p.time), [
        for (final i in xPositionSeconds) xAt(i),
      ]);
      for (final (k, p) in all.indexed) {
        final i = xPositionSeconds[k];
        expect(p.lat, xLat(i), reason: 'lat $i');
        expect(p.lon, xLon);
        expect(p.ele, xEle(i), reason: 'ele $i');
        expect(p.hr, hr[i], reason: 'hr $i');
      }
      final meta = parseXml(encodeGpx(run)).child('metadata')!;
      expect(DateTime.parse(meta.child('time')!.text), xStart);
    });

    test('TCX: jeder Punkt genau mit den gemessenen Werten', () async {
      final id = await seedMainRun(s);
      final run = await load(id);
      final root = parseXml(encodeTcx(run));
      final points = [
        for (final p in root.all('Trackpoint')) readTrackpoint(p),
      ];
      final expected = expectedTcx(await s.rawData.read(id));
      expect(points.map((p) => p.time), (expected.keys.toList()..sort()));
      for (final p in points) {
        expect(p, expected[p.time], reason: '${p.time}');
      }
      expect(points.any((p) => p.ele == 777.5), isTrue);
      expect(root.all('Id').single.text, '2030-01-01T08:00:00.000Z');
    });

    test('TCX: Runden mit Startzeit, Zeit ohne Pause, Strecke', () async {
      final run = await load(await seedMainRun(s));
      final laps = parseXml(encodeTcx(run)).all('Lap').toList();
      expect(laps.map((l) => DateTime.parse(l.attributes['StartTime']!)), [
        xAt(0),
        xAt(6),
      ]);
      double num(XmlElement l, String n) => double.parse(l.child(n)!.text);
      expect(laps.map((l) => num(l, 'TotalTimeSeconds')), [6, 11]);
      // 5 Schritte à 3 m in Runde 1; Runde 2: 6→7, 11→12, 12→13, 13→17
      // (über den Positionsverlust), 17→20, und 5→6.
      expect(num(laps[0], 'DistanceMeters'), closeTo(15, 0.01));
      expect(num(laps[1], 'DistanceMeters'), closeTo(33, 0.01));
      expect(laps.map((l) => l.child('Calories')!.text), ['0', '0']);
      expect(laps.map((l) => l.named('Track').length), [1, 2]);
    });
  });

  group('Negativfälle', () {
    test('ohne Puls: kein Pulselement und nie 0', () async {
      final id = await seedRun(s, batch: steadyBatch(0, 10, heartRate: false));
      final run = await load(id);
      final gpx = encodeGpx(run);
      final tcx = encodeTcx(run);
      expect(parseXml(gpx).all('gpxtpx:hr'), isEmpty);
      expect(parseXml(gpx).all('extensions'), isEmpty);
      expect(parseXml(tcx).all('HeartRateBpm'), isEmpty);
      expect(readGpx(gpx).single, hasLength(11));
      expect(readGpx(gpx).single.every((p) => p.hr == null), isTrue);
    });

    test('Pulsverlust: Punkte ohne Puls tragen keinen, auch nicht 0', () async {
      final run = await load(await seedMainRun(s));
      final gpx = readGpx(encodeGpx(run)).expand((p) => p);
      expect(gpx.firstWhere((p) => p.time == xAt(4)).hr, isNull);
      final tcx = parseXml(encodeTcx(run));
      final values = [for (final v in tcx.all('Value')) int.parse(v.text)];
      expect(values, isNot(contains(0)));
      expect(
        values.toSet(),
        {for (final i in xHeartSeconds) xBpm(i)}..remove(160),
      );
      final at4 = tcx
          .all('Trackpoint')
          .map(readTrackpoint)
          .firstWhere((p) => p.time == xAt(4));
      expect(at4.hr, isNull);
    });

    test('GPS-Lücke: keine erfundenen Punkte', () async {
      final id = await seedMainRun(s);
      final run = await load(id);
      bool inLoss(DateTime t) => !t.isBefore(xAt(14)) && t.isBefore(xAt(17));
      final gpx = readGpx(encodeGpx(run)).expand((p) => p).toList();
      expect(gpx.where((p) => inLoss(p.time)), isEmpty);
      expect(gpx, hasLength(xPositionSeconds.length));
      final tcx = parseXml(encodeTcx(run))
          .all('Trackpoint')
          .map(readTrackpoint);
      final inGap = tcx.where((p) => inLoss(p.time)).toList();
      // Nur der gemessene Puls, ohne Position und Höhe.
      expect(inGap.map((p) => p.time), [xAt(14.4), xAt(15.4), xAt(16.4)]);
      expect(inGap.every((p) => p.lat == null && p.ele == null), isTrue);
      final positions = tcx.where((p) => p.lat != null).length;
      expect(positions, xPositionSeconds.length);
    });

    test(
      'Pause und Unterbrechung trennen Abschnitte, Werte darin fehlen',
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
        final run = await load(id);
        final segs = readGpx(encodeGpx(run));
        List<DateTime> secs(Iterable<int> xs) => [for (final i in xs) xAt(i)];
        expect(segs.map((p) => p.map((x) => x.time).toList()), [
          secs([0, 1, 2, 3, 4]),
          secs([10, 11, 12, 13, 14]),
          secs([20, 21, 22, 23, 24, 25, 26]),
        ]);
        final tracks = parseXml(encodeTcx(run)).all('Track').toList();
        expect(tracks, hasLength(3));
        final lap = parseXml(encodeTcx(run)).all('Lap').single;
        expect(double.parse(lap.child('TotalTimeSeconds')!.text), 17);
      },
    );

    test('leerer Lauf: gültige Datei ohne Punkte', () async {
      final run = await load(await seedRun(s, seconds: 7));
      final gpx = parseXml(encodeGpx(run));
      expect(gpx.all('trkseg'), isEmpty);
      expect(gpx.all('trk'), hasLength(1));
      final tcx = parseXml(encodeTcx(run));
      final lap = tcx.all('Lap').single;
      expect(lap.all('Track'), isEmpty);
      expect(lap.child('TotalTimeSeconds')!.text, '7.0');
      expect(lap.child('DistanceMeters')!.text, '0.0');
    });

    test('Lauf mit einem Punkt', () async {
      final run = await load(await seedRun(s, batch: steadyBatch(3, 3)));
      final gpx = readGpx(encodeGpx(run)).single.single;
      expect(
        (gpx.time, gpx.lat, gpx.ele, gpx.hr),
        (xAt(3), xLat(3), xEle(3), xBpm(3)),
      );
      final tcx = parseXml(encodeTcx(run));
      expect(tcx.all('Trackpoint'), hasLength(1));
      expect(tcx.all('DistanceMeters').single.text, '0.0');
    });

    test('nur gemessene Werte: geschätzt, verworfen, außerhalb des Laufs '
        'und Doppelte derselben Millisekunde fehlen', () async {
      final run = await load(await seedMainRun(s));
      final lats = [
        for (final seg in run.segments)
          for (final p in seg.points)
            if (p.position != null) p.position!.latitude,
      ];
      expect(lats, isNot(contains(50))); // gleiche Millisekunde
      expect(lats, isNot(contains(51))); // estimated
      expect(lats, isNot(contains(52))); // in der Pause
      final hrs = [
        for (final seg in run.segments)
          for (final p in seg.points)
            if (p.heartRateBpm != null) p.heartRateBpm!,
      ];
      expect(hrs, isNot(contains(250))); // discarded
      expect(hrs, isNot(contains(xBpm(20)))); // nach dem Laufende
    });

    test(
      'Sonderzeichen im Namen: escaped, unzulässige Zeichen entfernt',
      () async {
        final base = await load(await seedRun(s, batch: steadyBatch(0, 2)));
        final run = ExportRun(
          name: 'a<b>&c"d\'e\u0001f\u{1F3C3}g\uD800h ü',
          startedAt: base.startedAt,
          endedAt: base.endedAt,
          segments: base.segments,
          laps: base.laps,
        );
        final gpx = encodeGpx(run);
        expectGolden(gpx, 'special-name.gpx');
        final root = parseXml(gpx);
        expect(root.all('name').map((n) => n.text), [
          'a<b>&c"d\'ef\u{1F3C3}gh ü',
          'a<b>&c"d\'ef\u{1F3C3}gh ü',
        ]);
        expect(gpx, isNot(contains('\u0001')));
        expect(run.fileName('gpx'), 'a_b__c_d_e_f__g_h__.gpx');
        expect(
          ExportRun(
            name: '../..',
            startedAt: base.startedAt,
            endedAt: base.endedAt,
            segments: const [],
            laps: base.laps,
          ).fileName('tcx'),
          'run.tcx',
        );
      },
    );

    test(
      'keine Profil- oder berechneten Werte, nur erlaubte Elemente',
      () async {
        final w = await RecalcWorld.create();
        final id = await w.seedRun(DateTime.utc(2030, 1, 10, 8), minutes: 5);
        await w.calc().calculateAfterRun(id);
        expect(await w.session.values.read(ValueOwner.run(id)), isNotEmpty);
        final run = (await RunExportService(session: w.session).load(id))!;
        final gpx = parseXml(encodeGpx(run));
        final tcx = parseXml(encodeTcx(run));
        expect(
          gpxElements.containsAll(gpx.descendantNames),
          isTrue,
          reason: '${gpx.descendantNames.difference(gpxElements)}',
        );
        expect(
          tcxElements.containsAll(tcx.descendantNames),
          isTrue,
          reason: '${tcx.descendantNames.difference(tcxElements)}',
        );
        final raw = await w.session.rawData.read(id);
        final bpms = {for (final h in raw.heartRates) h.value.bpm};
        for (final v in tcx.all('Value')) {
          expect(bpms, contains(int.parse(v.text)));
        }
        for (final v in gpx.all('gpxtpx:hr')) {
          expect(bpms, contains(int.parse(v.text)));
        }
        expect(gpx.attributes['creator'], 'ramuri');
        expect(encodeGpx(run), isNot(contains('strap')));
        expect(encodeTcx(run), isNot(contains('strap')));
      },
    );

    test('nicht beendeter oder unbekannter Lauf: kein Export', () async {
      final r = await s.runs.create(startedAt: xStart);
      expect(await RunExportService(session: s).load(r.id), isNull);
      expect(await RunExportService(session: s).load(999), isNull);
    });
  });

  group('Zahlen und Zeit', () {
    test('xmlDecimal ohne Exponent und verlustfrei', () {
      for (final v in [
        1e-7,
        -2.5e-8,
        1.5e21,
        0.1,
        -0.0,
        47.123456789012,
        1e-300,
      ]) {
        final t = xmlDecimal(v);
        expect(t, isNot(contains('e')), reason: t);
        expect(double.parse(t), v, reason: t);
      }
      expect(xmlDecimal(1e-7), '0.0000001');
      expect(xmlDecimal(-1.25e-7), '-0.000000125');
      expect(xmlDecimal(1.5e21), '1500000000000000000000');
      expect(() => xmlDecimal(double.nan), throwsArgumentError);
    });

    test('xmlTime: UTC mit Millisekunden, Mikrosekunden abgeschnitten', () {
      expect(xmlTime(xAt(1.234999)), '2030-01-01T08:00:01.234Z');
    });

    test(
      'Runden: Name aus Ortszeit, Markierung teilt, Rest ist eine Runde',
      () async {
        final run = await load(await seedMainRun(s));
        expect(run.laps.map((l) => (l.number, l.start, l.end)), [
          (1, xAt(0), xAt(6)),
          (2, xAt(6), xAt(20)),
        ]);
      },
    );
  });
}
