import '../../ports/storage_settings.dart';
import '../fitness/fitness_parameters.dart';
import '../fitness/reserve_zones.dart';
import 'display_settings.dart';

/// Warum Zonengrenzen abgelehnt werden (FR-0061, OQ-0065).
enum ZoneBoundsProblem {
  /// Nicht genau sechs Grenzen (fünf Zonen).
  wrongCount,

  /// Kein ganzer Prozentwert zwischen 0 und 100, oder die Obergrenze von
  /// Zone 5 ist nicht 100.
  outOfRange,

  /// Eine Grenze ist nicht größer als die davor. Eine Lücke oder Überlappung
  /// gibt es nicht: Zone n endet an der Untergrenze von Zone n+1.
  notAscending,
}

class ZoneBoundsException implements Exception {
  const ZoneBoundsException(this.problem, this.index);

  final ZoneBoundsProblem problem;

  /// Index der ersten fehlerhaften Grenze (0 bis 5); bei [wrongCount] 0.
  final int index;

  @override
  String toString() => 'ZoneBoundsException($problem, $index)';
}

/// Zonengrenzen der Herzfrequenzreserve in ganzen Prozent, vom Nutzer
/// einstellbar (FR-0061). Gespeichert wird die Liste der sechs Grenzen
/// (Untergrenze von Zone 1 bis Obergrenze von Zone 5) in
/// [SettingKeys.reserveZoneBounds]. Die Grenzen sind gemeinsame Kanten, damit
/// sind die Zonen lückenlos (OQ-0065). Die Einteilung ist eine Näherung
/// (FR-0064), keine gemessene Schwelle.
abstract final class ReserveZoneSettings {
  /// Standard aus FR-0062 und PAR-Parametersatz, in Prozent.
  static const List<int> defaultPercents = [50, 60, 70, 80, 90, 100];

  /// Obergrenze von Zone 5, fest (FR-0062: darüber gilt Zone 5 mit Hinweis);
  /// sie wirkt nicht auf die Einteilung und ist nicht einstellbar.
  static const int upperPercent = 100;

  /// Prüft [percents]; wirft [ZoneBoundsException]. Die Reihenfolge-Prüfung
  /// läuft über [ReserveZones.validateBounds], derselben Regel wie die
  /// Berechnung.
  static void validate(List<int> percents) {
    if (percents.length != defaultPercents.length) {
      throw const ZoneBoundsException(ZoneBoundsProblem.wrongCount, 0);
    }
    for (var i = 0; i < percents.length; i++) {
      final last = i == percents.length - 1;
      if (percents[i] < 0 ||
          percents[i] > upperPercent ||
          (last && percents[i] != upperPercent)) {
        throw ZoneBoundsException(ZoneBoundsProblem.outOfRange, i);
      }
    }
    try {
      ReserveZones.validateBounds(_params(percents));
    } on ArgumentError {
      var at = 1;
      while (at < percents.length && percents[at] > percents[at - 1]) {
        at++;
      }
      throw ZoneBoundsException(ZoneBoundsProblem.notAscending, at);
    }
  }

  /// Aktueller Parametersatz, nur die Zonengrenzen ersetzt; Version und
  /// übrige Werte bleiben beim Satz.
  static FitnessParameters _params(List<int> percents) =>
      const FitnessParameters.v3().copyWith(
        reserveZoneBounds: [for (final p in percents) p / 100],
      );

  /// Gespeicherte Grenzen; fehlt der Eintrag oder ist er ungültig, gilt der
  /// Standard.
  static Future<List<int>> load(SettingsStore store) async {
    final raw = await store.get(SettingKeys.reserveZoneBounds);
    if (raw == null) return defaultPercents;
    final parsed = raw.split(',').map((s) => int.tryParse(s.trim())).toList();
    if (parsed.contains(null)) return defaultPercents;
    final percents = parsed.cast<int>();
    try {
      validate(percents);
    } on ZoneBoundsException {
      return defaultPercents;
    }
    return percents;
  }

  /// Speichert [percents] nur, wenn sie gültig sind; sonst
  /// [ZoneBoundsException] und der alte Stand bleibt.
  static Future<void> save(
    SettingsStore store,
    List<int> percents, {
    required DateTime at,
  }) async {
    validate(percents);
    await store.set(SettingKeys.reserveZoneBounds, percents.join(','), at: at);
  }

  /// Zurück auf den Standard.
  static Future<void> reset(SettingsStore store, {required DateTime at}) =>
      save(store, defaultPercents, at: at);

  /// Parametersatz mit den gespeicherten Grenzen für neue Berechnungen.
  static Future<FitnessParameters> loadParameters(SettingsStore store) async =>
      _params(await load(store));
}
