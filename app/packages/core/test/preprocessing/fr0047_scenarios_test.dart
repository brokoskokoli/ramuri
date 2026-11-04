// FR-0047: je ein benannter, synthetischer Gesamtlauf pro Datenproblem, mit
// von Hand aus der Geometrie hergeleiteten Sollwerten (nicht aus der Ausgabe
// abgeschrieben). Grundlauf: 3 m/s, 1 Hz, geradeaus nach Norden, Genauigkeit
// 5 m, Start t0. Strecken werden mit 1 cm Toleranz verglichen (Haversine).
import 'package:core/core.dart';
import 'package:test/test.dart';

import 'altitude_support.dart';
import 'hr_support.dart';
import 'support.dart';

/// Punkte im Sekundentakt von [from] bis [to] bei [v] m/s, Norden = Startwert
/// + v * (s - from); Sekunden aus [skip] fehlen, [special] ersetzt Punkte.
List<RawPosition> track(
  int from,
  int to, {
  double v = 3,
  double base = 0,
  Set<int> skip = const {},
  Map<int, RawPosition> special = const {},
}) => [
  for (var s = from; s <= to; s++)
    if (!skip.contains(s)) special[s] ?? pos(s, base + v * (s - from)),
];

RunPreprocessing play(RunPreprocessor r, List<RawPosition> points, num until) {
  points.forEach(r.addPosition);
  return r.result(at: at(until));
}

void main() {
  test('GPS-Ungenauigkeit (PAR-001): Punkt mit 30 m wird verworfen, '
      '25 m zählt', () {
    // Punkt 5: 30 m > 25 -> verworfen. Punkt 7: genau 25 -> bleibt.
    // Gerade Strecke 0..10 = 3*10 = 30 m. Segment 4->6 (6 m) überbrückt den
    // verworfenen Punkt: bridged = 6 m. Punkt 6 ist dadurch geschätzt.
    final res = play(
      RunPreprocessor(start: t0),
      track(0, 10, special: {5: pos(5, 15, acc: 30), 7: pos(7, 21, acc: 25)}),
      10,
    );
    final p = res.position;
    expect(p.distanceMeters, closeTo(30, 0.01));
    expect(p.bridgedDistanceMeters, closeTo(6, 0.01));
    expect(p.positions[5].state, MeasurementState.discarded);
    expect(p.positions[5].reason, DiscardReason.accuracy);
    expect(p.positions[6].state, MeasurementState.estimated);
    expect(p.positions[7].state, MeasurementState.present);
    expect(p.acceptedPoints, hasLength(10));
  });

  test('Positionssprung (PAR-002/003): hart bei t=3, weich bei t=7', () {
    // t=3: 600 m statt 9 m -> 591 m in 1 s ab Punkt 2 (6 m) = hard (>12,5).
    // t=7: 12 m in 1 s ab Punkt 6 (18 m): 12 m/s (>8, <=12,5), 12 m > 5+5 -> weich verworfen.
    // Rest geradeaus, Distanz 0..10 = 30 m; Überbrückt: 2->4 und 6->8,
    // je 6 m = 12 m.
    final res = play(
      RunPreprocessor(start: t0),
      track(0, 10, special: {3: pos(3, 600), 7: pos(7, 30)}),
      10,
    );
    final p = res.position;
    expect(p.positions[3].reason, DiscardReason.hardJump);
    expect(p.positions[7].reason, DiscardReason.softJump);
    expect(p.distanceMeters, closeTo(30, 0.01));
    expect(p.bridgedDistanceMeters, closeTo(12, 0.01));
    expect(res.pace.medianSpeed, closeTo(3, 1e-6));
  });

  test('fehlende Herzfrequenz (PAR-010): Lücke 20..40 bleibt fehlend', () {
    // 140 bpm für s=0..19 (20 Werte), 160 bpm für s=41..60 (20 Werte).
    // Mittel = (20*140+20*160)/40 = 150, Maximum 160, nichts interpoliert.
    // Lücke vom letzten Wert (19) bis zum nächsten (41) = 22 s > 10 s.
    // Fehlende Zeit im Abschnitt [0,60], Takt 1 s: 22-1 = 21 s -> 21/60 = 0,35;
    // > 5 Prozent und Einzellücke > 10 s: Regel verletzt.
    final r = RunPreprocessor(start: t0);
    beat(0, 19, 140).forEach(r.addHeartRate);
    beat(41, 60, 160).forEach(r.addHeartRate);
    final res = r.result(at: at(60));
    final h = res.heartRate;
    expect(h.averageBpm, 150);
    expect(h.maxBpm, 160);
    expect(h.gaps, hasLength(1));
    expect(h.gaps.single.start, at(19));
    expect(h.gaps.single.end, at(41));
    final q = res.assessSection(at(0), at(60));
    expect(q.missingHeartRateShare, closeTo(0.35, 1e-9));
    expect(q.longestHeartRateGap, const Duration(seconds: 22));
    expect(q.meetsHeartRateGapRule, isFalse);
    // Ganz ohne Puls: null, nie 0.
    final none = RunPreprocessor(start: t0).result(at: at(60)).heartRate;
    expect([none.averageBpm, none.maxBpm, none.medianBpm], [null, null, null]);
  });

  test('Sensorausreißer (PAR-009): 200 bpm bei 140 bpm Umgebung', () {
    // Abweichung vom Median 140: 60 > 25; Rate 60 bpm/s > 5 -> verworfen.
    // Mittel aller übrigen: 140, Maximum 140 (nicht 200).
    final r = RunPreprocessor(start: t0);
    for (final h in beat(0, 60, 140)) {
      r.addHeartRate(h.time == at(30) ? hr(30, 200) : h);
    }
    final h = r.result(at: at(60)).heartRate;
    expect(h.processed[30].reason, DiscardReason.heartRateOutlier);
    expect([h.averageBpm, h.maxBpm, h.medianBpm], [140, 140, 140]);
    expect(h.acceptedValues, hasLength(60));
  });

  test('Verzögerung der Herzfrequenz (PAR-011): Einschwingzeit markiert, '
      'Werte bleiben unverschoben', () {
    // 3 m/s bis s=300 (900 m), danach 4,1 m/s (bis 360), Punkt 301 bei 904,1. Start: [0,180].
    // Tempowechsel: x s nach 300 ist Mittel(t-2min,t] = 3 + 1,1*x/120, das
    // frühere Fenster 3. Differenz 1,1*x/120 >= 0,25 erstmals bei x=28
    // (27: 0,2475). Auslösen von s=328 bis 360, jedes verlängert: Ende
    // 360+180 = 540. Intervalle: [0,180] und [328,540].
    final r = RunPreprocessor(start: t0);
    final pts = [...track(0, 300), ...track(301, 360, v: 4.1, base: 904.1)];
    beat(0, 360, 150).forEach(r.addHeartRate);
    final res = play(r, pts, 360);
    final iv = res.settling.intervals;
    expect(
      [for (final i in iv) (i.start, i.end)],
      [(at(0), at(180)), (at(328), at(540))],
    );
    expect(res.heartRate.acceptedValues, hasLength(361));
    expect(res.heartRate.averageBpm, 150);
    expect(res.assessSection(at(200), at(320)).overlapsSettling, isFalse);
    final a = res.assessSection(at(100), at(200));
    expect(a.settlingOverlap, const Duration(seconds: 80));
    expect(a.settlingShare, closeTo(0.8, 1e-9));
    expect(res.assessSection(at(330), at(360)).settlingShare, 1);
  });

  test('Trainingspause (manuell): keine Strecke und keine Bewegungszeit '
      'über die Pause', () {
    // Punkte 0..20 (60 m), Pause 20..50, Punkte 51..60 ab 1000 m (neuer
    // Abschnitt, 9 s * 3 = 27 m). Der Sprung 60 -> 1000 m zählt nicht.
    // Distanz 60 + 27 = 87. Gesamtzeit 60 s, Bewegungszeit 60-30 = 30 s.
    // Keine GPS-Lücke durch die Pause; Einschwingzeit startet ab 50.
    final r = RunPreprocessor(start: t0);
    track(0, 20).forEach(r.addPosition);
    r.pause(at(20));
    r.addPosition(pos(35, 70)); // in der Pause: nicht verfügbar
    r.resume(at(50));
    final res = play(r, track(51, 60, base: 1000), 60);
    expect(res.position.distanceMeters, closeTo(87, 0.01));
    expect(res.position.gaps, isEmpty);
    expect(res.movement.totalTime, const Duration(seconds: 60));
    expect(res.movement.movingTime, const Duration(seconds: 30));
    expect(res.position.positions[21].state, MeasurementState.unavailable);
    // Einschwingzeit [0,180] und ab Wiederbeginn [50,230] verschmelzen.
    expect(
      [for (final i in res.settling.intervals) (i.start, i.end)],
      [(at(0), at(230))],
    );
  });

  test(
    'Messunterbrechung (PAR-004): 15 s ohne Punkte ist Lücke, 10 s nicht',
    () {
      // Punkte 0..10 (30 m), dann 11..24 fehlend, 25..30. Abstand 10 -> 25 =
      // 15 s > 10: Lücke [10,25], die 45 m des Sprungs zählen nicht. Punkte
      // 25..30: 15 m. Danach fehlen 31..39, Punkt 40 bei 90+30 = 120 m: Abstand
      // genau 10 s wird überbrückt (kein Verwerfen, kein Lückeneintrag) und
      // zählt 30 m. Strecke 30 + 15 + 30 = 75. Zeit läuft weiter (FR-0194):
      // Bewegungszeit = Gesamtzeit = 40 s.
      final pts = [...track(0, 10), ...track(25, 30, base: 75), pos(40, 120)];
      final res = play(RunPreprocessor(start: t0), pts, 40);
      expect(res.position.gaps, hasLength(1));
      expect(res.position.gaps.single.start, at(10));
      expect(res.position.gaps.single.end, at(25));
      expect(res.position.distanceMeters, closeTo(75, 0.01));
      expect(res.position.bridgedDistanceMeters, 0);
      expect(res.movement.movingTime, const Duration(seconds: 40));
      expect(res.assessSection(at(0), at(40)).gpsGaps, hasLength(1));
    },
  );

  test('Höhenfehler (PAR-012/013): schlechter Wert und Rauschen zählen '
      'nicht', () {
    // Werte alle 40 s (Median = Rohwert), Referenz startet bei 100.
    // 101, 99: unter 3. 135 mit 30 m Genauigkeit: verworfen (sonst +35).
    // 104: +4 (Referenz 104). 100,5: 3,5 tiefer -> Referenz 100,5, kein
    // Aufstieg. 103,4: 2,9 darüber, zählt nicht. 103,5: genau 3,0 -> +3.
    // Letzter Wert ohne Vertikalgenauigkeit bleibt (103,5, +0), wird gezählt.
    // Aufstieg 4 + 3 = 7.
    final r = RunPreprocessor(start: t0);
    final values = <double>[
      100.0,
      101,
      99,
      135,
      104,
      100.5,
      103.4,
      103.5,
      103.5,
    ];
    for (var i = 0; i < values.length; i++) {
      r.addAltitude(
        alt(i * 40, values[i], va: i == 3 ? 30 : (i == 8 ? null : 5)),
      );
    }
    final a = r.result(at: at(320)).altitude;
    expect(a.ascentMeters, 7);
    expect(a.processed[3].reason, DiscardReason.verticalAccuracy);
    expect(a.withoutVerticalAccuracy, 1);
    expect(a.acceptedValues, hasLength(8));
  });

  test('FR-0045: Lauf mit und ohne Ausreißer liefert je Kanal dasselbe', () {
    RunPreprocessing run({required bool outliers}) {
      final r = RunPreprocessor(start: t0);
      for (final p in track(0, 10)) {
        if (p.time == at(5) && !outliers) continue;
        r.addPosition(outliers && p.time == at(5) ? pos(5, 600) : p);
      }
      for (final h in beat(0, 10, 140)) {
        if (h.time == at(5) && !outliers) continue;
        r.addHeartRate(outliers && h.time == at(5) ? hr(5, 220) : h);
      }
      for (var s = 0; s <= 10; s += 5) {
        if (s == 5 && !outliers) continue;
        r.addAltitude(outliers && s == 5 ? alt(5, 900, va: 80) : alt(s, 100));
      }
      return r.result(at: at(10));
    }

    final a = run(outliers: true);
    final b = run(outliers: false);
    expect(a.position.distanceMeters, closeTo(b.position.distanceMeters, 1e-9));
    expect(a.pace.medianSpeed, b.pace.medianSpeed);
    expect(a.movement.movingTime, b.movement.movingTime);
    expect(a.heartRate.averageBpm, b.heartRate.averageBpm);
    expect(a.heartRate.maxBpm, b.heartRate.maxBpm);
    expect(a.altitude.ascentMeters, b.altitude.ascentMeters);
    expect(a.altitude.medianMeters, b.altitude.medianMeters);
    expect(a.position.positions[5].accepted, isFalse);
    expect(a.heartRate.processed[5].accepted, isFalse);
    expect(a.altitude.processed[1].accepted, isFalse);
  });

  test('FR-0057: alle vier Zustände im Gesamtergebnis, je Kanal', () {
    final r = RunPreprocessor(start: t0);
    r.addPosition(pos(0, 0));
    r.addPosition(pos(1, 3));
    r.addPosition(pos(2, 6, acc: 90)); // verworfen
    r.addPosition(pos(3, 9)); // geschätzt
    r.addHeartRate(hr(0, 140));
    r.addHeartRate(hr(1, 140, contact: SensorContact.poor)); // verworfen
    r.addHeartRate(hr(2, 140, state: MeasurementState.estimated));
    r.addHeartRate(hr(3, 140, state: MeasurementState.unavailable));
    r.addAltitude(alt(0, 100));
    r.addAltitude(alt(1, 100, va: 99)); // verworfen
    r.addAltitude(alt(2, 100, state: MeasurementState.estimated));
    r.addAltitude(alt(3, 100, state: MeasurementState.unavailable));
    r.pause(at(3));
    r.addPosition(pos(4, 12)); // Pause: nicht verfügbar
    final res = r.result(at: at(4));
    const all = {
      MeasurementState.present,
      MeasurementState.estimated,
      MeasurementState.unavailable,
      MeasurementState.discarded,
    };
    expect({for (final p in res.position.positions) p.state}, all);
    expect({for (final p in res.heartRate.processed) p.state}, all);
    expect({for (final p in res.altitude.processed) p.state}, all);
  });
}
