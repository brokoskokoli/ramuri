import 'dart:convert';
import 'dart:typed_data';

import '../../ports/archive_source.dart';
import '../../ports/clock.dart';
import '../health/health_import.dart';
import '../recalculation/recalculation_service.dart';
import '../recalculation/value_calculation_service.dart';
import '../settings/display_settings.dart';
import 'archive_errors.dart';
import 'archive_json.dart';
import 'archive_schema.dart';

/// Technische Merker in `settings`, die nicht ins Archiv gehören (Vertrag 4.3).
const Set<String> archiveExcludedSettingKeys = {
  ValueCalculationService.calculationPendingKey,
  ValueCalculationService.refreshPendingKey,
  RecalculationService.pendingKey,
  SettingKeys.loadProfilePending,
  SettingKeys.loadCoefficientsPending,
  SettingKeys.loadFactorPending,
  SettingKeys.loadFactorDeclined,
  SettingKeys.planStartedUnit,
  SettingKeys.guidedUnitSnapshot,
  HealthImportService.lastImportKey,
};

/// Zeilen je Seite beim Lesen.
const int archivePageSize = 500;

/// Zielgröße eines Stücks Text für den Strom (Zeichen).
const int _batchChars = 64 * 1024;

/// Erzeugt den Klartext des Archivs (JSON Lines, UTF-8) als Strom aus
/// Stücken zu etwa 64 KiB. Liest die Datenbank seitenweise; nichts wird
/// vollständig im Speicher gehalten. Fehler tragen nie Inhalte.
Stream<Uint8List> archiveLines({
  required ArchiveSource source,
  required Clock clock,
  int pageSize = archivePageSize,
  bool Function()? isCancelled,
}) async* {
  final out = StringBuffer();
  Uint8List? flush({bool force = false}) {
    if (out.isEmpty || (!force && out.length < _batchChars)) return null;
    final bytes = Uint8List.fromList(utf8.encode(out.toString()));
    out.clear();
    return bytes;
  }

  void line(Map<String, Object?> json) {
    out.write(jsonEncode(json));
    out.write('\n');
  }

  final ArchiveSnapshot snapshot;
  try {
    snapshot = await source.open();
  } on ArchiveExportException {
    rethrow;
  } catch (_) {
    throw const ArchiveExportException(ArchiveExportFailure.readFailed);
  }
  line({
    'type': 'manifest',
    'format': archiveWriteFormat,
    'schema_version': archiveSchemaVersion,
    'created_at_us': clock.now().toUtc().microsecondsSinceEpoch,
  });
  final counts = <String, int>{};
  for (final section in archiveSectionsFor(archiveSchemaVersion)) {
    line({'type': 'section', 'name': section.name});
    var count = 0;
    Object? after;
    while (!section.isReserved) {
      if (isCancelled?.call() ?? false) {
        throw const ArchiveExportException(ArchiveExportFailure.cancelled);
      }
      final List<Map<String, Object?>> page;
      try {
        page = await snapshot.readPage(section, after: after, limit: pageSize);
      } on ArchiveExportException {
        rethrow;
      } catch (_) {
        throw const ArchiveExportException(ArchiveExportFailure.readFailed);
      }
      if (page.isEmpty) break;
      for (final row in page) {
        final key = row[section.key];
        if (_skip(section, key)) continue;
        line({'type': 'row', 'data': encodeArchiveRow(section, row)});
        count++;
      }
      after = page.last[section.key];
      if (after == null) {
        throw const ArchiveExportException(ArchiveExportFailure.invalidData);
      }
      final bytes = flush();
      if (bytes != null) yield bytes;
      if (page.length < pageSize) break;
    }
    counts[section.name] = count;
  }
  line({'type': 'end', 'rows': counts});
  final rest = flush(force: true);
  if (rest != null) yield rest;
}

bool _skip(ArchiveSectionSpec section, Object? key) =>
    section.name == 'settings' && archiveExcludedSettingKeys.contains(key);

/// Prüft eine Zeile gegen den Abschnitt und gibt sie in Schemareihenfolge
/// zurück. Wirft [ArchiveExportException] (`invalidData`) ohne den Wert zu
/// nennen: fehlende oder zusätzliche Spalte, falscher Typ, NULL in einer
/// Pflichtspalte, nicht endliche Zahl, einzelnes Surrogat im Text.
Map<String, Object?> encodeArchiveRow(
  ArchiveSectionSpec section,
  Map<String, Object?> row,
) {
  const bad = ArchiveExportException(ArchiveExportFailure.invalidData);
  if (row.length != section.columns.length) throw bad;
  final out = <String, Object?>{};
  for (final c in section.columns) {
    if (!row.containsKey(c.name)) throw bad;
    final v = row[c.name];
    if (v == null) {
      if (!c.nullable) throw bad;
    } else {
      final ok = switch (c.type) {
        ArchiveType.integer => v is int,
        ArchiveType.real => v is num && v.isFinite,
        ArchiveType.text => v is String && isValidArchiveText(v),
        ArchiveType.boolean => v is int && (v == 0 || v == 1),
        ArchiveType.blob => v is Uint8List,
      };
      if (!ok) throw bad;
    }
    out[c.name] = v is Uint8List ? encodeArchiveBlob(v) : v;
  }
  return out;
}
