import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:test/test.dart';

const _std = PpgCameraRef('0');
const _second = PpgCameraRef('2', '4');
const _broken = PpgCameraRef('3');

const _cameras = [
  PpgCameraInfo(ref: _std, focalLengthMm: 4.2, isDefault: true),
  PpgCameraInfo(ref: _second, focalLengthMm: 2.1),
  PpgCameraInfo(ref: _broken, unusable: PpgCameraUnusable.noFlash),
];

void main() {
  group('PpgCameraRef', () {
    test('gleich, wenn beide Felder gleich sind', () {
      expect(const PpgCameraRef('2', '4'), const PpgCameraRef('2', '4'));
      expect(const PpgCameraRef('2'), isNot(const PpgCameraRef('2', '4')));
      expect(const PpgCameraRef('2', '4'), isNot(const PpgCameraRef('2', '5')));
      expect(
        const PpgCameraRef('2', '4').hashCode,
        const PpgCameraRef('2', '4').hashCode,
      );
    });

    test('gespeicherte Form hin und zurück; Unpassendes ist keine Wahl', () {
      expect(_std.key, '0');
      expect(_second.key, '2/4');
      expect(PpgCameraRef.parse('0'), _std);
      expect(PpgCameraRef.parse('2/4'), _second);
      for (final bad in [null, '', '/', '2/', '/4', '1/2/3']) {
        expect(PpgCameraRef.parse(bad), isNull, reason: '$bad');
      }
    });

    test('toString nennt keine Kennung', () {
      expect(_second.toString(), isNot(contains('2')));
      expect(_cameras[1].toString(), isNot(contains('2')));
    });
  });

  group('resolvePpgCamera', () {
    PpgCameraRef? resolve({
      bool dev = true,
      PpgCameraRef? manual,
      PpgCameraRef? auto,
      List<PpgCameraInfo> cameras = _cameras,
    }) => resolvePpgCamera(
      cameras: cameras,
      developerMode: dev,
      manual: manual,
      auto: auto,
    );

    test('Entwicklermodus an, gültige Wahl von Hand: diese', () {
      expect(resolve(manual: _second), _second);
      expect(resolve(manual: _second, auto: _std), _second);
    });

    test('Entwicklermodus aus: Wahl von Hand gilt nicht', () {
      expect(resolve(dev: false, manual: _second), isNull);
      expect(resolve(dev: false, manual: _second, auto: _std), _std);
    });

    test('Wahl von Hand nicht mehr vorhanden: Suche, sonst Standard', () {
      const gone = PpgCameraRef('9');
      expect(resolve(manual: gone), isNull);
      expect(resolve(manual: gone, auto: _second), _second);
    });

    test('Wahl von Hand nicht nutzbar: Suche, sonst Standard', () {
      expect(resolve(manual: _broken), isNull);
      expect(resolve(manual: _broken, auto: _second), _second);
    });

    test('Ergebnis der Suche vorhanden und nutzbar: dieses', () {
      expect(resolve(auto: _second), _second);
      expect(resolve(dev: false, auto: _second), _second);
    });

    test('Ergebnis der Suche fehlt oder nicht nutzbar: Standard', () {
      expect(resolve(auto: const PpgCameraRef('9')), isNull);
      expect(resolve(auto: _broken), isNull);
    });

    test('nichts gespeichert: Standard', () {
      expect(resolve(), isNull);
      expect(resolve(dev: false), isNull);
      expect(resolve(manual: _second, cameras: const []), isNull);
    });
  });

  group('SettingsPpgCameraChoiceStore', () {
    late StorageSession session;
    late SettingsPpgCameraChoiceStore store;
    setUp(() async {
      session = await FakeStorage().open(Uint8List(32));
      store = SettingsPpgCameraChoiceStore(
        session.settings,
        FakeClock(DateTime.utc(2026, 11, 18, 7)),
      );
    });

    test('lesen, setzen, löschen (beide Einträge getrennt)', () async {
      expect(await store.readManual(), isNull);
      expect(await store.readAuto(), isNull);
      await store.setManual(_second);
      await store.setAuto(_std);
      expect(await store.readManual(), _second);
      expect(await store.readAuto(), _std);
      expect(await session.settings.get(SettingKeys.ppgCameraManual), '2/4');
      expect(await session.settings.get(SettingKeys.ppgCameraAuto), '0');
      await store.setManual(null);
      expect(await store.readManual(), isNull);
      expect(await store.readAuto(), _std);
      await store.setAuto(null);
      expect(await store.readAuto(), isNull);
    });

    test('Alles löschen setzt beide zurück', () async {
      await store.setManual(_second);
      await store.setAuto(_std);
      await session.deleteAll();
      expect(await store.readManual(), isNull);
      expect(await store.readAuto(), isNull);
    });

    test('kein Archivinhalt', () {
      expect(archiveExcludedSettingKeys, contains(SettingKeys.ppgCameraManual));
      expect(archiveExcludedSettingKeys, contains(SettingKeys.ppgCameraAuto));
    });
  });

  group('choosePpgCamera', () {
    late StorageSession session;
    late SettingsPpgCameraChoiceStore store;
    late FakePpgCamera camera;
    var dev = false;
    setUp(() async {
      session = await FakeStorage().open(Uint8List(32));
      store = SettingsPpgCameraChoiceStore(
        session.settings,
        FakeClock(DateTime.utc(2026, 11, 18, 7)),
      );
      camera = FakePpgCamera()..cameraList = _cameras;
      dev = false;
    });

    Future<PpgCameraRef?> choose() => choosePpgCamera(
      camera: camera,
      developerMode: () async => dev,
      choice: store,
    );

    test('nichts gespeichert: Standard, ohne die Kameras abzufragen', () async {
      dev = true;
      expect(await choose(), isNull);
      expect(camera.camerasCount, 0);
    });

    test('ohne Entwicklermodus zählt die Wahl von Hand nicht', () async {
      await store.setManual(_second);
      expect(await choose(), isNull);
      expect(camera.camerasCount, 0);
      dev = true;
      expect(await choose(), _second);
    });

    test('Ergebnis der Suche gilt auch ohne Entwicklermodus', () async {
      await store.setAuto(_second);
      expect(await choose(), _second);
    });

    test('Fehler beim Lesen: Standard', () async {
      dev = true;
      await store.setManual(_second);
      expect(
        await choosePpgCamera(
          camera: camera,
          developerMode: () async => throw StateError('x'),
          choice: store,
        ),
        isNull,
      );
    });
  });
}
