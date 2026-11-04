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

  @override
  Future<void> createOriginals(ValueOwner owner, List<ComputedValue> values) =>
      guarded(
        () => _db.transaction(() async {
          await _checkOwner(owner);
          _noDuplicates(values);
          final keys = {for (final r in await _rows(owner)) r.valueKey};
          if (values.any((v) => keys.contains(v.key))) {
            throw const StorageException(StorageFailure.rejected);
          }
          await _db.batch((b) {
            for (final v in values) {
              b.insert(_db.computedValues, _insert(owner, v, _Role.original));
              b.insert(_db.computedValues, _insert(owner, v, _Role.current));
            }
          });
        }),
      );

  @override
  Future<void> swapCurrent(ValueOwner owner, List<ComputedValue> values) =>
      guarded(
        () => _db.transaction(() async {
          await _checkOwner(owner);
          _noDuplicates(values);
          final keys = {
            for (final r in await _rows(owner))
              if (r.role == _Role.original.name) r.valueKey,
          };
          if (values.any((v) => !keys.contains(v.key))) {
            throw const StorageException(StorageFailure.notFound);
          }
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
          }
        }),
      );

  @override
  Future<List<ValuePair>> read(ValueOwner owner) => guarded(() async {
    final original = <String, ComputedValue>{};
    final current = <String, ComputedValue>{};
    for (final r in await _rows(owner)) {
      final v = ComputedValue(
        key: r.valueKey,
        value: r.valueReal,
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
