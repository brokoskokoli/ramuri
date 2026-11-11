import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter/services.dart';

import '../permissions/method_channel_permission_status.dart';

/// Kanalnamen zu `PpgCamera.kt`; dieselben Zeichenketten stehen dort (ein Test prüft das).
const String ppgCameraChannelName = 'ramuri/ppg_camera';
const String ppgCameraStreamChannelName = 'ramuri/ppg_camera_stream';

/// [PpgCamera] über Camera2 im Android-Teil (ADR-0011). Über die Grenze gehen nur Zahlen je
/// Bild (Zeitstempel, R/G der Mitte, 16 × R, 16 × G), nie Pixel. Die Rechteanfrage läuft über
/// den vorhandenen Rechte-Kanal (`MainActivity.kt`). Nichts davon geht in ein Log.
class MethodChannelPpgCamera implements PpgCamera {
  MethodChannelPpgCamera({
    MethodChannel? method,
    EventChannel? events,
    MethodChannel? permissions,
  }) : _method = method ?? const MethodChannel(ppgCameraChannelName),
       _events = events ?? const EventChannel(ppgCameraStreamChannelName),
       _permissions = permissions ?? permissionChannel;

  final MethodChannel _method;
  final EventChannel _events;
  final MethodChannel _permissions;

  StreamController<PpgCameraEvent>? _active;
  StreamSubscription<dynamic>? _sub;

  static PpgCameraAvailability _availability(String? s) => switch (s) {
    'available' => PpgCameraAvailability.available,
    'permission_denied' => PpgCameraAvailability.permissionDenied,
    'no_flash' => PpgCameraAvailability.noFlash,
    _ => PpgCameraAvailability.noCamera,
  };

  @override
  Future<PpgCameraAvailability> availability() => _ask(_method, 'availability');

  @override
  Future<PpgCameraAvailability> requestPermission() =>
      _ask(_permissions, 'requestCamera');

  Future<PpgCameraAvailability> _ask(MethodChannel c, String name) async {
    try {
      return _availability(await c.invokeMethod<String>(name));
    } on PlatformException {
      return PpgCameraAvailability.noCamera;
    } on MissingPluginException {
      return PpgCameraAvailability.noCamera;
    }
  }

  static PpgCameraStopReason _reason(Object? s) => switch (s) {
    'permission_denied' => PpgCameraStopReason.permissionDenied,
    'no_camera' => PpgCameraStopReason.noCamera,
    'no_flash' => PpgCameraStopReason.noFlash,
    'busy' => PpgCameraStopReason.busy,
    'disconnected' => PpgCameraStopReason.disconnected,
    'frame_rate' => PpgCameraStopReason.frameRate,
    'background' => PpgCameraStopReason.background,
    _ => PpgCameraStopReason.error,
  };

  static List<double>? _sixteen(Object? v) {
    if (v is! List || v.length != 16 || v.any((e) => e is! num)) return null;
    return [for (final e in v) (e as num).toDouble()];
  }

  /// Wandelt eine Nachricht von Kotlin in ein Ereignis; Unpassendes entfällt (nie ein Fehler).
  static PpgCameraEvent? parse(Object? event) {
    if (event is! Map) return null;
    switch (event['type']) {
      case 'frame':
        final t = event['t'];
        final r = event['r'];
        final g = event['g'];
        final r16 = _sixteen(event['r16']);
        final g16 = _sixteen(event['g16']);
        if (t is! num || r is! num || g is! num || r16 == null || g16 == null) {
          return null;
        }
        return PpgCameraFrame(
          PpgFrame(
            t: t.toDouble(),
            r: r.toDouble(),
            g: g.toDouble(),
            r16: r16,
            g16: g16,
          ),
        );
      case 'started':
        final fps = event['fps'];
        return fps is int ? PpgCameraStarted(fps) : null;
      case 'locked':
        return const PpgCameraExposureLocked();
      case 'stopped':
        return PpgCameraStopped(_reason(event['reason']));
    }
    return null;
  }

  /// Bewusst kein `async*`: Abbestellen eines Generators wirkt erst am nächsten `yield`,
  /// die Kamera bliebe mit Torch an. Abbestellen meldet sich in Kotlin über onCancel
  /// (Torch aus, Sitzung und Gerät zu).
  @override
  Stream<PpgCameraEvent> start() {
    late final StreamController<PpgCameraEvent> out;
    out = StreamController<PpgCameraEvent>(
      onListen: () {
        _sub = _events.receiveBroadcastStream().listen(
          (event) {
            final e = parse(event);
            if (e == null) return;
            out.add(e);
            if (e is PpgCameraStopped) out.close();
          },
          // Fehler des Kanals (z. B. Kamera weg): Ereignis mit Grund, dann Ende; kein Absturz.
          onError: (Object error) {
            final code = error is PlatformException ? error.code : null;
            out.add(PpgCameraStopped(_reason(code)));
            out.close();
          },
          onDone: out.close,
        );
      },
      onCancel: () {
        if (!identical(_active, out)) return null;
        _active = null;
        return _sub?.cancel();
      },
    );
    _active = out;
    return out.stream;
  }

  @override
  Future<void> stop() async {
    final a = _active;
    _active = null;
    final sub = _sub;
    _sub = null;
    try {
      await _method.invokeMethod<void>('stop');
    } on PlatformException {
      // Es lief nichts oder die Kamera ist schon zu.
    } on MissingPluginException {
      // Keine Plattform dahinter.
    }
    await sub?.cancel();
    await a?.close();
  }
}
