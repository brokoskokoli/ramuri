import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:core/testing/storage_contract.dart';
import 'package:test/test.dart';

void main() {
  final key = Uint8List.fromList(List.generate(32, (i) => i));
  for (final c in storageContractCases()) {
    test('Fake: ${c.name}', () async {
      final storage = FakeStorage();
      await c.run(
        StorageContractHarness(
          open: () => storage.open(key),
          deleteRun: (id) async => storage.deleteRun(id),
        ),
      );
    });
  }
}
