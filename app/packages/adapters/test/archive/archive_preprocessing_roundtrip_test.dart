// SPDX-License-Identifier: GPL-3.0-only
// Archiv: Kettenversion der Vorverarbeitung an Laufwerten
// (`computed_values.preprocessing_version`, docs/contracts/archive.md,
// Abschnitt 12, seit Schema 19; ADR-0004). Ein Lauf mit VO2max, TRIMP und
// Zeit über 80 % HFmax in der heutigen Methode, über die Ports angelegt, mit
// echter Kryptografie exportiert und in eine leere App wiederhergestellt:
// (a) die Kette bleibt erhalten, (b) dasselbe Archiv als Schema 18 ohne die
// Spalte liest sich mit der Kette von damals und ergibt kein Angebot zur
// Neuberechnung. Alle Daten sind synthetisch.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:adapters/adapters.dart' hide ComputedValue;
import 'package:core/core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';

import '../storage/support.dart' show testKey;

const String _password = 'synthetisches Testpasswort';

final _t0 = DateTime.utc(2030, 1, 1, 7);
final _t1 = _t0.add(const Duration(minutes: 40));

const _fitness = FitnessParameters.v4();

List<ComputedValue> _values(String? chain) {
  const vo2 = AcsmReserveVo2maxEstimator();
  const trimp = EdwardsTrimp();
  const high = HighHeartRateTime();
  return [
    for (final (key, method, version, unit) in [
      (vo2maxRunValueKey, vo2.method, vo2.methodVersion, 'ml/kg/min'),
      (trimpRunValueKey, trimp.method, trimp.methodVersion, 'au'),
      (highHeartRateTimeValueKey, high.method, high.methodVersion, 's'),
    ])
      ComputedValue(
        key: key,
        value: 40.5,
        unit: unit,
        computedAt: _t1.add(const Duration(minutes: 1)),
        dataFrom: _t0,
        dataTo: _t1,
        measurementCount: 40,
        sources: const ['heart_rate'],
        method: method,
        methodVersion: version,
        parameterVersion: _fitness.parameterVersion,
        quality: ValueQuality.good,
        heartRateBasis: const HeartRateBasis(
          maxBpm: 190,
          restingBpm: 55,
          maxIsEstimated: false,
        ),
        preprocessingVersion: chain,
      ),
  ];
}

Future<Uint8List> _collect(Stream<List<int>> s) async {
  final b = BytesBuilder(copy: false);
  await for (final c in s) {
    b.add(c);
  }
  return b.takeBytes();
}

/// Schreibt das Archiv [path] als Schema 18 um: Manifest mit Schema 18, an
/// `computed_values` ohne `preprocessing_version` (Form vor Schema 19).
Future<String> _asSchema18(String path, String out) async {
  final cipher = createArchiveCipher();
  final plain = await _collect(
    cipher.decrypt(_password, File(path).openRead()),
  );
  String? section;
  var seen = 0;
  final lines = <String>[];
  for (final l in const LineSplitter().convert(
    utf8.decode(gzip.decode(plain)),
  )) {
    final m = jsonDecode(l) as Map<String, dynamic>;
    if (m['type'] == 'manifest') {
      expect(m['schema_version'], 19);
      m['schema_version'] = 18;
    } else if (m['type'] == 'section') {
      section = m['name'] as String;
    } else if (m['type'] == 'row' && section == 'computed_values') {
      expect((m['data'] as Map).remove('preprocessing_version'), isNotNull);
      seen++;
    }
    lines.add(jsonEncode(m));
  }
  expect(seen, 6);
  final bytes = await _collect(
    cipher.encrypt(
      _password,
      Stream.value(gzip.encode(utf8.encode('${lines.join('\n')}\n'))),
    ),
  );
  File(out).writeAsBytesSync(bytes);
  return out;
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory work;
  late Uint8List key;

  setUp(() {
    work = Directory.systemTemp.createTempSync('kettenarchiv_');
    key = testKey(12);
  });
  tearDown(() => work.deleteSync(recursive: true));

  Future<String> export(String? chain) async {
    final source = await EncryptedStorage('${work.path}/source.db').open(key);
    addTearDown(() async {
      try {
        await source.close();
      } catch (_) {}
    });
    final run = await source.runs.create(startedAt: _t0, mode: RunMode.gps);
    await source.runs.setState(
      run.id,
      RunState.finished,
      endedAt: _t1,
      endedUtcOffset: const Duration(hours: 1),
    );
    await source.values.createOriginals(ValueOwner.run(run.id), _values(chain));
    final exportDir = Directory('${work.path}/exports')..createSync();
    final f = await ArchiveExporter(
      source: DriftArchiveSource((source as EncryptedStorageSession).database),
      handoff: FakeFileHandoff()..directory = exportDir.path,
      clock: FakeClock(DateTime.utc(2030, 1, 2, 12)),
      cipherFactory: createArchiveCipherInWorker,
    ).export(password: _password);
    await source.close();
    return f.path!;
  }

  Future<StorageSession> restore(String path) async {
    final activePath = '${work.path}/app/running_app.db';
    Directory('${work.path}/app').createSync();
    var target = await EncryptedStorage(activePath).open(key);
    addTearDown(() async {
      try {
        await target.close();
      } catch (_) {}
    });
    final files = FileDatabaseFiles(activePath);
    target = await ArchiveRestoreService(
      session: target,
      sink: DriftArchiveSink(
        storage: EncryptedStorage(files.importPath),
        key: () => Uint8List.fromList(key),
        files: files,
      ),
      files: files,
      cipherFactory: createArchiveCipherInWorker,
      clock: FakeClock(DateTime.utc(2030, 1, 2, 12)),
      reopen: () async => target = await EncryptedStorage(activePath).open(key),
      serialize: <T>(Future<T> Function() a) => a(),
    ).restore(path: path, password: _password);
    return target;
  }

  Future<RecalculationOffer?> check(StorageSession session) async {
    final clock = FakeClock(DateTime.utc(2030, 1, 2, 12));
    final service = RecalculationService(
      session: session,
      clock: clock,
      calculation: ValueCalculationService(session: session, clock: clock),
    );
    addTearDown(service.dispose);
    return service.checkVersions();
  }

  Future<List<String>> chains(StorageSession s) async {
    final all = await s.values.read(const ValueOwner.run(1));
    return [
      for (final p in all) ...[
        'original:${p.original.preprocessingVersion}',
        'current:${p.current.preprocessingVersion}',
      ],
    ];
  }

  test('Export und Reimport behalten die Kettenversion an original und '
      'current; eine abweichende Kette bleibt ein Angebot', () async {
    final target = await restore(await export('hr0.test'));
    expect(await chains(target), [
      for (var i = 0; i < 3; i++) ...['original:hr0.test', 'current:hr0.test'],
    ]);
    expect((await check(target))?.causes, {
      RecalculationCause.algorithmVersion,
    });
  });

  test('Export und Reimport mit der heutigen Kette: kein Angebot', () async {
    final target = await restore(await export(preprocessingChainVersion()));
    expect(await chains(target), [
      for (var i = 0; i < 3; i++) ...[
        'original:${preprocessingChainVersion()}',
        'current:${preprocessingChainVersion()}',
      ],
    ]);
    expect(await check(target), isNull);
  });

  test('Archiv mit Schema 18 ohne Spalte: Laufwerte tragen die Kette von '
      'damals, kein Angebot', () async {
    final path = await _asSchema18(
      await export(legacyPreprocessingChainVersion),
      '${work.path}/s18.runarchv',
    );
    final target = await restore(path);
    expect(await chains(target), [
      for (var i = 0; i < 3; i++) ...[
        'original:$legacyPreprocessingChainVersion',
        'current:$legacyPreprocessingChainVersion',
      ],
    ]);
    expect(await check(target), isNull);
  });
}
