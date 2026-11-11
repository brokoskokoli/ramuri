import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/history/run_detail_screen.dart';

import 'app_harness.dart';
import 'history_summary_test.dart' show seedRun, text;
import 'run_recovery_test.dart' show crash;
import 'settings_gate_storage.dart';

// Heute (FR-0209): Woche, Kilometersumme, letzter Lauf, Hinweis ohne Läufe.
// Alle Werte sind erfunden: 10 Minuten mit 3 m/s sind 1,80 km.

final Uint8List _appKey = Uint8List.fromList(List.filled(32, 7));

/// Öffnet den Speicher vor dem Start der App: Einrichtung erledigt, optional
/// Meilen.
Future<StorageSession> _preopen(Device d, {bool miles = false}) async {
  final s = await d.storage.open(_appKey);
  await s.settings.set(SettingKeys.setupDone, '1', at: DateTime.utc(2026));
  if (miles) {
    await s.settings.set(
      SettingKeys.distanceUnit,
      DistanceUnit.miles.storageValue,
      at: DateTime.utc(2026),
    );
  }
  return s;
}

/// Beendeter Lauf, der um [end] (UTC) endet und den Versatz [offset] trägt.
Future<int> _run(
  StorageSession s,
  DateTime end,
  Duration offset, {
  int minutes = 10,
}) async {
  final start = end.subtract(Duration(minutes: minutes));
  final id = await seedRun(s, start, minutes: minutes);
  await s.runs.setState(
    id,
    RunState.finished,
    endedAt: end,
    endedUtcOffset: offset,
  );
  return id;
}

Future<void> _start(Device d, WidgetTester tester, [String locale = 'de']) =>
    d.start(tester, Locale(locale));

String _dayLabel(WidgetTester tester, int i) =>
    tester.widget<Semantics>(key('week_day_$i')).properties.label!;

/// Zurück in den Vordergrund.
Future<void> _resume(WidgetTester tester) async {
  for (final s in [
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(s);
  }
  await tester.pumpAndSettle();
}

/// In den Hintergrund.
void _pause(WidgetTester tester) {
  for (final s in [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(s);
  }
}

void main() {
  testWidgets('ohne Läufe: Hinweis statt leerer Werte, Start bleibt', (
    tester,
  ) async {
    final d = Device();
    await _preopen(d);
    await _start(d, tester);
    expect(key('home_empty'), findsOneWidget);
    expect(find.textContaining('Noch kein Lauf'), findsOneWidget);
    expect(key('home_week'), findsNothing);
    expect(key('home_week_km'), findsNothing);
    expect(key('home_last_run'), findsNothing);
    expect(find.textContaining('0,00'), findsNothing);
    expect(find.text('Frei laufen'), findsOneWidget);
    expect(key('home_start_run'), findsOneWidget);
    // Kein Plan, keine Erholung, kein Wochenziel, kein Platzhalter.
    expect(find.textContaining('Erholung'), findsNothing);
    expect(find.textContaining('geplant'), findsNothing);
  });

  testWidgets('Woche Mo bis So: Haken, Tagesnamen, Summe wie die '
      'Wochenstatistik (Lokalzeit, Vorwoche)', (tester) async {
    final d = Device();
    d.clock.set(DateTime.utc(2026, 6, 10, 12)); // Mittwoch
    final s = await _preopen(d);
    const plus2 = Duration(hours: 2);
    const plus3 = Duration(hours: 3);
    const minus2 = Duration(hours: -2);
    const minus3 = Duration(hours: -3);
    // Montag früh in Ortszeit (UTC noch Sonntag): zählt zur Woche.
    await _run(s, DateTime.utc(2026, 6, 7, 23, 30), plus2);
    // Sonntag spät in Ortszeit, 20 Minuten: zählt zur Woche.
    await _run(s, DateTime.utc(2026, 6, 14, 23, 5), minus2, minutes: 20);
    // Sonntagabend UTC, in Ortszeit schon Montag der Folgewoche: nicht.
    await _run(s, DateTime.utc(2026, 6, 14, 22, 5), plus3);
    // Montag früh UTC, in Ortszeit noch Sonntag der Vorwoche: nicht.
    await _run(s, DateTime.utc(2026, 6, 8, 0, 5), minus3);
    // Mitte der Vorwoche: nicht.
    await _run(s, DateTime.utc(2026, 6, 3, 8), Duration.zero);
    await _start(d, tester);

    final km = text('home_week_km');
    expect(km, '5,40 km');
    final done = [
      for (var i = 0; i < 7; i++)
        tester.widget<Semantics>(key('week_day_$i')).properties.label!,
    ];
    expect(done, [
      'Montag, gelaufen',
      'Dienstag, kein Lauf',
      'Mittwoch, kein Lauf',
      'Donnerstag, kein Lauf',
      'Freitag, kein Lauf',
      'Samstag, kein Lauf',
      'Sonntag, gelaufen',
    ]);
    expect(
      find.descendant(of: key('home_week'), matching: find.text('Mo')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: key('home_week'),
        matching: find.byIcon(Icons.check_rounded),
      ),
      findsNWidgets(2),
    );

    // Dieselbe Summe wie die Wochenstatistik (FR-0044).
    await tester.tap(key('home_statistics'));
    await tester.pumpAndSettle();
    expect(text('stat_runs_value'), '2');
    expect(text('stat_distance_value'), km);
  });

  testWidgets('Einheiten nach Einstellung, Beschriftung auf Englisch', (
    tester,
  ) async {
    final d = Device();
    d.clock.set(DateTime.utc(2026, 6, 10, 12));
    final s = await _preopen(d, miles: true);
    await _run(s, DateTime.utc(2026, 6, 9, 9), Duration.zero);
    await _start(d, tester, 'en');
    expect(text('home_week_km'), matches(RegExp(r'^1\.12 mi$')));
    expect(text('home_last_run_values'), contains('mi'));
    expect(text('home_last_run_values'), contains('min/mi'));
    expect(_dayLabel(tester, 0), 'Monday, no run');
    expect(_dayLabel(tester, 1), 'Tuesday, ran');
    expect(
      find.descendant(of: key('home_week'), matching: find.text('Mon')),
      findsOneWidget,
    );
    expect(find.text('Today'), findsWidgets);
    expect(find.text('This week'), findsOneWidget);
    expect(find.textContaining('Last run'), findsOneWidget);
    expect(find.text('Free run'), findsOneWidget);
    // Datum lang, lokalisiert: Wochentag zuerst, ohne Jahr.
    expect(text('home_date'), 'Wednesday, June 10');
  });

  testWidgets('Datum auf Deutsch', (tester) async {
    final d = Device();
    d.clock.set(DateTime.utc(2026, 6, 10, 12));
    await _preopen(d);
    await _start(d, tester);
    expect(text('home_date'), 'Mittwoch, 10. Juni');
  });

  testWidgets('letzter Lauf: Sprung in dieselbe Detailseite wie im Verlauf', (
    tester,
  ) async {
    final d = Device();
    d.clock.set(DateTime.utc(2026, 6, 10, 12));
    final s = await _preopen(d);
    await _run(s, DateTime.utc(2026, 6, 2, 9), Duration.zero);
    final last = await _run(s, DateTime.utc(2026, 6, 9, 9), Duration.zero);
    await _start(d, tester);
    expect(text('home_last_run_values'), '1,80 km · 5:33 min/km');
    await tester.tap(key('home_last_run'));
    await tester.pumpAndSettle();
    final page = tester.widget<RunDetailScreen>(find.byType(RunDetailScreen));
    expect(page.runId, last);
    // Vollbild: keine Navigationsleiste.
    expect(find.byType(NavigationBar), findsNothing);
    expect(key('home_today'), findsNothing);
  });

  testWidgets('Lauf ohne Ende zählt nicht, wie in der Statistik', (
    tester,
  ) async {
    final d = Device();
    d.clock.set(DateTime.utc(2026, 6, 10, 12));
    final s = await _preopen(d);
    await s.runs.create(startedAt: DateTime.utc(2026, 6, 10, 8));
    await _start(d, tester);
    // Das Angebot zur Wiederaufnahme liegt über Heute; darunter zählt Heute
    // den Lauf nicht (die Läufe kommen aus derselben Quelle wie in der
    // Statistik, die unfertige Läufe auslässt).
    expect(key('recover_dialog'), findsOneWidget);
    expect(key('home_empty'), findsOneWidget);
    expect(key('home_week_km'), findsNothing);
  });

  testWidgets('lädt nach gespeichertem Wiederaufnahme-Lauf neu', (
    tester,
  ) async {
    final d = Device();
    await crash(d, tester);
    d.clock.advance(const Duration(hours: 1));
    await d.start(tester, const Locale('de'));
    // Der Dialog liegt über Heute; darunter steht noch der Hinweis.
    expect(key('recover_dialog'), findsOneWidget);
    expect(key('home_empty'), findsOneWidget);
    expect(key('home_last_run'), findsNothing);
    await tester.tap(key('recover_save'));
    await tester.pumpAndSettle();
    expect(key('recover_dialog'), findsNothing);
    expect(key('home_empty'), findsNothing);
    expect(key('home_last_run'), findsOneWidget);
    expect(key('home_week_km'), findsOneWidget);
  });

  testWidgets('Tageswechsel im Hintergrund: beim Fortsetzen zeigt Heute den '
      'neuen Tag und die neue Woche (Sonntag zu Montag)', (tester) async {
    final d = Device();
    d.clock.set(DateTime.utc(2026, 6, 14, 12)); // Sonntag
    final s = await _preopen(d);
    await _run(s, DateTime.utc(2026, 6, 14, 9), Duration.zero);
    await _start(d, tester);
    expect(text('home_date'), 'Sonntag, 14. Juni');
    expect(text('home_week_km'), '1,80 km');
    expect(_dayLabel(tester, 6), 'Sonntag, gelaufen');

    // Dieselbe Uhr am selben Tag: Fortsetzen ändert nichts.
    _pause(tester);
    d.clock.set(DateTime.utc(2026, 6, 14, 20));
    await _resume(tester);
    expect(text('home_date'), 'Sonntag, 14. Juni');
    expect(text('home_week_km'), '1,80 km');

    _pause(tester);
    d.clock.set(DateTime.utc(2026, 6, 15, 7)); // Montag, neue Woche
    await _resume(tester);
    expect(text('home_date'), 'Montag, 15. Juni');
    // Neue Woche: der Lauf vom Sonntag zählt nicht mehr, kein Haken.
    expect(text('home_week_km'), '0,00 km');
    expect(_dayLabel(tester, 6), 'Sonntag, kein Lauf');
    expect(
      find.descendant(
        of: key('home_week'),
        matching: find.byIcon(Icons.check_rounded),
      ),
      findsNothing,
    );
    // Letzter Lauf bleibt der vom Sonntag.
    expect(key('home_last_run'), findsOneWidget);
  });

  testWidgets('Beobachter wird mit dem Heute-Tab abgebaut: Fortsetzen nach '
      'Tab-Wechsel und Tageswechsel wirft nichts', (tester) async {
    final d = Device();
    d.clock.set(DateTime.utc(2026, 6, 14, 12));
    final s = await _preopen(d);
    await _run(s, DateTime.utc(2026, 6, 14, 9), Duration.zero);
    await _start(d, tester);
    await tester.tap(key('home_history'));
    await tester.pumpAndSettle();
    expect(key('home_screen'), findsNothing, reason: 'Heute ist abgebaut');
    _pause(tester);
    d.clock.set(DateTime.utc(2026, 6, 15, 7));
    await _resume(tester);
    expect(tester.takeException(), isNull);
    await tester.tap(key('home_today'));
    await tester.pumpAndSettle();
    expect(text('home_date'), 'Montag, 15. Juni');
  });

  testWidgets('Fortsetzen lädt nur bei neuem Tag neu: am selben Tag und nach '
      'dem Neuladen am neuen Tag bleibt die Anzeige stehen', (tester) async {
    final d = Device();
    d.clock.set(DateTime.utc(2026, 6, 14, 12));
    final s = await _preopen(d);
    final id = await _run(s, DateTime.utc(2026, 6, 14, 9), Duration.zero);
    await _start(d, tester);
    expect(key('home_last_run'), findsOneWidget);
    // Der Lauf verschwindet am Speicher vorbei; die Seite weiß es nicht.
    await s.deleteRun(id);

    // Selber Tag: kein Neuladen, der gelöschte Lauf steht noch da.
    _pause(tester);
    d.clock.set(DateTime.utc(2026, 6, 14, 20));
    await _resume(tester);
    expect(key('home_last_run'), findsOneWidget);
    expect(key('home_empty'), findsNothing);

    // Neuer Tag: Neuladen, der Lauf ist weg.
    _pause(tester);
    d.clock.set(DateTime.utc(2026, 6, 15, 7));
    await _resume(tester);
    expect(key('home_last_run'), findsNothing);
    expect(key('home_empty'), findsOneWidget);

    // Neuer Lauf am Speicher vorbei; am selben (neuen) Tag lädt nichts neu.
    await _run(s, DateTime.utc(2026, 6, 15, 8), Duration.zero);
    _pause(tester);
    d.clock.set(DateTime.utc(2026, 6, 15, 9));
    await _resume(tester);
    expect(key('home_last_run'), findsNothing);
    expect(key('home_empty'), findsOneWidget);
  });

  testWidgets('Tageswechsel mitten in der Woche: Datum und Heute-Kreis '
      'ziehen mit', (tester) async {
    final d = Device();
    d.clock.set(DateTime.utc(2026, 6, 10, 12)); // Mittwoch
    final s = await _preopen(d);
    await _run(s, DateTime.utc(2026, 6, 9, 9), Duration.zero);
    await _start(d, tester);
    expect(text('home_date'), 'Mittwoch, 10. Juni');
    _pause(tester);
    d.clock.set(DateTime.utc(2026, 6, 11, 6));
    await _resume(tester);
    expect(text('home_date'), 'Donnerstag, 11. Juni');
    expect(text('home_week_km'), '1,80 km');
  });

  testWidgets('Woche und Datum nach Ortszeit, nicht nach UTC: Sonntag 23:30 '
      'UTC ist bei +2 h schon Montag', (tester) async {
    final d = Device();
    d.clock.utcOffset = const Duration(hours: 2);
    d.clock.set(DateTime.utc(2026, 6, 14, 23, 30));
    final s = await _preopen(d);
    // Lauf der Vorwoche und ein Lauf der neuen Woche (Montag früh Ortszeit).
    await _run(s, DateTime.utc(2026, 6, 10, 9), const Duration(hours: 2));
    await _run(
      s,
      DateTime.utc(2026, 6, 14, 22, 10),
      const Duration(hours: 2),
      minutes: 20,
    );
    await _start(d, tester);
    expect(text('home_date'), 'Montag, 15. Juni');
    // Neue Woche (Mo 15.): nur der Lauf von 00:10 Ortszeit zählt.
    expect(text('home_week_km'), '3,60 km');
    expect(_dayLabel(tester, 0), 'Montag, gelaufen');
    expect(_dayLabel(tester, 6), 'Sonntag, kein Lauf');
    // Dieselbe Summe wie die Wochenstatistik.
    await tester.tap(key('home_statistics'));
    await tester.pumpAndSettle();
    expect(text('stat_runs_value'), '1');
    expect(text('stat_distance_value'), '3,60 km');
  });

  testWidgets('Wochensumme aus einem Teil der Läufe sagt es, wie die '
      'Statistik', (tester) async {
    final d = Device();
    d.clock.set(DateTime.utc(2026, 6, 10, 12));
    final s = await _preopen(d);
    await _run(s, DateTime.utc(2026, 6, 9, 9), Duration.zero);
    // Beendet, aber ohne Messwerte: keine Strecke.
    final empty = await s.runs.create(startedAt: DateTime.utc(2026, 6, 8, 9));
    await s.runs.setState(
      empty.id,
      RunState.finished,
      endedAt: DateTime.utc(2026, 6, 8, 9),
      endedUtcOffset: Duration.zero,
    );
    await _start(d, tester);
    expect(text('home_week_km'), '1,80 km');
    expect(text('home_week_partial'), 'Aus 1 von 2 Läufen');
    await tester.tap(key('home_statistics'));
    await tester.pumpAndSettle();
    expect(text('stat_distance_value'), '1,80 km');
    expect(find.text('Aus 1 von 2 Läufen'), findsWidgets);
  });

  testWidgets('Wochensumme vollständig: kein Teilhinweis', (tester) async {
    final d = Device();
    d.clock.set(DateTime.utc(2026, 6, 10, 12));
    final s = await _preopen(d);
    await _run(s, DateTime.utc(2026, 6, 9, 9), Duration.zero);
    await _start(d, tester);
    expect(key('home_week_partial'), findsNothing);
  });

  testWidgets('Zurück von Alles löschen bei Lesefehler der Einstellungen: '
      'Heute meldet und lädt neu', (tester) async {
    final d = Device();
    d.clock.set(DateTime.utc(2026, 6, 10, 12));
    final s = await _preopen(d);
    await _run(s, DateTime.utc(2026, 6, 9, 9), Duration.zero);
    final gate = SettingsGateStorage(d.storage);
    d.storageOverride = gate;
    await _start(d, tester);
    expect(key('home_last_run'), findsOneWidget);
    await openOverview(tester);
    await tester.tap(key('overview_data'));
    await tester.pumpAndSettle();
    // Nach dem Löschen scheitert das Neulesen der Einstellungen: die Seite
    // bleibt stehen, es gibt kein popUntil.
    gate.failGets = true;
    await tester.tap(find.text('Alles löschen'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Alles löschen'),
      ),
    );
    await tester.pumpAndSettle();
    gate.failGets = false;
    expect(key('overview_data'), findsNothing);
    expect(find.text('Alles löschen'), findsWidgets);
    // Deutsch: pageBack sucht den englischen Tooltip „Back“.
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(key('home_screen'), findsOneWidget);
    expect(key('home_last_run'), findsNothing);
    expect(key('home_empty'), findsOneWidget);
  });

  testWidgets('Ladefehler sichtbar, Start bleibt, Erneut lädt', (tester) async {
    final d = Device();
    d.clock.set(DateTime.utc(2026, 6, 10, 12));
    final s = await _preopen(d);
    await _run(s, DateTime.utc(2026, 6, 9, 9), Duration.zero);
    final flaky = _FlakyStorage(d.storage)..failRuns = true;
    d.storageOverride = flaky;
    await _start(d, tester);
    expect(key('home_failed'), findsOneWidget);
    expect(find.textContaining('nicht gelesen'), findsOneWidget);
    expect(find.textContaining('0,00'), findsNothing);
    expect(key('home_week_km'), findsNothing);
    expect(key('home_start_run'), findsOneWidget);
    flaky.failRuns = false;
    await tester.tap(key('home_retry'));
    await tester.pumpAndSettle();
    expect(key('home_failed'), findsNothing);
    expect(text('home_week_km'), '1,80 km');
  });

  testWidgets('Design: Tage vergangen/heute/künftig, Summe fett in Sora, '
      'Symbol-Kästchen beim letzten Lauf, Liste im Verlauf-Tab', (
    tester,
  ) async {
    final d = Device();
    d.clock.set(DateTime.utc(2026, 6, 10, 12)); // Mittwoch
    final s = await _preopen(d);
    await _run(s, DateTime.utc(2026, 6, 8, 8), Duration.zero); // Montag
    await _start(d, tester);
    String kind(int i) {
      for (final k in [
        'week_dot_done',
        'week_dot_past',
        'week_dot_today',
        'week_dot_future',
      ]) {
        if (find
            .descendant(of: key('week_day_$i'), matching: key(k))
            .evaluate()
            .isNotEmpty) {
          return k;
        }
      }
      return 'keiner';
    }

    expect(
      [for (var i = 0; i < 7; i++) kind(i)],
      [
        'week_dot_done',
        'week_dot_past',
        'week_dot_today',
        'week_dot_future',
        'week_dot_future',
        'week_dot_future',
        'week_dot_future',
      ],
    );
    final km = tester.widget<Text>(key('home_week_km'));
    expect(km.style!.fontFamily, 'Sora');
    expect(km.style!.fontWeight, FontWeight.w700);
    expect(
      find.descendant(
        of: key('home_last_run'),
        matching: find.byIcon(Icons.timeline_rounded),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: key('home_history'),
        matching: find.byIcon(Icons.format_list_bulleted_rounded),
      ),
      findsOneWidget,
    );
  });
}

/// Speicher, dessen Läufe sich nicht lesen lassen, solange [failRuns] gilt.
class _FlakyStorage implements Storage {
  _FlakyStorage(this.inner);
  final Storage inner;
  bool failRuns = false;
  @override
  Future<StorageSession> open(Uint8List key) async =>
      _Session(this, await inner.open(key));
}

class _Session implements StorageSession {
  _Session(this.o, this.s);
  final _FlakyStorage o;
  final StorageSession s;
  @override
  RunStore get runs => _Runs(o, s.runs);
  @override
  RawDataStore get rawData => s.rawData;
  @override
  SettingsStore get settings => s.settings;
  @override
  ProfileStore get profile => s.profile;
  @override
  RunMarkerStore get markers => s.markers;
  @override
  PreprocessingStore get preprocessing => s.preprocessing;
  @override
  RatedSectionStore get sections => s.sections;
  @override
  ComputedValueStore get values => s.values;
  @override
  KnownDeviceStore get devices => s.devices;
  @override
  ConsentStore get consents => s.consents;
  @override
  RunSubjectiveStore get subjective => s.subjective;
  @override
  ManualTrainingStore get manualTrainings => s.manualTrainings;
  @override
  Future<void> deleteRun(int runId) => s.deleteRun(runId);
  @override
  Future<void> deleteAll() => s.deleteAll();
  @override
  Future<void> close() => s.close();
}

class _Runs implements RunStore {
  _Runs(this.o, this.inner);
  final _FlakyStorage o;
  final RunStore inner;
  @override
  Future<StoredRun> create({required DateTime startedAt}) =>
      inner.create(startedAt: startedAt);
  @override
  Future<void> setState(
    int runId,
    RunState state, {
    DateTime? endedAt,
    Duration? endedUtcOffset,
  }) => inner.setState(
    runId,
    state,
    endedAt: endedAt,
    endedUtcOffset: endedUtcOffset,
  );
  @override
  Future<StoredRun?> get(int runId) => inner.get(runId);
  @override
  Future<List<StoredRun>> list() {
    if (o.failRuns) {
      return Future.error(const StorageException(StorageFailure.failed));
    }
    return inner.list();
  }

  @override
  Future<List<StoredRun>> finishedBetween(DateTime from, DateTime to) =>
      inner.finishedBetween(from, to);

  @override
  Future<List<StoredRun>> unfinished() => inner.unfinished();
}
