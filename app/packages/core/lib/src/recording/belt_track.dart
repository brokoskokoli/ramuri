/// Auswertung eines Bandlaufs aus den Bandeinstellungen (FR-0196, K57): die
/// EINE reine Funktion für Sitzung (während des Laufs) und Analyse (danach).
/// Strecke, Bewegungszeit und Pace sind das Integral der eingestellten
/// Geschwindigkeit über die aktive Zeit, also ohne manuelle Pausen und ohne
/// Unterbrechung nach einem Absturz. Die Werte sind eingestellt, nicht gemessen.
library;

import '../../ports/storage_raw.dart';
import '../../ports/storage_runs.dart';
import '../preprocessing/movement_time_processor.dart' show TimeSpan;
import 'treadmill.dart';

/// Ein Stück aktiver Bandzeit mit gleichbleibender Einstellung.
class BeltPiece {
  const BeltPiece({
    required this.span,
    required this.speedMetersPerSecond,
    required this.inclinePercent,
  });

  final TimeSpan span;
  final double speedMetersPerSecond;
  final double? inclinePercent;

  /// Geschwindigkeit größer 0 (K57: 0 ist Stillstand ohne Bewegungszeit).
  bool get isMoving => speedMetersPerSecond > 0;

  double get meters => isMoving
      ? speedMetersPerSecond *
            span.duration.inMicroseconds /
            Duration.microsecondsPerSecond
      : 0;
}

class BeltTrack {
  BeltTrack(List<BeltPiece> pieces) : pieces = List.unmodifiable(pieces);

  /// Aktive Bandzeit in Zeitreihenfolge; Stücke mit gleicher Einstellung, die
  /// sich berühren (Lebenszeichen-Zeilen, unveränderte Wiederholungen), sind
  /// zu einem zusammengefasst.
  final List<BeltPiece> pieces;

  /// Strecke in Metern.
  double get meters => pieces.fold(0.0, (a, p) => a + p.meters);

  /// Bewegungszeit: aktive Zeit mit Geschwindigkeit größer 0.
  Duration get moving => Duration(
    microseconds: pieces
        .where((p) => p.isMoving)
        .fold(0, (a, p) => a + p.span.duration.inMicroseconds),
  );

  /// Bewegte Stücke gleicher Geschwindigkeit und Steigung (Phasen für die
  /// Abschnittsauswahl); eine Änderung trennt sie, auch ohne Lücke.
  List<BeltPiece> get constantPhases => [
    for (final p in pieces)
      if (p.isMoving) p,
  ];

  /// Durchschnittspace in s/km über die Bewegungszeit; `null` ohne Strecke.
  double? get averagePaceSecondsPerKm {
    final m = meters;
    if (!(m > 0)) return null;
    return moving.inMicroseconds / Duration.microsecondsPerSecond / (m / 1000);
  }

  /// Stück, das [t] enthält (Anfang eingeschlossen), sonst `null`.
  BeltPiece? pieceAt(DateTime t) {
    for (final p in pieces) {
      if (!t.isBefore(p.span.start) && t.isBefore(p.span.end)) return p;
    }
    return null;
  }
}

/// Rechnet die Bandstrecke von [start] bis [to]. [settings] gelten ab ihrem
/// Offset bis zur nächsten Einstellung (aufsteigend sortiert angenommen),
/// [pauses] sind Zeiten ohne aktive Bandzeit (offene Pausen enden bei [to]).
BeltTrack computeBeltTrack({
  required DateTime start,
  required DateTime to,
  required List<BeltSetting> settings,
  required List<(DateTime, DateTime)> pauses,
}) {
  final pieces = <BeltPiece>[];
  for (var i = 0; i < settings.length; i++) {
    final b = settings[i];
    final a = start.add(b.offset);
    var e = i + 1 < settings.length ? start.add(settings[i + 1].offset) : to;
    if (e.isAfter(to)) e = to;
    if (!e.isAfter(a)) continue;
    // Aktive Teile: [a, e] ohne die Pausen.
    var cursor = a;
    final cuts = [
      for (final (ps, pe) in pauses)
        if (pe.isAfter(a) && ps.isBefore(e)) (ps, pe),
    ]..sort((x, y) => x.$1.compareTo(y.$1));
    void emit(DateTime from, DateTime until) {
      if (!until.isAfter(from)) return;
      final last = pieces.isEmpty ? null : pieces.last;
      if (last != null &&
          last.span.end == from &&
          last.speedMetersPerSecond == b.speedMetersPerSecond &&
          last.inclinePercent == b.inclinePercent) {
        pieces[pieces.length - 1] = BeltPiece(
          span: TimeSpan(start: last.span.start, end: until),
          speedMetersPerSecond: b.speedMetersPerSecond,
          inclinePercent: b.inclinePercent,
        );
      } else {
        pieces.add(
          BeltPiece(
            span: TimeSpan(start: from, end: until),
            speedMetersPerSecond: b.speedMetersPerSecond,
            inclinePercent: b.inclinePercent,
          ),
        );
      }
    }

    for (final (ps, pe) in cuts) {
      if (ps.isAfter(cursor)) emit(cursor, ps.isBefore(e) ? ps : e);
      if (pe.isAfter(cursor)) cursor = pe;
    }
    emit(cursor, e);
  }
  return BeltTrack(pieces);
}

/// Die Bandauswertung eines beendeten Laufs aus den gespeicherten Rohdaten
/// und Lücken; `null` bei einem GPS-Lauf. Pausen und Unterbrechungen zählen
/// nicht zur aktiven Zeit, so wie in der Sitzung.
BeltTrack? beltTrackOfRun(
  StoredRun run,
  DateTime end,
  StoredRawData raw,
  List<StoredGap> gaps,
) {
  if (run.mode != RunMode.treadmill) return null;
  final settings = [for (final s in raw.beltSettings) s.value]
    ..sort((a, b) => a.offset.compareTo(b.offset));
  return computeBeltTrack(
    start: run.startedAt,
    to: end,
    settings: settings,
    pauses: [
      for (final g in gaps)
        if (g.kind == RunGapKind.manualPause ||
            g.kind == RunGapKind.interruption)
          (g.start, g.end ?? end),
    ],
  );
}
