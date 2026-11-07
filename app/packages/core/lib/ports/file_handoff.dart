import 'dart:typed_data';

/// Eine fertige Datei für die Übergabe an das System (FR-0201): Teilen-Menü
/// oder Dokumentenziel. Der Inhalt liegt nur im Speicher; wo er auf der
/// Plattform zwischengespeichert wird, entscheidet der Adapter.
class ExportFile {
  /// Wirft [ArgumentError], wenn [fileName] kein sicherer Dateiname ist
  /// ([isSafeExportFileName]) oder [mimeType] nicht die Form `typ/untertyp`
  /// hat.
  ExportFile({
    required this.fileName,
    required this.mimeType,
    required this.bytes,
  }) {
    if (!isSafeExportFileName(fileName)) {
      throw ArgumentError.value(fileName, 'fileName', 'unsicherer Dateiname');
    }
    if (!_mime.hasMatch(mimeType)) {
      throw ArgumentError.value(mimeType, 'mimeType');
    }
  }

  final String fileName;
  final String mimeType;
  final Uint8List bytes;

  static final _mime = RegExp(r'^[a-z0-9.+-]+/[a-z0-9.+-]+$');
}

/// Ergebnis einer Übergabe. Beim Teilen heißt [completed]: Ein Ziel im
/// Teilen-Menü wurde gewählt; ob das Ziel die Datei weiterverarbeitet, meldet
/// Android nicht. Beim Speichern: Die Datei ist geschrieben.
enum FileHandoffResult { completed, cancelled, failed }

/// Port: Datei an das System übergeben (FR-0201). Nichts wird ohne Aktion des
/// Nutzers übertragen; beide Wege öffnen einen Systemdialog. WP11 nutzt ihn
/// für Lauf-Exporte, WP12 für das Archiv. Wirft nie: Fehler der Plattform
/// werden zu [FileHandoffResult.failed].
abstract interface class FileHandoff {
  /// Teilen-Menü des Systems (`ACTION_SEND`).
  Future<FileHandoffResult> share(ExportFile file);

  /// Ablage über das System-Dokumentenziel (`ACTION_CREATE_DOCUMENT`).
  Future<FileHandoffResult> save(ExportFile file);
}

/// Höchstlänge eines Dateinamens in Zeichen (Dateisysteme: 255 Bytes; alle
/// erlaubten Zeichen sind ASCII).
const int maxExportFileNameLength = 255;

final _safeName = RegExp(r'^[A-Za-z0-9-][A-Za-z0-9._-]*$');

/// Sicher als Dateiname auf jeder Plattform: nur `A-Z a-z 0-9 . _ -`, beginnt
/// nicht mit `.` oder `_`, höchstens [maxExportFileNameLength] Zeichen. Damit
/// sind Pfadtrenner, `.`/`..` und versteckte Dateien ausgeschlossen.
bool isSafeExportFileName(String name) =>
    name.length <= maxExportFileNameLength && _safeName.hasMatch(name);

/// Dateiname aus [base] und [extension] (Abbildungsregel 8): Zeichen außer
/// `A-Z a-z 0-9 . _ -` werden zu `_`, führende `.`/`_` entfallen, ein leerer
/// Name wird zu `run`; zu lange Namen werden gekürzt. Wirft [ArgumentError],
/// wenn [extension] nicht nur aus `a-z 0-9` besteht (1 bis 8 Zeichen).
String exportFileName(String base, String extension) {
  if (!RegExp(r'^[a-z0-9]{1,8}$').hasMatch(extension)) {
    throw ArgumentError.value(extension, 'extension');
  }
  final safe = base
      .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_')
      .replaceAll(RegExp(r'^[._]+'), '');
  final room = maxExportFileNameLength - extension.length - 1;
  final cut = safe.length > room ? safe.substring(0, room) : safe;
  return '${cut.isEmpty ? 'run' : cut}.$extension';
}
