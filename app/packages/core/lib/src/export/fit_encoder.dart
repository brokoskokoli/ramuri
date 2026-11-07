import 'dart:typed_data';

import 'export_run.dart';
import 'fit_crc.dart';

/// FIT-Protokollversion 2.0 im Dateikopf (obere 4 Bit Haupt-, untere
/// Nebenversion).
const int fitProtocolVersion = 0x20;

/// Profilversion im Dateikopf: 21.40 (Haupt * 100 + Neben). Alle Felder des
/// Kodierers stehen so seit Profil 1.x im Profil.
const int fitProfileVersion = 2140;

/// Beginn der FIT-Zeitrechnung: 1989-12-31 00:00 UTC.
final DateTime fitEpoch = DateTime.utc(1989, 12, 31);

/// Kleinster FIT-Zeitwert, der als Datum gilt (kleinere sind relative Zeit).
const int _fitMinDateTime = 0x10000000;

// Basistypen (Typnummer, Invalid-Wert).
const _enum = (0x00, 0xFF);
const _uint8 = (0x02, 0xFF);
const _uint16 = (0x84, 0xFFFF);
const _sint32 = (0x85, 0x7FFFFFFF);
const _uint32 = (0x86, 0xFFFFFFFF);

typedef _BaseType = (int, int);
typedef _Field = (int number, _BaseType type);

int _size(_BaseType t) => switch (t.$1) {
  0x00 || 0x02 => 1,
  0x84 => 2,
  _ => 4,
};

// Globale Nachrichtennummern und Felder nach FIT-Profil 21.x.
const int _fileIdMsg = 0;
const int _sessionMsg = 18;
const int _lapMsg = 19;
const int _recordMsg = 20;
const int _eventMsg = 21;
const int _activityMsg = 34;

const List<_Field> _fileIdFields = [
  (0, _enum), // type
  (1, _uint16), // manufacturer
  (4, _uint32), // time_created
];
const List<_Field> _eventFields = [
  (253, _uint32), // timestamp
  (0, _enum), // event
  (1, _enum), // event_type
];
const List<_Field> _recordFields = [
  (253, _uint32), // timestamp
  (0, _sint32), // position_lat (semicircles)
  (1, _sint32), // position_long (semicircles)
  (2, _uint16), // altitude (scale 5, offset 500, m)
  (3, _uint8), // heart_rate (bpm)
];
const List<_Field> _lapFields = [
  (254, _uint16), // message_index
  (253, _uint32), // timestamp
  (0, _enum), // event
  (1, _enum), // event_type
  (2, _uint32), // start_time
  (7, _uint32), // total_elapsed_time (scale 1000, s)
  (8, _uint32), // total_timer_time (scale 1000, s)
  (9, _uint32), // total_distance (scale 100, m)
  (24, _enum), // lap_trigger
  (25, _enum), // sport
];
const List<_Field> _sessionFields = [
  (254, _uint16), // message_index
  (253, _uint32), // timestamp
  (0, _enum), // event
  (1, _enum), // event_type
  (2, _uint32), // start_time
  (5, _enum), // sport
  (6, _enum), // sub_sport
  (7, _uint32), // total_elapsed_time
  (8, _uint32), // total_timer_time
  (9, _uint32), // total_distance
  (25, _uint16), // first_lap_index
  (26, _uint16), // num_laps
  (28, _enum), // trigger
];
const List<_Field> _activityFields = [
  (253, _uint32), // timestamp
  (0, _uint32), // total_timer_time
  (1, _uint16), // num_sessions
  (2, _enum), // type
  (3, _enum), // event
  (4, _enum), // event_type
];

// Profilwerte.
const int _fileActivity = 4;
const int _manufacturerDevelopment = 255;
const int _eventTimer = 0;
const int _eventSession = 8;
const int _eventLap = 9;
const int _eventActivity = 26;
const int _eventTypeStart = 0;
const int _eventTypeStop = 1;
const int _eventTypeStopAll = 4;
const int _lapTriggerManual = 0;
const int _lapTriggerSessionEnd = 7;
const int _sportRunning = 1;
const int _subSportGeneric = 0;
const int _sessionTriggerActivityEnd = 0;
const int _activityManual = 0;

/// FIT-Aktivitätsdatei (Protokoll 2.0, Profil 21.x,
/// `docs/contracts/file-export.md`). Erwartet ein mit [exportSecond]
/// gebautes [ExportRun]; Zeiten mit Bruchteilen einer Sekunde lösen einen
/// [ArgumentError] aus.
///
/// Inhalt: `file_id`, je Abschnitt Timer-Ereignis `start` und `stop_all`,
/// je Exportpunkt ein `record` (fehlende Werte als Invalid-Wert des Typs),
/// je Runde ein `lap` am Rundenende, eine `session` und eine `activity`.
/// Kopf- und Datei-CRC nach [fitCrc16].
Uint8List encodeFit(ExportRun run) {
  final w = _FitWriter();
  final start = _time(run.startedAt);
  final end = _time(run.endedAt);
  w.message(_fileIdMsg, _fileIdFields, [
    _fileActivity,
    _manufacturerDevelopment,
    start,
  ]);

  final distances = run.lapDistancesMeters();
  var nextLap = 0;
  var lapOfLast = 0;
  void writeLapsBefore(int lapIndex) {
    while (nextLap < lapIndex && nextLap < run.laps.length - 1) {
      _writeLap(w, run, nextLap, distances[nextLap]);
      nextLap++;
    }
  }

  // Elemente in Zeitfolge; jedes gehört einer Runde, die nie abnimmt. Eine
  // Runde wird vor dem ersten Element der nächsten geschrieben.
  void item(int lapIndex, void Function() write) {
    if (lapIndex < lapOfLast) lapIndex = lapOfLast;
    lapOfLast = lapIndex;
    writeLapsBefore(lapIndex);
    write();
  }

  void event(DateTime t, int type) =>
      w.message(_eventMsg, _eventFields, [_time(t), _eventTimer, type]);

  final segments = _mergeSeconds(run);
  if (segments.isEmpty) {
    item(0, () => event(run.startedAt, _eventTypeStart));
    item(0, () => event(run.startedAt, _eventTypeStopAll));
  }
  for (final (segment, points) in segments) {
    item(
      run.lapIndexAt(segment.start),
      () => event(segment.start, _eventTypeStart),
    );
    for (final p in points) {
      item(
        run.lapIndexAt(p.time),
        () => w.message(_recordMsg, _recordFields, [
          _time(p.time),
          p.position == null ? null : _semicircles(p.position!.latitude),
          p.position == null ? null : _semicircles(p.position!.longitude),
          _altitude(p.altitudeMeters),
          _heartRate(p.heartRateBpm),
        ]),
      );
    }
    item(
      _lapBefore(run, segment.end),
      () => event(segment.end, _eventTypeStopAll),
    );
  }
  writeLapsBefore(run.laps.length);
  _writeLap(w, run, run.laps.length - 1, distances.last);

  final timer = run.activeTimeWithin(run.startedAt, run.endedAt);
  final distance = distances.fold<double>(0, (a, b) => a + b);
  w.message(_sessionMsg, _sessionFields, [
    0,
    end,
    _eventSession,
    _eventTypeStop,
    start,
    _sportRunning,
    _subSportGeneric,
    _millis(run.endedAt.difference(run.startedAt)),
    _millis(timer),
    _centimeters(distance),
    0,
    run.laps.length,
    _sessionTriggerActivityEnd,
  ]);
  w.message(_activityMsg, _activityFields, [
    end,
    _millis(timer),
    1,
    _activityManual,
    _eventActivity,
    _eventTypeStop,
  ]);
  return w.finish();
}

void _writeLap(_FitWriter w, ExportRun run, int index, double distance) {
  final lap = run.laps[index];
  w.message(_lapMsg, _lapFields, [
    index,
    _time(lap.end),
    _eventLap,
    _eventTypeStop,
    _time(lap.start),
    _millis(lap.end.difference(lap.start)),
    _millis(run.activeTimeWithin(lap.start, lap.end)),
    _centimeters(distance),
    index == run.laps.length - 1 ? _lapTriggerSessionEnd : _lapTriggerManual,
    _sportRunning,
  ]);
}

/// Index der letzten Runde, die vor [t] beginnt (für das Ende eines
/// Abschnitts, das noch zur laufenden Runde gehört).
int _lapBefore(ExportRun run, DateTime t) {
  var index = 0;
  for (var i = 0; i < run.laps.length; i++) {
    if (run.laps[i].start.isBefore(t)) index = i;
  }
  return index;
}

/// Je Sekunde höchstens ein Punkt, auch über Abschnittsgrenzen: Fallen nach
/// dem Abrunden zwei Abschnitte in dieselbe Sekunde, ergänzt der spätere
/// Punkt nur die noch fehlenden Kanäle des früheren (erster Wert je Kanal).
List<(ExportSegment, List<ExportPoint>)> _mergeSeconds(ExportRun run) {
  final bySecond = <int, ExportPoint>{};
  final order = <List<int>>[];
  for (final s in run.segments) {
    final keys = <int>[];
    for (final p in s.points) {
      final key = _time(p.time);
      final first = bySecond[key];
      if (first == null) {
        bySecond[key] = p;
        keys.add(key);
      } else {
        bySecond[key] = ExportPoint(
          time: first.time,
          position: first.position ?? p.position,
          altitudeMeters: first.altitudeMeters ?? p.altitudeMeters,
          heartRateBpm: first.heartRateBpm ?? p.heartRateBpm,
        );
      }
    }
    order.add(keys);
  }
  return [
    for (var i = 0; i < run.segments.length; i++)
      (run.segments[i], [for (final k in order[i]) bySecond[k]!]),
  ];
}

/// FIT-Zeit (`date_time`): ganze Sekunden seit [fitEpoch].
int _time(DateTime t) {
  final us = t.microsecondsSinceEpoch - fitEpoch.microsecondsSinceEpoch;
  if (us % Duration.microsecondsPerSecond != 0) {
    throw ArgumentError('FIT braucht ganze Sekunden (exportSecond)');
  }
  final s = us ~/ Duration.microsecondsPerSecond;
  if (s < _fitMinDateTime || s >= 0xFFFFFFFF) {
    throw ArgumentError('Zeit außerhalb des FIT-Bereichs');
  }
  return s;
}

/// Grad in Semicircles (2^31 / 180°), gerundet. 180° ist −180°; der eine
/// Wert unmittelbar darunter, der mit dem Invalid-Wert zusammenfiele, wird
/// um eine Einheit (< 1 cm) verschoben.
int _semicircles(double degrees) {
  var v = (degrees * 2147483648 / 180).round();
  if (v >= 2147483648) v -= 4294967296;
  if (v == 0x7FFFFFFF) v = 0x7FFFFFFE;
  return v;
}

/// Höhe: (m + 500) * 5, gerundet; außerhalb −500…12 606,8 m fehlt sie.
int? _altitude(double? meters) {
  if (meters == null) return null;
  final v = ((meters + 500) * 5).round();
  return v < 0 || v >= 0xFFFF ? null : v;
}

/// Puls 1…254; 255 ist der Invalid-Wert von `uint8` und fehlt.
int? _heartRate(int? bpm) => bpm == null || bpm < 1 || bpm > 254 ? null : bpm;

int _millis(Duration d) => (d.inMicroseconds / 1000).round();

int? _centimeters(double meters) {
  final v = (meters * 100).round();
  return v < 0 || v >= 0xFFFFFFFF ? null : v;
}

/// Schreibt Nachrichten mit normalem Kopf, little-endian. Je globaler
/// Nachricht ein lokaler Typ, definiert vor der ersten Datennachricht.
class _FitWriter {
  final BytesBuilder _data = BytesBuilder();
  final Map<int, int> _local = {};

  void message(int global, List<_Field> fields, List<int?> values) {
    assert(fields.length == values.length);
    var local = _local[global];
    if (local == null) {
      local = _local.length;
      if (local > 15) throw StateError('zu viele lokale Nachrichtentypen');
      _local[global] = local;
      _data
        ..addByte(0x40 | local)
        ..addByte(0) // reserviert
        ..addByte(0) // little-endian
        ..addByte(global & 0xFF)
        ..addByte(global >> 8)
        ..addByte(fields.length);
      for (final (number, type) in fields) {
        _data
          ..addByte(number)
          ..addByte(_size(type))
          ..addByte(type.$1);
      }
    }
    _data.addByte(local);
    for (var i = 0; i < fields.length; i++) {
      final type = fields[i].$2;
      final v = values[i] ?? type.$2;
      final size = _size(type);
      for (var b = 0; b < size; b++) {
        _data.addByte((v >> (8 * b)) & 0xFF);
      }
    }
  }

  Uint8List finish() {
    final data = _data.takeBytes();
    final header = ByteData(14)
      ..setUint8(0, 14)
      ..setUint8(1, fitProtocolVersion)
      ..setUint16(2, fitProfileVersion, Endian.little)
      ..setUint32(4, data.length, Endian.little)
      ..setUint8(8, 0x2E) // .
      ..setUint8(9, 0x46) // F
      ..setUint8(10, 0x49) // I
      ..setUint8(11, 0x54); // T
    final head = header.buffer.asUint8List();
    header.setUint16(12, fitCrc16(head.take(12)), Endian.little);
    final out = BytesBuilder(copy: false)
      ..add(head)
      ..add(data);
    final crc = fitCrc16(data, fitCrc16(head));
    out
      ..addByte(crc & 0xFF)
      ..addByte(crc >> 8);
    return out.takeBytes();
  }
}
