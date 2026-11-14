import 'package:core/core.dart';
import 'package:flutter/material.dart';

import 'device_info.dart';
import 'morning_belt.dart';
import 'morning_measure_controller.dart';
import 'morning_measure_screen.dart';
import 'resting_measure_controller.dart';
import 'resting_measure_launcher.dart';

/// Hält Controller und Ton-Schalter der Morgenmessung und schließt die Seite
/// am Ende. Kamera und Speicher kommen vom Aufrufer.
/// Markierungen für das Ergebnis aus Entwicklermodus und Opt-in der Einstellungen
/// (dieselben wie auf der Seite Morgenwerte, [morningTrendMarks]).
Future<MorningTrendMarks> Function(RestingPosture) morningMarksReader(
  SettingsStore settings,
  Clock clock,
  Map<ValidationQuantity, ValidationState> state,
) =>
    (posture) async => morningTrendMarks(
      developerMode: await SettingsDeveloperModeStore(settings, clock).read(),
      posture: posture,
      optIn: await settings.get(SettingKeys.morningCameraRmssdOptIn) == '1',
      state: state,
    );

class MorningMeasureHost extends StatefulWidget {
  const MorningMeasureHost({
    super.key,
    required this.camera,
    required this.store,
    required this.settings,
    required this.clock,
    this.evaluate,
    this.device = readDeviceInfo,
    this.hooks = const MorningMeasureHooks(),
    this.belt,
    this.validationState = ppgValidationState,
    this.autoTick = true,
  });

  final PpgCamera camera;
  final MorningStore store;
  final SettingsStore settings;
  final Clock clock;

  /// Nur Tests: gescriptete Auswertung statt Isolate.
  final PpgEvaluate? evaluate;
  final DeviceInfoReader device;

  /// Stellen für Teil E (Gurt-RR): Beginn der Ruhephase, Ende der Messung.
  final MorningMeasureHooks hooks;

  /// Gurt-RR im Entwicklermodus (Teil E); `null` ohne Pulsquelle der App.
  final MorningBelt? belt;
  final Map<ValidationQuantity, ValidationState> validationState;

  /// Nur Tests: Sekundentakt der Ruhephase aus.
  final bool autoTick;

  @override
  State<MorningMeasureHost> createState() => _MorningMeasureHostState();
}

class _MorningMeasureHostState extends State<MorningMeasureHost> {
  final _soundOn = ValueNotifier<bool>(true);
  late final MorningMeasureController _controller;

  @override
  void initState() {
    super.initState();
    widget.belt?.init().then((_) {
      if (mounted) setState(() {});
    });
    _controller = MorningMeasureController(
      camera: widget.camera,
      store: widget.store,
      windowStore: SettingsMorningWindowStore(widget.settings, widget.clock),
      clock: widget.clock,
      device: widget.device,
      hooks: widget.hooks,
      belt: widget.belt,
      signal: SystemRestingSignal(_soundOn),
      evaluate: widget.evaluate,
      autoTick: widget.autoTick,
      validationState: widget.validationState,
      marksFor: morningMarksReader(
        widget.settings,
        widget.clock,
        widget.validationState,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    widget.belt?.dispose();
    _soundOn.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MorningMeasureScreen(
    controller: _controller,
    soundOn: _soundOn,
    onClose: () => Navigator.of(context).pop(),
  );
}
