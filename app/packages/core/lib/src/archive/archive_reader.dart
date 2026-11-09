import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../ports/archive_cipher.dart';
import '../subjective/srpe.dart';
import '../subjective/subjective_limits.dart';
import 'archive_errors.dart';
import 'archive_header.dart';
import 'archive_json.dart';
import 'archive_schema.dart';

/// Längste Zeile (ohne `\n`), Grenze gegen Speicherbomben (Vertrag 4).
const int archiveMaxLineBytes = 16 * 1024 * 1024;

/// Geprüfte Zeilen eines Abschnitts.
class ArchiveRowBatch {
  const ArchiveRowBatch(this.section, this.rows);

  final ArchiveSectionSpec section;
  final List<Map<String, Object?>> rows;
}

final RegExp _isoDay = RegExp(r'^\d{4}-\d{2}-\d{2}$');

const ArchiveImportException _damaged = ArchiveImportException(
  ArchiveImportFailure.damaged,
);

/// Zustandsautomat über den Zeilen des Archivs (Vertrag 4.1 und 4.2): Manifest
/// zuerst, Abschnitte vollständig und in Vertragsreihenfolge, Zeilen nach
/// Spalten und Typen, Endzeile mit Zählern, nichts danach.
class ArchiveLineValidator {
  /// [headerFormat]: Formatversion aus dem Kopf der Datei, falls bekannt; das
  /// Manifest muss dazu passen (Widerspruch: beschädigt).
  ArchiveLineValidator({this.headerFormatOf, required this.today});

  final int? Function()? headerFormatOf;

  /// Heutiger Ortstag als `JJJJ-MM-TT` (Vertrag 4.1, `manual_trainings`): ein
  /// nachgetragenes Training mit späterem Tag macht das Archiv ungültig, wie
  /// die Eingabe (`ManualTraining.requireNotAfter`). Der Leser hat keine Uhr;
  /// der Aufrufer legt den Tag vor dem ersten Schreiben fest.
  final String today;
  List<ArchiveSectionSpec> _sections = archiveSectionsFor(
    archiveMinSchemaVersion,
  );
  int _nextSection = 0;
  ArchiveSectionSpec? _current;
  int _currentCount = 0;
  Object? _lastKey;
  bool _manifestSeen = false;
  bool _ended = false;
  final List<int> _counts = [];

  /// Die Endzeile wurde gelesen und stimmt.
  bool get ended => _ended;

  /// Abschnitt der zuletzt gelesenen Zeile.
  ArchiveSectionSpec? get section => _current;

  /// Prüft eine Zeile. Liefert die Datenzeile in Schemareihenfolge oder `null`
  /// für Manifest, Abschnittskopf und Ende. Wirft [ArchiveImportException].
  Map<String, Object?>? accept(Object? line) {
    if (line is! Map<String, Object?>) throw _damaged;
    if (_ended) throw _damaged;
    final type = line['type'];
    if (!_manifestSeen) {
      if (type != 'manifest') throw _damaged;
      _manifest(line);
      _manifestSeen = true;
      return null;
    }
    switch (type) {
      case 'section':
        _sectionHeader(line);
        return null;
      case 'row':
        return _row(line);
      case 'end':
        _end(line);
        return null;
      default:
        throw _damaged;
    }
  }

  /// Nach dem Ende des Stroms: ohne Endzeile ist das Archiv unvollständig.
  void finish() {
    if (!_ended) throw _damaged;
  }

  static void _exactKeys(Map<String, Object?> m, Set<String> keys) {
    if (m.length != keys.length || !m.keys.every(keys.contains)) {
      throw _damaged;
    }
  }

  void _manifest(Map<String, Object?> m) {
    // Das Schema zuerst: Ein neueres Archiv darf weitere Schlüssel tragen.
    final schema = m['schema_version'];
    if (schema is! int) throw _damaged;
    if (schema > archiveSchemaVersion) {
      throw const ArchiveImportException(ArchiveImportFailure.newerSchema);
    }
    if (schema < archiveMinSchemaVersion) {
      throw const ArchiveImportException(
        ArchiveImportFailure.unsupportedSchema,
      );
    }
    _exactKeys(m, {'type', 'format', 'schema_version', 'created_at_us'});
    final format = m['format'];
    // Format 1 gehört zu Schema 4, Format 2 zu Schema 5 und 6; alles andere
    // ist ein Widerspruch, auch zum Kopf.
    if (format is! int ||
        !archiveFormats.contains(format) ||
        format != archiveFormatFor(schema) ||
        (headerFormatOf?.call() ?? format) != format ||
        m['created_at_us'] is! int) {
      throw _damaged;
    }
    _sections = archiveSectionsFor(schema);
  }

  void _sectionHeader(Map<String, Object?> m) {
    _exactKeys(m, {'type', 'name'});
    if (_nextSection >= _sections.length) throw _damaged;
    final spec = _sections[_nextSection];
    // Unbekannter, doppelter, fehlender (übersprungener) oder verschobener
    // Abschnitt: jeder ist ungleich dem erwarteten Namen.
    if (m['name'] != spec.name) throw _damaged;
    if (_current != null) _counts.add(_currentCount);
    _nextSection++;
    _current = spec;
    _currentCount = 0;
    _lastKey = null;
  }

  Map<String, Object?> _row(Map<String, Object?> m) {
    _exactKeys(m, {'type', 'data'});
    final spec = _current;
    final data = m['data'];
    if (spec == null || spec.isReserved || data is! Map<String, Object?>) {
      throw _damaged;
    }
    if (data.length != spec.columns.length) throw _damaged;
    final out = <String, Object?>{};
    for (final c in spec.columns) {
      if (!data.containsKey(c.name)) throw _damaged;
      final v = data[c.name];
      if (v == null) {
        if (!c.nullable) throw _damaged;
      } else {
        final ok = switch (c.type) {
          ArchiveType.integer => v is int,
          ArchiveType.real => v is num && v.isFinite,
          ArchiveType.text => v is String && isValidArchiveText(v),
          ArchiveType.boolean => v is int && (v == 0 || v == 1),
        };
        if (!ok) throw _damaged;
      }
      out[c.name] = v;
    }
    _checkSubjective(spec, out);
    // Aufsteigend nach dem Schlüssel (Vertrag 4.2); Textschlüssel
    // (`settings`) prüft die Datenbank als Primärschlüssel.
    final key = out[spec.key];
    if (!spec.keyIsText) {
      if (_lastKey != null && (key! as int) <= (_lastKey! as int)) {
        throw _damaged;
      }
      _lastKey = key;
    }
    _currentCount++;
    return out;
  }

  /// Grenzen der Angaben zum Lauf und der nachgetragenen Trainings (WP18):
  /// kein Klemmen, kein Runden. Alles Weitere (Art, Datum, Warnsignal-Regel,
  /// sRPE-Spalten gleichzeitig, Fremdschlüssel) prüft die Datenbank. Nichts
  /// davon nennt einen Wert.
  void _checkSubjective(ArchiveSectionSpec spec, Map<String, Object?> row) {
    bool inRange(Object? v, int lo, int hi) =>
        v == null || (v is int && v >= lo && v <= hi);
    switch (spec.name) {
      case 'run_feedback':
        if (!inRange(row['rpe'], rpeMin, rpeMax) ||
            !inRange(row['wellbeing'], wellbeingMin, wellbeingMax)) {
          throw _damaged;
        }
        // Die vier sRPE-Spalten: alle gesetzt (dann mit RPE) oder alle leer.
        final srpe = [
          row['srpe_points'],
          row['srpe_duration_s'],
          row['srpe_method'],
          row['srpe_method_version'],
        ];
        final set = srpe.where((v) => v != null).length;
        if (set != 0 && (set != srpe.length || row['rpe'] == null)) {
          throw _damaged;
        }
        if (set != 0) {
          final points = row['srpe_points']! as num;
          final seconds = row['srpe_duration_s']! as num;
          // Eigene Methode und Version: der Wert muss Dauer · RPE sein. Andere
          // (ältere) Methoden kann der Leser nicht nachrechnen.
          if (row['srpe_method'] == SrpeLoad.methodId &&
              row['srpe_method_version'] == SrpeLoad.methodVersion) {
            final expected = seconds * (row['rpe']! as int) / 60;
            if ((points - expected).abs() > 1e-6 * (expected.abs() + 1)) {
              throw _damaged;
            }
          }
        }
      case 'manual_trainings':
        final d = row['duration_s'];
        if (d is! int || d <= 0 || !inRange(row['rpe'], rpeMin, rpeMax)) {
          throw _damaged;
        }
        // Gleiche Form, dann ist der Textvergleich der Tagesvergleich. Andere
        // Formen lehnt die Datenbank ab (CHECK, Vertrag 4.1).
        final day = row['day'];
        if (day is String &&
            _isoDay.hasMatch(day) &&
            day.compareTo(today) > 0) {
          throw _damaged;
        }
    }
  }

  void _end(Map<String, Object?> m) {
    _exactKeys(m, {'type', 'rows'});
    if (_nextSection != _sections.length) throw _damaged;
    _counts.add(_currentCount);
    final rows = m['rows'];
    if (rows is! Map<String, Object?> || rows.length != _sections.length) {
      throw _damaged;
    }
    for (var i = 0; i < _sections.length; i++) {
      final n = rows[_sections[i].name];
      // `0.0 == 0` gilt in Dart: Zähler müssen Ganzzahlen sein.
      if (n is! int || n != _counts[i]) throw _damaged;
    }
    _ended = true;
  }
}

/// Zerlegt einen Bytestrom an `\n` in Zeilen. Eine Zeile ohne abschließendes
/// `\n` am Ende, eine leere Zeile und eine zu lange Zeile sind Fehler.
class _LineSplitter {
  final BytesBuilder _pending = BytesBuilder(copy: false);

  void add(Uint8List chunk, void Function(Uint8List line) onLine) {
    var start = 0;
    while (true) {
      final nl = chunk.indexOf(0x0A, start);
      if (nl < 0) {
        final rest = chunk.length - start;
        if (_pending.length + rest > archiveMaxLineBytes) throw _damaged;
        if (rest > 0) {
          _pending.add(Uint8List.fromList(Uint8List.sublistView(chunk, start)));
        }
        return;
      }
      final Uint8List line;
      if (_pending.isEmpty) {
        line = Uint8List.sublistView(chunk, start, nl);
      } else {
        _pending.add(Uint8List.sublistView(chunk, start, nl));
        line = _pending.takeBytes();
      }
      if (line.isEmpty || line.length > archiveMaxLineBytes) throw _damaged;
      onLine(line);
      start = nl + 1;
    }
  }

  /// Am Ende des Stroms darf keine halbe Zeile übrig sein.
  void finish() {
    if (_pending.isNotEmpty) throw _damaged;
  }
}

/// CRC-32 (IEEE, wie gzip).
class _Crc32 {
  static final Uint32List _table = () {
    final t = Uint32List(256);
    for (var n = 0; n < 256; n++) {
      var c = n;
      for (var k = 0; k < 8; k++) {
        c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
      }
      t[n] = c;
    }
    return t;
  }();

  int _crc = 0xFFFFFFFF;

  void add(List<int> data) {
    var c = _crc;
    for (var i = 0; i < data.length; i++) {
      c = _table[(c ^ data[i]) & 0xFF] ^ (c >> 8);
    }
    _crc = c;
  }

  int get value => (_crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

/// Merkt sich die letzten 8 Byte und die Länge eines Bytestroms.
class _Tail8 {
  final Uint8List bytes = Uint8List(8);
  int length = 0;

  void add(List<int> data) {
    length += data.length;
    if (data.length >= 8) {
      bytes.setRange(0, 8, data, data.length - 8);
    } else {
      bytes.setRange(0, 8 - data.length, bytes, data.length);
      bytes.setRange(8 - data.length, 8, data);
    }
  }
}

/// Liest ein Archiv: entschlüsselt über [cipher], entpackt (gzip) als Strom,
/// zerlegt in Zeilen und prüft jede. Liefert die geprüften Zeilen in Stapeln
/// von höchstens [batchRows] (nie über einen Abschnitt hinweg).
///
/// **Nur ein Strom, der ohne Fehler endet, ist ein gültiges Archiv.** Frühere
/// Stapel können kommen, bevor das letzte Stück, der gzip-Rahmen und die
/// Endzeile geprüft sind; wer sie verbraucht, verwirft sie bei jedem Fehler
/// (Zwischendatenbank, Vertrag 3.2). Fehler sind [ArchiveImportException].
Stream<ArchiveRowBatch> readArchive({
  required Stream<List<int>> file,
  required ArchiveCipher cipher,
  required String password,
  required String today,
  int batchRows = 500,
}) async* {
  // Formatversion aus dem Kopf (Offset 8): Das Manifest muss dazu passen.
  // Ohne Magic (Tests mit einem Rahmen ohne Kopf) entfällt die Prüfung.
  final headStart = BytesBuilder(copy: false);
  int? headFormat() {
    if (headStart.length < 10) return null;
    final b = headStart.toBytes();
    for (var i = 0; i < 8; i++) {
      if (b[i] != ArchiveHeader.magic[i]) return null;
    }
    return ByteData.sublistView(b).getUint16(8);
  }

  final validator = ArchiveLineValidator(
    headerFormatOf: headFormat,
    today: today,
  );
  final splitter = _LineSplitter();
  final tail = _Tail8();
  final crc = _Crc32();
  var inflated = 0;
  var rows = <Map<String, Object?>>[];
  ArchiveSectionSpec? batchSection;
  final ready = <ArchiveRowBatch>[];

  void flush() {
    if (rows.isNotEmpty) ready.add(ArchiveRowBatch(batchSection!, rows));
    rows = <Map<String, Object?>>[];
  }

  void onLine(Uint8List bytes) {
    final Object? json;
    // `utf8.decode` entfernt eine Byte-Order-Mark am Anfang still; der
    // Vertrag verlangt UTF-8 ohne BOM.
    if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      throw _damaged;
    }
    try {
      json = parseArchiveJson(utf8.decode(bytes));
    } on FormatException {
      throw _damaged;
    }
    final row = validator.accept(json);
    if (row == null) {
      flush();
      return;
    }
    batchSection = validator.section;
    rows.add(row);
    if (rows.length >= batchRows) flush();
  }

  final tapped = file.map((c) {
    if (headStart.length < 10) {
      headStart.add(c.length > 10 ? c.sublist(0, 10) : c);
    }
    return c;
  });
  final compressed = cipher.decrypt(password, tapped).map((c) {
    tail.add(c);
    return c;
  });
  try {
    await for (final out in gzip.decoder.bind(compressed)) {
      crc.add(out);
      inflated += out.length;
      splitter.add(out is Uint8List ? out : Uint8List.fromList(out), onLine);
      for (final b in ready) {
        yield b;
      }
      ready.clear();
    }
  } on ArchiveException catch (e) {
    throw ArchiveImportException(_map(e.failure));
  } on ArchiveImportException {
    rethrow;
  } on FormatException {
    throw _damaged;
  } on FileSystemException {
    throw const ArchiveImportException(ArchiveImportFailure.readFailed);
  }
  // Dart prüft Länge und Ende des gzip-Elements nicht streng (abgeschnittene
  // Elemente, Byte danach und weitere Elemente werden hingenommen); der
  // Vertrag verlangt genau ein Element. Es endet mit CRC32 und ISIZE der
  // gesamten Ausgabe.
  if (tail.length < 18) throw _damaged;
  final t = ByteData.sublistView(tail.bytes);
  if (t.getUint32(0, Endian.little) != crc.value ||
      t.getUint32(4, Endian.little) != (inflated & 0xFFFFFFFF)) {
    throw _damaged;
  }
  splitter.finish();
  validator.finish();
}

ArchiveImportFailure _map(ArchiveFailure f) => switch (f) {
  ArchiveFailure.notAnArchive => ArchiveImportFailure.notAnArchive,
  ArchiveFailure.unsupportedVersion => ArchiveImportFailure.unsupportedVersion,
  ArchiveFailure.unsupportedParameters =>
    ArchiveImportFailure.unsupportedParameters,
  ArchiveFailure.wrongPasswordOrDamaged =>
    ArchiveImportFailure.wrongPasswordOrDamaged,
  ArchiveFailure.damaged => ArchiveImportFailure.damaged,
};
