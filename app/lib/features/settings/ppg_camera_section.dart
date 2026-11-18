import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import '../../ui/ui.dart';

/// Karte „Kamera für die Pulsmessung“ auf den Entwicklereinstellungen
/// (FR-0220, nur Entwicklermodus): „Standard“ löscht die Wahl von Hand, darunter
/// je Rückkamera aus [PpgCamera.cameras] ein Eintrag. Nicht nutzbare Kameras sind
/// sichtbar, aber nicht wählbar, mit Grund. Die Liste braucht kein Kamera-Recht.
/// Kennungen und Liste werden nicht geloggt.
class PpgCameraSection extends StatefulWidget {
  const PpgCameraSection({
    super.key,
    required this.camera,
    required this.choice,
  });

  final PpgCamera camera;
  final PpgCameraChoiceStore choice;

  /// Schlüssel eines Eintrags (Tests, E2E); `null` = „Standard“.
  static Key entryKey(PpgCameraRef? ref) =>
      Key('about_ppg_camera_${ref?.key ?? 'default'}');

  @override
  State<PpgCameraSection> createState() => _PpgCameraSectionState();
}

class _PpgCameraSectionState extends State<PpgCameraSection> {
  List<PpgCameraInfo>? _cameras;
  PpgCameraRef? _manual;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    List<PpgCameraInfo> cameras;
    PpgCameraRef? manual;
    try {
      cameras = await widget.camera.cameras();
    } catch (_) {
      // Liste nicht lesbar: wie ohne Rückkamera (keine Wahl möglich).
      cameras = const [];
    }
    try {
      manual = await widget.choice.readManual();
    } catch (_) {
      manual = null;
    }
    if (!mounted) return;
    setState(() {
      _cameras = cameras;
      _manual = manual;
    });
  }

  Future<void> _select(String? key) async {
    final ref = PpgCameraRef.parse(key);
    await widget.choice.setManual(ref);
    if (!mounted) return;
    setState(() => _manual = ref);
  }

  String? _reason(AppLocalizations l10n, PpgCameraUnusable? u) => switch (u) {
    null => null,
    PpgCameraUnusable.noFlash => l10n.devCameraNoFlash,
    PpgCameraUnusable.frameRate => l10n.devCameraFrameRate,
    PpgCameraUnusable.other => l10n.devCameraUnusable,
  };

  static Widget? _subtitle(List<String> parts, TextStyle style) =>
      parts.isEmpty ? null : Text(parts.join(' · '), style: style);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = RamuriColors.of(context);
    final theme = Theme.of(context).textTheme;
    final muted = theme.bodySmall!.copyWith(color: c.textMuted);
    final cameras = _cameras;
    final nf = NumberFormat.decimalPatternDigits(
      locale: Localizations.localeOf(context).toString(),
      decimalDigits: 1,
    );
    final children = <Widget>[
      Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 4),
        child: Text(l10n.devCameraTitle, style: theme.titleMedium),
      ),
    ];
    if (cameras == null) {
      children.add(const SizedBox(height: 48));
    } else if (cameras.isEmpty) {
      children.add(
        Padding(
          key: const Key('about_ppg_camera_none'),
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(l10n.devCameraNone, style: muted),
        ),
      );
    } else {
      final manual = _manual;
      final missing =
          manual != null && !cameras.any((cam) => cam.ref == manual);
      if (missing) {
        children.add(
          Padding(
            key: const Key('about_ppg_camera_missing'),
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              l10n.devCameraMissing,
              style: theme.bodySmall!.copyWith(color: c.text),
            ),
          ),
        );
      }
      children.add(
        RadioGroup<String>(
          groupValue: missing ? '' : (manual?.key ?? ''),
          onChanged: _select,
          child: Column(
            children: [
              RadioListTile<String>(
                key: PpgCameraSection.entryKey(null),
                contentPadding: EdgeInsets.zero,
                value: '',
                title: Text(l10n.devCameraDefaultChoice),
              ),
              for (final cam in cameras)
                RadioListTile<String>(
                  key: PpgCameraSection.entryKey(cam.ref),
                  contentPadding: EdgeInsets.zero,
                  value: cam.ref.key,
                  enabled: cam.usable,
                  title: Text(l10n.devCameraName(cam.ref.key)),
                  subtitle: _subtitle([
                    if (cam.focalLengthMm != null)
                      l10n.devCameraFocal(nf.format(cam.focalLengthMm)),
                    if (cam.isDefault) l10n.devCameraDefaultChoice,
                    ?_reason(l10n, cam.unusable),
                  ], muted),
                ),
            ],
          ),
        ),
      );
    }
    return Column(
      key: const Key('about_ppg_camera'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}
