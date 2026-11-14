// E2E: Erholung (WP34) in der echten App mit echtem Speicher. Testdaten werden
// direkt in den Speicher geschrieben (Health-Connect-Reihen, Morgenmessungen,
// Einwilligungen, Warnsignal, Entwicklermodus); die Oberflaeche liest sie wie
// im Betrieb. Szenarien in Reihenfolge, jedes baut auf dem Stand des vorigen auf:
//  1 Basisstufe: kein Gesundheitsdatum, Warnsignal als Ausloeser, Stufe auf der Karte
//  2 Entwicklermodus aus + gespeicherte Morgenmessungen: weiter Basis
//  3 Entwicklermodus an: erweiterte Stufe (Kamera), Warnsignal vor der Einschaetzung,
//    Detailseite, Verlauf (Kamerareihen), Karten flackern beim Aufheben nicht
//  4 Entwicklermodus wieder aus: Basis
//  5 Health-Connect-Reihen (Einwilligung HRV, Ruhepuls, Schlaf), Detailseite, Verlauf mit Luecke
//  6 beide Quellen: Verlauf trennt die Quellen
//  7 Ortstag: Uhr nahe Mitternacht (Emulator-Zeitzone), Tageswechsel gegenueber UTC
// Ausgabe: Zeilen "E2E_<zeit> ...", synthetische Werte und Texte. Marker "SHOT <name>".
import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:running_app/features/readiness/readiness_history_screen.dart';
import 'package:running_app/system_clock.dart';

import 'support/e2e_support.dart';

const _shots = bool.fromEnvironment('E2E_SHOTS');

Future<void> shot(WidgetTester t, String name) async {
  log('SHOT $name');
  if (_shots) await pumpFor(t, const Duration(milliseconds: 2500));
}

/// Uhr mit festem "jetzt", Versatz der Systemzeitzone (Emulator).
class _FixedClock implements Clock {
  _FixedClock(this.at);
  final DateTime at;
  final _sw = Stopwatch()..start();
  @override
  DateTime now() => at;
  @override
  Duration monotonic() => _sw.elapsed;
  @override
  Duration utcOffsetAt(DateTime t) => const SystemClock().utcOffsetAt(t);
}

DateTime _today(Clock c) {
  final n = c.now();
  final l = n.toUtc().add(c.utcOffsetAt(n));
  return DateTime(l.year, l.month, l.day);
}

/// Lokale Zeit am Tag [d] plus [days] Tage, in UTC.
DateTime _at(DateTime d, int days, int h, [int min = 0]) =>
    DateTime(d.year, d.month, d.day + days, h, min).toUtc();

/// Ruhepuls und RMSSD der Kamera: Tage -27..0 (0 = heute), heute auffaellig.
MorningMeasurement _morning(DateTime d, int day) {
  final t = _at(d, day, 7);
  return MorningMeasurement(
    measuredAt: t,
    utcOffset: DateTime(d.year, d.month, d.day + day, 7).timeZoneOffset,
    posture: RestingPosture.lying,
    deviceManufacturer: 'E2E',
    deviceModel: 'AVD',
    method: 'ppg',
    methodVersion: 1,
    quality: PpgQuality.good,
    restingHrBpm: day == 0 ? 66.0 : 56.0 + (day.abs() % 4),
    rmssdMs: day == 0 ? 30.0 : 44.0 + (day.abs() % 5) * 2,
    timingNoiseMs: 10,
    cameraIntervalsMs: const [],
    beforeValidation: false,
    outsideWindow: false,
  );
}

Future<void> _seedCamera(StorageSession s, DateTime d) async {
  for (var day = -27; day <= 0; day++) {
    await (s as MorningStorage).morning.add(_morning(d, day));
  }
}

/// HRV (Nacht, 03:00), Ruhepuls (07:00), Schlaf (22:00 bis 06:00) fuer Tage -28..0;
/// Ruhepuls fehlt an drei Tagen (Luecke); heute HRV niedrig, Ruhepuls hoch.
Future<void> _seedHealth(StorageSession s, DateTime d) async {
  final h = (s as HealthStorage).health;
  final sleep = <HealthRecord>[];
  final hrv = <HealthRecord>[];
  final rhr = <HealthRecord>[];
  for (var day = -28; day <= 0; day++) {
    final i = day + 28;
    sleep.add(
      HealthRecord(
        kind: HealthDataKind.sleep,
        id: 'e2e-sleep-$i',
        origin: 'e2e.app',
        start: _at(d, day - 1, 22),
        end: _at(d, day, 6),
      ),
    );
    hrv.add(
      HealthRecord(
        kind: HealthDataKind.hrvRmssd,
        id: 'e2e-hrv-$i',
        origin: 'e2e.app',
        start: _at(d, day, 3),
        end: _at(d, day, 3),
        value: day == 0 ? 33.0 : 46.0 + (i % 5) * 2,
        unit: 'ms',
      ),
    );
    if (day < -18 || day > -16) {
      rhr.add(
        HealthRecord(
          kind: HealthDataKind.restingHeartRate,
          id: 'e2e-rhr-$i',
          origin: 'e2e.app',
          start: _at(d, day, 7),
          end: _at(d, day, 7),
          value: day == 0 ? 63.0 : 54.0 + (i % 4),
          unit: 'bpm',
        ),
      );
    }
  }
  await h.upsertSleep(sleep);
  await h.upsertValues(hrv);
  await h.upsertValues(rhr);
}

Future<void> _consent(StorageSession s, Clock c, bool on) async {
  final cs = ConsentService(s.consents, c);
  for (final k in [
    HealthDataKind.hrvRmssd,
    HealthDataKind.restingHeartRate,
    HealthDataKind.sleep,
  ]) {
    if (on) {
      await cs.grant(healthSourceKey(k));
    } else {
      await s.consents.set(
        healthSourceKey(k),
        ConsentState.revoked,
        at: c.now(),
      );
    }
  }
}

Future<void> _warning(StorageSession s, DateTime d, {required bool on}) async {
  final store = (s as WarningStorage).warning;
  if (on) {
    await store.set(
      WarningSignal(
        reportedOn: DateTime.utc(d.year, d.month, d.day - 10),
        source: WarningSource.manual,
      ),
    );
  } else {
    await store.lift();
  }
}

Future<void> _dev(StorageSession s, Clock c, bool on) =>
    SettingsDeveloperModeStore(s.settings, c).set(on);

/// Alle Texte der Detailseite zu den Schluesseln mit Zaehler, sonst keine.
String _list(String prefix, [int max = 8]) {
  final out = <String>[];
  for (var i = 0; i < max && has('$prefix$i'); i++) {
    out.add(txt('$prefix$i'));
  }
  return out.isEmpty ? '<keine>' : out.join(' | ');
}

/// Einstellungen mit Wert protokollieren (fester Ausgangszustand).
Future<void> _state(
  WidgetTester t,
  StorageSession s,
  Clock c,
  String label,
) async {
  final dev = await t.runAsync(
    () => SettingsDeveloperModeStore(s.settings, c).read(),
  );
  final cons = <String>[];
  for (final k in [
    HealthDataKind.hrvRmssd,
    HealthDataKind.restingHeartRate,
    HealthDataKind.sleep,
  ]) {
    final g = await t.runAsync(
      () => ConsentService(s.consents, c).isGranted(healthSourceKey(k)),
    );
    cons.add('${k.key}=$g');
  }
  final w = await t.runAsync((s as WarningStorage).warning.read);
  final morning = (await t.runAsync(
    () => (s as MorningStorage).morning.list(),
  ))!.length;
  final now = c.now();
  log(
    '$label STATE dev=$dev consents{${cons.join(',')}} warnung=${w != null} '
    'morgenmessungen=$morning tz=${DateTime.now().timeZoneName} '
    'offset=${c.utcOffsetAt(now).inMinutes}min now_utc=${now.toIso8601String()}',
  );
}

/// Heute neu aufbauen (neuer Seitenzustand, gleicher Speicher).
Future<void> _heute(WidgetTester t, World w) async {
  await startApp(t, w);
  await _onHome(t);
}

/// Heute steht, wenn die Uebersicht-Taste da ist (die Startkarte kann unter den
/// Karten ausserhalb des gebauten Bereichs liegen).
Future<void> _onHome(WidgetTester t) async {
  await waitFor(
    t,
    () => has('home_overview') || has('welcome_start') || has('setup_skip'),
    'Heute',
  );
  if (has('welcome_start') || has('setup_skip')) await setupIfShown(t);
  // Die Karten erscheinen erst, wenn Import und Erholung geladen sind.
  await waitFor(
    t,
    () => has('readiness_card') || has('home_recovery_card'),
    'Karte auf Heute',
  );
  await pumpFor(t, const Duration(seconds: 2));
  // Ohne Systemrecht in Health Connect (AVD) fragt die App je Art nach dem
  // Loeschen (SEC-0007); der Test beantwortet mit "Abbrechen, weiter lesen".
  for (var i = 0; i < 4 && has('health_delete_cancel'); i++) {
    log('Loeschfrage beantwortet mit Abbrechen (Nr. ${i + 1})');
    await tapDialog(t, 'health_delete_cancel');
    await pumpFor(t, const Duration(seconds: 1));
  }
}

String _heuteCards() =>
    'recovery=${has('home_recovery_card')} readiness=${has('readiness_card')} '
    'basis_note=${has('readiness_basis_note')}';

/// Werte des Diagramms zu [key] (null = Luecke), aus dem Painter.
List<double?> _chart(String key) {
  final w = find.byKey(Key(key)).evaluate().first.widget as CustomPaint;
  return (w.painter! as ReadinessSeriesPainter).values;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Erholung: Basis, Kamera, Health Connect, Verlauf, Ortstag', (
    t,
  ) async {
    final w = buildWorld();
    final clock = w.deps.clock;
    await startApp(t, w);
    await setupIfShown(t);
    final s = await session(t, w);
    final d = _today(clock);
    log('S0 heute_ortstag=${d.toIso8601String().substring(0, 10)}');
    await _state(t, s, clock, 'S0');

    // 1) Basisstufe: Warnsignal als Ausloeser, nichts sonst.
    await t.runAsync(() => _warning(s, d, on: true));
    await _heute(t, w);
    log('S1 ${_heuteCards()}');
    expect(has('home_recovery_card'), isTrue, reason: 'S1 Hinweiskarte');
    expect(has('readiness_card'), isFalse, reason: 'S1 keine Erholungskarte');
    expect(has('readiness_basis_note'), isTrue, reason: 'S1 Basis-Satz');
    log(
      'S1 text=${txt('home_recovery_text')} note=${txt('readiness_basis_note')}',
    );
    await shot(t, 's1_basis');
    await tapKey(t, 'home_recovery_basis');
    await waitFor(t, () => has('home_recovery_basis_dialog'), 'Basis-Dialog');
    log('S1 dialog=${_list('home_recovery_basis_')}');
    await tapDialog(t, 'home_recovery_basis_close');
    log('S1 ok');

    // 2) Entwicklermodus aus, Morgenmessungen gespeichert: weiter Basis.
    await t.runAsync(() async {
      await _dev(s, clock, false);
      await _seedCamera(s, d);
    });
    await _state(t, s, clock, 'S2');
    await _heute(t, w);
    log('S2 ${_heuteCards()}');
    expect(has('readiness_card'), isFalse, reason: 'S2 Basis trotz Messungen');
    expect(has('readiness_basis_note'), isTrue);
    log('S2 ok');

    // 3) Entwicklermodus an: erweiterte Stufe, Warnsignal zuerst.
    await t.runAsync(() => _dev(s, clock, true));
    await _state(t, s, clock, 'S3');
    await _heute(t, w);
    log('S3 ${_heuteCards()}');
    expect(has('readiness_card'), isTrue, reason: 'S3 erweiterte Karte');
    expect(has('readiness_basis_note'), isFalse, reason: 'S3 kein Basis-Satz');
    final yWarn = t.getTopLeft(find.byKey(const Key('home_recovery_card'))).dy;
    final yCard = t.getTopLeft(find.byKey(const Key('readiness_card'))).dy;
    log('S3 warnung_y=${yWarn.round()} erholung_y=${yCard.round()}');
    expect(yWarn, lessThan(yCard), reason: 'S3 Warnsignal vor Einschaetzung');
    log(
      'S3 karte stage=${txt('readiness_stage')} title=${txt('readiness_title')} text=${txt('readiness_text')} warnung=${txt('home_recovery_text')}',
    );
    await shot(t, 's3_heute');
    await tapKey(t, 'readiness_where_from');
    await waitFor(t, () => has('readiness_detail'), 'Detailseite');
    await pumpFor(t, const Duration(milliseconds: 500));
    final dWarn = has('readiness_detail_warning');
    log(
      'S3 detail warning=$dWarn level=${txt('readiness_detail_level_word')} title=${txt('readiness_detail_title')} text=${txt('readiness_detail_text')}',
    );
    log('S3 detail reasons=${_list('readiness_detail_reason_')}');
    log('S3 detail facts=${_list('readiness_detail_fact_')}');
    log(
      'S3 detail drivers=${has('readiness_detail_drivers')} factors=${has('readiness_detail_factors')} missing=${has('readiness_detail_missing')} dev=${has('readiness_detail_dev')}',
    );
    expect(dWarn, isTrue, reason: 'S3 Warnung auf der Detailseite');
    await shot(t, 's3_detail');
    await tapKey(t, 'readiness_detail_series_link');
    await waitFor(t, () => has('readiness_history'), 'Verlauf');
    await pumpFor(t, const Duration(milliseconds: 500));
    for (final k in [
      'camera_hrv_0',
      'camera_restingHeartRate_1',
      'camera_hrv_1',
      'camera_restingHeartRate_0',
    ]) {
      if (has('readiness_series_$k')) {
        final v = _chart('readiness_series_chart_$k');
        log(
          'S3 verlauf $k n=${v.length} gefuellt=${v.where((e) => e != null).length} source=${txt('readiness_series_source_$k')} latest=${txt('readiness_series_latest_$k')} mark=${txt('readiness_series_mark_$k')} few=${has('readiness_series_few_$k')}',
        );
      }
    }
    expect(has('readiness_history_dev'), isTrue);
    await shot(t, 's3_verlauf');
    await back(t);
    await back(t);
    await waitFor(t, () => has('readiness_card'), 'Heute');

    // Kein Flackern: Warnsignal aufheben (Erinnerungskarte, setState mit _busy).
    final lift = find.byKey(const Key('home_warning_lift'));
    log('S3 erinnerung=${has('home_warning_reminder')}');
    expect(lift, findsOneWidget, reason: 'S3 Erinnerung mit Aufheben-Knopf');
    {
      var gone = 0;
      final idx = <int>[];
      var frames = 0;
      await t.ensureVisible(lift);
      await t.tap(lift);
      final end = DateTime.now().add(const Duration(seconds: 4));
      while (DateTime.now().isBefore(end)) {
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 16)),
        );
        await t.pump(const Duration(milliseconds: 16));
        frames++;
        if (!has('readiness_card')) {
          gone++;
          idx.add(frames);
        }
      }
      log(
        'S3 flackern frames=$frames karte_weg=$gone bei_frame=${idx.join(',')}',
      );
      expect(gone, 0, reason: 'S3 Karte flackert beim Aufheben');
    }
    log(
      'S3 nach_aufheben warnung=${has('home_recovery_card')} karte=${has('readiness_card')} warnung_gespeichert=${await t.runAsync((s as WarningStorage).warning.read) != null}',
    );
    log('S3 ok');

    // 4) Entwicklermodus wieder aus: Basis (Warnsignal wieder als Ausloeser).
    await t.runAsync(() async {
      await _dev(s, clock, false);
      await _warning(s, d, on: true);
    });
    await _state(t, s, clock, 'S4');
    await _heute(t, w);
    log('S4 ${_heuteCards()}');
    expect(has('readiness_card'), isFalse, reason: 'S4 Basis');
    expect(has('readiness_basis_note'), isTrue);
    log('S4 ok');

    // 5) Health Connect: Einwilligung, Reihen mit Luecke, ohne Warnsignal.
    await t.runAsync(() async {
      await _warning(s, d, on: false);
      await _seedHealth(s, d);
      await _consent(s, clock, true);
    });
    await _state(t, s, clock, 'S5');
    final hc = (s as HealthStorage).health;
    log(
      'S5 gespeichert hrv=${await t.runAsync(() => hc.count(HealthDataKind.hrvRmssd))} ruhepuls=${await t.runAsync(() => hc.count(HealthDataKind.restingHeartRate))} schlaf=${await t.runAsync(() => hc.count(HealthDataKind.sleep))}',
    );
    await _heute(t, w);
    log('S5 ${_heuteCards()}');
    expect(has('readiness_card'), isTrue, reason: 'S5 erweiterte Karte (HC)');
    expect(has('home_recovery_card'), isFalse, reason: 'S5 keine Warnung');
    log(
      'S5 karte stage=${txt('readiness_stage')} title=${txt('readiness_title')} text=${txt('readiness_text')}',
    );
    await shot(t, 's5_heute');
    log(
      'S5 overlay dialogs=${find.byType(AlertDialog).evaluate().length} snack=${find.byType(SnackBar).evaluate().length} sheet=${find.byType(BottomSheet).evaluate().length} barrier=${find.byType(ModalBarrier).evaluate().length} hittable=${hittable(t, find.byKey(const Key('readiness_where_from')))}',
    );
    await pumpFor(t, const Duration(seconds: 12));
    log(
      'S5 nach_pause hittable=${hittable(t, find.byKey(const Key('readiness_where_from')))} ${_heuteCards()}',
    );
    await tapKey(t, 'readiness_where_from');
    await waitFor(t, () => has('readiness_detail'), 'Detailseite HC');
    await pumpFor(t, const Duration(milliseconds: 500));
    expect(
      has('readiness_detail_warning'),
      isFalse,
      reason: 'S5 keine Warnung',
    );
    log(
      'S5 detail level=${txt('readiness_detail_level_word')} title=${txt('readiness_detail_title')} text=${txt('readiness_detail_text')} dev=${has('readiness_detail_dev')}',
    );
    log('S5 detail reasons=${_list('readiness_detail_reason_')}');
    log('S5 detail facts=${_list('readiness_detail_fact_')}');
    log(
      'S5 detail drivers=${has('readiness_detail_drivers')} factors=${has('readiness_detail_factors')} missing=${has('readiness_detail_missing')}',
    );
    await shot(t, 's5_detail');
    await tapKey(t, 'readiness_detail_series_link');
    await waitFor(t, () => has('readiness_history'), 'Verlauf HC');
    await pumpFor(t, const Duration(milliseconds: 500));
    for (final k in [
      'hc_hrv_0',
      'hc_restingHeartRate_1',
      'hc_hrv_1',
      'hc_restingHeartRate_0',
    ]) {
      if (has('readiness_series_$k')) {
        final v = _chart('readiness_series_chart_$k');
        log(
          'S5 verlauf $k n=${v.length} gefuellt=${v.where((e) => e != null).length} luecken=${[for (var i = 0; i < v.length; i++)
            if (v[i] == null) i].join(',')} source=${txt('readiness_series_source_$k')} latest=${txt('readiness_series_latest_$k')}',
        );
      }
    }
    expect(
      has('readiness_history_dev'),
      isFalse,
      reason: 'S5 Entwicklermodus aus',
    );
    await shot(t, 's5_verlauf');
    await back(t);
    await back(t);
    log('S5 ok');

    // 6) beide Quellen: getrennte Reihen.
    await t.runAsync(() => _dev(s, clock, true));
    await _state(t, s, clock, 'S6');
    await _heute(t, w);
    await tapKey(t, 'readiness_where_from');
    await waitFor(t, () => has('readiness_detail'), 'Detailseite beide');
    log('S6 detail text=${txt('readiness_detail_text')}');
    log('S6 detail reasons=${_list('readiness_detail_reason_')}');
    log('S6 detail facts=${_list('readiness_detail_fact_')}');
    await tapKey(t, 'readiness_detail_series_link');
    await waitFor(t, () => has('readiness_history'), 'Verlauf beide');
    await pumpFor(t, const Duration(milliseconds: 500));
    final keys = [
      for (final e in find.byWidgetPredicate((x) {
        final k = x.key;
        return k is ValueKey<String> &&
            k.value.startsWith('readiness_series_') &&
            !k.value.contains('_latest_') &&
            !k.value.contains('_source_') &&
            !k.value.contains('_chart_') &&
            !k.value.contains('_mark_') &&
            !k.value.contains('_few_');
      }).evaluate())
        (e.widget.key! as ValueKey<String>).value.substring(
          'readiness_series_'.length,
        ),
    ];
    log('S6 reihen=${keys.join(',')}');
    for (final k in keys) {
      log('S6 reihe $k source=${txt('readiness_series_source_$k')}');
    }
    expect(
      keys.where((k) => k.startsWith('hc_')).length,
      2,
      reason: 'S6 zwei HC-Reihen',
    );
    expect(
      keys.where((k) => k.startsWith('camera_')).length,
      2,
      reason: 'S6 zwei Kamerareihen',
    );
    await shot(t, 's6_verlauf');
    await back(t);
    await back(t);
    log('S6 ok');

    // 7) Ortstag: feste Uhr 23:40 und 00:20 Ortszeit (Systemzeitzone des Emulators).
    for (final (label, days, h, m) in [
      ('vor_mitternacht', 0, 23, 40),
      ('nach_mitternacht', 1, 0, 20),
    ]) {
      final fake = _FixedClock(_at(d, days, h, m));
      final w2 = buildWorld(clock: fake);
      await startApp(t, w2);
      await _onHome(t);
      final fd = _today(fake);
      log(
        'S7 $label now_utc=${fake.now().toIso8601String()} ortstag=${fd.toIso8601String().substring(0, 10)} utc_tag=${fake.now().toIso8601String().substring(0, 10)} offset=${fake.utcOffsetAt(fake.now()).inMinutes}min',
      );
      log('S7 $label ${_heuteCards()}');
      if (has('readiness_card')) {
        log(
          'S7 $label karte title=${txt('readiness_title')} text=${txt('readiness_text')}',
        );
        await tapKey(t, 'readiness_where_from');
        await waitFor(t, () => has('readiness_detail'), 'Detail $label');
        log(
          'S7 $label detail facts=${_list('readiness_detail_fact_')} reasons=${_list('readiness_detail_reason_')}',
        );
        await tapKey(t, 'readiness_detail_series_link');
        await waitFor(t, () => has('readiness_history'), 'Verlauf $label');
        await pumpFor(t, const Duration(milliseconds: 500));
        for (final k in ['hc_hrv_0', 'camera_hrv_0']) {
          if (has('readiness_series_chart_$k')) {
            final v = _chart('readiness_series_chart_$k');
            log(
              'S7 $label verlauf $k letzter=${v.last == null ? 'Luecke' : 'Wert'} vorletzter=${v[v.length - 2] == null ? 'Luecke' : 'Wert'}',
            );
          }
        }
        await shot(t, 's7_${label}_verlauf');
        await back(t);
        await back(t);
      }
      await shot(t, 's7_$label');
    }
    log('S7 ok');
  });
}
