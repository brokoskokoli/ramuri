import 'dart:io';

import 'package:adapters/adapters.dart' hide RawHeartRate;
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// Speicherbedarf der RR-Reihe (WP26, FR-0213): 2 h bei 180 bpm, synthetisch.
/// Die Zahl steht im Bericht; die Prüfungen fangen Fehler im Aufbau ab
/// (Positivkontrolle: Zeilen wirklich geschrieben, Datei wirklich gewachsen).
void main() {
  const packets = 7200; // 2 h, ein Paket je Sekunde
  const perPacket = 3; // 21600 Werte
  final t0 = DateTime.utc(2030, 1, 1, 12);

  Future<int> sizeWith(
    Directory dir,
    String name, {
    required bool hr,
    required bool rr,
  }) async {
    final path = '${dir.path}/$name.db';
    final s =
        await EncryptedStorage(path).open(testKey()) as EncryptedStorageSession;
    final run = (await s.runs.create(startedAt: t0)).id;
    for (var from = 0; from < packets; from += 100) {
      await s.rawData.append(
        run,
        RawBatch(
          heartRates: hr
              ? [
                  for (var i = from; i < from + 100; i++)
                    RawHeartRate(
                      time: t0.add(Duration(seconds: i)),
                      source: 'AA:BB:CC:DD:EE:FF',
                      bpm: 180,
                      contact: SensorContact.good,
                    ),
                ]
              : const [],
          rrPackets: rr
              ? [
                  for (var i = from; i < from + 100; i++)
                    RrPacket(
                      time: t0.add(Duration(seconds: i)),
                      source: 'AA:BB:CC:DD:EE:FF',
                      intervals: [
                        for (var k = 0; k < perPacket; k++)
                          341 + (i * 7 + k * 13) % 40,
                      ],
                    ),
                ]
              : const [],
        ),
      );
    }
    final data = await s.rawData.read(run);
    expect(data.rrPackets.length, rr ? packets : 0);
    expect(data.heartRates.length, hr ? packets : 0);
    if (rr) {
      expect(
        data.rrPackets.fold<int>(0, (n, p) => n + p.value.intervals.length),
        packets * perPacket,
      );
    }
    await s.database.customSelect('PRAGMA wal_checkpoint(TRUNCATE)').get();
    await s.close();
    return File(path).lengthSync();
  }

  test('2 h bei 180 bpm: Dateizuwachs durch RR', () async {
    final dir = tempDir();
    addTearDown(() => dir.deleteSync(recursive: true));
    final empty = await sizeWith(dir, 'empty', hr: false, rr: false);
    final hrOnly = await sizeWith(dir, 'hr', hr: true, rr: false);
    final rrOnly = await sizeWith(dir, 'rr', hr: false, rr: true);
    final both = await sizeWith(dir, 'both', hr: true, rr: true);
    // ignore: avoid_print
    print(
      'RR-Speicher: leer=$empty B, nur Puls=$hrOnly B (+${hrOnly - empty}), '
      'nur RR=$rrOnly B (+${rrOnly - empty}), beides=$both B; '
      'RR-Zuwachs neben Puls=${both - hrOnly} B; '
      'Nutzdaten ${packets * perPacket * 2} B',
    );
    expect(rrOnly, greaterThan(empty));
    // Untergrenze: mindestens die Nutzdaten (2 Byte je Wert).
    expect(rrOnly - empty, greaterThan(packets * perPacket * 2));
    expect(both, greaterThan(hrOnly));
  }, timeout: const Timeout(Duration(minutes: 3)));
}
