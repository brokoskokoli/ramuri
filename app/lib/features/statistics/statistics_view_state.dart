/// Art des gewählten Zeitraums (FR-0044).
enum StatisticsKind { week, month, custom, run }

/// Auswahl und Lage der Fortschrittsseite. Die Hülle (`AppShell`) hält ein
/// Objekt über Tab-Wechsel und Neuaufbau hinweg; die Seite liest und schreibt
/// es, die Daten lädt sie bei jedem Aufbau frisch. Ohne übergebenes Objekt
/// legt die Seite ein eigenes an.
///
/// `null` bei [anchor], [from], [to] und [runId] heißt „nicht gewählt“; die
/// Seite nimmt dann heute beziehungsweise den neuesten Lauf. Eine gemerkte
/// [runId] kann inzwischen gelöscht sein; die Seite fällt dann auf den
/// neuesten Lauf zurück.
class StatisticsViewState {
  StatisticsKind kind = StatisticsKind.week;
  String? anchor;
  String? from;
  String? to;
  int? runId;

  /// Scrollposition der Liste; die Seite klemmt sie auf den neuen Inhalt.
  double scrollOffset = 0;
}
