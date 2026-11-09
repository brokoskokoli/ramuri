import 'subjective_limits.dart';

/// Subjektive Trainingsbelastung (FR-0095): `Dauer[min] · RPE`. Eigene Skala,
/// getrennt vom TRIMP; es gibt bewusst keine Summe beider (FR-0096).
///
/// Methode und Version stehen an jedem gespeicherten Wert (NFR-0001, NFR-0005).
/// Bei einem Lauf zählt die Bewegungszeit (OQ-0015), bei einem nachgetragenen
/// Training die eingegebene Dauer.
class SrpeLoad {
  const SrpeLoad._({
    required this.points,
    required this.duration,
    required this.rpe,
    required this.method,
    required this.version,
  });

  /// Gespeichert an `srpe_method` / `srpe_method_version`.
  static const String methodId = 'srpe_duration_rpe';
  static const int methodVersion = 1;

  /// Einheit des Werts (wie TRIMP-Punkte, aber eine andere Skala).
  static const String unit = 'srpe_points';

  /// Rechnet die Last. [duration] darf nicht negativ sein, [rpe] liegt in
  /// 0 bis 10 (sonst [SubjectiveRangeError]); keine Rundung. 45 min bei RPE 5
  /// ergibt 225.
  factory SrpeLoad.compute({required Duration duration, required int rpe}) {
    checkRpe(rpe);
    if (duration.isNegative) throw SubjectiveRangeError('duration');
    return SrpeLoad._(
      points: duration.inMicroseconds * rpe / Duration.microsecondsPerMinute,
      duration: duration,
      rpe: rpe,
      method: methodId,
      version: methodVersion,
    );
  }

  /// Wert aus dem Speicher, mit der Methode und Version, mit der er gerechnet
  /// wurde. Punkte nicht negativ, RPE in Grenzen.
  factory SrpeLoad.restore({
    required double points,
    required Duration duration,
    required int rpe,
    required String method,
    required int version,
  }) {
    checkRpe(rpe);
    if (!(points >= 0) || !points.isFinite || duration.isNegative) {
      throw SubjectiveRangeError('srpe');
    }
    return SrpeLoad._(
      points: points,
      duration: duration,
      rpe: rpe,
      method: method,
      version: version,
    );
  }

  final double points;

  /// Zugrunde liegende Dauer (Bewegungszeit bzw. eingegebene Dauer).
  final Duration duration;
  final int rpe;

  final String method;
  final int version;

  @override
  bool operator ==(Object other) =>
      other is SrpeLoad &&
      other.points == points &&
      other.duration == duration &&
      other.rpe == rpe &&
      other.method == method &&
      other.version == version;

  @override
  int get hashCode => Object.hash(points, duration, rpe, method, version);
}
