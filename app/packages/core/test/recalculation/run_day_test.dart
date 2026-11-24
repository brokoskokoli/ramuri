// Tag eines Laufs (PAR-237): Ein Lauf zählt am Ortstag seines Starts, auch
// über Mitternacht. Alle Zeitpunkte sind feste UTC-Zeitpunkte mit dem am Lauf
// gespeicherten Versatz; das Ergebnis hängt nicht von der Zone des Prozesses
// ab (auch in der Zeitzonen-Matrix des Gates).
import 'package:core/core.dart';
import 'package:test/test.dart';

import 'recalc_support.dart';

StoredRun _run(DateTime startUtc, Duration length, Duration? offset) =>
    StoredRun(
      id: 1,
      state: RunState.finished,
      startedAt: startUtc,
      endedAt: startUtc.add(length),
      endedUtcOffset: offset,
    );

void main() {
  group('dayOfRun: Ortstag des Laufbeginns (PAR-237)', () {
    test('23:30–00:40 Ortszeit bei +1 h zählt am Starttag', () {
      // 23:30 Ortszeit = 22:30 UTC; Ende 00:40 Ortszeit am Folgetag.
      final r = _run(
        DateTime.utc(2030, 2, 20, 22, 30),
        const Duration(minutes: 70),
        const Duration(hours: 1),
      );
      expect(dayOfRun(r), '2030-02-20');
      expect(runStartLocalDay(r), DateTime.utc(2030, 2, 20));
      expect(runStartLocal(r), DateTime.utc(2030, 2, 20, 23, 30));
    });

    test('ohne Versatz gilt der UTC-Tag des Starts', () {
      final r = _run(
        DateTime.utc(2030, 2, 20, 23, 30),
        const Duration(minutes: 70),
        null,
      );
      expect(dayOfRun(r), '2030-02-20');
    });

    test('08:00–09:00 bleibt am selben Tag', () {
      final r = _run(
        DateTime.utc(2030, 2, 20, 7),
        const Duration(hours: 1),
        const Duration(hours: 1),
      );
      expect(dayOfRun(r), '2030-02-20');
    });

    test('Versatz −5 h: Start 22:00 Ortszeit = 03:00 UTC am Folgetag zählt '
        'am Ortstag, nicht am UTC-Tag', () {
      final r = _run(
        DateTime.utc(2030, 2, 21, 3),
        const Duration(minutes: 90),
        const Duration(hours: -5),
      );
      expect(dayOfRun(r), '2030-02-20');
    });

    test('Sommerzeit-Nacht Ende Oktober (Europa/Berlin): 01:30 MESZ bis '
        '03:30 MEZ zählt an einem Tag, dem Starttag', () {
      // 25.10.2026: 01:30 MESZ = 23:30 UTC (24.10.), 03:30 MEZ = 02:30 UTC.
      // Am Lauf steht der Versatz des Endes (+1 h).
      final r = _run(
        DateTime.utc(2026, 10, 24, 23, 30),
        const Duration(hours: 3),
        const Duration(hours: 1),
      );
      expect(dayOfRun(r), '2026-10-25');
    });

    test('Sommerzeit-Nacht Ende März (Europa/Berlin): 01:30 MEZ bis 03:30 '
        'MESZ zählt an einem Tag, dem Starttag', () {
      // 29.03.2026: 01:30 MEZ = 00:30 UTC, 03:30 MESZ = 01:30 UTC; Versatz
      // des Endes +2 h.
      final r = _run(
        DateTime.utc(2026, 3, 29, 0, 30),
        const Duration(hours: 1),
        const Duration(hours: 2),
      );
      expect(dayOfRun(r), '2026-03-29');
    });

    test(
      'Plan und Tageswerte rechnen gleich (PAR-231 verweist auf PAR-237)',
      () {
        final r = _run(
          DateTime.utc(2030, 2, 20, 22, 30),
          const Duration(minutes: 70),
          const Duration(hours: 1),
        );
        expect(
          isoDay(planRunStartDay(r, fallbackOffset: Duration.zero)),
          dayOfRun(r),
        );
      },
    );
  });

  group('Zeitraum-Abfrage nach dem Laufbeginn (PAR-237)', () {
    // Zeitraum 2030-02-10 bis 2030-02-16 (UTC-Mitternacht), Versatz +1 h.
    final first = DateTime.utc(2030, 2, 10);
    final last = DateTime.utc(2030, 2, 16);

    Future<List<int>> inPeriod(StorageSession s) async {
      final b = runDayQueryBounds(first, last);
      final found = await s.runs.finishedBetween(b.from, b.to);
      return [
        for (final r in found)
          if (dayOfRun(r).compareTo(isoDay(first)) >= 0 &&
              dayOfRun(r).compareTo(isoDay(last)) <= 0)
            r.id,
      ];
    }

    Future<int> finished(StorageSession s, DateTime start, DateTime end) async {
      final r = await s.runs.create(startedAt: start);
      await s.runs.setState(
        r.id,
        RunState.finished,
        endedAt: end,
        endedUtcOffset: const Duration(hours: 1),
      );
      return r.id;
    }

    test('Lauf am letzten Tag 23:50 bis 00:30 danach ist dabei; Lauf am '
        'Vortag 23:50 bis 00:30 am ersten Tag nicht', () async {
      final w = await RecalcWorld.create();
      final s = w.session;
      // 23:50 Ortszeit = 22:50 UTC.
      final lastDay = await finished(
        s,
        DateTime.utc(2030, 2, 16, 22, 50),
        DateTime.utc(2030, 2, 16, 23, 30),
      );
      final dayBefore = await finished(
        s,
        DateTime.utc(2030, 2, 9, 22, 50),
        DateTime.utc(2030, 2, 9, 23, 30),
      );
      final ids = await inPeriod(s);
      expect(ids, contains(lastDay));
      expect(ids, isNot(contains(dayBefore)));
    });

    test('Puffer hinten reicht für den größten Versatz: Start am letzten Tag '
        '23:59 bei −12 h, Ende 8 h später', () async {
      final w = await RecalcWorld.create();
      final r = await w.session.runs.create(
        startedAt: DateTime.utc(2030, 2, 17, 11, 59),
      );
      await w.session.runs.setState(
        r.id,
        RunState.finished,
        endedAt: DateTime.utc(2030, 2, 17, 19, 59),
        endedUtcOffset: const Duration(hours: -12),
      );
      expect(await inPeriod(w.session), [r.id]);
    });
  });

  group('Neuberechnung: Tageswerte vom Endtag an den Starttag (PAR-237)', () {
    test('Tageswert des Starttags enthält den Lauf über Mitternacht, der '
        'Folgetag hat keinen eigenen', () async {
      final w = await RecalcWorld.create();
      final id = await w.seedRun(
        DateTime.utc(2030, 2, 20, 22, 30),
        minutes: 70,
        utcOffset: const Duration(hours: 1),
      );
      await w.calc().calculateAfterRun(id);
      final days = await w.daysWithValues('2030-02-19', '2030-02-22');
      expect(days.keys, ['2030-02-20']);
      final long = days['2030-02-20']!
          .firstWhere((p) => p.current.key == vo2maxLongTermValueKey)
          .current;
      expect(long.measurementCount, 1);
      expect(long.value, isNotNull);
    });

    test('alter Tageswert am Endtag löst ein Angebot aus; danach hängt er am '
        'Starttag und am Endtag steht keiner mehr', () async {
      final w = await RecalcWorld.create();
      // 23:30–00:40 Ortszeit bei +1 h.
      final id = await w.seedRun(
        DateTime.utc(2030, 2, 20, 22, 30),
        minutes: 70,
        utcOffset: const Duration(hours: 1),
      );
      // Stand der alten Version: Laufwerte mit Kettenstufe day1, Tageswerte
      // am Tag des Laufendes.
      await ValueCalculationService(
        session: w.session,
        clock: w.clock,
        preprocessingVersion: preprocessingChainVersion(runDay: 1),
      ).calculateAfterRun(id);
      const startDay = '2030-02-20';
      const endDay = '2030-02-21';
      final atStart = await w.session.values.read(
        const ValueOwner.day(startDay),
      );
      expect(atStart, isNotEmpty);
      await w.session.values.writeAll(
        create: {
          const ValueOwner.day(endDay): [for (final p in atStart) p.original],
        },
        removeDays: {startDay},
      );
      expect(await w.daysWithValues('2030-02-19', '2030-02-22'), {
        endDay: isNotEmpty,
      });

      final offer = await w.recalc().checkVersions();
      expect(offer, isNotNull);
      await w.recalc().confirm(offer!);

      final days = await w.daysWithValues('2030-02-19', '2030-02-22');
      expect(days.keys, [startDay]);
      expect(
        {for (final p in days[startDay]!) p.current.key},
        {for (final p in atStart) p.original.key},
      );
      expect(await w.recalc().checkVersions(), isNull);
    });
  });
}
