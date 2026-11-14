import 'package:core/core.dart';
import 'package:flutter/material.dart';

import 'device_info.dart';
import 'morning_measure_controller.dart';
import 'morning_measure_screen.dart';
import 'resting_measure_controller.dart';
import 'resting_measure_launcher.dart';

/// Hält Controller und Ton-Schalter der Morgenmessung und schließt die Seite
/// am Ende. Kamera und Speicher kommen vom Aufrufer.
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
    _controller = MorningMeasureController(
      camera: widget.camera,
      store: widget.store,
      windowStore: SettingsMorningWindowStore(widget.settings, widget.clock),
      clock: widget.clock,
      device: widget.device,
      hooks: widget.hooks,
      signal: SystemRestingSignal(_soundOn),
      evaluate: widget.evaluate,
      autoTick: widget.autoTick,
      validationState: widget.validationState,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
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
