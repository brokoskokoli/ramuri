import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import '../../ui/ui.dart';

/// Eine Morgenmessung mit Gurt-RR und ihr Vergleich (nur im Speicher).
class BeltCompareEntry {
  const BeltCompareEntry({required this.stored, required this.result});

  final StoredMorningMeasurement stored;
  final MorningBeltCompareResult result;

  MorningMeasurement get m => stored.value;
}

/// Liest alle Morgenmessungen mit Gurt-RR und vergleicht sie (FR-0217),
/// neueste zuerst. Gerechnet wird beim Lesen, gespeichert wird nichts. Die
/// Rechnung je Messung ist klein (Versätze × Kamera-Abstände); zwischen den
/// Messungen gibt das Lesen aus dem Speicher die Oberfläche frei.
Future<List<BeltCompareEntry>> loadBeltCompareEntries(
  MorningStore store,
) async {
  final out = <BeltCompareEntry>[];
  for (final e in await store.list()) {
    final packets = await store.beltPackets(e.id);
    if (packets.isEmpty) continue;
    final m = e.value;
    out.add(
      BeltCompareEntry(
        stored: e,
        result: compareMorningWithBelt(
          m.cameraIntervalsMs,
          [for (final p in packets) p.value],
          cameraRmssdMs: m.rmssdMs,
          cameraRestingHrBpm: m.restingHrBpm,
        ),
      ),
    );
  }
  out.sort((a, b) {
    final t = b.m.measuredAt.compareTo(a.m.measuredAt);
    return t != 0 ? t : b.stored.id.compareTo(a.stored.id);
  });
  return out;
}

/// Zahlen mit einer Nachkommastelle; Differenzen mit sichtbarem Vorzeichen.
class _Fmt {
  _Fmt(String locale)
    : _nf = NumberFormat.decimalPatternDigits(locale: locale, decimalDigits: 1);

  final NumberFormat _nf;

  String v(double? x) => x == null ? '–' : _nf.format(x);

  String signed(double? x) {
    if (x == null) return '–';
    final s = _nf.format(x.abs());
    if (x > 0 && s != _nf.format(0)) return '+$s';
    if (x < 0 && s != _nf.format(0)) return '−$s';
    return s;
  }
}

String _localTime(BuildContext context, MorningMeasurement m) {
  final locale = Localizations.localeOf(context).toString();
  final local = m.measuredAt.toUtc().add(m.utcOffset);
  return DateFormat.yMd(locale).add_Hm().format(local);
}

String _meta(AppLocalizations l10n, MorningMeasurement m) {
  final pose = m.posture == RestingPosture.lying
      ? l10n.morningLegendLying
      : l10n.morningLegendSitting;
  final quality = switch (m.quality) {
    PpgQuality.good => l10n.morningQualityGood,
    PpgQuality.limited => l10n.morningQualityLimited,
    PpgQuality.unusable => l10n.devCompareQualityUnusable,
  };
  return '$pose · $quality';
}

/// Abschnitt „Kamera gegen Gurt“ der Entwicklereinstellungen (FR-0217): je
/// Morgenmessung mit Gurt-RR eine Zeile, neueste zuerst; Tipp öffnet das
/// Detail. Nur Anzeige: nichts geht in Readiness, Trends oder Export, nichts in
/// Logs.
class BeltCompareSection extends StatefulWidget {
  const BeltCompareSection({super.key, required this.store});

  final MorningStore store;

  @override
  State<BeltCompareSection> createState() => _BeltCompareSectionState();
}

class _BeltCompareSectionState extends State<BeltCompareSection> {
  late final Future<List<BeltCompareEntry>?> _entries = _load();

  Future<List<BeltCompareEntry>?> _load() async {
    try {
      return await loadBeltCompareEntries(widget.store);
    } on Object {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = RamuriColors.of(context);
    final theme = Theme.of(context).textTheme;
    return Padding(
      key: const Key('dev_compare'),
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: FutureBuilder<List<BeltCompareEntry>?>(
        future: _entries,
        builder: (context, snap) {
          final entries = snap.data;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: Text(
                  l10n.devCompareTitle,
                  style: theme.titleSmall!.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                l10n.devCompareIntro,
                style: theme.bodySmall!.copyWith(color: c.textMuted),
              ),
              if (snap.connectionState == ConnectionState.done) ...[
                const SizedBox(height: 6),
                if (entries == null)
                  const Text('–')
                else if (entries.isEmpty)
                  Text(
                    l10n.devCompareEmpty,
                    key: const Key('dev_compare_empty'),
                    style: theme.bodyMedium,
                  )
                else
                  for (final e in entries) _Row(entry: e, store: widget.store),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.entry, required this.store});

  final BeltCompareEntry entry;
  final MorningStore store;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = RamuriColors.of(context);
    final theme = Theme.of(context).textTheme;
    final f = _Fmt(Localizations.localeOf(context).toString());
    final m = entry.m;
    final r = entry.result;
    final lines = switch (r) {
      MorningBeltNoMatch() => [l10n.devCompareNoMatch],
      MorningBeltComparison() => [
        l10n.devCompareRmssd(f.v(m.rmssdMs), f.v(r.beltRmssdMs)),
        l10n.devCompareDiff(
          f.signed(r.rmssdDiffMs),
          f.signed(r.rmssdDiffPercent),
        ),
      ],
    };
    return InkWell(
      key: Key('dev_compare_row_${entry.stored.id}'),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => BeltCompareDetailScreen(
            entry: entry,
            rawSignal: () => store.rawSignal(entry.stored.id),
          ),
        ),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_localTime(context, m)} · ${_meta(l10n, m)}',
                      style: theme.bodyMedium!.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    for (final t in lines)
                      Text(
                        t,
                        style: theme.bodySmall!.copyWith(color: c.textMuted),
                      ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: c.textSoft),
            ],
          ),
        ),
      ),
    );
  }
}

/// Detail einer Morgenmessung gegen den Gurt (FR-0217): alle Kennwerte, Kamera
/// aus dem Rohsignal (sonst „unbekannt“) und die Kurve der Schlagabstände.
class BeltCompareDetailScreen extends StatefulWidget {
  const BeltCompareDetailScreen({
    super.key,
    required this.entry,
    this.rawSignal,
  });

  final BeltCompareEntry entry;

  /// Lädt das Rohsignal für die Kamera-Angabe; ohne: „unbekannt“.
  final Future<MorningRawSignal?> Function()? rawSignal;

  @override
  State<BeltCompareDetailScreen> createState() =>
      _BeltCompareDetailScreenState();
}

class _BeltCompareDetailScreenState extends State<BeltCompareDetailScreen> {
  late final Future<MorningRawSignal?> _rawSignal = _raw();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = RamuriColors.of(context);
    final theme = Theme.of(context).textTheme;
    final f = _Fmt(Localizations.localeOf(context).toString());
    final m = widget.entry.m;
    final r = widget.entry.result;
    final cmp = r is MorningBeltComparison ? r : null;
    String ms(double? v) => v == null ? '–' : l10n.devCompareMs(f.v(v));
    String bpm(double? v) => v == null ? '–' : l10n.devCompareBpm(f.v(v));
    final validCount = m.cameraIntervalsMs.where((v) => v.isFinite).length;
    final ws = m.windowStartS, we = m.windowEndS;
    final rows = <(String, String, String)>[
      ('rmssd_camera', l10n.devCompareRmssdCamera, ms(m.rmssdMs)),
      ('rmssd_belt', l10n.devCompareRmssdBelt, ms(cmp?.beltRmssdMs)),
      (
        'rmssd_diff',
        l10n.devCompareRmssdDiff,
        cmp?.rmssdDiffMs == null
            ? '–'
            : l10n.devCompareDiffMs(
                f.signed(cmp!.rmssdDiffMs),
                f.signed(cmp.rmssdDiffPercent),
              ),
      ),
      ('hr_camera', l10n.devCompareHrCamera, bpm(m.restingHrBpm)),
      ('hr_belt', l10n.devCompareHrBelt, bpm(cmp?.beltRestingHrBpm)),
      (
        'hr_diff',
        l10n.devCompareHrDiff,
        cmp?.restingHrDiffBpm == null
            ? '–'
            : l10n.devCompareDiffBpm(
                f.signed(cmp!.restingHrDiffBpm),
                f.signed(cmp.restingHrDiffPercent),
              ),
      ),
      (
        'paired',
        l10n.devComparePaired,
        cmp == null
            ? '–'
            : l10n.devComparePairedValue(
                f.v(cmp.pairedCameraRmssdMs),
                f.v(cmp.pairedBeltRmssdMs),
                cmp.pairedDiffCount,
              ),
      ),
      ('error', l10n.devCompareIbiError, ms(cmp?.ibiErrorMs)),
      ('noise', l10n.devCompareNoise, ms(m.timingNoiseMs)),
      (
        'valid',
        l10n.devCompareValid,
        l10n.devCompareValidValue(validCount, m.cameraIntervalsMs.length),
      ),
      (
        'window',
        l10n.devCompareWindow,
        ws == null || we == null
            ? '–'
            : l10n.devCompareWindowValue(f.v(ws), f.v(we)),
      ),
    ];
    Widget row(String key, String label, Widget value) => MergeSemantics(
      child: Padding(
        key: Key('dev_compare_detail_$key'),
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                label,
                style: theme.bodyMedium!.copyWith(color: c.textMuted),
              ),
            ),
            const SizedBox(width: 12),
            Flexible(child: value),
          ],
        ),
      ),
    );
    Text value(String s) => Text(
      s,
      textAlign: TextAlign.end,
      style: theme.bodyMedium!.copyWith(fontWeight: FontWeight.w700),
    );
    return Scaffold(
      appBar: AppBar(title: Text(l10n.devCompareTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '${_localTime(context, m)} · ${_meta(l10n, m)}',
            style: theme.titleSmall!.copyWith(fontWeight: FontWeight.w800),
          ),
          if (cmp == null) ...[
            const SizedBox(height: 4),
            Text(
              l10n.devCompareNoMatch,
              key: const Key('dev_compare_detail_no_match'),
              style: theme.bodyMedium,
            ),
          ],
          const SizedBox(height: 8),
          RamuriCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Column(
              children: [
                for (final (k, label, v) in rows) row(k, label, value(v)),
                row(
                  'camera',
                  l10n.devCompareCamera,
                  FutureBuilder<MorningRawSignal?>(
                    future: _rawSignal,
                    builder: (context, snap) {
                      if (snap.connectionState != ConnectionState.done) {
                        return value('');
                      }
                      final raw = snap.data;
                      final id = raw?.cameraId;
                      if (id == null) {
                        return value(l10n.devCompareCameraUnknown);
                      }
                      final phys = raw!.physicalCameraId;
                      return value(
                        l10n.devCameraName(phys == null ? id : '$id/$phys'),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          if (cmp != null) ...[
            const SizedBox(height: 12),
            RamuriCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Semantics(
                    container: true,
                    image: true,
                    excludeSemantics: true,
                    label: l10n.devCompareChart(
                      f.v(cmp.pairedCameraRmssdMs),
                      f.v(cmp.pairedBeltRmssdMs),
                      f.v(cmp.ibiErrorMs),
                      cmp.pairCount,
                    ),
                    child: CustomPaint(
                      key: const Key('dev_compare_chart'),
                      size: const Size(double.infinity, 200),
                      painter: BeltComparePainter(
                        camera: cmp.cameraIbiMs,
                        belt: cmp.beltWindowMs,
                        line: c.action,
                        dot: c.ember,
                        grid: c.outline,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ExcludeSemantics(
                    child: Text(
                      l10n.devCompareLegend,
                      style: theme.bodySmall!.copyWith(color: c.textMuted),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<MorningRawSignal?> _raw() async {
    final load = widget.rawSignal;
    if (load == null) return null;
    try {
      return await load();
    } on Object {
      return null;
    }
  }
}

/// Kurve der Schlagabstände: x = Nummer im Fenster, y = Abstand in ms. Gurt
/// als Linie (Lücken bei fehlenden oder ungültigen Werten), Kamera als Punkte
/// (ungültige ausgelassen).
class BeltComparePainter extends CustomPainter {
  BeltComparePainter({
    required this.camera,
    required this.belt,
    required this.line,
    required this.dot,
    required this.grid,
  });

  final List<double> camera;
  final List<double?> belt;
  final Color line;
  final Color dot;
  final Color grid;

  @override
  void paint(Canvas canvas, Size size) {
    final values = [
      for (final v in camera)
        if (v.isFinite) v,
      for (final v in belt) ?v,
    ];
    final n = camera.length;
    if (values.isEmpty || n == 0) return;
    var lo = values.reduce((a, b) => a < b ? a : b);
    var hi = values.reduce((a, b) => a > b ? a : b);
    if (hi - lo < 50) {
      final mid = (hi + lo) / 2;
      lo = mid - 25;
      hi = mid + 25;
    }
    const pad = 8.0;
    double x(int i) =>
        n == 1 ? size.width / 2 : pad + (size.width - 2 * pad) * i / (n - 1);
    double y(double v) =>
        pad + (size.height - 2 * pad) * (1 - (v - lo) / (hi - lo));
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      gridPaint..style = PaintingStyle.stroke,
    );
    final linePaint = Paint()
      ..color = line
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i + 1 < belt.length; i++) {
      final a = belt[i], b = belt[i + 1];
      if (a == null || b == null) continue;
      canvas.drawLine(Offset(x(i), y(a)), Offset(x(i + 1), y(b)), linePaint);
    }
    final dotPaint = Paint()..color = dot;
    for (var i = 0; i < n; i++) {
      final v = camera[i];
      if (!v.isFinite) continue;
      canvas.drawCircle(Offset(x(i), y(v)), 3, dotPaint);
    }
  }

  @override
  bool shouldRepaint(BeltComparePainter old) =>
      old.camera != camera ||
      old.belt != belt ||
      old.line != line ||
      old.dot != dot ||
      old.grid != grid;
}
