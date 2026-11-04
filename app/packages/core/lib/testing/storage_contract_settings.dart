import '../core.dart';
import 'contract_support.dart';

final settingsContractCases = <StorageContractCase>[
  const StorageContractCase(
    'Profil: leer, speichern, ersetzen, Grenzen',
    _profile,
  ),
  const StorageContractCase('Einstellungen', _settings),
  const StorageContractCase('Bekannte Geräte: ein bevorzugtes', _devices),
  const StorageContractCase(
    'Einwilligungen: fehlt gilt als nicht erteilt',
    _consents,
  ),
];

String _p(ProfileRecord p) =>
    '${p.birthYear}|${p.bodyWeightKg}|${p.bodyHeightMeters}|${p.restingHeartRateBpm}|${p.maxHeartRateBpm}|${p.weeklyRunMinutes}|${p.trainingDaysMask}|${p.usualTrainingMinutes}';

Future<void> _profile(StorageContractHarness h) async {
  final s = await h.open();
  expectEq(
    _p(await s.profile.read()),
    'null|null|null|null|null|null|null|null',
    'leeres Profil',
  );
  await s.profile.save(
    const ProfileRecord(
      birthYear: 1990,
      bodyWeightKg: 70.5,
      bodyHeightMeters: 1.8,
      restingHeartRateBpm: 50,
      maxHeartRateBpm: 190,
      weeklyRunMinutes: 120,
      trainingDaysMask: 21,
      usualTrainingMinutes: 45,
    ),
  );
  expectEq(
    _p(await s.profile.read()),
    '1990|70.5|1.8|50|190|120|21|45',
    'gespeichert',
  );
  await s.profile.save(const ProfileRecord(birthYear: 1991));
  expectEq(
    _p(await s.profile.read()),
    '1991|null|null|null|null|null|null|null',
    'ersetzt das ganze Profil',
  );
  for (final bad in const [
    ProfileRecord(bodyWeightKg: 0),
    ProfileRecord(bodyHeightMeters: -1),
    ProfileRecord(birthYear: 0),
    ProfileRecord(trainingDaysMask: 128),
  ]) {
    await expectFails(
      () => s.profile.save(bad),
      StorageFailure.rejected,
      'Wert außerhalb der Beschränkung',
    );
  }
  expectEq(
    _p(await s.profile.read()),
    '1991|null|null|null|null|null|null|null',
    'Fehler ändert nichts',
  );
  await s.close();
}

Future<void> _settings(StorageContractHarness h) async {
  final s = await h.open();
  expectTrue(await s.settings.get('unit') == null, 'fehlt ist null');
  await s.settings.set('unit', 'km', at: at(1));
  await s.settings.set('zones', 'a', at: at(1));
  await s.settings.set('unit', 'mi', at: at(2));
  expectEq(await s.settings.get('unit'), 'mi', 'überschrieben');
  expectEq(
    (await s.settings.all()).entries.map((e) => '${e.key}=${e.value}').toList()
      ..sort(),
    ['unit=mi', 'zones=a'],
    'alle',
  );
  await s.close();
}

Future<void> _devices(StorageContractHarness h) async {
  final s = await h.open();
  await s.devices.upsert('A', displayName: 'Gurt', at: at(1, 3));
  await s.devices.upsert('B', at: at(2));
  String d(KnownDevice k) =>
      '${k.deviceId}|${k.displayName}|${k.isPreferred}|${us(k.addedAt)}';
  expectEq((await s.devices.list()).map(d), [
    'A|Gurt|false|${us(at(1, 3))}',
    'B|null|false|${us(at(2))}',
  ], 'zwei Geräte');
  await s.devices.setPreferred('B');
  await s.devices.upsert('B', displayName: 'Uhr', at: at(9));
  await s.devices.upsert('A', at: at(9));
  expectEq((await s.devices.list()).map(d), [
    'A|Gurt|false|${us(at(1, 3))}',
    'B|Uhr|true|${us(at(2))}',
  ], 'Name geändert, Bevorzugung und Zeit bleiben');
  await s.devices.setPreferred('A');
  expectEq((await s.devices.list()).map((k) => k.isPreferred), [
    true,
    false,
  ], 'höchstens ein bevorzugtes');
  await expectFails(
    () => s.devices.setPreferred('Z'),
    StorageFailure.notFound,
    'unbekanntes Gerät',
  );
  expectEq((await s.devices.list()).map((k) => k.isPreferred), [
    true,
    false,
  ], 'Fehler ändert nichts');
  await s.devices.setPreferred(null);
  expectEq((await s.devices.list()).map((k) => k.isPreferred), [
    false,
    false,
  ], 'Festlegung aufgehoben');
  await s.close();
}

Future<void> _consents(StorageContractHarness h) async {
  final s = await h.open();
  expectTrue(await s.consents.get('strava') == null, 'fehlt ist null');
  await s.consents.set('strava', ConsentState.granted, at: at(1));
  await s.consents.set('health', ConsentState.granted, at: at(1));
  await s.consents.set('strava', ConsentState.revoked, at: at(2));
  expectEq(await s.consents.get('strava'), ConsentState.revoked, 'Widerruf');
  expectEq(
    await s.consents.get('health'),
    ConsentState.granted,
    'andere Quelle bleibt',
  );
  expectEq((await s.consents.all()).length, 2, 'alle');
  await s.close();
}
