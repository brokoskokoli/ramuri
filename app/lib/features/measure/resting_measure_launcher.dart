import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'resting_measure_controller.dart';
import 'resting_measure_screen.dart';

/// Kamera für die Ruhepuls-Messung (WP27): in der App `AppDependencies.ppgCamera`,
/// gesetzt über dem Navigator, damit auch normal geöffnete Seiten sie sehen.
/// Ohne Scope (Tests, die sie nicht brauchen) gibt es keinen Einstieg zur Messung.
class PpgCameraScope extends InheritedWidget {
  const PpgCameraScope({
    super.key,
    required this.camera,
    required super.child,
    this.evaluate,
  });

  final PpgCamera camera;

  /// Nur Tests: gescriptete Auswertung statt der Auswertung auf einem Isolate.
  final PpgEvaluate? evaluate;

  static PpgCamera? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<PpgCameraScope>()?.camera;

  static PpgEvaluate? evaluateOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<PpgCameraScope>()?.evaluate;

  @override
  bool updateShouldNotify(PpgCameraScope old) =>
      camera != old.camera || evaluate != old.evaluate;
}

/// Öffnet die Messung und liefert, wie sie endete. Zurück des Systems auf
/// Einstieg, Ergebnis und Kein Wert ruft im Screen kein `onClose` auf; es
/// zählt als [RestingMeasureOutcome.discarded] (nichts wird übernommen).
/// Während Ruhephase und Messung bricht der Screen dabei selbst ab.
typedef RestingMeasureLauncher = Future<RestingMeasureOutcome> Function(
  BuildContext context,
);

/// Der Einstieg für Formular-Seiten: Messung über [camera], Übernahme über
/// [profile] (bei Profil die Fassung mit Neuberechnung, damit Zonen wie bei
/// manueller Eingabe nachgezogen werden).
RestingMeasureLauncher restingMeasureLauncher({
  required PpgCamera camera,
  required ProfileService profile,
  required SettingsStore settings,
  required Clock clock,
  PpgEvaluate? evaluate,
}) => (context) async {
  final outcome = await Navigator.of(context).push<RestingMeasureOutcome>(
    MaterialPageRoute(
      builder: (_) => RestingMeasureHost(
        camera: camera,
        profile: profile,
        settings: settings,
        clock: clock,
        evaluate: evaluate,
      ),
    ),
  );
  return outcome ?? RestingMeasureOutcome.discarded;
};

/// Kanal zum Signal am Ende der Ruhephase (Kotlin: RestingSignal.kt).
const String restingSignalChannelName = 'ramuri/resting_signal';

/// Ton oder Vibration am Ende der Ruhephase über einen kleinen Kanal (Android:
/// Benachrichtigungston bzw. Vibrator mit einmaligem Muster). Flutters
/// SystemSound ist auf Android wirkungslos und die Haptik hängt an der
/// Berührungsfeedback-Einstellung. Ton an: Ton; Ton aus: Vibration.
class SystemRestingSignal implements RestingMeasureSignal {
  SystemRestingSignal(this._soundOn, {MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(restingSignalChannelName);

  final ValueNotifier<bool> _soundOn;
  final MethodChannel _channel;

  @override
  Future<void> restEnded() async {
    try {
      await _channel.invokeMethod<void>(_soundOn.value ? 'tone' : 'vibrate');
    } catch (_) {
      // Ohne Ton oder Vibration (Kanal fehlt, Gerät ohne Vibrator) läuft die Messung trotzdem weiter.
    }
  }
}

/// Hält Controller und Ton-Schalter der Messung: legt sie an, gibt sie frei und
/// schließt die Seite mit dem Ausgang der Messung.
class RestingMeasureHost extends StatefulWidget {
  const RestingMeasureHost({
    super.key,
    required this.camera,
    required this.profile,
    required this.settings,
    required this.clock,
    this.evaluate,
  });

  final PpgCamera camera;
  final ProfileService profile;
  final SettingsStore settings;
  final Clock clock;

  /// Nur Tests: gescriptete Auswertung statt Isolate.
  final PpgEvaluate? evaluate;

  @override
  State<RestingMeasureHost> createState() => _RestingMeasureHostState();
}

class _RestingMeasureHostState extends State<RestingMeasureHost> {
  final _soundOn = ValueNotifier<bool>(true);
  late final RestingMeasureController _controller;

  @override
  void initState() {
    super.initState();
    _controller = RestingMeasureController(
      camera: widget.camera,
      profile: widget.profile,
      settings: widget.settings,
      clock: widget.clock,
      signal: SystemRestingSignal(_soundOn),
      evaluate: widget.evaluate,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _soundOn.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RestingMeasureScreen(
    controller: _controller,
    soundOn: _soundOn,
    onClose: (outcome) => Navigator.of(context).pop(outcome),
  );
}
