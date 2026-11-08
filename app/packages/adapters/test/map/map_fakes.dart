import 'dart:async';
import 'dart:typed_data';

import 'package:adapters/adapters.dart';

export 'package:adapters/map_testing.dart';

class MemoryStore implements MapTileStore {
  final Map<String, Uint8List> data = {};
  int writes = 0;
  int reads = 0;
  Completer<void>? holdRead;
  @override
  Future<Uint8List?> read(String key) async {
    reads++;
    if (holdRead != null) await holdRead!.future;
    return data[key];
  }

  @override
  Future<void> write(String key, Uint8List bytes) async {
    writes++;
    data[key] = bytes;
  }
}
