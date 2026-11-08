import 'package:flutter/widgets.dart';

import 'map_consent_controller.dart';

/// Hält den Kartencontroller der aktuellen Sitzung über dem Navigator, damit auch normal geöffnete Seiten ihn sehen
/// (wie `AppSettingsHolder`). Die Wurzel der Sitzung bindet ihn beim Start und löst ihn beim Ende.
class MapConsentHolder {
  MapConsentController? _controller;

  MapConsentController? get controller => _controller;

  void bind(MapConsentController controller) => _controller = controller;

  /// Löst nur, wenn noch derselbe Controller gebunden ist (eine neue Sitzung hat ihn schon ersetzt).
  void unbind(MapConsentController controller) {
    if (identical(_controller, controller)) _controller = null;
  }
}

class MapConsentScope extends InheritedWidget {
  const MapConsentScope({
    super.key,
    required this.holder,
    required super.child,
  });

  final MapConsentHolder holder;

  /// Controller der Sitzung; `null` ohne Scope oder ohne verdrahteten Kartenanbieter.
  static MapConsentController? of(BuildContext context) => context
      .getInheritedWidgetOfExactType<MapConsentScope>()
      ?.holder
      .controller;

  @override
  bool updateShouldNotify(MapConsentScope old) => holder != old.holder;
}
