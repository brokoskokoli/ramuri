import 'package:flutter/widgets.dart';

import '../storage/storage_start.dart';
import 'archive_wiring.dart';

/// Archivdienste der App (WP12) für die Oberfläche; in Tests die Fakes aus
/// `AppDependencies`.
class ArchiveScope extends InheritedWidget {
  const ArchiveScope({
    super.key,
    this.export,
    this.restore,
    this.verify,
    this.start,
    required super.child,
  });

  final ArchiveExportFactory? export;
  final ArchiveRestoreFactory? restore;
  final ArchiveVerifier? verify;

  /// Start der Speicherschicht: Der Import übergibt ihm die neue Sitzung.
  final StorageStartController? start;

  /// Ohne Scope oder ohne Export `null`: Dann bietet die Oberfläche keinen
  /// Export an.
  static ArchiveExportFactory? exportOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ArchiveScope>()?.export;

  static ArchiveRestoreFactory? restoreOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ArchiveScope>()?.restore;

  static ArchiveVerifier? verifyOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ArchiveScope>()?.verify;

  static StorageStartController? startOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ArchiveScope>()?.start;

  @override
  bool updateShouldNotify(ArchiveScope old) =>
      export != old.export ||
      restore != old.restore ||
      verify != old.verify ||
      start != old.start;
}
