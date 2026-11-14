import 'dart:convert';
import 'dart:typed_data';

import '../../ports/file_handoff.dart';
import '../../ports/storage_morning.dart';
import '../preprocessing/measurement.dart' show RrPacket;

/// Formatversion der Messpaare-CSV (`docs/contracts/morning-pairs-csv.md`).
const int morningPairsCsvFormatVersion = 1;

/// MIME-Typ der Datei.
const String morningPairsCsvMimeType = 'text/csv';

/// Kopfzeile der Formatversion 1 (Vertrag Abschnitt 3).
const List<String> morningPairsCsvColumns = [
  'format_version',
  'morning_id',
  'row_type',
  'key',
  'seq',
  'sub',
  'time',
  'value',
  'unit',
];

/// Eine Morgenmessung mit der Gurt-RR derselben Zeit, Eingabe des Kodierers.
class MorningPair {
  const MorningPair({
    required this.id,
    required this.measurement,
    this.beltPackets = const [],
  });

  final int id;
  final MorningMeasurement measurement;

  /// Roh gespeicherte Gurt-RR-Pakete nach Empfangszeit; leer ohne Gurt.
  final List<RrPacket> beltPackets;
}

/// Kodiert die Morgen als CSV nach `docs/contracts/morning-pairs-csv.md`:
/// RFC 4180, UTF-8 (Bytes macht der Aufrufer), CRLF, Dezimalpunkt, je Morgen
/// Zeilen der Arten `meta`, `camera`, `camera_ibi`, `belt_rr`; Morgen nach
/// Zeitpunkt, dann Id. Ein ungültiges Kamera-Intervall (NaN) ist ein leeres
/// Wertfeld. Rein; ohne Morgen bleibt nur die Kopfzeile.
String encodeMorningPairsCsv(Iterable<MorningPair> pairs) {
  final sorted = pairs.toList()
    ..sort((a, b) {
      final t = a.measurement.measuredAt.compareTo(b.measurement.measuredAt);
      return t != 0 ? t : a.id.compareTo(b.id);
    });
  final out = StringBuffer(_line(morningPairsCsvColumns));
  for (final p in sorted) {
    final m = p.measurement;
    void row(
      String type,
      String key, {
      String seq = '',
      String sub = '',
      String time = '',
      String value = '',
      String unit = '',
    }) => out.write(
      _line([
        '$morningPairsCsvFormatVersion',
        '${p.id}',
        type,
        key,
        seq,
        sub,
        time,
        value,
        unit,
      ]),
    );
    String num(double? v) {
      if (v == null) return '';
      final s = '$v';
      if (!s.contains('e')) return s;
      // Keine Exponentschreibweise (Vertrag Abschnitt 2): feste Form mit
      // 12 Nachkommastellen, ohne überzählige Nullen.
      return v
          .toStringAsFixed(12)
          .replaceFirst(RegExp(r'0+$'), '')
          .replaceFirst(RegExp(r'\.$'), '.0');
    }

    row('meta', 'measured_at', time: _time(m.measuredAt));
    row('meta', 'utc_offset', value: '${m.utcOffset.inSeconds}', unit: 's');
    row('meta', 'posture', value: m.posture.storageValue);
    row('meta', 'device_manufacturer', value: m.deviceManufacturer);
    row('meta', 'device_model', value: m.deviceModel);
    row('meta', 'method', value: m.method);
    row('meta', 'method_version', value: '${m.methodVersion}');
    row('meta', 'quality', value: m.quality.name);
    row('meta', 'before_validation', value: m.beforeValidation ? '1' : '0');
    row('meta', 'outside_window', value: m.outsideWindow ? '1' : '0');
    row('meta', 'sleep_band', value: m.sleepBand?.code ?? '');
    row('meta', 'belt_packets', value: '${p.beltPackets.length}');
    row('camera', 'resting_hr', value: num(m.roundedRestingHr), unit: 'bpm');
    row('camera', 'rmssd', value: num(m.rmssdMs), unit: 'ms');
    row('camera', 'timing_noise', value: num(m.timingNoiseMs), unit: 'ms');
    for (final (i, v) in m.cameraIntervalsMs.indexed) {
      row(
        'camera_ibi',
        'ibi',
        seq: '${i + 1}',
        value: v.isNaN ? '' : v.toStringAsFixed(3),
        unit: 'ms',
      );
    }
    for (final (i, packet) in p.beltPackets.indexed) {
      for (final (j, v) in packet.intervals.indexed) {
        row(
          'belt_rr',
          'rr',
          seq: '${i + 1}',
          sub: '${j + 1}',
          time: _time(packet.time),
          value: '$v',
          unit: '1/1024 s',
        );
      }
    }
  }
  return out.toString();
}

/// Anzahl der Morgen mit und ohne Gurt-RR (für den Abschnitt Entwickler).
Future<({int withBelt, int without})> countMorningPairs(
  MorningStore store,
) async {
  var withBelt = 0, without = 0;
  for (final e in await store.list()) {
    if ((await store.beltPackets(e.id)).isEmpty) {
      without++;
    } else {
      withBelt++;
    }
  }
  return (withBelt: withBelt, without: without);
}

/// Liest alle Morgenmessungen samt Gurt-RR und baut die Datei für die
/// Übergabe. Wirft Speicherfehler weiter.
Future<ExportFile> buildMorningPairsCsvFile(
  MorningStore store, {
  required DateTime now,
}) async {
  final pairs = <MorningPair>[];
  for (final e in await store.list()) {
    pairs.add(
      MorningPair(
        id: e.id,
        measurement: e.value,
        beltPackets: [for (final p in await store.beltPackets(e.id)) p.value],
      ),
    );
  }
  final day = now.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return ExportFile(
    fileName:
        'running-morgenpaare-${day.year}${two(day.month)}${two(day.day)}.csv',
    mimeType: morningPairsCsvMimeType,
    bytes: Uint8List.fromList(utf8.encode(encodeMorningPairsCsv(pairs))),
  );
}

String _time(DateTime t) => t.toUtc().toIso8601String();

String _line(List<String> fields) => '${fields.map(_field).join(',')}\r\n';

String _field(String s) {
  if (!s.contains(RegExp(r'[",\r\n]'))) return s;
  return '"${s.replaceAll('"', '""')}"';
}
