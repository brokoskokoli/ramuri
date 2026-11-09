import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter/foundation.dart';

/// Phase der Neuberechnung aus Sicht der Oberfläche.
enum RecalculationPhase { idle, running, done, failed, declineFailed }

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

  /// Nach dem Speichern des Profils. Fehler hier verhindern nichts am
  /// Speichern selbst. Das Angebot steht nach dem Rückkehr sofort in [offer]:
  /// der Strom [RecalculationService.offers] liefert asynchron und käme für
  /// die Rückmeldung der Seite zu spät.
  Future<void> profileChanged(ProfileRecord before, ProfileRecord after) async {
    try {
      final offer = await service.profileChanged(before: before, after: after);
      if (offer != null) _onOffer(offer);
    } on Object {
      // Das Profil ist gespeichert; ein Angebot gibt es dann eben nicht.
    }
  }

  Future<void> confirm() async {
    final offer = _offer;
    if (offer == null || busy) return;
    _phase = RecalculationPhase.running;
    _result = null;
    notifyListeners();
    try {
      // Nicht parallel zum Nachholen aus dem Start und zur Berechnung nach
      // einem Lauf.
      _result = await exclusive(() => service.confirm(offer));
    } on Object {
      // Der alte Stand bleibt ganz (Tausch in einer Transaktion), das Angebot
      // bleibt für einen neuen Versuch.
      _phase = RecalculationPhase.failed;
      if (!_disposed) notifyListeners();
      return;
    }
    // Getauscht ist getauscht: scheitert nur das Lesen eines weiteren Angebots,
    // gilt die Neuberechnung als erledigt und es wird kein Angebot gezeigt.
    try {
      _offer = await service.pendingOffer();
    } on Object {
      _offer = null;
    }
    _phase = RecalculationPhase.done;
    if (!_disposed) notifyListeners();
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
