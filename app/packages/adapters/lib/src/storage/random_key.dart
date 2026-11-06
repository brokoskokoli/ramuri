import 'dart:math';
import 'dart:typed_data';

import 'package:core/core.dart';

/// Zufälliger Datenbankschlüssel aus der sicheren Quelle des Systems.
Uint8List generateStorageKey([Random? random]) {
  final r = random ?? Random.secure();
  return Uint8List.fromList(
    List.generate(storageKeyLength, (_) => r.nextInt(256)),
  );
}
