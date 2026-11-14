import '../../ports/clock.dart';
import '../../ports/health_import.dart';
import '../../ports/storage_health.dart';
import '../../ports/storage_settings.dart';
import '../consent/consent_service.dart';
import '../consent/consent_sources.dart';
import 'health_parameters.dart';

/// Mindestabstand zwischen zwei Importen (WP32 Punkt 3, „höchstens einmal je
/// 15 min“). „Jetzt abrufen“ umgeht ihn.
const Duration healthImportMinInterval = Duration(minutes: 15);

/// Zeitraum des Lesens: ohne `READ_HEALTH_DATA_HISTORY` liefert Health Connect
/// höchstens 30 Tage vor der ersten Freigabe (WP32 Vorentscheidung Zeitraum).
const Duration healthImportWindow = Duration(days: 30);

/// Ab dem zweiten Import beginnt das Fenster so viel vor dem letzten
/// erfolgreichen Lesen der Art, damit spät synchronisierte Einträge ankommen
/// (gleiche ID wird überschrieben, nie doppelt gespeichert).
const Duration healthImportOverlap = Duration(days: 2);

/// Pulsverlauf einer Einheit: Health Connect erlaubt Fenster bis 24 h.
const Duration healthHeartRateMaxWindow = Duration(hours: 24);

/// Höchstzahl Seiten je Art und Lauf (Schutz vor einem Token, der sich wiederholt).
const int healthImportMaxPages = 200;

enum HealthImportTrigger {
  /// App-Start.
  appStart,

  /// „Heute“ wurde geöffnet.
  todayOpened,

  /// „Jetzt abrufen“: umgeht die Sperre.
  manual,
}

enum HealthKindStatus {
  /// Keine eigene Einwilligung: Health Connect wurde für diese Art nicht berührt.
  notConsented,

  /// Eigene Einwilligung ja, Recht in Health Connect fehlt: nichts gelesen,
  /// „Löschfrage offen“ gemerkt (SEC-0007).
  permissionMissing,

  /// Gelesen und gespeichert.
  imported,

  /// Lesen oder Speichern ist gescheitert (kein Inhalt im Fehler).
  failed,

  /// Die Einwilligung wurde während des Lesens widerrufen: nichts gespeichert.
  revokedWhileReading,
}

class HealthKindResult {
  const HealthKindResult(
    this.status, {
    this.stored = 0,
    this.rejected = 0,
    this.error,
  });

  final HealthKindStatus status;

  /// Zahl der gespeicherten (neuen oder überschriebenen) Sätze.
  final int stored;

  /// Zahl der verworfenen Sätze (Wert außerhalb PAR-162/PAR-017, ungültig).
  final int rejected;
  final HealthReadError? error;
}

enum HealthImportStatus {
  /// Die Sperre von 15 min gilt, nichts geschah.
  throttled,

  /// Health Connect fehlt oder ist zu alt: nichts gelesen, nichts geändert.
  unavailable,

  /// Ein Import läuft schon; dieser Aufruf wartet nicht darauf.
  alreadyRunning,

  /// Durchgelaufen (je Art siehe [HealthImportResult.kinds]).
  done,
}

class HealthImportResult {
  const HealthImportResult(this.status, [this.kinds = const {}]);
  final HealthImportStatus status;
  final Map<HealthDataKind, HealthKindResult> kinds;
}

/// Import aus Health Connect (WP32 Teil C1, ohne Oberfläche). Nur im
/// Vordergrund: Die App ruft [run] bei App-Start, beim Öffnen von „Heute“ und
/// bei „Jetzt abrufen“. Je Datenart wird nur gelesen, wenn die eigene
/// Einwilligung erteilt ist UND Health Connect das Recht erteilt hat (SEC-0001,
/// SEC-0002); beides wird vor jedem Lesen frisch geprüft, ebenso der Zustand
/// von Health Connect. Fehlt das Recht trotz Einwilligung, wird nichts gelesen
/// und für diese Art „Löschfrage offen“ gemerkt (SEC-0007). Kein Abgleich von
/// Löschungen. Keine Werte in Fehlern oder Logs.
///
/// Die Sperre gilt im Prozess nach der monotonen Uhr und über Neustarts nach dem
/// Zeitpunkt des letzten Imports (Wanduhr), den [settings] hält
/// ([lastImportKey], technischer Merker, nicht im Archiv). Ohne [settings] oder
/// bei Lese-/Schreibfehlern gilt nur die Sperre im Prozess.
class HealthImportService {
  HealthImportService({
    required this.port,
    required this.store,
    required this.consents,
    required this.clock,
    this.params = const HealthParameters.v4(),
    this.minInterval = healthImportMinInterval,
    this.window = healthImportWindow,
    this.overlap = healthImportOverlap,
    this.settings,
  });

  /// Einstellung: Zeitpunkt des letzten Imports (Millisekunden seit 1970, UTC).
  static const String lastImportKey = 'health.last_import_ms';

  final HealthConnectPort port;
  final HealthImportStore store;
  final ConsentService consents;
  final Clock clock;
  final HealthParameters params;
  final Duration minInterval;
  final Duration window;
  final Duration overlap;
  final SettingsStore? settings;

  Duration? _lastStart;
  bool _running = false;
  final Map<HealthDataKind, DateTime> _lastRead = {};

  Future<HealthImportResult> run(HealthImportTrigger trigger) async {
    if (_running) {
      return const HealthImportResult(HealthImportStatus.alreadyRunning);
    }
    _running = true;
    try {
      final mono = clock.monotonic();
      if (trigger != HealthImportTrigger.manual &&
          ((_lastStart != null && mono - _lastStart! < minInterval) ||
              await _persistedThrottle())) {
        return const HealthImportResult(HealthImportStatus.throttled);
      }
      _lastStart = mono;
      final result = await _import();
      // Nur wenn wirklich gelesen wurde (eine Art eingewilligt und mit Recht):
      // sonst bleibt der Speicher unberührt.
      if (result.kinds.values.any(
        (k) =>
            k.status != HealthKindStatus.notConsented &&
            k.status != HealthKindStatus.permissionMissing,
      )) {
        await _persistStart();
      }
      return result;
    } finally {
      _running = false;
    }
  }

  /// Letzter Import (aus einem früheren Prozess) liegt weniger als
  /// [minInterval] zurück. Eine Zeit in der Zukunft (Uhr zurückgestellt) oder
  /// ein Lesefehler sperren nicht.
  Future<bool> _persistedThrottle() async {
    final store = settings;
    if (store == null) return false;
    try {
      final ms = int.tryParse(await store.get(lastImportKey) ?? '');
      if (ms == null) return false;
      final ago = clock.now().difference(
        DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true),
      );
      return !ago.isNegative && ago < minInterval;
    } catch (_) {
      return false;
    }
  }

  Future<void> _persistStart() async {
    final store = settings;
    if (store == null) return;
    try {
      final now = clock.now();
      await store.set(lastImportKey, '${now.millisecondsSinceEpoch}', at: now);
    } catch (_) {}
  }

  /// Merkt „Löschfrage offen“. Scheitert das Schreiben, bleibt der Lauf heil;
  /// der nächste Lauf merkt es erneut, solange das Recht fehlt.
  Future<void> _flagDeleteQuestion(String key) async {
    try {
      await consents.openDeleteQuestion(key);
    } catch (_) {}
  }

  Future<HealthImportResult> _import() async {
    // Vor jedem Lesen: Zustand von Health Connect und erteilte Rechte.
    HealthSdkStatus sdk;
    try {
      sdk = await port.sdkStatus();
    } catch (_) {
      return const HealthImportResult(HealthImportStatus.unavailable);
    }
    if (sdk != HealthSdkStatus.available) {
      return const HealthImportResult(HealthImportStatus.unavailable);
    }
    Set<HealthDataKind> rights;
    try {
      rights = await port.grantedKinds();
    } catch (_) {
      return const HealthImportResult(HealthImportStatus.unavailable);
    }

    final results = <HealthDataKind, HealthKindResult>{};
    // Einheiten zuerst, damit der Pulsverlauf sie findet.
    const order = [
      HealthDataKind.sleep,
      HealthDataKind.hrvRmssd,
      HealthDataKind.restingHeartRate,
      HealthDataKind.vo2Max,
      HealthDataKind.exercise,
      HealthDataKind.heartRate,
    ];
    var exercises = <HealthRecord>[];
    for (final kind in order) {
      final key = healthSourceKey(kind);
      if (!await consents.isGranted(key)) {
        results[kind] = const HealthKindResult(HealthKindStatus.notConsented);
        continue;
      }
      if (!rights.contains(kind)) {
        await _flagDeleteQuestion(key);
        results[kind] = const HealthKindResult(
          HealthKindStatus.permissionMissing,
        );
        continue;
      }
      try {
        final r = await _readKind(kind, exercises);
        results[kind] = r.$1;
        if (kind == HealthDataKind.exercise) exercises = r.$2;
      } on HealthReadException catch (e) {
        if (e.error == HealthReadError.permissionMissing) {
          // Recht zwischen Prüfung und Lesen entzogen.
          await _flagDeleteQuestion(key);
          results[kind] = const HealthKindResult(
            HealthKindStatus.permissionMissing,
          );
        } else {
          results[kind] = HealthKindResult(
            HealthKindStatus.failed,
            error: e.error,
          );
          if (e.error == HealthReadError.rateLimited) {
            // Die übrigen Arten gar nicht erst versuchen.
            for (final k in order.skip(order.indexOf(kind) + 1)) {
              results.putIfAbsent(
                k,
                () => const HealthKindResult(
                  HealthKindStatus.failed,
                  error: HealthReadError.rateLimited,
                ),
              );
            }
            break;
          }
        }
      } catch (_) {
        results[kind] = const HealthKindResult(
          HealthKindStatus.failed,
          error: HealthReadError.other,
        );
      }
    }
    return HealthImportResult(HealthImportStatus.done, results);
  }

  /// Liest eine Art, prüft die Werte und speichert. Gibt das Ergebnis und die
  /// gespeicherten Einheiten (für den Pulsverlauf) zurück.
  Future<(HealthKindResult, List<HealthRecord>)> _readKind(
    HealthDataKind kind,
    List<HealthRecord> exercises,
  ) async {
    final now = clock.now();
    final key = healthSourceKey(kind);
    final last = _lastRead[kind];
    var from = now.subtract(window);
    if (last != null) {
      final f = last.subtract(overlap);
      if (f.isAfter(from)) from = f;
    }

    if (kind == HealthDataKind.heartRate) {
      return (await _readHeartRate(exercises, key), const <HealthRecord>[]);
    }

    final read = await _readAll(kind, from, now);
    final valid = <HealthRecord>[];
    var rejected = 0;
    for (final r in read) {
      if (_isValid(r, kind)) {
        valid.add(r);
      } else {
        rejected++;
      }
    }
    // Widerruf während des Lesens: nichts speichern (wie ConsentGuard).
    if (!await consents.isGranted(key)) {
      return (
        const HealthKindResult(HealthKindStatus.revokedWhileReading),
        const <HealthRecord>[],
      );
    }
    switch (kind) {
      case HealthDataKind.sleep:
        await store.upsertSleep(valid);
      case HealthDataKind.exercise:
        await store.upsertExercises(valid);
      case HealthDataKind.hrvRmssd:
      case HealthDataKind.restingHeartRate:
      case HealthDataKind.vo2Max:
        await store.upsertValues(valid);
      case HealthDataKind.heartRate:
        break;
    }
    _lastRead[kind] = now;
    return (
      HealthKindResult(
        HealthKindStatus.imported,
        stored: valid.length,
        rejected: rejected,
      ),
      kind == HealthDataKind.exercise ? valid : const <HealthRecord>[],
    );
  }

  Future<List<HealthRecord>> _readAll(
    HealthDataKind kind,
    DateTime from,
    DateTime to,
  ) async {
    final out = <HealthRecord>[];
    String? token;
    for (var i = 0; i < healthImportMaxPages; i++) {
      final page = await port.readPage(
        kind: kind,
        from: from,
        to: to,
        pageToken: token,
      );
      out.addAll(page.records);
      token = page.nextToken;
      if (token == null) break;
    }
    return out;
  }

  /// Pulsverlauf je Einheit dieses Laufs (Fenster höchstens 24 h).
  Future<HealthKindResult> _readHeartRate(
    List<HealthRecord> exercises,
    String key,
  ) async {
    var stored = 0;
    var rejected = 0;
    for (final ex in exercises) {
      var end = ex.end;
      if (end.difference(ex.start) > healthHeartRateMaxWindow) {
        end = ex.start.add(healthHeartRateMaxWindow);
      }
      final records = await _readAll(HealthDataKind.heartRate, ex.start, end);
      final samples = <HealthHeartRateSample>[];
      for (final r in records) {
        for (final s in r.samples) {
          if (s.beatsPerMinute > 0 &&
              !s.time.isBefore(ex.start) &&
              !s.time.isAfter(end)) {
            samples.add(s);
          } else {
            rejected++;
          }
        }
      }
      if (!await consents.isGranted(key)) {
        return const HealthKindResult(HealthKindStatus.revokedWhileReading);
      }
      samples.sort((a, b) => a.time.compareTo(b.time));
      if (await store.replaceExerciseHeartRate(ex.id, samples)) {
        stored += samples.length;
      }
    }
    return HealthKindResult(
      HealthKindStatus.imported,
      stored: stored,
      rejected: rejected,
    );
  }

  bool _isValid(HealthRecord r, HealthDataKind kind) {
    if (r.id.isEmpty || r.origin.isEmpty || r.end.isBefore(r.start)) {
      return false;
    }
    switch (kind) {
      case HealthDataKind.hrvRmssd:
        return _inRange(r.value, params.rmssdMinMs, params.rmssdMaxMs);
      case HealthDataKind.restingHeartRate:
        return _inRange(
          r.value,
          params.restingHeartRateMinBpm,
          params.restingHeartRateMaxBpm,
        );
      case HealthDataKind.vo2Max:
        // Keine Grenze in den Parametern: nur endlich und positiv.
        final v = r.value;
        return v != null && v.isFinite && v > 0;
      case HealthDataKind.sleep:
      case HealthDataKind.exercise:
      case HealthDataKind.heartRate:
        return true;
    }
  }

  bool _inRange(double? v, double min, double max) =>
      v != null && v.isFinite && v >= min && v <= max;
}
