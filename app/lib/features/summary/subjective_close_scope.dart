import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Offene Texte eines Abschnitts „Angaben zum Lauf“ (FR-0038), die vor dem
/// Schließen der Seite gespeichert werden müssen.
abstract interface class SubjectivePendingSave {
  /// Geänderte Texte, die noch nicht gespeichert sind, oder ein Speichern läuft.
  /// Ein gescheitertes Speichern zählt nicht mehr als offen (die Fehlerzeile
  /// zeigt es); neues Tippen danach schon.
  bool get hasPendingSave;

  /// Speichert die geänderten Texte und wartet auf alle laufenden Speicher-
  /// vorgänge. `true`, wenn alles gespeichert ist; sonst zeigt der Abschnitt
  /// seine Fehlerzeile, und der Text bleibt im Feld.
  Future<bool> flush();
}

/// Wächter vor dem Schließen einer Seite mit dem Abschnitt „Angaben zum Lauf“:
/// Schließen (Knopf oder Zurück) wartet auf das Speichern geänderter Texte.
/// Scheitert es, bleibt die Seite offen und die Fehlerzeile sichtbar; die
/// gescheiterten Texte gelten dann nicht mehr als offen, das nächste Schließen
/// geht ohne erneutes Warten durch (der Fehler war sichtbar). Wird danach neu
/// getippt, wartet das Schließen wieder.
class SubjectiveCloseGuard extends ChangeNotifier {
  SubjectivePendingSave? _section;
  final ValueNotifier<bool> _busy = ValueNotifier(false);

  /// Läuft gerade das Speichern vor dem Schließen (Ladeanzeige am Knopf).
  ValueListenable<bool> get busy => _busy;

  /// Ob das Schließen erst auf das Speichern warten muss.
  bool get blocksClose => _section?.hasPendingSave ?? false;

  bool _disposed = false;

  /// Meldet den Abschnitt an; [section] ersetzt einen früheren. Ohne
  /// Benachrichtigung (der Aufruf kommt aus dem Aufbau): Ein frisch
  /// angemeldeter Abschnitt hat noch nichts Offenes.
  void attach(SubjectivePendingSave section) => _section = section;

  /// Meldet den Abschnitt ab. Ein danach noch gesperrtes Zurück geht über
  /// [prepareClose] sofort durch.
  void detach(SubjectivePendingSave section) {
    if (identical(_section, section)) _section = null;
  }

  /// Der Zustand „offen“ des Abschnitts hat sich geändert.
  void changed() {
    if (!_disposed) notifyListeners();
  }

  /// Speichert vor dem Schließen; `true`, wenn die Seite schließen darf.
  Future<bool> prepareClose() async {
    final section = _section;
    if (!blocksClose || section == null) return true;
    _busy.value = true;
    try {
      return await section.flush();
    } finally {
      if (!_disposed) {
        _busy.value = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _busy.dispose();
    super.dispose();
  }
}

/// Stellt einen [SubjectiveCloseGuard] für die Seite bereit und hält die
/// Zurück-Taste an, solange geänderte Texte noch nicht gespeichert sind.
/// Schließen per Knopf geht über [SubjectiveCloseScope.close].
class SubjectiveCloseScope extends StatefulWidget {
  const SubjectiveCloseScope({super.key, required this.child});

  final Widget child;

  /// Wächter der Seite, falls vorhanden (ohne Abhängigkeit).
  static SubjectiveCloseGuard? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_SubjectiveCloseInherited>()?.guard;

  /// Schließt die Seite von [context] mit [result], nachdem geänderte Texte
  /// gespeichert sind. Scheitert das Speichern, bleibt sie offen. Ohne
  /// Wächter schließt sie sofort.
  static Future<void> close<T>(BuildContext context, [T? result]) async {
    final guard = maybeOf(context);
    final navigator = Navigator.of(context);
    if (guard != null) {
      if (guard.busy.value) return;
      if (!await guard.prepareClose()) return;
    }
    if (navigator.mounted) navigator.pop(result);
  }

  @override
  State<SubjectiveCloseScope> createState() => _SubjectiveCloseScopeState();
}

class _SubjectiveCloseScopeState extends State<SubjectiveCloseScope> {
  final _guard = SubjectiveCloseGuard();

  @override
  void dispose() {
    _guard.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _SubjectiveCloseInherited(
      guard: _guard,
      child: ListenableBuilder(
        listenable: _guard,
        builder: (context, child) => PopScope<Object?>(
          canPop: !_guard.blocksClose,
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) return;
            SubjectiveCloseScope.close(context, result);
          },
          child: child!,
        ),
        child: widget.child,
      ),
    );
  }
}

class _SubjectiveCloseInherited extends InheritedWidget {
  const _SubjectiveCloseInherited({required this.guard, required super.child});

  final SubjectiveCloseGuard guard;

  @override
  bool updateShouldNotify(_SubjectiveCloseInherited old) => guard != old.guard;
}
