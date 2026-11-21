import 'dart:async';
import 'dart:convert';

import 'package:core/core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Ein gezählter Fehler: nur Fehlertyp (`runtimeType`) und Ortskennung (erste
/// Datei der App im Stack, ohne Zeile). Nie Nachricht, `toString` des Fehlers
/// oder Stack (SEC-0009).
@immutable
class ErrorCount {
  const ErrorCount({
    required this.type,
    required this.place,
    required this.count,
  });

  /// Kennung aus einem Fehler und seinem Stack; liest vom Fehler nur den Typ.
  factory ErrorCount.of(Object error, StackTrace? stack) => ErrorCount(
    type: error.runtimeType.toString(),
    place: errorPlace(stack),
    count: 1,
  );

  final String type;
  final String place;
  final int count;

  bool sameAs(ErrorCount other) => type == other.type && place == other.place;

  ErrorCount plus(int n) =>
      ErrorCount(type: type, place: place, count: count + n);

  Map<String, Object> toJson() => {
    'type': type,
    'place': place,
    'count': count,
  };
}

/// Ortskennung, wenn der Stack keine Datei der App nennt (auch ohne Stack oder
/// bei verschleierten Symbolen).
const String unknownErrorPlace = 'unknown';

/// Bibliotheken der App: die App selbst und ihre Pakete `core` und `adapters`.
final RegExp _appFile = RegExp(
  r'(package:(?:running_app|core|adapters)/[^\s:()]+\.dart)',
);

/// Erste Datei der App im [stack] als `package:…/….dart`, ohne Zeile und
/// Spalte; sonst [unknownErrorPlace]. Liest nur den Dateipfad, keine
/// Argumente oder Werte.
String errorPlace(StackTrace? stack) {
  if (stack == null) return unknownErrorPlace;
  for (final line in stack.toString().split('\n')) {
    final m = _appFile.firstMatch(line);
    if (m != null) return m.group(1)!;
  }
  return unknownErrorPlace;
}

/// Zählt [add] in [entries] ein: gleicher Typ und Ort erhöht den Zähler, und
/// der Eintrag rückt ans Ende (zuletzt gesehen). Mehr als [limit] Einträge:
/// die am längsten nicht mehr gesehenen fallen vorne weg.
void mergeErrorCount(List<ErrorCount> entries, ErrorCount add, int limit) {
  final i = entries.indexWhere(add.sameAs);
  final merged = i < 0 ? add : entries.removeAt(i).plus(add.count);
  entries.add(merged);
  while (entries.length > limit) {
    entries.removeAt(0);
  }
}

/// Liest den gespeicherten Stand; ein unlesbarer Eintrag gilt als leer.
List<ErrorCount> decodeErrorCounts(String? text) {
  if (text == null || text.isEmpty) return [];
  try {
    final list = jsonDecode(text) as List<Object?>;
    return [
      for (final e in list.cast<Map<String, Object?>>())
        ErrorCount(
          type: e['type']! as String,
          place: e['place']! as String,
          count: e['count']! as int,
        ),
    ];
  } on Object {
    return [];
  }
}

String encodeErrorCounts(List<ErrorCount> entries) =>
    jsonEncode([for (final e in entries) e.toJson()]);

/// Zähler unbehandelter und still abgefangener Fehler je (Typ, Ort), lokal in
/// den Einstellungen der verschlüsselten Datenbank (Schlüssel
/// [SettingKeys.errorCounts], nicht im Archiv). Höchstens [limit] Einträge.
/// Kein Netz, keine Anzeige, keine Ausgabe.
///
/// Vor dem Öffnen der Datenbank (oder wenn Schreiben scheitert) bleiben die
/// Zähler im Speicher und gehen mit dem nächsten Schreiben in die Datenbank.
/// Die Datenbank ist der Stand: „Alles löschen“ leert auch die Zähler.
class ErrorCounter {
  ErrorCounter({this.limit = maxEntries});

  /// Obergrenze der Einträge (Richtwert).
  static const int maxEntries = 50;

  final int limit;

  SettingsStore? _store;
  Clock? _clock;

  /// Noch nicht gespeicherte Zähler.
  final List<ErrorCount> _pending = [];

  Future<void> _tail = Future<void>.value();

  /// Zählt einen Fehler; wirft nie.
  void record(Object error, StackTrace? stack) {
    try {
      mergeErrorCount(_pending, ErrorCount.of(error, stack), limit);
      _schedule();
    } on Object {
      // Zählen darf die Fehlerbehandlung nicht stören.
    }
  }

  /// Ab jetzt in [store] speichern (Sitzung geöffnet); schreibt Ausstehendes.
  void attach(SettingsStore store, Clock clock) {
    if (identical(_store, store)) return;
    _store = store;
    _clock = clock;
    _schedule();
  }

  /// Keine Sitzung mehr: Zähler bleiben bis zur nächsten im Speicher.
  void detach() {
    _store = null;
    _clock = null;
  }

  /// Fertig, wenn alle bisher angestoßenen Schreibvorgänge gelaufen sind.
  Future<void> get idle => _tail;

  void _schedule() {
    _tail = _tail.then((_) => _flush());
  }

  Future<void> _flush() async {
    final store = _store;
    final clock = _clock;
    if (store == null || clock == null || _pending.isEmpty) return;
    final batch = List.of(_pending);
    _pending.clear();
    try {
      final entries = decodeErrorCounts(
        await store.get(SettingKeys.errorCounts),
      );
      for (final e in batch) {
        mergeErrorCount(entries, e, limit);
      }
      await store.set(
        SettingKeys.errorCounts,
        encodeErrorCounts(entries),
        at: clock.now(),
      );
    } on Object {
      // Nicht speicherbar: im Speicher behalten (der eigene Fehler wird nicht
      // gezählt, sonst entstünde eine Schleife).
      final later = List.of(_pending);
      _pending
        ..clear()
        ..addAll(batch);
      for (final e in later) {
        mergeErrorCount(_pending, e, limit);
      }
    }
  }
}

/// Setzt die globalen Handler für Flutter- und Plattformfehler. Sie zählen nur
/// Typ und Ort ([ErrorCounter]). Mit [debugOutput] (nur Debug-Build) geben
/// zusätzlich die Standard-Handler aus; sonst gibt es keine Ausgabe.
void installErrorHandlers(ErrorCounter errors, {required bool debugOutput}) {
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    errors.record(details.exception, details.stack);
    if (debugOutput) previous?.call(details);
  };
  // `true`: behandelt, die Engine gibt nichts aus; im Debug-Build `false`,
  // dann gibt die Engine den Fehler wie gewohnt aus.
  PlatformDispatcher.instance.onError = (error, stack) {
    errors.record(error, stack);
    return !debugOutput;
  };
}

/// Startet [body] (das `runApp`) in einer Zone, deren unbehandelte
/// asynchrone Fehler gezählt werden, und setzt vorher die Handler aus
/// [installErrorHandlers]. Mit [debugOutput] (nur Debug-Build) gibt der
/// Standard-Weg den Fehler zusätzlich aus.
void runCountingErrors(
  ErrorCounter errors,
  void Function() body, {
  bool debugOutput = kDebugMode,
}) {
  runZonedGuarded(
    () {
      WidgetsFlutterBinding.ensureInitialized();
      installErrorHandlers(errors, debugOutput: debugOutput);
      body();
    },
    (error, stack) {
      errors.record(error, stack);
      if (debugOutput) {
        FlutterError.presentError(
          FlutterErrorDetails(exception: error, stack: stack),
        );
      }
    },
  );
}
