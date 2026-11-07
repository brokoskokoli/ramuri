import 'dart:io';

import 'package:adapters/adapters.dart';
import 'package:core/core.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel(fileHandoffChannelName);
  final file = ExportFile(
    fileName: 'run-20300101-090000.gpx',
    mimeType: 'application/gpx+xml',
    bytes: Uint8List.fromList([60, 63, 120]),
  );

  late List<MethodCall> calls;
  Object? Function(MethodCall) answer = (_) => 'completed';

  setUp(() {
    calls = [];
    answer = (_) => 'completed';
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return answer(call);
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('share und save senden Name, MIME-Typ und Bytes', () async {
    final h = MethodChannelFileHandoff();
    expect(await h.share(file), FileHandoffResult.completed);
    expect(await h.save(file), FileHandoffResult.completed);
    expect(calls.map((c) => c.method), ['share', 'save']);
    for (final c in calls) {
      final args = c.arguments as Map;
      expect(args['fileName'], file.fileName);
      expect(args['mimeType'], file.mimeType);
      expect(args['bytes'], file.bytes);
    }
  });

  test('Antworten werden auf das Ergebnis abgebildet', () async {
    final h = MethodChannelFileHandoff();
    answer = (_) => 'cancelled';
    expect(await h.share(file), FileHandoffResult.cancelled);
    expect(await h.save(file), FileHandoffResult.cancelled);
    for (final other in [null, 'failed', 'irgendwas']) {
      answer = (_) => other;
      expect(await h.share(file), FileHandoffResult.failed, reason: '$other');
    }
  });

  test('Plattformfehler und fehlender Kanal sind failed, kein Wurf', () async {
    answer = (_) => throw PlatformException(code: 'busy');
    expect(
      await MethodChannelFileHandoff().save(file),
      FileHandoffResult.failed,
    );
    messenger.setMockMethodCallHandler(channel, null);
    expect(
      await MethodChannelFileHandoff().share(file),
      FileHandoffResult.failed,
    );
  });

  test('eigener Kanal per Konstruktor', () async {
    const other = MethodChannel('test/file_handoff');
    messenger.setMockMethodCallHandler(other, (_) async => 'cancelled');
    expect(
      await MethodChannelFileHandoff(other).share(file),
      FileHandoffResult.cancelled,
    );
    expect(calls, isEmpty);
    messenger.setMockMethodCallHandler(other, null);
  });

  test('Kanalname, Methoden und Antworten stehen gleich in Kotlin', () {
    const dir =
        '../../android/app/src/main/kotlin/io/github/brokoskokoli/running_app';
    final kt = File('$dir/FileHandoffChannel.kt').readAsStringSync();
    final flow = File('$dir/FileHandoffFlow.kt').readAsStringSync();
    expect(kt, contains('"$fileHandoffChannelName"'));
    for (final m in ['share', 'save', 'fileName', 'mimeType', 'bytes']) {
      expect(kt, contains('"$m"'), reason: m);
    }
    for (final r in ['completed', 'cancelled']) {
      expect(flow, contains('"$r"'), reason: r);
    }
    // An der Activity, weil ein Systemdialog gestartet wird.
    expect(
      File('$dir/MainActivity.kt').readAsStringSync(),
      contains('FileHandoffChannel('),
    );
  });
}
