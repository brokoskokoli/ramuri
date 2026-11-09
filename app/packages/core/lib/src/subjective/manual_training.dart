import 'srpe.dart';
import 'subjective_limits.dart';

/// Art eines nachgetragenen Trainings (FR-0199). `other` ist „Sonstiges“ und
/// zählt nur für Belastung und Pausenende (OQ-0058).
enum ManualTrainingKind { run, other }

/// Ein nachgetragenes Training (FR-0199): Datum (Kalendertag), Art, Dauer, RPE.
/// Es liegt in eigener Tabelle und erzeugt keine GPS-, VO₂max- oder Lauf-Werte.
class ManualTraining {
  /// [day] zählt nur mit Jahr, Monat und Tag (Kalendertag, ohne Zeitzone).
  /// [duration] muss ganze Sekunden und größer als 0 sein, [rpe] 0 bis 10; sonst
  /// [SubjectiveRangeError]. Dass der Tag nicht in der Zukunft liegt, prüft
  /// [requireNotAfter] (braucht die Uhr).
  ManualTraining({
    required DateTime day,
    required this.kind,
    required this.duration,
    required int rpe,
  }) : day = DateTime.utc(day.year, day.month, day.day),
       rpe = checkRpe(rpe)! {
    if (duration.inMicroseconds <= 0 ||
        duration.inMicroseconds % Duration.microsecondsPerSecond != 0) {
      throw SubjectiveRangeError('duration');
    }
  }

  /// Kalendertag als UTC-Mitternacht.
  final DateTime day;
  final ManualTrainingKind kind;
  final Duration duration;
  final int rpe;

  /// `JJJJ-MM-TT`.
  String get isoDay {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${day.year.toString().padLeft(4, '0')}-${two(day.month)}-${two(day.day)}';
  }

  /// Wirft [SubjectiveRangeError], wenn der Tag nach dem Kalendertag von
  /// [today] liegt.
  void requireNotAfter(DateTime today) {
    final t = DateTime.utc(today.year, today.month, today.day);
    if (day.isAfter(t)) throw SubjectiveRangeError('day');
  }

  /// sRPE aus Dauer und RPE; kein Umrechnungsfaktor (PAR-086 fehlt).
  SrpeLoad get srpe => SrpeLoad.compute(duration: duration, rpe: rpe);

  @override
  bool operator ==(Object other) =>
      other is ManualTraining &&
      other.day == day &&
      other.kind == kind &&
      other.duration == duration &&
      other.rpe == rpe;

  @override
  int get hashCode => Object.hash(day, kind, duration, rpe);

  @override
  String toString() => 'ManualTraining(…)';
}

/// Gespeichertes nachgetragenes Training.
class StoredManualTraining {
  const StoredManualTraining({required this.id, required this.training});
  final int id;
  final ManualTraining training;
}
