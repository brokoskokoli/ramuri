import 'package:core/core.dart';
import 'package:flutter/foundation.dart';

/// Marker für den Artefaktbeleg (WP32, wie WP07/WP27): Dieser Text darf in keinem Release-APK stehen;
/// `tool/check_release_apk.sh` sucht ihn dort.
const String testHealthConnectMarker = 'RUNAPP-DEBUG-TEST-HEALTH-9c3e71';

/// Fake von Health Connect für Debug-Build und E2E (WP32): synthetische Datensätze, keine echten Daten.
///
/// Inhalt (alle relativ zu [now], also immer im 30-Tage-Fenster):
/// - Schlaf: `debug.app.a` (mit Phasen) und `debug.app.b` (ohne Phasen) schreiben je drei Nächte;
/// - HRV: beide Apps mit Werten in der Schlafphase, `debug.app.b` zusätzlich ein Wert außerhalb der Schlafphase
///   (nur im 60-min-Rückfall) und Werte außerhalb 1 bis 200 ms (werden verworfen);
/// - Ruhepuls mit Werten außerhalb 30 bis 120 bpm; VO₂max;
/// - eine Trainingseinheit (Lauf, 40 min) mit Pulsverlauf.
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

  List<HealthRecord> _records(HealthDataKind kind) {
    final t = now().toUtc();
    final day = DateTime.utc(t.year, t.month, t.day);
    // Nacht n endet um 06:30 UTC des Tages (heute minus n), Dauer 7,5 h.
    DateTime wake(int n) => day
        .subtract(Duration(days: n))
        .add(const Duration(hours: 6, minutes: 30));
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
          for (final (i, v) in [42.0, 48.0, 51.0].indexed) {
            out.add(
              _value(kind, 'full', n, i, 'debug.app.a', start, v, 30 + i * 90),
            );
          }
          // Nur diese App: ein Wert außerhalb der Schlafphase (Rückfall) und zwei ungültige.
          out.add(_value(kind, 'bare', n, 0, 'debug.app.b', end, 38, 20));
          out.add(_value(kind, 'bare', n, 1, 'debug.app.b', start, 0.5, 60));
          out.add(_value(kind, 'bare', n, 2, 'debug.app.b', start, 250, 120));
        case HealthDataKind.restingHeartRate:
          out.add(
            _value(
              kind,
              'full',
              n,
              0,
              'debug.app.a',
              day.subtract(Duration(days: n)),
              54.0 + n,
              60,
            ),
          );
          out.add(
            _value(
              kind,
              'bare',
              n,
              0,
              'debug.app.b',
              day.subtract(Duration(days: n)),
              20,
              90,
            ),
          );
        case HealthDataKind.vo2Max:
          if (n == 0) {
            out.add(_value(kind, 'full', n, 0, 'debug.app.a', day, 47.5, 120));
          }
        case HealthDataKind.exercise:
          if (n == 1) {
            final s = day
                .subtract(const Duration(days: 1))
                .add(const Duration(hours: 17));
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
            final s = day
                .subtract(const Duration(days: 1))
                .add(const Duration(hours: 17));
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
      unit: kind == HealthDataKind.hrvRmssd ? 'ms' : null,
    );
  }
}
