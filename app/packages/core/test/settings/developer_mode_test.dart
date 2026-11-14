import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:test/test.dart';

void main() {
  late StorageSession session;
  late SettingsDeveloperModeStore mode;
  setUp(() async {
    session = await FakeStorage().open(Uint8List(32));
    mode = SettingsDeveloperModeStore(
      session.settings,
      FakeClock(DateTime.utc(2026, 11, 14, 7)),
    );
  });

  test('fehlt der Eintrag, ist er aus; setzen und zurücksetzen', () async {
    expect(await mode.read(), isFalse);
    await mode.set(true);
    expect(await mode.read(), isTrue);
    await mode.set(false);
    expect(await mode.read(), isFalse);
  });

  test('Alles löschen setzt den Modus zurück', () async {
    await mode.set(true);
    await session.deleteAll();
    expect(await mode.read(), isFalse);
  });

  test('kein Archivinhalt', () {
    expect(archiveExcludedSettingKeys, contains(SettingKeys.developerMode));
  });
}
