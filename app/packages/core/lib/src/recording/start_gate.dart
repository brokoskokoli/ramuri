import '../../ports/location_access.dart';

/// Grund, aus dem kein Lauf startet (FR-0195). Die Oberfläche erklärt ihn.
enum StartBlock {
  /// Keine Standortberechtigung.
  permissionDenied,

  /// Nur ungefährer Standort; der Lauf verlangt genauen (OQ-0064).
  approximateOnly,

  /// GPS ist im System ausgeschaltet.
  gpsOff,

  /// Der Stand ließ sich nicht ermitteln; kein Start (sicher scheitern).
  unknown,
}

/// Ergebnis der Startprüfung: [block] ist `null`, wenn der Lauf starten darf.
class StartReadiness {
  const StartReadiness(this.block);

  final StartBlock? block;

  bool get canStart => block == null;
}

/// Prüft vor dem Start, ob genauer Standort erteilt und GPS an ist.
class RecordingStartGate {
  RecordingStartGate(this._access);

  final LocationAccessPort _access;

  /// Mit [askUser] zeigt das System den Berechtigungsdialog, falls nötig.
  /// Die Prüfung fragt nie, wenn der genaue Standort schon erteilt ist.
  Future<StartReadiness> check({bool askUser = false}) async {
    try {
      var access = await _access.access();
      if (access != LocationAccess.precise && askUser) {
        access = await _access.request();
      }
      switch (access) {
        case LocationAccess.denied:
          return const StartReadiness(StartBlock.permissionDenied);
        case LocationAccess.approximateOnly:
          return const StartReadiness(StartBlock.approximateOnly);
        case LocationAccess.precise:
          break;
      }
      if (!await _access.gpsEnabled()) {
        return const StartReadiness(StartBlock.gpsOff);
      }
      return const StartReadiness(null);
    } on Object {
      return const StartReadiness(StartBlock.unknown);
    }
  }
}
