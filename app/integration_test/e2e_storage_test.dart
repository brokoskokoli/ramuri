// E2E-Hilfstest: legt Daten mit den echten Adaptern an oder liest sie. Er
// gehört nicht zu `flutter test` (läuft nur als `flutter test integration_test
// --dart-define=...` auf einem Gerät) und enthält keine Testeinstellung für das
// Produkt. Marken sind synthetisch; Schlüssel werden nie ausgegeben.
//
// PHASE=write: Marke schreiben, Sitzung offen lassen (kein Schließen), warten,
//   bis der Prozess beendet wird (WAL-Datei mit Frames, noch kein Checkpoint).
//   Gibt danach "E2E_NEED_KILL" aus; tool/ci_e2e.sh beendet dann den Prozess
//   (am force-stop).
// PHASE=fill: Marke und viele Füllzeilen schreiben, dann die Sitzung schließen.
//   Das Schließen der letzten Verbindung führt in SQLite einen Checkpoint aus
//   und entfernt die WAL-Datei; der Inhalt steht danach in der Hauptdatei. Zur
//   Kontrolle wird neu geöffnet, die Marke gelesen und wieder geschlossen.
//   Ausgegeben werden nur Dateigrößen. Danach wartet der Test, damit die
//   Dateien gezogen werden können.
// PHASE=read: über die echte Schicht lesen; erwartet, dass die Marke da ist
//   (nach PHASE=write und Prozessende), und gibt nur true/false aus.
// Ohne PHASE (Verzeichnislauf) wird der Test übersprungen.
//
// MARKER=<synthetische Marke> ist für alle Phasen anzugeben.
import 'dart:io';

import 'package:adapters/adapters.dart';
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const phase = String.fromEnvironment('PHASE');
const marker = String.fromEnvironment('MARKER');
const settingKey = 'e2e.marker';

/// Anzahl und Größe der Füllzeilen (PHASE=fill): rund 300 KB Nutzdaten, also
/// sicher mehr als 100 KB in der Hauptdatei.
const fillRows = 300;
const fillRowChars = 1024;

int _size(String path) =>
    File(path).existsSync() ? File(path).lengthSync() : -1;

void _printSizes(String label, String path) {
  // ignore: avoid_print
  print(
    'E2E_SIZES $label main=${_size(path)} wal=${_size('$path-wal')} '
    'shm=${_size('$path-shm')}',
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'storage $phase',
    (tester) async {
      await tester.runAsync(() async {
        final path = await databasePath();
        final storage = EncryptedStorage(path);
        final service = StorageKeyService(
          keyStore: SecureKeyStore(),
          databaseFilesExist: storage.filesExist,
          generateKey: generateStorageKey,
        );
        final start = await service.decide();
        // ignore: avoid_print
        print('E2E_DECIDE=${start.runtimeType}');
        final key = switch (start) {
          OpenExistingStorage(:final key) => key,
          CreateNewStorage(:final key) => key,
          _ => null,
        };
        expect(key, isNotNull, reason: 'Speicher nicht öffnbar');
        if (key == null) return;
        final session = await storage.open(key);
        if (phase == 'write') {
          await session.settings.set(settingKey, marker, at: DateTime.now());
          final back = await session.settings.get(settingKey);
          // ignore: avoid_print
          print('E2E_WRITTEN match=${back == marker}');
          expect(back, marker);
          // ignore: avoid_print
          print('E2E_NEED_KILL');
          await Future<void>.delayed(const Duration(minutes: 10));
        } else if (phase == 'fill') {
          final at = DateTime.now();
          await session.settings.set(settingKey, marker, at: at);
          final padding = 'x' * (fillRowChars - marker.length);
          for (var i = 0; i < fillRows; i++) {
            await session.settings.set(
              'e2e.fill.$i',
              '$marker$padding',
              at: at,
            );
          }
          _printSizes('before_close', path);
          // Letzte Verbindung schließen: Checkpoint, WAL-Datei entfällt.
          await session.close();
          _printSizes('after_close', path);
          final again = await storage.open(key);
          final back = await again.settings.get(settingKey);
          // ignore: avoid_print
          print('E2E_FILLED match=${back == marker}');
          await again.close();
          _printSizes('after_reopen_close', path);
          await Future<void>.delayed(const Duration(minutes: 10));
        } else {
          final v = await session.settings.get(settingKey);
          // ignore: avoid_print
          print('E2E_READ present=${v != null} match=${v == marker}');
          await session.close();
          expect(v, isNotNull, reason: 'Marke aus PHASE=write fehlt');
          expect(v, marker);
        }
      });
    },
    skip: phase.isEmpty,
    timeout: const Timeout(Duration(minutes: 12)),
  );
}
