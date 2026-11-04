import '../core.dart';
import 'contract_support.dart';
import 'contract_samples.dart';
import 'storage_contract_data.dart';
import 'storage_contract_derived.dart';
import 'storage_contract_settings.dart';

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
  const StorageContractCase('Löschen eines Laufs kaskadiert', _cascade),
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
  await s.values.createOriginals(const ValueOwner.day('2030-01-01'), [
    sampleValue('atl', 2),
  ]);
  await s.settings.set('k', 'v', at: at(0));
  await h.deleteRun(a);

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
