import 'storage.dart' show StorageException, StorageFailure;
import 'storage_settings.dart';

/// Woher das Warnsignal stammt (Spalte `active_warning.source`).
enum WarningSource {
  /// Vom Nutzer gemeldet (Plan-Seite).
  manual('manual'),

  /// Antwort "ja" auf die Warnfrage der Zusammenfassung (WP18).
  runFeedback('run_feedback');

  const WarningSource(this.code);

  /// Wert in der Datenbank und im Archiv.
  final String code;

  static WarningSource? fromCode(String code) {
    for (final s in values) {
      if (s.code == code) return s;
    }
    return null;
  }
}

/// Ortstag aus Jahr, Monat und Tag des Werts, ohne Zeitzonenumrechnung
/// (UTC-Mitternacht): Der Aufrufer übergibt den Ortstag.
DateTime warningDay(DateTime t) => DateTime.utc(t.year, t.month, t.day);

/// Das aktive Warnsignal (FR-0203, K58; Name wegen der Tabellenklasse `ActiveWarning` der Datenbank). [reportedOn] ist ein Ortstag
/// (UTC-Mitternacht, siehe [warningDay]). [runId] nennt den Lauf der Meldung,
/// bindet die Zeile aber nicht an ihn: Sie überlebt das Löschen des Laufs.
class WarningSignal {
  WarningSignal({
    required DateTime reportedOn,
    required this.source,
    this.runId,
  }) : reportedOn = warningDay(reportedOn);

  final DateTime reportedOn;
  final WarningSource source;
  final int? runId;

  @override
  bool operator ==(Object other) =>
      other is WarningSignal &&
      other.reportedOn == reportedOn &&
      other.source == source &&
      other.runId == runId;

  @override
  int get hashCode => Object.hash(reportedOn, source, runId);

  /// Ohne Inhalte (Gesundheitsdaten gehören nicht in Logs).
  @override
  String toString() => 'WarningSignal';
}

/// Das Warnsignal: höchstens eines. Gelöscht wird es nur durch [lift] und
/// durch [StorageSession.deleteAll], nicht durch [StorageSession.deleteRun].
/// Jede Methode wirft nur [StorageException].
abstract interface class WarningStore {
  /// Das aktive Warnsignal oder `null`.
  Future<WarningSignal?> read();

  /// Setzt das Warnsignal; ein vorhandenes wird ersetzt (höchstens eines).
  /// Einen Lauf, den es nicht (mehr) gibt, nimmt der Speicher an
  /// (kein Fremdschlüssel).
  Future<void> set(WarningSignal warning);

  /// Hebt das Warnsignal auf, die Zeile wird gelöscht. Ohne Warnsignal ein
  /// Nichts (idempotent).
  Future<void> lift();
}

/// Ein Speicher, der das Warnsignal führt; getrennt von [StorageSession]
/// (wie `GoalStorage`).
abstract interface class WarningStorage {
  WarningStore get warning;
}

/// Prüfung vor dem Speichern, gleich für Fake und Datenbank.
void checkWarningForStorage(WarningSignal w) {
  final id = w.runId;
  if (id != null && id <= 0) {
    throw const StorageException(StorageFailure.rejected);
  }
}

/// Schlüssel der Zusatzzustände zum Warnsignal in `settings`. Sie sind keine
/// technischen Merker: Sie gehen ins Archiv und werden mit "Alles löschen"
/// entfernt.
abstract final class WarningSettingKeys {
  /// Ortstag der letzten Nachfrage (Erinnerung nach 7 Tagen, FR-0203), `JJJJ-MM-TT`.
  static const String lastPromptOn = 'warning.last_prompt_on';

  /// Antwort auf die Pausenfrage: `yes:JJJJ-MM-TT` oder `no:JJJJ-MM-TT`
  /// (Antwort, Ortstag der Antwort).
  static const String pauseAnswer = 'warning.pause_answer';

  /// Hinweissperre (PAR-175): bis zu diesem Ortstag (einschließlich) kein
  /// neuer Hinweis, `JJJJ-MM-TT`.
  static const String hintBlockedUntil = 'warning.hint_blocked_until';

  /// Kennung der Plan-Fassung, deren Karte "Plan angepasst" gesehen wurde
  /// (ganze Zahl).
  static const String planChangeSeen = 'plan.change_seen_plan_id';
}

/// Antwort auf die Pausenfrage mit Ortstag.
class PauseAnswer {
  PauseAnswer({required this.paused, required DateTime on})
    : on = warningDay(on);

  /// `true`: Pause bestätigt ("ja").
  final bool paused;
  final DateTime on;

  @override
  bool operator ==(Object other) =>
      other is PauseAnswer && other.paused == paused && other.on == on;

  @override
  int get hashCode => Object.hash(paused, on);
}

/// Typisierter Zugriff auf die Zusatzzustände über [SettingsStore]. Ein
/// unlesbarer Wert gilt wie ein fehlender (nie eine Ausnahme mit Inhalt).
class WarningState {
  const WarningState(this._settings);
  final SettingsStore _settings;

  Future<DateTime?> lastPromptOn() async =>
      _parseDay(await _settings.get(WarningSettingKeys.lastPromptOn));

  Future<void> setLastPromptOn(DateTime day, {required DateTime at}) =>
      _settings.set(WarningSettingKeys.lastPromptOn, _dayText(day), at: at);

  Future<PauseAnswer?> pauseAnswer() async {
    final v = await _settings.get(WarningSettingKeys.pauseAnswer);
    if (v == null) return null;
    final i = v.indexOf(':');
    if (i < 0) return null;
    final head = v.substring(0, i);
    final day = _parseDay(v.substring(i + 1));
    if (day == null || (head != 'yes' && head != 'no')) return null;
    return PauseAnswer(paused: head == 'yes', on: day);
  }

  Future<void> setPauseAnswer(PauseAnswer a, {required DateTime at}) =>
      _settings.set(
        WarningSettingKeys.pauseAnswer,
        '${a.paused ? 'yes' : 'no'}:${_dayText(a.on)}',
        at: at,
      );

  Future<DateTime?> hintBlockedUntil() async =>
      _parseDay(await _settings.get(WarningSettingKeys.hintBlockedUntil));

  Future<void> setHintBlockedUntil(DateTime day, {required DateTime at}) =>
      _settings.set(WarningSettingKeys.hintBlockedUntil, _dayText(day), at: at);

  Future<int?> planChangeSeen() async {
    final v = await _settings.get(WarningSettingKeys.planChangeSeen);
    final n = v == null ? null : int.tryParse(v);
    return n != null && n > 0 ? n : null;
  }

  Future<void> setPlanChangeSeen(int planId, {required DateTime at}) {
    if (planId <= 0) throw const StorageException(StorageFailure.rejected);
    return _settings.set(WarningSettingKeys.planChangeSeen, '$planId', at: at);
  }

  static String _dayText(DateTime t) {
    final d = warningDay(t);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year.toString().padLeft(4, '0')}-${two(d.month)}-${two(d.day)}';
  }

  static DateTime? _parseDay(String? v) {
    if (v == null || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(v)) return null;
    final d = DateTime.tryParse('${v}T00:00:00Z');
    return d != null && _dayText(d) == v ? d : null;
  }
}
