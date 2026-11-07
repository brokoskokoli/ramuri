import 'dart:typed_data';

/// Eine fertige Datei für die Übergabe an das System (FR-0201): Teilen-Menü
/// oder Dokumentenziel. Genau eine Quelle: [bytes] im Speicher (kleine
/// Dateien, z. B. ein Lauf) oder [path] einer Datei, die schon unter
/// [FileHandoff.exportDirectory] liegt (große Dateien, z. B. ein Archiv);
/// dann gehen nur Name und Pfad an die Plattform, die Bytes nicht.
class ExportFile {
  /// Inhalt im Speicher. Wirft [ArgumentError], wenn [fileName] kein sicherer
  /// Dateiname ist ([isSafeExportFileName]) oder [mimeType] nicht die Form
  /// `typ/untertyp` hat.
  ExportFile({
    required this.fileName,
    required this.mimeType,
    required Uint8List this.bytes,
  }) : path = null {
    _check();
  }

  /// Datei unter [FileHandoff.exportDirectory]. [path] ist absolut und ohne
  /// `.`/`..`-Abschnitte, sonst [ArgumentError]. Ob die Datei wirklich dort
  /// liegt, prüft der Adapter (auch symbolische Links); andere Pfade lehnt er
  /// ab ([FileHandoffResult.failed]).
  ExportFile.inExportDirectory({
    required this.fileName,
    required this.mimeType,
    required String this.path,
  }) : bytes = null {
    _check();
    if (!isPlainAbsolutePath(path!)) {
      throw ArgumentError.value(path, 'path', 'kein schlichter absoluter Pfad');
    }
    // Der Name der Datei ist der Name, den der Nutzer sieht; Kotlin prüft
    // dasselbe (ExportFiles.source).
    if (path!.substring(path!.lastIndexOf('/') + 1) != fileName) {
      throw ArgumentError.value(
        path,
        'path',
        'Dateiname weicht von fileName ab',
      );
    }
  }

  final String fileName;
  final String mimeType;

  /// Inhalt im Speicher; `null` bei einer Datei über [path].
  final Uint8List? bytes;

  /// Absoluter Pfad unter [FileHandoff.exportDirectory], dessen letzter
  /// Abschnitt [fileName] ist; `null` bei [bytes].
  final String? path;

  void _check() {
    if (!isSafeExportFileName(fileName)) {
      throw ArgumentError.value(fileName, 'fileName', 'unsicherer Dateiname');
    }
    if (!_mime.hasMatch(mimeType)) {
      throw ArgumentError.value(mimeType, 'mimeType');
    }
  }

  static final _mime = RegExp(r'^[a-z0-9.+-]+/[a-z0-9.+-]+$');
}

/// Absolut (`/…`), ohne leere, `.`- oder `..`-Abschnitte und ohne
/// Steuerzeichen.
bool isPlainAbsolutePath(String path) {
  if (!path.startsWith('/') || path.length < 2) return false;
  if (RegExp(r'[\x00-\x1F\x7F\\]').hasMatch(path)) return false;
  final parts = path.substring(1).split('/');
  return parts.every((p) => p.isNotEmpty && p != '.' && p != '..');
}

/// Ergebnis einer Übergabe. Beim Teilen heißt [completed]: Ein Ziel im
/// Teilen-Menü wurde gewählt; ob das Ziel die Datei weiterverarbeitet, meldet
/// Android nicht. Beim Speichern: Die Datei ist geschrieben.
///
/// Bekannte Unschärfe beim Teilen: Android meldet die Wahl des Ziels
/// asynchron. Schließt ein Ziel sofort (oder bei der Aktion „Kopieren“ ab
/// Android 14), kann die App vorher wieder vorne sein; dann kommt
/// [cancelled], obwohl geteilt wurde. Folge nur eine fehlende Bestätigung.
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

  /// Absoluter Ordner, in den der Aufrufer eine große Datei schreibt, bevor
  /// er sie mit [ExportFile.inExportDirectory] übergibt. Er ist nur Ablage
  /// für die Übergabe: Die Plattform räumt ihn beim Start und vor jedem
  /// Teilen auf (außer der geteilten Datei). `null`, wenn es keinen gibt.
  /// Wirft nie.
  Future<String?> exportDirectory();

  /// Datei zum Öffnen wählen (`ACTION_OPEN_DOCUMENT`, beliebiger Typ), z. B.
  /// ein Archiv für den Reimport. Die Plattform kopiert den Inhalt als Strom
  /// in eine eigene App-Datei (nur die gewählte Datei, höchstens eine zugleich,
  /// vorher wird der Ordner geleert); [FilePickResult.path] zeigt auf diese
  /// Kopie. Eine Größengrenze gibt es nicht: Die Wahl liegt beim Nutzer, der
  /// Strom belegt keinen Arbeitsspeicher, und ein volles Gerät ergibt
  /// [FileHandoffResult.failed] (die Teilkopie wird entfernt). Wirft nie.
  Future<FilePickResult> pickFile();

  /// Entfernt die Kopie aus [pickFile] (nach dem Import, auch bei Fehlern).
  /// Die Plattform räumt sie außerdem beim Prozessstart. Wirft nie.
  Future<void> discardPicked();
}

/// Ergebnis von [FileHandoff.pickFile]: [path] nur bei [FileHandoffResult.completed].
class FilePickResult {
  const FilePickResult.completed(String this.path)
    : result = FileHandoffResult.completed;
  const FilePickResult.cancelled()
    : result = FileHandoffResult.cancelled,
      path = null;
  const FilePickResult.failed()
    : result = FileHandoffResult.failed,
      path = null;

  final FileHandoffResult result;

  /// Absoluter Pfad der Kopie unter der Plattform (nur lesen; mit [FileHandoff.discardPicked] entsorgen).
  final String? path;
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
