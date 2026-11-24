import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:core/core.dart';
import 'package:core/fakes/fake_storage_settings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/app_dependencies.dart';
import 'package:running_app/error_counter.dart';
import 'package:running_app/features/health/health_connect_controller.dart';
import 'package:running_app/features/health/health_connect_scope.dart';
import 'package:running_app/features/storage/storage_start.dart';

import 'app_harness.dart';

/// Synthetischer „Wert“ in Fehlernachrichten; er darf nirgends gespeichert werden.
const _value = 'Ruhepuls 4711';

/// Fehler, deren Text einen Wert trägt (wie ein `toString` mit Messwert).
class _ValueError implements Exception {
  @override
  String toString() => 'Messung $_value bpm';
}

/// Stack wie aus der App: erst Flutter, dann die erste Datei der App mit Zeile
/// und Argumenten im Rahmen.
StackTrace _appStack(String file) => StackTrace.fromString(
  '#0      Element.rebuild (package:flutter/src/widgets/framework.dart:5000:7)\n'
  '#1      Foo.bar ($file:12:3)\n'
  '#2      Baz.qux (package:core/src/other.dart:3:1)\n',
);

Future<List<ErrorCount>> _stored(FakeStorage storage, ErrorCounter c) async {
  await c.idle;
  return decodeErrorCounts(storage.data.settings[SettingKeys.errorCounts]);
}

(ErrorCounter, FakeStorage) _attached({int limit = ErrorCounter.maxEntries}) {
  final storage = FakeStorage();
  final c = ErrorCounter(limit: limit)
    ..attach(
      FakeSettingsStore(storage.data),
      FakeClock(DateTime.utc(2026, 1, 1)),
    );
  return (c, storage);
}

/// Stellt die globalen Handler nach dem Test wieder her (die Testumgebung
/// braucht ihre eigenen).
void _keepGlobalHandlers() {
  final flutter = FlutterError.onError;
  final platform = PlatformDispatcher.instance.onError;
  addTearDown(() {
    FlutterError.onError = flutter;
    PlatformDispatcher.instance.onError = platform;
  });
}

/// Uhr, deren Monotonzeit scheitert: der Import selbst wirft dann (alles
/// andere fängt der Dienst schon ab).
class _FailingClock extends FakeClock {
  _FailingClock() : super(DateTime.utc(2026, 11, 14, 12));

  @override
  Duration monotonic() => throw StateError('Uhr $_value');
}

class _Port implements HealthConnectPort {
  /// Sätze für den Ruhepuls; für alles andere nichts.
  List<HealthRecord> records = const [];

  /// Diese Aufrufe werfen einen Fehler mit Wert in der Nachricht.
  Set<String> failing = const {};

  void _fail(String call) {
    if (failing.contains(call)) throw StateError(_value);
  }

  @override
  Future<HealthSdkStatus> sdkStatus() async {
    _fail('sdkStatus');
    return HealthSdkStatus.available;
  }

  @override
  Future<Set<HealthDataKind>> grantedKinds() async {
    _fail('grantedKinds');
    return HealthDataKind.values.toSet();
  }

  @override
  Future<Set<HealthDataKind>> requestPermissions(
    Set<HealthDataKind> kinds,
  ) async {
    _fail('requestPermissions');
    return kinds;
  }

  @override
  Future<bool> openInstall() async {
    _fail('openInstall');
    return true;
  }

  @override
  Future<HealthPage> readPage({
    required HealthDataKind kind,
    required DateTime from,
    required DateTime to,
    String? pageToken,
    int? pageSize,
  }) async => HealthPage(
    kind == HealthDataKind.restingHeartRate ? records : const [],
    null,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('nur Typ und Ort', () {
    test(
      'Eintrag enthält Typ und Ort, nie Nachricht, Zeile oder Stack',
      () async {
        final (c, storage) = _attached();
        c.record(
          _ValueError(),
          _appStack('package:running_app/features/x.dart'),
        );
        c.record(StateError(_value), StackTrace.current);
        final entries = await _stored(storage, c);
        expect(entries.map((e) => e.toJson()), [
          {
            'type': '_ValueError',
            'place': 'package:running_app/features/x.dart',
            'count': 1,
            'first': '2026-01-01',
            'last': '2026-01-01',
          },
          // Der Test selbst ist keine Datei der App.
          {
            'type': 'StateError',
            'place': unknownErrorPlace,
            'count': 1,
            'first': '2026-01-01',
            'last': '2026-01-01',
          },
        ]);
        final raw = storage.data.settings[SettingKeys.errorCounts]!;
        expect(raw, isNot(contains('4711')));
        expect(raw, isNot(contains('Ruhepuls')));
        expect(raw, isNot(contains('Messung')));
        expect(raw, isNot(contains(':12')));
        expect(raw, isNot(contains('Foo.bar')));
        expect(storage.data.settings.keys, [SettingKeys.errorCounts]);
      },
    );

    test('Ort: erste Datei von App, core oder adapters; sonst unbekannt', () {
      expect(
        errorPlace(_appStack('package:adapters/src/storage/a.dart')),
        'package:adapters/src/storage/a.dart',
      );
      expect(
        errorPlace(_appStack('package:other/x.dart')),
        'package:core/src/other.dart',
      );
      expect(errorPlace(null), unknownErrorPlace);
      expect(
        errorPlace(StackTrace.fromString('#00 abs 0 virt 0 _kDartIsolate')),
        unknownErrorPlace,
      );
    });

    test(
      'gleicher Typ und Ort zählt hoch, anderer Ort ist ein eigener Eintrag',
      () async {
        final (c, storage) = _attached();
        final a = _appStack('package:running_app/a.dart');
        c.record(StateError('1'), a);
        c.record(StateError('2'), a);
        c.record(StateError('3'), _appStack('package:running_app/b.dart'));
        final entries = await _stored(storage, c);
        expect(entries.map((e) => (e.place, e.count)), [
          ('package:running_app/a.dart', 2),
          ('package:running_app/b.dart', 1),
        ]);
      },
    );
  });

  group('globale Handler', () {
    test(
      'Flutter-, Plattform- und Zonenfehler werden gezählt, zweimal → 2',
      () async {
        _keepGlobalHandlers();
        final (c, storage) = _attached();
        final zoneDone = Completer<void>();
        var bodyRan = false;
        runCountingErrors(c, debugOutput: false, () {
          bodyRan = true;
          // Zweimal derselbe asynchrone Fehler in der Zone (gleicher Ort).
          final stack = _appStack('package:running_app/zone.dart');
          for (var i = 0; i < 2; i++) {
            Future<void>.error(FormatException(_value), stack);
          }
          Future<void>.delayed(Duration.zero, zoneDone.complete);
        });
        expect(bodyRan, isTrue);
        await zoneDone.future;
        expect(
          PlatformDispatcher.instance.onError,
          isNotNull,
          reason: 'Handler für Plattformfehler gesetzt',
        );
        for (var i = 0; i < 2; i++) {
          FlutterError.reportError(
            FlutterErrorDetails(
              exception: ArgumentError(_value),
              stack: _appStack('package:running_app/flutter.dart'),
            ),
          );
          final handled = PlatformDispatcher.instance.onError!(
            UnsupportedError(_value),
            _appStack('package:running_app/platform.dart'),
          );
          expect(handled, isTrue, reason: 'Release: nichts an die Engine');
        }
        final entries = await _stored(storage, c);
        expect(
          {for (final e in entries) e.type: (e.place, e.count)},
          {
            'FormatException': ('package:running_app/zone.dart', 2),
            'ArgumentError': ('package:running_app/flutter.dart', 2),
            'UnsupportedError': ('package:running_app/platform.dart', 2),
          },
        );
        expect(
          storage.data.settings[SettingKeys.errorCounts],
          isNot(contains('4711')),
        );
      },
    );

    test(
      'ohne Debug-Ausgabe kein Standard-Handler, mit Debug-Ausgabe zusätzlich',
      () {
        _keepGlobalHandlers();
        for (final debug in [false, true]) {
          final shown = <FlutterErrorDetails>[];
          FlutterError.onError = shown.add;
          final c = ErrorCounter();
          installErrorHandlers(c, debugOutput: debug);
          FlutterError.reportError(
            FlutterErrorDetails(exception: StateError(_value)),
          );
          expect(shown, hasLength(debug ? 1 : 0), reason: 'debug: $debug');
          expect(
            PlatformDispatcher.instance.onError!(
              StateError(_value),
              StackTrace.empty,
            ),
            !debug,
          );
        }
      },
    );
  });

  test('Zonenfehler: ohne Debug-Ausgabe nichts ausgegeben, mit Debug-Ausgabe zusätzlich', () async {
    _keepGlobalHandlers();
    final present = FlutterError.presentError;
    addTearDown(() => FlutterError.presentError = present);
    for (final debug in [false, true]) {
      final shown = <FlutterErrorDetails>[];
      FlutterError.presentError = shown.add;
      final (c, storage) = _attached();
      final done = Completer<void>();
      runCountingErrors(c, debugOutput: debug, () {
        Future<void>.error(
          FormatException(_value),
          _appStack('package:running_app/zone.dart'),
        );
        Future<void>.delayed(Duration.zero, done.complete);
      });
      await done.future;
      expect(shown, hasLength(debug ? 1 : 0), reason: 'debug: $debug');
      expect((await _stored(storage, c)).single.count, 1);
    }
  });

  group('Einstiege setzen die Handler', () {
    /// Quelltext ohne Zeilenkommentare.
    String code(String path) =>
        File(path)
            .readAsStringSync()
            .split('\n')
            .where((l) => !l.trimLeft().startsWith('//'))
            .join('\n');

    test(
      'main.dart startet runApp in runCountingErrors mit demselben Zähler',
      () {
        final source = code('lib/main.dart');
        expect(source, contains('final errors = ErrorCounter();'));
        final guarded = source.indexOf('runCountingErrors(errors, () {');
        expect(guarded, isNonNegative);
        expect(source.indexOf('runApp('), greaterThan(guarded));
        expect(source, contains('AppDependencies.create(errors: errors)'));
        // Release: die Ausgabe folgt kDebugMode, nie fest eingeschaltet.
        expect(source, isNot(contains('debugOutput')));
      },
    );

    test('main_debug.dart startet runApp in runCountingErrors mit demselben Zähler', () {
      final source = code('lib/main_debug.dart');
      expect(source, contains('final errors = ErrorCounter();'));
      final guarded = source.indexOf(
        'runCountingErrors(errors, () => _run(errors));',
      );
      expect(guarded, isNonNegative);
      final run = source.indexOf('void _run(ErrorCounter errors) {');
      expect(run, greaterThan(guarded));
      expect(source.indexOf('runApp('), greaterThan(run));
      expect(
        RegExp(r'AppDependencies\.create\(\s*errors: errors,').hasMatch(source),
        isTrue,
      );
      expect('runApp('.allMatches(source), hasLength(1));
      expect(source, isNot(contains('debugOutput')));
    });
  });

  group('Obergrenze', () {
    List<ErrorCount> fill(int n) {
      final entries = <ErrorCount>[];
      for (var i = 0; i < n; i++) {
        mergeErrorCount(
          entries,
          ErrorCount(type: 'E', place: 'p$i', count: 1),
          ErrorCounter.maxEntries,
        );
      }
      return entries;
    }

    test('genau 50 Einträge bleiben alle', () {
      expect(ErrorCounter.maxEntries, 50);
      final entries = fill(50);
      expect(entries, hasLength(50));
      expect(entries.first.place, 'p0');
    });

    test('der 51. verdrängt den am längsten nicht gesehenen', () {
      final entries = fill(50);
      // p0 wird erneut gesehen und rückt nach hinten; p1 ist nun der älteste.
      mergeErrorCount(
        entries,
        const ErrorCount(type: 'E', place: 'p0', count: 1),
        ErrorCounter.maxEntries,
      );
      mergeErrorCount(
        entries,
        const ErrorCount(type: 'E', place: 'neu', count: 1),
        ErrorCounter.maxEntries,
      );
      expect(entries, hasLength(50));
      expect(entries.map((e) => e.place), isNot(contains('p1')));
      expect(entries.map((e) => e.place), containsAll(['p0', 'neu']));
      expect(entries.firstWhere((e) => e.place == 'p0').count, 2);
    });

    test('auch gespeichert und vor dem Speichern höchstens 50', () async {
      final storage = FakeStorage();
      final c = ErrorCounter();
      for (var i = 0; i < 60; i++) {
        c.record(StateError('$i'), _appStack('package:running_app/f$i.dart'));
      }
      c.attach(FakeSettingsStore(storage.data), FakeClock(DateTime.utc(2026)));
      for (var i = 60; i < 70; i++) {
        c.record(StateError('$i'), _appStack('package:running_app/f$i.dart'));
      }
      final entries = await _stored(storage, c);
      expect(entries, hasLength(50));
      expect(entries.first.place, 'package:running_app/f20.dart');
      expect(entries.last.place, 'package:running_app/f69.dart');
    });
  });

  group('Speichern', () {
    test('vor dem Öffnen gepuffert, danach gespeichert; gespeicherter Stand zählt weiter', () async {
      final storage = FakeStorage();
      storage.data.settings[SettingKeys.errorCounts] = encodeErrorCounts([
        const ErrorCount(
          type: 'StateError',
          place: unknownErrorPlace,
          count: 3,
        ),
      ]);
      final c = ErrorCounter()..record(StateError(_value), null);
      await c.idle;
      c.attach(FakeSettingsStore(storage.data), FakeClock(DateTime.utc(2026)));
      final entries = await _stored(storage, c);
      expect(entries.single.count, 4);
    });

    test('scheitert das Schreiben, gehen die Zähler nicht verloren', () async {
      final storage = FakeStorage();
      final c = ErrorCounter()
        ..attach(_FailingSettings(), FakeClock(DateTime.utc(2026)));
      c.record(StateError(_value), null);
      await c.idle;
      c.record(StateError(_value), null);
      await c.idle;
      c.attach(FakeSettingsStore(storage.data), FakeClock(DateTime.utc(2026)));
      final entries = await _stored(storage, c);
      expect(entries.single.count, 2);
    });

    test('unlesbarer Stand gilt als leer', () {
      expect(decodeErrorCounts('{kaputt'), isEmpty);
      expect(decodeErrorCounts('[{"type":1}]'), isEmpty);
    });

    test('AppDependencies speichert in der geöffneten Sitzung', () async {
      final storage = FakeStorage();
      final start = StorageStartController(
        keyStore: FakeKeyStore(),
        generateKey: () => Uint8List.fromList(List.filled(32, 7)),
        wire: () async =>
            StorageWiring(storage: storage, files: FakeDatabaseFiles()),
      );
      final deps = AppDependencies(storageStart: start);
      deps.errors.record(StateError(_value), null);
      await start.start();
      expect(start.state, isA<StorageReady>());
      final entries = await _stored(storage, deps.errors);
      expect(entries.single.type, 'StateError');
    });
  });

  group('Tage, Lesen, Zurücksetzen (FR-0223)', () {
    test(
      'erster und letzter lokaler Tag: erster bleibt, letzter rückt vor',
      () async {
        final storage = FakeStorage();
        final clock = FakeClock(
          DateTime.utc(2026, 11, 3, 23, 30),
          utcOffset: const Duration(hours: 2),
        );
        final c = ErrorCounter()
          ..attach(FakeSettingsStore(storage.data), clock);
        c.record(StateError(_value), null);
        var e = (await _stored(storage, c)).single;
        expect((e.firstDay, e.lastDay), ('2026-11-04', '2026-11-04'));
        clock.advanceTo(DateTime.utc(2026, 11, 9, 12));
        c.record(StateError(_value), null);
        e = (await _stored(storage, c)).single;
        expect(
          (e.count, e.firstDay, e.lastDay),
          (2, '2026-11-04', '2026-11-09'),
        );
      },
    );

    test(
      'Eintrag ohne Tage (ältere Fassung) lesbar; Zählen setzt die Tage',
      () async {
        final storage = FakeStorage();
        storage.data.settings[SettingKeys.errorCounts] =
            '[{"type":"StateError","place":"unknown","count":3}]';
        final old = decodeErrorCounts(
          storage.data.settings[SettingKeys.errorCounts],
        ).single;
        expect((old.count, old.firstDay, old.lastDay), (3, null, null));
        final c = ErrorCounter()
          ..attach(
            FakeSettingsStore(storage.data),
            FakeClock(DateTime.utc(2026, 11, 5, 10)),
          );
        c.record(StateError(_value), null);
        final e = (await _stored(storage, c)).single;
        expect(
          (e.count, e.firstDay, e.lastDay),
          (4, '2026-11-05', '2026-11-05'),
        );
      },
    );

    test('Tage gespeichert und wieder gelesen, ohne Nachricht', () async {
      final (c, storage) = _attached();
      c.record(_ValueError(), _appStack('package:running_app/x.dart'));
      await c.idle;
      final text = storage.data.settings[SettingKeys.errorCounts]!;
      expect(text, contains('"first":"2026-01-01"'));
      expect(text, isNot(contains('4711')));
    });

    test('read: gespeicherte und noch nicht gespeicherte Zähler', () async {
      final storage = FakeStorage();
      final c = ErrorCounter()..record(StateError(_value), null);
      expect((await c.read()).single.count, 1);
      c.attach(FakeSettingsStore(storage.data), FakeClock(DateTime.utc(2026)));
      c.record(StateError(_value), null);
      expect((await c.read()).single.count, 2);
    });

    test(
      'read: nicht lesbarer Stand wirft, danach zählt der Zähler weiter',
      () async {
        final c = ErrorCounter()
          ..attach(_FailingSettings(), FakeClock(DateTime.utc(2026)));
        await expectLater(c.read(), throwsA(isA<StateError>()));
        final storage = FakeStorage();
        c.attach(
          FakeSettingsStore(storage.data),
          FakeClock(DateTime.utc(2026)),
        );
        c.record(StateError(_value), null);
        expect((await _stored(storage, c)).single.count, 1);
      },
    );

    test('reset: leert gespeicherte und noch nicht gespeicherte', () async {
      final storage = FakeStorage();
      final c = ErrorCounter()
        ..attach(_FailingSettings(), FakeClock(DateTime.utc(2026)));
      c.record(StateError(_value), null);
      await c.idle;
      storage.data.settings[SettingKeys.errorCounts] = encodeErrorCounts([
        const ErrorCount(type: 'RangeError', place: 'p', count: 9),
      ]);
      c.attach(FakeSettingsStore(storage.data), FakeClock(DateTime.utc(2026)));
      await c.reset();
      expect(await c.read(), isEmpty);
      expect(await _stored(storage, c), isEmpty);
    });

    test('reset: Schreiben scheitert → wirft', () async {
      final c = ErrorCounter()
        ..attach(_FailingSettings(), FakeClock(DateTime.utc(2026)));
      await expectLater(c.reset(), throwsA(isA<StateError>()));
    });

    test('dropPending verwirft nur Ungespeichertes', () async {
      final c = ErrorCounter()..record(StateError(_value), null);
      c.dropPending();
      final storage = FakeStorage();
      c.attach(FakeSettingsStore(storage.data), FakeClock(DateTime.utc(2026)));
      expect(await _stored(storage, c), isEmpty);
    });
  });

  group('Health Connect zählt still abgefangene Fehler', () {
    HealthConnectController controller(
      ErrorCounter c, {
      bool failing = true,
      _Port? port,
    }) {
      final storage = FakeStorage();
      return healthConnectSession(
        port: port ?? _Port(),
        store: storage.data.health,
        settings: FakeSettingsStore(storage.data),
        consentStore: FakeConsentStore(storage.data),
        clock: failing
            ? _FailingClock()
            : FakeClock(DateTime.utc(2026, 11, 14, 12)),
        countError: c.record,
      );
    }

    test('Import im Hintergrund', () async {
      final (c, storage) = _attached();
      controller(c).runInBackground(HealthImportTrigger.appStart);
      await pumpEventQueue();
      final entries = await _stored(storage, c);
      expect(entries.single.type, 'StateError');
      expect(entries.single.count, 1);
    });

    test('Import und danach Laden', () async {
      final (c, storage) = _attached();
      final hc = controller(c);
      await hc.importThenLoad(HealthImportTrigger.appStart);
      // Das Laden läuft trotzdem (Verhalten wie bisher).
      expect(hc.loaded, isTrue);
      final entries = await _stored(storage, c);
      expect(entries.single.type, 'StateError');
      expect(entries.single.count, 1);
    });

    test('Fehler in onNewData', () async {
      final (c, storage) = _attached();
      final port = _Port();
      final hc = controller(c, failing: false, port: port);
      await hc.consents.grant(healthSourceKey(HealthDataKind.restingHeartRate));
      hc.onNewData = () => throw StateError(_value);
      port.records = [
        HealthRecord(
          kind: HealthDataKind.restingHeartRate,
          id: 'r1',
          origin: 'x',
          start: DateTime.utc(2026, 11, 14, 6),
          end: DateTime.utc(2026, 11, 14, 7),
          value: 50,
          unit: 'bpm',
        ),
      ];
      hc.runInBackground(HealthImportTrigger.appStart);
      await pumpEventQueue();
      final entries = await _stored(storage, c);
      expect(entries.single.type, 'StateError');
      expect(entries.single.count, 1);
    });
  });

  group('Health Connect zählt Fehler mit Ersatzverhalten', () {
    const kind = HealthDataKind.restingHeartRate;
    final key = healthSourceKey(kind);

    HealthConnectController hcOf(
      ErrorCounter c, {
      _Port? port,
      FakeStorage? storage,
      bool failingQuestions = false,
      bool failingSettings = false,
    }) {
      final data = (storage ?? FakeStorage()).data;
      return healthConnectSession(
        port: port ?? _Port(),
        store: data.health,
        settings: failingSettings
            ? _FailingSettings()
            : FakeSettingsStore(data),
        consentStore: failingQuestions
            ? _QuestionFailingConsents(data)
            : FakeConsentStore(data),
        clock: FakeClock(DateTime.utc(2026, 11, 14, 12)),
        countError: c.record,
      );
    }

    Future<void> expectCounted(
      FakeStorage storage,
      ErrorCounter c,
      int n,
    ) async {
      final entries = await _stored(storage, c);
      expect(entries.single.type, 'StateError');
      expect(entries.single.count, n);
      expect(
        storage.data.settings[SettingKeys.errorCounts],
        isNot(contains('4711')),
      );
    }

    test('Einschalten: Schließen der Löschfrage scheitert', () async {
      final (c, storage) = _attached();
      final hc = hcOf(c, failingQuestions: true);
      await hc.enable(kind);
      expect(hc.enabled, contains(kind), reason: 'Verhalten wie bisher');
      await expectCounted(storage, c, 1);
    });

    test('Ausschalten: Merken der Löschfrage scheitert', () async {
      final (c, storage) = _attached();
      final hc = hcOf(c, failingQuestions: true);
      await hc.consents.grant(key);
      await hc.disable(kind);
      expect(hc.questions, [kind], reason: 'trotzdem jetzt fragen');
      await expectCounted(storage, c, 1);
    });

    test('Laden: Zustand von Health Connect nicht lesbar', () async {
      final (c, storage) = _attached();
      final hc = hcOf(c, port: _Port()..failing = {'sdkStatus'});
      await hc.load();
      expect(hc.sdk, HealthSdkStatus.unavailable);
      await expectCounted(storage, c, 1);
    });

    test('Laden: Rechte nicht lesbar', () async {
      final (c, storage) = _attached();
      final hc = hcOf(c, port: _Port()..failing = {'grantedKinds'});
      await hc.load();
      expect(hc.permitted, isEmpty);
      await expectCounted(storage, c, 1);
    });

    test('Laden: Schließen einer erledigten Löschfrage scheitert', () async {
      final (c, storage) = _attached();
      final data = FakeStorage();
      data.data.consents[deleteQuestionKey(key)] = ConsentState.granted;
      final hc = hcOf(c, storage: data, failingQuestions: true);
      await hc.load();
      expect(hc.questions, [kind], reason: 'die Frage bleibt, wie sie war');
      await expectCounted(storage, c, 1);
    });

    test('Laden: letzter Import nicht lesbar', () async {
      final (c, storage) = _attached();
      final hc = hcOf(c, failingSettings: true);
      await hc.load();
      expect(hc.lastImport, isNull);
      await expectCounted(storage, c, 1);
    });

    test('Installieren lässt sich nicht öffnen', () async {
      final (c, storage) = _attached();
      final hc = hcOf(c, port: _Port()..failing = {'openInstall'});
      expect(await hc.openInstall(), isFalse);
      await expectCounted(storage, c, 1);
    });

    test('Berechtigungsdialog scheitert', () async {
      final (c, storage) = _attached();
      final hc = hcOf(c, port: _Port()..failing = {'requestPermissions'});
      hc.enabled = {kind};
      await hc.requestRights();
      expect(hc.permitted, isEmpty);
      await expectCounted(storage, c, 1);
    });
  });

  testWidgets('App: Health-Connect-Controller zählt in die Sitzung', (
    tester,
  ) async {
    final device = Device();
    device.healthConnect = _Port();
    await device.start(tester, const Locale('de'));
    await device.skipSetup(tester);
    final hc = HealthConnectScope.of(
      tester.element(find.byType(Navigator).first),
    );
    expect(hc, isNotNull);
    hc!.countError!(StateError(_value), StackTrace.empty);
    await tester.runAsync(() => device.errors.idle);
    final entries = decodeErrorCounts(
      device.storage.data.settings[SettingKeys.errorCounts],
    );
    expect(entries.single.type, 'StateError');
    await device.stop(tester);
  });
}

/// Einwilligungen, deren Löschfragen sich nicht speichern lassen.
class _QuestionFailingConsents extends FakeConsentStore {
  _QuestionFailingConsents(super.d);

  @override
  Future<void> set(
    String sourceKey,
    ConsentState state, {
    required DateTime at,
  }) async {
    if (sourceKey.endsWith(deleteQuestionKey(''))) {
      throw StateError(_value);
    }
    await super.set(sourceKey, state, at: at);
  }
}

class _FailingSettings implements SettingsStore {
  @override
  Future<String?> get(String key) async => throw StateError(_value);

  @override
  Future<Map<String, String>> all() async => throw StateError(_value);

  @override
  Future<void> set(String key, String value, {required DateTime at}) async =>
      throw StateError(_value);
}
