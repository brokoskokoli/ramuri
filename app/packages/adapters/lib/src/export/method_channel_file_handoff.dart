import 'package:core/core.dart';
import 'package:flutter/services.dart';

/// Kanalname zu `FileHandoffChannel.kt` (`CHANNEL`); dieselbe Zeichenkette
/// steht dort (ein Test prüft das).
const String fileHandoffChannelName = 'ramuri/file_handoff';

/// [FileHandoff] über eigenen Kotlin-Code (FR-0201): Teilen über
/// `ACTION_SEND` und `FileProvider`, Speichern über `ACTION_CREATE_DOCUMENT`,
/// Öffnen über `ACTION_OPEN_DOCUMENT` (`pickFile`).
/// Der Kanal hängt an der Activity, weil beide Wege einen Systemdialog
/// starten. Gesendet wird entweder `bytes` oder `path` (Datei unter
/// [exportDirectory]; Kotlin prüft, dass sie dort liegt). Antworten der
/// Plattform: `completed` oder `cancelled`; alles andere, auch ein
/// Plattformfehler, ist [FileHandoffResult.failed].
class MethodChannelFileHandoff implements FileHandoff {
  MethodChannelFileHandoff([MethodChannel? channel])
    : _channel = channel ?? const MethodChannel(fileHandoffChannelName);

  final MethodChannel _channel;

  @override
  Future<FileHandoffResult> share(ExportFile file) => _call('share', file);

  @override
  Future<FileHandoffResult> save(ExportFile file) => _call('save', file);

  @override
  Future<String?> exportDirectory() async {
    try {
      return await _channel.invokeMethod<String>('exportDirectory');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Future<FilePickResult> pickFile() async {
    try {
      final answer = await _channel.invokeMethod<String>('pickFile');
      if (answer == 'cancelled') return const FilePickResult.cancelled();
      if (answer != null && isPlainAbsolutePath(answer)) {
        return FilePickResult.completed(answer);
      }
      return const FilePickResult.failed();
    } on PlatformException {
      return const FilePickResult.failed();
    } on MissingPluginException {
      return const FilePickResult.failed();
    }
  }

  @override
  Future<void> discardPicked() async {
    try {
      await _channel.invokeMethod<void>('discardPicked');
    } on PlatformException {
      // Die Plattform räumt beim Prozessstart ohnehin auf.
    } on MissingPluginException {
      // dito
    }
  }

  Future<FileHandoffResult> _call(String method, ExportFile file) async {
    try {
      final answer = await _channel.invokeMethod<String>(method, {
        'fileName': file.fileName,
        'mimeType': file.mimeType,
        'bytes': ?file.bytes,
        'path': ?file.path,
      });
      return switch (answer) {
        'completed' => FileHandoffResult.completed,
        'cancelled' => FileHandoffResult.cancelled,
        _ => FileHandoffResult.failed,
      };
    } on PlatformException {
      return FileHandoffResult.failed;
    } on MissingPluginException {
      return FileHandoffResult.failed;
    }
  }
}
