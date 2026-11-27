import 'package:core/core.dart';
import 'package:flutter/widgets.dart';

import 'archive_wiring.dart';

/// Archivdienste der App (WP12) für die Oberfläche; in Tests die Fakes aus
/// `AppDependencies`.
class ArchiveScope extends InheritedWidget {
  const ArchiveScope({
    super.key,
    this.export,
    this.restore,
    this.verify,
    this.headerCheck = precheckArchiveFile,
    this.start,
    required super.child,
  });

  final ArchiveExportFactory? export;
  final ArchiveRestoreFactory? restore;
  final ArchiveVerifier? verify;

  /// Vorprüfung des Kopfes vor der Passwortabfrage (FR-0198).
  final ArchiveHeaderCheck headerCheck;

  /// Ziel der neuen Sitzung (in der App der Start der Speicherschicht): Der
  /// Import übergibt ihm die neue Sitzung.
  final ArchiveSessionTarget? start;

  /// Ohne Scope oder ohne Export `null`: Dann bietet die Oberfläche keinen
  /// Export an.
  static ArchiveExportFactory? exportOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ArchiveScope>()?.export;

  static ArchiveRestoreFactory? restoreOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ArchiveScope>()?.restore;

  static ArchiveVerifier? verifyOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ArchiveScope>()?.verify;

  /// Ohne Scope die Prüfung der echten Datei.
  static ArchiveHeaderCheck headerCheckOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ArchiveScope>()?.headerCheck ??
      precheckArchiveFile;

  static ArchiveSessionTarget? startOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ArchiveScope>()?.start;

  @override
  bool updateShouldNotify(ArchiveScope old) =>
      export != old.export ||
      restore != old.restore ||
      verify != old.verify ||
      headerCheck != old.headerCheck ||
      start != old.start;
}
