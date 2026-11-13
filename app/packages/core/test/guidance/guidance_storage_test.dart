import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:test/test.dart';

/// Plan mit festen Einheiten; alles andere gibt es nicht.
class _Plan implements PlanRepository {
  _Plan(this.units);
  final List<PlanUnit> units;
  DateTime? lastFrom;
  DateTime? lastTo;

  @override
  Future<List<PlanUnit>> unitsBetween(DateTime from, DateTime to) async {
    lastFrom = from;
    lastTo = to;
    return [
      for (final u in units)
        if (!u.day.isBefore(from) && !u.day.isAfter(to)) u,
    ];
  }

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError();
}

class _Values implements ComputedValueStore {
  _Values(this.byRun);
  final Map<int, Map<String, ComputedValue>> byRun;

  @override
  Future<Map<int, Map<String, ComputedValue>>> readRunValues(
    Set<String> keys,
  ) async => byRun;

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError();
}

class _Session implements StorageSession, PlanStorage {
  _Session(this.plans, this.values);
  @override
  final PlanRepository plans;
  @override
  final ComputedValueStore values;

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError();
}

final _day0 = DateTime.utc(2031, 3, 20);

PlanUnit _unit(int daysAgo, PlanUnitKind kind, int? runId) => PlanUnit(
  id: daysAgo,
  day: _day0.subtract(Duration(days: daysAgo)),
  kind: kind,
  phase: PlanPhase.build,
  weekIndex: 0,
  minutes: 30,
  segments: const [],
  runId: runId,
);

ComputedValue _secs(String key, int s) => ComputedValue(
  key: key,
  value: s.toDouble(),
  unit: 's',
  computedAt: _day0,
  dataFrom: _day0,
  dataTo: _day0,
  measurementCount: 1,
  sources: const ['hr'],
  method: 'test',
  methodVersion: 1,
  parameterVersion: 1,
  quality: ValueQuality.good,
);

/// Zonenzeiten eines Laufs in Sekunden: Zone 1..5 und unter Zone 1.
Map<String, ComputedValue> _zones(List<int> z, [int below = 0]) => {
  for (var i = 0; i < 5; i++)
    zoneTimeValueKey(i + 1): _secs(zoneTimeValueKey(i + 1), z[i]),
  zoneBelowValueKey: _secs(zoneBelowValueKey, below),
};

void main() {
  group('Schnappschuss der geführten Einheit', () {
    test('Rundlauf mit Abschnitten, Ziel und Merker', () {
      final s = GuidedUnitSnapshot(
        runId: 7,
        walkBreakHintGiven: true,
        segments: const [
          PlanSegment(kind: PlanSegmentKind.warmUp, minutes: 5),
          PlanSegment(
            kind: PlanSegmentKind.run,
            minutes: 2,
            seconds: 90,
            intensity: PlanTargetIntensity(
              rpeMin: 3,
              rpeMax: 4,
              paceFastSecondsPerKm: 330.5,
              paceSlowSecondsPerKm: 360,
              basisCode: 'hr',
              hrMinBpm: 120,
              hrMaxBpm: 140,
              estimated: true,
              paceIsLimit: true,
            ),
          ),
        ],
      );
      final r = GuidedUnitSnapshot.decode(s.encode())!;
      expect(r.runId, 7);
      expect(r.walkBreakHintGiven, isTrue);
      expect(r.segments, hasLength(2));
      expect(r.segments[0].kind, PlanSegmentKind.warmUp);
      expect(r.segments[0].intensity, isNull);
      final b = r.segments[1];
      expect(b.durationSeconds, 90);
      expect(b.intensity!.hrMaxBpm, 140);
      expect(b.intensity!.paceFastSecondsPerKm, 330.5);
      expect(b.intensity!.paceIsLimit, isTrue);
      expect(b.intensity!.estimated, isTrue);
      expect(b.intensity!.maxHrEstimated, isFalse);
      expect(b.intensity!.rpeMin, 3);
    });

    test('leer, kaputt, fremde Version: null', () {
      expect(GuidedUnitSnapshot.decode(null), isNull);
      expect(GuidedUnitSnapshot.decode(''), isNull);
      expect(GuidedUnitSnapshot.decode('{kaputt'), isNull);
      expect(GuidedUnitSnapshot.decode('{"v":2,"run":1,"seg":[]}'), isNull);
      expect(
        GuidedUnitSnapshot.decode('{"v":1,"run":1,"seg":[{"k":"x","m":1}]}'),
        isNull,
      );
    });

    test('der Schlüssel liegt nicht im Archiv', () {
      expect(
        archiveExcludedSettingKeys,
        contains(SettingKeys.guidedUnitSnapshot),
      );
    });
  });

  group('Schalter der Ansagen', () {
    test('Vorgabe alles an; nur 0 schaltet aus; Speichern und Lesen', () async {
      final s = await FakeStorage().open(Uint8List(32));
      final g = GuidanceSettings(s.settings);
      var w = await g.load();
      expect(
        [w.enabled, w.kilometer, w.heartRate, w.segments],
        [true, true, true, true],
      );
      await g.save(
        const GuidanceSwitches(kilometer: false, segments: false),
        clock: FakeClock(DateTime.utc(2031)),
      );
      w = await g.load();
      expect(
        [w.enabled, w.kilometer, w.heartRate, w.segments],
        [true, false, true, false],
      );
      await s.settings.set(
        SettingKeys.guidanceEnabled,
        '0',
        at: DateTime.utc(2031),
      );
      expect((await g.load()).enabled, isFalse);
    });
  });

  group('Gehpausen-Beleg aus gespeicherten Läufen', () {
    Future<List<EasyRunExposure>> load(
      List<PlanUnit> units,
      Map<int, Map<String, ComputedValue>> values,
    ) => recentEasyRunExposures(
      _Session(_Plan(units), _Values(values)),
      today: _day0,
    );

    test(
      'nur lockere Einheiten mit Lauf, neueste zuerst, höchstens 3',
      () async {
        final r = await load(
          [
            _unit(1, PlanUnitKind.easy, 11),
            _unit(2, PlanUnitKind.tempo, 12), // nicht locker
            _unit(3, PlanUnitKind.easy, null), // ohne Lauf
            _unit(4, PlanUnitKind.easy, 14),
            _unit(5, PlanUnitKind.easy, 15),
            _unit(6, PlanUnitKind.easy, 16), // vierte: zählt nicht
          ],
          {
            11: _zones([0, 0, 600, 0, 0]), // alles über Zone 2
            14: _zones([600, 0, 0, 0, 0]),
            15: _zones([0, 0, 0, 600, 0]),
            16: _zones([0, 0, 0, 600, 0]),
          },
        );
        expect(r, hasLength(3));
        expect([for (final e in r) e.mostlyAbove], [true, false, true]);
        expect(easyRunsMostlyAboveUpper(r), isTrue);
      },
    );

    test(
      'Lauf ohne gespeicherte Zonenzeiten: kein Beleg, nie darüber',
      () async {
        final r = await load(
          [
            _unit(1, PlanUnitKind.easy, 11),
            _unit(2, PlanUnitKind.easy, 12),
            _unit(3, PlanUnitKind.easy, 13),
          ],
          {
            11: _zones([0, 0, 600, 0, 0]),
            // 12: gar nichts gespeichert
            13: {
              zoneTimeValueKey(1): _secs(zoneTimeValueKey(1), 60),
            }, // unvollständig
          },
        );
        expect(r, hasLength(3));
        expect(r[1].known, Duration.zero);
        expect(r[2].known, Duration.zero);
        expect(r[1].mostlyAbove, isFalse);
        expect(easyRunsMostlyAboveUpper(r), isFalse);
      },
    );

    test('Zeit unter Zone 1 zählt als bekannt, nicht als darüber', () async {
      final r = await load(
        [_unit(1, PlanUnitKind.easy, 11)],
        {
          11: _zones([0, 0, 300, 0, 0], 300),
        },
      );
      expect(r.single.known, const Duration(minutes: 10));
      expect(r.single.aboveUpper, const Duration(minutes: 5));
      expect(r.single.mostlyAbove, isFalse); // genau die Hälfte
    });

    test('ohne Plan im Speicher oder ohne Einheiten: leer', () async {
      final s = await FakeStorage().open(Uint8List(32));
      expect(await recentEasyRunExposures(s, today: _day0), isEmpty);
      expect(await load(const [], const {}), isEmpty);
    });

    test('Suchfenster endet am Ortstag und reicht 120 Tage zurück', () async {
      final plan = _Plan(const []);
      await recentEasyRunExposures(
        _Session(plan, _Values(const {})),
        today: DateTime.utc(2031, 3, 20, 23, 30),
      );
      expect(plan.lastTo, DateTime.utc(2031, 3, 20));
      expect(plan.lastFrom, DateTime.utc(2030, 11, 20));
    });
  });
}
