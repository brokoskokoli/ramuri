import 'dart:async';
import 'dart:collection';

import '../../ports/storage.dart';

/// Die eine Schreibreihe des Plans je Sitzung (ADR-0010: eine Fassung rechnet
/// auf dem Stand, den die vorige hinterlassen hat). Jede Planänderung – aus
/// jeder Instanz des Plan-Controllers, dem Erholungs-Auslöser und der
/// automatischen Zuordnung – läuft über [run]; so überholen sich Fassungen
/// und Zuordnungen nicht.
///
/// Reihenfolge der Sperren: Wer zusätzlich die Neuberechnung der Werte
/// sperrt (`exclusive`), nimmt diese zuerst und reiht sich darin hier ein,
/// nie umgekehrt; eine Aktion in der Reihe ruft [run] nicht erneut auf.
class PlanWriteQueue {
  PlanWriteQueue();

  /// Die Reihe der Sitzung [session]: dieselbe Instanz, solange die Sitzung
  /// lebt; eine neue Sitzung (nach dem Öffnen oder Wiederherstellen) hat eine
  /// eigene.
  factory PlanWriteQueue.of(StorageSession session) =>
      _bySession[session] ??= PlanWriteQueue();

  static final Expando<PlanWriteQueue> _bySession = Expando('PlanWriteQueue');

  final Queue<Future<void> Function()> _pending = Queue();
  bool _draining = false;

  /// Führt [action] nach allen vorher eingereihten aus, nie parallel zu ihnen.
  /// Ein Fehler geht an den Aufrufer; die Reihe läuft weiter. [action] läuft
  /// in der Zone ihres Aufrufers; ist die Reihe leer, beginnt sie sofort
  /// (ohne auf eine schon abgeschlossene Aktion zu warten).
  Future<T> run<T>(Future<T> Function() action) {
    final done = Completer<T>();
    final zone = Zone.current;
    _pending.add(() async {
      try {
        done.complete(await zone.run(action));
      } on Object catch (e, s) {
        done.completeError(e, s);
      }
    });
    if (!_draining) _drain();
    return done.future;
  }

  Future<void> _drain() async {
    _draining = true;
    try {
      while (_pending.isNotEmpty) {
        await _pending.removeFirst()();
      }
    } finally {
      _draining = false;
    }
  }
}
