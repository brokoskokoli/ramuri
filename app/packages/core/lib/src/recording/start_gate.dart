import 'dart:async';

import '../../ports/location_access.dart';

/// Frist für jede Antwort beim Lesen des Stands ohne Rückfrage (PAR-249):
/// Berechtigung, GPS-Schalter und die gemerkte Laufart der Seite. Kommt eine
/// Antwort nicht in dieser Zeit, gilt der Stand als unbekannt
/// ([StartBlock.unknown]): kein Start, „Erneut prüfen“. Der Dialog der
/// Berechtigung (`request`) hat keine Frist; er wartet auf den Nutzer.
const startCheckTimeout = Duration(seconds: 10);

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
  RecordingStartGate(this._access, {this.timeout = startCheckTimeout});

  final LocationAccessPort _access;

  /// Frist je Lesen ohne Rückfrage (PAR-249); kürzer nur in Tests.
  final Duration timeout;

  /// Mit [askUser] zeigt das System den Berechtigungsdialog, falls nötig.
  /// Die Prüfung fragt nie, wenn der genaue Standort schon erteilt ist.
  Future<StartReadiness> check({bool askUser = false}) async {
    try {
      var access = await _access.access().timeout(timeout);
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
      if (!await _access.gpsEnabled().timeout(timeout)) {
        return const StartReadiness(StartBlock.gpsOff);
      }
      return const StartReadiness(null);
    } on Object {
      // Auch eine Antwort, die nicht in der Frist kommt (TimeoutException).
      return const StartReadiness(StartBlock.unknown);
    }
  }
}
