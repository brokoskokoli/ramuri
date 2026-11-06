import '../preprocessing/geo.dart';
import 'export_run.dart';
import 'xml_text.dart';

const String _tcxNs =
    'http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2';

/// TCX (TrainingCenterDatabase v2, `docs/contracts/file-export.md`). Jede
/// Runde wird ein `Lap`, jeder Abschnitt darin mit Punkten ein `Track`. Ein
/// `Trackpoint` trägt nur die an seinem Zeitstempel gemessenen Werte. Die
/// Pflichtfelder der Runde sind minimal gefüllt: `TotalTimeSeconds` =
/// Zeit ohne Pausen, `DistanceMeters` = Summe der Großkreisabstände
/// aufeinanderfolgender Positionen je Abschnitt, `Calories` = 0.
String encodeTcx(ExportRun run) {
  final distances = _lapDistances(run);
  final b = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
    ..writeln(
      '<TrainingCenterDatabase xmlns="$_tcxNs" '
      'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
      'xsi:schemaLocation="$_tcxNs '
      'https://www8.garmin.com/xmlschemas/TrainingCenterDatabasev2.xsd">',
    )
    ..writeln('  <Activities>')
    ..writeln('    <Activity Sport="Running">')
    ..writeln('      <Id>${xmlTime(run.startedAt)}</Id>');
  for (var i = 0; i < run.laps.length; i++) {
    final lap = run.laps[i];
    final seconds =
        run.activeTimeWithin(lap.start, lap.end).inMicroseconds / 1e6;
    b
      ..writeln('      <Lap StartTime="${xmlTime(lap.start)}">')
      ..writeln(
        '        <TotalTimeSeconds>${xmlDecimal(seconds)}</TotalTimeSeconds>',
      )
      ..writeln(
        '        <DistanceMeters>'
        '${xmlDecimal((distances[i] * 1000).roundToDouble() / 1000)}'
        '</DistanceMeters>',
      )
      ..writeln('        <Calories>0</Calories>')
      ..writeln('        <Intensity>Active</Intensity>')
      ..writeln('        <TriggerMethod>Manual</TriggerMethod>');
    for (final s in run.segments) {
      final points = [
        for (final p in s.points)
          if (_lapOf(run, p.time) == i) p,
      ];
      if (points.isEmpty) continue;
      b.writeln('        <Track>');
      for (final p in points) {
        b
          ..writeln('          <Trackpoint>')
          ..writeln('            <Time>${xmlTime(p.time)}</Time>');
        final pos = p.position;
        if (pos != null) {
          b
            ..writeln('            <Position>')
            ..writeln(
              '              <LatitudeDegrees>${xmlDecimal(pos.latitude)}'
              '</LatitudeDegrees>',
            )
            ..writeln(
              '              <LongitudeDegrees>${xmlDecimal(pos.longitude)}'
              '</LongitudeDegrees>',
            )
            ..writeln('            </Position>');
        }
        final ele = p.altitudeMeters;
        if (ele != null) {
          b.writeln(
            '            <AltitudeMeters>${xmlDecimal(ele)}</AltitudeMeters>',
          );
        }
        final hr = p.heartRateBpm;
        if (hr != null) {
          b.writeln(
            '            <HeartRateBpm><Value>$hr</Value></HeartRateBpm>',
          );
        }
        b.writeln('          </Trackpoint>');
      }
      b.writeln('        </Track>');
    }
    b.writeln('      </Lap>');
  }
  b
    ..writeln('    </Activity>')
    ..writeln('  </Activities>')
    ..writeln('</TrainingCenterDatabase>');
  return b.toString();
}

/// Index der letzten Runde, deren Start nicht nach [t] liegt (sonst 0).
int _lapOf(ExportRun run, DateTime t) {
  var index = 0;
  for (var i = 0; i < run.laps.length; i++) {
    if (!run.laps[i].start.isAfter(t)) index = i;
  }
  return index;
}

/// Strecke je Runde: Abstand aufeinanderfolgender Positionen desselben
/// Abschnitts, der Runde des späteren Punkts zugerechnet.
List<double> _lapDistances(ExportRun run) {
  final out = List<double>.filled(run.laps.length, 0);
  for (final s in run.segments) {
    ExportPosition? previous;
    for (final p in s.points) {
      final pos = p.position;
      if (pos == null) continue;
      if (previous != null) {
        out[_lapOf(run, p.time)] += haversineMeters(
          previous.latitude,
          previous.longitude,
          pos.latitude,
          pos.longitude,
        );
      }
      previous = pos;
    }
  }
  return out;
}
