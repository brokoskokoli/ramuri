import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter/foundation.dart';

/// Phase der Neuberechnung aus Sicht der Oberfläche.
enum RecalculationPhase { idle, running, done, failed }

/// Hält das Angebot einer Neuberechnung und den Ablauf für die Oberfläche
/// (FR-0006, FR-0058, OQ-0031, OQ-0053). Alles Rechnen und Speichern liegt im
/// [RecalculationService] aus `core`; hier steht nur der Zustand.
///
/// Fehlermeldungen tragen keine Gesundheitsdaten: der Fehler selbst wird
/// nicht angezeigt, nur [RecalculationPhase.failed].
class RecalculationController extends ChangeNotifier {
  RecalculationController(this.service) {
    _sub = service.offers.listen((o) {
      _offer = o;
      if (_phase != RecalculationPhase.running) {
        _phase = RecalculationPhase.idle;
      }
      notifyListeners();
    });
  }

  final RecalculationService service;
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
  Future<void> start() async {
    try {
      await service.checkVersions();
      final pending = await service.pendingOffer();
      if (_disposed || busy) return;
      _offer = pending;
      notifyListeners();
    } on Object {
      // Kein Angebot sichtbar; beim nächsten Start erneut.
    }
  }

  /// Nach dem Speichern des Profils. Fehler hier verhindern nichts am
  /// Speichern selbst.
  Future<void> profileChanged(ProfileRecord before, ProfileRecord after) async {
    try {
      await service.profileChanged(before: before, after: after);
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
      _result = await service.confirm(offer);
      _offer = await service.pendingOffer();
      _phase = RecalculationPhase.done;
    } on Object {
      // Der alte Stand bleibt ganz (Tausch in einer Transaktion), das Angebot
      // bleibt für einen neuen Versuch.
      _phase = RecalculationPhase.failed;
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> decline() async {
    final offer = _offer;
    if (offer == null || busy) return;
    try {
      await service.decline(offer);
      _offer = null;
      _phase = RecalculationPhase.idle;
    } on Object {
      _phase = RecalculationPhase.failed;
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
