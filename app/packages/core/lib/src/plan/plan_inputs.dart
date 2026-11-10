import '../goals/training_goal.dart';
import 'plan_parameters.dart';
import 'plan_registry.dart' show planRuleVersion;
import 'walk_run_program.dart' show walkRunMethod;
import 'target_intensity.dart' show IntensityInputs;
import 'walk_run_schedule.dart';
import 'walk_run_units.dart' show WalkRunPosition;
import 'weekly_time.dart' show planDay;

/// Methode und Version einer Plan-Fassung (ADR-0010 Punkt 1, NFR-0001).
class PlanVersion {
  const PlanVersion({
    this.method = planMethod,
    this.methodVersion = planMethodVersion,
    this.parameterVersion = planRuleVersion,
  });

  /// Die Fassung dieses Codes.
  static const PlanVersion current = PlanVersion();

  final String method;
  final int methodVersion;

  /// Gesamtversion der Regeln ([planRuleVersion]); trägt die Versionen von
  /// Parametersatz, Geh-Lauf-Abfolge und Zielintensität.
  final int parameterVersion;

  /// Stand des Parametersatzes (Wochenzeit, Einheiten) in [parameterVersion].
  int get parametersPart => parameterVersion ~/ 1000000;

  /// Version der Geh-Lauf-Abfolge in [parameterVersion].
  int get walkRunPart => (parameterVersion ~/ 1000) % 1000;

  /// Version der Zielintensität in [parameterVersion].
  int get targetIntensityPart => parameterVersion % 1000;

  /// Methode und Version, mit der eine Einheit der Art [walkRun] dieser Fassung
  /// entstanden ist: die Einheit der Abfolge trägt die Geh-Lauf-Methode, jede
  /// andere die der Fassung (ADR-0010 Punkt 2). Beim Lesen gebraucht.
  (String, int) unitMethod({required bool walkRun}) =>
      walkRun ? (walkRunMethod, walkRunPart) : (method, methodVersion);

  /// Gilt diese Fassung unter den Regeln dieses Codes? `false` löst
  /// `ruleVersion` aus (ADR-0010 Punkt 7), sobald sich eine Teilmethode
  /// geändert hat.
  bool get isCurrent => this == current;

  Map<String, Object?> toJson() => {
    'method': method,
    'methodVersion': methodVersion,
    'parameterVersion': parameterVersion,
  };

  @override
  bool operator ==(Object other) =>
      other is PlanVersion &&
      other.method == method &&
      other.methodVersion == methodVersion &&
      other.parameterVersion == parameterVersion;

  @override
  int get hashCode => Object.hash(method, methodVersion, parameterVersion);
}

String _dayText(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

DateTime _parseDay(Object? v, String key) {
  if (v is String && RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(v)) {
    final p = v.split('-').map(int.parse).toList();
    final d = DateTime.utc(p[0], p[1], p[2]);
    if (_dayText(d) == v) return d;
  }
  throw FormatException('PlanInputs: ungültiger Tag in "$key"');
}

/// Alles, was die Planrechnung außer dem Ziel braucht (ADR-0010 Punkt 2).
/// Wird an der Fassung gespeichert; die Schlüsselreihenfolge von [toJson] ist
/// fest (Archiv, Vergleich).
class PlanInputs {
  PlanInputs({
    required DateTime anchor,
    required this.startWeeklyMinutes,
    required DateTime today,
    this.walkRunWeeks = 0,
    this.easyPaceSecondsPerKm,
    this.easyRunCount = 0,
    this.lastWeekMinutes,
    this.achievedShare,
    this.walkRunStart,
    DateTime? walkRunFrom,
    this.intensity,
  }) : walkRunFrom = walkRunFrom == null ? null : planDay(walkRunFrom),
       anchor = planDay(anchor),
       today = planDay(today) {
    if (startWeeklyMinutes < 1) {
      throw ArgumentError.value(startWeeklyMinutes, 'startWeeklyMinutes');
    }
    if (walkRunWeeks < 0) {
      throw ArgumentError.value(walkRunWeeks, 'walkRunWeeks');
    }
    if (easyRunCount < 0) {
      throw ArgumentError.value(easyRunCount, 'easyRunCount');
    }
    final pace = easyPaceSecondsPerKm;
    if (pace != null && (!pace.isFinite || pace <= 0)) {
      throw ArgumentError.value(pace, 'easyPaceSecondsPerKm');
    }
    final share = achievedShare;
    if (share != null && (!share.isFinite || share < 0 || share > 1)) {
      throw ArgumentError.value(share, 'achievedShare');
    }
    final last = lastWeekMinutes;
    if (last != null && last < 0) {
      throw ArgumentError.value(last, 'lastWeekMinutes');
    }
  }

  /// Neues Ziel (PAR-192): Anker ist der Montag der Woche von [today]. Mit
  /// genanntem Stand beginnt der Plan mit dieser Wochenzeit, sonst mit 30 min
  /// je Lauftag. Bei „30 min am Stück“ = nein ([canRunContinuous30]) steht
  /// davor die Geh-Lauf-Abfolge (PAR-065) von Position 0: [walkRunStart] und
  /// ihre Länge in Kalenderwochen; danach beginnt der Plan mit 30 min je
  /// Lauftag (PAR-192), auch bei genanntem Stand.
  factory PlanInputs.forNewGoal(
    TrainingGoal goal,
    DateTime today, {
    PlanParameters parameters = const PlanParameters(),
  }) {
    final t = planDay(today);
    final stated = goal.currentWeeklySeconds;
    final program = !canRunContinuous30(
      goal,
      weekIndex: 0,
      parameters: parameters,
    );
    final minutes = stated != null && !program
        ? (stated / 60).round()
        : parameters.continuousRunMinutes * goal.runDays.length;
    const start = WalkRunPosition(0);
    return PlanInputs(
      anchor: t.subtract(Duration(days: t.weekday - DateTime.monday)),
      startWeeklyMinutes: minutes < 1 ? 1 : minutes,
      today: t,
      walkRunStart: program ? start : null,
      walkRunFrom: program ? t : null,
      walkRunWeeks: program
          ? WalkRunSchedule.forGoal(
              goal,
              anchor: t.subtract(Duration(days: t.weekday - DateTime.monday)),
              from: t,
            ).weeks
          : 0,
    );
  }

  factory PlanInputs.fromJson(Map<String, Object?> json) {
    if (json['inputsVersion'] != 1) {
      throw const FormatException('PlanInputs: unbekannte inputsVersion');
    }
    int intOf(String k, {bool optional = false}) {
      final v = json[k];
      if (v is int) return v;
      if (v == null && optional) return 0;
      throw FormatException('PlanInputs: "$k" ist keine Ganzzahl');
    }

    double? doubleOf(String k) {
      final v = json[k];
      if (v == null) return null;
      if (v is num) return v.toDouble();
      throw FormatException('PlanInputs: "$k" ist keine Zahl');
    }

    final last = json['lastWeekMinutes'];
    if (last != null && last is! int) {
      throw const FormatException('PlanInputs: "lastWeekMinutes"');
    }
    try {
      return PlanInputs(
        walkRunStart: _parseStart(json['walkRunStart']),
        walkRunFrom: json['walkRunFrom'] == null
            ? null
            : _parseDay(json['walkRunFrom'], 'walkRunFrom'),
        intensity: _parseIntensity(json['intensity']),
        anchor: _parseDay(json['anchor'], 'anchor'),
        startWeeklyMinutes: intOf('startWeeklyMinutes'),
        walkRunWeeks: intOf('walkRunWeeks'),
        easyPaceSecondsPerKm: doubleOf('easyPaceSecondsPerKm'),
        easyRunCount: intOf('easyRunCount'),
        lastWeekMinutes: last as int?,
        achievedShare: doubleOf('achievedShare'),
        today: _parseDay(json['today'], 'today'),
      );
    } on ArgumentError catch (e) {
      throw FormatException('PlanInputs: ungültiger Wert (${e.name})');
    }
  }

  /// Montag der Ankerwoche: die Zählung der Wochen (PAR-194) beginnt hier.
  /// Ein Neustart (PAR-202) setzt einen neuen Anker.
  final DateTime anchor;

  /// Wochenzeit der ersten Laufwoche in Minuten (PAR-192).
  final int startWeeklyMinutes;

  /// Länge der Geh-Lauf-Abfolge in Kalenderwochen vor der ersten Laufwoche
  /// (Startfall „nein“, PAR-065), bei Anlage aus [WalkRunSchedule] gerechnet.
  /// Mit [walkRunStart] rechnet die Planung die Länge aus Lauftagen und
  /// maximaler Zeit neu ([WalkRunSchedule.weeks]); ohne [walkRunStart] gilt
  /// dieser Wert als Verlauf ohne Einheiten (ältere Eingaben).
  final int walkRunWeeks;

  /// Stelle der Geh-Lauf-Abfolge in der Ankerwoche; `null`: keine Abfolge.
  /// Wiederholen (PAR-140) setzt eine neue Stelle mit neuem Anker.
  final WalkRunPosition? walkRunStart;

  /// Erster Tag der Abfolge (Anlage mitten in der Woche): Lauftage davor
  /// gehören nicht dazu. Nur mit [walkRunStart].
  final DateTime? walkRunFrom;

  /// Grundlagen der Zielintensität (FR-0153); `null`: nur RPE.
  final IntensityInputs? intensity;

  /// Lockeres Tempo (Median, PAR-205) in s/km und die Zahl der Läufe dahinter.
  final double? easyPaceSecondsPerKm;
  final int easyRunCount;

  /// Nur vorbereitet (PAR-201): Wochenzeit der letzten abgeschlossenen Woche
  /// und erreichter Anteil. Die Rechnung liest sie noch nicht.
  final int? lastWeekMinutes;
  final double? achievedShare;

  /// „Heute“ der Rechnung als Ortstag (Aufzeichnung; [generatePlan] rechnet
  /// mit seinem Argument `today`).
  final DateTime today;

  Map<String, Object?> toJson() => {
    'inputsVersion': 1,
    'anchor': _dayText(anchor),
    'startWeeklyMinutes': startWeeklyMinutes,
    'walkRunWeeks': walkRunWeeks,
    'easyPaceSecondsPerKm': easyPaceSecondsPerKm,
    'easyRunCount': easyRunCount,
    'lastWeekMinutes': lastWeekMinutes,
    'achievedShare': achievedShare,
    'walkRunStart': walkRunStart == null
        ? null
        : {'week': walkRunStart!.week, 'session': walkRunStart!.session},
    'walkRunFrom': walkRunFrom == null ? null : _dayText(walkRunFrom!),
    'intensity': intensity?.toJson(),
    'today': _dayText(today),
  };

  PlanInputs copyWith({
    DateTime? anchor,
    int? startWeeklyMinutes,
    int? walkRunWeeks,
    double? easyPaceSecondsPerKm,
    int? easyRunCount,
    DateTime? today,
    WalkRunPosition? walkRunStart,
    DateTime? walkRunFrom,
    IntensityInputs? intensity,
  }) => PlanInputs(
    walkRunStart: walkRunStart ?? this.walkRunStart,
    walkRunFrom: walkRunFrom ?? this.walkRunFrom,
    intensity: intensity ?? this.intensity,
    anchor: anchor ?? this.anchor,
    startWeeklyMinutes: startWeeklyMinutes ?? this.startWeeklyMinutes,
    walkRunWeeks: walkRunWeeks ?? this.walkRunWeeks,
    easyPaceSecondsPerKm: easyPaceSecondsPerKm ?? this.easyPaceSecondsPerKm,
    easyRunCount: easyRunCount ?? this.easyRunCount,
    lastWeekMinutes: lastWeekMinutes,
    achievedShare: achievedShare,
    today: today ?? this.today,
  );
}

WalkRunPosition? _parseStart(Object? v) {
  if (v == null) return null;
  if (v is Map<String, Object?>) {
    final w = v['week'], s = v['session'];
    if (w is int && s is int && w >= 0 && s >= 0) return WalkRunPosition(w, s);
  }
  throw const FormatException('PlanInputs: "walkRunStart"');
}

IntensityInputs? _parseIntensity(Object? v) {
  if (v == null) return null;
  if (v is Map<String, Object?>) return IntensityInputs.fromJson(v);
  throw const FormatException('PlanInputs: "intensity"');
}

/// „30 min am Stück“ (PAR-192, PAR-198): die einzige Ableitung. ANNAHME: Die
/// Antwort „ja“ oder eine genannte Wochenzeit, deren längster Lauf nach
/// PAR-195 mindestens 30 min ergibt, zählt als Ja; nach der Geh-Lauf-Abfolge
/// ([walkRunWeeks] Wochen) gilt es ebenfalls. Bei „unbekannt“ ohne Wochenzeit
/// bleibt es Nein.
bool canRunContinuous30(
  TrainingGoal goal, {
  required int weekIndex,
  int walkRunWeeks = 0,
  PlanParameters parameters = const PlanParameters(),
}) {
  if (goal.canRun30 == ContinuousRun30.yes) return true;
  final stated = goal.currentWeeklySeconds;
  if (stated != null) {
    final longest =
        stated / 60 * parameters.longestRunShare(goal.runDays.length);
    if (longest >= parameters.continuousRunMinutes) return true;
  }
  return walkRunWeeks > 0 && weekIndex >= walkRunWeeks;
}

/// Zielspitze: längster Lauf, den das Ziel braucht, in Minuten (PAR-205).
/// Das Tempo gilt nur ab [PlanParameters.peakMinEasyRuns] Läufen.
int targetLongestRunMinutes({
  required GoalDistance distance,
  double? easyPaceSecondsPerKm,
  int easyRunCount = 0,
  PlanParameters parameters = const PlanParameters(),
}) {
  final pace = easyPaceSecondsPerKm;
  int minutes;
  if (pace != null &&
      pace.isFinite &&
      pace > 0 &&
      easyRunCount >= parameters.peakMinEasyRuns) {
    final km = distance == GoalDistance.halfMarathon
        ? parameters.peakHalfMarathonKm.toDouble()
        : distance.meters / 1000;
    minutes = (km * pace / 60).ceil();
  } else {
    minutes = switch (distance) {
      GoalDistance.fiveKilometers => parameters.peakFallbackShort,
      GoalDistance.tenKilometers => parameters.peakFallbackTen,
      GoalDistance.halfMarathon => parameters.peakFallbackHalf,
    };
  }
  return minutes > parameters.peakMaxMinutes
      ? parameters.peakMaxMinutes
      : minutes;
}
