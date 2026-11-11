import 'package:core/core.dart';
import 'package:test/test.dart';

import '../preprocessing/hr_support.dart';

HeartRateMeasurement? p(List<int> d) => HeartRateParser.parseMeasurement(d);

void main() {
  group('0x2A37 Wertformat', () {
    test('8 Bit', () {
      expect(p([0x00, 72])?.beatsPerMinute, 72);
      expect(p([0x00, 255])?.beatsPerMinute, 255);
    });
    test('16 Bit little endian', () {
      expect(p([0x01, 0x2C, 0x01])?.beatsPerMinute, 300);
      expect(p([0x01, 72, 0x00])?.beatsPerMinute, 72);
    });
    test('RR und Energie dahinter werden ignoriert', () {
      // Flags: Energie (Bit 3) und RR (Bit 4), Wert 8 Bit.
      expect(p([0x18, 80, 1, 0, 0x20, 0x03])?.beatsPerMinute, 80);
      // Auch mit abgeschnittenem RR-Teil: der Wert bleibt gültig.
      expect(p([0x10, 80, 0x20])?.beatsPerMinute, 80);
    });
  });

  group('RR-Intervalle (FR-0213)', () {
    List<int>? rr(List<int> d) => p(d)?.rrIntervals;
    test('ein Wert, 8-Bit-Puls (Flags 0x10)', () {
      expect(rr([0x10, 60, 0x00, 0x04]), [1024]);
    });
    test('mehrere Werte je Paket, Reihenfolge und LE', () {
      expect(rr([0x10, 60, 0x00, 0x04, 0x34, 0x12, 0xFF, 0xFF]), [
        1024,
        0x1234,
        65535,
      ]);
    });
    test('16-Bit-Puls (Flags 0x11)', () {
      final m = p([0x11, 0x2C, 0x01, 0x20, 0x03])!;
      expect(m.beatsPerMinute, 300);
      expect(m.rrIntervals, [800]);
    });
    test('Energy Expended davor (Flags 0x18 und 0x19)', () {
      expect(rr([0x18, 80, 0xAA, 0xBB, 0x20, 0x03, 0x00, 0x00]), [800, 0]);
      final m = p([0x19, 80, 0, 0xAA, 0xBB, 0x20, 0x03])!;
      expect(m.beatsPerMinute, 80);
      expect(m.rrIntervals, [800]);
    });
    test('Wert 0 bleibt erhalten, keine Umrechnung', () {
      expect(rr([0x10, 60, 0, 0]), [0]);
    });
    test('Flag gesetzt, aber keine Bytes: leer, Puls bleibt', () {
      final m = p([0x10, 60])!;
      expect(m.beatsPerMinute, 60);
      expect(m.rrIntervals, isEmpty);
    });
    test('ungerade Länge: loses Byte entfällt, vollständige Werte bleiben', () {
      expect(rr([0x10, 60, 0x00, 0x04, 0x99]), [1024]);
      final m = p([0x10, 60, 0x99])!;
      expect(m.beatsPerMinute, 60);
      expect(m.rrIntervals, isEmpty);
    });
    test('Energie angekündigt, aber abgeschnitten: Puls bleibt, RR leer', () {
      final m = p([0x18, 80, 0xAA])!;
      expect(m.beatsPerMinute, 80);
      expect(m.rrIntervals, isEmpty);
    });
    test('ohne Flag-Bit 4 sind Zusatzbytes keine RR', () {
      expect(rr([0x00, 60, 0x00, 0x04]), isEmpty);
      expect(rr([0x08, 60, 0x01, 0x00, 0x00, 0x04]), isEmpty);
    });
    test('RR ändert Puls und Kontakt nicht, toString ohne Werte', () {
      final m = p([0x16, 72, 0x34, 0x12])!;
      expect(m.beatsPerMinute, 72);
      expect(m.contact, SensorContact.good);
      expect(m.toString(), isNot(contains('4660')));
      expect(m, p([0x16, 72, 0x34, 0x12]));
      expect(m == p([0x16, 72, 0x35, 0x12]), isFalse);
    });
    test('Liste ist unveränderlich', () {
      expect(() => rr([0x10, 60, 1, 0])!.add(1), throwsUnsupportedError);
    });
  });

  group('Kontaktbit (PAR-008)', () {
    SensorContact? c(int flags) => p([flags, 70])?.contact;
    test('nicht unterstützt (00 und 01)', () {
      expect(c(0x00), SensorContact.unsupported);
      expect(c(0x02), SensorContact.unsupported); // Bits 1-2 = 01
    });
    test('unterstützt, kein Kontakt', () {
      expect(c(0x04), SensorContact.poor); // Bits 1-2 = 10
    });
    test('unterstützt, Kontakt erkannt', () {
      expect(c(0x06), SensorContact.good); // Bits 1-2 = 11
    });
    test('16 Bit mit Kontakt', () {
      expect(p([0x07, 70, 0])?.contact, SensorContact.good);
      expect(p([0x05, 70, 0])?.contact, SensorContact.poor);
    });
  });

  group('kaputte Pakete', () {
    test('leer, nur Flags, 16 Bit mit einem Byte: kein Wert', () {
      expect(p([]), isNull);
      expect(p([0x00]), isNull);
      expect(p([0x01]), isNull);
      expect(p([0x01, 70]), isNull);
    });
    test('Bytes außerhalb 0..255: kein Wert, kein Absturz', () {
      expect(p([0x00, 300]), isNull);
      expect(p([0x00, -1]), isNull);
    });
  });

  group('PAR-007 und PAR-008 im Filter', () {
    HeartRateMeasurement m(List<int> d) => p(d)!;
    String verdict(List<int> d) {
      final x = m(d);
      final r = runHr([hr(1, x.beatsPerMinute, contact: x.contact)]);
      return '${r.processed.single.state.name}/${r.processed.single.reason?.name}';
    }

    test('Grenzen 30 und 240 gelten, 29 und 241 nicht', () {
      expect(verdict([0, 30]), 'present/null');
      expect(verdict([0, 240]), 'present/null');
      expect(verdict([0, 29]), 'discarded/implausibleHeartRate');
      expect(verdict([0, 241]), 'discarded/implausibleHeartRate');
      expect(verdict([0x01, 0x2C, 0x01]), 'discarded/implausibleHeartRate');
      expect(verdict([0, 0]), 'discarded/implausibleHeartRate');
    });
    test(
      'kein Kontakt wird verworfen, gesetzt und nicht unterstützt zählen',
      () {
        expect(verdict([0x04, 70]), 'discarded/noContact');
        expect(verdict([0x06, 70]), 'present/null');
        expect(verdict([0x00, 70]), 'present/null');
      },
    );
  });

  group('0x2A19 Batterie', () {
    test('Prozent', () {
      expect(HeartRateParser.parseBattery([87]), 87);
      expect(HeartRateParser.parseBattery([0]), 0);
      expect(HeartRateParser.parseBattery([100]), 100);
    });
    test('leer oder über 100: kein Wert', () {
      expect(HeartRateParser.parseBattery([]), isNull);
      expect(HeartRateParser.parseBattery([101]), isNull);
      expect(HeartRateParser.parseBattery([255]), isNull);
    });
  });
}
