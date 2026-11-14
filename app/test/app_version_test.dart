import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/settings/app_version.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('ramuri/permissions');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('Erfolg: liefert die Version der Plattform', () async {
    String? asked;
    messenger.setMockMethodCallHandler(channel, (call) async {
      asked = call.method;
      return '1.2.3 (45)';
    });
    expect(await readAppVersion(), '1.2.3 (45)');
    expect(asked, 'appVersion');
  });

  test('Fehler der Plattform: null statt Ausnahme', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (call) async => throw PlatformException(code: 'x'),
    );
    expect(await readAppVersion(), isNull);
  });

  test('keine Plattform (kein Handler): null', () async {
    expect(await readAppVersion(), isNull);
  });

  test('Plattform meldet null: null', () async {
    messenger.setMockMethodCallHandler(channel, (call) async => null);
    expect(await readAppVersion(), isNull);
  });
}
