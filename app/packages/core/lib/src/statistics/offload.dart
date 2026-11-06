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
