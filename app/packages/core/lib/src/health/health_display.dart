import '../../ports/health_import.dart';
import '../subjective/manual_training.dart';

/// Aufbereitung importierter Health-Connect-Daten nur zur Anzeige (WP32 Teil E,
/// FR-0024, K62 F2). Nichts hiervon fließt in eine Berechnung der App ein.

/// Ein Wert der Vergleichsreihe: Zeitpunkt und Zahl der Quell-App.
class Vo2maxPoint {
  const Vo2maxPoint(this.time, this.value);
  final DateTime time;
  final double value;
}

/// VO₂max-Werte genau einer Quell-App, ältester zuerst (FR-0024). Die Werte
/// bleiben Schätzungen der Quelle: sie werden nie mit der eigenen Reihe oder mit
/// anderen Quellen verrechnet.
class Vo2maxSourceSeries {
  const Vo2maxSourceSeries({
    required this.origin,
    required this.points,
    required this.unit,
  });

  /// Paket der Quell-App (`metadata.dataOrigin`), SEC-0005.
  final String origin;
  final List<Vo2maxPoint> points;
  final String unit;

  Vo2maxPoint get latest => points.last;
}

/// Gruppiert importierte VO₂max-Werte je Quell-App für die Vergleichskarte. Nur
/// [HealthDataKind.vo2Max] mit Zahl; je Quelle eine Reihe; die Quelle mit dem
/// jüngsten Wert steht zuerst. Es gibt bewusst keinen gemeinsamen Wert.
List<Vo2maxSourceSeries> vo2maxComparison(Iterable<HealthRecord> records) {
  final byOrigin = <String, List<HealthRecord>>{};
  for (final r in records) {
    if (r.kind != HealthDataKind.vo2Max || r.value == null) continue;
    (byOrigin[r.origin] ??= []).add(r);
  }
  final out = <Vo2maxSourceSeries>[];
  byOrigin.forEach((origin, list) {
    list.sort((a, b) => a.start.compareTo(b.start));
    out.add(
      Vo2maxSourceSeries(
        origin: origin,
        points: [for (final r in list) Vo2maxPoint(r.start, r.value!)],
        unit: list.last.unit ?? '',
      ),
    );
  });
  out.sort((a, b) => b.latest.time.compareTo(a.latest.time));
  return out;
}

/// Health Connect `EXERCISE_TYPE_RUNNING` und `EXERCISE_TYPE_RUNNING_TREADMILL`.
const _runningTypes = {56, 57};

bool isRunningExercise(int? exerciseType) =>
    exerciseType != null && _runningTypes.contains(exerciseType);

/// Art des Nachtrags für eine übernommene Einheit: Laufen als Lauf, alles
/// andere als „Sonstiges“.
ManualTrainingKind manualKindOfExercise(int? exerciseType) =>
    isRunningExercise(exerciseType)
    ? ManualTrainingKind.run
    : ManualTrainingKind.other;

/// Dauer der Einheit (Ende minus Beginn), auf ganze Minuten gerundet, mindestens
/// eine Minute (Vorbelegung des Nachtrags; der Nutzer kann sie ändern).
int exerciseMinutes(HealthRecord exercise) {
  final m = (exercise.end.difference(exercise.start).inSeconds / 60).round();
  return m < 1 ? 1 : m;
}

/// Kalendertag des Beginns in der Ortszeit der Aufzeichnung (Zonenversatz des
/// Datensatzes, sonst [fallbackOffset]) als UTC-Mitternacht.
DateTime exerciseLocalDay(HealthRecord exercise, Duration fallbackOffset) {
  final offset = exercise.offsetSeconds == null
      ? fallbackOffset
      : Duration(seconds: exercise.offsetSeconds!);
  final t = exercise.start.toUtc().add(offset);
  return DateTime.utc(t.year, t.month, t.day);
}

/// Health-Connect-IDs der schon übernommenen Einheiten.
Set<String> adoptedHcIds(Iterable<StoredManualTraining> trainings) => {
  for (final t in trainings)
    if (t.training.hcId != null) t.training.hcId!,
};
