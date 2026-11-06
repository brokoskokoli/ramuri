import '../core.dart';
import 'contract_samples.dart';
import 'contract_support.dart';

final derivedContractCases = <StorageContractCase>[
  const StorageContractCase(
    'Vorverarbeitung: ersetzen je Lauf',
    _preprocessing,
  ),
  const StorageContractCase(
    'Abschnitte: ersetzen, GPS-Lücken mit Ende und open',
    _sections,
  ),
];

final valueContractCases = <StorageContractCase>[
  const StorageContractCase(
    'Werte: original anlegen, current tauschen',
    _values,
  ),
  const StorageContractCase('Werte: Fehler ändern nichts', _valueFailures),
  const StorageContractCase(
    'Werte: ungültiger Abschnitt ändert nichts',
    _valueSectionFailures,
  ),
  const StorageContractCase('Werte: Tageswerte', _dayValues),
];

String _describe(StoredPreprocessing p) {
  final s = p.summary;
  return '${s.method}|${s.methodVersion}|${s.parameterVersion}|${us(s.computedAt)}|${s.totalTime?.inMicroseconds}|${s.movingTime?.inMicroseconds}|${s.distanceMeters}|${s.bridgedDistanceMeters}|${s.averageBpm}|${s.maxBpm}|${s.medianBpm}'
      ' samples=${p.samples.map((x) => '${x.channel.name}/${x.rawId}/${us(x.time)}/${x.state.name}/${x.discardReason?.name}')}'
      ' spans=${p.spans.map((x) => '${x.kind.name}/${us(x.start)}/${us(x.end)}')}';
}

Future<void> _preprocessing(StorageContractHarness h) async {
  final s = await h.open();
  final r = (await s.runs.create(startedAt: at(0))).id;
  final other = (await s.runs.create(startedAt: at(0))).id;
  expectTrue(await s.preprocessing.read(r) == null, 'leer ist null');
  await s.preprocessing.replace(r, samplePreprocessing());
  await s.preprocessing.replace(other, samplePreprocessing(7));
  final first = await s.preprocessing.read(r);
  expectEq(
    _describe(first!),
    'preprocessing|1|2|${us(at(60, 5))}|61500000|60000000|1000.5|null|null|170|null'
        ' samples=(position/1/${us(at(1))}/present/null, position/2/${us(at(2))}/discarded/hardJump)'
        ' spans=(moving/${us(at(5))}/null/null, settling/${us(at(1))}/${us(at(5))})',
    'gelesen: sortiert, fehlende Werte null',
  );
  await s.preprocessing.replace(
    r,
    StoredPreprocessing(summary: samplePreprocessing(3).summary),
  );
  final replaced = await s.preprocessing.read(r);
  expectEq(replaced!.summary.methodVersion, 3, 'ersetzt');
  expectEq(
    '${replaced.samples.length}/${replaced.spans.length}',
    '0/0',
    'alte Samples und Spans weg',
  );
  expectEq(
    (await s.preprocessing.read(other))!.summary.methodVersion,
    7,
    'anderer Lauf unberührt',
  );
  await expectFails(
    () => s.preprocessing.replace(999, samplePreprocessing()),
    StorageFailure.notFound,
    'unbekannter Lauf',
  );
  await s.close();
}

String _section(RatedSection x) {
  final q = x.quality;
  return '${us(x.assessedAt)}|${q.method}|${q.methodVersion}|${q.parameterVersion}|${us(q.from)}|${us(q.to)}'
      '|hr=${MeasurementState.values.map((m) => q.heartRateCounts[m])}|pos=${MeasurementState.values.map((m) => q.positionCounts[m])}'
      '|${q.missingHeartRateShare}|${q.longestHeartRateGap.inMicroseconds}|${q.meetsHeartRateGapRule}|${q.settlingOverlap.inMicroseconds}|${q.settlingShare}|gaps=${q.gpsGaps.map((g) => '${us(g.start)}-${us(g.end)}-${g.open}')}';
}

Future<void> _sections(StorageContractHarness h) async {
  final s = await h.open();
  final r = (await s.runs.create(startedAt: at(0))).id;
  await s.sections.replace(r, [sampleSection(60), sampleSection(0)]);
  final read = await s.sections.read(r);
  expectEq(read.length, 2, 'zwei Abschnitte');
  expectEq(
    _section(read.first),
    _section(sampleSection(0)),
    'Inhalt, nach Beginn sortiert, GPS-Lücken mit Ende',
  );
  await s.sections.replace(r, [sampleSection(120)]);
  expectEq((await s.sections.read(r)).map((x) => us(x.quality.from)), [
    us(at(120)),
  ], 'ersetzt');
  await s.sections.replace(r, const []);
  expectEq((await s.sections.read(r)).length, 0, 'leer ersetzt');
  await expectFails(
    () => s.sections.replace(999, [sampleSection(0)]),
    StorageFailure.notFound,
    'unbekannter Lauf',
  );
  await s.close();
}

Future<void> _values(StorageContractHarness h) async {
  final s = await h.open();
  final r = (await s.runs.create(startedAt: at(0))).id;
  final o = ValueOwner.run(r);
  await s.values.createOriginals(o, [
    sampleValue('vo2max', 48.5, quality: ValueQuality.sufficient, sections: sampleValueSections()),
    sampleValue('efficiency', null, quality: ValueQuality.undeterminable),
  ]);
  var read = await s.values.read(o);
  expectEq(read.map((p) => p.original.key), [
    'efficiency',
    'vo2max',
  ], 'nach Schlüssel sortiert');
  expectEq(
    describePair(read[1]),
    'O(${describeValue(sampleValue('vo2max', 48.5, quality: ValueQuality.sufficient, sections: sampleValueSections()))}) C(${describeValue(sampleValue('vo2max', 48.5, quality: ValueQuality.sufficient, sections: sampleValueSections()))})',
    'current beginnt als Kopie',
  );
  expectEq(read[0].original.value, null, 'undeterminable ohne Wert');

  await s.values.swapCurrent(o, [
    sampleValue('vo2max', 50.25, method: 2, quality: ValueQuality.good, sections: sampleValueSections(7).sublist(0, 2)),
  ]);
  read = await s.values.read(o);
  expectEq(
    describeValue(read[1].original),
    describeValue(
      sampleValue('vo2max', 48.5, quality: ValueQuality.sufficient, sections: sampleValueSections()),
    ),
    'original bleibt',
  );
  expectEq(
    describeValue(read[1].current),
    describeValue(
      sampleValue('vo2max', 50.25, method: 2, quality: ValueQuality.good, sections: sampleValueSections(7).sublist(0, 2)),
    ),
    'current getauscht',
  );
  expectEq(
    describePair(read[0]),
    describePair((await s.values.read(o))[0]),
    'anderer Wert unberührt',
  );
  expectEq(read[0].current.value, null, 'efficiency current unverändert null');
  expectEq(read[1].original.sections.length, 3, 'original behält 3 Abschnitte');
  expectEq(read[1].current.sections.length, 2, 'current hat neue Abschnitte');
  expectEq(read[0].original.sections.length, 0, 'Wert ohne Abschnitte');
  await s.close();
}

Future<void> _valueFailures(StorageContractHarness h) async {
  final s = await h.open();
  final r = (await s.runs.create(startedAt: at(0))).id;
  final o = ValueOwner.run(r);
  await s.values.createOriginals(o, [sampleValue('a', 1), sampleValue('b', 2)]);
  await expectFails(
    () =>
        s.values.createOriginals(o, [sampleValue('c', 3), sampleValue('a', 9)]),
    StorageFailure.rejected,
    'Original existiert',
  );
  expectEq((await s.values.read(o)).length, 2, 'kein Teilstand beim Anlegen');
  await expectFails(
    () =>
        s.values.createOriginals(o, [sampleValue('x', 1), sampleValue('x', 2)]),
    StorageFailure.rejected,
    'doppelter Schlüssel',
  );
  await expectFails(
    () => s.values.createOriginals(const ValueOwner.run(999), [
      sampleValue('a', 1),
    ]),
    StorageFailure.notFound,
    'unbekannter Lauf',
  );

  final before = (await s.values.read(o)).map(describePair).join(';');
  await expectFails(
    () => s.values.swapCurrent(o, [
      sampleValue('a', 100),
      sampleValue('missing', 5),
    ]),
    StorageFailure.notFound,
    'Original fehlt',
  );
  expectEq(
    (await s.values.read(o)).map(describePair).join(';'),
    before,
    'Tausch ganz oder gar nicht',
  );
  await expectFails(
    () => s.values.swapCurrent(o, [sampleValue('a', 1), sampleValue('a', 2)]),
    StorageFailure.rejected,
    'doppelter Schlüssel beim Tausch',
  );
  await expectFails(
    () =>
        s.values.swapCurrent(const ValueOwner.run(999), [sampleValue('a', 1)]),
    StorageFailure.notFound,
    'Tausch an unbekanntem Lauf',
  );
  expectEq(
    (await s.values.read(o)).map(describePair).join(';'),
    before,
    'unverändert',
  );
  await s.close();
}

Future<void> _valueSectionFailures(StorageContractHarness h) async {
  final s = await h.open();
  final r = (await s.runs.create(startedAt: at(0))).id;
  final o = ValueOwner.run(r);
  ValueSection bad() => ValueSection(
    start: at(50),
    end: at(10),
    weight: 1,
    lateFactor: 1,
    status: SectionStatus.eligible,
  );
  // Der erste Wert ist gültig und wäre vor dem Fehler schon geschrieben.
  await expectFails(
    () => s.values.createOriginals(o, [
      sampleValue('a', 1, sections: sampleValueSections()),
      sampleValue('b', 2, sections: [bad()]),
    ]),
    StorageFailure.rejected,
    'ungültiger Abschnitt',
  );
  expectEq((await s.values.read(o)).length, 0, 'nichts geschrieben');
  await s.values.createOriginals(o, [
    sampleValue('a', 1, sections: sampleValueSections()),
    sampleValue('b', 2, sections: sampleValueSections(1)),
  ]);
  final before = (await s.values.read(o)).map(describePair).join(';');
  await expectFails(
    () => s.values.swapCurrent(o, [
      sampleValue('a', 5, sections: sampleValueSections(3)),
      sampleValue('b', 6, sections: [bad()]),
    ]),
    StorageFailure.rejected,
    'ungültiger Abschnitt beim Tausch',
  );
  expectEq(
    (await s.values.read(o)).map(describePair).join(';'),
    before,
    'Tausch ganz oder gar nicht, auch die Abschnitte',
  );
  await s.close();
}

Future<void> _dayValues(StorageContractHarness h) async {
  final s = await h.open();
  final r = (await s.runs.create(startedAt: at(0))).id;
  const d1 = ValueOwner.day('2030-01-01');
  await s.values.createOriginals(d1, [sampleValue('atl', 10)]);
  await s.values.createOriginals(const ValueOwner.day('2030-01-02'), [
    sampleValue('atl', 20),
  ]);
  await s.values.createOriginals(ValueOwner.run(r), [sampleValue('atl', 30)]);
  await s.values.swapCurrent(d1, [sampleValue('atl', 11)]);
  expectEq(
    (await s.values.read(d1))
        .map((p) => '${p.original.value}/${p.current.value}'),
    ['10.0/11.0'],
    'Tageswert',
  );
  expectEq(
    (await s.values.read(const ValueOwner.day('2030-01-02')))
        .single
        .current
        .value,
    20.0,
    'anderer Tag getrennt',
  );
  expectEq(
    (await s.values.read(ValueOwner.run(r))).single.current.value,
    30.0,
    'Laufwert getrennt von Tageswert',
  );
  await expectFails(
    () => s.values.createOriginals(d1, [sampleValue('atl', 1)]),
    StorageFailure.rejected,
    'Tagesoriginal existiert',
  );
  await s.close();
}
