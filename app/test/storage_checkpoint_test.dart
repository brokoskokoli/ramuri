import 'dart:io';
import 'dart:typed_data';

import 'package:adapters/adapters.dart';
import 'package:flutter_test/flutter_test.dart';

/// Belegt die Annahme des E2E-Modus PHASE=fill (integration_test/): Schließen
/// der letzten Verbindung macht den Checkpoint, die WAL-Datei entfällt, die
/// Hauptdatei ist groß und die Marke bleibt lesbar.
void main() {
  test(
    'Schließen checkpointet: Hauptdatei > 100 KB, WAL weg, Marke lesbar',
    () async {
      const marker = 'SYNTHETISCHE-FUELL-MARKE';
      final dir = Directory.systemTemp.createTempSync('wp02_ckpt_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/app.db';
      final key = Uint8List.fromList(List.generate(32, (i) => i + 1));
      final storage = EncryptedStorage(path);
      final s = await storage.open(key);
      final at = DateTime.utc(2030);
      await s.settings.set('e2e.marker', marker, at: at);
      final padding = 'x' * (1024 - marker.length);
      for (var i = 0; i < 300; i++) {
        await s.settings.set('e2e.fill.$i', '$marker$padding', at: at);
      }
      expect(File('$path-wal').lengthSync(), greaterThan(0));
      await s.close();
      expect(File('$path-wal').existsSync(), isFalse);
      expect(File(path).lengthSync(), greaterThan(100 * 1024));
      final again = await storage.open(key);
      expect(await again.settings.get('e2e.marker'), marker);
      await again.close();
      expect(File('$path-wal').existsSync(), isFalse);
      expect(File(path).lengthSync(), greaterThan(100 * 1024));
    },
  );
}
