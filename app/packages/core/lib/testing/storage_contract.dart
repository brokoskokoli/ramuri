import '../core.dart';
import 'contract_support.dart';
import 'contract_samples.dart';
import 'storage_contract_data.dart';
import 'storage_contract_derived.dart';
import 'storage_contract_goals.dart';
import 'storage_contract_morning.dart';
import 'storage_contract_plan.dart';
import 'storage_contract_prediction.dart';
import 'storage_contract_settings.dart';
import 'storage_contract_subjective.dart';
import 'storage_contract_warning.dart';

export 'contract_support.dart'
    show StorageContractCase, StorageContractHarness, ContractViolation;

/// Der Vertrag des Speichers. Läuft gegen den [FakeStorage] in `core` und
/// gegen die echte verschlüsselte Datenbank in `adapters`, damit Folgepakete
/// dem Fake trauen können. Fehlerarten sind Teil des Vertrags.
List<StorageContractCase> storageContractCases() => [
  ...runContractCases,
  ...rawContractCases,
  ...derivedContractCases,
  ...valueContractCases,
  ...settingsContractCases,
  ...subjectiveContractCases,
  ...predictionContractCases,
  ...goalContractCases,
  ...planContractCases,
  ...warningContractCases,
  ...morningContractCases,
  const StorageContractCase('Löschen eines Laufs kaskadiert', _cascade),
  const StorageContractCase('Tageswerte beim Löschen eines Laufs', _dayValues),
  const StorageContractCase('Löschen: Fehlerarten', _deleteFailures),
  const StorageContractCase('Alles löschen leert den Speicher', _deleteAll),
  const StorageContractCase('Inhalt überlebt Schließen und Öffnen', _reopen),
];

Future<void> _cascade(StorageContractHarness h) async {
  final s = await h.open();
  final a = (await s.runs.create(startedAt: at(0))).id;
  final b = (await s.runs.create(startedAt: at(1))).id;
  for (final r in [a, b]) {
    await s.markers.addLap(
      r,
      StoredLap(index: 1, markedAt: at(5), lapTime: const Duration(seconds: 5)),
    );
    await s.markers.openGap(r, RunGapKind.interruption, at(2));
    await s.rawData.append(r, sampleBatch());
    await s.preprocessing.replace(r, samplePreprocessing());
    await s.sections.replace(r, [sampleSection(0)]);
    await s.values.createOriginals(ValueOwner.run(r), [sampleValue('v', 1)]);
  }
  // Datenzeitraum vor beiden Läufen: überlappt nicht, bleibt.
  await s.values.createOriginals(const ValueOwner.day('2030-01-01'), [
    _dayValue('atl', at(-1000), at(-500)),
  ]);
  await s.settings.set('k', 'v', at: at(0));
  await s.deleteRun(a);

  expectTrue(await s.runs.get(a) == null, 'Lauf weg');
  expectEq((await s.runs.list()).map((r) => r.id), [b], 'anderer Lauf bleibt');
  expectEq((await s.markers.laps(a)).length, 0, 'Runden weg');
  expectEq((await s.markers.gaps(a)).length, 0, 'Lücken weg');
  final raw = await s.rawData.read(a);
  expectEq(
    raw.positions.length +
        raw.heartRates.length +
        raw.altitudes.length +
        raw.steps.length +
        raw.unavailable.length,
    0,
    'Rohdaten weg',
  );
  expectTrue(await s.preprocessing.read(a) == null, 'Vorverarbeitung weg');
  expectEq((await s.sections.read(a)).length, 0, 'Abschnitte weg');
  expectEq((await s.values.read(ValueOwner.run(a))).length, 0, 'Werte weg');
  final bulk = await s.values.readRunValues({'v'});
  expectTrue(!bulk.containsKey(a), 'Werte weg (gebündelte Abfrage)');
  expectTrue(bulk.containsKey(b), 'Werte des anderen bleiben (gebündelt)');

  expectEq(
    (await s.markers.laps(b)).length,
    1,
    'Runden des anderen Laufs bleiben',
  );
  expectEq(
    (await s.markers.gaps(b)).length,
    1,
    'Lücken des anderen Laufs bleiben',
  );
  expectEq(
    (await s.rawData.read(b)).positions.length,
    2,
    'Rohdaten des anderen Laufs bleiben',
  );
  expectTrue(
    await s.preprocessing.read(b) != null,
    'Vorverarbeitung des anderen bleibt',
  );
  expectEq(
    (await s.sections.read(b)).length,
    1,
    'Abschnitte des anderen bleiben',
  );
  expectEq(
    (await s.values.read(ValueOwner.run(b))).length,
    1,
    'Werte des anderen bleiben',
  );
  expectEq(
    (await s.values.read(const ValueOwner.day('2030-01-01'))).length,
    1,
    'Tageswert bleibt',
  );
  expectEq(await s.settings.get('k'), 'v', 'Einstellung bleibt');
  await expectFails(
    () => s.markers.addLap(
      a,
      StoredLap(index: 1, markedAt: at(5), lapTime: Duration.zero),
    ),
    StorageFailure.notFound,
    'Runde an gelöschtem Lauf',
  );
  await s.close();
}

Future<void> _reopen(StorageContractHarness h) async {
  var s = await h.open();
  final id = (await s.runs.create(startedAt: at(0, 7))).id;
  await s.rawData.append(id, sampleBatch());
  await s.settings.set('unit', 'km', at: at(1));
  await s.consents.set('src', ConsentState.granted, at: at(1));
  await s.close();
  s = await h.open();
  expectEq(
    us((await s.runs.get(id))!.startedAt),
    us(at(0, 7)),
    'Lauf nach Neuöffnen',
  );
  expectEq(
    (await s.rawData.read(id)).positions.length,
    2,
    'Rohdaten nach Neuöffnen',
  );
  expectEq(await s.settings.get('unit'), 'km', 'Einstellung nach Neuöffnen');
  expectEq(
    await s.consents.get('src'),
    ConsentState.granted,
    'Einwilligung nach Neuöffnen',
  );
  await s.close();
}

ComputedValue _dayValue(String key, DateTime? from, DateTime? to) =>
    ComputedValue(
      key: key,
      value: 1,
      unit: 'au',
      computedAt: at(300),
      dataFrom: from,
      dataTo: to,
      measurementCount: 1,
      sources: const ['gps'],
      method: 'm',
      methodVersion: 1,
      parameterVersion: 1,
      quality: ValueQuality.good,
    );

/// Annahme (Supervisor): Mit dem Lauf gehen Tageswerte weg, deren Datenzeitraum
/// den Lauf überlappt (Ränder zählen mit) oder unbekannt ist; WP09 berechnet
/// sie neu. Nicht überlappende bleiben.
Future<void> _dayValues(StorageContractHarness h) async {
  final s = await h.open();
  final r = (await s.runs.create(startedAt: at(100))).id;
  await s.runs.setState(r, RunState.finished, endedAt: at(200));
  const days = {
    'inside': ('2030-01-01', 150, 160),
    'overlapStart': ('2030-01-02', 50, 100),
    'overlapEnd': ('2030-01-03', 200, 300),
    'covers': ('2030-01-04', 0, 1000),
    'before': ('2030-01-05', 0, 99),
    'after': ('2030-01-06', 201, 300),
  };
  for (final e in days.entries) {
    await s.values.createOriginals(ValueOwner.day(e.value.$1), [
      _dayValue(e.key, at(e.value.$2), at(e.value.$3)),
    ]);
  }
  await s.values.createOriginals(const ValueOwner.day('2030-01-07'), [
    _dayValue('unknown', null, null),
  ]);
  // Original und current mit verschiedenen Zeiträumen: ein Treffer genügt.
  await s.values.createOriginals(const ValueOwner.day('2030-01-08'), [
    _dayValue('swapped', at(0), at(99)),
  ]);
  await s.values.swapCurrent(const ValueOwner.day('2030-01-08'), [
    _dayValue('swapped', at(150), at(160)),
  ]);
  await s.deleteRun(r);
  for (final e in days.entries) {
    final left = (await s.values.read(ValueOwner.day(e.value.$1))).length;
    final keep = e.key == 'before' || e.key == 'after';
    expectEq(left, keep ? 1 : 0, 'Tageswert ${e.key}');
  }
  expectEq(
    (await s.values.read(const ValueOwner.day('2030-01-07'))).length,
    0,
    'Tageswert ohne Zeitraum',
  );
  expectEq(
    (await s.values.read(const ValueOwner.day('2030-01-08'))).length,
    0,
    'Tageswert mit überlappendem current',
  );
  await s.close();
}

Future<void> _deleteFailures(StorageContractHarness h) async {
  final s = await h.open();
  await expectFails(() => s.deleteRun(99), StorageFailure.notFound, 'Lauf 99');
  final r = (await s.runs.create(startedAt: at(0))).id;
  await s.deleteRun(r);
  await expectFails(() => s.deleteRun(r), StorageFailure.notFound, 'doppelt');
  await s.close();
}

Future<void> _deleteAll(StorageContractHarness h) async {
  var s = await h.open();
  final r = (await s.runs.create(startedAt: at(0))).id;
  await s.rawData.append(r, sampleBatch());
  await s.preprocessing.replace(r, samplePreprocessing());
  await s.sections.replace(r, [sampleSection(0)]);
  await s.values.createOriginals(ValueOwner.run(r), [sampleValue('v', 1)]);
  await s.values.createOriginals(const ValueOwner.day('2030-01-01'), [
    _dayValue('atl', at(-1000), at(-500)),
  ]);
  await s.profile.save(const ProfileRecord(birthYear: 1990));
  await s.settings.set('k', 'v', at: at(0));
  await s.devices.upsert('dev', displayName: 'Gurt', at: at(0));
  await s.devices.setPreferred('dev');
  await s.consents.set('src', ConsentState.granted, at: at(0));
  await s.deleteAll();
  expectEq((await s.runs.list()).length, 0, 'Läufe');
  expectEq(
    (await s.values.read(const ValueOwner.day('2030-01-01'))).length,
    0,
    'Tageswerte',
  );
  expectTrue((await s.profile.read()).birthYear == null, 'Profil');
  expectEq((await s.settings.all()).length, 0, 'Einstellungen');
  expectEq((await s.devices.list()).length, 0, 'Geräte');
  expectEq((await s.consents.all()).length, 0, 'Einwilligungen');
  // Nach dem Neuöffnen weiter leer, und der Speicher bleibt benutzbar.
  await s.close();
  s = await h.open();
  expectEq((await s.runs.list()).length, 0, 'Läufe nach Neuöffnen');
  final r2 = (await s.runs.create(startedAt: at(5))).id;
  expectEq(r2, 1, 'Zähler zurückgesetzt');
  await s.settings.set('k', 'w', at: at(5));
  expectEq(await s.settings.get('k'), 'w', 'Speicher benutzbar');
  await s.close();
}
