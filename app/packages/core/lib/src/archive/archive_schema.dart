/// Abschnitte und Spalten des Archivs (`docs/contracts/archive.md` 4.3,
/// Schema 8, Formatversion 2). Ein Test gleicht sie mit der Tabelle im Vertrag ab, ein
/// Adapter-Test mit der Datenbank.
library;

/// Typ einer Spalte: I = INTEGER, R = REAL, T = TEXT, B = BOOLEAN (0/1).
enum ArchiveType { integer, real, text, boolean }

class ArchiveColumn {
  const ArchiveColumn(
    this.name,
    this.type, {
    this.nullable = false,
    this.sinceSchema,
    this.olderValue,
  });

  final String name;
  final ArchiveType type;
  final bool nullable;

  /// Erstes Schema, in dem die Spalte im Archiv steht, wenn sie nach dem
  /// Abschnitt dazukam (`plan_units.fixed` ab 8); sonst `null`.
  final int? sinceSchema;

  /// Wert der Spalte für Zeilen aus einem Archiv vor [sinceSchema].
  final Object? olderValue;
}

/// Ein Abschnitt des Archivs. [key] ist die Spalte der Reihenfolge und des
/// seitenweisen Lesens (Primärschlüssel); [keyIsText] nur bei `settings`.
/// Reservierte Abschnitte (Warnmeldung) haben keine Spalten. Ein
/// Abschnitt mit [columnsSinceSchema] (Ziele und Pläne, seit Schema 7) ist in älteren
/// Schemas reserviert: [forSchema] gibt dann die Form ohne Spalten.
class ArchiveSectionSpec {
  const ArchiveSectionSpec._(
    this.name,
    this.columns,
    this.key,
    this.sinceSchema,
    this.columnsSinceSchema,
  );

  factory ArchiveSectionSpec(
    String name,
    String columns, {
    String? key,
    int sinceSchema = 4,
    int? columnsSinceSchema,
    Map<String, (int, Object?)> addedColumns = const {},
  }) {
    final cols = <ArchiveColumn>[];
    if (columns.isNotEmpty) {
      for (final part in columns.split(', ')) {
        final bits = part.split(' ');
        final nullable = bits[1].endsWith('?');
        final t = switch (bits[1].replaceAll('?', '')) {
          'I' => ArchiveType.integer,
          'R' => ArchiveType.real,
          'T' => ArchiveType.text,
          'B' => ArchiveType.boolean,
          _ => throw ArgumentError.value(part),
        };
        final added = addedColumns[bits[0]];
        cols.add(
          ArchiveColumn(
            bits[0],
            t,
            nullable: nullable,
            sinceSchema: added?.$1,
            olderValue: added?.$2,
          ),
        );
      }
    }
    return ArchiveSectionSpec._(
      name,
      List.unmodifiable(cols),
      cols.isEmpty ? null : key ?? 'id',
      sinceSchema,
      columnsSinceSchema,
    );
  }

  final String name;
  final List<ArchiveColumn> columns;
  final String? key;

  /// Erstes Datenbankschema, in dem der Abschnitt steht (4 bis 8).
  final int sinceSchema;

  /// Erstes Schema, in dem der Abschnitt Zeilen trägt, wenn er schon früher
  /// als leerer Platzhalter im Archiv stand (`goals`, `plans` ab 7); sonst `null`.
  final int? columnsSinceSchema;

  /// Der Abschnitt, wie ihn ein Archiv mit [schema] führt: vor
  /// [columnsSinceSchema] reserviert (keine Spalten, immer leer); Spalten mit
  /// späterem [ArchiveColumn.sinceSchema] fehlen (der Leser setzt dafür
  /// [ArchiveColumn.olderValue]).
  ArchiveSectionSpec forSchema(int schema) {
    final c = columnsSinceSchema;
    if (c != null && schema < c) {
      return ArchiveSectionSpec._(name, const [], null, sinceSchema, c);
    }
    if (!columns.any((col) => (col.sinceSchema ?? 0) > schema)) return this;
    return ArchiveSectionSpec._(
      name,
      List.unmodifiable([
        for (final col in columns)
          if ((col.sinceSchema ?? 0) <= schema) col,
      ]),
      key,
      sinceSchema,
      columnsSinceSchema,
    );
  }

  /// Schlüsselspalte ist Text (nur `settings`).
  bool get keyIsText =>
      key != null &&
      columns.firstWhere((c) => c.name == key).type == ArchiveType.text;

  /// Abschnitt ohne Tabelle (immer leer).
  bool get isReserved => columns.isEmpty;
}

/// Die 24 Abschnitte des Schemas 8 in der Reihenfolge des Vertrags;
/// ältere Schemas haben weniger ([archiveSectionsFor]): Schema 4 die 19 mit
/// `sinceSchema == 4`, Schema 5 dazu die zwei von WP18.
final List<ArchiveSectionSpec> archiveSections = List.unmodifiable([
  ArchiveSectionSpec(
    'runs',
    'id I, state T, started_at_us I, ended_at_us I?, ended_utc_offset_s I?',
  ),
  ArchiveSectionSpec(
    'laps',
    'id I, run_id I, lap_index I, marked_at_us I, lap_time_s R',
  ),
  ArchiveSectionSpec(
    'run_gaps',
    'id I, run_id I, kind T, start_us I, end_us I?',
  ),
  ArchiveSectionSpec(
    'raw_positions',
    'id I, run_id I, time_us I, source T, state T, latitude_deg R?, '
        'longitude_deg R?, accuracy_m R?, speed_mps R?, speed_accuracy_mps R?, '
        'vertical_accuracy_m R?',
  ),
  ArchiveSectionSpec(
    'raw_heart_rates',
    'id I, run_id I, time_us I, source T, state T, bpm I?, contact T',
  ),
  ArchiveSectionSpec(
    'raw_altitudes',
    'id I, run_id I, time_us I, source T, state T, altitude_m R?, '
        'vertical_accuracy_m R?',
  ),
  ArchiveSectionSpec(
    'raw_steps',
    'id I, run_id I, time_us I, source T, state T, step_count I?',
  ),
  ArchiveSectionSpec(
    'preprocessing_results',
    'id I, run_id I, method T, method_version I, parameter_version I, '
        'computed_at_us I, total_time_s R?, moving_time_s R?, distance_m R?, '
        'bridged_distance_m R?, average_bpm R?, max_bpm I?, median_bpm R?, '
        'best_pace_s_per_km R?, lap_count I?, heart_rate_time_s R?',
  ),
  ArchiveSectionSpec(
    'preprocessed_samples',
    'id I, run_id I, channel T, raw_id I, time_us I, state T, discard_reason T?',
  ),
  ArchiveSectionSpec(
    'preprocessed_spans',
    'id I, run_id I, kind T, start_us I, end_us I?',
  ),
  ArchiveSectionSpec(
    'rated_sections',
    'id I, run_id I, start_us I, end_us I, method T, method_version I, '
        'parameter_version I, assessed_at_us I, heart_rate_present I, '
        'heart_rate_estimated I, heart_rate_unavailable I, '
        'heart_rate_discarded I, position_present I, position_estimated I, '
        'position_unavailable I, position_discarded I, '
        'missing_heart_rate_share R, longest_heart_rate_gap_s R, '
        'meets_heart_rate_gap_rule B, settling_overlap_s R, settling_share R, '
        'gps_gaps T',
  ),
  ArchiveSectionSpec(
    'computed_values',
    'id I, run_id I?, day T?, value_key T, role T, value_real R?, unit T, '
        'computed_at_us I, data_from_us I?, data_to_us I?, measurement_count I, '
        'sources T, method T, method_version I, parameter_version I, quality T, '
        'unavailable_reason T?, hr_max_bpm I?, hr_rest_bpm I?, '
        'hr_max_is_estimated B?',
  ),
  ArchiveSectionSpec(
    'value_sections',
    'id I, computed_value_id I, position I, start_us I, end_us I, '
        'gps_median_accuracy_m R?, weight R, late_factor R, status T, '
        'discard T?, reasons T, oxygen_demand R?, estimate R?',
  ),
  ArchiveSectionSpec(
    'profile',
    'id I, birth_year I?, body_weight_kg R?, body_height_m R?, '
        'resting_heart_rate_bpm I?, max_heart_rate_bpm I?, '
        'weekly_run_minutes I?, training_days_mask I?, usual_training_minutes I?',
  ),
  ArchiveSectionSpec('settings', 'key T, value T, updated_at_us I', key: 'key'),
  ArchiveSectionSpec(
    'known_devices',
    'id I, device_id T, display_name T?, is_preferred B, added_at_us I',
  ),
  // WP18, seit Schema 5 (Formatversion 2).
  ArchiveSectionSpec(
    'run_feedback',
    'run_id I, rpe I?, wellbeing I?, complaints T?, warning_answer T?, '
        'note T?, srpe_points R?, srpe_duration_s R?, srpe_method T?, '
        'srpe_method_version I?',
    key: 'run_id',
    sinceSchema: 5,
  ),
  ArchiveSectionSpec(
    'manual_trainings',
    'id I, day T, kind T, duration_s I, rpe I',
    sinceSchema: 5,
  ),
  // WP21, Nummer 19: bis Schema 6 reservierter Platzhalter (0 Zeilen), ab
  // Schema 7 das Ziel.
  ArchiveSectionSpec(
    'goals',
    'id I, type T, distance T?, target_s R?, target_date T?, run_days I, '
        'max_session_s R, weekly_cap_s R, current_weekly_s R?, can_run_30 T, '
        'hard_session B, created_at_us I',
    columnsSinceSchema: 7,
  ),
  // WP21, Nummer 20: ebenso bis Schema 6 reserviert, ab Schema 7 die
  // Plan-Fassungen (`inputs`, `summary` sind JSON-Text).
  ArchiveSectionSpec(
    'plans',
    'id I, goal_id I, created_at_us I, valid_from T, trigger T, reason T, '
        'method T, method_version I, parameter_version I, inputs T, summary T',
    columnsSinceSchema: 7,
  ),
  ArchiveSectionSpec('active_warning', ''),
  // WP20, seit Schema 6 (Nummern 22 und 23; 19 bis 21 sind reserviert).
  // Archive mit Schema 4 oder 5 haben diese Abschnitte nicht.
  ArchiveSectionSpec(
    'reference_performances',
    'id I, kind T, distance_m R, time_s R, performed_on T, created_at_us I, '
        'run_id I?',
    sinceSchema: 6,
  ),
  ArchiveSectionSpec('rejected_suggestions', 'id I, run_id I', sinceSchema: 6),
  // WP21, Nummer 24, ab Schema 7: Einheiten der Plan-Fassungen
  // (`structure` ist JSON-Text, `run_id` ordnet einen Lauf zu). WP22,
  // Schema 8: Spalte `fixed`; Archive mit Schema 7 lesen sich mit 'none'.
  ArchiveSectionSpec(
    'plan_units',
    'id I, plan_id I, day T, week I, phase T, kind T, minutes I, '
        'structure T, run_id I?, pinned B, fixed T',
    sinceSchema: 7,
    addedColumns: {'fixed': (8, 'none')},
  ),
]);

/// Formatversionen, die der Leser kennt.
const List<int> archiveFormats = [1, 2];

/// Formatversion, die der Schreiber erzeugt.
const int archiveWriteFormat = 2;

/// Neuestes Datenbankschema, das Leser und Schreiber kennen.
const int archiveSchemaVersion = 8;

/// Älteste Schemaversion, die gelesen wird (Format 1 beginnt mit Schema 4).
/// Fehlende Abschnitte eines älteren Schemas gelten als leer.
const int archiveMinSchemaVersion = 4;

/// Formatversion eines Schemas: Schema 4 ist Format 1, ab Schema 5 Format 2
/// (Format 2 ist noch nicht ausgeliefert und trägt deshalb Schema 5 bis 8).
int archiveFormatFor(int schema) => schema <= 4 ? 1 : 2;

/// Die Abschnitte eines Schemas in Reihenfolge (4: 19, 5: 21, 6: 23, ab 7:
/// 24; ab 7 tragen die Abschnitte 19 und 20 Zeilen, 24 `plan_units` gibt es
/// nur ab 7, seine Spalte `fixed` ab 8).
/// Ein Schema außerhalb von [archiveMinSchemaVersion] bis
/// [archiveSchemaVersion] wirft einen [RangeError], statt still eine falsche
/// Liste zu geben.
List<ArchiveSectionSpec> archiveSectionsFor(int schema) {
  RangeError.checkValueInInterval(
    schema,
    archiveMinSchemaVersion,
    archiveSchemaVersion,
    'schema',
  );
  return [
    for (final s in archiveSections)
      if (s.sinceSchema <= schema) s.forSchema(schema),
  ];
}
