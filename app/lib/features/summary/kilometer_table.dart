import 'package:core/core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../ui/ui.dart';
import '../run/live_run_view.dart' show formatClock;
import '../settings/unit_format.dart';

/// Kilometertabelle der Detailansicht nach `Detail.dc.html` (FR-0211): je
/// voller Kilometer (bei Meilen je Meile) die Bewegungszeit, ein Balken nach
/// der Pace, die Pace und der mittlere Puls. Die Tabelle zeigt nur, was
/// [computeKilometerSplits] liefert. Die Zeit enthält die Lückenzeit, die Pace
/// nicht; ein Abschnitt mit Positionslücke ist gekennzeichnet, der angebrochene
/// letzte nennt seine Länge. Was fehlt, steht als „–“, nie als 0.
class KilometerTable extends StatelessWidget {
  const KilometerTable({
    super.key,
    required this.splits,
    required this.formatter,
  });

  final KilometerSplits splits;
  final UnitFormatter formatter;

  /// Pace-Text ohne Einheit (die Kopfzeile nennt sie nicht, die Spalte ist schmal).
  String _pace(double? secondsPerKm) =>
      formatter.pace(secondsPerKm).replaceFirst(' ${formatter.paceLabel}', '');

  String _hr(double? bpm) =>
      bpm == null ? UnitFormatter.noValue : '${bpm.round()}';

  String _time(Duration d) =>
      d > Duration.zero ? formatClock(d) : UnitFormatter.noValue;

  /// Zeiten in ganzen Sekunden. Die Zeiten der Abschnitte sind Bruchteile von
  /// Sekunden (die Grenzen liegen zwischen zwei Messpunkten); jede einzeln
  /// abzuschneiden ließe die Summe unter der angezeigten Bewegungszeit liegen.
  /// Darum wird die laufende Summe abgeschnitten und die Differenz gezeigt:
  /// jeder Wert weicht um weniger als eine Sekunde ab, die Summe ist genau die
  /// angezeigte Bewegungszeit (`formatClock` schneidet ebenfalls ab).
  List<Duration> _wholeSeconds() {
    final out = <Duration>[];
    var cumulative = Duration.zero;
    var shown = 0;
    for (final s in splits.splits) {
      cumulative += s.time;
      final now = cumulative.inSeconds;
      out.add(Duration(seconds: now - shown));
      shown = now;
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final colors = RamuriColors.of(context);
    if (splits.splits.isEmpty) {
      return Text(l10n.detailSplitsNone, key: const Key('detail_km_none'));
    }
    // Balkenlänge nach der Pace der vollen Abschnitte (schnell = lang); der
    // angebrochene Rest ordnet sich nur ein und prägt die Skala nicht.
    final full = [
      for (final s in splits.splits)
        if (!s.isPartial && s.paceSecondsPerKm != null) s.paceSecondsPerKm!,
    ];
    final scale = full.isEmpty
        ? [
            for (final s in splits.splits)
              if (s.paceSecondsPerKm != null) s.paceSecondsPerKm!,
          ]
        : full;
    final fast = scale.isEmpty ? 0.0 : scale.reduce((a, b) => a < b ? a : b);
    final slow = scale.isEmpty ? 0.0 : scale.reduce((a, b) => a > b ? a : b);
    final mean = scale.isEmpty
        ? 0.0
        : scale.reduce((a, b) => a + b) / scale.length;
    double fraction(double pace) => slow - fast < 1e-9
        ? 1
        : (0.4 + 0.6 * (slow - pace) / (slow - fast)).clamp(0.05, 1.0);

    final head = text.labelMedium?.copyWith(color: colors.textMuted);
    final cell = text.bodyMedium?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
      fontWeight: FontWeight.w700,
    );
    const pad = EdgeInsets.only(right: 10);
    Widget padded(Widget w, {EdgeInsets p = pad}) =>
        Padding(padding: p, child: w);
    final unitLabel = formatter.distanceLabel;
    final unitName = unitLabel;

    TableRow header() => TableRow(
      children: [
        padded(Text(unitLabel, style: head)),
        padded(Text(l10n.detailColTime, style: head)),
        const SizedBox.shrink(),
        padded(Text(l10n.detailColPace, style: head)),
        Text(l10n.detailColHr, style: head),
      ],
    );

    final times = _wholeSeconds();
    TableRow row(KilometerSplit s) {
      final i = s.index;
      final time = times[s.index - 1];
      final pace = s.paceSecondsPerKm;
      final label = l10n.detailSplitSemantics(
        unitName,
        i,
        _time(time),
        _pace(pace),
        s.heartRateAverageBpm == null
            ? l10n.sumNoHeartRate
            : l10n.runBpm(s.heartRateAverageBpm!.round()),
      );
      final captions = [
        if (s.isPartial)
          l10n.detailSplitPartial(formatter.distance(s.lengthMeters)),
        if (s.hasPositionGap)
          l10n.detailSplitGap(formatClock(s.positionGapTime)),
      ];
      final small = text.bodySmall;
      return TableRow(
        key: ValueKey('detail_km_row_$i'),
        children: [
          padded(
            Semantics(
              container: true,
              label: label,
              excludeSemantics: true,
              child: Text('$i', key: Key('detail_km_index_$i'), style: cell),
            ),
          ),
          ExcludeSemantics(
            child: padded(
              Text(_time(time), key: Key('detail_km_time_$i'), style: cell),
            ),
          ),
          ExcludeSemantics(
            child: padded(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: _Bar(
                      key: Key('detail_km_bar_$i'),
                      fraction: pace == null ? 0 : fraction(pace),
                      fast: pace != null && pace <= mean,
                      track: colors.track,
                      strong: colors.accent,
                      soft: colors.action,
                    ),
                  ),
                  for (var c = 0; c < captions.length; c++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        captions[c],
                        key: Key(
                          (s.isPartial && c == 0)
                              ? 'detail_km_partial_$i'
                              : 'detail_km_gap_$i',
                        ),
                        style: small,
                      ),
                    ),
                ],
              ),
            ),
          ),
          ExcludeSemantics(
            child: padded(
              Text(_pace(pace), key: Key('detail_km_pace_$i'), style: cell),
            ),
          ),
          ExcludeSemantics(
            child: Text(
              _hr(s.heartRateAverageBpm),
              key: Key('detail_km_hr_$i'),
              style: text.bodyMedium,
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Table(
          key: const Key('detail_km_table'),
          defaultVerticalAlignment: TableCellVerticalAlignment.top,
          columnWidths: const {
            0: IntrinsicColumnWidth(),
            1: IntrinsicColumnWidth(),
            2: FlexColumnWidth(),
            3: IntrinsicColumnWidth(),
            4: IntrinsicColumnWidth(),
          },
          children: [header(), for (final s in splits.splits) row(s)],
        ),
        const SizedBox(height: 8),
        Text(l10n.detailSplitsNote, style: text.bodySmall),
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    super.key,
    required this.fraction,
    required this.fast,
    required this.track,
    required this.strong,
    required this.soft,
  });

  final double fraction;
  final bool fast;
  final Color track;
  final Color strong;
  final Color soft;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 10,
      decoration: BoxDecoration(
        color: track,
        borderRadius: BorderRadius.circular(5),
      ),
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: fraction,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: fast ? strong : soft,
            borderRadius: BorderRadius.circular(5),
          ),
        ),
      ),
    );
  }
}
