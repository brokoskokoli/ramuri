import 'package:core/core.dart';
import 'package:drift/drift.dart' show Value;

import 'app_database.dart' as d;
import 'encrypted_storage.dart';

/// Führt einen Zugriff aus; jeder Fehler verlässt ihn als [StorageException]
/// ohne Inhalte und ohne Ursache (die rohe Ausnahme trägt Statement und
/// Parameter, Falle 4).
Future<T> guarded<T>(Future<T> Function() body) async {
  try {
    return await body();
  } catch (e, st) {
    Error.throwWithStackTrace(translateStorageError(e), st);
  }
}

int usOf(DateTime t) => t.toUtc().microsecondsSinceEpoch;
int? usOfOrNull(DateTime? t) => t == null ? null : usOf(t);
DateTime timeOf(int us) => DateTime.fromMicrosecondsSinceEpoch(us, isUtc: true);
DateTime? timeOfOrNull(int? us) => us == null ? null : timeOf(us);

double secondsOf(Duration x) =>
    x.inMicroseconds / Duration.microsecondsPerSecond;
Duration durationOf(double s) =>
    Duration(microseconds: (s * Duration.microsecondsPerSecond).round());
double? secondsOfOrNull(Duration? x) => x == null ? null : secondsOf(x);
Duration? durationOfOrNull(double? s) => s == null ? null : durationOf(s);

/// `heartRateLoss` -> `heart_rate_loss`.
String snake(String camel) =>
    camel.replaceAllMapped(RegExp('[A-Z]'), (m) => '_${m[0]!.toLowerCase()}');

T enumOf<T extends Enum>(
  List<T> values,
  String stored,
  String Function(T) nameOf,
) => values.firstWhere(
  (v) => nameOf(v) == stored,
  orElse: () => throw const StorageException(StorageFailure.failed),
);

Value<T> some<T>(T v) => Value(v);

/// Wirft `notFound`, wenn der Lauf fehlt.
Future<void> requireRun(d.AppDatabase db, int runId) async {
  final row =
      await (db.selectOnly(db.runs)
            ..addColumns([db.runs.id])
            ..where(db.runs.id.equals(runId)))
          .getSingleOrNull();
  if (row == null) throw const StorageException(StorageFailure.notFound);
}
