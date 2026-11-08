import 'package:core/core.dart';

/// Auswahl des Verlaufs. Die Hülle (`AppShell`) hält ein Objekt über Tab-Wechsel
/// und Neuaufbau hinweg (wie `StatisticsViewState`); die Seite liest und
/// schreibt es, die Daten lädt sie bei jedem Aufbau frisch. Ohne übergebenes
/// Objekt legt die Seite ein eigenes an.
///
/// Die Scrollposition hält die Liste selbst über ihren `PageStorageKey` (WP13),
/// je Zeitraum eine eigene; sie gehört nicht hierher.
class HistoryViewState {
  /// Der Monat ist die Vorgabe des Designs („Verlauf“).
  HistoryRange range = HistoryRange.month;
}
