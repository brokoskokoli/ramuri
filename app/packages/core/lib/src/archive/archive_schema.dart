/// Abschnitte und Spalten des Archivs (`docs/contracts/archive.md` 4.3,
/// Schema 5, Formatversion 2). Ein Test gleicht sie mit der Tabelle im Vertrag ab, ein
/// Adapter-Test mit der Datenbank.
library;

/// Typ einer Spalte: I = INTEGER, R = REAL, T = TEXT, B = BOOLEAN (0/1).
enum ArchiveType { integer, real, text, boolean }

class ArchiveColumn {
  const ArchiveColumn(this.name, this.type, {this.nullable = false});

  final String name;
  final ArchiveType type;
  final bool nullable;
}

/// Ein Abschnitt des Archivs. [key] ist die Spalte der Reihenfolge und des
/// seitenweisen Lesens (Primärschlüssel); [keyIsText] nur bei `settings`.
/// Reservierte Abschnitte (Ziele, Pläne, Warnmeldung) haben keine Spalten.
class ArchiveSectionSpec {
  const ArchiveSectionSpec._(
    this.name,
    this.columns,
    this.key,
    this.sinceFormat,
  );

  factory ArchiveSectionSpec(
    String name,
    String columns, {
    String? key,
    int sinceFormat = 1,
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
        cols.add(ArchiveColumn(bits[0], t, nullable: nullable));
      }
    }
    return ArchiveSectionSpec._(
      name,
      List.unmodifiable(cols),
      cols.isEmpty ? null : key ?? 'id',
      sinceFormat,
    );
  }

  final String name;
  final List<ArchiveColumn> columns;
  final String? key;

  /// Erste Formatversion, in der der Abschnitt steht (1 oder 2).
  final int sinceFormat;

  /// Schlüsselspalte ist Text (nur `settings`).
  bool get keyIsText =>
      key != null &&
      columns.firstWhere((c) => c.name == key).type == ArchiveType.text;

  /// Abschnitt ohne Tabelle (immer leer).
  bool get isReserved => columns.isEmpty;
}

/// Die 21 Abschnitte der Formatversion 2 in der Reihenfolge des Vertrags;
/// Formatversion 1 hat die 19 mit `sinceFormat == 1` ([archiveSectionsFor]).
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
  // WP18, Formatversion 2 (Schema 5).
  ArchiveSectionSpec(
    'run_feedback',
    'run_id I, rpe I?, wellbeing I?, complaints T?, warning_answer T?, '
        'note T?, srpe_points R?, srpe_duration_s R?, srpe_method T?, '
        'srpe_method_version I?',
    key: 'run_id',
    sinceFormat: 2,
  ),
  ArchiveSectionSpec(
    'manual_trainings',
    'id I, day T, kind T, duration_s I, rpe I',
    sinceFormat: 2,
  ),
  ArchiveSectionSpec('goals', ''),
  ArchiveSectionSpec('plans', ''),
  ArchiveSectionSpec('active_warning', ''),
]);

/// Formatversionen, die der Leser kennt.
const List<int> archiveFormats = [1, 2];

/// Formatversion, die der Schreiber erzeugt.
const int archiveWriteFormat = 2;

/// Datenbankschema, das zu einer Formatversion gehört (Format 1: 4, Format 2: 5).
int archiveSchemaFor(int format) => format == 1 ? 4 : 5;

/// Die Abschnitte einer Formatversion in Reihenfolge.
List<ArchiveSectionSpec> archiveSectionsFor(int format) => [
  for (final s in archiveSections)
    if (s.sinceFormat <= format) s,
];
