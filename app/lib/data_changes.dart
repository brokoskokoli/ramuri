import 'package:flutter/foundation.dart';

/// Meldet den Bereichen der App (Heute, Verlauf, Fortschritt), dass sich die
/// gespeicherten Daten geändert haben können. Der Speicher hat keine Ströme;
/// diese Benachrichtigung gibt es einmal je Sitzung (in `ReadyRoot`). Wer sie
/// hört, baut sich mit neuer [revision] neu auf und lädt dabei die Daten.
class DataChanges extends ChangeNotifier {
  int _revision = 0;
  bool _disposed = false;

  /// Zählt mit jeder Änderung hoch; als Teil eines `ValueKey` erzwingt sie den
  /// Neuaufbau samt Neuladen.
  int get revision => _revision;

  void changed() {
    // Späte Meldungen einer Aktion nach dem Ende der Sitzung gehen ins Leere.
    if (_disposed) return;
    _revision++;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
