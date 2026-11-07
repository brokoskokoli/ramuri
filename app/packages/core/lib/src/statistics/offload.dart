import 'dart:async';
import 'dart:isolate';

/// Führt eine reine Rechnung [job] mit [argument] aus. Die Rechnung darf nichts
/// aus dem Speicher oder der Oberfläche anfassen; Argument und Ergebnis müssen
/// an einen anderen Isolate sendbar sein.
typedef Offload = Future<R> Function<A, R>(R Function(A) job, A argument);

/// Rechnet im aufrufenden Isolate (Tests, kleine Rechnungen).
Future<R> inlineOffload<A, R>(R Function(A) job, A argument) async =>
    job(argument);

/// Rechnet in einem eigenen Isolate, damit die Oberfläche bei langen Läufen
/// nicht einfriert. [job] muss eine Top-Level-Funktion sein.
Future<R> isolateOffload<A, R>(R Function(A) job, A argument) =>
    Isolate.run(() => job(argument));

/// Wie [Offload], aber für eine Rechnung, die selbst asynchron ist (zum
/// Beispiel Argon2id aus `cryptography`, das nur als `Future` vorliegt).
typedef OffloadAsync = Future<R> Function<A, R>(
  FutureOr<R> Function(A) job,
  A argument,
);

/// Rechnet [job] im aufrufenden Isolate (Tests).
Future<R> inlineOffloadAsync<A, R>(
  FutureOr<R> Function(A) job,
  A argument,
) async => job(argument);

/// Rechnet [job] in einem eigenen Isolate und wartet dort auf dessen Ergebnis.
/// [job] muss eine Top-Level-Funktion sein, Argument und Ergebnis sendbar.
Future<R> isolateOffloadAsync<A, R>(FutureOr<R> Function(A) job, A argument) =>
    Isolate.run<R>(() => job(argument));
