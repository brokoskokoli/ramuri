import 'dart:io';

import 'package:adapters/adapters.dart';
import 'package:core/core.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel(healthChannelName);
  final calls = <MethodCall>[];
  Object? Function(MethodCall)? answer;

  setUp(() {
    calls.clear();
    answer = null;
    messenger.setMockMethodCallHandler(channel, (c) async {
      calls.add(c);
      return answer!(c);
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('Kanalname und Methoden stehen auch im Kotlin-Teil', () {
    final kt = File(
      '../../android/app/src/main/kotlin/io/github/brokoskokoli/ramuri/HealthConnectChannel.kt',
    ).readAsStringSync();
    expect(kt, contains('"$healthChannelName"'));
    for (final m in [
      'sdkStatus',
      'grantedKinds',
      'requestPermissions',
      'readPage',
      'openInstall',
    ]) {
      expect(kt, contains('"$m"'));
    }
    final logic = File(
      '../../android/app/src/main/kotlin/io/github/brokoskokoli/ramuri/HealthConnectLogic.kt',
    ).readAsStringSync();
    for (final k in HealthDataKind.values) {
      expect(logic, contains('"${k.key}"'));
    }
  });

  test('sdkStatus und Fehler ohne Kanal', () async {
    answer = (_) => 'update_required';
    final port = MethodChannelHealthConnect();
    expect(await port.sdkStatus(), HealthSdkStatus.updateRequired);
    messenger.setMockMethodCallHandler(channel, null);
    expect(await port.sdkStatus(), HealthSdkStatus.unavailable);
  });

  test(
    'grantedKinds und requestPermissions übersetzen die Schlüssel',
    () async {
      answer = (_) => ['sleep', 'vo2_max', 'unbekannt'];
      final port = MethodChannelHealthConnect();
      expect(await port.grantedKinds(), {
        HealthDataKind.sleep,
        HealthDataKind.vo2Max,
      });
      await port.requestPermissions({HealthDataKind.hrvRmssd});
      expect(calls.last.method, 'requestPermissions');
      expect(calls.last.arguments, {
        'kinds': ['hrv_rmssd'],
      });
    },
  );

  test(
    'readPage schickt Fenster in UTC-Millisekunden und liest Datensätze',
    () async {
      answer = (_) => {
        'records': [
          {
            'id': 'a1',
            'origin': 'com.example.watch',
            'startMs': 1000,
            'endMs': 61000,
            'offsetSeconds': 3600,
            'stages': [
              [1000, 31000, 5],
              [31000, 61000, 4],
            ],
          },
        ],
        'nextToken': 'n2',
      };
      final page = await MethodChannelHealthConnect().readPage(
        kind: HealthDataKind.sleep,
        from: DateTime.utc(2026, 11, 1),
        to: DateTime.utc(2026, 11, 2),
        pageSize: 100,
      );
      expect(calls.single.arguments, {
        'kind': 'sleep',
        'fromMs': DateTime.utc(2026, 11, 1).millisecondsSinceEpoch,
        'toMs': DateTime.utc(2026, 11, 2).millisecondsSinceEpoch,
        'pageToken': null,
        'pageSize': 100,
      });
      final r = page.records.single;
      expect(page.nextToken, 'n2');
      expect(r.id, 'a1');
      expect(r.origin, 'com.example.watch');
      expect(r.start, DateTime.utc(1970, 1, 1, 0, 0, 1));
      expect(r.offsetSeconds, 3600);
      expect(r.stages.map((s) => s.stage), [5, 4]);
    },
  );

  test('Schlafphasen vom Kanal bis zur Schlafzeit: nur SLEEPING, LIGHT, DEEP, REM zählen (PAR-166)', () async {
    final t0 = DateTime.utc(2026, 11, 13, 22).millisecondsSinceEpoch;
    int m(int minutes) => t0 + minutes * 60000;
    // Phasen wie Health Connect sie liefert: 5 DEEP, 4 LIGHT, 6 REM, 2 SLEEPING, 1 AWAKE, 7 AWAKE_IN_BED, 3 OUT_OF_BED, 0 UNKNOWN.
    final stages = [
      [m(0), m(60), 5],
      [m(60), m(120), 4],
      [m(120), m(150), 6],
      [m(150), m(180), 2],
      [m(180), m(200), 1],
      [m(200), m(210), 7],
      [m(210), m(220), 3],
      [m(220), m(240), 0],
    ];
    answer = (_) => {
      'records': [
        {
          'id': 's1',
          'origin': 'com.example.watch',
          'startMs': m(0),
          'endMs': m(240),
          'stages': stages,
        },
      ],
    };
    final page = await MethodChannelHealthConnect().readPage(
      kind: HealthDataKind.sleep,
      from: DateTime.utc(2026, 11, 13),
      to: DateTime.utc(2026, 11, 14),
    );
    final session = sleepSessionOf(page.records.single);
    expect(session.stages.map((s) => s.kind), [
      SleepStageKind.deep,
      SleepStageKind.light,
      SleepStageKind.rem,
      SleepStageKind.sleeping,
      SleepStageKind.awake,
      SleepStageKind.awake,
      SleepStageKind.awake,
      SleepStageKind.other,
    ]);
    final summary = const HealthProcessing().sleepSummary(session);
    expect(summary.isEstimate, isFalse);
    expect(summary.sleepDuration, const Duration(minutes: 180));
    expect(summary.sessionDuration, const Duration(minutes: 240));
  });

  test(
    'openInstall: Kanalantwort, Fehler und fehlender Kanal ergeben false',
    () async {
      answer = (_) => true;
      final port = MethodChannelHealthConnect();
      expect(await port.openInstall(), isTrue);
      expect(calls.single.method, 'openInstall');
      answer = (_) => false;
      expect(await port.openInstall(), isFalse);
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => throw PlatformException(code: 'x'),
      );
      expect(await port.openInstall(), isFalse);
      messenger.setMockMethodCallHandler(channel, null);
      expect(await port.openInstall(), isFalse);
    },
  );

  test('Fehlercodes werden zu HealthReadError', () async {
    final port = MethodChannelHealthConnect();
    Future<HealthReadError?> err(String code) async {
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => throw PlatformException(code: code),
      );
      try {
        await port.readPage(
          kind: HealthDataKind.sleep,
          from: DateTime.utc(2026),
          to: DateTime.utc(2027),
        );
      } on HealthReadException catch (e) {
        return e.error;
      }
      return null;
    }

    expect(await err('permission_missing'), HealthReadError.permissionMissing);
    expect(await err('rate_limited'), HealthReadError.rateLimited);
    expect(await err('bad_arguments'), HealthReadError.badArguments);
    expect(await err('zzz'), HealthReadError.other);
  });

  test(
    'fehlerhafter Datensatz wird HealthReadException, kein TypeError',
    () async {
      final port = MethodChannelHealthConnect();
      final bad = <Object?>[
        {'origin': 'app.a', 'startMs': 1, 'endMs': 2}, // ohne id
        {'id': 'x', 'startMs': 1, 'endMs': 2}, // ohne origin
        {'id': 'x', 'origin': 'app.a', 'startMs': 'eins', 'endMs': 2},
        {'id': 7, 'origin': 'app.a', 'startMs': 1, 'endMs': 2},
        'kein Datensatz',
      ];
      for (final record in bad) {
        answer = (_) => {
          'records': [record],
          'nextToken': null,
        };
        await expectLater(
          port.readPage(
            kind: HealthDataKind.sleep,
            from: DateTime.utc(2026),
            to: DateTime.utc(2027),
          ),
          throwsA(
            isA<HealthReadException>().having(
              (e) => e.error,
              'error',
              HealthReadError.other,
            ),
          ),
        );
      }
    },
  );
}
