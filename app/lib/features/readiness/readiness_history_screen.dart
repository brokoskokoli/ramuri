import 'package:core/core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../ui/ui.dart';
import 'readiness_service.dart';
import 'readiness_texts.dart';

/// Tage im Verlauf (Design: 28 Tage).
const int readinessHistoryDays = 28;

/// Verlauf der Reihen (WP34 Teil D2, Design
/// `design/screens/readiness/Verlauf.dc.html`): je Quelle eine eigene Reihe
/// über 28 Tage (Health Connect je Quell-App, Kamera je Haltung und Gerät),
/// nie gemischt, ohne Vergleichswerte anderer Menschen. Tage ohne Wert bleiben
/// Lücken. Die Werte stammen aus den Reihen des Modells
/// ([DeviationResult.byDay]), die Seite rechnet nichts.
class ReadinessHistoryScreen extends StatelessWidget {
  const ReadinessHistoryScreen({super.key, required this.snapshot});

  final ReadinessSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = RamuriColors.of(context);
    final shown = [
      for (final s in snapshot.series)
        if (s.byDay.isNotEmpty) s,
    ];
    final hc = [
      for (final s in shown)
        if (s.source == ReadinessSource.healthConnect) s,
    ];
    final cam = [
      for (final s in shown)
        if (s.source == ReadinessSource.camera) s,
    ];
    DateTime? last;
    for (final s in shown) {
      for (final d in s.byDay.keys) {
        if (last == null || d.isAfter(last)) last = d;
      }
    }
    final today = snapshot.today ?? last;
    return Scaffold(
      key: const Key('readiness_history'),
      appBar: AppBar(title: Text(l.readinessHistoryTitle)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l.readinessHistoryNote,
              key: const Key('readiness_history_note'),
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: c.textMuted),
            ),
            if (shown.isEmpty || today == null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(
                  l.readinessSeriesNone,
                  key: const Key('readiness_history_none'),
                ),
              )
            else ...[
              if (hc.isNotEmpty)
                _GroupHead(text: l.readinessSourceHealthConnect),
              for (var i = 0; i < hc.length; i++)
                _SeriesCard(
                  keyName: 'hc_${hc[i].factor.name}_$i',
                  series: hc[i],
                  today: today,
                  snapshot: snapshot,
                ),
              if (cam.isNotEmpty) _GroupHead(text: l.readinessSourceCamera),
              for (var i = 0; i < cam.length; i++)
                _SeriesCard(
                  keyName: 'camera_${cam[i].factor.name}_$i',
                  series: cam[i],
                  today: today,
                  snapshot: snapshot,
                ),
            ],
            if (snapshot.developerMode)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Center(
                  child: Text(
                    l.morningDevActive,
                    key: const Key('readiness_history_dev'),
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _GroupHead extends StatelessWidget {
  const _GroupHead({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 8),
    child: Semantics(
      header: true,
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: RamuriColors.of(context).textMuted,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );
}

/// Die Werte der 28 Tage bis [today], ältester zuerst; `null` = Lücke.
List<double?> readinessSeriesValues(DeviationResult s, DateTime today) => [
  for (var i = readinessHistoryDays - 1; i >= 0; i--)
    s.byDay[today.subtract(Duration(days: i))],
];

class _SeriesCard extends StatelessWidget {
  const _SeriesCard({
    required this.keyName,
    required this.series,
    required this.today,
    required this.snapshot,
  });

  final String keyName;
  final DeviationResult series;
  final DateTime today;
  final ReadinessSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = RamuriColors.of(context);
    final t = Theme.of(context).textTheme;
    final s = series;
    final values = readinessSeriesValues(s, today);
    final count = values.where((v) => v != null).length;
    final camera = s.source == ReadinessSource.camera;
    final hrv = s.factor == ReadinessFactor.hrv;
    final decimals = camera && !hrv ? 1 : 0;
    final name = readinessFactorName(
      l,
      hrv ? ReadinessFactorId.hrv : ReadinessFactorId.restingHeartRate,
    );
    final title = l.readinessSeriesTitle(name, hrv ? 'ms' : '/min');
    final sourceName = readinessSourceName(
      l,
      camera
          ? ReadinessFactorSource.camera
          : ReadinessFactorSource.healthConnect,
    );
    final key = s.cameraSeries;
    final posture = key?.posture == RestingPosture.sitting
        ? l.measurePostureSitting
        : l.measurePostureLying;
    final device = key == null
        ? ''
        : [key.manufacturer, key.model].where((x) => x.isNotEmpty).join(' ');
    final source = camera
        ? l.readinessSeriesCamera(posture, device)
        : l.readinessSeriesOrigin(s.origin ?? '');
    // Markierung einer gesperrten Kamerareihe (PAR-171K): gestrichelt, ohne
    // Einfluss auf die Zahl; im Entwicklermodus keine Kennzeichnung.
    final mark = camera && key != null
        ? snapshot.effectiveRelease.forFactor(s.factor, key.posture).mark
        : MorningRmssdMark.none;
    final markText = readinessMarkText(l, mark);
    final latest = values.lastWhere((v) => v != null, orElse: () => null);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: RamuriCard(
        key: Key('readiness_series_$keyName'),
        radius: 24,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                if (latest != null)
                  Text(
                    readinessNumberText(l, latest, decimals),
                    key: Key('readiness_series_latest_$keyName'),
                    style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              source,
              key: Key('readiness_series_source_$keyName'),
              style: t.labelLarge?.copyWith(
                color: c.accent,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (markText != null)
              Text(
                markText,
                key: Key('readiness_series_mark_$keyName'),
                style: t.bodySmall?.copyWith(color: c.textMuted),
              ),
            if (s.fewMeasurements)
              Text(
                l.readinessReasonFewMeasurements,
                key: Key('readiness_series_few_$keyName'),
                style: t.bodySmall?.copyWith(color: c.textMuted),
              ),
            const SizedBox(height: 8),
            Semantics(
              label: l.readinessSeriesSemantics(title, sourceName, count),
              excludeSemantics: true,
              child: SizedBox(
                height: 90,
                width: double.infinity,
                child: CustomPaint(
                  key: Key('readiness_series_chart_$keyName'),
                  painter: ReadinessSeriesPainter(
                    values: values,
                    dashed: mark != MorningRmssdMark.none,
                    line: mark != MorningRmssdMark.none
                        ? c.textMuted
                        : c.accent,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Zeichnet die Werte als Linie mit Punkten; fehlende Tage unterbrechen die
/// Linie (Lücken bleiben Lücken). Eine eigene y-Achse je Reihe.
class ReadinessSeriesPainter extends CustomPainter {
  ReadinessSeriesPainter({
    required this.values,
    required this.dashed,
    required this.line,
  });

  final List<double?> values;
  final bool dashed;
  final Color line;

  /// Mindestspanne der y-Achse, damit eine flache Reihe nicht wie ein großer
  /// Sprung wirkt (relativ zum Mittel der Werte).
  static const double _minRelativeSpan = 0.1;

  @override
  void paint(Canvas canvas, Size size) {
    final present = [for (final v in values) ?v];
    if (present.isEmpty) return;
    var lo = present.reduce((a, b) => a < b ? a : b);
    var hi = present.reduce((a, b) => a > b ? a : b);
    final mid = (lo + hi) / 2;
    final minSpan = mid.abs() * _minRelativeSpan + 1e-6;
    if (hi - lo < minSpan) {
      lo = mid - minSpan / 2;
      hi = mid + minSpan / 2;
    }
    const pad = 6.0;
    final n = values.length;
    double x(int i) => pad + (size.width - 2 * pad) * i / (n - 1);
    double y(double v) =>
        pad + (size.height - 2 * pad) * (1 - (v - lo) / (hi - lo));
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..color = line;
    final dot = Paint()..color = line;
    var path = Path();
    var open = false;
    void flush() {
      if (!open) return;
      if (dashed) {
        for (final m in path.computeMetrics()) {
          for (var d = 0.0; d < m.length; d += 10) {
            canvas.drawPath(
              m.extractPath(d, (d + 5).clamp(0, m.length)),
              stroke,
            );
          }
        }
      } else {
        canvas.drawPath(path, stroke);
      }
      path = Path();
      open = false;
    }

    for (var i = 0; i < n; i++) {
      final v = values[i];
      if (v == null) {
        flush();
        continue;
      }
      final p = Offset(x(i), y(v));
      if (open) {
        path.lineTo(p.dx, p.dy);
      } else {
        path.moveTo(p.dx, p.dy);
        open = true;
      }
      canvas.drawCircle(p, 2.5, dot);
    }
    flush();
  }

  @override
  bool shouldRepaint(ReadinessSeriesPainter old) =>
      old.values != values || old.dashed != dashed || old.line != line;
}
