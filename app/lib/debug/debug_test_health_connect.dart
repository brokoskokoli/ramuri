import 'package:core/core.dart';
import 'package:flutter/foundation.dart';

/// Marker für den Artefaktbeleg (WP32, wie WP07/WP27): Dieser Text darf in keinem Release-APK stehen;
/// `tool/check_release_apk.sh` sucht ihn dort.
const String testHealthConnectMarker = 'RUNAPP-DEBUG-TEST-HEALTH-9c3e71';

/// Fake von Health Connect für Debug-Build und E2E (WP32): synthetische Datensätze, keine echten Daten.
///
/// Inhalt (alle relativ zu [now], also immer im 30-Tage-Fenster, und nie nach [now]: wie in Health Connect gibt
/// es keinen Satz, der erst in der Zukunft endet; die Nacht vor heute erscheint also erst nach dem Aufwachen):
/// - Schlaf: `debug.app.a` (mit Phasen) und `debug.app.b` (ohne Phasen) schreiben je drei Nächte;
/// - HRV: beide Apps mit Werten in der Schlafphase, `debug.app.b` zusätzlich ein Wert außerhalb der Schlafphase
///   (nur im 60-min-Rückfall) und Werte außerhalb 1 bis 200 ms (werden verworfen);
/// - Ruhepuls mit Werten außerhalb 30 bis 120 bpm; VO₂max;
/// - eine Trainingseinheit (Lauf, 40 min) mit Pulsverlauf.
///
/// Alle Tageszeiten gelten in Ortszeit (Zeitzone des Systems, wie [localDayRanges]): Die Nacht endet um 06:30
/// Ortszeit, damit sie in jeder Zeitzone am heutigen Ortstag endet und als Hauptschlafphase zählt (PAR-164).
/// Die Zeitpunkte werden aus Jahr, Monat und Tag gebildet und sind damit sommerzeitfest; geliefert wird UTC.
///
/// Rechte: zu Beginn keine; [requestPermissions] erteilt, was gefragt wird. Zustand wählbar ([status]).
class DebugTestHealthConnect implements HealthConnectPort {
  DebugTestHealthConnect({
    required this.now,
    this.status = HealthSdkStatus.available,
    Set<HealthDataKind> granted = const {},
  }) : _granted = {...granted} {
    // Hält den Marker im Code, sobald die Debug-Quelle erzeugt wird (Positivkontrolle am Artefakt).
    debugPrint(
      '$testHealthConnectMarker aktiv: Health-Connect-Daten sind simuliert',
    );
  }

  final DateTime Function() now;
  HealthSdkStatus status;
  final Set<HealthDataKind> _granted;

  /// Für E2E: Recht ohne Dialog entziehen (wie in den Systemeinstellungen).
  void revokePermission(HealthDataKind kind) => _granted.remove(kind);

  @override
  Future<HealthSdkStatus> sdkStatus() async => status;

  @override
  Future<Set<HealthDataKind>> grantedKinds() async => {..._granted};

  @override
  Future<Set<HealthDataKind>> requestPermissions(
    Set<HealthDataKind> kinds,
  ) async {
    if (status == HealthSdkStatus.available) _granted.addAll(kinds);
    return {..._granted};
  }

  /// Für E2E: zählt die Aufrufe; es öffnet sich nichts.
  int installOpened = 0;

  @override
  Future<bool> openInstall() async {
    installOpened++;
    return true;
  }

  @override
  Future<HealthPage> readPage({
    required HealthDataKind kind,
    required DateTime from,
    required DateTime to,
    String? pageToken,
    int? pageSize,
  }) async {
    if (!_granted.contains(kind)) {
      throw const HealthReadException(HealthReadError.permissionMissing);
    }
    final records = _records(kind)
        .where((r) => !r.end.isBefore(from) && !r.start.isAfter(to));
    return HealthPage(records.toList(), null);
  }

  /// Alle Sätze der Art, die bis [now] (einschließlich) enden.
  List<HealthRecord> _records(HealthDataKind kind) {
    final t = now().toUtc();
    return [
      for (final r in _allRecords(kind, t))
        if (!r.end.isAfter(t)) r,
    ];
  }

  List<HealthRecord> _allRecords(HealthDataKind kind, DateTime t) {
    final l = t.toLocal();
    // Zeitpunkt [hour]:[minute] Ortszeit des Tages (heute minus [n]), als UTC.
    DateTime at(int n, [int hour = 0, int minute = 0]) =>
        DateTime(l.year, l.month, l.day - n, hour, minute).toUtc();
    // Nacht n endet um 06:30 Ortszeit des Tages (heute minus n), Dauer 7,5 h.
    DateTime wake(int n) => at(n, 6, 30);
    final out = <HealthRecord>[];
    for (var n = 0; n < 3; n++) {
      final end = wake(n);
      final start = end.subtract(const Duration(hours: 7, minutes: 30));
      switch (kind) {
        case HealthDataKind.sleep:
          out.add(
            HealthRecord(
              kind: kind,
              id: 'debug-sleep-full-$n',
              origin: 'debug.app.a',
              start: start,
              end: end,
              stages: [
                HealthSleepStage(start, start.add(const Duration(hours: 4)), 4),
                HealthSleepStage(
                  start.add(const Duration(hours: 4)),
                  start.add(const Duration(hours: 6)),
                  5,
                ),
                HealthSleepStage(
                  start.add(const Duration(hours: 6)),
                  start.add(const Duration(hours: 7, minutes: 15)),
                  6,
                ),
                HealthSleepStage(
                  start.add(const Duration(hours: 7, minutes: 15)),
                  end,
                  1,
                ),
              ],
            ),
          );
          out.add(
            HealthRecord(
              kind: kind,
              id: 'debug-sleep-bare-$n',
              origin: 'debug.app.b',
              start: start.add(const Duration(minutes: 10)),
              end: end.add(const Duration(minutes: 5)),
            ),
          );
        case HealthDataKind.hrvRmssd:
          // Die Nacht beginnt (ohne Zeitumstellung) um 23:00 Ortszeit des Vortags: alle Werte in der Schlafphase
          // bis Mitternacht, damit sie auch kurz nach Mitternacht schon vorliegen (bei 30/120/210 min lagen zwei
          // davon bis 02:00 in der Zukunft).
          for (final (i, v) in [42.0, 48.0, 51.0].indexed) {
            out.add(
              _value(kind, 'full', n, i, 'debug.app.a', start, v, 15 + i * 15),
            );
          }
          // Nur diese App: ein Wert außerhalb der Schlafphase (Rückfall, liegt nach dem Aufwachen und fehlt daher
          // bis 06:50 Ortszeit) und zwei ungültige.
          out.add(_value(kind, 'bare', n, 0, 'debug.app.b', end, 38, 20));
          out.add(_value(kind, 'bare', n, 1, 'debug.app.b', start, 0.5, 50));
          out.add(_value(kind, 'bare', n, 2, 'debug.app.b', start, 250, 55));
        case HealthDataKind.restingHeartRate:
          out.add(
            _value(
              kind,
              'full',
              n,
              0,
              'debug.app.a',
              at(n),
              54.0 + n,
              // Lokale Mitternacht wie VO2max: nie hinter "jetzt" (bei 60 bzw. 90 min fehlte der Wert bis 01:30).
              0,
            ),
          );
          out.add(_value(kind, 'bare', n, 0, 'debug.app.b', at(n), 20, 0));
        case HealthDataKind.vo2Max:
          if (n == 0) {
            // Lokale Mitternacht: nie hinter "jetzt" (bei 120 min fehlte der Wert zwischen 00:00 und 02:00).
            out.add(_value(kind, 'full', n, 0, 'debug.app.a', at(0), 47.5, 0));
          }
        case HealthDataKind.exercise:
          if (n == 1) {
            // Gestern 17:00 Ortszeit.
            final s = at(1, 17);
            out.add(
              HealthRecord(
                kind: kind,
                id: 'debug-exercise-0',
                origin: 'debug.app.a',
                start: s,
                end: s.add(const Duration(minutes: 40)),
                exerciseType: 56,
              ),
            );
          }
        case HealthDataKind.heartRate:
          if (n == 1) {
            // Gestern 17:00 Ortszeit.
            final s = at(1, 17);
            out.add(
              HealthRecord(
                kind: kind,
                id: 'debug-heartrate-0',
                origin: 'debug.app.a',
                start: s,
                end: s.add(const Duration(minutes: 40)),
                samples: [
                  for (var m = 0; m <= 40; m += 2)
                    HealthHeartRateSample(
                      s.add(Duration(minutes: m)),
                      125 + (m * 2 ~/ 3),
                    ),
                ],
              ),
            );
          }
      }
    }
    return out;
  }

  HealthRecord _value(
    HealthDataKind kind,
    String tag,
    int night,
    int index,
    String origin,
    DateTime base,
    double v,
    int minutesAfter,
  ) {
    final t = base.add(Duration(minutes: minutesAfter));
    return HealthRecord(
      kind: kind,
      id: 'debug-${kind.key}-$tag-$night-$index',
      origin: origin,
      start: t,
      end: t,
      value: v,
      // Einheiten wie der echte Adapter (HealthConnectChannel.kt: toChannelMap); der Speicher verlangt sie.
      unit: switch (kind) {
        HealthDataKind.hrvRmssd => 'ms',
        HealthDataKind.restingHeartRate => 'bpm',
        _ => 'ml/min/kg',
      },
    );
  }
}
