import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import '../../ui/ui.dart';
import '../measure/camera_finder_screen.dart';

/// Abschnitt „Kamera-Messung“ der Einstellungen (FR-0220), nur bei mehr als einer nutzbaren
/// Kamera: die geltende Kamera nach [resolvePpgCamera] („Standardkamera“ bzw. „Kamera `<id>`“,
/// je mit Brennweite) und „Kamera suchen“. Die Suche öffnet die Seite „Kamera finden“ für alle
/// Nutzer ohne anschließende Messung; danach gilt die neu gelesene Wahl. Die Liste braucht
/// kein Kamera-Recht; Kennungen werden nicht geloggt.
class PpgCameraMeasureSection extends StatefulWidget {
  const PpgCameraMeasureSection({
    super.key,
    required this.camera,
    required this.settings,
    required this.clock,
  });

  final PpgCamera camera;
  final SettingsStore settings;
  final Clock clock;

  @override
  State<PpgCameraMeasureSection> createState() =>
      _PpgCameraMeasureSectionState();
}

class _PpgCameraMeasureSectionState extends State<PpgCameraMeasureSection> {
  List<PpgCameraInfo> _cameras = const [];
  PpgCameraInfo? _current;
  bool _dev = false;

  late final SettingsPpgCameraChoiceStore _choice =
      SettingsPpgCameraChoiceStore(widget.settings, widget.clock);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    List<PpgCameraInfo> cameras;
    var dev = false;
    PpgCameraRef? manual;
    PpgCameraRef? auto;
    try {
      cameras = await widget.camera.cameras();
    } catch (_) {
      // Liste nicht lesbar: wie ohne Auswahl (kein Abschnitt).
      cameras = const [];
    }
    try {
      dev = await SettingsDeveloperModeStore(
        widget.settings,
        widget.clock,
      ).read();
      manual = dev ? await _choice.readManual() : null;
      auto = await _choice.readAuto();
    } catch (_) {
      manual = null;
      auto = null;
    }
    final ref = resolvePpgCamera(
      cameras: cameras,
      developerMode: dev,
      manual: manual,
      auto: auto,
    );
    final current = ref == null
        ? cameras.where((c) => c.isDefault).firstOrNull
        : cameras.where((c) => c.ref == ref).firstOrNull;
    if (!mounted) return;
    setState(() {
      _cameras = cameras;
      _current = current;
      _dev = dev;
    });
  }

  Future<void> _find() async {
    await Navigator.of(context).push<PpgCameraRef>(
      MaterialPageRoute(
        builder: (_) => CameraFinderScreen(
          camera: widget.camera,
          choice: _choice,
          developerMode: _dev,
          purpose: CameraFinderPurpose.settings,
        ),
      ),
    );
    if (!mounted) return;
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_cameras.where((c) => c.usable).length < 2) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context);
    final c = RamuriColors.of(context);
    final theme = Theme.of(context).textTheme;
    final nf = NumberFormat.decimalPatternDigits(
      locale: Localizations.localeOf(context).toString(),
      decimalDigits: 1,
    );
    final current = _current;
    final name = current == null || current.isDefault
        ? l10n.settingsCameraDefault
        : l10n.devCameraName(current.ref.key);
    final focal = current?.focalLengthMm;
    final label = focal == null
        ? name
        : '$name · ${l10n.devCameraFocal(nf.format(focal))}';
    return Column(
      key: const Key('settings_ppg_camera'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeading(l10n.settingsCameraTitle),
        const SizedBox(height: 12),
        RamuriCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.devCameraTitle, style: theme.titleSmall),
              const SizedBox(height: 4),
              Text(
                label,
                key: const Key('settings_ppg_camera_current'),
                style: theme.bodyMedium!.copyWith(color: c.text),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const Key('settings_ppg_camera_find'),
                icon: const Icon(Icons.camera_alt_outlined),
                label: Text(l10n.devCameraFind),
                onPressed: _find,
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}
