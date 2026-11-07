import 'package:flutter/widgets.dart';

import 'archive_wiring.dart';

/// Archivdienste der App (WP12) für die Oberfläche; in Tests die Fakes aus
/// `AppDependencies`.
class ArchiveScope extends InheritedWidget {
  const ArchiveScope({
    super.key,
    this.export,
    this.restore,
    required super.child,
  });

  final ArchiveExportFactory? export;
  final ArchiveRestoreFactory? restore;

  /// Ohne Scope oder ohne Export `null`: Dann bietet die Oberfläche keinen
  /// Export an.
  static ArchiveExportFactory? exportOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ArchiveScope>()?.export;

  static ArchiveRestoreFactory? restoreOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ArchiveScope>()?.restore;

  @override
  bool updateShouldNotify(ArchiveScope old) =>
      export != old.export || restore != old.restore;
}
