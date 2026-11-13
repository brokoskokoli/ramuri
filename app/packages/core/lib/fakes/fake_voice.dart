import 'dart:async';

import '../ports/voice.dart';

/// Fake: merkt sich die gesprochenen Texte; kann werfen oder hängen.
class FakeVoice implements VoicePort {
  /// Wird bei [speak] und [stop] geworfen (synchron nach dem Zählen).
  Object? error;

  /// Hält [speak] an, bis diese Future fertig ist (hängende Sprachausgabe).
  Future<void>? hang;

  final List<String> spoken = [];
  final List<String?> languages = [];
  int stopCalls = 0;

  @override
  Future<void> speak(String text, {String? languageTag}) async {
    spoken.add(text);
    languages.add(languageTag);
    final e = error;
    if (e != null) throw e;
    await hang;
  }

  @override
  Future<void> stop() async {
    stopCalls++;
    final e = error;
    if (e != null) throw e;
  }
}
