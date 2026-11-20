// E2E: Erholung (WP34) in der echten App mit echtem Speicher. Testdaten werden
// direkt in den Speicher geschrieben (Health-Connect-Reihen, Morgenmessungen,
// Einwilligungen, Warnsignal, Entwicklermodus); die Oberflaeche liest sie wie
// im Betrieb. Szenarien in Reihenfolge, jedes baut auf dem Stand des vorigen auf:
//  1 Basisstufe: kein Gesundheitsdatum, Warnsignal als Ausloeser, Stufe auf der Karte
//  2 Entwicklermodus aus + gespeicherte Morgenmessungen: weiter Basis
//  3 Entwicklermodus an: erweiterte Stufe (Kamera), Warnsignal vor der Einschaetzung,
//    Detailseite, Verlauf (Kamerareihen), Karten flackern beim Aufheben nicht
//  4 Entwicklermodus wieder aus: Basis
//  5 Health-Connect-Reihen (Einwilligung HRV, Ruhepuls, Schlaf), feste Uhr 09:00
//    Ortszeit: Schlaf zaehlt (PAR-164), Detailseite, Verlauf mit Luecke
//  6 beide Quellen: Verlauf trennt die Quellen
//  7 Ortstag: Uhr nahe Mitternacht (Emulator-Zeitzone), Tageswechsel gegenueber UTC;
//    Schlaf zaehlt bis Mitternacht des Endtags, danach Grund "Schlaf fehlt" (PAR-164)
// Ausgabe: Zeilen "E2E_<zeit> ...", synthetische Werte und Texte. Marker "SHOT <name>".
import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:running_app/features/readiness/readiness_history_screen.dart';
import 'package:running_app/l10n/app_localizations.dart';
import 'package:running_app/system_clock.dart';

import 'support/e2e_support.dart';

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

/// Schlaf auf der Detailseite (PAR-164, FR-0108, FR-0109). Zaehlt er
/// ([counts]), steht er als Faktor mit seinem Teilwert, nicht unter den
/// fehlenden Faktoren, und kein Grund nennt fehlenden Schlaf; sonst umgekehrt.
/// Die Uhr ist fest, das Ergebnis haengt nicht an der Uhrzeit des Laufs.
void _expectSleep(WidgetTester t, String label, {required bool counts}) {
  final l = AppLocalizations.of(
    t.element(find.byKey(const Key('readiness_detail'))),
  );
  final reasons = [
    for (var i = 0; has('readiness_detail_reason_$i'); i++)
      txt('readiness_detail_reason_$i'),
  ];
  final sleepReason = reasons.contains(l.readinessReasonSleepMissing);
  final factor = has('readiness_detail_factor_sleep');
  final missing = has('readiness_detail_missing_sleep');
  log(
    '$label schlaf faktor=$factor fehlt=$missing grund_schlaf_fehlt=$sleepReason',
  );
  expect(factor, counts, reason: '$label Schlaf als Faktor: $counts');
  expect(missing, !counts, reason: '$label Schlaf fehlt: ${!counts}');
  expect(
    sleepReason,
    !counts,
    reason: '$label Grund "Schlaf fehlt": ${!counts}',
  );
}

typedef _State = ({
  bool dev,
  Map<String, bool> consents,
  bool warning,
  int morning,
});

/// Einstellungen lesen und mit Wert protokollieren (fester Ausgangszustand).
Future<_State> _state(
  WidgetTester t,
  StorageSession s,
  Clock c,
  String label,
) async {
  final dev = await t.runAsync(
    () => SettingsDeveloperModeStore(s.settings, c).read(),
  );
  final cons = <String>[];
  final granted = <String, bool>{};
  for (final k in [
    HealthDataKind.hrvRmssd,
    HealthDataKind.restingHeartRate,
    HealthDataKind.sleep,
  ]) {
    final g = await t.runAsync(
      () => ConsentService(s.consents, c).isGranted(healthSourceKey(k)),
    );
    cons.add('${k.key}=$g');
    granted[k.key] = g!;
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
  return (dev: dev!, consents: granted, warning: w != null, morning: morning);
}

/// Heute neu aufbauen (neuer Seitenzustand, gleicher Speicher).
Future<void> _heute(WidgetTester t, World w, {int questions = 0}) async {
  await startApp(t, w);
  await _onHome(t, questions: questions);
}

/// Heute steht, wenn die Uebersicht-Taste da ist (die Startkarte kann unter den
/// Karten ausserhalb des gebauten Bereichs liegen).
Future<void> _onHome(WidgetTester t, {int questions = 0}) async {
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
  // Ohne Systemrecht in Health Connect (AVD) fragt die App je Art nach dem
  // Loeschen (SEC-0007); der Test beantwortet mit "Abbrechen, weiter lesen".
  // Je Art mit Einwilligung und Daten fragt die App einmal; die Zahl steht
  // fest, so wird auf jede Frage und danach auf das Ende der letzten gewartet.
  for (var i = 1; i <= questions; i++) {
    await waitFor(t, () => has('health_delete_cancel'), 'Loeschfrage Nr. $i');
    log('Loeschfrage beantwortet mit Abbrechen (Nr. $i)');
    await tapDialog(t, 'health_delete_cancel');
  }
  await waitFor(
    t,
    () => !has('health_delete_cancel'),
    'keine Loeschfrage mehr',
  );
}

String _heuteCards() =>
    'recovery=${has('home_recovery_card')} readiness=${has('readiness_card')} '
    'basis_note=${has('readiness_basis_note')}';

/// Werte des Diagramms zu [key] (null = Luecke), aus dem Painter.
List<double?> _chart(String key) {
  final w = find.byKey(Key(key)).evaluate().first.widget as CustomPaint;
  return (w.painter! as ReadinessSeriesPainter).values;
}

/// Schluessel der Reihen auf dem Verlauf (ohne Teil-Schluessel wie _chart_).
List<String> _seriesKeys() => [
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

List<int> _gaps(List<double?> v) => [
  for (var i = 0; i < v.length; i++)
    if (v[i] == null) i,
];

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Erholung: Basis, Kamera, Health Connect, Verlauf, Ortstag', (
    t,
  ) async {
    final w = buildWorld();
    step('READINESS S0 start');
    final clock = w.deps.clock;
    await startApp(t, w);
    await setupIfShown(t);
    final s = await session(t, w);
    final d = _today(clock);
    log('S0 heute_ortstag=${d.toIso8601String().substring(0, 10)}');
    final s0 = await _state(t, s, clock, 'S0');
    // Ausgangszustand der frischen Installation: sonst sagen die Stufen nichts.
    expect(s0.dev, isFalse, reason: 'S0 Entwicklermodus aus');
    expect(
      s0.consents.values.every((g) => !g),
      isTrue,
      reason: 'S0 keine Einwilligung (${s0.consents})',
    );
    expect(s0.consents.length, 3, reason: 'S0 drei Arten gelesen');
    expect(s0.warning, isFalse, reason: 'S0 kein Warnsignal');
    expect(s0.morning, 0, reason: 'S0 keine Morgenmessung');

    step('READINESS S1 basisstufe');
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
    await shotHellDunkel(t, 's1_basis', 'readiness_basis_note');
    await tapKey(t, 'home_recovery_basis');
    await waitFor(t, () => has('home_recovery_basis_dialog'), 'Basis-Dialog');
    log('S1 dialog=${_list('home_recovery_basis_')}');
    await tapDialog(t, 'home_recovery_basis_close');
    log('S1 ok');

    step('READINESS S2 morgenmessungen');
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

    step('READINESS S3 erweiterte_stufe');
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
    await shotHellDunkel(t, 's3_heute', 'readiness_card');
    step('READINESS S3 detail');
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
    await shotHellDunkel(t, 's3_detail', 'readiness_detail');
    step('READINESS S3 verlauf');
    await tapKey(t, 'readiness_detail_series_link');
    await waitFor(t, () => has('readiness_history'), 'Verlauf');
    await pumpFor(t, const Duration(milliseconds: 500));
    final camKeys = _seriesKeys();
    log('S3 reihen=${camKeys.join(',')}');
    expect(camKeys.length, 2, reason: 'S3 zwei Reihen (RMSSD, Ruhepuls)');
    for (final k in camKeys) {
      expect(k.startsWith('camera_'), isTrue, reason: 'S3 Quelle Kamera: $k');
      final v = _chart('readiness_series_chart_$k');
      log(
        'S3 verlauf $k n=${v.length} gefuellt=${v.where((e) => e != null).length} source=${txt('readiness_series_source_$k')} latest=${txt('readiness_series_latest_$k')} mark=${txt('readiness_series_mark_$k')} few=${has('readiness_series_few_$k')}',
      );
      expect(v.length, 28, reason: 'S3 $k 28 Tage');
      expect(v.where((e) => e != null).length, 28, reason: 'S3 $k 28 Werte');
      expect(
        has('readiness_series_few_$k'),
        isFalse,
        reason: 'S3 $k nicht "wenig"',
      );
    }
    expect(has('readiness_history_dev'), isTrue);
    await shotHellDunkel(t, 's3_verlauf', 'readiness_history');
    await back(t);
    await back(t);
    await waitFor(t, () => has('readiness_card'), 'Heute');

    step('READINESS S3 warnsignal_aufheben');
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

    step('READINESS S4 basis_wieder');
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

    step('READINESS S5 health_connect');
    // 5) Health Connect: Einwilligung, Reihen mit Luecke, ohne Warnsignal.
    await t.runAsync(() async {
      await _warning(s, d, on: false);
      await _seedHealth(s, d);
      await _consent(s, clock, true);
    });
    // Feste Uhr 09:00 Ortszeit am Tag d: die Sitzung der Nacht endet um 06:00
    // desselben Ortstags und zaehlt (PAR-164), gleich zu welcher Uhrzeit der
    // Lauf startet.
    final clock5 = _FixedClock(_at(d, 0, 9));
    final w5 = buildWorld(clock: clock5);
    await _state(t, s, clock5, 'S5');
    final hc = (s as HealthStorage).health;
    log(
      'S5 gespeichert hrv=${await t.runAsync(() => hc.count(HealthDataKind.hrvRmssd))} ruhepuls=${await t.runAsync(() => hc.count(HealthDataKind.restingHeartRate))} schlaf=${await t.runAsync(() => hc.count(HealthDataKind.sleep))}',
    );
    await _heute(t, w5, questions: 3);
    log('S5 ${_heuteCards()}');
    expect(has('readiness_card'), isTrue, reason: 'S5 erweiterte Karte (HC)');
    expect(has('home_recovery_card'), isFalse, reason: 'S5 keine Warnung');
    log(
      'S5 karte stage=${txt('readiness_stage')} title=${txt('readiness_title')} text=${txt('readiness_text')}',
    );
    expect(has('readiness_stage'), isTrue, reason: 'S5 Stufe auf der Karte');
    expect(txt('readiness_stage'), isNotEmpty, reason: 'S5 Stufe benannt');
    expect(txt('readiness_title'), isNotEmpty, reason: 'S5 Titel');
    final insufficient = AppLocalizations.of(
      t.element(find.byKey(const Key('readiness_title'))),
    ).readinessInsufficientTitle;
    expect(
      txt('readiness_title'),
      isNot(contains(insufficient)),
      reason: 'S5 genug Daten mit HC (28 Tage)',
    );
    await shotHellDunkel(t, 's5_heute', 'readiness_card');
    log(
      'S5 overlay dialogs=${find.byType(AlertDialog).evaluate().length} snack=${find.byType(SnackBar).evaluate().length} sheet=${find.byType(BottomSheet).evaluate().length} barrier=${find.byType(ModalBarrier).evaluate().length} hittable=${hittable(t, find.byKey(const Key('readiness_where_from')))}',
    );
    await waitFor(
      t,
      () =>
          has('readiness_where_from') &&
          hittable(t, find.byKey(const Key('readiness_where_from'))),
      'Erholungskarte bedienbar',
    );
    step('READINESS S5 detail');
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
    _expectSleep(t, 'S5', counts: true);
    await shotHellDunkel(t, 's5_detail', 'readiness_detail');
    step('READINESS S5 verlauf');
    await tapKey(t, 'readiness_detail_series_link');
    await waitFor(t, () => has('readiness_history'), 'Verlauf HC');
    await pumpFor(t, const Duration(milliseconds: 500));
    final hcKeys = _seriesKeys();
    log('S5 reihen=${hcKeys.join(',')}');
    expect(hcKeys.length, 2, reason: 'S5 zwei Reihen (HRV, Ruhepuls)');
    for (final k in hcKeys) {
      expect(
        k.startsWith('hc_'),
        isTrue,
        reason: 'S5 Quelle Health Connect: $k',
      );
      final v = _chart('readiness_series_chart_$k');
      final gaps = _gaps(v);
      log(
        'S5 verlauf $k n=${v.length} gefuellt=${v.where((e) => e != null).length} luecken=${gaps.join(',')} source=${txt('readiness_series_source_$k')} latest=${txt('readiness_series_latest_$k')}',
      );
      expect(v.length, 28, reason: 'S5 $k 28 Tage');
      expect(
        txt('readiness_series_source_$k'),
        contains('Health Connect'),
        reason: 'S5 $k Quelle genannt',
      );
      if (k.contains('restingHeartRate')) {
        expect(gaps, [9, 10, 11], reason: 'S5 Ruhepuls: Luecken Tag 9-11');
      } else {
        expect(gaps, isEmpty, reason: 'S5 HRV ohne Luecke');
      }
    }
    expect(
      has('readiness_history_dev'),
      isFalse,
      reason: 'S5 Entwicklermodus aus',
    );
    await shotHellDunkel(t, 's5_verlauf', 'readiness_history');
    await back(t);
    await back(t);
    log('S5 ok');

    step('READINESS S6 beide_quellen');
    // 6) beide Quellen: getrennte Reihen.
    await t.runAsync(() => _dev(s, clock, true));
    await _state(t, s, clock, 'S6');
    await _heute(t, w, questions: 3);
    step('READINESS S6 detail');
    await tapKey(t, 'readiness_where_from');
    await waitFor(t, () => has('readiness_detail'), 'Detailseite beide');
    log('S6 detail text=${txt('readiness_detail_text')}');
    log('S6 detail reasons=${_list('readiness_detail_reason_')}');
    log('S6 detail facts=${_list('readiness_detail_fact_')}');
    step('READINESS S6 verlauf');
    await tapKey(t, 'readiness_detail_series_link');
    await waitFor(t, () => has('readiness_history'), 'Verlauf beide');
    await pumpFor(t, const Duration(milliseconds: 500));
    final keys = _seriesKeys();
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
    await shotHellDunkel(t, 's6_verlauf', 'readiness_history');
    await back(t);
    await back(t);
    log('S6 ok');

    step('READINESS S7 ortstag');
    // 7) Ortstag: feste Uhr 23:40 und 00:20 Ortszeit (Systemzeitzone des Emulators).
    for (final (label, days, h, m) in [
      ('vor_mitternacht', 0, 23, 40),
      ('nach_mitternacht', 1, 0, 20),
    ]) {
      final fake = _FixedClock(_at(d, days, h, m));
      // Marke je Fall als Literal (step nimmt keine gebildeten Namen).
      if (days == 0) {
        step('READINESS S7 vor_mitternacht');
      } else {
        step('READINESS S7 nach_mitternacht');
      }
      final w2 = buildWorld(clock: fake);
      await startApp(t, w2);
      await _onHome(t, questions: 3);
      final fd = _today(fake);
      log(
        'S7 $label now_utc=${fake.now().toIso8601String()} ortstag=${fd.toIso8601String().substring(0, 10)} utc_tag=${fake.now().toIso8601String().substring(0, 10)} offset=${fake.utcOffsetAt(fake.now()).inMinutes}min',
      );
      log('S7 $label ${_heuteCards()}');
      // Ortstag: nach Mitternacht Ortszeit ist es der naechste Tag.
      expect(
        fd,
        DateTime(d.year, d.month, d.day + days),
        reason: 'S7 $label Ortstag',
      );
      // Die Karte steht in beiden Faellen (heute fehlen nach Mitternacht nur
      // die Tageswerte, nicht die Einwilligung).
      expect(has('readiness_card'), isTrue, reason: 'S7 $label Karte');
      log(
        'S7 $label karte title=${txt('readiness_title')} text=${txt('readiness_text')}',
      );
      await tapKey(t, 'readiness_where_from');
      await waitFor(t, () => has('readiness_detail'), 'Detail $label');
      log(
        'S7 $label detail facts=${_list('readiness_detail_fact_')} reasons=${_list('readiness_detail_reason_')}',
      );
      step('READINESS S7 schlaf_pruefen');
      // PAR-164: die Sitzung bis 06:00 des Tages d zaehlt bis Mitternacht;
      // nach Mitternacht ohne neue Sitzung fehlt der Schlaf der letzten Nacht.
      _expectSleep(t, 'S7 $label', counts: days == 0);
      await tapKey(t, 'readiness_detail_series_link');
      await waitFor(t, () => has('readiness_history'), 'Verlauf $label');
      await pumpFor(t, const Duration(milliseconds: 500));
      step('READINESS S7 verlauf');
      final keys7 = _seriesKeys();
      log('S7 $label reihen=${keys7.join(',')}');
      expect(keys7.length, 4, reason: 'S7 $label vier Reihen (HC, Kamera)');
      for (final k in keys7) {
        final v = _chart('readiness_series_chart_$k');
        log(
          'S7 $label verlauf $k letzter=${v.last == null ? 'Luecke' : 'Wert'} vorletzter=${v[v.length - 2] == null ? 'Luecke' : 'Wert'}',
        );
        if (days == 0) {
          // Vor Mitternacht ist heute der letzte Tag mit Wert (Ruhepuls und HRV
          // der Kamera und von HC haben heute einen Eintrag).
          expect(v.last, isNotNull, reason: 'S7 $label $k letzter = heute');
        } else {
          // Nach Mitternacht ist der neue Tag der letzte Punkt, ohne Wert; der
          // Tag davor hat einen (Tageswechsel am Ortstag, nicht an UTC).
          expect(v.last, isNull, reason: 'S7 $label $k neuer Tag ohne Wert');
          expect(
            v[v.length - 2],
            isNotNull,
            reason: 'S7 $label $k gestern mit Wert',
          );
        }
      }
      await shotHellDunkel(t, 's7_${label}_verlauf', 'readiness_history');
      await back(t);
      await back(t);
      await shotHellDunkel(t, 's7_$label', 'readiness_card');
    }
    log('S7 ok');
  });
}
