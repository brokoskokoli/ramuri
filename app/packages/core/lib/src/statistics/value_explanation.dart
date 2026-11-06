import '../../ports/storage.dart';
import '../../ports/storage_devices.dart';
import '../../ports/storage_profile.dart';
import '../../ports/storage_values.dart';
import '../fitness/fitness_result.dart';
import '../sensors/heart_rate_sources.dart';

/// Art einer Quelle von Messwerten (SEC-0005, FR-0020).
enum ExplainedSourceKind {
  /// Standort des Telefons (`raw_positions.source`, Kennung `gps`).
  gps,

  /// Pulssensor; die Kennung ist die Geräte-ID.
  heartRateDevice,
}

/// Eine Quelle zu einem Datensatz: die gespeicherte Kennung, bei einem
/// Pulssensor der Name aus den bekannten Geräten. Ein Gerät, das nicht mehr
/// bekannt ist (gelöscht), hat keinen Namen ([deleted]); ein bekanntes ohne
/// Anzeigenamen hat [name] `null` und [deleted] `false`.
class ExplainedSource {
  const ExplainedSource({
    required this.id,
    required this.kind,
    this.name,
    this.deleted = false,
    this.count,
    this.firstTime,
    this.lastTime,
  });

  final String id;
  final ExplainedSourceKind kind;
  final String? name;
  final bool deleted;

  /// Zahl der gespeicherten Werte dieses Abschnitts (nur Läufe).
  final int? count;

  /// Zeit des ersten und letzten Werts des Abschnitts. Dazwischen können
  /// Lücken liegen; daraus keine Dauer mit Puls ableiten (FR-0056).
  final DateTime? firstTime;
  final DateTime? lastTime;
}

/// Kennung der Standortquelle in den Rohdaten (`RecordingSession`).
const String gpsSourceId = 'gps';

/// Alles, was die Erklärung eines Werts (FR-0059) aus den gespeicherten Daten
/// braucht. Keine Texte: die Oberfläche beantwortet die sechs Fragen daraus.
class ValueExplanation {
  const ValueExplanation({
    required this.valueKey,
    required this.value,
    required this.sources,
    required this.profile,
    required this.failed,
  });

  final String valueKey;

  /// Der gespeicherte aktuelle Wert samt Grund; `null`, wenn keiner vorliegt.
  final ComputedValue? value;

  /// Quellen: bei Laufwerten die Abschnitte der Pulsquellen und die
  /// Standortquelle des Laufs, bei Tageswerten die Kennungen am Wert.
  final List<ExplainedSource> sources;

  /// Aktuelles Profil (für den Hinweis nach FR-0055).
  final ProfileRecord profile;

  /// Das Lesen ist gescheitert (kein Grund, kein Wert).
  final bool failed;

  /// Welche Profilwerte fehlen, die dieser Wert braucht (FR-0055).
  Set<ProfileGap> get profileGaps {
    final v = value;
    final reason = v?.unavailableReason;
    final basis = v?.heartRateBasis;
    final gaps = <ProfileGap>{};
    final needsMax =
        reason == UnavailableReason.missingMaxHeartRate ||
        (basis != null && basis.usableMaxBpm == null);
    final needsRest =
        reason == UnavailableReason.missingRestingHeartRate ||
        (basis != null && basis.usableRestingBpm == null);
    final needsBoth =
        reason == UnavailableReason.maxNotAboveResting ||
        reason == UnavailableReason.reserveTooSmall;
    if (needsMax || needsBoth) gaps.add(ProfileGap.maxHeartRate);
    if (needsRest || needsBoth) gaps.add(ProfileGap.restingHeartRate);
    return gaps;
  }
}

/// Ein Profilwert, dessen Fehlen einen Wert verhindert.
enum ProfileGap { maxHeartRate, restingHeartRate }

/// Liest zu einem Wert, was die Erklärung braucht. Nur lesend.
class ValueExplanationService {
  ValueExplanationService({required this.session});

  final StorageSession session;

  /// [runId] für Laufwerte, [day] (`JJJJ-MM-TT`) für Tageswerte.
  Future<ValueExplanation> load(
    String valueKey, {
    int? runId,
    String? day,
  }) async {
    assert((runId == null) != (day == null));
    try {
      final owner = runId != null
          ? ValueOwner.run(runId)
          : ValueOwner.day(day!);
      ComputedValue? value;
      for (final p in await session.values.read(owner)) {
        if (p.current.key == valueKey) value = p.current;
      }
      final devices = {
        for (final d in await session.devices.list()) d.deviceId: d,
      };
      final sources = runId != null
          ? await _runSources(runId, devices)
          : _valueSources(value, devices);
      return ValueExplanation(
        valueKey: valueKey,
        value: value,
        sources: sources,
        profile: await session.profile.read(),
        failed: false,
      );
    } on StorageException {
      return ValueExplanation(
        valueKey: valueKey,
        value: null,
        sources: const [],
        profile: const ProfileRecord(),
        failed: true,
      );
    }
  }

  /// Nur die Quellen der Rohdaten eines Laufs (SEC-0005), ohne Wert.
  Future<ValueExplanation> loadSources(int runId) async {
    try {
      final devices = {
        for (final d in await session.devices.list()) d.deviceId: d,
      };
      return ValueExplanation(
        valueKey: 'run_sources',
        value: null,
        sources: await _runSources(runId, devices),
        profile: const ProfileRecord(),
        failed: false,
      );
    } on StorageException {
      return const ValueExplanation(
        valueKey: 'run_sources',
        value: null,
        sources: [],
        profile: ProfileRecord(),
        failed: true,
      );
    }
  }

  /// Quellen der Rohdaten eines Laufs: Standort, dann die Pulsabschnitte.
  Future<List<ExplainedSource>> _runSources(
    int runId,
    Map<String, KnownDevice> devices,
  ) async {
    final raw = await session.rawData.read(runId);
    final out = <ExplainedSource>[];
    final positions = raw.positions
        .where((p) => p.value.source == gpsSourceId)
        .toList();
    if (positions.isNotEmpty) {
      out.add(
        ExplainedSource(
          id: gpsSourceId,
          kind: ExplainedSourceKind.gps,
          count: positions.length,
          firstTime: positions.first.value.time,
          lastTime: positions.last.value.time,
        ),
      );
    }
    for (final s in heartRateSourceSections([
      for (final r in raw.heartRates) r.value,
    ])) {
      out.add(_device(s.deviceId, devices, s));
    }
    return out;
  }

  ExplainedSource _device(
    String id,
    Map<String, KnownDevice> devices, [
    HeartRateSourceSection? section,
  ]) {
    final known = devices[id];
    return ExplainedSource(
      id: id,
      kind: ExplainedSourceKind.heartRateDevice,
      name: known?.displayName,
      deleted: known == null,
      count: section?.count,
      firstTime: section?.start,
      lastTime: section?.end,
    );
  }

  /// Quellen am Wert (Tageswerte tragen nur Kennungen). Eine Kennung, die weder
  /// die Standortquelle noch ein bekanntes Gerät ist, gilt als gelöschtes Gerät.
  List<ExplainedSource> _valueSources(
    ComputedValue? value,
    Map<String, KnownDevice> devices,
  ) => [
    for (final id in value?.sources ?? const <String>[])
      id == gpsSourceId
          ? const ExplainedSource(
              id: gpsSourceId,
              kind: ExplainedSourceKind.gps,
            )
          : _device(id, devices),
  ];
}
