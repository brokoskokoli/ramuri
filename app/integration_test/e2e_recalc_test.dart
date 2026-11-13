// E2E WP09: Neuberechnung mit echter verschluesselter DB im Emulator. Laeuft in
// der Sammlung (all_test.dart, tool/ci_e2e.sh) oder einzeln
// (flutter test integration_test/e2e_recalc_test.dart -d <emulator>). Alle Daten sind synthetisch, der Schluessel wird nie
// ausgegeben. Die Testhilfe oeffnet die Datenbank zusaetzlich zur App, nur zum
// Anlegen der Laeufe und zum Lesen, und schliesst sie sofort wieder (drift
// warnt dabei vor mehreren Verbindungen). Ausgabe: Zeilen "E2E_...".
import 'package:adapters/adapters.dart'
    hide RawAltitude, RawHeartRate, RawPosition;
import 'package:core/core.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:running_app/app.dart';
import 'package:running_app/app_dependencies.dart';
import 'package:running_app/l10n/app_localizations.dart';
import 'package:running_app/system_clock.dart';

import 'support/e2e_support.dart' show hittable, pumpFor;

const _metersPerDegree = earthRadiusMeters * 3.141592653589793 / 180;

void log(String s) {
  // ignore: avoid_print
  print('E2E_$s');
}

Future<StorageSession> _open() async {
  final path = await databasePath();
  final storage = EncryptedStorage(path);
  final service = StorageKeyService(
    keyStore: SecureKeyStore(),
    databaseFilesExist: storage.filesExist,
    generateKey: generateStorageKey,
  );
  final start = await service.decide();
  final key = switch (start) {
    OpenExistingStorage(:final key) => key,
    CreateNewStorage(:final key) => key,
    _ => throw StateError('not openable ${start.runtimeType}'),
  };
  return storage.open(key);
}

Future<void> _seed() async {
  final s = await _open();
  try {
    await _seedInto(s);
  } finally {
    await s.close();
  }
}

Future<void> _seedInto(StorageSession s) async {
  await s.profile.save(
    const ProfileRecord(maxHeartRateBpm: 190, restingHeartRateBpm: 60),
  );
  final calc = ValueCalculationService(session: s, clock: const SystemClock());
  final now = DateTime.now().toUtc();
  for (final days in [10, 3]) {
    final start = now.subtract(Duration(days: days));
    final run = await s.runs.create(startedAt: start);
    final pos = <RawPosition>[];
    final hrs = <RawHeartRate>[];
    final alts = <RawAltitude>[];
    for (var i = 0; i <= 1800; i++) {
      final t = start.add(Duration(seconds: i));
      pos.add(
        RawPosition(
          time: t,
          source: 'gps',
          latitude: 10 + i * 3.0 / _metersPerDegree,
          longitude: 20,
          accuracyMeters: 5,
        ),
      );
      hrs.add(
        RawHeartRate(
          time: t,
          source: 'strap',
          bpm: 150,
          contact: SensorContact.good,
        ),
      );
      alts.add(
        RawAltitude(
          time: t,
          source: 'baro',
          meters: 100,
          verticalAccuracyMeters: 3,
        ),
      );
    }
    await s.rawData.append(
      run.id,
      RawBatch(positions: pos, heartRates: hrs, altitudes: alts),
    );
    await s.runs.setState(
      run.id,
      RunState.finished,
      endedAt: start.add(const Duration(minutes: 30)),
    );
    await calc.calculateAfterRun(run.id);
  }
}

/// Werte (Schluessel, original/current, Basis, Qualitaet) und Rohdaten-Zaehler.
Future<String> _dump(String label) async {
  final s = await _open();
  final out = StringBuffer();
  try {
    final runs = await s.runs.list();
    final owners = <ValueOwner>[
      for (final r in runs) ValueOwner.run(r.id),
      for (final r in runs)
        if (r.endedAt != null) ValueOwner.day(dayOfRun(r)),
    ];
    for (final o in owners) {
      for (final p in await s.values.read(o)) {
        out.writeln(
          '${o.runId}/${o.day} ${p.original.key} '
          'orig=${p.original.value}@${p.original.heartRateBasis?.maxBpm}/${p.original.quality} '
          'cur=${p.current.value}@${p.current.heartRateBasis?.maxBpm}/${p.current.quality}',
        );
      }
    }
    for (final r in runs) {
      final raw = await s.rawData.read(r.id);
      out.writeln(
        'raw ${r.id} pos=${raw.positions.length} hr=${raw.heartRates.length} '
        'alt=${raw.altitudes.length} hrsum=${raw.heartRates.fold<int>(0, (a, b) => a + b.value.bpm.toInt())}',
      );
    }
    final prof = await s.profile.read();
    out.writeln(
      'profile max=${prof.maxHeartRateBpm} rest=${prof.restingHeartRateBpm}',
    );
    out.writeln(
      'pending=${await s.settings.get(RecalculationService.pendingKey)}',
    );
  } finally {
    await s.close();
  }
  final text = out.toString();
  for (final l in text.split('\n')) {
    if (l.isNotEmpty) log('$label $l');
  }
  return text;
}

/// Originalwerte (Basis, Qualitaet) und Rohdaten-Zeilen ohne die aktuellen Werte.
String _originals(String d) => d
    .split('\n')
    .where((l) => l.contains(' orig=') || l.startsWith('raw '))
    .map((l) => l.replaceFirst(RegExp(r' cur=.*'), ''))
    .join('\n');

String _vals(String d) => d
    .split('\n')
    .where((l) => !l.startsWith('profile') && !l.startsWith('pending'))
    .join('\n');

Future<void> _startApp(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(RunningApp(dependencies: AppDependencies.create()));
  await tester.pumpAndSettle(const Duration(seconds: 2));
  if (find.byKey(const Key('welcome_start')).evaluate().isNotEmpty) {
    await tester.tap(find.byKey(const Key('welcome_start')));
    await tester.pumpAndSettle();
  }
  if (find.byKey(const Key('setup_skip')).evaluate().isNotEmpty) {
    await tester.tap(find.byKey(const Key('setup_skip')));
    await tester.pumpAndSettle();
  }
}

/// Öffnet die Übersicht über das Profil-Symbol auf Heute; steht sie schon
/// oben, tut es nichts.
Future<void> openOverview(WidgetTester tester) async {
  final icon = find.byKey(const Key('home_overview'));
  if (icon.evaluate().isEmpty) return;
  await tester.tap(icon);
  await tester.pumpAndSettle();
}

/// Wartet in echter Zeit (Schritte von 50 ms, hoechstens [limit]), bis [finder]
/// etwas findet, und gibt die Wartezeit in ms zurueck. Rot mit Meldung bei Ablauf.
Future<int> _pumpUntil(
  WidgetTester tester,
  Finder finder, {
  Duration limit = const Duration(seconds: 30),
}) async {
  final watch = Stopwatch()..start();
  await tester.pump();
  while (finder.evaluate().isEmpty) {
    if (watch.elapsed > limit) {
      fail('nach ${limit.inSeconds} s nicht gefunden: $finder');
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
  return watch.elapsedMilliseconds;
}

/// Wie [_pumpUntil], aber bis [finder] nichts mehr findet (echte Wartezeit, da
/// Speichern und Neuberechnung echte Ein-/Ausgabe sind).
Future<void> _pumpUntilGone(
  WidgetTester tester,
  Finder finder, {
  Duration limit = const Duration(seconds: 60),
}) async {
  final watch = Stopwatch()..start();
  await tester.pump();
  while (finder.evaluate().isNotEmpty) {
    if (watch.elapsed > limit) {
      fail('nach ${limit.inSeconds} s noch vorhanden: $finder');
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Rot mit Diagnose, wenn ein Tipp auf [finder] ein anderes Element traefe
/// (verdeckt, Seite noch im Uebergang): nennt Seitenzustand, Lage und die
/// getroffenen Render-Typen (keine Werte). tester.tap warnt dann nur.
void _expectHittable(WidgetTester tester, Finder finder) {
  final element = tester.element(finder);
  final target = element.renderObject;
  final center = tester.getCenter(finder);
  final hit = HitTestResult();
  tester.binding.hitTestInView(hit, center, tester.view.viewId);
  if (hit.path.any((e) => e.target == target)) return;
  final route = ModalRoute.of(element);
  fail(
    'Tipp auf $finder bei $center trifft das Element nicht: '
    'Seite aktuell=${route?.isCurrent} aktiv=${route?.isActive} '
    'Scaffolds=${find.byType(Scaffold).evaluate().length} '
    'Tastaturhoehe=${tester.view.viewInsets.bottom} '
    'Treffer=${hit.path.map((e) => e.target.runtimeType).take(8).join(",")} '
    'Texte=${tester.widgetList<Text>(find.byType(Text)).map((t) => t.data?.length).take(12).join(",")}',
  );
}

Future<void> _changeMax(WidgetTester tester, String v) async {
  await openOverview(tester);
  await tester.tap(find.byKey(const Key('home_profile')));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('profile_max')), v);
  log(
    'CM max_field=${(tester.widget<TextField>(find.byKey(const Key('profile_max'))).controller?.text)}',
  );
  // Nach enterText steht die Tastatur offen und verdeckt den Knopf. Fokus
  // loesen; die System-Tastatur schliesst aber ausserhalb der Testuhr (CI API 31:
  // Tastaturhoehe noch 635 beim Tipp), pumpAndSettle wartet sie nicht ab. Darum
  // in echter Zeit warten, bis sie zu ist und der Tipp den Knopf trifft.
  final save = find.byKey(const Key('profile_save'));
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  final end = DateTime.now().add(const Duration(seconds: 20));
  while (DateTime.now().isBefore(end)) {
    if (tester.view.viewInsets.bottom == 0) {
      await tester.ensureVisible(save);
      await tester.pumpAndSettle();
      if (hittable(tester, save)) break;
    }
    await pumpFor(tester, const Duration(milliseconds: 100));
  }
  _expectHittable(tester, find.byKey(const Key('profile_save')));
  await tester.tap(find.byKey(const Key('profile_save')));
  // Das Speichern laeuft ueber echte Ein-/Ausgabe (verschluesselte DB), die
  // pump/pumpAndSettle nicht abwarten: erst bis die Rueckmeldung steht.
  final waited = await _pumpUntil(tester, find.byType(SnackBar));
  log('CM save_wait_ms=$waited');
  log(
    'CM banner=${find.byKey(const Key('profile_banner')).evaluate().length} note=${find.byKey(const Key('profile_saved_note')).evaluate().length} snack=${find.byType(SnackBar).evaluate().length}',
  );
  final l10n = AppLocalizations.of(tester.element(find.byType(Scaffold).last));
  final snackbarText = tester
      .widgetList<SnackBar>(find.byType(SnackBar))
      .map((s) => (s.content as Text).data!)
      .join();
  log('CM snackbar_text=${snackbarText.replaceAll('\n', ' / ')}');
  expect(snackbarText, '${l10n.profileSaved}\n${l10n.recalcOffered}');
  await tester.tap(find.byType(BackButton));
  await tester.pumpAndSettle();
}

Future<void> _openSettings(WidgetTester tester) async {
  await openOverview(tester);
  await tester.tap(find.byKey(const Key('home_settings')));
  await tester.pumpAndSettle();
}

String _texts(WidgetTester tester, String key) => tester
    .widgetList<Text>(
      find.descendant(of: find.byKey(Key(key)), matching: find.byType(Text)),
    )
    .map((t) => t.data)
    .join(' | ');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('WP09 Neuberechnung E2E', (tester) async {
    try {
      await _scenario(tester);
    } catch (_) {
      // Fuer das CI-Bildschirmfoto bei Rot (tool/ci_e2e.sh): Die App bleibt kurz
      // offen und zeigt den Fehlerzustand, dann wird der Fehler neu geworfen.
      log('CI_FAIL_HOLD');
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(seconds: 20)),
      );
      rethrow;
    }
  }, timeout: const Timeout(Duration(minutes: 10)));
}

Future<void> _scenario(WidgetTester tester) async {
  await tester.runAsync(() => _seed());
  final base = await tester.runAsync(() => _dump('S0')) as String;

  await _startApp(tester);
  expect(find.byKey(const Key('home_screen')), findsOneWidget);
  await _openSettings(tester);
  expect(find.byKey(const Key('recalc_dialog')), findsNothing);
  await tester.tap(find.byType(BackButton));
  await tester.pumpAndSettle();

  // Szenario 1
  await _changeMax(tester, '180');
  await _openSettings(tester);
  expect(find.byKey(const Key('recalc_dialog')), findsOneWidget);
  expect(find.byKey(const Key('recalc_cause_heartRateBasis')), findsOne);
  log('S1 card=${_texts(tester, 'recalc_dialog')}');
  final s1 = await tester.runAsync(() => _dump('S1')) as String;
  expect(_vals(s1), _vals(base));
  expect(s1, contains('profile max=180'));
  expect(s1, isNot(contains('pending=\n')));

  // Szenario 2
  await tester.tap(find.byKey(const Key('recalc_decline')));
  await _pumpUntilGone(tester, find.byKey(const Key('recalc_dialog')));
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('recalc_dialog')), findsNothing);
  final s2 = await tester.runAsync(() => _dump('S2')) as String;
  expect(_vals(s2), _vals(base));
  expect(s2, contains('profile max=180'));
  expect(s2, contains('pending=\n'));
  log('S2 card gone');

  // Szenario 3
  await tester.tap(find.byType(BackButton));
  await tester.pumpAndSettle();
  log(
    'S3 home_visible=${find.byKey(const Key('home_profile')).evaluate().isNotEmpty}',
  );
  await _changeMax(tester, '175');
  await tester.runAsync(() => _dump('S3pre'));
  await _openSettings(tester);
  expect(find.byKey(const Key('recalc_confirm')), findsOneWidget);
  final s3a = await tester.runAsync(() => _dump('S3a')) as String;
  await tester.tap(find.byKey(const Key('recalc_confirm')));
  await tester.pump();
  log(
    'S3 progress_visible=${find.byKey(const Key('recalc_progress')).evaluate().isNotEmpty}',
  );
  await _pumpUntilGone(tester, find.byKey(const Key('recalc_confirm')));
  await tester.pumpAndSettle(const Duration(seconds: 1));
  expect(find.byKey(const Key('recalc_confirm')), findsNothing);
  log(
    'S3 status=${tester.widget<Text>(find.byKey(const Key('recalc_status'))).data}',
  );
  final s3 = await tester.runAsync(() => _dump('S3')) as String;
  expect(s3, isNot(s3a));
  expect(s3, contains('cur='));
  expect(s3.contains('cur=') && s3.contains('@175'), isTrue);
  // Originale (Basis 190, Qualitaet) und Rohdaten bleiben wie im Ausgangszustand.
  expect(_originals(s3), _originals(base));
  expect(_originals(s3), contains('@190/'));
  expect(_originals(s3), isNot(contains('@175')));

  // Szenario 4: Basis erneut aendern, nicht beantworten, App neu starten
  await tester.tap(find.byType(BackButton));
  await tester.pumpAndSettle();
  await _changeMax(tester, '170');
  await _startApp(tester);
  await _openSettings(tester);
  expect(find.byKey(const Key('recalc_dialog')), findsOneWidget);
  log('S4 card_after_restart=${_texts(tester, 'recalc_dialog')}');
  final s4 = await tester.runAsync(() => _dump('S4')) as String;
  expect(s4, contains('pending='));
  expect(s4, isNot(contains('pending=\n')));
  expect(_originals(s4), _originals(base));
}
