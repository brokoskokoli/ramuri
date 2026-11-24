import 'package:flutter/material.dart';

import 'debug_test_ppg_camera.dart';

/// Wähler für das Szenario der Fake-Kamera (WP27, nur Debug-Einstiegspunkt
/// `main_debug.dart`): ein kleiner Knopf am rechten Rand, aufgeklappt eine
/// Liste der Szenarien plus Zeitraffer. Die Szenarien gelten je Kamera der
/// Debug-Quelle ([debugPpgCameras], FR-0220): oben wählt man die Kamera, deren
/// Szenario die Liste zeigt und setzt (Vorgabe: Standardkamera). Für E2E per UI
/// Automator: die `Semantics.identifier` sind `debug_ppg_toggle`,
/// `debug_ppg_camera_<n>` (n = Stelle in [debugPpgCameras], 0 = Standardkamera),
/// `debug_ppg_<szenario>` (z. B. `debug_ppg_goodPulse`), `debug_ppg_speed` und
/// `debug_ppg_preview` (Kamerasuche gleichzeitig oder im Wechsel);
/// die Texte beginnen mit „PPG“. Kein Code der Release-Einstiegsdatei importiert diese Datei.
///
/// Zugeklappt belegt das Feld einen festen Streifen von [collapsedWidth] am
/// rechten Rand; der Inhalt wird um genau diese Breite schmaler gelegt, damit
/// das Feld keinen Knopf der Seite verdeckt. Aufgeklappt liegt die Liste über
/// dem Inhalt.
class DebugPpgPanel extends StatefulWidget {
  const DebugPpgPanel({super.key, required this.camera, required this.child});

  final DebugTestPpgCamera camera;
  final Widget child;

  /// Breite des zugeklappten Felds (dp) und zugleich rechter Rand des Inhalts.
  static const double collapsedWidth = 56;

  @override
  State<DebugPpgPanel> createState() => _DebugPpgPanelState();
}

class _DebugPpgPanelState extends State<DebugPpgPanel> {
  bool _open = false;

  /// Kamera, deren Szenario die Liste zeigt.
  int _camera = 0;

  /// Zeitraffer: 60 s Messung in 2 s. Echtzeit ist die Vorgabe.
  static const double fastSpeed = 30;

  @override
  Widget build(BuildContext context) {
    final cam = widget.camera;
    final ref = debugPpgCameras[_camera].ref;
    return Stack(
      textDirection: TextDirection.ltr,
      children: [
        Padding(
          padding: const EdgeInsets.only(right: DebugPpgPanel.collapsedWidth),
          child: widget.child,
        ),
        Positioned(
          right: 0,
          top: 0,
          bottom: 0,
          width: DebugPpgPanel.collapsedWidth,
          child: ColoredBox(color: Theme.of(context).colorScheme.surface),
        ),
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
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _Tile(
                      id: 'debug_ppg_toggle',
                      width: DebugPpgPanel.collapsedWidth,
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
                      for (var i = 0; i < debugPpgCameras.length; i++)
                        _Tile(
                          id: 'debug_ppg_camera_$i',
                          label: 'PPG Kamera ${debugPpgCameras[i].ref.key}',
                          selected: _camera == i,
                          onTap: () => setState(() => _camera = i),
                        ),
                      for (final s in DebugPpgScenario.values)
                        _Tile(
                          id: 'debug_ppg_${s.name}',
                          label: 'PPG ${s.name}',
                          selected: cam.scenarioOf(ref) == s,
                          onTap: () => setState(() => cam.setScenario(ref, s)),
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
                      // Kamerasuche (FR-0220, PAR-227): gilt ab dem nächsten Start der Vorschau.
                      _Tile(
                        id: 'debug_ppg_preview',
                        label: cam.previewAlternating
                            ? 'PPG Suche im Wechsel'
                            : 'PPG Suche gleichzeitig',
                        selected: cam.previewAlternating,
                        onTap: () => setState(
                          () =>
                              cam.previewAlternating = !cam.previewAlternating,
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
    this.width,
  });

  /// Feste Breite (zugeklappter Knopf); der Text wird dann bei Bedarf verkleinert.
  final double? width;

  final String id;
  final String label;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget text = Text(
      label,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: selected ? scheme.inversePrimary : scheme.onInverseSurface,
        fontWeight: selected ? FontWeight.bold : FontWeight.normal,
        decoration: TextDecoration.none,
      ),
    );
    final w = width;
    if (w != null) {
      text = SizedBox(
        width: w - 16,
        child: FittedBox(fit: BoxFit.scaleDown, child: text),
      );
    }
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
          child: text,
        ),
      ),
    );
  }
}
