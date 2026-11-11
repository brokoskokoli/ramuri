import 'package:flutter/material.dart';

import 'debug_test_ppg_camera.dart';

/// Wähler für das Szenario der Fake-Kamera (WP27, nur Debug-Einstiegspunkt
/// `main_debug.dart`): ein kleiner Knopf am rechten Rand, aufgeklappt eine
/// Liste der Szenarien plus Zeitraffer. Für E2E per UI Automator: die
/// `Semantics.identifier` sind `debug_ppg_toggle`, `debug_ppg_<szenario>`
/// (z. B. `debug_ppg_goodPulse`) und `debug_ppg_speed`; die Texte beginnen mit
/// „PPG“. Kein Code der Release-Einstiegsdatei importiert diese Datei.
class DebugPpgPanel extends StatefulWidget {
  const DebugPpgPanel({super.key, required this.camera, required this.child});

  final DebugTestPpgCamera camera;
  final Widget child;

  @override
  State<DebugPpgPanel> createState() => _DebugPpgPanelState();
}

class _DebugPpgPanelState extends State<DebugPpgPanel> {
  bool _open = false;

  /// Zeitraffer: 60 s Messung in 2 s. Echtzeit ist die Vorgabe.
  static const double fastSpeed = 30;

  @override
  Widget build(BuildContext context) {
    final cam = widget.camera;
    return Stack(
      textDirection: TextDirection.ltr,
      children: [
        widget.child,
        Positioned(
          right: 0,
          top: 0,
          bottom: 0,
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Align(
              alignment: Alignment.centerRight,
              child: Material(
                color: Theme.of(context).colorScheme.inverseSurface,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _Tile(
                      id: 'debug_ppg_toggle',
                      // Zugeklappt zeigt der Knopf den Zeitraffer, damit man ihn vor einem Lauf
                      // sieht, ohne das Panel zu öffnen.
                      label: _open
                          ? 'PPG x'
                          : (cam.speed == 1
                                ? 'PPG'
                                : 'PPG x${cam.speed.round()}'),
                      onTap: () => setState(() => _open = !_open),
                    ),
                    if (_open) ...[
                      for (final s in DebugPpgScenario.values)
                        _Tile(
                          id: 'debug_ppg_${s.name}',
                          label: 'PPG ${s.name}',
                          selected: cam.scenario == s,
                          onTap: () => setState(() => cam.scenario = s),
                        ),
                      _Tile(
                        id: 'debug_ppg_speed',
                        label: cam.speed == 1
                            ? 'PPG Zeitraffer aus'
                            : 'PPG Zeitraffer an',
                        selected: cam.speed != 1,
                        onTap: () => setState(
                          () => cam.speed = cam.speed == 1 ? fastSpeed : 1,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.id,
    required this.label,
    required this.onTap,
    this.selected = false,
  });

  final String id;
  final String label;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      identifier: id,
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: selected ? scheme.inversePrimary : scheme.onInverseSurface,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              decoration: TextDecoration.none,
            ),
          ),
        ),
      ),
    );
  }
}
