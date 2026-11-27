import '../../ports/storage_warning.dart' show warningDay;

// Pausenfrage und Merker des Neustarts zur Pause (PAR-202, PAR-181). Sie
// liegen im Plan-Modul, weil der Plan-Ablauf ([PlanWorkflowService]) den
// Neustart rechnet; die Auswahl der Hinweise (`hints`) nutzt sie mit.

/// Die Pausenfrage (PAR-202): Ab 7 Tagen (PAR-180) ohne
/// erfasstes Training fragt die App, ob eine Pause war. [baseWeekMinutes] ist
/// die Summe der erfassten Minuten der Basiswoche ([pauseBaseWeek]: letzte
/// vollständige Kalenderwoche vor Beginn der Pause, Grundlage des Neustarts).
class PauseQuestion {
  const PauseQuestion({
    required this.daysSinceTraining,
    required this.lastTrainingDay,
    required this.baseWeekMinutes,
  });
  final int daysSinceTraining;
  final DateTime lastTrainingDay;
  final double baseWeekMinutes;
}

/// Merker: Der Neustart zur Pause nach dem Training vom Tag [day] wurde
/// bearbeitet; [restarted] = dabei entstand eine Fassung `pause` (sonst blieb
/// der Plan, z. B. in der Geh-Lauf-Abfolge). [provisional]: Bei einer Pause ab
/// 8 Wochen gilt vorläufig die sichere Vorgabe (Stufe 2) bis der Nutzer den
/// Einstieg wählt (PAR-181); der Einstieg bleibt dann wählbar. Gespeichert als
/// Text.
class PauseRestartMark {
  PauseRestartMark({
    required DateTime day,
    required this.restarted,
    this.provisional = false,
  }) : day = warningDay(day);
  final DateTime day;
  final bool restarted;
  final bool provisional;

  static const _tokens = {
    'restart': (true, false),
    'none': (false, false),
    'provisional': (true, true),
    'provisional-none': (false, true),
  };

  /// `JJJJ-MM-TT restart`, `… none`, `… provisional` oder
  /// `… provisional-none`; sonst `null`.
  static PauseRestartMark? parse(String? text) {
    if (text == null) return null;
    final parts = text.split(' ');
    final token = parts.length == 2 ? _tokens[parts[1]] : null;
    if (token == null) return null;
    final day = DateTime.tryParse('${parts[0]}T00:00:00Z');
    if (day == null) return null;
    return PauseRestartMark(
      day: day,
      restarted: token.$1,
      provisional: token.$2,
    );
  }

  String format() {
    String two(int v) => v.toString().padLeft(2, '0');
    final token = _tokens.entries
        .firstWhere((e) => e.value == (restarted, provisional))
        .key;
    return '${day.year.toString().padLeft(4, '0')}-${two(day.month)}-'
        '${two(day.day)} $token';
  }
}

/// Port: offene Pausenfrage und anstehender Neustart (PAR-202, PAR-181) für
/// die Plan-Abläufe; in der App der Dienst der Hinweise.
abstract interface class PlanPauseSource {
  /// Offene Pausenfrage oder `null`.
  Future<PauseQuestion?> pauseQuestion();

  /// Pause steht ohne Frage fest (Zusage „alles erfasst“) und wurde noch
  /// nicht bearbeitet, sonst `null`.
  Future<PauseQuestion?> pauseRestartDue();

  /// Neuer Einstieg nach langer Pause steht an (PAR-181), sonst `null`.
  Future<PauseQuestion?> newStartDue();
}
