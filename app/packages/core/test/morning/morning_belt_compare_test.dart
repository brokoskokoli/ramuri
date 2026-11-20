import 'package:core/core.dart';
import 'package:test/test.dart';

// Synthetische Gurt-Folge in 1/1024 s (keine echten Messwerte).
const _raw = [
  1000, 1040, 980, 1100, 1020, 960, 1080, 1000, 1120, 940, //
  1060, 1010, 990, 1130, 970, 1050, 1090, 950, 1030, 1070,
];

double _ms(int v) => v * 1000 / 1024;

/// Pakete zu je drei Werten, eine Sekunde auseinander.
List<RrPacket> _packets(List<int> raw, {int per = 3}) => [
  for (var i = 0; i < raw.length; i += per)
    RrPacket(
      time: DateTime.utc(2030, 1, 1, 6, 0, i ~/ per),
      source: 'gurt-1',
      intervals: raw.sublist(i, i + per > raw.length ? raw.length : i + per),
    ),
];

const _noise = [5.0, -5, 0, 5, -5, 0, 5, -5, 0, 5, -5, 0];

/// Kamera = Gurt ab Position 4 plus Rauschen ±5 ms (Versatz 4).
List<double> _camera([List<int> raw = _raw]) => [
  for (var i = 0; i < 12; i++) _ms(raw[4 + i]) + _noise[i],
];

MorningBeltComparison _match(MorningBeltCompareResult r) {
  expect(r, isA<MorningBeltComparison>());
  return r as MorningBeltComparison;
}

void main() {
  test('Gurt-Folge: Empfangszeit, Paket, Position; Wert × 1000 / 1024', () {
    final t = DateTime.utc(2030, 1, 1, 6);
    final seq = morningBeltSequenceMs([
      RrPacket(
        time: t.add(const Duration(seconds: 2)),
        source: 'a',
        intervals: const [1024],
      ),
      RrPacket(time: t, source: 'a', intervals: const [512, 2048]),
      RrPacket(time: t, source: 'a', intervals: const [256]),
    ]);
    expect(seq, [500, 2000, 250, 1000]);
  });

  test('bekannte Verschiebung wird gefunden; Kennwerte von Hand gerechnet', () {
    final r = _match(
      compareMorningWithBelt(
        _camera(),
        _packets(_raw),
        cameraRmssdMs: 120,
        cameraRestingHrBpm: 61,
      ),
    );
    expect(r.offset, 4);
    expect(r.pairCount, 12);
    expect(r.cost, closeTo(3.3333, 1e-3)); // 8 × 5 / 12
    expect(r.method, 'morning-belt-compare');
    expect(r.methodVersion, 1);
    // Gurt im Fenster = Positionen 4 bis 15.
    expect(r.beltWindowMs, [for (var j = 4; j < 16; j++) _ms(_raw[j])]);
    // Von Hand: Differenzen der Gurt-Werte 1020, 960, … , 1050 (1/1024 s).
    expect(r.beltRmssdMs, closeTo(110.21, 0.1));
    expect(r.beltRestingHrBpm, closeTo(59.80, 0.01));
    expect(r.pairedCameraRmssdMs, closeTo(112.36, 0.1));
    expect(r.pairedBeltRmssdMs, closeTo(110.21, 0.1));
    expect(r.pairedDiffCount, 11);
    expect(r.ibiErrorMs, closeTo(4.08, 0.1)); // √(8 × 25 / 12)
    expect(r.rmssdDiffMs, closeTo(120 - 110.21, 0.1));
    expect(r.rmssdDiffPercent, closeTo((120 - 110.21) / 110.21 * 100, 0.1));
    expect(r.restingHrDiffBpm, closeTo(61 - 59.80, 0.01));
    expect(r.restingHrDiffPercent, closeTo(1.2 / 59.80 * 100, 0.05));
    expect(r.validCameraCount, 12);
  });

  test('Versatz negativ: Gurt beginnt nach der Kamera', () {
    // Gurt erst ab Position 6: Kamera i gehört zu Gurt i − 2.
    final r = _match(
      compareMorningWithBelt(_camera(), _packets(_raw.sublist(6))),
    );
    expect(r.offset, -2);
    expect(r.pairCount, 10);
    expect(r.beltWindowMs.take(3), [null, null, _ms(_raw[6])]);
  });

  test('ohne Kamera-RMSSD: Gurt-Werte, keine Differenz', () {
    final r = _match(compareMorningWithBelt(_camera(), _packets(_raw)));
    expect(r.beltRmssdMs, isNotNull);
    expect(r.cameraRmssdMs, isNull);
    expect(r.rmssdDiffMs, isNull);
    expect(r.rmssdDiffPercent, isNull);
    expect(r.restingHrDiffBpm, isNull);
  });

  test('ungültiger Kamera-Wert (NaN) unterbricht die Paare', () {
    final cam = _camera()..[3] = double.nan;
    final r = _match(compareMorningWithBelt(cam, _packets(_raw)));
    expect(r.offset, 4);
    expect(r.pairCount, 11);
    expect(r.validCameraCount, 11);
    // Paare 2→3 und 3→4 fallen weg: 9 Differenzen.
    expect(r.pairedDiffCount, 9);
    expect(r.pairedCameraRmssdMs, closeTo(116.45, 0.1));
    expect(r.pairedBeltRmssdMs, closeTo(112.43, 0.1));
    // Der Gurt allein bleibt vollständig.
    expect(r.beltRmssdMs, closeTo(110.21, 0.1));
  });

  test('Gurt-Werte außerhalb 0,27 bis 2,0 s sind ungültig', () {
    final raw = [..._raw]..[10] = 250; // 244 ms
    final r = _match(compareMorningWithBelt(_camera(), _packets(raw)));
    expect(r.offset, 4);
    expect(r.beltWindowMs[6], isNull);
    expect(r.beltRmssdMs, closeTo(114.26, 0.1));
    expect(r.beltRestingHrBpm, closeTo(59.97, 0.01));
    expect(r.pairedDiffCount, 9);
    // Grenzen selbst gelten: 0,27 s und 2,0 s.
    final edges = [..._raw]
      ..[5] =
          2048 // 2000 ms
      ..[6] = 277; // 270,5 ms
    final e = _match(compareMorningWithBelt(_camera(), _packets(edges)));
    expect(e.offset, 4);
    expect(e.beltWindowMs[1], 2000);
    expect(e.beltWindowMs[2], isNotNull);
    final over = [..._raw]..[5] = 2049;
    final o = _match(compareMorningWithBelt(_camera(), _packets(over)));
    expect(o.beltWindowMs[1], isNull);
  });

  test('zu wenige Paare: keine Zuordnung (mindestens 10)', () {
    final r = compareMorningWithBelt(_camera(), _packets(_raw.sublist(0, 9)));
    expect(r, isA<MorningBeltNoMatch>());
    expect(
      (r as MorningBeltNoMatch).reason,
      MorningBeltNoMatchReason.tooFewPairs,
    );
  });

  test(
    'zu wenige Paare: keine Zuordnung (60 % der gültigen Kamera-Abstände)',
    () {
      // 20 Kamera-Abstände, 11 Gurt-Werte: höchstens 11 Paare < 12.
      final cam = [for (final v in _raw) _ms(v)];
      final r = compareMorningWithBelt(cam, _packets(_raw.sublist(0, 11)));
      expect(
        (r as MorningBeltNoMatch).reason,
        MorningBeltNoMatchReason.tooFewPairs,
      );
      // Mit 12 Gurt-Werten reicht es.
      final ok = compareMorningWithBelt(cam, _packets(_raw.sublist(0, 12)));
      expect(_match(ok).offset, 0);
    },
  );

  test('periodische Folge: mehrdeutig, keine Zuordnung (PAR-229)', () {
    final raw = [for (var i = 0; i < 40; i++) i.isEven ? 820 : 1020];
    final cam = [
      for (var i = 0; i < 20; i++) _ms(raw[i]) + (i % 3 == 0 ? 4 : -2),
    ];
    final r = compareMorningWithBelt(cam, _packets(raw));
    expect(
      (r as MorningBeltNoMatch).reason,
      MorningBeltNoMatchReason.ambiguous,
    );
  });

  test(
    'Grenze PAR-229: Verhältnis knapp darunter gilt, knapp darüber nicht',
    () {
      expect(morningBeltCompareAmbiguityRatio, 0.9);
      // 10 Kamera-Abstände je 1010 ms, 11 Gurt-Werte je 1000 ms außer dem
      // letzten: nur die Versätze 0 und 1 haben 10 Paare. Kosten Versatz 0 =
      // 10 ms, Versatz 1 = (9 × 10 + |1010 − letzter|) / 10.
      final cam = List<double>.filled(10, 1010);
      List<RrPacket> belt(int last) =>
          _packets([...List.filled(10, 1024), last]);
      // letzter 1056/1024 s = 1031,25 ms: Versatz 1 kostet 11,125; 10 / 11,125
      // = 0,899 ≤ 0,9.
      final ok = _match(compareMorningWithBelt(cam, belt(1056)));
      expect(ok.offset, 0);
      expect(ok.cost, closeTo(10, 1e-9));
      expect(ok.secondCost, closeTo(11.125, 1e-9));
      // letzter 1055/1024 s = 1030,27 ms: Versatz 1 kostet 11,027; Verhältnis
      // 0,907 > 0,9.
      final no = compareMorningWithBelt(cam, belt(1055));
      expect(
        (no as MorningBeltNoMatch).reason,
        MorningBeltNoMatchReason.ambiguous,
      );
    },
  );

  test('Kosten deckeln den Betrag je Paar bei 100 ms', () {
    // Ein Ausreißer von 400 ms zählt nur mit 100 ms: Kosten (8 × 5 + 100) / 12.
    final cam = _camera()..[5] += 400;
    final r = _match(compareMorningWithBelt(cam, _packets(_raw)));
    expect(r.offset, 4);
    expect(r.cost, closeTo((8 * 5 + 100) / 12, 1e-9));
  });

  test('leere Gurt-Folge oder keine Kamera-Abstände: keine Zuordnung', () {
    expect(
      (compareMorningWithBelt(
        _camera(),
        const [],
      ) as MorningBeltNoMatch).reason,
      MorningBeltNoMatchReason.empty,
    );
    expect(
      (compareMorningWithBelt(
        const [],
        _packets(_raw),
      ) as MorningBeltNoMatch).reason,
      MorningBeltNoMatchReason.empty,
    );
  });

  test('toString ohne Werte', () {
    final r = compareMorningWithBelt(_camera(), _packets(_raw));
    expect(r.toString(), isNot(contains('1')));
  });
}
