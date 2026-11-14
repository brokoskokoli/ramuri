import 'package:flutter/widgets.dart';

import 'health_connect_controller.dart';

/// Hält den Health-Connect-Controller der aktuellen Sitzung über dem Navigator (wie `MapConsentHolder`), damit auch
/// normal geöffnete Seiten ihn sehen. Die Wurzel der Sitzung bindet ihn beim Start und löst ihn beim Ende.
class HealthConnectHolder {
  HealthConnectController? _controller;

  HealthConnectController? get controller => _controller;

  void bind(HealthConnectController controller) => _controller = controller;

  void unbind(HealthConnectController controller) {
    if (identical(_controller, controller)) _controller = null;
  }
}

class HealthConnectScope extends InheritedWidget {
  const HealthConnectScope({
    super.key,
    required this.holder,
    required super.child,
  });

  final HealthConnectHolder holder;

  /// Controller der Sitzung; `null` ohne Scope oder ohne Speicher für Gesundheitsdaten.
  static HealthConnectController? of(BuildContext context) => context
      .getInheritedWidgetOfExactType<HealthConnectScope>()
      ?.holder
      .controller;

  @override
  bool updateShouldNotify(HealthConnectScope old) => holder != old.holder;
}
