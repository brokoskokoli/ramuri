import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import '../../ui/ui.dart';
import '../statistics/fitness_section.dart' show fitnessNumber;

/// Vergleichskarte „Zum Vergleich: andere Apps“ auf „Fortschritt“ (WP32 Teil E,
/// FR-0024, SEC-0005): die aus Health Connect gelesenen VO₂max-Schätzwerte, je
/// Quell-App eine Zeile mit Quelle, Datum und kleinem Verlauf. Die Werte sind
/// nur Anzeige. Sie gehen weder in die eigene VO₂max-Reihe noch in eine
/// Berechnung ein und werden weder verrechnet noch gemittelt. Ohne Importdaten
/// (keine Einwilligung, nichts importiert) bleibt die Karte unsichtbar.
class Vo2ComparisonCard extends StatefulWidget {
  const Vo2ComparisonCard({super.key, required this.session});

  final StorageSession session;

  @override
  State<Vo2ComparisonCard> createState() => _Vo2ComparisonCardState();
}

class _Vo2ComparisonCardState extends State<Vo2ComparisonCard> {
  late Future<List<Vo2maxSourceSeries>> _future = _load();

  @override
  void didUpdateWidget(Vo2ComparisonCard old) {
    super.didUpdateWidget(old);
    if (!identical(old.session, widget.session)) _future = _load();
  }

  Future<List<Vo2maxSourceSeries>> _load() async {
    final session = widget.session;
    if (session is! HealthStorage) return const [];
    try {
      final records = await (session as HealthStorage).health.values(
        HealthDataKind.vo2Max,
        DateTime.utc(2000),
        DateTime.utc(2200),
      );
      return vo2maxComparison(records);
    } on Object {
      // Ohne Inhalt: die Karte fehlt, der Rest der Seite bleibt.
      return const [];
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Vo2maxSourceSeries>>(
      future: _future,
      builder: (context, snapshot) {
        final sources = snapshot.data;
        if (sources == null || sources.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Vo2ComparisonView(sources: sources),
        );
      },
    );
  }
}

/// Darstellung der Vergleichskarte (ohne Laden).
class Vo2ComparisonView extends StatelessWidget {
  const Vo2ComparisonView({super.key, required this.sources});

  final List<Vo2maxSourceSeries> sources;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    final c = RamuriColors.of(context);
    final date = DateFormat.MMMd(lang);
    return RamuriCard(
      key: const Key('health_vo2_card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeading(l10n.healthVo2CardTitle, eyebrow: true),
          const SizedBox(height: 6),
          // Eigene Zeile: neben der Überschrift ist bei schmaler Anzeige
          // und großem Text kein Platz (Überlauf).
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: RamuriBadge(l10n.healthVo2CardBadge),
          ),
          for (final s in sources) ...[
            const SizedBox(height: 12),
            Semantics(
              container: true,
              excludeSemantics: true,
              label: [
                l10n.healthVo2Source(s.origin),
                l10n.healthVo2Semantics(
                  s.origin,
                  fitnessNumber(lang == 'de', s.latest.value),
                ),
                l10n.healthVo2Estimate(date.format(s.latest.time.toLocal())),
              ].join(', '),
              child: Row(
                key: Key('health_vo2_row_${s.origin}'),
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.healthVo2Source(s.origin),
                          key: Key('health_vo2_source_${s.origin}'),
                          style: text.titleSmall,
                        ),
                        Text(
                          l10n.healthVo2Estimate(
                            date.format(s.latest.time.toLocal()),
                          ),
                          style: text.bodySmall?.copyWith(color: c.textMuted),
                        ),
                      ],
                    ),
                  ),
                  if (s.points.length >= 2)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 12),
                      child: CustomPaint(
                        size: const Size(60, 28),
                        painter: _LinePainter([
                          for (final p in s.points) p.value,
                        ], c.accent),
                      ),
                    ),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: fitnessNumber(lang == 'de', s.latest.value),
                          style: text.titleLarge,
                        ),
                        TextSpan(
                          text: ' ${l10n.healthVo2Unit}',
                          style: text.bodySmall?.copyWith(color: c.textMuted),
                        ),
                      ],
                    ),
                    key: Key('health_vo2_value_${s.origin}'),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            l10n.healthVo2Note,
            key: const Key('health_vo2_note'),
            style: text.bodySmall?.copyWith(color: c.textMuted),
          ),
        ],
      ),
    );
  }
}

class _LinePainter extends CustomPainter {
  const _LinePainter(this.values, this.color);
  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    var lo = values.reduce((a, b) => a < b ? a : b);
    var hi = values.reduce((a, b) => a > b ? a : b);
    // Flache Reihen bleiben flach (Mindestspanne wie bei der Verlaufslinie).
    if (hi - lo < 2) {
      final mid = (hi + lo) / 2;
      lo = mid - 1;
      hi = mid + 1;
    }
    final pts = [
      for (var i = 0; i < values.length; i++)
        Offset(
          2 + (size.width - 4) * i / (values.length - 1),
          2 + (size.height - 4) * (1 - (values[i] - lo) / (hi - lo)),
        ),
    ];
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (final p in pts.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_LinePainter old) =>
      old.color != color || old.values != values;
}
