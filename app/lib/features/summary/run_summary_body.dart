import 'package:core/core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../run/live_run_view.dart' show formatClock;
import '../run/treadmill_units.dart';
import '../settings/unit_format.dart';
import '../../offload_scope.dart';
import '../../ui/unbreakable_unit.dart';

/// Zeit für die Anzeige; fehlt sie, „nicht verfügbar“ (nie „–“ oder 0).
String clockText(AppLocalizations l10n, Duration? d) =>
    d == null ? l10n.runUnavailable : formatClock(d);

/// Grund, warum ein Wert fehlt, als Text (nie 0). Hatte der Lauf keinen
/// Puls ([hasHeartRate] false), nennt auch ein Grund aus der Profilbasis den
/// fehlenden Puls: Die Rechnung prüft die Basis vor den Pulswerten und meldet
/// sonst „Pulswerte im Profil prüfen“, obwohl der Puls das Fehlende ist
/// (FR-0057). Fehlt der Puls nicht, bleibt der Profilgrund erkennbar.
String unavailableReasonText(
  AppLocalizations l10n,
  UnavailableReason reason, {
  bool hasHeartRate = true,
}) => switch (reason) {
  UnavailableReason.noHeartRate => l10n.sumNoHeartRate,
  UnavailableReason.missingMaxHeartRate ||
  UnavailableReason.missingRestingHeartRate ||
  UnavailableReason.maxNotAboveResting ||
  UnavailableReason.reserveTooSmall =>
    hasHeartRate ? l10n.sumNoBasisShort : l10n.sumNoHeartRate,
  UnavailableReason.insufficientCoverage => l10n.sumCoverageLow,
  _ => l10n.runUnavailable,
};

/// Dezimalzahl in der Schreibweise der Sprache.
String decimalText(UnitFormatter formatter, String text) =>
    formatter.languageCode == 'de' ? text.replaceAll('.', ',') : text;

/// Hinweis „Laufband“ mit Durchschnittsgeschwindigkeit und, wenn bekannt,
/// mittlerer Steigung (FR-0196); `null` ohne Bandstrecke.
String? treadmillNoteText(
  AppLocalizations l10n,
  UnitFormatter formatter,
  BeltTrack belt,
) {
  final mps = belt.averageSpeedMetersPerSecond;
  if (mps == null) return null;
  final unitLabel = formatter.unit == DistanceUnit.miles
      ? l10n.treadmillUnitMph
      : l10n.treadmillUnitKmh;
  final speed =
      '${decimalText(formatter, TreadmillUnits.displayFromMps(formatter.unit, mps).toStringAsFixed(1))} $unitLabel';
  final incline = belt.averageInclinePercent;
  return incline == null
      ? l10n.treadmillSummaryNote(speed)
      : l10n.treadmillSummaryNoteIncline(
          speed,
          decimalText(formatter, incline.toStringAsFixed(1)),
        );
}

/// Einordnung gegenüber den letzten Läufen (OQ-0037: Pace, nur der
/// Unterschied, unter 1 s/km gleich).
String classificationText(
  AppLocalizations l10n,
  RunClassification c,
  UnitFormatter formatter,
) {
  if (!c.isAvailable) {
    return c.unavailable == ClassificationUnavailable.noPaceForRun
        ? l10n.sumClassNoPace
        : l10n.sumClassNoPrevious;
  }
  final delta = c.deltaSecondsPerKm!;
  // Pace und Einheit bleiben im Satz zusammen (Sprachausgabe: [spokenUnit]).
  String pace(double? secondsPerKm) =>
      unitTogether(formatter.pace(secondsPerKm), formatter.paceLabel);
  final reference = pace(c.referenceSecondsPerKm);
  if (c.relation == PaceRelation.same) {
    return l10n.sumClassSame(c.comparedRuns, reference);
  }
  final text = pace(delta.abs());
  return delta < 0
      ? l10n.sumClassFaster(text, c.comparedRuns, reference)
      : l10n.sumClassSlower(text, c.comparedRuns, reference);
}

/// Lädt einen beendeten Lauf für die Zusammenfassung (FR-0037) und die
/// Detailansicht (FR-0041): liest und rechnet beim Öffnen aus den gespeicherten
/// Rohdaten ([RunSummaryService]); gestaltet wird der geladene Lauf von
/// [contentBuilder] (`RunSummaryPage`, `RunDetailPage`). Scheitert das Lesen
/// oder fehlt der Lauf im Speicher, zeigt [fallback] die Werte der Aufzeichnung.
class RunSummaryBody extends StatefulWidget {
  const RunSummaryBody({
    super.key,
    required this.session,
    required this.clock,
    required this.runId,
    required this.fallback,
    required this.contentBuilder,
    this.splitUnitMeters,
  });

  final StorageSession session;
  final Clock clock;
  final int runId;
  final List<Widget> Function() fallback;

  /// Gestaltet den geladenen Lauf. Laden, Rechnen und Rückfall bleiben hier für
  /// beide Ansichten gleich.
  final Widget Function(
    BuildContext context,
    RunSummary summary,
    RunDetailData detail,
    KilometerSplits? splits,
  )
  contentBuilder;

  /// Länge eines Abschnitts der Kilometertabelle ([kilometerMeters] oder
  /// [mileMeters]); ohne Angabe gibt es keine Kilometerwerte (die Zusammenfassung
  /// braucht sie nicht).
  final double? splitUnitMeters;

  @override
  State<RunSummaryBody> createState() => _RunSummaryBodyState();
}

class _RunSummaryBodyState extends State<RunSummaryBody> {
  late final Future<_Loaded?> _future = _load();

  Future<_Loaded?> _load() async {
    // Wo die reine Rechnung läuft (in der App ein eigener Isolate).
    final offload = OffloadScope.of(context);
    try {
      final summary = await RunSummaryService(
        session: widget.session,
        clock: widget.clock,
        offload: offload,
      ).load(widget.runId);
      if (summary == null) return null;
      // Einmal gebaut, nicht bei jedem Neuzeichnen.
      final detail = await offload(buildRunDetailJob, (
        pre: summary.preprocessing,
        start: summary.run.startedAt,
        end: summary.run.endedAt!,
        pauses: summary.manualPauses,
        belt: summary.belt,
      ));
      final unit = widget.splitUnitMeters;
      final splits = unit == null
          ? null
          : await offload(kilometerSplitsJob, (
              pre: summary.preprocessing,
              unitMeters: unit,
              belt: summary.belt,
            ));
      return _Loaded(summary, detail, splits);
    } on Object {
      // Keine Gesundheitsdaten in Meldungen; die Ansicht fällt zurück.
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return FutureBuilder<_Loaded?>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Column(
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 12),
                Text(l10n.sumLoading, key: const Key('sum_loading')),
              ],
            ),
          );
        }
        final loaded = snapshot.data;
        if (loaded == null) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.sumFallback, key: const Key('sum_fallback')),
              const SizedBox(height: 8),
              ...widget.fallback(),
            ],
          );
        }
        return widget.contentBuilder(
          context,
          loaded.summary,
          loaded.detail,
          loaded.splits,
        );
      },
    );
  }
}

class _Loaded {
  _Loaded(this.summary, this.detail, this.splits);
  final RunSummary summary;
  final RunDetailData detail;
  final KilometerSplits? splits;
}
