import 'dart:convert';

import 'package:core/core.dart';
import 'package:drift/drift.dart'
    show BooleanExpressionOperators, OrderingTerm, Value;

import 'access_support.dart';
import 'app_database.dart' as d;

/// Rolle der Zeile (ADR-0004 Punkt 4), Namen wie in der Spalte `role`.
enum _Role { original, current }

class DriftComputedValueStore implements ComputedValueStore {
  DriftComputedValueStore(this._db);
  final d.AppDatabase _db;

  Future<void> _checkOwner(ValueOwner o) async {
    final id = o.runId;
    if (id != null) await requireRun(_db, id);
  }

  static void _noDuplicates(List<ComputedValue> vs) {
    if (vs.map((v) => v.key).toSet().length != vs.length) {
      throw const StorageException(StorageFailure.rejected);
    }
  }

  /// Alle Zeilen des Besitzers.
  Future<List<d.ComputedValue>> _rows(ValueOwner o) =>
      (_db.select(_db.computedValues)
            ..where(
              (t) => o.runId != null
                  ? t.runId.equals(o.runId!)
                  : t.day.equals(o.day!),
            )
            ..orderBy([(t) => OrderingTerm.asc(t.valueKey)]))
          .get();

  d.ComputedValuesCompanion _insert(
    ValueOwner o,
    ComputedValue v,
    _Role role,
  ) => d.ComputedValuesCompanion.insert(
    runId: Value(o.runId),
    day: Value(o.day),
    valueKey: v.key,
    role: role.name,
    valueReal: Value(v.value),
    unavailableReason: Value(v.unavailableReason?.name),
    unit: v.unit,
    computedAtUs: usOf(v.computedAt),
    dataFromUs: Value(usOfOrNull(v.dataFrom)),
    dataToUs: Value(usOfOrNull(v.dataTo)),
    measurementCount: v.measurementCount,
    sources: jsonEncode(v.sources),
    method: v.method,
    methodVersion: v.methodVersion,
    parameterVersion: v.parameterVersion,
    quality: v.quality.name,
  );

  Future<void> _insertSections(int valueId, List<ValueSection> sections) async {
    for (var i = 0; i < sections.length; i++) {
      final s = sections[i];
      await _db
          .into(_db.valueSections)
          .insert(
            d.ValueSectionsCompanion.insert(
              computedValueId: valueId,
              position: i,
              startUs: usOf(s.start),
              endUs: usOf(s.end),
              gpsMedianAccuracyM: Value(s.gpsMedianAccuracyMeters),
              weight: s.weight,
              lateFactor: s.lateFactor,
              status: s.status.name,
              discard: Value(s.discard?.name),
              reasons: jsonEncode(s.reasons),
              oxygenDemand: Value(s.oxygenDemand),
              estimate: Value(s.estimate),
            ),
          );
    }
  }

  @override
  Future<void> createOriginals(
    ValueOwner owner,
    List<ComputedValue> values,
  ) => guarded(
    () => _db.transaction(() async {
      await _checkOwner(owner);
      _noDuplicates(values);
      final keys = {for (final r in await _rows(owner)) r.valueKey};
      if (values.any((v) => keys.contains(v.key))) {
        throw const StorageException(StorageFailure.rejected);
      }
      requireStorableValues(values);
      // Je Wert: original, dessen Abschnitte, dann current samt Abschnitten.
      // Die Reihenfolge ist Teil des Schutzes der Original-Abschnitte (Trigger
      // value_sections_original_no_late_insert).
      for (final v in values) {
        for (final role in _Role.values) {
          final id = await _db
              .into(_db.computedValues)
              .insert(_insert(owner, v, role));
          await _insertSections(id, v.sections);
        }
      }
    }),
  );

  @override
  Future<void> swapCurrent(ValueOwner owner, List<ComputedValue> values) =>
      swapCurrentAll({owner: values});

  @override
  Future<void> swapCurrentAll(Map<ValueOwner, List<ComputedValue>> changes) =>
      guarded(
        () => _db.transaction(() async {
          for (final e in changes.entries) {
            await _swapIn(e.key, e.value);
          }
        }),
      );

  Future<void> _swapIn(ValueOwner owner, List<ComputedValue> values) async {
    await _checkOwner(owner);
    _noDuplicates(values);
    final keys = {
      for (final r in await _rows(owner))
        if (r.role == _Role.original.name) r.valueKey,
    };
    if (values.any((v) => !keys.contains(v.key))) {
      throw const StorageException(StorageFailure.notFound);
    }
    requireStorableValues(values);
    final currentIds = {
      for (final r in await _rows(owner))
        if (r.role == _Role.current.name) r.valueKey: r.id,
    };
    for (final v in values) {
      await (_db.update(_db.computedValues)..where(
            (t) =>
                (owner.runId != null
                    ? t.runId.equals(owner.runId!)
                    : t.day.equals(owner.day!)) &
                t.valueKey.equals(v.key) &
                t.role.equals(_Role.current.name),
          ))
          .write(
            d.ComputedValuesCompanion(
              valueReal: Value(v.value),
              unavailableReason: Value(v.unavailableReason?.name),
              unit: Value(v.unit),
              computedAtUs: Value(usOf(v.computedAt)),
              dataFromUs: Value(usOfOrNull(v.dataFrom)),
              dataToUs: Value(usOfOrNull(v.dataTo)),
              measurementCount: Value(v.measurementCount),
              sources: Value(jsonEncode(v.sources)),
              method: Value(v.method),
              methodVersion: Value(v.methodVersion),
              parameterVersion: Value(v.parameterVersion),
              quality: Value(v.quality.name),
            ),
          );
      // Abschnitte des current ersetzen; die des original bleiben.
      final id = currentIds[v.key]!;
      await (_db.delete(
        _db.valueSections,
      )..where((t) => t.computedValueId.equals(id))).go();
      await _insertSections(id, v.sections);
    }
  }

  @override
  Future<List<ValuePair>> read(ValueOwner owner) => guarded(() async {
    final original = <String, ComputedValue>{};
    final current = <String, ComputedValue>{};
    final rows = await _rows(owner);
    final sections = <int, List<ValueSection>>{};
    if (rows.isNotEmpty) {
      final found =
          await (_db.select(_db.valueSections)
                ..where((t) => t.computedValueId.isIn(rows.map((r) => r.id)))
                ..orderBy([
                  (t) => OrderingTerm.asc(t.computedValueId),
                  (t) => OrderingTerm.asc(t.position),
                ]))
              .get();
      for (final x in found) {
        (sections[x.computedValueId] ??= []).add(
          ValueSection(
            start: timeOf(x.startUs),
            end: timeOf(x.endUs),
            weight: x.weight,
            lateFactor: x.lateFactor,
            status: enumOf(SectionStatus.values, x.status, (v) => v.name),
            reasons: [
              for (final e in jsonDecode(x.reasons) as List) e as String,
            ],
            gpsMedianAccuracyMeters: x.gpsMedianAccuracyM,
            discard: x.discard == null
                ? null
                : enumOf(EstimateDiscard.values, x.discard!, (v) => v.name),
            oxygenDemand: x.oxygenDemand,
            estimate: x.estimate,
          ),
        );
      }
    }
    for (final r in rows) {
      final v = ComputedValue(
        sections: sections[r.id] ?? const [],
        key: r.valueKey,
        value: r.valueReal,
        unavailableReason: r.unavailableReason == null
            ? null
            : enumOf(
                UnavailableReason.values,
                r.unavailableReason!,
                (v) => v.name,
              ),
        unit: r.unit,
        computedAt: timeOf(r.computedAtUs),
        dataFrom: timeOfOrNull(r.dataFromUs),
        dataTo: timeOfOrNull(r.dataToUs),
        measurementCount: r.measurementCount,
        sources: [for (final s in jsonDecode(r.sources) as List) s as String],
        method: r.method,
        methodVersion: r.methodVersion,
        parameterVersion: r.parameterVersion,
        quality: enumOf(ValueQuality.values, r.quality, (v) => v.name),
      );
      (r.role == _Role.original.name ? original : current)[r.valueKey] = v;
    }
    return [
      for (final k in original.keys)
        if (current.containsKey(k))
          ValuePair(original: original[k]!, current: current[k]!),
    ];
  });
}
