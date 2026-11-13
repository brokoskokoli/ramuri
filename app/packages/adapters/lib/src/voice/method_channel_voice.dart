import 'package:core/core.dart';
import 'package:flutter/services.dart';

/// Name des prozessweiten Kanals der Sprachausgabe; dieselbe Zeichenkette
/// steht in `VoiceChannel.kt` (der Test prüft das).
const String voiceChannelName = 'ramuri/voice';

/// [VoicePort] über die Sprachausgabe des Systems (kein Paket, kein Netz aus
/// der App). Fehler kommen als Ausnahme zurück; der Aufrufer behandelt sie als
/// folgenlos. Es steht nie ein Text in einer Fehlermeldung oder einem Log.
class MethodChannelVoice implements VoicePort {
  MethodChannelVoice([MethodChannel? channel])
    : _channel = channel ?? const MethodChannel(voiceChannelName);

  final MethodChannel _channel;

  @override
  Future<void> speak(String text, {String? languageTag}) => _channel
      .invokeMethod<void>('speak', {'text': text, 'language': languageTag});

  @override
  Future<void> stop() => _channel.invokeMethod<void>('stop');
}
