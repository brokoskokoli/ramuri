import 'package:flutter/material.dart';

import 'ramuri_colors.dart';

/// Ein Tag der [RamuriWeekStrip].
@immutable
class RamuriWeekDay {
  const RamuriWeekDay({
    required this.label,
    required this.semanticLabel,
    required this.done,
    this.today = false,
  });

  /// Kurzer Name (Mo), sichtbar unter dem Kreis.
  final String label;

  /// Für die Bedienungshilfe, etwa „Montag, gelaufen“.
  final String semanticLabel;

  /// Es wurde gelaufen: Kreis in Minze mit Haken.
  final bool done;

  /// Der heutige Tag: Kreis mit Akzentrand.
  final bool today;
}

/// Woche als Reihe von sieben Kreisen mit Namen darunter (Design „Heute“).
/// Die Tage ([days], Montag bis Sonntag) kommen fertig vom Aufrufer; jeder
/// Tag ist als Ganzes beschriftet.
class RamuriWeekStrip extends StatelessWidget {
  const RamuriWeekStrip({super.key, required this.days});

  final List<RamuriWeekDay> days;

  @override
  Widget build(BuildContext context) {
    final c = RamuriColors.of(context);
    final label = Theme.of(context).textTheme.labelSmall!;
    return Row(
      children: [
        for (var i = 0; i < days.length; i++)
          Expanded(
            child: Semantics(
              key: Key('week_day_$i'),
              container: true,
              excludeSemantics: true,
              label: days[i].semanticLabel,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: days[i].done
                          ? c.action
                          : (days[i].today ? c.tint : c.track),
                      border: days[i].today
                          ? Border.all(color: c.accent, width: 2)
                          : null,
                    ),
                    child: days[i].done
                        ? Icon(Icons.check_rounded, size: 18, color: c.onAction)
                        : null,
                  ),
                  const SizedBox(height: 6),
                  Text(days[i].label, style: label),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
