import 'package:core/core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../ui/ui.dart';
import '../settings/unit_format.dart';
import 'live_map_page.dart';
import 'run_controller.dart';
import 'treadmill_units.dart';

/// Bandgeschwindigkeit und Steigung im Lauf ändern (FR-0196, K57): Knöpfe
/// +/− mit 48 dp, Schritte nach PAR-209/PAR-210. Der Controller schreibt die
/// Änderung sofort in den Lauf; die Anzeige liest nur den Snapshot.
class TreadmillControls extends StatelessWidget {
  const TreadmillControls({
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
    final text = Theme.of(context).textTheme;
    final s = controller.snapshot;
    final unit = formatter.unit;
    final lang = formatter.languageCode;
    final speed = s.beltSpeedMetersPerSecond;
    final incline = s.inclinePercent;
    final unitLabel = unit == DistanceUnit.miles
        ? l10n.treadmillUnitMph
        : l10n.treadmillUnitKmh;

    Widget step(String id, String label, IconData icon, VoidCallback? onTap) =>
        LiveRoundButton(
          key: Key(id),
          semanticLabel: label,
          size: 48,
          background: c.panel,
          foreground: c.action,
          icon: icon,
          onPressed: onTap,
        );

    Widget row({
      required String label,
      required String valueId,
      required String value,
      required Widget minus,
      required Widget plus,
    }) => Row(
      children: [
        minus,
        Expanded(
          child: Column(
            children: [
              Text(label, style: text.labelMedium),
              Text(value, key: Key(valueId), style: text.headlineSmall),
            ],
          ),
        ),
        plus,
      ],
    );

    return RamuriCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          row(
            label: l10n.treadmillSpeedNow,
            valueId: 'treadmill_speed',
            value:
                '${TreadmillUnits.speedText(unit, speed ?? 0, lang)} $unitLabel',
            minus: step(
              'treadmill_speed_down',
              l10n.treadmillSlower,
              Icons.remove,
              () => controller.setBeltSpeed(
                TreadmillUnits.stepSpeed(
                  unit,
                  controller.snapshot.beltSpeedMetersPerSecond,
                  -1,
                ),
              ),
            ),
            plus: step(
              'treadmill_speed_up',
              l10n.treadmillFaster,
              Icons.add,
              () => controller.setBeltSpeed(
                TreadmillUnits.stepSpeed(
                  unit,
                  controller.snapshot.beltSpeedMetersPerSecond,
                  1,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          TextButton(
            key: const Key('treadmill_stop_belt'),
            onPressed: controller.snapshot.beltSpeedMetersPerSecond == 0
                ? null
                : () => controller.setBeltSpeed(0),
            child: Text(l10n.treadmillBeltStopped),
          ),
          const Divider(height: 16),
          row(
            label: l10n.treadmillInclineNow,
            valueId: 'treadmill_incline',
            value: incline == null
                ? UnitFormatter.noValue
                : '${TreadmillUnits.inclineText(incline, lang)} %',
            minus: step(
              'treadmill_incline_down',
              l10n.treadmillFlatter,
              Icons.remove,
              () => controller.setIncline(
                TreadmillUnits.stepIncline(
                  controller.snapshot.inclinePercent,
                  -1,
                ),
              ),
            ),
            plus: step(
              'treadmill_incline_up',
              l10n.treadmillSteeper,
              Icons.add,
              () => controller.setIncline(
                TreadmillUnits.stepIncline(
                  controller.snapshot.inclinePercent,
                  1,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
