import 'package:core/core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../ui/ui.dart';
import '../sensors/run_heart_rate.dart';
import '../settings/unit_format.dart';
import 'live_run_view.dart';
import 'run_controller.dart';

/// Zahl und Einheit eines fertig formatierten Werts: Hat [text] die [unit] als
/// Endung, steht sie getrennt; sonst (etwa „–“ oder „noch keine Daten“) ist der
/// ganze Text der Wert.
(String, String?) splitUnit(String text, String unit) {
  final suffix = ' $unit';
  if (text.length > suffix.length && text.endsWith(suffix)) {
    return (text.substring(0, text.length - suffix.length), unit);
  }
  return (text, null);
}

/// Wert in der Schrift der Zahl, dahinter die Einheit klein und unumbrechbar.
/// Der Schlüssel [id] sitzt auf dem Text, damit Tests und Hilfen ihn finden.
/// Mit [shrink] schrumpft Zahl samt Einheit nur dann, wenn beides nicht in die
/// Breite passt (`scaleDown`), und bleibt in einer Zeile.
class LiveValueText extends StatelessWidget {
  const LiveValueText({
    super.key,
    required this.id,
    required this.value,
    required this.valueStyle,
    required this.unitStyle,
    this.unit,
    this.textAlign,
    this.shrink = false,
  });

  final String id;
  final String value;
  final String? unit;
  final TextStyle valueStyle;
  final TextStyle unitStyle;
  final TextAlign? textAlign;
  final bool shrink;

  @override
  Widget build(BuildContext context) {
    final unit = this.unit;
    final text = Text.rich(
      TextSpan(
        children: [
          TextSpan(text: value, style: valueStyle),
          if (unit != null)
            TextSpan(
              text: ' ${unbreakableUnit(unit)}',
              // Der Wortverbinder soll nicht in der Sprachausgabe landen.
              semanticsLabel: ' $unit',
              style: unitStyle,
            ),
        ],
      ),
      key: Key(id),
      textAlign: textAlign,
      // Geschrumpft wird in einer Zeile; der Umbruch würde im IntrinsicHeight
      // eine Scheinzeile messen.
      softWrap: !shrink,
    );
    if (!shrink) return text;
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: AlignmentDirectional.centerStart,
      child: text,
    );
  }
}

/// Hinweiskarte der Lauf-Seiten (Pause, Dienst, Speicher, GPS).
class LiveBanner extends StatelessWidget {
  const LiveBanner(this.text, {super.key, this.error = false});

  /// Der Schlüssel [Key] des Aufrufers sitzt auf dem Text, nicht auf der Karte.
  final Text text;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: error ? scheme.errorContainer : scheme.secondaryContainer,
      child: Padding(padding: const EdgeInsets.all(12), child: text),
    );
  }
}

/// Rundenliste (FR-0030).
class LiveLaps extends StatelessWidget {
  const LiveLaps({super.key, required this.laps});

  final List<RecordedLap> laps;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      key: const Key('run_laps'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.runLaps, style: Theme.of(context).textTheme.titleSmall),
        if (laps.isEmpty) Text(l10n.runNoLaps),
        for (final lap in laps.reversed)
          Text(l10n.runLapRow(lap.index, formatClock(lap.lapTime))),
      ],
    );
  }
}

/// Werte-Seite des laufenden und des pausierten Laufs nach `Live.dc.html`:
/// Kopfzeile mit Zustand und Chips, Zeit, Strecke, Pace, Puls mit Zonenanzeige
/// und darunter, was das Design nicht zeigt, die Pflichtanzeigen aus FR-0026,
/// FR-0027 und FR-0202 sowie Sensorwechsel und Hinweise.
class LiveValues extends StatelessWidget {
  const LiveValues({
    super.key,
    required this.controller,
    required this.formatter,
  });

  final RunController controller;
  final UnitFormatter formatter;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = RamuriColors.of(context);
    final type = RamuriType.of(context);
    final text = Theme.of(context).textTheme;
    final s = controller.snapshot;
    final pre = controller.preprocessing;
    final na = l10n.runUnavailable;
    final paused = s.phase == RecordingPhase.paused;

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
      // Ohne Puls steht „nicht verfügbar“ schon am Pulswert; die Zone sagt es nicht noch einmal.
      LiveZoneKind.noHeartRate => null,
      LiveZoneKind.noBasis => l10n.runZoneNoBasis,
    };
    final gpsState = controller.locationError
        ? _GpsState.error
        : s.positionLost
        ? _GpsState.lost
        : controller.hasFix
        ? _GpsState.good
        : _GpsState.searching;
    final gapCount = s.gaps
        .where((g) => g.kind == RunGapKind.positionLoss)
        .length;

    final (paceValue, paceUnit) = splitUnit(
      livePaceText(controller, formatter, l10n),
      formatter.paceLabel,
    );
    final (avgValue, avgUnit) = avg == null
        ? (l10n.runNoDataYet, null)
        : splitUnit(formatter.pace(avg), formatter.paceLabel);
    final (distValue, distUnit) = s.distanceMeters == null
        ? (l10n.runNoDataYet, null)
        : splitUnit(
            formatter.distance(s.distanceMeters),
            formatter.distanceLabel,
          );
    final (ascentValue, ascentUnit) = ascent == null
        ? (na, null)
        : splitUnit(formatter.elevation(ascent), formatter.elevationLabel);
    final cadence = switch ((
      controller.cadenceAvailability,
      controller.cadenceStepsPerMinute,
    )) {
      (CadenceAvailability.available, final spm?) => spm.round().toString(),
      (CadenceAvailability.available, null) => l10n.runNoDataYet,
      _ => na,
    };
    final cadenceUnit = cadence == na || cadence == l10n.runNoDataYet
        ? null
        : l10n.liveUnitSpm;

    final numberStyle = text.headlineLarge!;
    final unitStyle = type.unit;

    // Ersatztexte („nicht verfügbar“, „noch keine Daten“) klein, nicht in
    // Wertgröße: sie brächen sonst in der halben Breite mehrzeilig um.
    TextStyle valueStyleOf(String value, TextStyle? style) =>
        value == na || value == l10n.runNoDataYet
        ? text.labelMedium!
        : style ?? type.valueSmall;

    Widget tile(
      String label,
      String id,
      String value,
      String? unit, {
      TextStyle? style,
      bool unitInLabel = false,
    }) => _LiveTile(
      label: label,
      // Pace: die Einheit steht in der Beschriftung, die Zahl bleibt groß.
      // Ohne Einheit (Ersatztext) bleibt die Beschriftung, wie sie ist.
      labelUnit: unitInLabel ? unit : null,
      child: LiveValueText(
        id: id,
        value: value,
        unit: unitInLabel ? null : unit,
        shrink: unit != null && !unitInLabel,
        valueStyle: valueStyleOf(value, style),
        unitStyle: unitStyle,
      ),
    );

    /// Längstes Wort der Ersatztexte: Sie dürfen umbrechen, aber nicht im Wort.
    String longestWord(String t) =>
        t.split(RegExp(r'\s+')).reduce((a, b) => a.length >= b.length ? a : b);
    final placeholderWords = [longestWord(na), longestWord(l10n.runNoDataYet)];

    /// Zwei Kacheln nebeneinander; passt die breiteste Form einer Zahl oder
    /// ein Wort der Beschriftung nicht in die halbe Breite, stehen sie
    /// untereinander (wie das Raster weniger Spalten nimmt). Gemessen wird nie
    /// der aktuelle Wert: Die Anordnung darf sich während des Laufs nicht
    /// ändern, nur weil die Pace von 9:59 auf 10:00 springt.
    Widget pair(
      (String, TextStyle?, String, String?) first,
      Widget firstTile,
      Widget? secondTile, [
      (String, TextStyle?, String, String?)? second,
    ]) => _TilePair(
      words: [
        for (final (widest, style, label, labelUnit) in [first, ?second]) ...[
          (widest, style ?? type.valueSmall),
          for (final word in [
            ...label.split(RegExp(r'\s+')),
            ...placeholderWords,
            ?labelUnit,
          ])
            (word, text.labelMedium!),
        ],
      ],
      first: firstTile,
      second: secondTile,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(controller: controller, paused: paused, gps: gpsState),
        const SizedBox(height: 12),
        if (s.phase == RecordingPhase.autoPaused)
          LiveBanner(
            Text(
              l10n.runAutoPausedBanner,
              key: const Key('run_banner_autopaused'),
            ),
          ),
        if (controller.serviceFailed)
          LiveBanner(
            Text(l10n.runServiceFailed, key: const Key('run_banner_service')),
            error: true,
          ),
        if (controller.writeFailure != null)
          LiveBanner(
            Text(l10n.runStorageFailed, key: const Key('run_banner_storage')),
            error: true,
          ),
        if (gpsState != _GpsState.good)
          LiveBanner(
            Text(switch (gpsState) {
              _GpsState.error => l10n.runGpsError,
              _GpsState.lost => l10n.runGpsLost,
              _ => l10n.runGpsSearching,
            }, key: const Key('run_gps')),
            error: gpsState != _GpsState.searching,
          ),
        // Zeit (FR-0026): groß, bei großer Schrift verkleinert statt umgebrochen.
        Semantics(
          container: true,
          child: Column(
            children: [
              Text(
                l10n.runTime,
                style: text.labelMedium?.copyWith(color: c.textLabel),
              ),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  formatClock(s.totalTime),
                  key: const Key('run_time'),
                  style: text.displayLarge,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: LiveValueText(
            id: 'run_distance',
            value: distValue,
            unit: distUnit,
            valueStyle: type.distance,
            unitStyle: type.unitLarge,
          ),
        ),
        const SizedBox(height: 14),
        pair(
          (
            '88:88',
            numberStyle,
            l10n.livePaceNow,
            paceUnit ?? formatter.paceLabel,
          ),
          tile(
            l10n.livePaceNow,
            'run_pace',
            paceValue,
            paceUnit,
            style: numberStyle,
            unitInLabel: true,
          ),
          tile(
            l10n.runAvgPace,
            'run_avg_pace',
            avgValue,
            avgUnit,
            style: numberStyle,
            unitInLabel: true,
          ),
          (
            '88:88',
            numberStyle,
            l10n.runAvgPace,
            avgUnit ?? formatter.paceLabel,
          ),
        ),
        const SizedBox(height: 10),
        _HeartCard(
          bpm: bpm,
          zoneNumber: zone.kind == LiveZoneKind.zone ? zone.zone : null,
          zoneText: zoneText,
          numberStyle: numberStyle,
          unitStyle: unitStyle,
        ),
        const SizedBox(height: 10),
        pair(
          ('8:88:88', null, l10n.runMovingTime, null),
          tile(
            l10n.runMovingTime,
            'run_moving_time',
            formatClock(s.movingTime),
            null,
          ),
          tile(l10n.runAscent, 'run_ascent', ascentValue, ascentUnit),
          ('+8888', null, l10n.runAscent, null),
        ),
        const SizedBox(height: 10),
        // FR-0202: Wert nur mit Berechtigung und Sensor, sonst „nicht verfügbar“.
        pair(
          ('888', null, l10n.runCadence, null),
          tile(l10n.runCadence, 'run_cadence', cadence, cadenceUnit),
          null,
        ),
        if (gapCount > 0) ...[
          const SizedBox(height: 10),
          Text(
            l10n.runGpsGaps(gapCount),
            key: const Key('run_gaps'),
            style: text.bodySmall,
          ),
        ],
        const SizedBox(height: 10),
        _LiveCard(child: LiveLaps(laps: s.laps)),
        if (controller.sensors case final run?) ...[
          const SizedBox(height: 10),
          _SensorPanel(run: run),
        ],
      ],
    );
  }
}

enum _GpsState { good, searching, lost, error }

/// Kopfzeile: Zustand links, rechts die Chips für GPS und Puls.
class _Header extends StatelessWidget {
  const _Header({
    required this.controller,
    required this.paused,
    required this.gps,
  });

  final RunController controller;
  final bool paused;
  final _GpsState gps;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = RamuriColors.of(context);
    final text = Theme.of(context).textTheme;
    final run = controller.sensors;
    final autoPaused = controller.snapshot.phase == RecordingPhase.autoPaused;
    Widget chips(RunSensorStatus? status) {
      final pulse = switch (status) {
        RunSensorStatus.connected => (l10n.livePulseConnected, true),
        RunSensorStatus.reconnecting => (l10n.livePulseReconnecting, false),
        RunSensorStatus.lost => (l10n.livePulseLost, false),
        RunSensorStatus.none || null => (
          controller.snapshot.heartRateBpm != null
              ? l10n.livePulseConnected
              : l10n.livePulseNone,
          controller.snapshot.heartRateBpm != null,
        ),
      };
      return Wrap(
        alignment: WrapAlignment.end,
        spacing: 6,
        runSpacing: 6,
        children: [
          _StatusChip(
            id: 'live_chip_gps',
            label: switch (gps) {
              _GpsState.good => l10n.liveGpsGood,
              _GpsState.searching => l10n.liveGpsSearching,
              _GpsState.lost => l10n.liveGpsLost,
              _GpsState.error => l10n.liveGpsError,
            },
            good: gps == _GpsState.good,
          ),
          _StatusChip(id: 'live_chip_hr', label: pulse.$1, good: pulse.$2),
        ],
      );
    }

    final label = Text(
      paused
          ? l10n.runPausedBanner
          : autoPaused
          ? l10n.liveStateAutoPaused
          : l10n.liveStateRunning,
      key: paused ? const Key('run_banner_paused') : const Key('live_state'),
      style: text.labelMedium?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: 0.5,
        color: c.text,
      ),
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 2,
          child: Padding(padding: const EdgeInsets.only(top: 6), child: label),
        ),
        Expanded(
          flex: 5,
          // Der Puls-Chip hängt am Sensorstatus und baut sich neu auf.
          child: run == null
              ? chips(null)
              : ListenableBuilder(
                  listenable: run,
                  builder: (context, _) => chips(run.status),
                ),
        ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.id,
    required this.label,
    required this.good,
  });

  final String id;
  final String label;
  final bool good;

  @override
  Widget build(BuildContext context) {
    final c = RamuriColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(15),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 30),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: good ? c.accent : c.emberDot,
                  shape: BoxShape.circle,
                ),
                child: const SizedBox.square(dimension: 8),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  key: Key(id),
                  style: Theme.of(context).textTheme.labelSmall
                      ?.copyWith(color: c.text),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Weiße Karte der Lauf-Seite.
class _LiveCard extends StatelessWidget {
  const _LiveCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return RamuriCard(
      radius: 22,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: child,
    );
  }
}

/// Ein oder zwei Kacheln in einer Reihe, je eine halbe Breite. Passt eine Zahl
/// oder ein Wort der Beschriftung nicht hinein (sie bräche mitten im Wort,
/// „14:5“ / „9“, „Bewegungszeit“ bei Faktor 1,3), stehen die Kacheln
/// untereinander und haben die ganze Breite, wie das Raster der Zusammenfassung
/// weniger Spalten nimmt. Die Einheit der Pace steht in der Beschriftung; die
/// anderen bleiben bei der Zahl und schrumpfen nur, wenn beides nicht passt.
class _TilePair extends StatelessWidget {
  const _TilePair({
    required this.words,
    required this.first,
    required this.second,
  });

  /// Zahl und Schrift der Zahl je Kachel.
  final List<(String, TextStyle)> words;
  final Widget first;
  final Widget? second;

  /// Innenabstand der Kachel ([_LiveCard]) links und rechts.
  static const double _cardPadding = 16;
  static const double _gap = 10;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final inner = (constraints.maxWidth - _gap) / 2 - 2 * _cardPadding;
        var fits = true;
        for (final (value, style) in words) {
          final painter = TextPainter(
            text: TextSpan(text: value, style: style),
            textDirection: Directionality.of(context),
            textScaler: scaler,
          )..layout();
          fits &= painter.width <= inner;
          painter.dispose();
        }
        if (!fits) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              first,
              if (second != null) ...[const SizedBox(height: _gap), second!],
            ],
          );
        }
        // Gleich hohe Karten; die Zahlen stehen unten auf einer Höhe, auch wenn
        // eine Beschriftung zweizeilig ist.
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: first),
              const SizedBox(width: _gap),
              Expanded(child: second ?? const SizedBox.shrink()),
            ],
          ),
        );
      },
    );
  }
}

class _LiveTile extends StatelessWidget {
  const _LiveTile({required this.label, required this.child, this.labelUnit});

  final String label;

  /// Einheit hinter der Beschriftung („Ø Pace min/km“).
  final String? labelUnit;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = RamuriColors.of(context);
    return Semantics(
      container: true,
      child: SizedBox(
        width: double.infinity,
        child: _LiveCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            // Die Zahl unten: Zahlen nebeneinander stehen auf einer Höhe.
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text.rich(
                labelWithUnit(label, labelUnit),
                style: Theme.of(context).textTheme.labelMedium
                    ?.copyWith(color: c.textMuted),
              ),
              const SizedBox(height: 2),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

/// Puls mit Zone (FR-0026): „nicht verfügbar“ statt 0, wenn Puls oder
/// Zonenbasis fehlen; die Zonenanzeige bleibt dann grau.
class _HeartCard extends StatelessWidget {
  const _HeartCard({
    required this.bpm,
    required this.zoneNumber,
    required this.zoneText,
    required this.numberStyle,
    required this.unitStyle,
  });

  final int? bpm;
  final int? zoneNumber;

  /// `null`, wenn die Zone nichts zusagen hat (kein Puls, der Pulswert sagt es).
  final String? zoneText;
  final TextStyle numberStyle;
  final TextStyle unitStyle;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = RamuriColors.of(context);
    final text = Theme.of(context).textTheme;
    final bpm = this.bpm;
    return Semantics(
      container: true,
      label: l10n.runHeartRate,
      child: _LiveCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 4,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.favorite, size: 22, color: c.ember),
                    const SizedBox(width: 8),
                    Flexible(
                      child: bpm == null
                          ? Text(
                              l10n.runUnavailable,
                              key: const Key('run_hr'),
                              style: text.labelMedium,
                            )
                          : LiveValueText(
                              id: 'run_hr',
                              value: '$bpm',
                              unit: l10n.liveUnitBpm,
                              valueStyle: numberStyle,
                              unitStyle: unitStyle,
                            ),
                    ),
                  ],
                ),
                if (zoneText case final zoneText?)
                  Text(
                    zoneText,
                    key: const Key('run_zone'),
                    style: text.labelMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: c.accent,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            // Der Text daneben nennt die Zone, sobald es einen Puls gibt (ohne
            // Puls gibt es keinen Zonentext); der Balken wiederholt es nicht
            // für die Sprachausgabe.
            ZoneMeter(zone: zoneNumber, semanticLabel: ''),
          ],
        ),
      ),
    );
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
    final theme = Theme.of(context).textTheme;
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
        return _LiveCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.runSensors, style: theme.titleSmall),
              Text(status, key: const Key('run_sensor_status')),
              if (active != null)
                Text(
                  l10n.runSensorSource(active.name ?? l10n.sensorsUnnamed),
                  key: const Key('run_sensor_source'),
                ),
              if (run.lossOngoing)
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
          ),
        );
      },
    );
  }
}
