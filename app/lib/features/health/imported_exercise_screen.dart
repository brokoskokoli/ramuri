import 'package:core/core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../ui/ui.dart';
import '../history/manual_training_screen.dart';

/// Ortszeit des Beginns einer importierten Einheit: Zonenversatz des
/// Datensatzes, sonst der der Uhr zum Beginn.
DateTime importedExerciseLocalStart(HealthRecord e, Clock clock) {
  final offset = e.offsetSeconds == null
      ? clock.utcOffsetAt(e.start)
      : Duration(seconds: e.offsetSeconds!);
  return e.start.toUtc().add(offset);
}

/// Anzeigename der Art einer importierten Einheit.
String importedExerciseKindText(AppLocalizations l10n, HealthRecord e) =>
    isRunningExercise(e.exerciseType)
    ? l10n.healthExerciseRun
    : l10n.healthExerciseOther;

/// Detail einer aus Health Connect importierten Trainingseinheit (WP32 Teil E,
/// K62 F2, SEC-0005): Art, Beginn, Dauer, Quell-App und Pulskurve, nur zur
/// Anzeige (keine Zonen, keine Berechnung). Die Einheit zählt für Belastung,
/// Pausenregel und Plan erst nach „Als Training übernehmen“: Das öffnet den
/// Nachtrag nach FR-0199 mit vorausgefüllter Dauer; die Anstrengung (RPE) fragt
/// die App. Der Puls geht nie in den Nachtrag ein. Eine schon übernommene
/// Einheit zeigt „übernommen“ statt des Knopfs.
class ImportedExerciseScreen extends StatefulWidget {
  const ImportedExerciseScreen({
    super.key,
    required this.exercise,
    required this.session,
    required this.clock,
    required this.today,
  });

  final HealthRecord exercise;
  final StorageSession session;
  final Clock clock;

  /// Heutiger Ortstag (`JJJJ-MM-TT`).
  final String today;

  @override
  State<ImportedExerciseScreen> createState() => _ImportedExerciseScreenState();
}

class _Loaded {
  const _Loaded(this.heartRate, this.adopted);
  final List<HealthHeartRateSample> heartRate;
  final bool adopted;
}

class _ImportedExerciseScreenState extends State<ImportedExerciseScreen> {
  late Future<_Loaded> _future = _load();

  SubjectiveService get _subjective =>
      SubjectiveService(session: widget.session, clock: widget.clock);

  Future<_Loaded> _load() async {
    final session = widget.session;
    final hr = session is HealthStorage
        ? await (session as HealthStorage).health.exerciseHeartRate(
            widget.exercise.id,
          )
        : const <HealthHeartRateSample>[];
    return _Loaded(hr, await _subjective.isAdopted(widget.exercise.id));
  }

  Future<void> _adopt() async {
    final e = widget.exercise;
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ManualTrainingScreen(
          service: _subjective,
          today: widget.today,
          prefill: ManualTrainingPrefill(
            day: exerciseLocalDay(e, widget.clock.utcOffsetAt(e.start)),
            kind: manualKindOfExercise(e.exerciseType),
            minutes: exerciseMinutes(e),
            hcId: e.id,
          ),
        ),
      ),
    );
    if (mounted && saved == true) {
      setState(() {
        _future = _load();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final material = MaterialLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final c = RamuriColors.of(context);
    final e = widget.exercise;
    final local = importedExerciseLocalStart(e, widget.clock);
    final minutes = exerciseMinutes(e);
    final when =
        '${material.formatMediumDate(local)} · '
        '${material.formatTimeOfDay(TimeOfDay.fromDateTime(local))}';
    return Scaffold(
      appBar: AppBar(
        title: Text(
          importedExerciseKindText(l10n, e),
          key: const Key('health_detail_title'),
        ),
      ),
      body: SafeArea(
        child: FutureBuilder<_Loaded>(
          future: _future,
          builder: (context, snapshot) {
            final data = snapshot.data;
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  when,
                  key: const Key('health_detail_when'),
                  style: text.titleSmall,
                ),
                const SizedBox(height: 12),
                RamuriCard(
                  tone: RamuriCardTone.accent,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.healthDetailOrigin(e.origin),
                        key: const Key('health_detail_origin'),
                        style: text.titleSmall,
                      ),
                      const SizedBox(height: 2),
                      Text(l10n.healthDetailOriginNote, style: text.bodySmall),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                RamuriCard(
                  child: Row(
                    children: [
                      Expanded(
                        child: _Fact(
                          label: l10n.healthDetailKind,
                          value: importedExerciseKindText(l10n, e),
                          valueKey: const Key('health_detail_kind'),
                        ),
                      ),
                      Expanded(
                        child: _Fact(
                          label: l10n.healthDetailDuration,
                          value: l10n.healthDetailMinutes('$minutes'),
                          valueKey: const Key('health_detail_duration'),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                RamuriCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SectionHeading(
                        l10n.healthDetailPulse,
                        eyebrow: true,
                        trailing: Text(
                          l10n.healthDetailDisplayOnly,
                          style: text.bodySmall?.copyWith(color: c.textMuted),
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (data == null)
                        const SizedBox(height: 140)
                      else if (data.heartRate.length < 2)
                        Text(
                          l10n.healthDetailPulseNone,
                          key: const Key('health_detail_pulse_none'),
                          style: text.bodyMedium,
                        )
                      else
                        HealthPulseChart(
                          key: const Key('health_detail_pulse'),
                          samples: data.heartRate,
                          semanticLabel: l10n.healthDetailPulseSemantics(
                            data.heartRate.length,
                          ),
                        ),
                      const SizedBox(height: 8),
                      Text(
                        l10n.healthDetailPulseNote,
                        style: text.bodySmall?.copyWith(color: c.textMuted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                if (data != null && data.adopted)
                  RamuriCard(
                    key: const Key('health_taken'),
                    tone: RamuriCardTone.accent,
                    child: Semantics(
                      liveRegion: true,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(l10n.healthTakenTitle, style: text.titleSmall),
                          const SizedBox(height: 2),
                          Text(l10n.healthTakenBody, style: text.bodySmall),
                        ],
                      ),
                    ),
                  )
                else if (data != null)
                  RamuriCard(
                    key: const Key('health_take_card'),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          l10n.healthTakeNote,
                          key: const Key('health_take_note'),
                          style: text.bodyMedium,
                        ),
                        const SizedBox(height: 12),
                        RamuriPrimaryButton(
                          key: const Key('health_take'),
                          label: l10n.healthTakeButton,
                          onPressed: _adopt,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          l10n.healthTakeHint,
                          key: const Key('health_take_hint'),
                          style: text.bodySmall?.copyWith(color: c.textMuted),
                        ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({
    required this.label,
    required this.value,
    required this.valueKey,
  });

  final String label;
  final String value;
  final Key valueKey;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final c = RamuriColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: text.bodySmall?.copyWith(color: c.textMuted)),
        Text(value, key: valueKey, style: text.titleMedium),
      ],
    );
  }
}

/// Pulskurve einer importierten Einheit, nur Anzeige: Linie mit den beiden
/// Achsenenden (kleinster und größter dargestellter Wert), keine Zonen, kein
/// Mittelwert. Sehr lange Reihen werden zum Zeichnen ausgedünnt.
class HealthPulseChart extends StatelessWidget {
  const HealthPulseChart({
    super.key,
    required this.samples,
    required this.semanticLabel,
    this.height = 140,
  });

  final List<HealthHeartRateSample> samples;
  final String semanticLabel;
  final double height;

  static const _maxPoints = 300;

  @override
  Widget build(BuildContext context) {
    final c = RamuriColors.of(context);
    final text = Theme.of(context).textTheme;
    final step = (samples.length / _maxPoints).ceil().clamp(1, 1 << 30);
    final shown = [for (var i = 0; i < samples.length; i += step) samples[i]];
    final bpm = [for (final s in shown) s.beatsPerMinute];
    var lo = bpm.reduce((a, b) => a < b ? a : b);
    var hi = bpm.reduce((a, b) => a > b ? a : b);
    return Semantics(
      container: true,
      image: true,
      excludeSemantics: true,
      label: semanticLabel,
      child: SizedBox(
        height: height,
        child: Row(
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('$hi', style: text.bodySmall),
                Text('$lo', style: text.bodySmall),
              ],
            ),
            const SizedBox(width: 8),
            Expanded(
              child: CustomPaint(
                size: Size.infinite,
                painter: _PulsePainter(
                  [for (final v in bpm) v.toDouble()],
                  c.accent,
                  c.outline,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PulsePainter extends CustomPainter {
  const _PulsePainter(this.values, this.line, this.grid);
  final List<double> values;
  final Color line;
  final Color grid;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    var lo = values.reduce((a, b) => a < b ? a : b);
    var hi = values.reduce((a, b) => a > b ? a : b);
    if (hi - lo < 1) hi = lo + 1;
    const pad = 2.0;
    final w = size.width - 2 * pad;
    final h = size.height - 2 * pad;
    canvas.drawLine(
      Offset(0, pad),
      Offset(size.width, pad),
      Paint()..color = grid,
    );
    canvas.drawLine(
      Offset(0, size.height - pad),
      Offset(size.width, size.height - pad),
      Paint()..color = grid,
    );
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final p = Offset(
        pad + w * i / (values.length - 1),
        pad + h * (1 - (values[i] - lo) / (hi - lo)),
      );
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_PulsePainter old) =>
      old.values != values || old.line != line || old.grid != grid;
}
