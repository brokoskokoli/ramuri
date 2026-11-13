import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import '../../ui/ui.dart';
import '../settings/app_settings.dart';
import '../settings/unit_format.dart';
import 'plan_texts.dart';

/// Beschreibung einer geplanten Einheit (FR-0143): Bezeichnung, Tag,
/// Trainingsziel, Dauer, Ablauf mit Zielintensität je Abschnitt und die
/// Grundlage der Vorgabe (PAR-106). Vollbild über der Navigation.
class PlanUnitScreen extends StatelessWidget {
  const PlanUnitScreen({super.key, required this.unit});

  final PlanUnit unit;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = RamuriColors.of(context);
    final text = Theme.of(context).textTheme;
    final lang = Localizations.localeOf(context).languageCode;
    final formatter = AppSettingsScope.formatterOf(context);
    return Scaffold(
      appBar: AppBar(),
      body: ListView(
        key: const Key('plan_unit_detail'),
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        children: [
          Semantics(
            header: true,
            child: Text(
              planKindName(l, unit.kind),
              key: const Key('plan_unit_title'),
              style: RamuriType.of(context).pageTitle,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            DateFormat.yMMMMEEEEd(lang).format(unit.day),
            style: text.titleSmall,
          ),
          Text(
            l.planUnitWeekPhase(
              unit.weekIndex + 1,
              planPhaseFull(l, unit.phase),
            ),
            style: text.bodySmall,
          ),
          const SizedBox(height: 18),
          SectionHeading(l.planUnitPurpose, eyebrow: true),
          const SizedBox(height: 6),
          Text(
            planKindPurpose(l, unit.kind),
            key: const Key('plan_unit_purpose'),
            style: text.bodyMedium,
          ),
          if (unit.kind != PlanUnitKind.rest) ...[
            const SizedBox(height: 18),
            SectionHeading(l.planUnitDuration, eyebrow: true),
            const SizedBox(height: 6),
            Text(
              planDurationText(l, unit.minutes),
              key: const Key('plan_unit_duration'),
              style: RamuriType.of(context).value,
            ),
          ],
          if (unit.segments.isNotEmpty) ...[
            const SizedBox(height: 18),
            SectionHeading(l.planUnitParts, eyebrow: true),
            const SizedBox(height: 8),
            for (var i = 0; i < unit.segments.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: RamuriCard(
                  key: Key('plan_unit_segment_$i'),
                  radius: 16,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  child: PlanSegmentRow(
                    segment: unit.segments[i],
                    formatter: formatter,
                    colors: c,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class PlanSegmentRow extends StatelessWidget {
  const PlanSegmentRow({
    super.key,
    required this.segment,
    required this.formatter,
    required this.colors,
  });

  final PlanSegment segment;
  final UnitFormatter formatter;
  final RamuriColors colors;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final t = segment.intensity;
    final lines = <Widget>[];
    if (t != null) {
      final rpe = _rpe(l, t);
      if (rpe != null) lines.add(Text(rpe, style: text.bodySmall));
      final pace = _pace(l, t);
      if (pace != null) lines.add(Text(pace, style: text.bodySmall));
      if (t.hrMinBpm != null && t.hrMaxBpm != null) {
        lines.add(
          Text(
            l.planHeartRateRange(t.hrMinBpm!, t.hrMaxBpm!),
            style: text.bodySmall,
          ),
        );
      }
      if (t.maxHrEstimated) {
        lines.add(Text(l.planMaxHrEstimated, style: text.bodySmall));
      }
      final basis = planBasisText(l, t.basisCode);
      if (basis != null) {
        lines.add(
          Text(
            l.planBasisLine(basis),
            key: const Key('plan_unit_basis'),
            style: text.labelSmall,
          ),
        );
      }
      if (t.estimated) lines.add(const EstimatedMark());
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                planSegmentName(l, segment.kind),
                style: text.titleSmall,
              ),
            ),
            Text(
              planSegmentDuration(l, segment.durationSeconds),
              style: text.labelMedium,
            ),
          ],
        ),
        if (lines.isNotEmpty) const SizedBox(height: 4),
        ...lines,
      ],
    );
  }

  /// RPE mit den Wörtern nach PAR-105 (die Skala aus der Rückmeldung). Bei
  /// einer Spanne steht das Wort der unteren Stufe: Das Wort der oberen würde
  /// bei Gehen und Aufwärmen (1 bis 4) „Fordert etwas“ sagen.
  static String? _rpe(AppLocalizations l, PlanTargetIntensity t) {
    final min = t.rpeMin;
    final max = t.rpeMax ?? min;
    if (min == null || max == null) return null;
    final word = _rpeWord(l, min);
    return min == max
        ? l.planRpeSingle(min, word)
        : l.planRpeRange(min, max, word);
  }

  String? _pace(AppLocalizations l, PlanTargetIntensity t) {
    final fast = t.paceFastSecondsPerKm;
    final slow = t.paceSlowSecondsPerKm;
    if (fast == null) return null;
    if (t.paceIsLimit || slow == null) {
      return l.planPaceLimit(formatter.pace(fast));
    }
    return l.planPaceRange(formatter.pace(fast), formatter.pace(slow));
  }
}

String _rpeWord(AppLocalizations l, int rpe) => switch (rpe.clamp(0, 10)) {
  0 => l.subjectiveRpe0,
  1 => l.subjectiveRpe1,
  2 => l.subjectiveRpe2,
  3 => l.subjectiveRpe3,
  4 => l.subjectiveRpe4,
  5 => l.subjectiveRpe5,
  6 => l.subjectiveRpe6,
  7 => l.subjectiveRpe7,
  8 => l.subjectiveRpe8,
  9 => l.subjectiveRpe9,
  _ => l.subjectiveRpe10,
};
