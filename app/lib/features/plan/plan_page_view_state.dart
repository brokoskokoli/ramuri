/// Auswahl und Lage der Plan-Seite. Die Hülle (`AppShell`) hält ein Objekt
/// über Tab-Wechsel und Neuaufbau hinweg (wie `StatisticsViewState`); die
/// Seite liest und schreibt es, die Daten lädt sie bei jedem Aufbau frisch.
/// Ohne übergebenes Objekt legt die Seite ein eigenes an.
class PlanPageViewState {
  /// Gezeigte Woche relativ zur Woche von heute (0 = diese Woche).
  int weekOffset = 0;

  /// Scrollposition der Seite; ein kürzerer Inhalt begrenzt sie beim ersten
  /// Layout selbst auf sein Ende.
  double scrollOffset = 0;
}
