import 'package:core/core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../ui/ui.dart';
import 'readiness_card.dart' show ReadinessRing;
import 'readiness_history_screen.dart';
import 'readiness_service.dart';
import 'readiness_texts.dart';

/// Detailseite „Erholung“ (WP34 Teil D2, Design
/// `design/screens/readiness/Detail.dc.html`): Zahl oder eingeschränkte
/// Einschätzung, Zustand, Bänderskala, Datenlage mit Grund (PAR-159),
/// Ursachen (PAR-172), Faktoren mit Quelle, Gewicht und Teilwert, fehlende
/// Faktoren, markierte Tatsachen (PAR-171K) und das Modell `readiness v1`.
/// Beschreibt Daten, stellt keine Diagnose; der Entwicklermodus kennzeichnet
/// nichts (K62 Punkt 6), nur der unauffällige Hinweis steht da.
class ReadinessDetailScreen extends StatelessWidget {
  const ReadinessDetailScreen({
    super.key,
    required this.snapshot,
    this.warning = false,
  });

  final ReadinessSnapshot snapshot;

  /// Warnsignal aktiv (FR-0203): der feste Hinweis steht vor der Einschätzung.
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final r = snapshot.result;
    final facts = r.state == ReadinessState.limited
        ? r.facts.skip(2).toList()
        : const <ReadinessFact>[];
    final tatsachen = [...facts, ...r.markedFacts];
    return Scaffold(
      key: const Key('readiness_detail'),
      appBar: AppBar(title: Text(l.recoveryTitle)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (warning) ...[
              _Section(
                key: const Key('readiness_detail_warning'),
                child: Text(l.planWarnBannerText),
              ),
              const SizedBox(height: 16),
            ],
            _Assessment(result: r),
            const SizedBox(height: 16),
            _Section(
              key: const Key('readiness_detail_level'),
              title: l.readinessSectionLevel,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    readinessLevelWord(l, r.level),
                    key: const Key('readiness_detail_level_word'),
                    style: Theme.of(context).textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  for (var i = 0; i < r.levelReasons.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        readinessReasonText(l, r.levelReasons[i]),
                        key: Key('readiness_detail_reason_$i'),
                      ),
                    ),
                ],
              ),
            ),
            if (r.state == ReadinessState.number &&
                r.explanation.code != ReadinessExplanationCode.noNumber) ...[
              const SizedBox(height: 16),
              _Section(
                key: const Key('readiness_detail_drivers'),
                title: l.readinessSectionDrivers,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_driversText(l, r.explanation)),
                    const SizedBox(height: 6),
                    Text(
                      l.readinessDriversBasis,
                      key: const Key('readiness_detail_drivers_basis'),
                      style: _muted(context),
                    ),
                  ],
                ),
              ),
            ],
            if (r.state == ReadinessState.number && r.factors.isNotEmpty) ...[
              const SizedBox(height: 16),
              _Section(
                key: const Key('readiness_detail_factors'),
                title: l.readinessSectionFactors,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final f in r.factors) _FactorRow(factor: f),
                    const SizedBox(height: 8),
                    if (r.capped)
                      Text(l.readinessCappedNote, style: _muted(context)),
                    if (r.value != null)
                      Text(
                        l.readinessTotalNote(r.value!),
                        style: _muted(context),
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            _Section(
              key: const Key('readiness_detail_missing'),
              title: l.readinessSectionMissing,
              child: r.missing.isEmpty
                  ? Text(l.readinessMissingNone)
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final id in r.missing)
                          Padding(
                            key: Key('readiness_detail_missing_${id.name}'),
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _FactorHead(
                                  name: readinessFactorName(l, id),
                                  weight: readinessWeightOf(id),
                                ),
                                Text(
                                  readinessMissingText(l, id),
                                  style: _muted(context),
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 4),
                        Text(l.readinessMissingNever, style: _muted(context)),
                      ],
                    ),
            ),
            if (tatsachen.isNotEmpty) ...[
              const SizedBox(height: 16),
              _Section(
                key: const Key('readiness_detail_facts'),
                title: l.readinessSectionFacts,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.readinessFactsBasis,
                      key: const Key('readiness_detail_facts_basis'),
                      style: _muted(context),
                    ),
                    for (var i = 0; i < tatsachen.length; i++)
                      Padding(
                        key: Key('readiness_detail_fact_$i'),
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(readinessFactText(l, tatsachen[i])),
                            if (readinessMarkText(l, tatsachen[i].mark)
                                case final mark?)
                              Text(
                                mark,
                                style: _muted(context)
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            RamuriCard(
              key: const Key('readiness_detail_series_link'),
              radius: 24,
              padding: EdgeInsets.zero,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ReadinessHistoryScreen(snapshot: snapshot),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        l.readinessSeriesLink,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: RamuriColors.of(context).accent,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const Icon(Icons.chevron_right),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            _Section(
              key: const Key('readiness_detail_where_from'),
              title: l.readinessWhereFrom,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l.readinessWhereFromText),
                  const SizedBox(height: 8),
                  Text(
                    l.readinessWhereFromSources,
                    key: const Key('readiness_detail_model'),
                    style: _muted(context),
                  ),
                ],
              ),
            ),
            if (snapshot.developerMode)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Center(
                  child: Text(
                    l.morningDevActive,
                    key: const Key('readiness_detail_dev'),
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

TextStyle? _muted(BuildContext context) =>
    Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: RamuriColors.of(context).textMuted);

String _driversText(AppLocalizations l, ReadinessExplanation e) =>
    switch (e.code) {
      ReadinessExplanationCode.drivers => l.readinessDriversLine(
        e.drivers.map((d) => readinessDriverText(l, d)).join(', '),
      ),
      ReadinessExplanationCode.onlySleepBelow => l.readinessOnlySleepBelow(
        readinessDriverText(l, e.drivers.first),
      ),
      ReadinessExplanationCode.noDeviation => l.readinessNoDeviation,
      ReadinessExplanationCode.noNumber => '',
    };

class _Section extends StatelessWidget {
  const _Section({super.key, this.title, required this.child});

  final String? title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return RamuriCard(
      radius: 24,
      padding: const EdgeInsets.all(16),
      child: SizedBox(
        width: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title != null) ...[
              Semantics(
                header: true,
                child: Text(
                  title!,
                  style: t.labelLarge?.copyWith(
                    color: RamuriColors.of(context).textMuted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
            DefaultTextStyle.merge(style: t.bodyMedium, child: child),
          ],
        ),
      ),
    );
  }
}

/// Einschätzung oben: Ring, Zustand und Skala (Zahl) bzw. der Grund mit den
/// Tatsachen (eingeschränkt) oder der feste Satz (unzureichend).
class _Assessment extends StatelessWidget {
  const _Assessment({required this.result});

  final ReadinessResult result;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = Theme.of(context).textTheme;
    final c = RamuriColors.of(context);
    final r = result;
    final number = r.state == ReadinessState.number && r.value != null;
    final title = switch (r.state) {
      ReadinessState.number =>
        r.band == null ? '' : readinessBandName(l, r.band!),
      ReadinessState.limited => l.readinessLimitedTitle,
      ReadinessState.insufficient => l.readinessInsufficientTitle,
    };
    return _Section(
      key: Key('readiness_detail_case_${r.state.name}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Semantics(
                label: number
                    ? l.readinessRingValue(r.value!)
                    : l.readinessRingNone,
                excludeSemantics: true,
                child: ReadinessRing(
                  value: number ? r.value : null,
                  size: 96,
                  valueKey: const Key('readiness_detail_value'),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${l.recoveryTitle} · ${l.readinessStageExtended}'
                          .toUpperCase(),
                      style: t.labelMedium?.copyWith(
                        color: c.textLabel,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      title,
                      key: const Key('readiness_detail_title'),
                      style: t.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (number)
                      const EstimatedMark()
                    else
                      Text(
                        l.readinessNoNumber,
                        style: t.bodySmall?.copyWith(color: c.textMuted),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (number) ...[
            _Scale(value: r.value!, band: r.band!),
            const SizedBox(height: 10),
            Text(
              l.readinessNumberNote,
              style: t.bodySmall?.copyWith(color: c.textMuted),
            ),
          ] else if (r.state == ReadinessState.limited) ...[
            Text(
              key: const Key('readiness_detail_text'),
              readinessCardText(l, r),
            ),
            const SizedBox(height: 10),
            Text(
              l.readinessLimitedNeed,
              style: t.bodySmall?.copyWith(color: c.textMuted),
            ),
          ] else ...[
            Text(
              key: const Key('readiness_detail_text'),
              l.readinessInsufficientText,
            ),
            const SizedBox(height: 10),
            Text(
              l.readinessInsufficientNote,
              style: t.bodySmall?.copyWith(color: c.textMuted),
            ),
          ],
        ],
      ),
    );
  }
}

/// Bänderskala: vier feste Bänder (FR-0116), das aktuelle ist hervorgehoben.
class _Scale extends StatelessWidget {
  const _Scale({required this.value, required this.band});

  final int value;
  final ReadinessBand band;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = RamuriColors.of(context);
    final t = Theme.of(context).textTheme;
    const order = [
      ReadinessBand.recoveryAdvised,
      ReadinessBand.elevatedLoad,
      ReadinessBand.normal,
      ReadinessBand.wellRecovered,
    ];
    const ranges = ['0–24', '25–49', '50–74', '75–100'];
    final names = [for (final b in order) readinessBandName(l, b)];
    return Semantics(
      label: l.readinessScaleSemantics(
        names[0],
        names[1],
        names[2],
        names[3],
        value,
      ),
      excludeSemantics: true,
      child: Row(
        key: const Key('readiness_detail_scale'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < order.length; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    key: Key(
                      'readiness_detail_band_${order[i].name}'
                      '${order[i] == band ? '_current' : ''}',
                    ),
                    height: 10,
                    decoration: BoxDecoration(
                      color: order[i] == band ? c.accent : c.track,
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    ranges[i],
                    style: t.labelSmall?.copyWith(
                      color: order[i] == band ? c.text : c.textMuted,
                      fontWeight: order[i] == band
                          ? FontWeight.w800
                          : FontWeight.w500,
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
}

class _FactorHead extends StatelessWidget {
  const _FactorHead({required this.name, required this.weight, this.score});

  final String name;
  final double weight;
  final double? score;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = Theme.of(context).textTheme;
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      children: [
        Text(name, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
        Text(l.readinessWeight((weight * 100).round()), style: _muted(context)),
        if (score != null) Text(l.readinessPartScore(score!.round())),
      ],
    );
  }
}

class _FactorRow extends StatelessWidget {
  const _FactorRow({required this.factor});

  final ReadinessFactorValue factor;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final f = factor;
    final v = f.values;
    final unit = f.id == ReadinessFactorId.hrv ? 'ms' : '/min';
    String n(double x) => readinessNumberText(l, x, v!.decimals);
    final lines = [
      if (v != null)
        l.readinessFactorMeans(
          n(v.windowMean),
          n(v.referenceMedian),
          n(v.today),
          unit,
        ),
      if (v != null && v.todayIsFallback) l.readinessFactFallback,
      if (f.id == ReadinessFactorId.load) l.readinessLoadOnlyLowers,
      if (f.estimated) l.readinessDriverEstimated,
      if (f.fewMeasurements) l.readinessReasonFewMeasurements,
      ?readinessMarkText(l, f.mark),
    ];
    return Padding(
      key: Key('readiness_detail_factor_${f.id.name}'),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _FactorHead(
            name: readinessFactorName(l, f.id),
            weight: f.weight,
            score: f.score,
          ),
          for (final s in lines) Text(s, style: _muted(context)),
          Text(
            readinessSourceName(l, f.source),
            style: _muted(context)?.copyWith(
              color: RamuriColors.of(context).accent,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
