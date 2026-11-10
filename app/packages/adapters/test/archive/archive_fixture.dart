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
  // Belastungsprofil (WP19), vor den übrigen in Schlüsselreihenfolge: vier Einstellungen gehören ins Archiv, die
  // unbestätigte Wahl und die Faktor-Merker sind technische Merker.
  for (final kv in const [
    ('load.all_recorded', '1'),
    ('load.coefficients', 'female'),
    ('load.coefficients_pending', 'male'),
    ('load.factor', 'banister;1.5;14;2026-11-07'),
    ('load.factor_declined', 'banister;3.0;14;2026-11-01'),
    ('load.factor_pending', 'banister;2.5;14;2026-11-08'),
    ('load.profile', 'banister'),
    ('load.profile_pending', 'edwards'),
  ]) {
    await sql(db, "INSERT INTO settings VALUES ('${kv.$1}', '${kv.$2}', 1)");
  }
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
    "INSERT INTO manual_trainings (day, kind, duration_s, rpe) VALUES ('2026-11-01', 'other', 3600, 4), ('2026-11-20', 'run', 1800, 0)",
  );
  // Leistungsprognose (Schema 6): eine Wettkampfzeit ohne Lauf, ein
  // bestätigter Lauf mit Verweis, ein abgelehnter Vorschlag.
  await sql(
    db,
    'INSERT INTO reference_performances (kind, distance_m, time_s, performed_on, created_at_us, run_id) '
    "VALUES ('race', 10000.0, 3012.5, '2026-10-01', 7, NULL), "
    "('confirmedRun', 5000.0, 1490.0, '2026-11-02', 8, 1)",
  );
  await sql(db, 'INSERT INTO rejected_suggestions (run_id) VALUES (1)');
  // Ziel (Schema 7): Zeitziel über 10 km, Lauftage Mo, Mi, Fr (Maske 21).
  await sql(
    db,
    'INSERT INTO goals (id, type, distance, target_s, target_date, run_days, '
    'max_session_s, weekly_cap_s, current_weekly_s, can_run_30, hard_session, '
    'created_at_us) '
    "VALUES (1, 'time', 'tenKilometers', 3000.0, '2027-03-20', 21, 3600.0, "
    "14400.0, 7200.0, 'yes', 1, 9)",
  );
  // Plan (Schema 7): eine Fassung mit zwei Einheiten; die erste mit Lauf und
  // Geh-Lauf-Segmenten in Sekunden, die zweite ein Ruhetag. Synthetisch.
  await sql(
    db,
    'INSERT INTO plans (id, goal_id, created_at_us, valid_from, "trigger", '
    'reason, method, method_version, parameter_version, inputs, summary) '
    "VALUES (1, 1, 10, '2026-11-02', 'create', 'goalCreated', 'plan-rules', "
    '1, 1, \'{"today":"2026-11-02","weeklyRunMinutes":120}\', '
    '\'{"weeks":12,"estimated":true}\')',
  );
  await sql(
    db,
    'INSERT INTO plan_units (id, plan_id, day, week, phase, kind, minutes, '
    'structure, run_id, pinned) VALUES '
    "(1, 1, '2026-11-02', 0, 'entry', 'walkRun', 30, "
    '\'[{"kind":"walk","minutes":5,"seconds":300},'
    '{"kind":"run","minutes":2,"seconds":90,"intensity":{"rpeMin":3,'
    '"rpeMax":4,"paceFast":360.0,"paceSlow":420.0,"basis":"estimate",'
    '"hrMin":null,"hrMax":null,"estimated":true,"maxHrEstimated":false,'
    '"paceIsLimit":false}}]\', 1, 1), '
    "(2, 1, '2026-11-03', 0, 'entry', 'rest', 0, '[]', NULL, 0)",
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
