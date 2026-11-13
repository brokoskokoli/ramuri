import 'package:core/core.dart';

import '../../l10n/app_localizations.dart';

/// Wortlaut der Ansagen (WP24, Festlegung 11): setzt aus einem
/// [GuidanceEvent] (Codes und Werte aus `core`) den gesprochenen Text in der
/// App-Sprache. Zahlen wie die Anzeige: Pace als `m:ss`, je Kilometer oder je
/// Meile nach der Einstellung ([DistanceUnit]).
class VoiceTexts {
  const VoiceTexts(this.l);

  final AppLocalizations l;

  /// Sprache der Ausgabe (BCP 47, nur der Sprachteil der App-Locale).
  String get languageTag => l.localeName.split('_').first;

  String text(GuidanceEvent e, DistanceUnit unit) => switch (e.kind) {
    GuidanceEventKind.kilometer => _kilometer(e, unit),
    GuidanceEventKind.segmentChange => _segmentChange(e, unit),
    GuidanceEventKind.segmentPreview => _preview(e, unit),
    GuidanceEventKind.unitComplete => l.voiceUnitComplete,
    GuidanceEventKind.heartRateAbove => l.voiceHeartRateAbove(
      '${e.heartRateBpm}',
      '${e.heartRateMaxBpm}',
    ),
    GuidanceEventKind.walkBreakHint => l.voiceWalkBreakHint,
  };

  String _kilometer(GuidanceEvent e, DistanceUnit unit) {
    final time = _time(e.kilometerTime!);
    final head = unit == DistanceUnit.miles
        ? l.voiceMile(
            _decimal(unit.distanceFromMeters(e.kilometer! * 1000.0)),
            time,
          )
        : l.voiceKilometer(e.kilometer!, time);
    final d = e.kilometerDuration;
    if (d == null || d <= Duration.zero) return head;
    final pace = _pace(d.inMilliseconds / 1000, unit);
    final tail = unit == DistanceUnit.miles
        ? l.voicePacePerMile(pace)
        : l.voicePacePerKm(pace);
    return '$head $tail';
  }

  String _segmentChange(GuidanceEvent e, DistanceUnit unit) {
    final head = l.voiceSegmentChange(
      _segment(e.segmentKind!),
      _time(e.segmentDuration!),
    );
    final target = _target(e.target, unit);
    return target == null ? head : '$head $target';
  }

  String _preview(GuidanceEvent e, DistanceUnit unit) {
    final head = l.voiceSegmentPreview(
      e.secondsUntilChange ?? 0,
      _segment(e.segmentKind!),
    );
    final target = _target(e.target, unit);
    return target == null ? head : '$head $target';
  }

  /// Ein Ziel je Ansage (Auslegung WP24): Pace, sonst Puls, sonst RPE.
  String? _target(PlanTargetIntensity? t, DistanceUnit unit) {
    if (t == null) return null;
    final slow = t.paceSlowSecondsPerKm;
    final fast = t.paceFastSecondsPerKm;
    if (t.paceIsLimit && slow != null) {
      return l.voiceTargetPaceLimit(_pace(slow, unit));
    }
    if (fast != null && slow != null) {
      return l.voiceTargetPace(_pace(fast, unit), _pace(slow, unit));
    }
    if (t.hrMinBpm != null && t.hrMaxBpm != null) {
      return l.voiceTargetHeartRate('${t.hrMinBpm}', '${t.hrMaxBpm}');
    }
    final lo = t.rpeMin;
    final hi = t.rpeMax;
    if (lo != null && hi != null) {
      return lo == hi
          ? l.voiceTargetRpeSingle('$lo')
          : l.voiceTargetRpe('$lo', '$hi');
    }
    final one = lo ?? hi;
    return one == null ? null : l.voiceTargetRpeSingle('$one');
  }

  String _segment(PlanSegmentKind k) => switch (k) {
    PlanSegmentKind.warmUp => l.voiceSegmentWarmUp,
    PlanSegmentKind.easy => l.voiceSegmentEasy,
    PlanSegmentKind.interval => l.voiceSegmentInterval,
    PlanSegmentKind.tempo => l.voiceSegmentTempo,
    PlanSegmentKind.recovery => l.voiceSegmentRecovery,
    PlanSegmentKind.endBlock => l.voiceSegmentEndBlock,
    PlanSegmentKind.coolDown => l.voiceSegmentCoolDown,
    PlanSegmentKind.run => l.voiceSegmentRun,
    PlanSegmentKind.walk => l.voiceSegmentWalk,
  };

  String _time(Duration d) {
    final s = d.inSeconds;
    if (s >= 3600) return l.voiceTimeHours(s ~/ 3600, s % 3600 ~/ 60);
    return l.voiceTimeMinutes(s ~/ 60, s % 60);
  }

  /// Pace `m:ss` wie [UnitFormatter.pace], auf ganze Sekunden gerundet.
  String _pace(double secondsPerKm, DistanceUnit unit) {
    final total = unit.paceFromSecondsPerKm(secondsPerKm).round();
    return '${total ~/ 60}:${(total % 60).toString().padLeft(2, '0')}';
  }

  String _decimal(double v) {
    final s = v.toStringAsFixed(1);
    return languageTag == 'de' ? s.replaceAll('.', ',') : s;
  }
}
