// Gemeinsame synthetische Füllung aller Tabellen des Schemas 4 für die
// Archiv-Tests mit echter Datenbank (Export, Import).
import 'dart:io';

import 'package:adapters/adapters.dart';
import 'package:drift/native.dart';

// Zur Laufzeit gebaut, damit das Testprogramm (dill) die Marke nicht selbst enthält.
final String fixtureMarker = ['ARCHIV', 'B1', 'MARKE', '8472'].join('-');
const String fixtureConsentMarker = 'EINWILLIGUNG-B1-MARKE-1357';

AppDatabase openPlain(String path) =>
    AppDatabase(NativeDatabase(File(path), setup: ConnectionSetup.configure));

Future<void> sql(AppDatabase db, String sql, [List<Object?> a = const []]) =>
    db.customStatement(sql, a);

/// Mindestens eine Zeile in jeder Tabelle des Schemas 4 (synthetisch).
Future<void> fillAllTables(AppDatabase db) async {
  await sql(
    db,
    "INSERT INTO runs VALUES (1, 'finished', 1000, 2000000000, 3600)",
  );
  await sql(
    db,
    'INSERT INTO laps (run_id, lap_index, marked_at_us, lap_time_s) VALUES (1, 1, 10, 300.5)',
  );
  await sql(
    db,
    "INSERT INTO run_gaps (run_id, kind, start_us) VALUES (1, 'interruption', 5)",
  );
  await sql(
    db,
    'INSERT INTO raw_positions (run_id, time_us, source, state, latitude_deg, longitude_deg, accuracy_m, speed_mps, speed_accuracy_mps, vertical_accuracy_m) '
    "VALUES (1, 1, '$fixtureMarker', 'present', 52.5, 13.25, 4.5, 2.75, 0.5, 3.0)",
  );
  await sql(
    db,
    "INSERT INTO raw_heart_rates (run_id, time_us, source, state, bpm, contact) VALUES (1, 1, 'strap', 'present', 140, 'good')",
  );
  await sql(
    db,
    "INSERT INTO raw_altitudes (run_id, time_us, source, state, altitude_m, vertical_accuracy_m) VALUES (1, 1, 'gps', 'present', 35.5, 2.0)",
  );
  await sql(
    db,
    "INSERT INTO raw_steps (run_id, time_us, source, state, step_count) VALUES (1, 1, 'phone', 'present', 12)",
  );
  await sql(
    db,
    'INSERT INTO preprocessing_results (run_id, method, method_version, parameter_version, computed_at_us, total_time_s, moving_time_s, distance_m, bridged_distance_m, average_bpm, max_bpm, median_bpm, best_pace_s_per_km, lap_count, heart_rate_time_s) '
    "VALUES (1, 'preprocessing', 1, 2, 99, 600.0, 590.0, 2000.0, 0.0, 150.5, 170, 151.0, 300.0, 1, 580.0)",
  );
  await sql(
    db,
    "INSERT INTO preprocessed_samples (run_id, channel, raw_id, time_us, state, discard_reason) VALUES (1, 'position', 1, 1, 'discarded', 'hardJump')",
  );
  await sql(
    db,
    "INSERT INTO preprocessed_spans (run_id, kind, start_us, end_us) VALUES (1, 'moving', 1, 9)",
  );
  await sql(
    db,
    'INSERT INTO rated_sections (run_id, start_us, end_us, method, method_version, parameter_version, assessed_at_us, heart_rate_present, heart_rate_estimated, heart_rate_unavailable, heart_rate_discarded, position_present, position_estimated, position_unavailable, position_discarded, missing_heart_rate_share, longest_heart_rate_gap_s, meets_heart_rate_gap_rule, settling_overlap_s, settling_share, gps_gaps) '
    "VALUES (1, 1, 9, 'section-quality', 1, 2, 99, 1, 0, 0, 0, 1, 0, 0, 0, 0.0, 0.0, 1, 0.0, 0.0, '[]')",
  );
  // original (ohne Wert, mit Grund und Basis), dessen Abschnitt, dann current.
  const cv =
      'INSERT INTO computed_values (run_id, value_key, role, value_real, unit, computed_at_us, data_from_us, data_to_us, measurement_count, sources, method, method_version, parameter_version, quality, unavailable_reason, hr_max_bpm, hr_rest_bpm, hr_max_is_estimated) ';
  await sql(
    db,
    "$cv VALUES (1, 'zone_time.unbekannt', 'original', NULL, 's', 99, 1, 9, 3, '[\"strap\"]', 'm', 1, 2, 'undeterminable', 'insufficientData', 190, NULL, 1)",
  );
  await sql(
    db,
    'INSERT INTO value_sections (computed_value_id, position, start_us, end_us, gps_median_accuracy_m, weight, late_factor, status, discard, reasons, oxygen_demand, estimate) '
    "VALUES (1, 0, 1, 2, 3.5, 1.0, 0.5, 'rejected', 'incomplete', '[\"a\"]', 30.5, 45.25)",
  );
  await sql(
    db,
    "$cv VALUES (1, 'zone_time.unbekannt', 'current', 12.5, 's', 100, 1, 9, 3, '[\"strap\"]', 'm', 1, 3, 'good', NULL, 190, 50, 0)",
  );
  await sql(
    db,
    'INSERT INTO computed_values (day, value_key, role, value_real, unit, computed_at_us, measurement_count, sources, method, method_version, parameter_version, quality) '
    "VALUES ('2026-11-07', 'atl', 'original', 7.0, 'au', 100, 1, '[]', 'm', 1, 1, 'good')",
  );
  await sql(
    db,
    'INSERT INTO profile (id, birth_year, body_weight_kg, body_height_m, resting_heart_rate_bpm, max_heart_rate_bpm, weekly_run_minutes, training_days_mask, usual_training_minutes) VALUES (1, 1990, 70.5, 1.8, 50, 190, 120, 5, 45)',
  );
  await sql(db, "INSERT INTO settings VALUES ('unit.pace', 'min_km', 1)");
  await sql(
    db,
    "INSERT INTO settings VALUES ('values.calculationPending', '1,2', 1)",
  );
  await sql(db, "INSERT INTO settings VALUES ('values.refreshPending', '', 1)");
  await sql(
    db,
    "INSERT INTO settings VALUES ('recalculation.pending', 'x', 1)",
  );
  await sql(
    db,
    "INSERT INTO known_devices (device_id, display_name, is_preferred, added_at_us) VALUES ('AA:BB', 'Gurt', 1, 5)",
  );
  // WP18 (Format 2): Angaben zum Lauf mit sRPE (45 min, RPE 5) und zwei
  // nachgetragene Trainings, eines mit Datum in der Zukunft. Synthetisch.
  await sql(
    db,
    "INSERT INTO run_feedback VALUES (1, 5, 2, 'Wade', 'yes', 'Notiz-Ä', 225.0, 2700.0, 'srpe_duration_rpe', 1)",
  );
  await sql(
    db,
    "INSERT INTO manual_trainings (day, kind, duration_s, rpe) VALUES ('2026-11-01', 'other', 3600, 4), ('2999-12-31', 'run', 1800, 0)",
  );
  await sql(
    db,
    "INSERT INTO consents VALUES ('$fixtureConsentMarker', 'granted', 5)",
  );
  await sql(
    db,
    "INSERT INTO storage_meta VALUES ('technisch', '$fixtureConsentMarker')",
  );
}
