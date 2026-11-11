import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter/foundation.dart';

enum PredictionPhase { loading, ready, failed }

/// Stand der Prognosekarte (WP20 Teil C).
class PredictionViewState {
  const PredictionViewState.loading()
    : phase = PredictionPhase.loading,
      prediction = null,
      showTestHint = false,
      all = const [],
      suggestion = null;

  const PredictionViewState.failed()
    : phase = PredictionPhase.failed,
      prediction = null,
      showTestHint = false,
      all = const [],
      suggestion = null;

  const PredictionViewState.ready({
    required PerformancePrediction this.prediction,
    required this.showTestHint,
    required this.all,
    required this.suggestion,
  }) : phase = PredictionPhase.ready;

  final PredictionPhase phase;
  final PerformancePrediction? prediction;

  /// Hinweis auf einen 5-km-Test ([showFiveKilometerTestHint]).
  final bool showTestHint;

  /// Die gespeicherte geltende Referenz (mit Kennung zum Löschen), auch wenn
  /// sie die Prognose nicht trägt (zu alt, Pause): die jüngste brauchbare
  /// ([isUsableReference], wie `activeReference` in `core`); `null` ohne
  /// brauchbare Referenz.
  StoredReference? get active {
    for (final s in all) {
      if (isUsableReference(s.reference)) return s;
    }
    return null;
  }

  /// Alle gespeicherten Referenzen, jüngste zuerst, auch unbrauchbare.
  final List<StoredReference> all;

  /// Alle außer [active]; unbrauchbare zeigt die Karte als ungültig.
  List<StoredReference> get others => [
    for (final s in all)
      if (!identical(s, active)) s,
  ];

  /// Der eine Vorschlag, der gerade zur Bestätigung ansteht, oder `null`.
  final ReferenceSuggestion? suggestion;
}

/// Lädt die Prognose, den Vorschlag und führt Eintragen, Löschen, Bestätigen
/// und Ablehnen aus. Gerechnet wird in `core` ([predictPerformance],
/// [suggestReferences]); die Tempowerte-Wiedergabe läuft über [offload] und
/// nur für Läufe der letzten Referenz-Gültigkeitsdauer (182 Tage).
///
/// Ein Vorschlag wird nie von allein übernommen: [acceptSuggestion] ist der
/// einzige Weg, und den löst nur die Bestätigung des Nutzers aus.
class PredictionController extends ChangeNotifier {
  PredictionController({
    required this.session,
    required this.clock,
    required this.hasVo2maxEstimate,
    this.offload = inlineOffload,
    this.parameters = const PredictionParameters(),
    this.onChanged,
  }) : _store = (session as PredictionStorage).prediction {
    unawaited(reload());
  }

  final StorageSession session;
  final Clock clock;
  final bool hasVo2maxEstimate;
  final Offload offload;
  final PredictionParameters parameters;

  /// Nach jeder Änderung der gespeicherten Daten (Eintragen, Löschen,
  /// Bestätigen, Ablehnen). Meldet die App über `DataChanges`.
  final VoidCallback? onChanged;

  final PredictionStore _store;

  PredictionViewState _state = const PredictionViewState.loading();
  bool _running = false;
  bool _again = false;
  bool _disposed = false;

  PredictionViewState get state => _state;

  Future<void> reload() async {
    if (_disposed) return;
    if (_running) {
      _again = true;
      return;
    }
    _running = true;
    try {
      do {
        _again = false;
        PredictionViewState next;
        try {
          next = await _compute();
        } on Object {
          // Nie den Inhalt des Fehlers zeigen (Gesundheitsdaten).
          next = const PredictionViewState.failed();
        }
        if (_disposed) return;
        _state = next;
        notifyListeners();
      } while (_again);
    } finally {
      _running = false;
    }
  }

  Future<PredictionViewState> _compute() async {
    final now = clock.now();
    final stored = await _store.references();
    final rejected = await _store.rejectedSuggestions();
    final today = calendarDay(now);
    final storedRunIds = {
      for (final s in stored)
        if (s.reference.runId != null) s.reference.runId!,
    };
    final rejectedIds = {for (final id in rejected) '$id'};
    final runs =
        await PredictionRunReader(
          session: session,
          clock: clock,
          parameters: parameters,
          offload: offload,
        ).load(
          noPaceFor: {...storedRunIds, ...rejectedIds},
          paceSince: today.subtract(
            Duration(days: parameters.maxReferenceAgeDays),
          ),
        );
    final prediction = predictPerformance(
      now: now,
      references: [for (final s in stored) s.reference],
      runs: runs,
      hasVo2maxEstimate: hasVo2maxEstimate,
      parameters: parameters,
    );
    final active = activeReference([for (final s in stored) s.reference]);
    // Nur Läufe der letzten 182 Tage kommen als Vorschlag in Frage; ältere
    // haben keine Tempowerte und die Referenz wäre schon zu alt.
    final recent = [
      for (final r in runs)
        if (daysBetween(r.date, now) <= parameters.maxReferenceAgeDays) r,
    ];
    final suggestions = suggestReferences(
      runs: recent,
      activeReference: active,
      rejectedRunIds: rejectedIds,
      storedRunIds: storedRunIds,
      parameters: parameters,
    );
    return PredictionViewState.ready(
      prediction: prediction,
      showTestHint: showFiveKilometerTestHint(
        prediction: prediction,
        now: now,
        runs: runs,
        parameters: parameters,
      ),
      all: stored,
      suggestion: suggestions.isEmpty ? null : suggestions.first,
    );
  }

  /// Trägt eine Referenz ein. `false`, wenn der Speicher sie abweist oder
  /// nicht erreichbar ist.
  Future<bool> addReference(ReferencePerformance reference) =>
      _mutate(() => _store.addReference(reference));

  /// Löscht die geltende Referenz.
  Future<bool> deleteActive() {
    final id = _state.active?.id;
    if (id == null) return Future.value(false);
    return deleteReference(id);
  }

  /// Löscht eine gespeicherte Referenz (auch eine ältere, nicht geltende).
  Future<bool> deleteReference(int id) =>
      _mutate(() => _store.deleteReference(id));

  /// Übernimmt den Vorschlag als bestätigten Lauf (FR-0131).
  Future<bool> acceptSuggestion(ReferenceSuggestion s) {
    final run = s.run;
    final meters = run.distanceMeters;
    if (meters == null) return Future.value(false);
    return _mutate(
      () => _store.addReference(
        ReferencePerformance(
          kind: ReferenceKind.confirmedRun,
          distanceMeters: meters,
          seconds: run.movingSeconds,
          date: run.date,
          createdAt: clock.now(),
          runId: run.id,
        ),
      ),
    );
  }

  /// Lehnt den Vorschlag ab; derselbe Lauf kommt nicht wieder.
  Future<bool> rejectSuggestion(ReferenceSuggestion s) {
    final id = int.tryParse(s.run.id);
    if (id == null) return Future.value(false);
    return _mutate(() => _store.rejectSuggestion(id));
  }

  bool _mutating = false;

  /// Läuft gerade eine Änderung (bis das Neuladen fertig ist)? Die Karte
  /// sperrt dann ihre Knöpfe (Soll 1).
  bool get busy => _mutating;

  /// Eine Änderung zur Zeit: Doppeltippen löst keine zweite aus (Soll 8). Die
  /// Sperre fällt erst nach dem Neuladen, sonst wäre kurz noch der alte
  /// Vorschlag zu sehen und anzutippen.
  Future<bool> _mutate(Future<Object?> Function() action) async {
    if (_mutating) return false;
    _mutating = true;
    notifyListeners();
    try {
      try {
        await action();
      } on Object {
        return false;
      }
      if (_disposed) return true;
      // Die App baut den Tab auf die Meldung hin neu auf; das Neuladen hier
      // hält auch eine Karte aktuell, die nicht neu aufgebaut wird.
      onChanged?.call();
      await reload();
      return true;
    } finally {
      _mutating = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
