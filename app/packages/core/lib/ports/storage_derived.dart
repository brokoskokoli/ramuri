import '../src/preprocessing/measurement.dart';
import '../src/preprocessing/section_quality.dart';
import 'storage_raw.dart';

/// Kennzahlen eines Laufs aus der Vorverarbeitung; `null` = nicht verfügbar.
class PreprocessingSummary {
  const PreprocessingSummary({
    required this.method,
    required this.methodVersion,
    required this.parameterVersion,
    required this.computedAt,
    this.totalTime,
    this.movingTime,
    this.distanceMeters,
    this.bridgedDistanceMeters,
    this.averageBpm,
    this.maxBpm,
    this.medianBpm,
  });

  final String method;
  final int methodVersion;
  final int parameterVersion;
  final DateTime computedAt;
  final Duration? totalTime;
  final Duration? movingTime;
  final double? distanceMeters;
  final double? bridgedDistanceMeters;
  final double? averageBpm;
  final int? maxBpm;
  final double? medianBpm;
}

/// Ergebnis des Filters je Rohwert; [rawId] ist die Id der Rohzeile
/// ([StoredRaw.id]) im Kanal.
class PreprocessedSample {
  const PreprocessedSample({
    required this.channel,
    required this.rawId,
    required this.time,
    required this.state,
    this.discardReason,
  });

  final RawChannel channel;
  final int rawId;
  final DateTime time;
  final MeasurementState state;
  final DiscardReason? discardReason;
}

enum PreprocessedSpanKind { moving, settling, positionGap, heartRateGap }

/// Abgeleitete Zeitspanne; [end] `null` = offen.
class PreprocessedSpan {
  const PreprocessedSpan({required this.kind, required this.start, this.end});

  final PreprocessedSpanKind kind;
  final DateTime start;
  final DateTime? end;
}

/// Gesamtes Ergebnis der Vorverarbeitung eines Laufs.
class StoredPreprocessing {
  const StoredPreprocessing({
    required this.summary,
    this.samples = const [],
    this.spans = const [],
  });

  final PreprocessingSummary summary;
  final List<PreprocessedSample> samples;
  final List<PreprocessedSpan> spans;
}

/// Vorverarbeitung (abgeleitet, jederzeit neu berechenbar).
abstract interface class PreprocessingStore {
  /// Ersetzt das Ergebnis des Laufs vollständig in einer Transaktion
  /// (kein Mischstand bei Abbruch). Unbekannter Lauf: `notFound`. Samples nach
  /// Kanal und Zeit, Spans nach Art und Beginn sortiert gelesen.
  Future<void> replace(int runId, StoredPreprocessing result);

  /// `null`, wenn für den Lauf nichts gespeichert ist.
  Future<StoredPreprocessing?> read(int runId);
}

/// Bewerteter Abschnitt (FR-0048). Von-bis steht in [quality]; auch die
/// GPS-Lücken ([SectionQuality.gpsGaps], mit Ende und `open`) werden gespeichert.
class RatedSection {
  const RatedSection({required this.assessedAt, required this.quality});

  final DateTime assessedAt;
  final SectionQuality quality;
}

/// Bewertete Abschnitte eines Laufs.
abstract interface class RatedSectionStore {
  /// Ersetzt alle Abschnitte des Laufs in einer Transaktion. Unbekannter Lauf:
  /// `notFound`.
  Future<void> replace(int runId, List<RatedSection> sections);

  /// Nach Beginn sortiert.
  Future<List<RatedSection>> read(int runId);
}

/// Lesereihenfolge der Samples: Kanal (Reihenfolge von [RawChannel]), Zeit,
/// Roh-Id. Fake und Adapter sortieren damit gleich.
int comparePreprocessedSamples(PreprocessedSample a, PreprocessedSample b) {
  final c = a.channel.index.compareTo(b.channel.index);
  if (c != 0) return c;
  final t = a.time.compareTo(b.time);
  return t != 0 ? t : a.rawId.compareTo(b.rawId);
}

/// Lesereihenfolge der Spans: Art (Reihenfolge von [PreprocessedSpanKind]),
/// dann Beginn.
int comparePreprocessedSpans(PreprocessedSpan a, PreprocessedSpan b) {
  final c = a.kind.index.compareTo(b.kind.index);
  return c != 0 ? c : a.start.compareTo(b.start);
}
