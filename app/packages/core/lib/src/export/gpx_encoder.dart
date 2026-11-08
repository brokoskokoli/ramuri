import 'export_run.dart';
import 'xml_text.dart';

const String _gpxNs = 'http://www.topografix.com/GPX/1/1';
const String _tpxNs = 'http://www.garmin.com/xmlschemas/TrackPointExtension/v1';

/// Höchster Abstand, in dem Höhe und Puls an eine Position gehängt werden
/// (Abbildungsregel 4).
const Duration gpxAttachWindow = Duration(seconds: 1);

/// GPX 1.1 mit Garmin TrackPointExtension v1 für den Puls
/// (`docs/contracts/file-export.md`). Ein `trkpt` entsteht nur aus einer
/// gemessenen Position; Höhe und Puls kommen vom nächsten Wert desselben
/// Abschnitts innerhalb von [gpxAttachWindow], sonst fehlen sie. Jeder Abschnitt
/// mit Positionen wird ein `trkseg`.
String encodeGpx(ExportRun run) {
  final name = xmlText(run.name);
  final b = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
    ..writeln(
      '<gpx version="1.1" creator="ramuri" xmlns="$_gpxNs" '
      'xmlns:gpxtpx="$_tpxNs" '
      'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
      'xsi:schemaLocation="$_gpxNs http://www.topografix.com/GPX/1/1/gpx.xsd '
      '$_tpxNs https://www8.garmin.com/xmlschemas/TrackPointExtensionv1.xsd">',
    )
    ..writeln('  <metadata>')
    ..writeln('    <name>$name</name>')
    ..writeln('    <time>${xmlTime(run.startedAt)}</time>')
    ..writeln('  </metadata>')
    ..writeln('  <trk>')
    ..writeln('    <name>$name</name>')
    ..writeln('    <type>running</type>');
  for (final s in run.segments) {
    final altitudes = [
      for (final p in s.points)
        if (p.altitudeMeters != null) (p.time, p.altitudeMeters!),
    ];
    final heartRates = [
      for (final p in s.points)
        if (p.heartRateBpm != null) (p.time, p.heartRateBpm!),
    ];
    final positioned = [
      for (final p in s.points)
        if (p.position != null) p,
    ];
    if (positioned.isEmpty) continue;
    b.writeln('    <trkseg>');
    for (final p in positioned) {
      final pos = p.position!;
      b.writeln(
        '      <trkpt lat="${xmlDecimal(pos.latitude)}" '
        'lon="${xmlDecimal(pos.longitude)}">',
      );
      final ele = _nearest(altitudes, p.time);
      if (ele != null) b.writeln('        <ele>${xmlDecimal(ele)}</ele>');
      b.writeln('        <time>${xmlTime(p.time)}</time>');
      final hr = _nearest(heartRates, p.time);
      if (hr != null) {
        b
          ..writeln('        <extensions>')
          ..writeln('          <gpxtpx:TrackPointExtension>')
          ..writeln('            <gpxtpx:hr>$hr</gpxtpx:hr>')
          ..writeln('          </gpxtpx:TrackPointExtension>')
          ..writeln('        </extensions>');
      }
      b.writeln('      </trkpt>');
    }
    b.writeln('    </trkseg>');
  }
  b
    ..writeln('  </trk>')
    ..writeln('</gpx>');
  return b.toString();
}

/// Wert mit dem kleinsten Zeitabstand zu [t] innerhalb [gpxAttachWindow]; bei
/// Gleichstand der frühere. [values] ist nach Zeit sortiert.
T? _nearest<T>(List<(DateTime, T)> values, DateTime t) {
  final us = t.microsecondsSinceEpoch;
  var lo = 0;
  var hi = values.length;
  while (lo < hi) {
    final mid = (lo + hi) >> 1;
    if (values[mid].$1.microsecondsSinceEpoch < us) {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }
  T? best;
  var bestDistance = gpxAttachWindow.inMicroseconds + 1;
  for (final i in [lo - 1, lo]) {
    if (i < 0 || i >= values.length) continue;
    final d = (values[i].$1.microsecondsSinceEpoch - us).abs();
    if (d < bestDistance) {
      best = values[i].$2;
      bestDistance = d;
    }
  }
  return best;
}
