import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import '../../offload_scope.dart';
import '../../ui/ui.dart';
import '../home/data_changes.dart';
import '../settings/app_settings.dart';
import '../settings/unit_format.dart';
import 'prediction_controller.dart';
import 'reference_form.dart';

/// Karte „Prognose“ auf Fortschritt (WP20 Teil C, FR-0128 bis FR-0134).
///
/// Vier Zeilen (5 km, 10 km, Halbmarathon, Marathon) mit Zeit auf die Minute
/// („≈ 52 min“), der Stufe als Wort mit Grund und der sichtbaren Referenz. Es
/// ist die allgemeine Schätzung, unabhängig von Ziel und Plan (FR-0133). Keine
/// Prozente, keine Spanne, keine Sicherheitsaussage (FR-0054). Ist die Zeit
/// nicht bestimmbar, steht der Grund statt einer Zeit; aus der VO₂max allein
/// entsteht nie eine Zeit (FR-0134).
///
/// Läuft der Speicher ohne Prognose-Daten, zeigt die Karte nichts.
class PredictionCard extends StatefulWidget {
  const PredictionCard({
    super.key,
    required this.session,
    required this.clock,
    this.hasVo2maxEstimate = false,
    this.changes,
    this.onFirstSettled,
  });

  final StorageSession session;
  final Clock clock;

  /// Gibt es eine VO₂max-Schätzung? Sie ändert nie eine Zeit, nur den Grund.
  final bool hasVo2maxEstimate;

  /// Meldet nach Eintragen, Löschen, Bestätigen und Ablehnen die Änderung der
  /// Daten (`DataChanges`).
  final DataChanges? changes;

  /// Einmal, nachdem die Karte ihre endgültige Höhe hat (Ergebnis oder Fehler
  /// statt „wird berechnet“); die Seite stellt dann ihre Scrollposition wieder
  /// her (wie bei der Karte Belastung).
  final VoidCallback? onFirstSettled;

  @override
  State<PredictionCard> createState() => _PredictionCardState();
}

class _PredictionCardState extends State<PredictionCard> {
  PredictionController? _controller;

  @override
  void initState() {
    super.initState();
    if (widget.session is PredictionStorage) {
      _controller = PredictionController(
        session: widget.session,
        clock: widget.clock,
        hasVo2maxEstimate: widget.hasVo2maxEstimate,
        offload: OffloadScope.of(context),
        onChanged: widget.changes?.changed,
      )..addListener(_reportSettled);
      _reportSettled();
    }
  }

  bool _settledReported = false;

  void _reportSettled() {
    final c = _controller;
    if (_settledReported ||
        c == null ||
        c.state.phase == PredictionPhase.loading) {
      return;
    }
    _settledReported = true;
    // Nach dem Layout mit der neuen Höhe, nicht davor.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onFirstSettled?.call();
    });
  }

  @override
  void dispose() {
    _controller?.removeListener(_reportSettled);
    _controller?.dispose();
    super.dispose();
  }

  PredictionController get _c => _controller!;

  Future<void> _run(Future<bool> action) async {
    final ok = await action;
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).predictionActionFailed),
        ),
      );
    }
  }

  Future<void> _add() async {
    final reference = await showReferenceForm(
      context,
      now: widget.clock.now(),
      formatter: AppSettingsScope.formatterOf(context),
    );
    if (reference != null) await _run(_c.addReference(reference));
  }

  /// Fragt vor dem Löschen und nennt die Referenz, die danach gilt.
  Future<void> _delete(StoredReference target) async {
    final l10n = AppLocalizations.of(context);
    final formatter = AppSettingsScope.formatterOf(context);
    final lang = Localizations.localeOf(context).languageCode;
    final rest = [
      for (final s in _c.state.all)
        if (s.id != target.id) s,
    ];
    final body = rest.isEmpty
        ? l10n.predictionDeleteBodyNone
        : l10n.predictionDeleteBodyNext(
            predictionKindText(l10n, rest.first.reference.kind),
            formatter.distance(rest.first.reference.distanceMeters),
            clockTimeText(rest.first.reference.seconds),
            DateFormat.yMMMd(lang).format(rest.first.reference.date),
          );
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.predictionDeleteTitle),
        content: Text(body, key: const Key('prediction_delete_body')),
        actions: [
          TextButton(
            key: const Key('prediction_delete_cancel'),
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.predictionCancel),
          ),
          TextButton(
            key: const Key('prediction_delete_confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.predictionDelete),
          ),
        ],
      ),
    );
    if (sure == true) await _run(_c.deleteReference(target.id));
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) => _body(context, controller.state),
      ),
    );
  }

  Widget _body(BuildContext context, PredictionViewState state) {
    final l10n = AppLocalizations.of(context);
    final c = RamuriColors.of(context);
    final theme = Theme.of(context).textTheme;
    final formatter = AppSettingsScope.formatterOf(context);
    final prediction = state.prediction;

    final children = <Widget>[
      SectionHeading(
        l10n.predictionTitle,
        trailing: RamuriBadge(l10n.progressEstimateBadge),
      ),
      const SizedBox(height: 4),
      Text(
        l10n.predictionSubtitle,
        key: const Key('prediction_subtitle'),
        style: theme.bodySmall!.copyWith(color: c.textMuted),
      ),
      const SizedBox(height: 10),
    ];

    switch (state.phase) {
      case PredictionPhase.loading:
        children.add(
          Text(
            l10n.predictionLoading,
            key: const Key('prediction_loading'),
            style: theme.bodyMedium!.copyWith(color: c.textMuted),
          ),
        );
      case PredictionPhase.failed:
        children
          ..add(
            Text(
              l10n.predictionLoadFailed,
              key: const Key('prediction_failed'),
              style: theme.bodyMedium,
            ),
          )
          ..add(
            _Action(
              key: const Key('prediction_retry'),
              label: l10n.predictionRetry,
              onPressed: _c.reload,
            ),
          );
      case PredictionPhase.ready:
        children.addAll(_ready(context, state, prediction!, formatter));
    }

    return RamuriCard(
      radius: 22,
      padding: const EdgeInsets.all(16),
      child: Column(
        key: const Key('prediction_card'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  List<Widget> _ready(
    BuildContext context,
    PredictionViewState state,
    PerformancePrediction prediction,
    UnitFormatter formatter,
  ) {
    final l10n = AppLocalizations.of(context);
    final c = RamuriColors.of(context);
    final theme = Theme.of(context).textTheme;
    final lang = Localizations.localeOf(context).languageCode;
    final allUndetermined = prediction.distances.every(
      (d) => d.level == PredictionLevel.notDeterminable,
    );
    final out = <Widget>[];

    // Die Referenz, auf der die Zeiten beruhen, immer sichtbar.
    final active = state.active?.reference;
    out.add(
      Text(
        active == null
            ? l10n.predictionNoReference
            : l10n.predictionReferenceLine(
                predictionKindText(l10n, active.kind),
                formatter.distance(active.distanceMeters),
                clockTimeText(active.seconds),
                DateFormat.yMMMd(lang).format(active.date),
              ),
        key: const Key('prediction_reference'),
        style: theme.bodySmall!.copyWith(color: c.textMuted),
      ),
    );
    out.add(const SizedBox(height: 8));

    for (var i = 0; i < prediction.distances.length; i++) {
      out.add(
        _DistanceRow(
          index: i,
          row: prediction.distances[i],
          formatter: formatter,
          showLevel: !allUndetermined,
        ),
      );
    }
    if (allUndetermined) {
      final reason = prediction.distances.first.reason;
      out
        ..add(const SizedBox(height: 6))
        ..add(
          Text(
            l10n.predictionNoneForAll(predictionReasonText(l10n, reason)),
            key: const Key('prediction_reason'),
            style: theme.bodyMedium,
          ),
        );
    }
    if (state.showTestHint) {
      out
        ..add(const SizedBox(height: 8))
        ..add(
          Text(
            l10n.predictionTestHint,
            key: const Key('prediction_test_hint'),
            style: theme.bodyMedium,
          ),
        );
    }

    final suggestion = state.suggestion;
    if (suggestion != null) {
      out
        ..add(const SizedBox(height: 12))
        ..add(_suggestion(context, suggestion, formatter));
    }

    out.add(const SizedBox(height: 4));
    out.add(
      Wrap(
        spacing: 8,
        children: [
          _Action(
            key: const Key('prediction_add'),
            label: l10n.predictionAddReference,
            onPressed: _c.busy ? null : _add,
          ),
          if (state.active != null)
            _Action(
              key: const Key('prediction_delete'),
              label: l10n.predictionDeleteReference,
              onPressed: _c.busy ? null : () => _delete(state.active!),
            ),
          _Action(
            key: const Key('prediction_explain'),
            label: l10n.predictionExplainLink,
            onPressed: () => _explain(context, prediction.metadata),
          ),
        ],
      ),
    );
    final others = state.others;
    if (others.isNotEmpty) {
      out
        ..add(const SizedBox(height: 8))
        ..add(
          Text(
            l10n.predictionOtherReferences(others.length),
            key: const Key('prediction_others'),
            style: theme.bodySmall!.copyWith(color: c.textMuted),
          ),
        );
      for (final s in others) {
        final r = s.reference;
        final line = l10n.predictionReferenceLine(
          predictionKindText(l10n, r.kind),
          formatter.distance(r.distanceMeters),
          clockTimeText(r.seconds),
          DateFormat.yMMMd(lang).format(r.date),
        );
        // Unbrauchbare Referenz (z. B. importiert außerhalb der Tempospanne):
        // sichtbar und löschbar, aber als ungültig gekennzeichnet.
        final summary = isUsableReference(r)
            ? line
            : l10n.planReferenceInvalid(line);
        out.add(
          Row(
            children: [
              Expanded(
                child: Text(
                  summary,
                  key: Key('prediction_other_${s.id}'),
                  style: theme.bodySmall,
                ),
              ),
              IconButton(
                key: Key('prediction_other_delete_${s.id}'),
                tooltip: l10n.predictionDeleteOther(summary),
                constraints: const BoxConstraints(
                  minWidth: RamuriTheme.minTarget,
                  minHeight: RamuriTheme.minTarget,
                ),
                icon: const Icon(Icons.delete_outline),
                onPressed: _c.busy ? null : () => _delete(s),
              ),
            ],
          ),
        );
      }
    }
    return out;
  }

  Widget _suggestion(
    BuildContext context,
    ReferenceSuggestion s,
    UnitFormatter formatter,
  ) {
    final l10n = AppLocalizations.of(context);
    final c = RamuriColors.of(context);
    final theme = Theme.of(context).textTheme;
    final lang = Localizations.localeOf(context).languageCode;
    return DecoratedBox(
      key: const Key('prediction_suggestion'),
      decoration: BoxDecoration(
        color: c.tint,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text(
                l10n.predictionSuggestionTitle,
                style: theme.labelLarge!.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              l10n.predictionSuggestionBody(
                DateFormat.yMMMd(lang).format(s.run.date),
                formatter.distance(s.run.distanceMeters),
                clockTimeText(s.run.movingSeconds),
              ),
              key: const Key('prediction_suggestion_text'),
              style: theme.bodyMedium,
            ),
            for (final b in s.branches)
              Text(switch (b) {
                SuggestionBranch.hardAndSteady => l10n.predictionSuggestionHard,
                SuggestionBranch.beatsReference =>
                  l10n.predictionSuggestionBeats,
              }, style: theme.bodySmall!.copyWith(color: c.textMuted)),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              children: [
                _Action(
                  key: const Key('prediction_suggestion_accept'),
                  label: l10n.predictionSuggestionAccept,
                  onPressed: _c.busy
                      ? null
                      : () => _run(_c.acceptSuggestion(s)),
                ),
                _Action(
                  key: const Key('prediction_suggestion_reject'),
                  label: l10n.predictionSuggestionReject,
                  onPressed: _c.busy
                      ? null
                      : () => _run(_c.rejectSuggestion(s)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _explain(BuildContext context, PredictionMetadata m) {
    final l10n = AppLocalizations.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final day = DateFormat.yMMMd(lang);
    final period = m.dataFrom == null
        ? l10n.predictionExplainPeriodNone(day.format(m.dataTo))
        : l10n.predictionExplainPeriodValue(
            day.format(m.dataFrom!),
            day.format(m.dataTo),
          );
    final sources = m.sources.isEmpty
        ? l10n.predictionExplainSourcesNone
        : m.sources.map((s) => predictionSourceText(l10n, s)).join(', ');
    final rows = <(String, String, String)>[
      (
        l10n.predictionExplainCalculated,
        DateFormat.yMMMd(lang).add_Hm().format(m.calculatedAt.toLocal()),
        'calculated',
      ),
      (l10n.predictionExplainPeriod, period, 'period'),
      (l10n.predictionExplainCount, '${m.measurementCount}', 'count'),
      (l10n.predictionExplainSources, sources, 'sources'),
      (
        l10n.predictionExplainMethod,
        l10n.predictionExplainMethodValue(m.method, m.methodVersion),
        'method',
      ),
      (
        l10n.predictionExplainLevel,
        predictionLevelText(l10n, m.level),
        'level',
      ),
    ];
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('prediction_explain_dialog'),
        title: Text(l10n.predictionExplainTitle),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.predictionExplainBody),
              for (final (label, value, id) in rows) ...[
                const SizedBox(height: 12),
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelMedium!
                      .copyWith(color: RamuriColors.of(context).textMuted),
                ),
                Text(value, key: Key('prediction_explain_$id')),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            key: const Key('prediction_explain_close'),
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.predictionExplainClose),
          ),
        ],
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({super.key, required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    // Vordergrund aus dem Textknopf-Theme (`accent`): `action` ist für dunkle
    // Flächen und gefüllte Knöpfe, auf der hellen Karte unlesbar.
    return TextButton(
      style: TextButton.styleFrom(
        minimumSize: const Size(0, RamuriTheme.minTarget),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        textStyle: RamuriType.of(context).link,
      ),
      onPressed: onPressed,
      child: Text(label),
    );
  }
}

class _DistanceRow extends StatelessWidget {
  const _DistanceRow({
    required this.index,
    required this.row,
    required this.formatter,
    required this.showLevel,
  });

  final int index;
  final DistancePrediction row;
  final UnitFormatter formatter;

  /// Stufe und Grund je Zeile; bei „nicht bestimmbar“ für alle steht der Grund
  /// einmal unter den Zeilen.
  final bool showLevel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = RamuriColors.of(context);
    final theme = Theme.of(context).textTheme;
    final seconds = row.seconds;
    final name = predictionDistanceName(l10n, row.distance);
    final label = formatter.unit == DistanceUnit.miles
        ? l10n.predictionDistanceWithUnit(
            name,
            formatter.distance(row.distance.meters),
          )
        : name;
    final value = seconds == null
        ? l10n.predictionNoTime
        : predictionTimeText(l10n, seconds);
    final level = l10n.predictionLevelWithReason(
      predictionLevelText(l10n, row.level),
      predictionReasonText(l10n, row.reason),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: MergeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Expanded(
                  child: Text(
                    label,
                    key: Key('prediction_label_$index'),
                    style: theme.bodyMedium!.copyWith(
                      fontWeight: FontWeight.w700,
                      color: c.textMuted,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    value,
                    key: Key('prediction_value_$index'),
                    textAlign: TextAlign.end,
                    style: seconds == null
                        ? theme.bodyMedium!.copyWith(color: c.textMuted)
                        : theme.titleMedium!.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                  ),
                ),
              ],
            ),
            if (showLevel)
              Text(
                level,
                key: Key('prediction_level_$index'),
                style: theme.bodySmall!.copyWith(color: c.textMuted),
              ),
          ],
        ),
      ),
    );
  }
}

/// „≈ 52 min“, „≈ 1 h 55 min“: auf die Minute gerundet (exakte Sekunden gibt
/// es nur in `core`).
String predictionTimeText(AppLocalizations l10n, double seconds) {
  final total = (seconds / 60).round();
  final hours = total ~/ 60;
  final minutes = total % 60;
  return hours == 0
      ? l10n.predictionTimeMinutes(minutes)
      : l10n.predictionTimeHours(hours, minutes);
}

/// Eingetragene Zeit als `h:mm:ss` (ab einer Stunde) oder `m:ss`.
String clockTimeText(double seconds) {
  final total = seconds.round();
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  String two(int v) => v.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '$m:${two(s)}';
}

String predictionDistanceName(AppLocalizations l10n, PredictionDistance d) =>
    switch (d) {
      PredictionDistance.fiveKilometers => l10n.predictionDistance5k,
      PredictionDistance.tenKilometers => l10n.predictionDistance10k,
      PredictionDistance.halfMarathon => l10n.predictionDistanceHalf,
      PredictionDistance.marathon => l10n.predictionDistanceFull,
    };

String predictionKindText(AppLocalizations l10n, ReferenceKind k) =>
    switch (k) {
      ReferenceKind.race => l10n.predictionKindRace,
      ReferenceKind.test => l10n.predictionKindTest,
      ReferenceKind.confirmedRun => l10n.predictionKindConfirmedRun,
    };

String predictionLevelText(AppLocalizations l10n, PredictionLevel l) =>
    switch (l) {
      PredictionLevel.notDeterminable => l10n.predictionLevelNotDeterminable,
      PredictionLevel.provisional => l10n.predictionLevelProvisional,
      PredictionLevel.sufficient => l10n.predictionLevelSufficient,
      PredictionLevel.good => l10n.predictionLevelGood,
    };

String predictionSourceText(AppLocalizations l10n, PredictionSource s) =>
    switch (s) {
      PredictionSource.enteredTime => l10n.predictionSourceEntered,
      PredictionSource.confirmedRun => l10n.predictionSourceConfirmedRun,
      PredictionSource.runHistory => l10n.predictionSourceHistory,
      PredictionSource.vo2max => l10n.predictionSourceVo2max,
    };

String predictionReasonText(AppLocalizations l10n, PredictionReason r) =>
    switch (r) {
      PredictionReason.noReference => l10n.predictionReasonNoReference,
      PredictionReason.onlyVo2max => l10n.predictionReasonOnlyVo2max,
      PredictionReason.referenceTooOld => l10n.predictionReasonReferenceTooOld,
      PredictionReason.pauseSinceReference => l10n.predictionReasonPause,
      PredictionReason.invalidReference => l10n.predictionReasonInvalid,
      PredictionReason.referenceAge => l10n.predictionReasonAge,
      PredictionReason.distanceRatio => l10n.predictionReasonRatio,
      PredictionReason.referenceIsConfirmedRun =>
        l10n.predictionReasonConfirmedRun,
      PredictionReason.referenceIsTest => l10n.predictionReasonTest,
      PredictionReason.marathon => l10n.predictionReasonMarathon,
      PredictionReason.regularity => l10n.predictionReasonRegularity,
      PredictionReason.longestRun => l10n.predictionReasonLongestRun,
      PredictionReason.goalFeasibility => l10n.predictionReasonGoal,
      PredictionReason.none => l10n.predictionReasonNone,
    };
