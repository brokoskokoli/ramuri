import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:core/testing/storage_contract.dart';
import 'package:test/test.dart';

void main() {
  final key = Uint8List.fromList(List.generate(32, (i) => i));
  for (final c in storageContractCases()) {
    test('Fake: ${c.name}', () async {
      final storage = FakeStorage();
      await c.run(StorageContractHarness(open: () => storage.open(key)));
    });
  }

  test('Fake: nicht durchgelaufener Checkpoint meldet deletedNotErased, Löschen gilt', () async {
    final storage = FakeStorage()..checkpointIncomplete = true;
    final s = await storage.open(key);
    final id = (await s.runs.create(startedAt: DateTime.utc(2030))).id;
    await expectLater(
      s.deleteRun(id),
      throwsA(
        isA<StorageException>().having(
          (e) => e.failure,
          'failure',
          StorageFailure.deletedNotErased,
        ),
      ),
    );
    expect(await s.runs.get(id), isNull);
    await expectLater(s.deleteAll(), throwsA(isA<StorageException>()));
  });
}
