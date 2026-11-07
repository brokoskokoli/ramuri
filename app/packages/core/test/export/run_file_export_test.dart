import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:test/test.dart';

import 'export_support.dart';

void main() {
  late StorageSession s;
  setUp(() async => s = await xSession());

  group('RunFileExportService', () {
    test('baut je Format die Datei wie der Kodierer (Goldens)', () async {
      final id = await seedMainRun(s);
      final service = RunFileExportService(session: s);
      for (final (format, mime) in [
        (ExportFormat.gpx, 'application/gpx+xml'),
        (ExportFormat.tcx, 'application/vnd.garmin.tcx+xml'),
        (ExportFormat.fit, 'application/vnd.ant.fit'),
      ]) {
        final file = (await service.build(id, format))!;
        // Hauptlauf: Start 08:00 UTC, Ortszeit UTC+1 (Abbildungsregel 8).
        expect(file.fileName, 'run-20300101-090000.${format.extension}');
        expect(file.mimeType, mime);
        expect(
          file.bytes,
          File('test/export/goldens/main.${format.extension}')
              .readAsBytesSync(),
          reason: format.name,
        );
      }
    });

    test('GPX und TCX sind UTF-8', () async {
      final id = await seedMainRun(s);
      final gpx = (await RunFileExportService(session: s)
          .build(id, ExportFormat.gpx))!;
      expect(utf8.decode(gpx.bytes), startsWith('<?xml'));
    });

    test('unbekannter oder nicht beendeter Lauf: null', () async {
      final service = RunFileExportService(session: s);
      expect(await service.build(999, ExportFormat.gpx), isNull);
      final active = await s.runs.create(startedAt: xStart);
      for (final f in ExportFormat.values) {
        expect(await service.build(active.id, f), isNull);
      }
    });

    test('leerer Lauf ergibt je Format eine Datei', () async {
      final id = await seedRun(s);
      for (final f in ExportFormat.values) {
        final file = await RunFileExportService(session: s).build(id, f);
        expect(file!.bytes, isNotEmpty);
      }
    });
  });

  group('Dateiname (Abbildungsregel 8)', () {
    test('ungültige Zeichen werden ersetzt, führende Punkte entfallen', () {
      expect(exportFileName('../../etc/passwd', 'gpx'), 'etc_passwd.gpx');
      expect(
        exportFileName('a/b\\c:d*e?f"g<h>i|j', 'fit'),
        'a_b_c_d_e_f_g_h_i_j.fit',
      );
      expect(exportFileName('Lauf am Sée 🏃', 'tcx'), 'Lauf_am_S_e___.tcx');
      expect(exportFileName('', 'gpx'), 'run.gpx');
      expect(exportFileName('._.', 'gpx'), 'run.gpx');
      for (final n in [
        exportFileName('../x', 'gpx'),
        exportFileName('a\u0000b', 'gpx'),
        exportFileName('x' * 400, 'gpx'),
      ]) {
        expect(isSafeExportFileName(n), isTrue, reason: n);
      }
      expect(exportFileName('x' * 400, 'gpx').length, maxExportFileNameLength);
    });

    test('ungültige Erweiterung wird abgelehnt', () {
      for (final ext in ['', 'GPX', 'g/x', '.gpx', 'toolongext']) {
        expect(() => exportFileName('run', ext), throwsArgumentError);
      }
    });

    test('ExportFile lehnt unsichere Namen und MIME-Typen ab', () {
      ExportFile make(String name, [String mime = 'application/gpx+xml']) =>
          ExportFile(fileName: name, mimeType: mime, bytes: Uint8List(0));
      for (final bad in [
        '', '.', '..', '../x.gpx', 'a/b.gpx', '.hidden.gpx', '_x.gpx', //
        'a b.gpx', 'ä.gpx', 'x' * 256,
      ]) {
        expect(() => make(bad), throwsArgumentError, reason: bad);
      }
      for (final bad in ['', 'gpx', 'text/', 'a/b/c', 'Text/Plain']) {
        expect(() => make('run.gpx', bad), throwsArgumentError, reason: bad);
      }
      expect(make('run-20300101-090000.gpx').fileName, isNotEmpty);
      expect(make('x' * 255).fileName.length, 255);
    });
  });

  test(
    'FakeFileHandoff merkt Dateien und liefert das gesetzte Ergebnis',
    () async {
      final fake = FakeFileHandoff();
      final file = ExportFile(
        fileName: 'run.gpx',
        mimeType: 'application/gpx+xml',
        bytes: Uint8List.fromList([1, 2]),
      );
      expect(await fake.share(file), FileHandoffResult.completed);
      fake.nextResult = FileHandoffResult.cancelled;
      expect(await fake.save(file), FileHandoffResult.cancelled);
      expect(fake.shared, [file]);
      expect(fake.saved, [file]);
    },
  );
}
