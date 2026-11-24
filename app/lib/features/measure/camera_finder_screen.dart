import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import '../../ui/ui.dart';
import 'camera_finder_controller.dart';

/// Seite „Kamera finden“ (FR-0220, PAR-227, PAR-228): Live-Bilder aller nutzbaren
/// Rückkameras bei eingeschaltetem Blitz in zwei Spalten, je Bild Bezeichnung, Bildrate,
/// Balken „Licht“, „Finger erkannt“ und die Empfehlung. Ein Tipp wählt eine Kamera;
/// „Übernehmen“ speichert sie (ohne Tipp die Empfehlung) als Ergebnis der Kamerasuche,
/// mit [allowManual] zusätzlich „Als feste Wahl setzen“ (Wahl von Hand). Zurück speichert
/// nichts. Zurück, Übernehmen und Hintergrund beenden die Vorschau (Taschenlampe aus).
/// Gibt die gespeicherte Kamera zurück (`Navigator.pop`), sonst `null`.
class CameraFinderScreen extends StatefulWidget {
  const CameraFinderScreen({
    super.key,
    required this.camera,
    required this.choice,
    this.developerMode = false,
    this.allowManual = false,
  });

  final PpgCamera camera;
  final PpgCameraChoiceStore choice;

  /// Zahlen je Kamera (R/G, Belichtungszeit, ISO, Lichtmenge) zeigen.
  final bool developerMode;

  /// „Als feste Wahl setzen“ anbieten (Entwicklereinstellungen).
  final bool allowManual;

  static Key tileKey(PpgCameraRef ref) => Key('camera_finder_tile_${ref.key}');
  static Key fingerKey(PpgCameraRef ref) =>
      Key('camera_finder_finger_${ref.key}');
  static Key recommendedKey(PpgCameraRef ref) =>
      Key('camera_finder_recommended_${ref.key}');
  static Key selectedKey(PpgCameraRef ref) =>
      Key('camera_finder_selected_${ref.key}');
  static Key lightKey(PpgCameraRef ref) =>
      Key('camera_finder_light_${ref.key}');
  static Key numbersKey(PpgCameraRef ref) =>
      Key('camera_finder_numbers_${ref.key}');

  @override
  State<CameraFinderScreen> createState() => _CameraFinderScreenState();
}

class _CameraFinderScreenState extends State<CameraFinderScreen>
    with WidgetsBindingObserver {
  late final CameraFinderController _c = CameraFinderController(
    camera: widget.camera,
    choice: widget.choice,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _c.addListener(_changed);
    _c.load();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _c.resume();
      case AppLifecycleState.inactive:
        break;
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _c.pause();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _c.removeListener(_changed);
    _c.dispose();
    super.dispose();
  }

  Future<void> _apply({required bool manual}) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final failed = AppLocalizations.of(context).settingsSaveFailed;
    PpgCameraRef? ref;
    try {
      ref = await _c.apply(manual: manual);
    } on StorageException {
      messenger.showSnackBar(SnackBar(content: Text(failed)));
      return;
    }
    if (ref == null || !mounted) return;
    navigator.pop(ref);
  }

  String _failure(AppLocalizations l10n, PpgCameraStopReason r) => switch (r) {
    PpgCameraStopReason.busy => l10n.cameraFinderFailBusy,
    PpgCameraStopReason.disconnected => l10n.cameraFinderFailDisconnected,
    PpgCameraStopReason.frameRate => l10n.cameraFinderFailFrameRate,
    _ => l10n.cameraFinderFailOther,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = RamuriColors.of(context);
    final theme = Theme.of(context).textTheme;
    final muted = theme.bodySmall!.copyWith(color: c.textMuted);
    final body = switch (_c.phase) {
      CameraFinderPhase.loading => const Center(
        child: CircularProgressIndicator(),
      ),
      CameraFinderPhase.onlyOne => _message(
        const Key('camera_finder_only_one'),
        l10n.cameraFinderOnlyOne,
        theme,
      ),
      CameraFinderPhase.noPermission => _message(
        const Key('camera_finder_no_permission'),
        l10n.cameraFinderNoPermission,
        theme,
      ),
      CameraFinderPhase.stopped => _message(
        const Key('camera_finder_stopped'),
        l10n.cameraFinderStopped,
        theme,
      ),
      CameraFinderPhase.running => _grid(l10n, c, theme, muted),
    };
    final running = _c.phase == CameraFinderPhase.running;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.cameraFinderTitle)),
      body: body,
      bottomNavigationBar: running
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FilledButton(
                      key: const Key('camera_finder_apply'),
                      onPressed: _c.canApply
                          ? () => _apply(manual: false)
                          : null,
                      child: Text(l10n.cameraFinderApply),
                    ),
                    if (widget.allowManual) ...[
                      const SizedBox(height: 8),
                      OutlinedButton(
                        key: const Key('camera_finder_manual'),
                        onPressed: _c.canApply
                            ? () => _apply(manual: true)
                            : null,
                        child: Text(l10n.cameraFinderSetManual),
                      ),
                    ],
                  ],
                ),
              ),
            )
          : null,
    );
  }

  Widget _message(Key key, String text, TextTheme theme) => Padding(
    key: key,
    padding: const EdgeInsets.all(24),
    child: Text(text, style: theme.bodyLarge),
  );

  Widget _grid(
    AppLocalizations l10n,
    RamuriColors c,
    TextTheme theme,
    TextStyle muted,
  ) {
    final rec = _c.recommendation;
    final maxLight = _c.maxLight;
    final locale = Localizations.localeOf(context).toString();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(l10n.cameraFinderInstruction, style: theme.bodyLarge),
        if (_c.mode == PpgPreviewMode.alternating)
          Padding(
            key: const Key('camera_finder_alternating'),
            padding: const EdgeInsets.only(top: 6),
            child: Text(l10n.cameraFinderAlternating, style: muted),
          ),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: widget.developerMode ? 0.56 : 0.66,
          children: [
            for (final cam in _c.cameras)
              _tile(cam, rec, maxLight, l10n, c, theme, muted, locale),
          ],
        ),
      ],
    );
  }

  Widget _tile(
    PpgCameraInfo cam,
    PpgCameraRef? rec,
    double? maxLight,
    AppLocalizations l10n,
    RamuriColors c,
    TextTheme theme,
    TextStyle muted,
    String locale,
  ) {
    final ref = cam.ref;
    final s = _c.stateOf(cam);
    final failure = _c.failureOf(ref);
    final selected = _c.selected == ref;
    final recommended = rec == ref;
    final texture = _c.textureOf(ref);
    final light = s.light;
    final share = light == null || maxLight == null || maxLight <= 0
        ? 0.0
        : (light / maxLight).clamp(0.0, 1.0);
    final scheme = Theme.of(context).colorScheme;
    final r = (s.meanRed ?? 0).clamp(0, 255).round();
    final g = (s.meanGreen ?? 0).clamp(0, 255).round();
    final Widget image = failure != null
        ? Container(
            color: scheme.inverseSurface,
            alignment: Alignment.center,
            padding: const EdgeInsets.all(8),
            child: Text(
              _failure(l10n, failure),
              textAlign: TextAlign.center,
              style: theme.bodySmall!.copyWith(color: scheme.onInverseSurface),
            ),
          )
        : texture != null
        ? Texture(textureId: texture)
        // Ohne Texture (Debug-Quelle): Fläche in der Farbe der Zahlen.
        : PpgPreviewPatch(r: r, g: g);
    final two = NumberFormat.decimalPatternDigits(
      locale: locale,
      decimalDigits: 2,
    );
    final one = NumberFormat.decimalPatternDigits(
      locale: locale,
      decimalDigits: 1,
    );
    final zero = NumberFormat.decimalPatternDigits(
      locale: locale,
      decimalDigits: 0,
    );
    final ratio = s.meanRed != null && (s.meanGreen ?? 0) != 0
        ? two.format(s.meanRed! / s.meanGreen!)
        : '–';
    return Material(
      key: CameraFinderScreen.tileKey(ref),
      color: c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selected
              ? scheme.primary
              : recommended
              ? scheme.tertiary
              : c.outline,
          width: selected || recommended ? 3 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: failure == null ? () => _c.select(ref) : null,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 4 / 3,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: image,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                l10n.devCameraName(ref.key),
                style: theme.titleSmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (cam.frameRate != null)
                Text(l10n.devCameraFrameRate(cam.frameRate!), style: muted),
              const SizedBox(height: 4),
              Text(l10n.cameraFinderLight, style: muted),
              LinearProgressIndicator(
                key: CameraFinderScreen.lightKey(ref),
                value: share,
                semanticsLabel: l10n.cameraFinderLight,
              ),
              const SizedBox(height: 4),
              Row(
                key: CameraFinderScreen.fingerKey(ref),
                children: [
                  Icon(
                    s.fingerDetected
                        ? Icons.check_circle
                        : Icons.circle_outlined,
                    size: 16,
                    color: s.fingerDetected ? scheme.primary : c.textMuted,
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      s.fingerDetected
                          ? l10n.cameraFinderFinger
                          : l10n.cameraFinderNoFinger,
                      style: theme.bodySmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              if (recommended)
                Text(
                  l10n.cameraFinderRecommended,
                  key: CameraFinderScreen.recommendedKey(ref),
                  style: theme.labelLarge!.copyWith(color: scheme.tertiary),
                ),
              if (selected)
                Text(
                  l10n.cameraFinderSelected,
                  key: CameraFinderScreen.selectedKey(ref),
                  style: theme.labelLarge!.copyWith(color: scheme.primary),
                ),
              if (widget.developerMode)
                Text(
                  l10n.cameraFinderNumbers(
                    ratio,
                    s.exposureNs == null
                        ? '–'
                        : one.format(s.exposureNs! / 1e6),
                    s.iso == null ? '–' : '${s.iso}',
                    light == null ? '–' : zero.format(light),
                  ),
                  key: CameraFinderScreen.numbersKey(ref),
                  style: muted,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
