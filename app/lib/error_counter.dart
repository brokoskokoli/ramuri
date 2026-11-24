import 'dart:async';
import 'dart:convert';

import 'package:core/core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Ein gezählter Fehler: nur Fehlertyp (`runtimeType`) und Ortskennung (erste
/// Datei der App im Stack, ohne Zeile), Anzahl und der lokale Tag des ersten
/// und letzten Auftretens. Nie Nachricht, `toString` des Fehlers oder Stack
/// (SEC-0009).
@immutable
class ErrorCount {
  const ErrorCount({
    required this.type,
    required this.place,
    required this.count,
    this.firstDay,
    this.lastDay,
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

  /// Lokaler Kalendertag (`JJJJ-MM-TT`) des ersten und letzten Auftretens;
  /// `null`, solange der Eintrag noch nicht gespeichert ist, und bei Einträgen
  /// aus einer Fassung ohne Tage.
  final String? firstDay;
  final String? lastDay;

  bool sameAs(ErrorCount other) => type == other.type && place == other.place;

  /// Derselbe Eintrag zusammen mit [other] (gleicher Typ und Ort): Anzahlen
  /// addiert, frühester erster und spätester letzter Tag.
  ErrorCount merge(ErrorCount other) => ErrorCount(
    type: type,
    place: place,
    count: count + other.count,
    firstDay: _earlier(firstDay, other.firstDay),
    lastDay: _later(lastDay, other.lastDay),
  );

  /// Mit [day] als Tag des Auftretens, wo noch keiner steht.
  ErrorCount on(String day) => ErrorCount(
    type: type,
    place: place,
    count: count,
    firstDay: firstDay ?? day,
    lastDay: lastDay ?? day,
  );

  Map<String, Object> toJson() => {
    'type': type,
    'place': place,
    'count': count,
    'first': ?firstDay,
    'last': ?lastDay,
  };
}

String? _earlier(String? a, String? b) =>
    a == null ? b : (b == null || a.compareTo(b) <= 0 ? a : b);

String? _later(String? a, String? b) =>
    a == null ? b : (b == null || a.compareTo(b) >= 0 ? a : b);

/// Lokaler Kalendertag (`JJJJ-MM-TT`) von [clock] jetzt.
String _today(Clock clock) {
  final now = clock.now();
  return isoDay(now.toUtc().add(clock.utcOffsetAt(now)));
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
  final merged = i < 0 ? add : entries.removeAt(i).merge(add);
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
          firstDay: e['first'] as String?,
          lastDay: e['last'] as String?,
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
/// Kein Netz und keine Ausgabe; angezeigt und als Diagnose-Datei geteilt
/// werden sie nur in den Entwicklereinstellungen (FR-0223).
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

  /// Aktueller Stand: gespeicherte Einträge samt noch nicht gespeicherten,
  /// in der Reihenfolge des letzten Auftretens. Wirft, wenn der gespeicherte
  /// Stand nicht lesbar ist.
  Future<List<ErrorCount>> read() {
    final done = _tail.then((_) async {
      final store = _store;
      final entries = store == null
          ? <ErrorCount>[]
          : decodeErrorCounts(await store.get(SettingKeys.errorCounts));
      for (final e in _pending) {
        mergeErrorCount(entries, e, limit);
      }
      return entries;
    });
    _tail = done.then((_) {}, onError: (Object _) {});
    return done;
  }

  /// „Zähler zurücksetzen“: leert gespeicherte und noch nicht gespeicherte
  /// Zähler. Wirft, wenn der gespeicherte Stand nicht geleert werden konnte.
  Future<void> reset() {
    final done = _tail.then((_) async {
      _pending.clear();
      final store = _store;
      final clock = _clock;
      if (store == null || clock == null) return;
      await store.set(
        SettingKeys.errorCounts,
        encodeErrorCounts(const []),
        at: clock.now(),
      );
    });
    _tail = done.then((_) {}, onError: (Object _) {});
    return done;
  }

  /// Nach „Alles löschen“ (SEC-0004): Die Datenbank samt gespeicherten
  /// Zählern ist leer; noch nicht gespeicherte Zähler werden verworfen, damit
  /// sie nicht wieder hineinkommen.
  void dropPending() => _pending.clear();

  void _schedule() {
    _tail = _tail.then((_) => _flush());
  }

  Future<void> _flush() async {
    final store = _store;
    final clock = _clock;
    if (store == null || clock == null || _pending.isEmpty) return;
    final day = _today(clock);
    final batch = [for (final e in _pending) e.on(day)];
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

/// Macht den [ErrorCounter] der App den Seiten zugänglich (Entwicklereinstellungen,
/// „Alles löschen“). Ohne Scope zeigen die Entwicklereinstellungen keine Zähler.
class ErrorCounterScope extends InheritedWidget {
  const ErrorCounterScope({
    super.key,
    required this.errors,
    required super.child,
  });

  final ErrorCounter errors;

  static ErrorCounter? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ErrorCounterScope>()?.errors;

  @override
  bool updateShouldNotify(ErrorCounterScope old) => errors != old.errors;
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
