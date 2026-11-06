import 'package:core/core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../sensors/run_heart_rate.dart';
import '../settings/unit_format.dart';
import 'run_controller.dart';

/// Zeit als `h:mm:ss`, unter einer Stunde `m:ss`; `null` ergibt „–“.
String formatClock(Duration? d) {
  if (d == null || d.isNegative) return UnitFormatter.noValue;
  final s = d.inSeconds;
  final h = s ~/ 3600;
  final mm = ((s % 3600) ~/ 60).toString().padLeft(2, '0');
  final ss = (s % 60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$mm:$ss' : '${s ~/ 60}:$ss';
}

/// Durchschnittspace in Sekunden je Kilometer aus Bewegungszeit und Strecke;
/// `null`, solange eines von beiden fehlt oder die Strecke 0 ist. Zeit in
/// GPS-Lücken zählt nicht mit, soweit sie in der Bewegungszeit liegt: Sie hat
/// keine gemessene Strecke und würde den Schnitt sonst zu langsam machen. Eine
/// Lücke im erkannten Stillstand steckt nicht in der Bewegungszeit und wird
/// darum nicht abgezogen. Die Spec
/// schweigt dazu (Entscheidung des Coders, WP10 abstimmen).
double? averagePaceSecondsPerKm(RecordingSnapshot s) {
  final moving = s.movingTime;
  final d = s.distanceMeters;
  if (moving == null || d == null || d <= 0) return null;
  final t = moving - s.positionLossMovingTime;
  if (t <= Duration.zero) return null;
  return t.inMicroseconds / 1e6 / (d / 1000);
}

/// Live-Bildschirm und Abschlussansicht eines Laufs.
class LiveRunView extends StatelessWidget {
  const LiveRunView({
    super.key,
    required this.controller,
    required this.formatter,
  });

  final RunController controller;
  final UnitFormatter formatter;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final finished = controller.phase == RecordingPhase.finished;
    return PopScope(
      canPop: finished,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmFinish(context);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(finished ? l10n.runDoneTitle : l10n.homeStartRun),
          automaticallyImplyLeading: finished,
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    ..._banners(context, l10n, finished),
                    ..._metrics(l10n, finished),
                    if (!finished) _autoPauseSwitch(l10n),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: finished
                    ? SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          key: const Key('run_done_close'),
                          onPressed: () => Navigator.of(context).pop(),
                          child: Text(l10n.runDoneClose),
                        ),
                      )
                    : _controls(context, l10n),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _banners(
    BuildContext context,
    AppLocalizations l10n,
    bool finished,
  ) {
    final s = controller.snapshot;
    final scheme = Theme.of(context).colorScheme;
    Widget banner(Key key, String text, {bool error = false}) => Card(
      color: error ? scheme.errorContainer : scheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(text, key: key),
      ),
    );
    return [
      if (finished)
        banner(
          const Key('run_done_status'),
          controller.writeFailure == null
              ? l10n.runDoneSaved
              : l10n.runDoneSaveProblem,
          error: controller.writeFailure != null,
        ),
      if (s.phase == RecordingPhase.paused)
        banner(const Key('run_banner_paused'), l10n.runPausedBanner),
      if (s.phase == RecordingPhase.autoPaused)
        banner(const Key('run_banner_autopaused'), l10n.runAutoPausedBanner),
      if (controller.serviceFailed && !finished)
        banner(
          const Key('run_banner_service'),
          l10n.runServiceFailed,
          error: true,
        ),
      if (controller.writeFailure != null && !finished)
        banner(
          const Key('run_banner_storage'),
          l10n.runStorageFailed,
          error: true,
        ),
    ];
  }

  List<Widget> _metrics(AppLocalizations l10n, bool finished) {
    final s = controller.snapshot;
    final pre = controller.preprocessing;
    final na = l10n.runUnavailable;

    final String livePace;
    switch (pre?.pace.livePace) {
      case PaceValue(:final secondsPerKm):
        livePace = formatter.pace(secondsPerKm);
      case PaceStandstill():
        livePace = UnitFormatter.noValue; // OQ-0037
      case PaceNoData() || null:
        livePace = l10n.runNoDataYet;
    }
    final avg = averagePaceSecondsPerKm(s);
    final ascent = pre?.altitude.ascentMeters;
    final bpm = s.heartRateBpm;
    final zone = controller.zone;
    final zoneText = switch (zone.kind) {
      LiveZoneKind.zone =>
        zone.aboveHint
            ? l10n.runZoneAbove(zone.zone!)
            : l10n.runZoneValue(zone.zone!),
      LiveZoneKind.belowZone1 => l10n.runZoneBelow,
      LiveZoneKind.noHeartRate => l10n.runZoneNoHeartRate,
      LiveZoneKind.noBasis => l10n.runZoneNoBasis,
    };
    final gpsText = controller.locationError
        ? l10n.runGpsError
        : s.positionLost
        ? l10n.runGpsLost
        : controller.hasFix
        ? l10n.runGpsOk
        : l10n.runGpsSearching;
    final gapCount = s.gaps
        .where((g) => g.kind == RunGapKind.positionLoss)
        .length;

    return [
      _Metric('run_time', l10n.runTime, formatClock(s.totalTime), big: true),
      _Metric(
        'run_distance',
        l10n.runDistance,
        s.distanceMeters == null
            ? l10n.runNoDataYet
            : formatter.distance(s.distanceMeters),
        big: true,
      ),
      if (!finished) _Metric('run_pace', l10n.runPace, livePace, big: true),
      _Metric('run_moving_time', l10n.runMovingTime, formatClock(s.movingTime)),
      _Metric(
        'run_avg_pace',
        l10n.runAvgPace,
        avg == null ? l10n.runNoDataYet : formatter.pace(avg),
      ),
      if (!finished) ...[
        _Metric(
          'run_hr',
          l10n.runHeartRate,
          bpm == null ? na : l10n.runBpm(bpm),
        ),
        _Metric('run_zone', l10n.runZone, zoneText),
        _Metric('run_gps', l10n.runGps, gpsText),
        if (controller.sensors case final run?)
          _SensorPanel(run: run)
        else
          _Metric(
            'run_sensors',
            l10n.runSensors,
            bpm != null
                ? l10n.runHeartRateSourceActive
                : l10n.runHeartRateSourceNone,
          ),
      ],
      if (gapCount > 0)
        _Metric('run_gaps', l10n.runGps, l10n.runGpsGaps(gapCount)),
      _Metric(
        'run_ascent',
        l10n.runAscent,
        ascent == null ? na : formatter.elevation(ascent),
      ),
      // FR-0202: Wert nur mit Berechtigung und Sensor, sonst „nicht verfügbar“.
      _Metric('run_cadence', l10n.runCadence, switch ((
        controller.cadenceAvailability,
        controller.cadenceStepsPerMinute,
      )) {
        (CadenceAvailability.available, final spm?) => l10n.runSpm(spm.round()),
        (CadenceAvailability.available, null) => l10n.runNoDataYet,
        _ => na,
      }),
      _Laps(laps: s.laps),
    ];
  }

  Widget _autoPauseSwitch(AppLocalizations l10n) => SwitchListTile(
    key: const Key('run_autopause'),
    contentPadding: EdgeInsets.zero,
    title: Text(l10n.runAutoPause),
    subtitle: Text(l10n.runAutoPauseHint),
    value: controller.autoPause,
    onChanged: controller.setAutoPause,
  );

  Widget _controls(BuildContext context, AppLocalizations l10n) {
    final phase = controller.phase;
    final paused = phase == RecordingPhase.paused;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (paused)
          FilledButton(
            key: const Key('run_resume'),
            onPressed: controller.resume,
            child: Text(l10n.runResume),
          )
        else
          FilledButton(
            key: const Key('run_pause'),
            onPressed: controller.pause,
            child: Text(l10n.runPause),
          ),
        // In der manuellen Pause lehnt die Sitzung eine Runde ab.
        OutlinedButton(
          key: const Key('run_lap'),
          onPressed: paused ? null : controller.lap,
          child: Text(l10n.runLap),
        ),
        OutlinedButton(
          key: const Key('run_finish'),
          onPressed: () => _confirmFinish(context),
          child: Text(l10n.runFinish),
        ),
      ],
    );
  }

  Future<void> _confirmFinish(BuildContext context) async {
    if (controller.phase == RecordingPhase.finished) return;
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.runFinishTitle),
        content: Text(l10n.runFinishBody),
        actions: [
          TextButton(
            key: const Key('run_finish_cancel'),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.runFinishCancel),
          ),
          FilledButton(
            key: const Key('run_finish_confirm'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.runFinishConfirm),
          ),
        ],
      ),
    );
    if (ok == true) await controller.finish();
  }
}

/// Sensorstatus, aktive Quelle und Wechsel der Quelle im Lauf (FR-0017,
/// FR-0018). Zeigt nie eine Geräteadresse; ohne Namen „Pulssensor“.
class _SensorPanel extends StatelessWidget {
  const _SensorPanel({required this.run});

  final RunHeartRate run;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: run,
      builder: (context, _) {
        final active = run.activeEntry;
        final status = switch (run.status) {
          RunSensorStatus.none => l10n.runSensorNone,
          RunSensorStatus.connected => l10n.runSensorConnected,
          RunSensorStatus.reconnecting => l10n.runSensorReconnecting,
          RunSensorStatus.lost => l10n.runSensorLost,
        };
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Metric('run_sensor_status', l10n.runSensors, status),
            if (active != null)
              Text(
                l10n.runSensorSource(active.name ?? l10n.sensorsUnnamed),
                key: const Key('run_sensor_source'),
              ),
            if (run.lossSeen)
              Text(
                l10n.runSensorLossNote,
                key: const Key('run_sensor_loss'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            for (final d in run.devices)
              if (d.id != run.activeId)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    key: Key('run_sensor_select_${d.id}'),
                    onPressed: () => run.select(d.id),
                    child: Text(
                      l10n.runSensorSwitchTo(d.name ?? l10n.sensorsUnnamed),
                    ),
                  ),
                ),
          ],
        );
      },
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric(this.id, this.label, this.value, {this.big = false});

  final String id;
  final String label;
  final String value;
  final bool big;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(flex: 2, child: Text(label, style: theme.bodyMedium)),
          Expanded(
            flex: 3,
            child: Text(
              value,
              key: Key(id),
              textAlign: TextAlign.end,
              style: big ? theme.headlineSmall : theme.titleMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _Laps extends StatelessWidget {
  const _Laps({required this.laps});

  final List<RecordedLap> laps;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      key: const Key('run_laps'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Text(l10n.runLaps, style: Theme.of(context).textTheme.titleSmall),
        if (laps.isEmpty) Text(l10n.runNoLaps),
        for (final lap in laps.reversed)
          Text(l10n.runLapRow(lap.index, formatClock(lap.lapTime))),
      ],
    );
  }
}
