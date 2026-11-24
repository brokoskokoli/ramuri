import '../recording/treadmill.dart';
import 'export_run.dart';
import 'xml_text.dart';

const String _tcxNs =
    'http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2';
const String _tpxNs = 'http://www.garmin.com/xmlschemas/ActivityExtension/v2';

/// TCX (TrainingCenterDatabase v2, `docs/contracts/file-export.md`). Jede
/// Runde wird ein `Lap`, jeder Abschnitt darin mit Punkten ein `Track`. Ein
/// `Trackpoint` trägt nur die an seinem Zeitstempel gemessenen Werte. Die
/// Pflichtfelder der Runde sind minimal gefüllt: `TotalTimeSeconds` =
/// Zeit ohne Pausen, `DistanceMeters` = Summe der Großkreisabstände
/// aufeinanderfolgender Positionen je Abschnitt, `Calories` = 0. Bandlauf
/// (FR-0196): Trackpoints ohne `Position`, mit der kumulierten
/// `DistanceMeters` aus den Bandeinstellungen; die Rundenstrecke ist deren
/// Zuwachs. TCX kennt keine Laufbandkennzeichnung (Sport nur Running, Biking,
/// Other). Schrittfrequenz: `Extensions/TPX/RunCadence` der ActivityExtension
/// v2 (Doppelschritte je Minute); der Namensraum steht nur in Dateien mit
/// Schrittfrequenz. Andere Sportart (FR-0221): [tcxSport], Trackpoints nur
/// mit Zeit und Puls, `Lap/DistanceMeters` = 0.
String encodeTcx(ExportRun run) {
  final distances = run.lapDistancesMeters();
  final withCadence = run.segments.any(
    (s) => s.points.any(
      (p) => exportStrideCadence(p.cadenceStepsPerMinute) != null,
    ),
  );
  final b = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
    ..writeln(
      '<TrainingCenterDatabase xmlns="$_tcxNs" '
      '${withCadence ? 'xmlns:tpx="$_tpxNs" ' : ''}'
      'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
      'xsi:schemaLocation="$_tcxNs '
      'https://www8.garmin.com/xmlschemas/TrainingCenterDatabasev2.xsd">',
    )
    ..writeln('  <Activities>')
    ..writeln('    <Activity Sport="${tcxSport(run.sport)}">')
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
          if (run.lapIndexAt(p.time) == i) p,
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
        final dist = p.distanceMeters;
        if (dist != null) {
          b.writeln(
            '            <DistanceMeters>${xmlDecimal(dist)}</DistanceMeters>',
          );
        }
        final hr = p.heartRateBpm;
        if (hr != null) {
          b.writeln(
            '            <HeartRateBpm><Value>$hr</Value></HeartRateBpm>',
          );
        }
        final cadence = exportStrideCadence(p.cadenceStepsPerMinute);
        if (cadence != null) {
          b
            ..writeln('            <Extensions>')
            ..writeln(
              '              <tpx:TPX><tpx:RunCadence>$cadence'
              '</tpx:RunCadence></tpx:TPX>',
            )
            ..writeln('            </Extensions>');
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

/// `Activity/@Sport` (TCX kennt nur `Running`, `Biking`, `Other`): Läufe
/// `Running`, Radfahren `Biking`, die übrigen Sportarten `Other` (FR-0221).
String tcxSport(OtherSport? sport) => switch (sport) {
  null => 'Running',
  OtherSport.cycling => 'Biking',
  OtherSport.rope || OtherSport.rowing || OtherSport.other => 'Other',
};
