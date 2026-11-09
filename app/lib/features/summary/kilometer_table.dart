import 'dart:math' as math;

import 'package:core/core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../ui/ui.dart';
import '../run/live_run_view.dart' show formatClock;
import '../settings/unit_format.dart';

/// Untere Grenze der Balkenbreite (Anteil der Spur) und Mindestspanne der Pace
/// in s/km, über die die Balken von voll bis zur Grenze laufen (Detail.dc.html).
const double barMinFraction = 0.4;
const double barMinSpanSeconds = 40;

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
    // Detail.dc.html: 40 % bis 100 % über eine Spanne von mindestens 40 s, der
    // schnellste volle Abschnitt voll. Wenige Sekunden Unterschied sehen so nicht
    // nach viel aus; ein angebrochener Abschnitt mit absurder Pace steht auf der
    // unteren Grenze.
    final span = math.max(barMinSpanSeconds, slow - fast);
    double fraction(double pace) =>
        (1 - (pace - fast) / span * (1 - barMinFraction)).clamp(
          barMinFraction,
          1.0,
        );

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
    final times = _wholeSeconds();

    // Spaltenbreiten wie bei IntrinsicColumnWidth, aber selbst gemessen: Die
    // Beschriftung eines Abschnitts steht als eigene Zeile über der vollen
    // Tabellenbreite (eine Table kann Zellen nicht verbinden).
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    // Fettschrift des Systems macht Text breiter; Text() merkt sie sich selbst.
    final bold = MediaQuery.boldTextOf(context);
    double measure(String t, TextStyle? st) {
      final p = TextPainter(
        text: TextSpan(
          text: t,
          style: bold
              ? st?.merge(const TextStyle(fontWeight: FontWeight.bold))
              : st,
        ),
        textDirection: direction,
        textScaler: scaler,
      )..layout();
      final w = p.width.ceilToDouble() + 1;
      p.dispose();
      return w;
    }

    double widest(String h, TextStyle? hs, Iterable<String> v, TextStyle? vs) =>
        [
          measure(h, hs),
          for (final t in v) measure(t, vs),
        ].reduce((a, b) => a > b ? a : b);
    final paces = [for (final s in splits.splits) _pace(s.paceSecondsPerKm)];
    final hrs = [for (final s in splits.splits) _hr(s.heartRateAverageBpm)];
    final w0 =
        widest(unitLabel, head, [
          for (final s in splits.splits) '${s.index}',
        ], cell) +
        10;
    final w1 =
        widest(l10n.detailColTime, head, [
          for (final t in times) _time(t),
        ], cell) +
        10;
    final w3 = widest(l10n.detailColPace, head, paces, cell) + 10;
    final w4 = widest(l10n.detailColHr, head, hrs, text.bodyMedium);

    // Reicht die Breite nicht (sehr große Schrift), schrumpfen die festen
    // Spalten anteilig und die Balkenspur behält mindestens [minBar]; der
    // Abstand der Zelle (10) kommt dazu. Zahlen und Köpfe brechen nie um,
    // sondern werden in ihrer Zelle verkleinert ([fit]).
    const minBar = 24.0;
    const barGap = 10.0;
    Widget fit(Widget w) => FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: w,
    );
    var shrink = 1.0;
    Widget line(List<Widget> cells) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: w0 * shrink, child: cells[0]),
        SizedBox(width: w1 * shrink, child: cells[1]),
        Expanded(child: cells[2]),
        SizedBox(width: w3 * shrink, child: cells[3]),
        SizedBox(width: w4 * shrink, child: cells[4]),
      ],
    );

    Widget header() => line([
      padded(fit(Text(unitLabel, style: head))),
      padded(fit(Text(l10n.detailColTime, style: head))),
      const SizedBox.shrink(),
      padded(fit(Text(l10n.detailColPace, style: head))),
      fit(Text(l10n.detailColHr, style: head)),
    ]);

    Widget row(KilometerSplit s) {
      final i = s.index;
      final time = times[s.index - 1];
      final pace = s.paceSecondsPerKm;
      final captions = [
        if (s.isPartial)
          l10n.detailSplitPartial(formatter.distance(s.lengthMeters)),
        if (s.hasPositionGap)
          l10n.detailSplitGap(formatClock(s.positionGapTime)),
      ];
      // Der Screenreader liest auch „angebrochen“ und die GPS-Lücke (FR-0211).
      final label = [
        l10n.detailSplitSemantics(
          unitName,
          i,
          _time(time),
          _pace(pace),
          s.heartRateAverageBpm == null
              ? l10n.sumNoHeartRate
              : l10n.runBpm(s.heartRateAverageBpm!.round()),
        ),
        ...captions,
      ].join(', ');
      final small = text.bodySmall;
      return Column(
        key: ValueKey('detail_km_row_$i'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          line([
            padded(
              Semantics(
                container: true,
                label: label,
                excludeSemantics: true,
                child: fit(
                  Text('$i', key: Key('detail_km_index_$i'), style: cell),
                ),
              ),
            ),
            ExcludeSemantics(
              child: padded(
                fit(
                  Text(_time(time), key: Key('detail_km_time_$i'), style: cell),
                ),
              ),
            ),
            ExcludeSemantics(
              child: padded(
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
              ),
            ),
            ExcludeSemantics(
              child: padded(
                fit(
                  Text(_pace(pace), key: Key('detail_km_pace_$i'), style: cell),
                ),
              ),
            ),
            ExcludeSemantics(
              child: fit(
                Text(
                  _hr(s.heartRateAverageBpm),
                  key: Key('detail_km_hr_$i'),
                  style: text.bodyMedium,
                ),
              ),
            ),
          ]),
          // Beschriftung über die volle Breite, nicht in der Balkenspalte.
          for (var c = 0; c < captions.length; c++)
            ExcludeSemantics(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  // Die Länge „0,84 km“ am Ende bleibt zusammen (nur Anzeige;
                  // die Sprachausgabe liest [captions] im Label der Zeile).
                  unitTogether(captions[c], formatter.distanceLabel),
                  key: Key(
                    (s.isPartial && c == 0)
                        ? 'detail_km_partial_$i'
                        : 'detail_km_gap_$i',
                  ),
                  style: small,
                ),
              ),
            ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, c) {
            final fixed = w0 + w1 + w3 + w4;
            shrink = fixed + minBar + barGap > c.maxWidth
                ? ((c.maxWidth - minBar - barGap) / fixed).clamp(0.0, 1.0)
                : 1.0;
            return Column(
              key: const Key('detail_km_table'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [header(), for (final s in splits.splits) row(s)],
            );
          },
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
        heightFactor: 1,
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
