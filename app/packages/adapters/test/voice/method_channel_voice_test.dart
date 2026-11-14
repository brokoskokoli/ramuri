import 'package:adapters/adapters.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel(voiceChannelName);
  late List<MethodCall> calls;

  setUp(() {
    calls = [];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('Kanalname ist ramuri/voice', () {
    expect(voiceChannelName, 'ramuri/voice');
  });

  test('speak sendet Text und Sprache, stop ruft stop', () async {
    final v = MethodChannelVoice();
    await v.speak('Hallo', languageTag: 'de');
    await v.stop();
    expect(calls.map((c) => c.method), ['speak', 'stop']);
    expect(calls.first.arguments, {'text': 'Hallo', 'language': 'de'});
  });

  test('available fragt mit der Sprache; nur true heißt verfügbar', () async {
    for (final (answer, expected) in [
      (true, true),
      (false, false),
      (null, false),
    ]) {
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return answer;
      });
      calls.clear();
      expect(await MethodChannelVoice().available(languageTag: 'de'), expected);
      expect(calls.single.method, 'available');
      expect(calls.single.arguments, {'language': 'de'});
    }
  });

  test('Kanalfehler kommt als Ausnahme ohne Text zurück', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'voice_failed');
    });
    await expectLater(
      MethodChannelVoice().speak('Geheim 150'),
      throwsA(
        isA<PlatformException>().having(
          (e) => '${e.message}${e.details}',
          'ohne Text',
          isNot(contains('Geheim')),
        ),
      ),
    );
  });
}
