/// Kennung und Version des Datensatzes der Geh-Lauf-Abfolge (NFR-0001,
/// NFR-0005). Wer Zeiten oder Wochen ändert, hebt die Version an.
const String walkRunMethod = 'walk-run-program';
const int walkRunMethodVersion = 1;

/// Art eines Schritts der Abfolge.
enum WalkRunStepKind { run, walk }

/// Ein Schritt: laufen oder gehen, in Sekunden.
class WalkRunStep {
  const WalkRunStep(this.kind, this.seconds);

  final WalkRunStepKind kind;
  final int seconds;
}

/// Datensatz einer Geh-Lauf-Abfolge (PAR-065, PAR-132 bis PAR-139): je
/// Programmwoche die Einheiten mit ihren Schritten. Auf- und Abwärmen (zu
/// Fuß) stehen einmal für das ganze Programm. Die Abfolge steht an genau
/// einer Stelle, [walkRunProgram]; ein anderer Datensatz ersetzt sie ohne
/// weiteren Code.
class WalkRunProgram {
  const WalkRunProgram({
    required this.version,
    required this.warmUpSeconds,
    required this.coolDownSeconds,
    required this.shortenedWalkSeconds,
    required this.weeks,
  });

  /// Version des Datensatzes (nicht die Methode des Plans).
  final int version;

  /// Gehen vor und nach den Läufen (PAR-065, PAR-119).
  final int warmUpSeconds;
  final int coolDownSeconds;

  /// Gehen davor und danach bei zu kurzer Zeit je Einheit (PAR-141).
  final int shortenedWalkSeconds;

  /// Programmwochen; jede Woche hat ihre Einheiten (meist 3).
  final List<WalkRunWeekData> weeks;

  /// Höchste Zahl der Einheiten in einer Woche.
  int get maxSessionsPerWeek =>
      weeks.fold(0, (m, w) => w.sessions.length > m ? w.sessions.length : m);

  /// Alle Einheiten in der Reihenfolge der Abfolge.
  List<({int week, int session})> get orderedSessions => [
    for (var w = 0; w < weeks.length; w++)
      for (var s = 0; s < weeks[w].sessions.length; s++) (week: w, session: s),
  ];
}

/// Eine Programmwoche: ihre Einheiten, je als Liste von Schritten.
class WalkRunWeekData {
  const WalkRunWeekData(this.sessions);

  final List<List<WalkRunStep>> sessions;
}

WalkRunStep _run(int seconds) => WalkRunStep(WalkRunStepKind.run, seconds);
WalkRunStep _walk(int seconds) => WalkRunStep(WalkRunStepKind.walk, seconds);

/// Drei gleiche Einheiten.
WalkRunWeekData _threeTimes(List<WalkRunStep> session) =>
    WalkRunWeekData([session, session, session]);

/// Die Abfolge (PAR-065, PAR-132 bis PAR-139): 9 Programmwochen bis 30 min
/// Dauerlauf, Auf- und Abwärmen je 5 min gehen.
final WalkRunProgram walkRunProgram = WalkRunProgram(
  version: walkRunMethodVersion,
  warmUpSeconds: 300,
  coolDownSeconds: 300,
  shortenedWalkSeconds: 180,
  weeks: _weeks,
);

final List<WalkRunWeekData> _weeks = [
  // Woche 1 (PAR-065): 8 Läufe zu 1:00, 7 Gehpausen zu 1:30.
  _threeTimes([
    for (var i = 0; i < 8; i++) ...[_run(60), if (i < 7) _walk(90)],
  ]),
  // Woche 2 (PAR-132): 5 x (1:30 laufen, 2:00 gehen), dann 1:30 laufen.
  _threeTimes([
    for (var i = 0; i < 5; i++) ...[_run(90), _walk(120)],
    _run(90),
  ]),
  // Woche 3 (PAR-133).
  _threeTimes([
    _run(90),
    _walk(90),
    _run(180),
    _walk(180),
    _run(90),
    _walk(90),
    _run(180),
  ]),
  // Woche 4 (PAR-134).
  _threeTimes([
    _run(180),
    _walk(90),
    _run(300),
    _walk(150),
    _run(180),
    _walk(90),
    _run(300),
  ]),
  // Woche 5 (PAR-135): drei verschiedene Einheiten.
  WalkRunWeekData([
    [_run(300), _walk(180), _run(300), _walk(180), _run(300)],
    [_run(480), _walk(300), _run(480)],
    [_run(1200)],
  ]),
  // Woche 6 (PAR-136).
  WalkRunWeekData([
    [_run(300), _walk(180), _run(480), _walk(180), _run(300)],
    [_run(600), _walk(180), _run(600)],
    [_run(1500)],
  ]),
  // Woche 7 bis 9 (PAR-137 bis PAR-139).
  _threeTimes([_run(1500)]),
  _threeTimes([_run(1680)]),
  _threeTimes([_run(1800)]),
];
