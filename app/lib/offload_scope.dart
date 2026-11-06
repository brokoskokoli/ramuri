import 'package:core/core.dart';
import 'package:flutter/widgets.dart';

/// Wo rechenintensive Wiedergaben laufen (Zusammenfassung, Historie,
/// Statistik): in der App ein eigener Isolate ([isolateOffload]); Tests setzen
/// über `AppDependencies.offload` den Inline-Offload oder einen Fake ein.
/// Lesen und Speichern bleiben im Haupt-Isolate.
class OffloadScope extends InheritedWidget {
  const OffloadScope({super.key, required this.offload, required super.child});

  final Offload offload;

  /// Ohne Scope: eigener Isolate.
  static Offload of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<OffloadScope>()?.offload ??
      isolateOffload;

  @override
  bool updateShouldNotify(OffloadScope old) => offload != old.offload;
}
