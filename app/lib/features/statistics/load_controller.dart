import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter/foundation.dart';

import 'load_view_state.dart';

/// Lädt den Belastungsstand (WP19) und hält ihn für die Karte „Belastung“.
/// Alles Rechnen liegt im [TrainingLoadService] aus `core`.
///
/// Neu geladen wird beim Anlegen, auf [reload] und bei jeder Meldung von
/// [changes] (nach Lauf, Nachtrag, Profil-/Einstellungsänderung und
/// Neuberechnung meldet `DataChanges`). Mehrere Anstöße in kurzer Folge
/// ergeben höchstens einen weiteren Lauf; der Stand springt nie auf einen
/// älteren zurück. Ein Fehler zeigt nur [LoadPhase.failed] (auch über einem
/// früheren Stand: kein stilles Stehenlassen), nie den Inhalt des Fehlers
/// (Gesundheitsdaten).
class LoadController extends ChangeNotifier {
  LoadController({required this.service, this.changes, this.serialize}) {
    changes?.addListener(reload);
    unawaited(reload());
  }

  final TrainingLoadService service;

  /// Meldet Änderungen der gespeicherten Daten (`DataChanges`).
  final Listenable? changes;

  /// Reiht das Laden in die Schlange der Neuberechnung ein, denn
  /// [TrainingLoadService.load] schreibt Einstellungen (Faktor, Angebot) und
  /// darf nicht parallel zu Bestätigen und Ablehnen laufen. In der App
  /// `RecalculationController.serialized` (nicht `exclusive`: dessen
  /// Datenänderungs-Meldung löste das Neuladen immer wieder aus). `null` =
  /// sofort.
  final Future<T> Function<T>(Future<T> Function() action)? serialize;

  LoadViewState _state = const LoadViewState.loading();
  bool _running = false;
  bool _again = false;
  bool _disposed = false;

  LoadViewState get state => _state;

  /// Lädt neu. Läuft schon ein Laden, folgt genau ein weiteres danach.
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
        LoadViewState next;
        try {
          final s = serialize;
          next = LoadViewState.ready(
            s == null ? await service.load() : await s(service.load),
          );
        } on Object {
          next = const LoadViewState.failed();
        }
        if (_disposed) return;
        _state = next;
        notifyListeners();
      } while (_again);
    } finally {
      _running = false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    changes?.removeListener(reload);
    super.dispose();
  }
}
