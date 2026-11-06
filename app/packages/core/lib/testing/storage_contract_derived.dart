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
  const StorageContractCase(
    'Werte: ungültige Zahlen und fehlender Grund werden abgelehnt',
    _valueInvalidNumbers,
  ),
  const StorageContractCase(
    'Werte: Herzfrequenzbasis als Schnappschuss',
    _valueBasis,
  ),
  const StorageContractCase('Werte: Tageswerte', _dayValues),
  const StorageContractCase(
    'Werte: Tausch über mehrere Besitzer ganz oder gar nicht',
    _swapAll,
  ),
  const StorageContractCase(
    'Werte: Anlegen und Tauschen über mehrere Besitzer in einer Transaktion',
    _writeAll,
  ),
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
  await _overviews(s, r, other);
  await s.close();
}

/// Gebündelte Kurzfassung aller Läufe (Historie): nur `moving` und
/// `positionGap`, keine Samples, mit der Zusammenfassung des Laufs.
Future<void> _overviews(StorageSession s, int r, int other) async {
  await s.preprocessing.replace(
    r,
    StoredPreprocessing(
      summary: samplePreprocessing(4).summary,
      samples: samplePreprocessing().samples,
      spans: [
        PreprocessedSpan(
          kind: PreprocessedSpanKind.settling,
          start: at(1),
          end: at(5),
        ),
        PreprocessedSpan(
          kind: PreprocessedSpanKind.positionGap,
          start: at(30),
          end: at(40),
        ),
        PreprocessedSpan(
          kind: PreprocessedSpanKind.moving,
          start: at(5),
          end: at(60),
        ),
      ],
    ),
  );
  final third = (await s.runs.create(startedAt: at(0))).id;
  final all = await s.preprocessing.readOverviews();
  expectEq(all.length, 2, 'nur Läufe mit Vorverarbeitung (nicht $third)');
  final o = all[r]!;
  expectEq(o.summary.methodVersion, 4, 'Zusammenfassung des Laufs');
  expectEq(o.summary.distanceMeters, 1000.5, 'Strecke');
  expectEq(o.samples.length, 0, 'keine Samples');
  expectEq(
    o.spans.map((x) => '${x.kind.name}/${us(x.start)}/${us(x.end)}').toList(),
    [
      'moving/${us(at(5))}/${us(at(60))}',
      'positionGap/${us(at(30))}/${us(at(40))}',
    ],
    'nur moving und positionGap, sortiert',
  );
  expectEq(all[other]!.summary.methodVersion, 7, 'anderer Lauf');
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
    sampleValue(
      'vo2max',
      48.5,
      quality: ValueQuality.sufficient,
      sections: sampleValueSections(),
    ),
    sampleValue(
      'efficiency',
      null,
      quality: ValueQuality.undeterminable,
      reason: UnavailableReason.noValidSection,
    ),
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
  expectEq(
    read[0].original.unavailableReason,
    UnavailableReason.noValidSection,
    'fehlender Wert mit Grund',
  );
  expectEq(
    read[0].current.unavailableReason,
    UnavailableReason.noValidSection,
    'current beginnt mit demselben Grund',
  );
  expectEq(read[1].original.unavailableReason, null, 'Wert ohne Grund');

  await s.values.swapCurrent(o, [
    sampleValue(
      'vo2max',
      50.25,
      method: 2,
      quality: ValueQuality.good,
      sections: sampleValueSections(7).sublist(0, 2),
    ),
  ]);
  read = await s.values.read(o);
  expectEq(
    describeValue(read[1].original),
    describeValue(
      sampleValue(
        'vo2max',
        48.5,
        quality: ValueQuality.sufficient,
        sections: sampleValueSections(),
      ),
    ),
    'original bleibt',
  );
  expectEq(
    describeValue(read[1].current),
    describeValue(
      sampleValue(
        'vo2max',
        50.25,
        method: 2,
        quality: ValueQuality.good,
        sections: sampleValueSections(7).sublist(0, 2),
      ),
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

  // Gebündelte Abfrage: das current der verlangten Schlüssel aller Läufe, ohne
  // Tageswerte und ohne Abschnitte.
  final other = (await s.runs.create(startedAt: at(1))).id;
  await s.values.createOriginals(ValueOwner.run(other), [
    sampleValue('vo2max', 40),
  ]);
  await s.values.createOriginals(const ValueOwner.day('2030-01-02'), [
    sampleValue('vo2max', 1),
  ]);
  final bulk = await s.values.readRunValues({'vo2max', 'nichts'});
  expectEq(bulk.keys.toSet(), {r, other}, 'alle Läufe mit dem Schlüssel');
  expectEq(bulk[r]!.keys.toList(), ['vo2max'], 'nur verlangte Schlüssel');
  expectEq(bulk[r]!['vo2max']!.value, 50.25, 'das current, nicht das original');
  expectEq(bulk[other]!['vo2max']!.value, 40.0, 'anderer Lauf');
  expectEq(bulk[r]!['vo2max']!.sections.length, 0, 'ohne Abschnitte');
  expectEq(
    bulk[r]!['vo2max']!.quality,
    ValueQuality.good,
    'Qualität des current',
  );
  expectEq(
    (await s.values.readRunValues({})).length,
    0,
    'keine Schlüssel, keine Antwort',
  );
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

/// Alle Fälle, die `requireStorableValues` ablehnt (Adapter und Fake gleich).
List<(String, ComputedValue)> _invalidValues() {
  ValueSection section({
    double weight = 1,
    double lateFactor = 1,
    double? gps,
    double? demand,
    double? estimate,
  }) => ValueSection(
    start: at(1),
    end: at(2),
    weight: weight,
    lateFactor: lateFactor,
    status: SectionStatus.eligible,
    gpsMedianAccuracyMeters: gps,
    oxygenDemand: demand,
    estimate: estimate,
  );
  const nan = double.nan;
  const inf = double.infinity;
  ComputedValue withSection(ValueSection s) =>
      sampleValue('v', 1, sections: [s]);
  return [
    ('Wert NaN', sampleValue('v', nan)),
    ('Wert unendlich', sampleValue('v', inf)),
    ('Wert fehlt ohne Grund', sampleValue('v', null, withoutReason: true)),
    (
      'Grund trotz Wert',
      sampleValue('v', 1, reason: UnavailableReason.noValidSection),
    ),
    ('Gewicht NaN', withSection(section(weight: nan))),
    ('Gewicht unendlich', withSection(section(weight: inf))),
    ('Spätfaktor negativ', withSection(section(lateFactor: -0.1))),
    ('Spätfaktor NaN', withSection(section(lateFactor: nan))),
    ('GPS-Genauigkeit negativ', withSection(section(gps: -1))),
    ('GPS-Genauigkeit NaN', withSection(section(gps: nan))),
    ('Schätzwert NaN', withSection(section(estimate: nan))),
    ('Schätzwert unendlich', withSection(section(estimate: -inf))),
    ('Sauerstoffbedarf NaN', withSection(section(demand: nan))),
  ];
}

Future<void> _valueInvalidNumbers(StorageContractHarness h) async {
  final s = await h.open();
  final r = (await s.runs.create(startedAt: at(0))).id;
  final o = ValueOwner.run(r);
  await s.values.createOriginals(o, [
    sampleValue('v', 3, sections: sampleValueSections()),
  ]);
  final before = (await s.values.read(o)).map(describePair).join(';');
  for (final (name, bad) in _invalidValues()) {
    await expectFails(
      () => s.values.swapCurrent(o, [bad]),
      StorageFailure.rejected,
      'Tausch: $name',
    );
    await expectFails(
      () => s.values.createOriginals(o, [
        ComputedValue(
          key: 'neu',
          value: bad.value,
          unavailableReason: bad.unavailableReason,
          unit: bad.unit,
          computedAt: bad.computedAt,
          measurementCount: bad.measurementCount,
          sources: bad.sources,
          method: bad.method,
          methodVersion: bad.methodVersion,
          parameterVersion: bad.parameterVersion,
          quality: bad.quality,
          sections: bad.sections,
        ),
      ]),
      StorageFailure.rejected,
      'Anlegen: $name',
    );
  }
  expectEq(
    (await s.values.read(o)).map(describePair).join(';'),
    before,
    'nichts geschrieben',
  );
  // Gleiche Fehlerreihenfolge: erst Existenz, dann Gültigkeit.
  await expectFails(
    () => s.values.swapCurrent(o, [sampleValue('missing', double.nan)]),
    StorageFailure.notFound,
    'unbekannter Schlüssel vor ungültiger Zahl',
  );
  await s.close();
}

Future<void> _valueBasis(StorageContractHarness h) async {
  final s = await h.open();
  final r = (await s.runs.create(startedAt: at(0))).id;
  final o = ValueOwner.run(r);
  const first = HeartRateBasis(maxBpm: 190, restingBpm: 55);
  const second = HeartRateBasis(maxBpm: 185, maxIsEstimated: true);
  await s.values.createOriginals(o, [
    sampleValue('a', 1, basis: first),
    sampleValue('b', 2, basis: second),
    // Snapshot "Basis kannte nichts" ist etwas anderes als kein Snapshot.
    sampleValue('c', 3, basis: const HeartRateBasis()),
    sampleValue('d', 4),
  ]);
  String of(ComputedValue v) => describeValue(v).split('|sections').first;
  var read = {for (final p in await s.values.read(o)) p.original.key: p};
  expectEq(read['a']!.original.heartRateBasis?.maxBpm, 190, 'HFmax gelesen');
  expectEq(read['a']!.original.heartRateBasis?.restingBpm, 55, 'HFRuhe');
  expectEq(
    read['a']!.original.heartRateBasis?.maxIsEstimated,
    false,
    'Näherung aus',
  );
  expectEq(read['b']!.original.heartRateBasis?.restingBpm, null, 'HFRuhe null');
  expectEq(
    read['b']!.original.heartRateBasis?.maxIsEstimated,
    true,
    'Näherung an',
  );
  expectTrue(
    read['c']!.original.heartRateBasis != null &&
        read['c']!.original.heartRateBasis!.maxBpm == null,
    'leerer Schnappschuss bleibt ein Schnappschuss',
  );
  expectEq(read['d']!.original.heartRateBasis, null, 'ohne Schnappschuss');
  expectEq(
    of(read['a']!.current),
    of(read['a']!.original),
    'current beginnt mit derselben Basis',
  );
  // Tausch: current bekommt die Basis des neuen Werts, original behält seine.
  await s.values.swapCurrent(o, [
    sampleValue('a', 5, basis: second),
    sampleValue('b', 6),
  ]);
  read = {for (final p in await s.values.read(o)) p.original.key: p};
  expectEq(read['a']!.current.heartRateBasis?.maxBpm, 185, 'current a neu');
  expectEq(read['a']!.current.heartRateBasis?.restingBpm, null, 'HFRuhe neu');
  expectEq(
    read['a']!.current.heartRateBasis?.maxIsEstimated,
    true,
    'Näherung neu',
  );
  expectEq(
    read['a']!.original.heartRateBasis?.maxBpm,
    190,
    'original a bleibt',
  );
  expectEq(read['b']!.current.heartRateBasis, null, 'current b ohne');
  expectEq(
    read['b']!.original.heartRateBasis?.maxBpm,
    185,
    'original b bleibt',
  );
  // Ungültige Basis wird abgelehnt, nichts geschrieben.
  final before = (await s.values.read(o)).map(describePair).join(';');
  for (final (name, bad) in [
    ('HFmax 0', const HeartRateBasis(maxBpm: 0)),
    ('HFmax negativ', const HeartRateBasis(maxBpm: -1)),
    ('HFRuhe 0', const HeartRateBasis(restingBpm: 0)),
  ]) {
    await expectFails(
      () => s.values.swapCurrent(o, [sampleValue('a', 1, basis: bad)]),
      StorageFailure.rejected,
      'Tausch: $name',
    );
    await expectFails(
      () => s.values.createOriginals(o, [sampleValue('neu', 1, basis: bad)]),
      StorageFailure.rejected,
      'Anlegen: $name',
    );
  }
  expectEq(
    (await s.values.read(o)).map(describePair).join(';'),
    before,
    'nichts geschrieben',
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

Future<void> _swapAll(StorageContractHarness h) async {
  final s = await h.open();
  final r1 = ValueOwner.run((await s.runs.create(startedAt: at(0))).id);
  final r2 = ValueOwner.run((await s.runs.create(startedAt: at(0))).id);
  const d = ValueOwner.day('2030-01-01');
  for (final o in [r1, r2, d]) {
    await s.values.createOriginals(o, [
      sampleValue('a', 1, sections: sampleValueSections()),
    ]);
  }
  // Ein Besitzer ohne Original macht den ganzen Tausch rückgängig.
  final before = [
    for (final o in [r1, r2, d]) (await s.values.read(o)).map(describePair),
  ].join(';');
  await expectFails(
    () => s.values.swapCurrentAll({
      r1: [sampleValue('a', 5, sections: sampleValueSections(3))],
      r2: [sampleValue('a', 6)],
      d: [sampleValue('fehlt', 7)],
    }),
    StorageFailure.notFound,
    'Original fehlt bei einem Besitzer',
  );
  expectEq(
    [
      for (final o in [r1, r2, d]) (await s.values.read(o)).map(describePair),
    ].join(';'),
    before,
    'nichts geändert',
  );
  await s.values.swapCurrentAll({
    r1: [sampleValue('a', 5, sections: sampleValueSections(3))],
    r2: [sampleValue('a', 6)],
    d: [sampleValue('a', 7)],
  });
  for (final (o, v) in [(r1, 5.0), (r2, 6.0), (d, 7.0)]) {
    final p = (await s.values.read(o)).single;
    expectEq(p.current.value, v, 'current getauscht');
    expectEq(p.original.value, 1.0, 'original bleibt');
  }
  expectEq(
    (await s.values.read(r1)).single.original.sections.length,
    sampleValueSections().length,
    'Original-Abschnitte bleiben',
  );
  await s.close();
}

Future<void> _writeAll(StorageContractHarness h) async {
  final s = await h.open();
  final r1 = ValueOwner.run((await s.runs.create(startedAt: at(0))).id);
  final r2 = ValueOwner.run((await s.runs.create(startedAt: at(0))).id);
  const d = ValueOwner.day('2030-01-01');
  await s.values.createOriginals(d, [sampleValue('a', 1)]);
  Future<String> state() async => [
    for (final o in [r1, r2, d]) (await s.values.read(o)).map(describePair),
  ].join(';');
  final before = await state();
  // Der Tausch scheitert (Original fehlt): auch das Anlegen gilt nicht.
  await expectFails(
    () => s.values.writeAll(
      create: {
        r1: [sampleValue('a', 5)],
        r2: [sampleValue('a', 6)],
      },
      swap: {
        d: [sampleValue('fehlt', 7)],
      },
    ),
    StorageFailure.notFound,
    'Tausch scheitert',
  );
  expectEq(await state(), before, 'nichts angelegt');
  // Das Anlegen scheitert (Wert existiert): auch der Tausch gilt nicht.
  await s.values.createOriginals(r2, [sampleValue('a', 6)]);
  final mid = await state();
  await expectFails(
    () => s.values.writeAll(
      create: {
        r1: [sampleValue('a', 5)],
        r2: [sampleValue('a', 9)],
      },
      swap: {
        d: [sampleValue('a', 7)],
      },
    ),
    StorageFailure.rejected,
    'Anlegen scheitert',
  );
  expectEq(await state(), mid, 'nichts getauscht, nichts angelegt');
  await s.values.writeAll(
    create: {
      r1: [sampleValue('a', 5, sections: sampleValueSections())],
    },
    swap: {
      d: [sampleValue('a', 7)],
    },
  );
  final p1 = (await s.values.read(r1)).single;
  expectEq(p1.original.value, 5.0, 'angelegt: original');
  expectEq(p1.current.value, 5.0, 'angelegt: current');
  final p = (await s.values.read(d)).single;
  expectEq(p.original.value, 1.0, 'original bleibt');
  expectEq(p.current.value, 7.0, 'current getauscht');
  await s.close();
}
