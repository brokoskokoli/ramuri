import 'package:core/core.dart';
import 'package:flutter/widgets.dart';

/// Übergabe von Dateien an das System (Teilen, Speichern; FR-0201). In der
/// App der Plattformkanal, in Tests [FakeFileHandoff] über
/// `AppDependencies.fileHandoff`.
class FileHandoffScope extends InheritedWidget {
  const FileHandoffScope({
    super.key,
    required this.handoff,
    required super.child,
  });

  final FileHandoff handoff;

  /// Ohne Scope `null`: Dann bietet die Oberfläche keinen Export an.
  static FileHandoff? of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<FileHandoffScope>()?.handoff;

  @override
  bool updateShouldNotify(FileHandoffScope old) => handoff != old.handoff;
}
