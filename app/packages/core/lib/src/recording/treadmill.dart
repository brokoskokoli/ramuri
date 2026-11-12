/// Laufbandmodus: Bereiche der Eingaben (PAR-209, PAR-210, K57) und die
/// gespeicherte Einstellung (FR-0196). Reine Werte, ohne Flutter.
library;

/// Art des Laufs (Spalte `runs.mode`, Archiv Abschnitt 1). `gps` ist die
/// Vorgabe und der Wert aller Läufe vor Schema 10.
enum RunMode {
  gps,
  treadmill;

  /// Wert in Datenbank und Archiv.
  String get wire => name;

  /// `null` bei unbekanntem Text.
  static RunMode? fromWire(String? s) {
    for (final m in values) {
      if (m.wire == s) return m;
    }
    return null;
  }
}

/// PAR-209: Bandgeschwindigkeit 1 bis 25 km/h in Schritten von 0,1 km/h.
const double treadmillSpeedMinKmh = 1;
const double treadmillSpeedMaxKmh = 25;
const double treadmillSpeedStepKmh = 0.1;

/// PAR-210: Steigung 0 bis 15 % in Schritten von 0,5 % (keine negative).
const double treadmillInclineMinPercent = 0;
const double treadmillInclineMaxPercent = 15;
const double treadmillInclineStepPercent = 0.5;

/// Eine Einstellung des Bands, die der Nutzer gesetzt hat (nur anhängen).
/// Sie gilt ab [offset] bis zur nächsten Einstellung des Laufs. Die Werte sind
/// vom Nutzer eingestellt, nicht gemessen.
class BeltSetting {
  const BeltSetting({
    required this.offset,
    required this.speedMetersPerSecond,
    this.inclinePercent,
  });

  /// Zeit ab Laufbeginn (`runs.started_at`), nicht negativ.
  final Duration offset;

  /// Geschwindigkeit in m/s; 0 = Stillstand (K57). Die Grenzen der Eingabe
  /// (PAR-209) prüft die Oberfläche; der Speicher lässt jeden endlichen Wert
  /// ab 0 zu, damit ein Archiv mit anderen Grenzen lesbar bleibt.
  final double speedMetersPerSecond;

  /// Steigung in %, `null` = nicht angegeben (nie 0 statt unbekannt).
  final double? inclinePercent;

  /// [speedMetersPerSecond] in km/h.
  double get speedKmh => speedMetersPerSecond * 3.6;

  @override
  bool operator ==(Object other) =>
      other is BeltSetting &&
      other.offset == offset &&
      other.speedMetersPerSecond == speedMetersPerSecond &&
      other.inclinePercent == inclinePercent;

  @override
  int get hashCode => Object.hash(offset, speedMetersPerSecond, inclinePercent);
}

/// Gespeicherte Einstellung samt Id.
class StoredBeltSetting {
  const StoredBeltSetting(this.id, this.value);

  final int id;
  final BeltSetting value;
}

/// Ob die Werte im Speicher zulässig sind (endlich, Geschwindigkeit und
/// Steigung nicht negativ, Zeit nicht negativ). Fake und Adapter nutzen sie.
bool isStorableBeltSetting(BeltSetting s) {
  final v = s.speedMetersPerSecond, g = s.inclinePercent;
  return !s.offset.isNegative &&
      v.isFinite &&
      v >= 0 &&
      (g == null || (g.isFinite && g >= 0));
}
