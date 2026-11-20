import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter/foundation.dart';

/// Phase der Neuberechnung aus Sicht der Oberfläche.
///
/// Ein Erfolg ist keine eigene Phase: [RecalculationController.confirm] gibt
/// das Ergebnis zurück, die Seite meldet es als Snackbar, die Karte steht
/// danach wieder in [idle].
enum RecalculationPhase { idle, running, failed, declineFailed }

/// Warum die App ohne Nachfrage von Banister auf Edwards umgestellt hat
/// (FR-0197: ohne Läufe mit Werten ist nichts neu zu rechnen). Die Seite
/// weist darauf hin.
enum EdwardsSwitchReason {
  /// Der Ruhepuls fehlt (Profil gespeichert).
  restingHeartRate,

  /// Der Ruhepuls ist da, aber Ruhepuls und HFmax ergeben keine brauchbare
  /// Herzfrequenzreserve (FR-0060; Profil gespeichert).
  heartRateReserve,

  /// Die Koeffizienten-Angabe wurde entfernt.
  coefficients,
}

/// Der Grund für den Hinweis aus den [issues] der Auflösung, die umgestellt
/// hat. Bei mehreren gilt: fehlender Ruhepuls vor unbrauchbarer Reserve vor
/// fehlenden Koeffizienten. Ohne Issues `null`.
EdwardsSwitchReason? edwardsSwitchReasonOf(Iterable<LoadProfileIssue> issues) {
  if (issues.contains(LoadProfileIssue.missingRestingHeartRate)) {
    return EdwardsSwitchReason.restingHeartRate;
  }
  if (issues.contains(LoadProfileIssue.heartRateReserveUnusable)) {
    return EdwardsSwitchReason.heartRateReserve;
  }
  if (issues.contains(LoadProfileIssue.missingCoefficients)) {
    return EdwardsSwitchReason.coefficients;
  }
  return null;
}

/// Hält das Angebot einer Neuberechnung und den Ablauf für die Oberfläche
/// (FR-0006, FR-0058, OQ-0031, OQ-0053). Alles Rechnen und Speichern liegt im
/// [RecalculationService] aus `core`; hier steht nur der Zustand.
///
/// Fehlermeldungen tragen keine Gesundheitsdaten: der Fehler selbst wird
/// nicht angezeigt, nur [RecalculationPhase.failed].
class RecalculationController extends ChangeNotifier {
  RecalculationController(this.service, {this.onStart, this.onDataChanged}) {
    _sub = service.offers.listen(_onOffer);
  }

  void _onOffer(RecalculationOffer o) {
    if (_disposed) return;
    _offer = o;
    if (_phase != RecalculationPhase.running) {
      _phase = RecalculationPhase.idle;
    }
    notifyListeners();
  }

  final RecalculationService service;

  /// Läuft einmal zu Beginn von [start], vor allem anderen (etwa das Nachholen
  /// der Tageswerte nach einem Löschen). Fehler werden verschluckt.
  final Future<void> Function()? onStart;

  /// Meldet, dass Werte geschrieben worden sein können: nach dem Nachholen
  /// beim Start und nach jeder Aktion über [exclusive] (Berechnung nach dem
  /// Lauf, Löschen, Import, Neuberechnung), auch wenn sie scheitert. Die
  /// Oberfläche lädt daraufhin ihre Daten neu.
  final VoidCallback? onDataChanged;
  Future<void>? _starting;
  Future<void> _queue = Future<void>.value();
  late final StreamSubscription<RecalculationOffer> _sub;

  RecalculationOffer? _offer;
  RecalculationPhase _phase = RecalculationPhase.idle;
  RecalculationResult? _result;
  bool _disposed = false;

  RecalculationOffer? get offer => _offer;
  RecalculationPhase get phase => _phase;
  RecalculationResult? get result => _result;

  EdwardsSwitchReason? _edwardsSwitch;

  /// Holt den Grund einer stillen Umstellung von Banister auf Edwards seit
  /// dem letzten Abholen ab (einmal, danach `null`), damit die Seite darauf
  /// hinweist. Die Wahl des Nutzers über [requestLoadProfile] zählt nicht.
  EdwardsSwitchReason? takeEdwardsSwitch() {
    final r = _edwardsSwitch;
    _edwardsSwitch = null;
    return r;
  }

  /// Führt [action] aus und merkt sich den Grund aus [reason], wenn das
  /// aktive Profil dabei von Banister auf Edwards gewechselt ist.
  Future<T> _watchEdwardsSwitch<T>(
    EdwardsSwitchReason? Function() reason,
    Future<T> Function() action,
  ) async {
    final store = service.session.settings;
    final before = await LoadSettings.activeProfile(store);
    final result = await action();
    if (before == LoadProfile.banister &&
        await LoadSettings.activeProfile(store) == LoadProfile.edwards) {
      final r = reason();
      if (r != null) _edwardsSwitch = r;
    }
    return result;
  }

  /// Wie [_watchEdwardsSwitch] für Aufrufe, die über die Auflösung des
  /// Service umstellen: Der Grund kommt aus genau der Auflösung, die
  /// umgestellt hat ([RecalculationService.takeEdwardsSwitchIssues]).
  Future<T> _watchResolvedEdwardsSwitch<T>(Future<T> Function() action) {
    // Gründe einer älteren, nicht abgeholten Umstellung verwerfen.
    service.takeEdwardsSwitchIssues();
    return _watchEdwardsSwitch(
      () => edwardsSwitchReasonOf(service.takeEdwardsSwitchIssues() ?? []),
      action,
    );
  }

  /// Solange gerechnet wird, darf nichts anderes die Werte ändern oder die
  /// Seite verlassen werden (Sperre).
  bool get busy => _phase == RecalculationPhase.running;

  /// Beim App-Start: offenes Angebot lesen und prüfen, ob sich die Version
  /// der Berechnung geändert hat. Ein Fehler lässt kein Angebot erscheinen
  /// und ändert nichts.
  Future<void> start() => _starting ??= _start();

  Future<void> _start() async {
    try {
      await onStart?.call();
    } on Object {
      // Die Werte fehlen weiter; der Merker bleibt, beim nächsten Start erneut.
    }
    try {
      await service.checkVersions();
      final pending = await service.pendingOffer();
      if (_disposed || busy) return;
      _offer = pending;
      notifyListeners();
    } on Object {
      // Kein Angebot sichtbar; beim nächsten Start erneut.
    }
    _dataChanged();
  }

  void _dataChanged() {
    if (!_disposed) onDataChanged?.call();
  }

  /// Führt [action] erst aus, wenn der Start (Nachholen beim Start) und alle
  /// vorher eingereihten Aktionen fertig sind, und nie parallel zu ihnen. Wer
  /// Werte schreibt (Berechnung nach dem Lauf, [confirm]), geht hier durch.
  /// Ein Fehler der Aktion geht an den Aufrufer, die Reihe läuft weiter.
  Future<T> exclusive<T>(Future<T> Function() action) =>
      serialized(action).whenComplete(_dataChanged);

  /// Wie [exclusive], aber ohne [onDataChanged] danach. Für Aktionen, die nur
  /// lesen oder Merker schreiben (Ablehnen, Laden des Belastungsstands): würde
  /// ihr Ende `onDataChanged` melden, lüde die Oberfläche neu und riefe sie
  /// wieder auf, ohne Ende.
  Future<T> serialized<T>(Future<T> Function() action) {
    final result = _queue.then((_) async {
      await _starting;
      return action();
    });
    _queue = result.then((_) {}, onError: (Object _) {});
    return result;
  }

  /// Wie [serialized], liest danach aber das offene Angebot neu. Für Aktionen,
  /// die ein Faktor-Angebot zurücknehmen oder ersetzen können (Laden des
  /// Belastungsstands): die Karte der Neuberechnung zeigt sonst weiter ein
  /// Angebot, das es nicht mehr gibt, oder einen alten Wert.
  Future<T> serializedRefreshingOffer<T>(Future<T> Function() action) =>
      serialized(() async {
        try {
          return await action();
        } finally {
          await _refreshOffer();
        }
      });

  /// Liest das offene Angebot neu und meldet nur eine Änderung. Während der
  /// Neuberechnung nicht: sie liest das Angebot danach selbst.
  Future<void> _refreshOffer() async {
    if (_disposed || busy) return;
    try {
      final pending = await service.pendingOffer();
      if (_disposed || busy || _sameOffer(_offer, pending)) return;
      _offer = pending;
      notifyListeners();
    } on Object {
      // Das Angebot bleibt, wie es war; beim nächsten Mal erneut.
    }
  }

  static bool _sameOffer(RecalculationOffer? a, RecalculationOffer? b) {
    if (a == null || b == null) return a == null && b == null;
    return setEquals(a.causes, b.causes) &&
        listEquals(a.runIds, b.runIds) &&
        a.loadProfile == b.loadProfile &&
        a.personalFactor == b.personalFactor;
  }

  /// Nach dem Speichern des Profils. Fehler hier verhindern nichts am
  /// Speichern selbst. Das Angebot steht nach dem Rückkehr sofort in [offer]:
  /// der Strom [RecalculationService.offers] liefert asynchron und käme für
  /// die Rückmeldung der Seite zu spät.
  Future<void> profileChanged(ProfileRecord before, ProfileRecord after) async {
    try {
      final offer = await _watchResolvedEdwardsSwitch(
        () => service.profileChanged(before: before, after: after),
      );
      if (offer != null) _onOffer(offer);
    } on Object {
      // Das Profil ist gespeichert; ein Angebot gibt es dann eben nicht.
    }
  }

  /// Wählt das Belastungsprofil (FR-0197). Mit Läufen entsteht ein Angebot
  /// (Ursache `loadProfile`), das erst die Bestätigung gültig macht; sonst gilt
  /// die Wahl sofort. Wirft [LoadProfileNotApplicableException] oder
  /// [StorageException]. Meldet danach eine Datenänderung (Karte Belastung).
  Future<void> requestLoadProfile(LoadProfile target) =>
      _requestChange(() => service.requestLoadProfile(target));

  /// Ändert die Koeffizienten-Angabe (`null` entfernt sie). Bei aktivem
  /// Banister als Angebot, sonst sofort (siehe
  /// [RecalculationService.requestLoadCoefficients]).
  /// Stellt das Entfernen ohne Läufe mit Werten sofort auf Edwards um, steht
  /// das danach in [takeEdwardsSwitch].
  Future<void> requestLoadCoefficients(LoadCoefficients? value) =>
      _requestChange(
        () => _watchEdwardsSwitch(
          () => EdwardsSwitchReason.coefficients,
          () => service.requestLoadCoefficients(value),
        ),
      );

  /// Nach einer Änderung von Ruhepuls oder HFmax (siehe
  /// [RecalculationService.loadBasisChanged]); Fehler verhindern nichts am
  /// bereits gespeicherten Profil. Eine Umstellung auf Edwards ohne Läufe mit
  /// Werten steht danach in [takeEdwardsSwitch].
  Future<void> loadBasisChanged() async {
    try {
      await _requestChange(
        () => _watchResolvedEdwardsSwitch(service.loadBasisChanged),
      );
    } on Object {
      // Das Profil ist gespeichert; ein Angebot gibt es dann eben nicht.
    }
  }

  /// Die Zusage „alles erfasst“ (FR-0103). Leere Tage ändern ATL/CTL, darum
  /// lädt die Karte Belastung danach neu; eine Neuberechnung gibt es nicht.
  Future<void> setAllRecorded(bool value) => _requestChange(() async {
    await LoadSettings.saveAllRecorded(
      service.session.settings,
      value,
      at: service.clock.now(),
    );
    return null;
  });

  /// Führt eine Änderung der Belastungseinstellungen in der Reihe aus und liest
  /// danach das offene Angebot neu: ein Wechsel, eine Rücknahme der Wahl oder
  /// eine Ablehnung ändern es, der Strom [RecalculationService.offers] liefert
  /// nur neue Angebote.
  Future<void> _requestChange(
    Future<RecalculationOffer?> Function() action,
  ) async {
    try {
      await exclusive(action);
    } finally {
      if (!_disposed && !busy) {
        try {
          final pending = await service.pendingOffer();
          if (!_disposed && !_sameOffer(_offer, pending)) {
            _offer = pending;
            _phase = RecalculationPhase.idle;
          }
        } on Object {
          // Das Angebot bleibt, wie es war.
        }
        if (!_disposed) notifyListeners();
      }
    }
  }

  Future<void> _showCurrentOffer() async {
    try {
      _offer = await service.pendingOffer();
    } on Object {
      _offer = null;
    }
    _phase = RecalculationPhase.idle;
    if (!_disposed) notifyListeners();
  }

  /// Bestätigt das gezeigte Angebot. Gibt das Ergebnis zurück, wenn
  /// neu berechnet wurde, sonst `null` (kein Angebot, schon beschäftigt,
  /// Angebot inzwischen ersetzt, Fehler). Nach dem Erfolg steht die Phase
  /// wieder auf [RecalculationPhase.idle]; die Meldung gibt die Seite aus.
  Future<RecalculationResult?> confirm() async {
    final offer = _offer;
    if (offer == null || busy) return null;
    _phase = RecalculationPhase.running;
    _result = null;
    notifyListeners();
    try {
      // Nicht parallel zum Nachholen aus dem Start und zur Berechnung nach
      // einem Lauf.
      _result = await exclusive(() => service.confirm(offer));
    } on RecalculationOfferChangedException {
      // Das gezeigte Angebot gibt es so nicht mehr; nichts wurde geändert. Das
      // neue Angebot steht danach da, bestätigt wird erst auf Wunsch.
      await _showCurrentOffer();
      return null;
    } on Object {
      // Der alte Stand bleibt ganz (Tausch in einer Transaktion), das Angebot
      // bleibt für einen neuen Versuch.
      _phase = RecalculationPhase.failed;
      if (!_disposed) notifyListeners();
      return null;
    }
    // Getauscht ist getauscht: scheitert nur das Lesen eines weiteren Angebots,
    // gilt die Neuberechnung als erledigt und es wird kein Angebot gezeigt.
    try {
      _offer = await service.pendingOffer();
    } on Object {
      _offer = null;
    }
    _phase = RecalculationPhase.idle;
    if (!_disposed) notifyListeners();
    return _result;
  }

  Future<void> decline() async {
    final offer = _offer;
    if (offer == null || busy) return;
    try {
      // Nicht parallel zu einer Bestätigung, zum Nachholen und zum Laden des
      // Belastungsstands: alle schreiben Einstellungen.
      await serialized(() => service.decline(offer));
      _offer = null;
      _phase = RecalculationPhase.idle;
    } on RecalculationOfferChangedException {
      await _showCurrentOffer();
      return;
    } on Object {
      // Nichts geändert; das Angebot bleibt, eigene Meldung (kein Rechenfehler).
      _phase = RecalculationPhase.declineFailed;
    }
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _sub.cancel();
    super.dispose();
  }
}
