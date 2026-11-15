import 'dart:convert';
import 'dart:typed_data';

import '../../ports/file_handoff.dart';
import '../../ports/storage_morning.dart';
import '../ppg/ppg_evaluator.dart' show PpgFrame;
import '../preprocessing/measurement.dart' show RrPacket;

/// Formatversion der Messpaare-CSV (`docs/contracts/morning-pairs-csv.md`).
const int morningPairsCsvFormatVersion = 2;

/// MIME-Typ der Datei.
const String morningPairsCsvMimeType = 'text/csv';

/// Kopfzeile der Formatversion 2 (Vertrag Abschnitt 3).
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
    this.rawSignal,
  });

  final int id;
  final MorningMeasurement measurement;

  /// Roh gespeicherte Gurt-RR-Pakete nach Empfangszeit; leer ohne Gurt.
  final List<RrPacket> beltPackets;

  /// Kamera-Rohsignal (nur Entwicklermodus); `null` = keins gespeichert, dann
  /// gibt es keine `raw_frame`-Zeilen.
  final MorningRawSignal? rawSignal;
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
    row('meta', 'usable', value: m.isUsable ? '1' : '0');
    row('meta', 'quality_reason', value: m.unusableReason?.name ?? '');
    row('meta', 'window_start', value: num(m.windowStartS), unit: 's');
    row('meta', 'window_end', value: num(m.windowEndS), unit: 's');
    row(
      'meta',
      'rest_skipped_after',
      value: num(m.restSkippedAfterS),
      unit: 's',
    );
    row('meta', 'before_validation', value: m.beforeValidation ? '1' : '0');
    row('meta', 'outside_window', value: m.outsideWindow ? '1' : '0');
    row('meta', 'sleep_band', value: m.sleepBand?.code ?? '');
    row('meta', 'belt_packets', value: '${p.beltPackets.length}');
    final raw = p.rawSignal;
    row('meta', 'raw_frames', value: '${raw?.frames.length ?? 0}');
    if (raw != null) {
      String n(Object? v) => v == null ? '' : '$v';
      row('meta', 'exposure_time', value: n(raw.exposureTimeNs), unit: 'ns');
      row('meta', 'iso', value: n(raw.iso));
      row('meta', 'timestamp_source', value: raw.timestampSource?.code ?? '');
      row(
        'meta',
        'rolling_shutter_skew',
        value: n(raw.rollingShutterSkewNs),
        unit: 'ns',
      );
      row('meta', 'torch_strength', value: n(raw.torchStrength));
      row('meta', 'frame_gap_count', value: '${raw.frameGapCount}');
      row('meta', 'frame_gap_total', value: num(raw.frameGapTotalS), unit: 's');
      row('meta', 'saturated_fraction', value: num(raw.saturatedFraction));
    }
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
    if (raw != null) {
      for (final (i, f) in raw.frames.indexed) {
        row('raw_frame', 'frame', seq: '${i + 1}', value: _frameValue(f));
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
        rawSignal: await store.rawSignal(e.id),
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

/// Ein Bild als 35 Zahlen mit `;` getrennt: t, r, g, r16[0..15], g16[0..15]
/// (Vertrag Abschnitt 4). Verlustfrei: kürzeste Dezimalform, die beim Lesen
/// wieder genau dieselbe Zahl (float64) ergibt.
String _frameValue(PpgFrame f) =>
    [f.t, f.r, f.g, ...f.r16, ...f.g16].map(_exact).join(';');

/// Kürzeste Dezimalform, die zurückgelesen genau [v] ergibt, nie mit Exponent.
String _exact(double v) {
  final s = '$v';
  if (!s.contains('e')) return s;
  if (v.abs() >= 1) return '${BigInt.from(v)}.0';
  // Sehr kleine Beträge (unter 1e-6; für Pixelmittel ohne Bedeutung): feste
  // Form mit 20 Nachkommastellen, Rundung höchstens 5e-21.
  return v.toStringAsFixed(20);
}

String _time(DateTime t) => t.toUtc().toIso8601String();

String _line(List<String> fields) => '${fields.map(_field).join(',')}\r\n';

String _field(String s) {
  if (!s.contains(RegExp(r'[",\r\n]'))) return s;
  return '"${s.replaceAll('"', '""')}"';
}
