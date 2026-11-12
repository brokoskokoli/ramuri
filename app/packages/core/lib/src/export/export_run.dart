import '../../ports/storage.dart';
import '../../ports/storage_raw.dart';
import '../../ports/storage_runs.dart';
import '../preprocessing/geo.dart';
import '../recording/belt_track.dart';
import '../preprocessing/measurement.dart';
import '../../ports/file_handoff.dart';

/// Gemessene Position eines Exportpunkts (WGS84, Grad).
class ExportPosition {
  const ExportPosition(this.latitude, this.longitude);

  final double latitude;
  final double longitude;
}

/// Ein Zeitpunkt des Exports (FR-0183). Jeder Kanal ist entweder ein
/// gemessener Rohwert mit genau diesem (gerundeten) Zeitstempel oder `null`;
/// nichts wird interpoliert oder als 0 eingesetzt.
class ExportPoint {
  const ExportPoint({
    required this.time,
    this.position,
    this.altitudeMeters,
    this.heartRateBpm,
    this.distanceMeters,
    this.speedMetersPerSecond,
  });

  final DateTime time;
  final ExportPosition? position;
  final double? altitudeMeters;
  final int? heartRateBpm;

  /// Nur Bandläufe (FR-0196): kumulierte Strecke seit Laufbeginn aus den
  /// eingestellten Bandwerten, nicht gemessen.
  final double? distanceMeters;

  /// Nur Bandläufe: eingestellte Geschwindigkeit in m/s.
  final double? speedMetersPerSecond;
}

/// Zusammenhängender Abschnitt zwischen zwei Pausen bzw. Unterbrechungen
/// (Abbildungsregel 5). [end] ist exklusiv, außer im letzten Abschnitt.
class ExportSegment {
  const ExportSegment({
    required this.start,
    required this.end,
    required this.points,
  });

  final DateTime start;
  final DateTime end;

  /// Nach Zeit sortiert, je Zeitstempel höchstens ein Punkt.
  final List<ExportPoint> points;
}

/// Runde (Abbildungsregel 6): von [start] bis [end]; ein Punkt gehört zur
/// letzten Runde, deren Start nicht nach ihm liegt.
class ExportLap {
  const ExportLap({
    required this.number,
    required this.start,
    required this.end,
  });

  final int number;
  final DateTime start;
  final DateTime end;
}

/// Formatneutrales Exportmodell eines beendeten Laufs. Enthält nur gemessene
/// Rohwerte, keine Profil- oder berechneten Werte (Vertrag
/// `docs/contracts/file-export.md`).
class ExportRun {
  const ExportRun({
    required this.name,
    required this.startedAt,
    required this.endedAt,
    required this.segments,
    required this.laps,
    this.isTreadmill = false,
  });

  /// Bandlauf (FR-0196): keine Positionen, Strecke und Geschwindigkeit je
  /// Punkt aus den Bandeinstellungen; GPX gibt es dafür nicht.
  final bool isTreadmill;

  /// Anzeigename, ohne Erweiterung (`run-YYYYMMDD-HHMMSS`).
  final String name;
  final DateTime startedAt;
  final DateTime endedAt;
  final List<ExportSegment> segments;

  /// Mindestens eine Runde, nach Zeit sortiert.
  final List<ExportLap> laps;

  /// Dateiname: [name] auf `A-Z a-z 0-9 . _ -` beschränkt, plus [extension]
  /// (siehe [exportFileName]).
  String fileName(String extension) => exportFileName(name, extension);

  /// Zeit der Abschnitte innerhalb von [from] bis [to] (Pausen zählen nicht).
  Duration activeTimeWithin(DateTime from, DateTime to) {
    var us = 0;
    for (final s in segments) {
      final a = _maxUs(s.start, from);
      final b = _minUs(s.end, to);
      if (b > a) us += b - a;
    }
    return Duration(microseconds: us);
  }

  /// Index der letzten Runde, deren Start nicht nach [t] liegt (sonst 0).
  int lapIndexAt(DateTime t) {
    var index = 0;
    for (var i = 0; i < laps.length; i++) {
      if (!laps[i].start.isAfter(t)) index = i;
    }
    return index;
  }

  /// Strecke je Runde in Metern: Großkreisabstand aufeinanderfolgender
  /// Positionen desselben Abschnitts, der Runde des späteren Punkts
  /// zugerechnet (Vertrag, Pflichtfelder der Runde).
  ///
  /// Bandlauf: Zuwachs der kumulierten Strecke der Punkte je Runde.
  List<double> lapDistancesMeters() {
    final out = List<double>.filled(laps.length, 0);
    if (isTreadmill) {
      var previous = 0.0;
      for (final s in segments) {
        for (final p in s.points) {
          final d = p.distanceMeters;
          if (d == null) continue;
          out[lapIndexAt(p.time)] += d - previous;
          previous = d;
        }
      }
      return out;
    }
    for (final s in segments) {
      ExportPosition? previous;
      for (final p in s.points) {
        final pos = p.position;
        if (pos == null) continue;
        if (previous != null) {
          out[lapIndexAt(p.time)] += haversineMeters(
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
}

int _maxUs(DateTime a, DateTime b) =>
    a.microsecondsSinceEpoch > b.microsecondsSinceEpoch
    ? a.microsecondsSinceEpoch
    : b.microsecondsSinceEpoch;

int _minUs(DateTime a, DateTime b) =>
    a.microsecondsSinceEpoch < b.microsecondsSinceEpoch
    ? a.microsecondsSinceEpoch
    : b.microsecondsSinceEpoch;

/// Zeitauflösung für GPX und TCX (ISO 8601 mit Millisekunden).
const Duration exportMillisecond = Duration(milliseconds: 1);

/// Zeitauflösung für FIT (ganze Sekunden).
const Duration exportSecond = Duration(seconds: 1);

/// Bildet einen beendeten Lauf auf das Exportmodell ab (Abbildungsregeln 1–8,
/// `docs/contracts/file-export.md`). Zeitstempel werden auf [resolution]
/// abgerundet; je Kanal und Zeitschritt gilt der erste Wert.
///
/// Wirft [ArgumentError], wenn der Lauf nicht beendet ist.
ExportRun buildExportRun({
  required StoredRun run,
  required StoredRawData raw,
  required List<StoredGap> gaps,
  required List<StoredLap> laps,
  Duration resolution = exportMillisecond,
}) {
  final endedAt = run.endedAt;
  if (run.state != RunState.finished || endedAt == null) {
    throw ArgumentError('Nur beendete Läufe sind exportierbar');
  }
  final res = resolution.inMicroseconds;
  if (res <= 0) throw ArgumentError.value(resolution, 'resolution');
  int floor(int us) => us - us % res;
  DateTime at(int us) => DateTime.fromMicrosecondsSinceEpoch(us, isUtc: true);

  final startUs = run.startedAt.microsecondsSinceEpoch;
  final endUs = endedAt.microsecondsSinceEpoch < startUs
      ? startUs
      : endedAt.microsecondsSinceEpoch;

  // Pausen [Beginn, Ende), auf den Lauf begrenzt und zusammengefasst.
  final pauses = <(int, int)>[];
  final sorted = [
    for (final g in gaps)
      if (g.kind == RunGapKind.manualPause || g.kind == RunGapKind.interruption)
        (
          g.start.microsecondsSinceEpoch.clamp(startUs, endUs),
          (g.end?.microsecondsSinceEpoch ?? endUs).clamp(startUs, endUs),
        ),
  ]..sort((a, b) => a.$1.compareTo(b.$1));
  for (final p in sorted) {
    if (p.$2 < p.$1) continue;
    if (pauses.isNotEmpty && p.$1 <= pauses.last.$2) {
      if (p.$2 > pauses.last.$2) pauses.last = (pauses.last.$1, p.$2);
    } else {
      pauses.add(p);
    }
  }

  // Aktive Abschnitte [a, b), der letzte schließt das Laufende ein.
  final bounds = <(int, int)>[];
  var cursor = startUs;
  for (final p in pauses) {
    if (p.$1 > cursor) bounds.add((cursor, p.$1));
    if (p.$2 > cursor) cursor = p.$2;
  }
  if (endUs > cursor || bounds.isEmpty && pauses.isEmpty) {
    bounds.add((cursor, endUs));
  }

  int? segmentOf(int us) {
    for (var i = 0; i < bounds.length; i++) {
      final (a, b) = bounds[i];
      final last = i == bounds.length - 1 && b == endUs;
      if (us >= a && (us < b || last && us == b)) return i;
    }
    return null;
  }

  final builders = [for (final _ in bounds) <int, _PointBuilder>{}];
  void put<T extends RawSample>(
    List<StoredRaw<T>> rows,
    bool Function(T) usable,
    bool Function(_PointBuilder) has,
    void Function(_PointBuilder, T) set,
  ) {
    for (final row in rows) {
      final v = row.value;
      if (v.state != MeasurementState.present || !usable(v)) continue;
      final us = v.time.microsecondsSinceEpoch;
      final seg = segmentOf(us);
      if (seg == null) continue;
      final b = builders[seg].putIfAbsent(floor(us), _PointBuilder.new);
      if (!has(b)) set(b, v);
    }
  }

  put<RawPosition>(
    raw.positions,
    (p) =>
        p.latitude.isFinite &&
        p.longitude.isFinite &&
        p.latitude >= -90 &&
        p.latitude <= 90 &&
        p.longitude >= -180 &&
        p.longitude < 180,
    (b) => b.position != null,
    (b, p) => b.position = ExportPosition(p.latitude, p.longitude),
  );
  put<RawAltitude>(
    raw.altitudes,
    (a) => a.meters.isFinite,
    (b) => b.altitude != null,
    (b, a) => b.altitude = a.meters,
  );
  put<RawHeartRate>(
    raw.heartRates,
    (h) => h.bpm >= 1 && h.bpm <= 255,
    (b) => b.heartRate != null,
    (b, h) => b.heartRate = h.bpm,
  );

  // Bandlauf: je volle Sekunde ab Abschnittsbeginn und am Abschnittsende ein
  // Punkt; jeder Punkt (auch ein Pulspunkt) trägt Strecke und Geschwindigkeit
  // aus den Bandeinstellungen.
  final belt = beltTrackOfRun(run, at(endUs), raw, gaps);
  if (belt != null) {
    for (var i = 0; i < bounds.length; i++) {
      final (a, b) = bounds[i];
      for (var us = a; us < b; us += Duration.microsecondsPerSecond) {
        builders[i].putIfAbsent(floor(us), _PointBuilder.new);
      }
      builders[i].putIfAbsent(floor(b), _PointBuilder.new);
      builders[i].forEach((key, point) => point.setBelt(belt, at(key)));
    }
  }

  final segments = [
    for (var i = 0; i < bounds.length; i++)
      ExportSegment(
        start: at(floor(bounds[i].$1)),
        end: at(floor(bounds[i].$2)),
        points: [
          for (final us in builders[i].keys.toList()..sort())
            builders[i][us]!.build(at(us)),
        ],
      ),
  ];

  final marks = [...laps]..sort((a, b) => a.index.compareTo(b.index));
  final exportLaps = <ExportLap>[];
  var lapStart = startUs;
  for (final m in marks) {
    final markUs = m.markedAt.microsecondsSinceEpoch.clamp(lapStart, endUs);
    exportLaps.add(
      ExportLap(
        number: m.index,
        start: at(floor(lapStart)),
        end: at(floor(markUs)),
      ),
    );
    lapStart = markUs;
  }
  if (exportLaps.isEmpty || endUs > lapStart) {
    exportLaps.add(
      ExportLap(
        number: marks.isEmpty ? 1 : marks.last.index + 1,
        start: at(floor(lapStart)),
        end: at(floor(endUs)),
      ),
    );
  }

  return ExportRun(
    name: exportRunName(run),
    startedAt: at(floor(startUs)),
    endedAt: at(floor(endUs)),
    segments: segments,
    laps: exportLaps,
    isTreadmill: belt != null,
  );
}

/// `run-YYYYMMDD-HHMMSS` aus der Startzeit, in Ortszeit über
/// [StoredRun.endedUtcOffset], sonst UTC (Abbildungsregel 8).
String exportRunName(StoredRun run) {
  final t = run.startedAt.toUtc().add(run.endedUtcOffset ?? Duration.zero);
  String two(int v) => v.toString().padLeft(2, '0');
  return 'run-${t.year.toString().padLeft(4, '0')}${two(t.month)}${two(t.day)}'
      '-${two(t.hour)}${two(t.minute)}${two(t.second)}';
}

class _PointBuilder {
  ExportPosition? position;
  double? altitude;
  int? heartRate;
  double? distance;
  double? speed;

  void setBelt(BeltTrack belt, DateTime t) {
    distance = belt.metersAt(t);
    // Am Abschnittsende gilt noch die Einstellung des letzten Stücks.
    speed = (belt.pieceAt(t) ?? belt.pieceAt(t.subtract(exportMillisecond)))
        ?.speedMetersPerSecond;
  }

  ExportPoint build(DateTime time) => ExportPoint(
    time: time,
    position: position,
    altitudeMeters: altitude,
    heartRateBpm: heartRate,
    distanceMeters: distance,
    speedMetersPerSecond: speed,
  );
}

/// Liest einen Lauf für den Export, wie `RunSummaryService.load`.
class RunExportService {
  RunExportService({required this.session});

  final StorageSession session;

  /// `null` für einen unbekannten oder nicht beendeten Lauf. Wirft
  /// [StorageException] bei Lesefehlern.
  Future<ExportRun?> load(
    int runId, {
    Duration resolution = exportMillisecond,
  }) async {
    final run = await session.runs.get(runId);
    if (run == null || run.state != RunState.finished || run.endedAt == null) {
      return null;
    }
    return buildExportRun(
      run: run,
      raw: await session.rawData.read(runId),
      gaps: await session.markers.gaps(runId),
      laps: await session.markers.laps(runId),
      resolution: resolution,
    );
  }
}
