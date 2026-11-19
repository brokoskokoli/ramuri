import 'dart:convert';

import '../plan/plan_unit.dart';

/// Schnappschuss der geführten Einheit (WP24, Festlegung 3): die beim Start
/// kopierten Abschnitte samt Lauf-Kennung und dem Merker „Gehpausen-Hinweis
/// gegeben“. Steht als JSON in `settings` ([SettingKeys.guidedUnitSnapshot]);
/// eine Neuberechnung des Plans im Lauf ändert die geführte Einheit nicht, und
/// ein Wiederanlauf liest ihn wieder. Enthält keine Messwerte. Dazu kommen die
/// Bewegungszeiten, an denen der Nutzer übersprungen hat (FR-0218), damit ein
/// Wiederanlauf am erreichten Abschnitt fortsetzt.
class GuidedUnitSnapshot {
  const GuidedUnitSnapshot({
    required this.runId,
    required this.segments,
    this.walkBreakHintGiven = false,
    this.kind,
    this.skips = const [],
  });

  /// Lauf, zu dem der Schnappschuss gehört; ein fremder Lauf ignoriert ihn.
  final int runId;
  final List<PlanSegment> segments;
  final bool walkBreakHintGiven;

  /// Art der Einheit (Name von `PlanUnitKind`) für die Kopfzeile der Live-Seite;
  /// optional, ein Schnappschuss ohne sie bleibt gültig (Version 1 tolerant).
  final String? kind;

  /// Bewegungszeiten der Sprünge in ihrer Reihenfolge (FR-0218); optional,
  /// ein Schnappschuss ohne sie (Version 1 von vor FR-0218) hat keine.
  final List<Duration> skips;

  GuidedUnitSnapshot withWalkBreakHintGiven() => GuidedUnitSnapshot(
    runId: runId,
    segments: segments,
    walkBreakHintGiven: true,
    kind: kind,
    skips: skips,
  );

  /// Derselbe Schnappschuss mit den Sprüngen [value].
  GuidedUnitSnapshot withSkips(List<Duration> value) => GuidedUnitSnapshot(
    runId: runId,
    segments: segments,
    walkBreakHintGiven: walkBreakHintGiven,
    kind: kind,
    skips: List.unmodifiable(value),
  );

  String encode() => jsonEncode({
    'v': 1,
    'run': runId,
    'hint': walkBreakHintGiven,
    if (kind != null) 'kind': kind,
    'seg': [for (final s in segments) _segment(s)],
    if (skips.isNotEmpty) 'skip': [for (final d in skips) d.inMilliseconds],
  });

  /// `null` bei leerem, unlesbarem oder fremdem Wert.
  static GuidedUnitSnapshot? decode(String? value) {
    if (value == null || value.isEmpty) return null;
    try {
      final j = jsonDecode(value);
      if (j is! Map<String, dynamic> || j['v'] != 1) return null;
      final run = j['run'];
      final seg = j['seg'];
      if (run is! int || seg is! List) return null;
      return GuidedUnitSnapshot(
        runId: run,
        segments: [
          for (final s in seg) _readSegment(s as Map<String, dynamic>),
        ],
        walkBreakHintGiven: j['hint'] == true,
        kind: j['kind'] is String ? j['kind'] as String : null,
        skips: _readSkips(j['skip']),
      );
    } on Object {
      return null;
    }
  }

  /// Fehlt der Eintrag, gibt es keine Sprünge; ein kaputter Eintrag macht den
  /// ganzen Schnappschuss unlesbar (wie bei den Abschnitten).
  static List<Duration> _readSkips(Object? value) {
    if (value == null) return const [];
    return List.unmodifiable([
      for (final ms in value as List) Duration(milliseconds: ms as int),
    ]);
  }

  static Map<String, Object?> _segment(PlanSegment s) => {
    'k': s.kind.name,
    'm': s.minutes,
    if (s.seconds != null) 's': s.seconds,
    if (s.intensity != null) 'i': _intensity(s.intensity!),
  };

  static PlanSegment _readSegment(Map<String, dynamic> j) => PlanSegment(
    kind: PlanSegmentKind.values.byName(j['k'] as String),
    minutes: j['m'] as int,
    seconds: j['s'] as int?,
    intensity: j['i'] == null
        ? null
        : _readIntensity(j['i'] as Map<String, dynamic>),
  );

  static Map<String, Object?> _intensity(PlanTargetIntensity t) => {
    if (t.rpeMin != null) 'rmin': t.rpeMin,
    if (t.rpeMax != null) 'rmax': t.rpeMax,
    if (t.paceFastSecondsPerKm != null) 'pf': t.paceFastSecondsPerKm,
    if (t.paceSlowSecondsPerKm != null) 'ps': t.paceSlowSecondsPerKm,
    if (t.basisCode != null) 'b': t.basisCode,
    if (t.hrMinBpm != null) 'hmin': t.hrMinBpm,
    if (t.hrMaxBpm != null) 'hmax': t.hrMaxBpm,
    if (t.estimated) 'e': true,
    if (t.maxHrEstimated) 'me': true,
    if (t.paceIsLimit) 'pl': true,
  };

  static PlanTargetIntensity _readIntensity(Map<String, dynamic> j) =>
      PlanTargetIntensity(
        rpeMin: j['rmin'] as int?,
        rpeMax: j['rmax'] as int?,
        paceFastSecondsPerKm: (j['pf'] as num?)?.toDouble(),
        paceSlowSecondsPerKm: (j['ps'] as num?)?.toDouble(),
        basisCode: j['b'] as String?,
        hrMinBpm: j['hmin'] as int?,
        hrMaxBpm: j['hmax'] as int?,
        estimated: j['e'] == true,
        maxHrEstimated: j['me'] == true,
        paceIsLimit: j['pl'] == true,
      );
}
