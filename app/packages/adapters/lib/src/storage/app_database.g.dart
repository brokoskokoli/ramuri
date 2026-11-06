// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class StorageMeta extends Table with TableInfo<StorageMeta, StorageMetaData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  StorageMeta(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL PRIMARY KEY',
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'storage_meta';
  @override
  VerificationContext validateIntegrity(
    Insertable<StorageMetaData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  StorageMetaData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StorageMetaData(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  StorageMeta createAlias(String alias) {
    return StorageMeta(attachedDatabase, alias);
  }

  @override
  bool get dontWriteConstraints => true;
}

class StorageMetaData extends DataClass implements Insertable<StorageMetaData> {
  final String key;
  final String value;
  const StorageMetaData({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  StorageMetaCompanion toCompanion(bool nullToAbsent) {
    return StorageMetaCompanion(key: Value(key), value: Value(value));
  }

  factory StorageMetaData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StorageMetaData(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  StorageMetaData copyWith({String? key, String? value}) =>
      StorageMetaData(key: key ?? this.key, value: value ?? this.value);
  StorageMetaData copyWithCompanion(StorageMetaCompanion data) {
    return StorageMetaData(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StorageMetaData(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StorageMetaData &&
          other.key == this.key &&
          other.value == this.value);
}

class StorageMetaCompanion extends UpdateCompanion<StorageMetaData> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const StorageMetaCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  StorageMetaCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value);
  static Insertable<StorageMetaData> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  StorageMetaCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return StorageMetaCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('StorageMetaCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class Runs extends Table with TableInfo<Runs, Run> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  Runs(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL PRIMARY KEY AUTOINCREMENT',
  );
  static const VerificationMeta _stateMeta = const VerificationMeta('state');
  late final GeneratedColumn<String> state = GeneratedColumn<String>(
    'state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints:
        'NOT NULL CHECK (state IN (\'active\', \'paused\', \'finished\'))',
  );
  static const VerificationMeta _startedAtUsMeta = const VerificationMeta(
    'startedAtUs',
  );
  late final GeneratedColumn<int> startedAtUs = GeneratedColumn<int>(
    'started_at_us',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _endedAtUsMeta = const VerificationMeta(
    'endedAtUs',
  );
  late final GeneratedColumn<int> endedAtUs = GeneratedColumn<int>(
    'ended_at_us',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _endedUtcOffsetSMeta = const VerificationMeta(
    'endedUtcOffsetS',
  );
  late final GeneratedColumn<int> endedUtcOffsetS = GeneratedColumn<int>(
    'ended_utc_offset_s',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: 'CHECK (ended_utc_offset_s BETWEEN -64800 AND 64800)',
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    state,
    startedAtUs,
    endedAtUs,
    endedUtcOffsetS,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'runs';
  @override
  VerificationContext validateIntegrity(
    Insertable<Run> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('state')) {
      context.handle(
        _stateMeta,
        state.isAcceptableOrUnknown(data['state']!, _stateMeta),
      );
    } else if (isInserting) {
      context.missing(_stateMeta);
    }
    if (data.containsKey('started_at_us')) {
      context.handle(
        _startedAtUsMeta,
        startedAtUs.isAcceptableOrUnknown(
          data['started_at_us']!,
          _startedAtUsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_startedAtUsMeta);
    }
    if (data.containsKey('ended_at_us')) {
      context.handle(
        _endedAtUsMeta,
        endedAtUs.isAcceptableOrUnknown(data['ended_at_us']!, _endedAtUsMeta),
      );
    }
    if (data.containsKey('ended_utc_offset_s')) {
      context.handle(
        _endedUtcOffsetSMeta,
        endedUtcOffsetS.isAcceptableOrUnknown(
          data['ended_utc_offset_s']!,
          _endedUtcOffsetSMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Run map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Run(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      state: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}state'],
      )!,
      startedAtUs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}started_at_us'],
      )!,
      endedAtUs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}ended_at_us'],
      ),
      endedUtcOffsetS: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}ended_utc_offset_s'],
      ),
    );
  }

  @override
  Runs createAlias(String alias) {
    return Runs(attachedDatabase, alias);
  }

  @override
  bool get dontWriteConstraints => true;
}

class Run extends DataClass implements Insertable<Run> {
  final int id;
  final String state;
  final int startedAtUs;

  /// NULL, solange der Lauf nicht beendet ist.
  final int? endedAtUs;

  /// Seit Version 3 (WP09 D2a): UTC-Versatz der Ortszeit zum Laufende in
  /// Sekunden (Zeitzone zum Laufzeitpunkt; Tageswerte hängen am lokalen
  /// Kalendertag des Laufendes). NULL = unbekannt: Läufe aus Version 1, oder
  /// der Aufrufer hat ihn nicht genannt; nur bei beendetem Lauf (Trigger).
  final int? endedUtcOffsetS;
  const Run({
    required this.id,
    required this.state,
    required this.startedAtUs,
    this.endedAtUs,
    this.endedUtcOffsetS,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['state'] = Variable<String>(state);
    map['started_at_us'] = Variable<int>(startedAtUs);
    if (!nullToAbsent || endedAtUs != null) {
      map['ended_at_us'] = Variable<int>(endedAtUs);
    }
    if (!nullToAbsent || endedUtcOffsetS != null) {
      map['ended_utc_offset_s'] = Variable<int>(endedUtcOffsetS);
    }
    return map;
  }

  RunsCompanion toCompanion(bool nullToAbsent) {
    return RunsCompanion(
      id: Value(id),
      state: Value(state),
      startedAtUs: Value(startedAtUs),
      endedAtUs: endedAtUs == null && nullToAbsent
          ? const Value.absent()
          : Value(endedAtUs),
      endedUtcOffsetS: endedUtcOffsetS == null && nullToAbsent
          ? const Value.absent()
          : Value(endedUtcOffsetS),
    );
  }

  factory Run.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Run(
      id: serializer.fromJson<int>(json['id']),
      state: serializer.fromJson<String>(json['state']),
      startedAtUs: serializer.fromJson<int>(json['started_at_us']),
      endedAtUs: serializer.fromJson<int?>(json['ended_at_us']),
      endedUtcOffsetS: serializer.fromJson<int?>(json['ended_utc_offset_s']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'state': serializer.toJson<String>(state),
      'started_at_us': serializer.toJson<int>(startedAtUs),
      'ended_at_us': serializer.toJson<int?>(endedAtUs),
      'ended_utc_offset_s': serializer.toJson<int?>(endedUtcOffsetS),
    };
  }

  Run copyWith({
    int? id,
    String? state,
    int? startedAtUs,
    Value<int?> endedAtUs = const Value.absent(),
    Value<int?> endedUtcOffsetS = const Value.absent(),
  }) => Run(
    id: id ?? this.id,
    state: state ?? this.state,
    startedAtUs: startedAtUs ?? this.startedAtUs,
    endedAtUs: endedAtUs.present ? endedAtUs.value : this.endedAtUs,
    endedUtcOffsetS: endedUtcOffsetS.present
        ? endedUtcOffsetS.value
        : this.endedUtcOffsetS,
  );
  Run copyWithCompanion(RunsCompanion data) {
    return Run(
      id: data.id.present ? data.id.value : this.id,
      state: data.state.present ? data.state.value : this.state,
      startedAtUs: data.startedAtUs.present
          ? data.startedAtUs.value
          : this.startedAtUs,
      endedAtUs: data.endedAtUs.present ? data.endedAtUs.value : this.endedAtUs,
      endedUtcOffsetS: data.endedUtcOffsetS.present
          ? data.endedUtcOffsetS.value
          : this.endedUtcOffsetS,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Run(')
          ..write('id: $id, ')
          ..write('state: $state, ')
          ..write('startedAtUs: $startedAtUs, ')
          ..write('endedAtUs: $endedAtUs, ')
          ..write('endedUtcOffsetS: $endedUtcOffsetS')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, state, startedAtUs, endedAtUs, endedUtcOffsetS);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Run &&
          other.id == this.id &&
          other.state == this.state &&
          other.startedAtUs == this.startedAtUs &&
          other.endedAtUs == this.endedAtUs &&
          other.endedUtcOffsetS == this.endedUtcOffsetS);
}

class RunsCompanion extends UpdateCompanion<Run> {
  final Value<int> id;
  final Value<String> state;
  final Value<int> startedAtUs;
  final Value<int?> endedAtUs;
  final Value<int?> endedUtcOffsetS;
  const RunsCompanion({
    this.id = const Value.absent(),
    this.state = const Value.absent(),
    this.startedAtUs = const Value.absent(),
    this.endedAtUs = const Value.absent(),
    this.endedUtcOffsetS = const Value.absent(),
  });
  RunsCompanion.insert({
    this.id = const Value.absent(),
    required String state,
    required int startedAtUs,
    this.endedAtUs = const Value.absent(),
    this.endedUtcOffsetS = const Value.absent(),
  }) : state = Value(state),
       startedAtUs = Value(startedAtUs);
  static Insertable<Run> custom({
    Expression<int>? id,
    Expression<String>? state,
    Expression<int>? startedAtUs,
    Expression<int>? endedAtUs,
    Expression<int>? endedUtcOffsetS,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (state != null) 'state': state,
      if (startedAtUs != null) 'started_at_us': startedAtUs,
      if (endedAtUs != null) 'ended_at_us': endedAtUs,
      if (endedUtcOffsetS != null) 'ended_utc_offset_s': endedUtcOffsetS,
    });
  }

  RunsCompanion copyWith({
    Value<int>? id,
    Value<String>? state,
    Value<int>? startedAtUs,
    Value<int?>? endedAtUs,
    Value<int?>? endedUtcOffsetS,
  }) {
    return RunsCompanion(
      id: id ?? this.id,
      state: state ?? this.state,
      startedAtUs: startedAtUs ?? this.startedAtUs,
      endedAtUs: endedAtUs ?? this.endedAtUs,
      endedUtcOffsetS: endedUtcOffsetS ?? this.endedUtcOffsetS,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(state.value);
    }
    if (startedAtUs.present) {
      map['started_at_us'] = Variable<int>(startedAtUs.value);
    }
    if (endedAtUs.present) {
      map['ended_at_us'] = Variable<int>(endedAtUs.value);
    }
    if (endedUtcOffsetS.present) {
      map['ended_utc_offset_s'] = Variable<int>(endedUtcOffsetS.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RunsCompanion(')
          ..write('id: $id, ')
          ..write('state: $state, ')
          ..write('startedAtUs: $startedAtUs, ')
          ..write('endedAtUs: $endedAtUs, ')
          ..write('endedUtcOffsetS: $endedUtcOffsetS')
          ..write(')'))
        .toString();
  }
}

class Laps extends Table with TableInfo<Laps, Lap> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  Laps(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL PRIMARY KEY AUTOINCREMENT',
  );
  static const VerificationMeta _runIdMeta = const VerificationMeta('runId');
  late final GeneratedColumn<int> runId = GeneratedColumn<int>(
    'run_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL REFERENCES runs(id)ON DELETE CASCADE',
  );
  static const VerificationMeta _lapIndexMeta = const VerificationMeta(
    'lapIndex',
  );
  late final GeneratedColumn<int> lapIndex = GeneratedColumn<int>(
    'lap_index',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _markedAtUsMeta = const VerificationMeta(
    'markedAtUs',
  );
  late final GeneratedColumn<int> markedAtUs = GeneratedColumn<int>(
    'marked_at_us',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _lapTimeSMeta = const VerificationMeta(
    'lapTimeS',
  );
  late final GeneratedColumn<double> lapTimeS = GeneratedColumn<double>(
    'lap_time_s',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    runId,
    lapIndex,
    markedAtUs,
    lapTimeS,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'laps';
  @override
  VerificationContext validateIntegrity(
    Insertable<Lap> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('run_id')) {
      context.handle(
        _runIdMeta,
        runId.isAcceptableOrUnknown(data['run_id']!, _runIdMeta),
      );
    } else if (isInserting) {
      context.missing(_runIdMeta);
    }
    if (data.containsKey('lap_index')) {
      context.handle(
        _lapIndexMeta,
        lapIndex.isAcceptableOrUnknown(data['lap_index']!, _lapIndexMeta),
      );
    } else if (isInserting) {
      context.missing(_lapIndexMeta);
    }
    if (data.containsKey('marked_at_us')) {
      context.handle(
        _markedAtUsMeta,
        markedAtUs.isAcceptableOrUnknown(
          data['marked_at_us']!,
          _markedAtUsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_markedAtUsMeta);
    }
    if (data.containsKey('lap_time_s')) {
      context.handle(
        _lapTimeSMeta,
        lapTimeS.isAcceptableOrUnknown(data['lap_time_s']!, _lapTimeSMeta),
      );
    } else if (isInserting) {
      context.missing(_lapTimeSMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {runId, lapIndex},
  ];
  @override
  Lap map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Lap(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      runId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}run_id'],
      )!,
      lapIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}lap_index'],
      )!,
      markedAtUs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}marked_at_us'],
      )!,
      lapTimeS: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}lap_time_s'],
      )!,
    );
  }

  @override
  Laps createAlias(String alias) {
    return Laps(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints => const ['UNIQUE(run_id, lap_index)'];
  @override
  bool get dontWriteConstraints => true;
}

class Lap extends DataClass implements Insertable<Lap> {
  final int id;
  final int runId;
  final int lapIndex;
  final int markedAtUs;
  final double lapTimeS;
  const Lap({
    required this.id,
    required this.runId,
    required this.lapIndex,
    required this.markedAtUs,
    required this.lapTimeS,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['run_id'] = Variable<int>(runId);
    map['lap_index'] = Variable<int>(lapIndex);
    map['marked_at_us'] = Variable<int>(markedAtUs);
    map['lap_time_s'] = Variable<double>(lapTimeS);
    return map;
  }

  LapsCompanion toCompanion(bool nullToAbsent) {
    return LapsCompanion(
      id: Value(id),
      runId: Value(runId),
      lapIndex: Value(lapIndex),
      markedAtUs: Value(markedAtUs),
      lapTimeS: Value(lapTimeS),
    );
  }

  factory Lap.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Lap(
      id: serializer.fromJson<int>(json['id']),
      runId: serializer.fromJson<int>(json['run_id']),
      lapIndex: serializer.fromJson<int>(json['lap_index']),
      markedAtUs: serializer.fromJson<int>(json['marked_at_us']),
      lapTimeS: serializer.fromJson<double>(json['lap_time_s']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'run_id': serializer.toJson<int>(runId),
      'lap_index': serializer.toJson<int>(lapIndex),
      'marked_at_us': serializer.toJson<int>(markedAtUs),
      'lap_time_s': serializer.toJson<double>(lapTimeS),
    };
  }

  Lap copyWith({
    int? id,
    int? runId,
    int? lapIndex,
    int? markedAtUs,
    double? lapTimeS,
  }) => Lap(
    id: id ?? this.id,
    runId: runId ?? this.runId,
    lapIndex: lapIndex ?? this.lapIndex,
    markedAtUs: markedAtUs ?? this.markedAtUs,
    lapTimeS: lapTimeS ?? this.lapTimeS,
  );
  Lap copyWithCompanion(LapsCompanion data) {
    return Lap(
      id: data.id.present ? data.id.value : this.id,
      runId: data.runId.present ? data.runId.value : this.runId,
      lapIndex: data.lapIndex.present ? data.lapIndex.value : this.lapIndex,
      markedAtUs: data.markedAtUs.present
          ? data.markedAtUs.value
          : this.markedAtUs,
      lapTimeS: data.lapTimeS.present ? data.lapTimeS.value : this.lapTimeS,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Lap(')
          ..write('id: $id, ')
          ..write('runId: $runId, ')
          ..write('lapIndex: $lapIndex, ')
          ..write('markedAtUs: $markedAtUs, ')
          ..write('lapTimeS: $lapTimeS')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, runId, lapIndex, markedAtUs, lapTimeS);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Lap &&
          other.id == this.id &&
          other.runId == this.runId &&
          other.lapIndex == this.lapIndex &&
          other.markedAtUs == this.markedAtUs &&
          other.lapTimeS == this.lapTimeS);
}

class LapsCompanion extends UpdateCompanion<Lap> {
  final Value<int> id;
  final Value<int> runId;
  final Value<int> lapIndex;
  final Value<int> markedAtUs;
  final Value<double> lapTimeS;
  const LapsCompanion({
    this.id = const Value.absent(),
    this.runId = const Value.absent(),
    this.lapIndex = const Value.absent(),
    this.markedAtUs = const Value.absent(),
    this.lapTimeS = const Value.absent(),
  });
  LapsCompanion.insert({
    this.id = const Value.absent(),
    required int runId,
    required int lapIndex,
    required int markedAtUs,
    required double lapTimeS,
  }) : runId = Value(runId),
       lapIndex = Value(lapIndex),
       markedAtUs = Value(markedAtUs),
       lapTimeS = Value(lapTimeS);
  static Insertable<Lap> custom({
    Expression<int>? id,
    Expression<int>? runId,
    Expression<int>? lapIndex,
    Expression<int>? markedAtUs,
    Expression<double>? lapTimeS,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (runId != null) 'run_id': runId,
      if (lapIndex != null) 'lap_index': lapIndex,
      if (markedAtUs != null) 'marked_at_us': markedAtUs,
      if (lapTimeS != null) 'lap_time_s': lapTimeS,
    });
  }

  LapsCompanion copyWith({
    Value<int>? id,
    Value<int>? runId,
    Value<int>? lapIndex,
    Value<int>? markedAtUs,
    Value<double>? lapTimeS,
  }) {
    return LapsCompanion(
      id: id ?? this.id,
      runId: runId ?? this.runId,
      lapIndex: lapIndex ?? this.lapIndex,
      markedAtUs: markedAtUs ?? this.markedAtUs,
      lapTimeS: lapTimeS ?? this.lapTimeS,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (runId.present) {
      map['run_id'] = Variable<int>(runId.value);
    }
    if (lapIndex.present) {
      map['lap_index'] = Variable<int>(lapIndex.value);
    }
    if (markedAtUs.present) {
      map['marked_at_us'] = Variable<int>(markedAtUs.value);
    }
    if (lapTimeS.present) {
      map['lap_time_s'] = Variable<double>(lapTimeS.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LapsCompanion(')
          ..write('id: $id, ')
          ..write('runId: $runId, ')
          ..write('lapIndex: $lapIndex, ')
          ..write('markedAtUs: $markedAtUs, ')
          ..write('lapTimeS: $lapTimeS')
          ..write(')'))
        .toString();
  }
}

class RunGaps extends Table with TableInfo<RunGaps, RunGap> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  RunGaps(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL PRIMARY KEY AUTOINCREMENT',
  );
  static const VerificationMeta _runIdMeta = const VerificationMeta('runId');
  late final GeneratedColumn<int> runId = GeneratedColumn<int>(
    'run_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL REFERENCES runs(id)ON DELETE CASCADE',
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (kind IN (\'manual_pause\', \'position_loss\', \'heart_rate_loss\', \'interruption\'))',
  );
  static const VerificationMeta _startUsMeta = const VerificationMeta(
    'startUs',
  );
  late final GeneratedColumn<int> startUs = GeneratedColumn<int>(
    'start_us',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _endUsMeta = const VerificationMeta('endUs');
  late final GeneratedColumn<int> endUs = GeneratedColumn<int>(
    'end_us',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  @override
  List<GeneratedColumn> get $columns => [id, runId, kind, startUs, endUs];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'run_gaps';
  @override
  VerificationContext validateIntegrity(
    Insertable<RunGap> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('run_id')) {
      context.handle(
        _runIdMeta,
        runId.isAcceptableOrUnknown(data['run_id']!, _runIdMeta),
      );
    } else if (isInserting) {
      context.missing(_runIdMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('start_us')) {
      context.handle(
        _startUsMeta,
        startUs.isAcceptableOrUnknown(data['start_us']!, _startUsMeta),
      );
    } else if (isInserting) {
      context.missing(_startUsMeta);
    }
    if (data.containsKey('end_us')) {
      context.handle(
        _endUsMeta,
        endUs.isAcceptableOrUnknown(data['end_us']!, _endUsMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  RunGap map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RunGap(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      runId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}run_id'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      startUs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}start_us'],
      )!,
      endUs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}end_us'],
      ),
    );
  }

  @override
  RunGaps createAlias(String alias) {
    return RunGaps(attachedDatabase, alias);
  }

  @override
  bool get dontWriteConstraints => true;
}

class RunGap extends DataClass implements Insertable<RunGap> {
  final int id;
  final int runId;
  final String kind;
  final int startUs;
  final int? endUs;
  const RunGap({
    required this.id,
    required this.runId,
    required this.kind,
    required this.startUs,
    this.endUs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['run_id'] = Variable<int>(runId);
    map['kind'] = Variable<String>(kind);
    map['start_us'] = Variable<int>(startUs);
    if (!nullToAbsent || endUs != null) {
      map['end_us'] = Variable<int>(endUs);
    }
    return map;
  }

  RunGapsCompanion toCompanion(bool nullToAbsent) {
    return RunGapsCompanion(
      id: Value(id),
      runId: Value(runId),
      kind: Value(kind),
      startUs: Value(startUs),
      endUs: endUs == null && nullToAbsent
          ? const Value.absent()
          : Value(endUs),
    );
  }

  factory RunGap.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RunGap(
      id: serializer.fromJson<int>(json['id']),
      runId: serializer.fromJson<int>(json['run_id']),
      kind: serializer.fromJson<String>(json['kind']),
      startUs: serializer.fromJson<int>(json['start_us']),
      endUs: serializer.fromJson<int?>(json['end_us']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'run_id': serializer.toJson<int>(runId),
      'kind': serializer.toJson<String>(kind),
      'start_us': serializer.toJson<int>(startUs),
      'end_us': serializer.toJson<int?>(endUs),
    };
  }

  RunGap copyWith({
    int? id,
    int? runId,
    String? kind,
    int? startUs,
    Value<int?> endUs = const Value.absent(),
  }) => RunGap(
    id: id ?? this.id,
    runId: runId ?? this.runId,
    kind: kind ?? this.kind,
    startUs: startUs ?? this.startUs,
    endUs: endUs.present ? endUs.value : this.endUs,
  );
  RunGap copyWithCompanion(RunGapsCompanion data) {
    return RunGap(
      id: data.id.present ? data.id.value : this.id,
      runId: data.runId.present ? data.runId.value : this.runId,
      kind: data.kind.present ? data.kind.value : this.kind,
      startUs: data.startUs.present ? data.startUs.value : this.startUs,
      endUs: data.endUs.present ? data.endUs.value : this.endUs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RunGap(')
          ..write('id: $id, ')
          ..write('runId: $runId, ')
          ..write('kind: $kind, ')
          ..write('startUs: $startUs, ')
          ..write('endUs: $endUs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, runId, kind, startUs, endUs);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RunGap &&
          other.id == this.id &&
          other.runId == this.runId &&
          other.kind == this.kind &&
          other.startUs == this.startUs &&
          other.endUs == this.endUs);
}

class RunGapsCompanion extends UpdateCompanion<RunGap> {
  final Value<int> id;
  final Value<int> runId;
  final Value<String> kind;
  final Value<int> startUs;
  final Value<int?> endUs;
  const RunGapsCompanion({
    this.id = const Value.absent(),
    this.runId = const Value.absent(),
    this.kind = const Value.absent(),
    this.startUs = const Value.absent(),
    this.endUs = const Value.absent(),
  });
  RunGapsCompanion.insert({
    this.id = const Value.absent(),
    required int runId,
    required String kind,
    required int startUs,
    this.endUs = const Value.absent(),
  }) : runId = Value(runId),
       kind = Value(kind),
       startUs = Value(startUs);
  static Insertable<RunGap> custom({
    Expression<int>? id,
    Expression<int>? runId,
    Expression<String>? kind,
    Expression<int>? startUs,
    Expression<int>? endUs,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (runId != null) 'run_id': runId,
      if (kind != null) 'kind': kind,
      if (startUs != null) 'start_us': startUs,
      if (endUs != null) 'end_us': endUs,
    });
  }

  RunGapsCompanion copyWith({
    Value<int>? id,
    Value<int>? runId,
    Value<String>? kind,
    Value<int>? startUs,
    Value<int?>? endUs,
  }) {
    return RunGapsCompanion(
      id: id ?? this.id,
      runId: runId ?? this.runId,
      kind: kind ?? this.kind,
      startUs: startUs ?? this.startUs,
      endUs: endUs ?? this.endUs,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (runId.present) {
      map['run_id'] = Variable<int>(runId.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (startUs.present) {
      map['start_us'] = Variable<int>(startUs.value);
    }
    if (endUs.present) {
      map['end_us'] = Variable<int>(endUs.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RunGapsCompanion(')
          ..write('id: $id, ')
          ..write('runId: $runId, ')
          ..write('kind: $kind, ')
          ..write('startUs: $startUs, ')
          ..write('endUs: $endUs')
          ..write(')'))
        .toString();
  }
}

class RawPositions extends Table with TableInfo<RawPositions, RawPosition> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  RawPositions(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL PRIMARY KEY AUTOINCREMENT',
  );
  static const VerificationMeta _runIdMeta = const VerificationMeta('runId');
  late final GeneratedColumn<int> runId = GeneratedColumn<int>(
    'run_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL REFERENCES runs(id)ON DELETE CASCADE',
  );
  static const VerificationMeta _timeUsMeta = const VerificationMeta('timeUs');
  late final GeneratedColumn<int> timeUs = GeneratedColumn<int>(
    'time_us',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
    'source',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _stateMeta = const VerificationMeta('state');
  late final GeneratedColumn<String> state = GeneratedColumn<String>(
    'state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (state IN (\'present\', \'estimated\', \'unavailable\', \'discarded\'))',
  );
  static const VerificationMeta _latitudeDegMeta = const VerificationMeta(
    'latitudeDeg',
  );
  late final GeneratedColumn<double> latitudeDeg = GeneratedColumn<double>(
    'latitude_deg',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _longitudeDegMeta = const VerificationMeta(
    'longitudeDeg',
  );
  late final GeneratedColumn<double> longitudeDeg = GeneratedColumn<double>(
    'longitude_deg',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _accuracyMMeta = const VerificationMeta(
    'accuracyM',
  );
  late final GeneratedColumn<double> accuracyM = GeneratedColumn<double>(
    'accuracy_m',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _speedMpsMeta = const VerificationMeta(
    'speedMps',
  );
  late final GeneratedColumn<double> speedMps = GeneratedColumn<double>(
    'speed_mps',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _speedAccuracyMpsMeta = const VerificationMeta(
    'speedAccuracyMps',
  );
  late final GeneratedColumn<double> speedAccuracyMps = GeneratedColumn<double>(
    'speed_accuracy_mps',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _verticalAccuracyMMeta = const VerificationMeta(
    'verticalAccuracyM',
  );
  late final GeneratedColumn<double> verticalAccuracyM =
      GeneratedColumn<double>(
        'vertical_accuracy_m',
        aliasedName,
        true,
        type: DriftSqlType.double,
        requiredDuringInsert: false,
        $customConstraints: '',
      );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    runId,
    timeUs,
    source,
    state,
    latitudeDeg,
    longitudeDeg,
    accuracyM,
    speedMps,
    speedAccuracyMps,
    verticalAccuracyM,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'raw_positions';
  @override
  VerificationContext validateIntegrity(
    Insertable<RawPosition> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('run_id')) {
      context.handle(
        _runIdMeta,
        runId.isAcceptableOrUnknown(data['run_id']!, _runIdMeta),
      );
    } else if (isInserting) {
      context.missing(_runIdMeta);
    }
    if (data.containsKey('time_us')) {
      context.handle(
        _timeUsMeta,
        timeUs.isAcceptableOrUnknown(data['time_us']!, _timeUsMeta),
      );
    } else if (isInserting) {
      context.missing(_timeUsMeta);
    }
    if (data.containsKey('source')) {
      context.handle(
        _sourceMeta,
        source.isAcceptableOrUnknown(data['source']!, _sourceMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceMeta);
    }
    if (data.containsKey('state')) {
      context.handle(
        _stateMeta,
        state.isAcceptableOrUnknown(data['state']!, _stateMeta),
      );
    } else if (isInserting) {
      context.missing(_stateMeta);
    }
    if (data.containsKey('latitude_deg')) {
      context.handle(
        _latitudeDegMeta,
        latitudeDeg.isAcceptableOrUnknown(
          data['latitude_deg']!,
          _latitudeDegMeta,
        ),
      );
    }
    if (data.containsKey('longitude_deg')) {
      context.handle(
        _longitudeDegMeta,
        longitudeDeg.isAcceptableOrUnknown(
          data['longitude_deg']!,
          _longitudeDegMeta,
        ),
      );
    }
    if (data.containsKey('accuracy_m')) {
      context.handle(
        _accuracyMMeta,
        accuracyM.isAcceptableOrUnknown(data['accuracy_m']!, _accuracyMMeta),
      );
    }
    if (data.containsKey('speed_mps')) {
      context.handle(
        _speedMpsMeta,
        speedMps.isAcceptableOrUnknown(data['speed_mps']!, _speedMpsMeta),
      );
    }
    if (data.containsKey('speed_accuracy_mps')) {
      context.handle(
        _speedAccuracyMpsMeta,
        speedAccuracyMps.isAcceptableOrUnknown(
          data['speed_accuracy_mps']!,
          _speedAccuracyMpsMeta,
        ),
      );
    }
    if (data.containsKey('vertical_accuracy_m')) {
      context.handle(
        _verticalAccuracyMMeta,
        verticalAccuracyM.isAcceptableOrUnknown(
          data['vertical_accuracy_m']!,
          _verticalAccuracyMMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  RawPosition map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RawPosition(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      runId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}run_id'],
      )!,
      timeUs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}time_us'],
      )!,
      source: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source'],
      )!,
      state: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}state'],
      )!,
      latitudeDeg: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}latitude_deg'],
      ),
      longitudeDeg: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}longitude_deg'],
      ),
      accuracyM: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}accuracy_m'],
      ),
      speedMps: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}speed_mps'],
      ),
      speedAccuracyMps: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}speed_accuracy_mps'],
      ),
      verticalAccuracyM: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}vertical_accuracy_m'],
      ),
    );
  }

  @override
  RawPositions createAlias(String alias) {
    return RawPositions(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints => const [
    'CHECK(state = \'unavailable\' OR(latitude_deg IS NOT NULL AND longitude_deg IS NOT NULL))',
  ];
  @override
  bool get dontWriteConstraints => true;
}

class RawPosition extends DataClass implements Insertable<RawPosition> {
  final int id;
  final int runId;
  final int timeUs;
  final String source;
  final String state;
  final double? latitudeDeg;
  final double? longitudeDeg;
  final double? accuracyM;

  /// Ab Version 2 (WP06 C, K12): Rohwerte des Standortgebers, NULL = nicht
  /// geliefert (nie 0). Zeilen aus Version 1 haben NULL.
  final double? speedMps;
  final double? speedAccuracyMps;
  final double? verticalAccuracyM;
  const RawPosition({
    required this.id,
    required this.runId,
    required this.timeUs,
    required this.source,
    required this.state,
    this.latitudeDeg,
    this.longitudeDeg,
    this.accuracyM,
    this.speedMps,
    this.speedAccuracyMps,
    this.verticalAccuracyM,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['run_id'] = Variable<int>(runId);
    map['time_us'] = Variable<int>(timeUs);
    map['source'] = Variable<String>(source);
    map['state'] = Variable<String>(state);
    if (!nullToAbsent || latitudeDeg != null) {
      map['latitude_deg'] = Variable<double>(latitudeDeg);
    }
    if (!nullToAbsent || longitudeDeg != null) {
      map['longitude_deg'] = Variable<double>(longitudeDeg);
    }
    if (!nullToAbsent || accuracyM != null) {
      map['accuracy_m'] = Variable<double>(accuracyM);
    }
    if (!nullToAbsent || speedMps != null) {
      map['speed_mps'] = Variable<double>(speedMps);
    }
    if (!nullToAbsent || speedAccuracyMps != null) {
      map['speed_accuracy_mps'] = Variable<double>(speedAccuracyMps);
    }
    if (!nullToAbsent || verticalAccuracyM != null) {
      map['vertical_accuracy_m'] = Variable<double>(verticalAccuracyM);
    }
    return map;
  }

  RawPositionsCompanion toCompanion(bool nullToAbsent) {
    return RawPositionsCompanion(
      id: Value(id),
      runId: Value(runId),
      timeUs: Value(timeUs),
      source: Value(source),
      state: Value(state),
      latitudeDeg: latitudeDeg == null && nullToAbsent
          ? const Value.absent()
          : Value(latitudeDeg),
      longitudeDeg: longitudeDeg == null && nullToAbsent
          ? const Value.absent()
          : Value(longitudeDeg),
      accuracyM: accuracyM == null && nullToAbsent
          ? const Value.absent()
          : Value(accuracyM),
      speedMps: speedMps == null && nullToAbsent
          ? const Value.absent()
          : Value(speedMps),
      speedAccuracyMps: speedAccuracyMps == null && nullToAbsent
          ? const Value.absent()
          : Value(speedAccuracyMps),
      verticalAccuracyM: verticalAccuracyM == null && nullToAbsent
          ? const Value.absent()
          : Value(verticalAccuracyM),
    );
  }

  factory RawPosition.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RawPosition(
      id: serializer.fromJson<int>(json['id']),
      runId: serializer.fromJson<int>(json['run_id']),
      timeUs: serializer.fromJson<int>(json['time_us']),
      source: serializer.fromJson<String>(json['source']),
      state: serializer.fromJson<String>(json['state']),
      latitudeDeg: serializer.fromJson<double?>(json['latitude_deg']),
      longitudeDeg: serializer.fromJson<double?>(json['longitude_deg']),
      accuracyM: serializer.fromJson<double?>(json['accuracy_m']),
      speedMps: serializer.fromJson<double?>(json['speed_mps']),
      speedAccuracyMps: serializer.fromJson<double?>(
        json['speed_accuracy_mps'],
      ),
      verticalAccuracyM: serializer.fromJson<double?>(
        json['vertical_accuracy_m'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'run_id': serializer.toJson<int>(runId),
      'time_us': serializer.toJson<int>(timeUs),
      'source': serializer.toJson<String>(source),
      'state': serializer.toJson<String>(state),
      'latitude_deg': serializer.toJson<double?>(latitudeDeg),
      'longitude_deg': serializer.toJson<double?>(longitudeDeg),
      'accuracy_m': serializer.toJson<double?>(accuracyM),
      'speed_mps': serializer.toJson<double?>(speedMps),
      'speed_accuracy_mps': serializer.toJson<double?>(speedAccuracyMps),
      'vertical_accuracy_m': serializer.toJson<double?>(verticalAccuracyM),
    };
  }

  RawPosition copyWith({
    int? id,
    int? runId,
    int? timeUs,
    String? source,
    String? state,
    Value<double?> latitudeDeg = const Value.absent(),
    Value<double?> longitudeDeg = const Value.absent(),
    Value<double?> accuracyM = const Value.absent(),
    Value<double?> speedMps = const Value.absent(),
    Value<double?> speedAccuracyMps = const Value.absent(),
    Value<double?> verticalAccuracyM = const Value.absent(),
  }) => RawPosition(
    id: id ?? this.id,
    runId: runId ?? this.runId,
    timeUs: timeUs ?? this.timeUs,
    source: source ?? this.source,
    state: state ?? this.state,
    latitudeDeg: latitudeDeg.present ? latitudeDeg.value : this.latitudeDeg,
    longitudeDeg: longitudeDeg.present ? longitudeDeg.value : this.longitudeDeg,
    accuracyM: accuracyM.present ? accuracyM.value : this.accuracyM,
    speedMps: speedMps.present ? speedMps.value : this.speedMps,
    speedAccuracyMps: speedAccuracyMps.present
        ? speedAccuracyMps.value
        : this.speedAccuracyMps,
    verticalAccuracyM: verticalAccuracyM.present
        ? verticalAccuracyM.value
        : this.verticalAccuracyM,
  );
  RawPosition copyWithCompanion(RawPositionsCompanion data) {
    return RawPosition(
      id: data.id.present ? data.id.value : this.id,
      runId: data.runId.present ? data.runId.value : this.runId,
      timeUs: data.timeUs.present ? data.timeUs.value : this.timeUs,
      source: data.source.present ? data.source.value : this.source,
      state: data.state.present ? data.state.value : this.state,
      latitudeDeg: data.latitudeDeg.present
          ? data.latitudeDeg.value
          : this.latitudeDeg,
      longitudeDeg: data.longitudeDeg.present
          ? data.longitudeDeg.value
          : this.longitudeDeg,
      accuracyM: data.accuracyM.present ? data.accuracyM.value : this.accuracyM,
      speedMps: data.speedMps.present ? data.speedMps.value : this.speedMps,
      speedAccuracyMps: data.speedAccuracyMps.present
          ? data.speedAccuracyMps.value
          : this.speedAccuracyMps,
      verticalAccuracyM: data.verticalAccuracyM.present
          ? data.verticalAccuracyM.value
          : this.verticalAccuracyM,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RawPosition(')
          ..write('id: $id, ')
          ..write('runId: $runId, ')
          ..write('timeUs: $timeUs, ')
          ..write('source: $source, ')
          ..write('state: $state, ')
          ..write('latitudeDeg: $latitudeDeg, ')
          ..write('longitudeDeg: $longitudeDeg, ')
          ..write('accuracyM: $accuracyM, ')
          ..write('speedMps: $speedMps, ')
          ..write('speedAccuracyMps: $speedAccuracyMps, ')
          ..write('verticalAccuracyM: $verticalAccuracyM')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    runId,
    timeUs,
    source,
    state,
    latitudeDeg,
    longitudeDeg,
    accuracyM,
    speedMps,
    speedAccuracyMps,
    verticalAccuracyM,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RawPosition &&
          other.id == this.id &&
          other.runId == this.runId &&
          other.timeUs == this.timeUs &&
          other.source == this.source &&
          other.state == this.state &&
          other.latitudeDeg == this.latitudeDeg &&
          other.longitudeDeg == this.longitudeDeg &&
          other.accuracyM == this.accuracyM &&
          other.speedMps == this.speedMps &&
          other.speedAccuracyMps == this.speedAccuracyMps &&
          other.verticalAccuracyM == this.verticalAccuracyM);
}

class RawPositionsCompanion extends UpdateCompanion<RawPosition> {
  final Value<int> id;
  final Value<int> runId;
  final Value<int> timeUs;
  final Value<String> source;
  final Value<String> state;
  final Value<double?> latitudeDeg;
  final Value<double?> longitudeDeg;
  final Value<double?> accuracyM;
  final Value<double?> speedMps;
  final Value<double?> speedAccuracyMps;
  final Value<double?> verticalAccuracyM;
  const RawPositionsCompanion({
    this.id = const Value.absent(),
    this.runId = const Value.absent(),
    this.timeUs = const Value.absent(),
    this.source = const Value.absent(),
    this.state = const Value.absent(),
    this.latitudeDeg = const Value.absent(),
    this.longitudeDeg = const Value.absent(),
    this.accuracyM = const Value.absent(),
    this.speedMps = const Value.absent(),
    this.speedAccuracyMps = const Value.absent(),
    this.verticalAccuracyM = const Value.absent(),
  });
  RawPositionsCompanion.insert({
    this.id = const Value.absent(),
    required int runId,
    required int timeUs,
    required String source,
    required String state,
    this.latitudeDeg = const Value.absent(),
    this.longitudeDeg = const Value.absent(),
    this.accuracyM = const Value.absent(),
    this.speedMps = const Value.absent(),
    this.speedAccuracyMps = const Value.absent(),
    this.verticalAccuracyM = const Value.absent(),
  }) : runId = Value(runId),
       timeUs = Value(timeUs),
       source = Value(source),
       state = Value(state);
  static Insertable<RawPosition> custom({
    Expression<int>? id,
    Expression<int>? runId,
    Expression<int>? timeUs,
    Expression<String>? source,
    Expression<String>? state,
    Expression<double>? latitudeDeg,
    Expression<double>? longitudeDeg,
    Expression<double>? accuracyM,
    Expression<double>? speedMps,
    Expression<double>? speedAccuracyMps,
    Expression<double>? verticalAccuracyM,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (runId != null) 'run_id': runId,
      if (timeUs != null) 'time_us': timeUs,
      if (source != null) 'source': source,
      if (state != null) 'state': state,
      if (latitudeDeg != null) 'latitude_deg': latitudeDeg,
      if (longitudeDeg != null) 'longitude_deg': longitudeDeg,
      if (accuracyM != null) 'accuracy_m': accuracyM,
      if (speedMps != null) 'speed_mps': speedMps,
      if (speedAccuracyMps != null) 'speed_accuracy_mps': speedAccuracyMps,
      if (verticalAccuracyM != null) 'vertical_accuracy_m': verticalAccuracyM,
    });
  }

  RawPositionsCompanion copyWith({
    Value<int>? id,
    Value<int>? runId,
    Value<int>? timeUs,
    Value<String>? source,
    Value<String>? state,
    Value<double?>? latitudeDeg,
    Value<double?>? longitudeDeg,
    Value<double?>? accuracyM,
    Value<double?>? speedMps,
    Value<double?>? speedAccuracyMps,
    Value<double?>? verticalAccuracyM,
  }) {
    return RawPositionsCompanion(
      id: id ?? this.id,
      runId: runId ?? this.runId,
      timeUs: timeUs ?? this.timeUs,
      source: source ?? this.source,
      state: state ?? this.state,
      latitudeDeg: latitudeDeg ?? this.latitudeDeg,
      longitudeDeg: longitudeDeg ?? this.longitudeDeg,
      accuracyM: accuracyM ?? this.accuracyM,
      speedMps: speedMps ?? this.speedMps,
      speedAccuracyMps: speedAccuracyMps ?? this.speedAccuracyMps,
      verticalAccuracyM: verticalAccuracyM ?? this.verticalAccuracyM,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (runId.present) {
      map['run_id'] = Variable<int>(runId.value);
    }
    if (timeUs.present) {
      map['time_us'] = Variable<int>(timeUs.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(state.value);
    }
    if (latitudeDeg.present) {
      map['latitude_deg'] = Variable<double>(latitudeDeg.value);
    }
    if (longitudeDeg.present) {
      map['longitude_deg'] = Variable<double>(longitudeDeg.value);
    }
    if (accuracyM.present) {
      map['accuracy_m'] = Variable<double>(accuracyM.value);
    }
    if (speedMps.present) {
      map['speed_mps'] = Variable<double>(speedMps.value);
    }
    if (speedAccuracyMps.present) {
      map['speed_accuracy_mps'] = Variable<double>(speedAccuracyMps.value);
    }
    if (verticalAccuracyM.present) {
      map['vertical_accuracy_m'] = Variable<double>(verticalAccuracyM.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RawPositionsCompanion(')
          ..write('id: $id, ')
          ..write('runId: $runId, ')
          ..write('timeUs: $timeUs, ')
          ..write('source: $source, ')
          ..write('state: $state, ')
          ..write('latitudeDeg: $latitudeDeg, ')
          ..write('longitudeDeg: $longitudeDeg, ')
          ..write('accuracyM: $accuracyM, ')
          ..write('speedMps: $speedMps, ')
          ..write('speedAccuracyMps: $speedAccuracyMps, ')
          ..write('verticalAccuracyM: $verticalAccuracyM')
          ..write(')'))
        .toString();
  }
}

class RawHeartRates extends Table with TableInfo<RawHeartRates, RawHeartRate> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  RawHeartRates(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL PRIMARY KEY AUTOINCREMENT',
  );
  static const VerificationMeta _runIdMeta = const VerificationMeta('runId');
  late final GeneratedColumn<int> runId = GeneratedColumn<int>(
    'run_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL REFERENCES runs(id)ON DELETE CASCADE',
  );
  static const VerificationMeta _timeUsMeta = const VerificationMeta('timeUs');
  late final GeneratedColumn<int> timeUs = GeneratedColumn<int>(
    'time_us',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
    'source',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _stateMeta = const VerificationMeta('state');
  late final GeneratedColumn<String> state = GeneratedColumn<String>(
    'state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (state IN (\'present\', \'estimated\', \'unavailable\', \'discarded\'))',
  );
  static const VerificationMeta _bpmMeta = const VerificationMeta('bpm');
  late final GeneratedColumn<int> bpm = GeneratedColumn<int>(
    'bpm',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _contactMeta = const VerificationMeta(
    'contact',
  );
  late final GeneratedColumn<String> contact = GeneratedColumn<String>(
    'contact',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints:
        'NOT NULL CHECK (contact IN (\'good\', \'poor\', \'unsupported\'))',
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    runId,
    timeUs,
    source,
    state,
    bpm,
    contact,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'raw_heart_rates';
  @override
  VerificationContext validateIntegrity(
    Insertable<RawHeartRate> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('run_id')) {
      context.handle(
        _runIdMeta,
        runId.isAcceptableOrUnknown(data['run_id']!, _runIdMeta),
      );
    } else if (isInserting) {
      context.missing(_runIdMeta);
    }
    if (data.containsKey('time_us')) {
      context.handle(
        _timeUsMeta,
        timeUs.isAcceptableOrUnknown(data['time_us']!, _timeUsMeta),
      );
    } else if (isInserting) {
      context.missing(_timeUsMeta);
    }
    if (data.containsKey('source')) {
      context.handle(
        _sourceMeta,
        source.isAcceptableOrUnknown(data['source']!, _sourceMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceMeta);
    }
    if (data.containsKey('state')) {
      context.handle(
        _stateMeta,
        state.isAcceptableOrUnknown(data['state']!, _stateMeta),
      );
    } else if (isInserting) {
      context.missing(_stateMeta);
    }
    if (data.containsKey('bpm')) {
      context.handle(
        _bpmMeta,
        bpm.isAcceptableOrUnknown(data['bpm']!, _bpmMeta),
      );
    }
    if (data.containsKey('contact')) {
      context.handle(
        _contactMeta,
        contact.isAcceptableOrUnknown(data['contact']!, _contactMeta),
      );
    } else if (isInserting) {
      context.missing(_contactMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  RawHeartRate map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RawHeartRate(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      runId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}run_id'],
      )!,
      timeUs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}time_us'],
      )!,
      source: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source'],
      )!,
      state: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}state'],
      )!,
      bpm: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}bpm'],
      ),
      contact: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}contact'],
      )!,
    );
  }

  @override
  RawHeartRates createAlias(String alias) {
    return RawHeartRates(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints => const [
    'CHECK(state = \'unavailable\' OR bpm IS NOT NULL)',
  ];
  @override
  bool get dontWriteConstraints => true;
}

class RawHeartRate extends DataClass implements Insertable<RawHeartRate> {
  final int id;
  final int runId;
  final int timeUs;
  final String source;
  final String state;
  final int? bpm;
  final String contact;
  const RawHeartRate({
    required this.id,
    required this.runId,
    required this.timeUs,
    required this.source,
    required this.state,
    this.bpm,
    required this.contact,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['run_id'] = Variable<int>(runId);
    map['time_us'] = Variable<int>(timeUs);
    map['source'] = Variable<String>(source);
    map['state'] = Variable<String>(state);
    if (!nullToAbsent || bpm != null) {
      map['bpm'] = Variable<int>(bpm);
    }
    map['contact'] = Variable<String>(contact);
    return map;
  }

  RawHeartRatesCompanion toCompanion(bool nullToAbsent) {
    return RawHeartRatesCompanion(
      id: Value(id),
      runId: Value(runId),
      timeUs: Value(timeUs),
      source: Value(source),
      state: Value(state),
      bpm: bpm == null && nullToAbsent ? const Value.absent() : Value(bpm),
      contact: Value(contact),
    );
  }

  factory RawHeartRate.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RawHeartRate(
      id: serializer.fromJson<int>(json['id']),
      runId: serializer.fromJson<int>(json['run_id']),
      timeUs: serializer.fromJson<int>(json['time_us']),
      source: serializer.fromJson<String>(json['source']),
      state: serializer.fromJson<String>(json['state']),
      bpm: serializer.fromJson<int?>(json['bpm']),
      contact: serializer.fromJson<String>(json['contact']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'run_id': serializer.toJson<int>(runId),
      'time_us': serializer.toJson<int>(timeUs),
      'source': serializer.toJson<String>(source),
      'state': serializer.toJson<String>(state),
      'bpm': serializer.toJson<int?>(bpm),
      'contact': serializer.toJson<String>(contact),
    };
  }

  RawHeartRate copyWith({
    int? id,
    int? runId,
    int? timeUs,
    String? source,
    String? state,
    Value<int?> bpm = const Value.absent(),
    String? contact,
  }) => RawHeartRate(
    id: id ?? this.id,
    runId: runId ?? this.runId,
    timeUs: timeUs ?? this.timeUs,
    source: source ?? this.source,
    state: state ?? this.state,
    bpm: bpm.present ? bpm.value : this.bpm,
    contact: contact ?? this.contact,
  );
  RawHeartRate copyWithCompanion(RawHeartRatesCompanion data) {
    return RawHeartRate(
      id: data.id.present ? data.id.value : this.id,
      runId: data.runId.present ? data.runId.value : this.runId,
      timeUs: data.timeUs.present ? data.timeUs.value : this.timeUs,
      source: data.source.present ? data.source.value : this.source,
      state: data.state.present ? data.state.value : this.state,
      bpm: data.bpm.present ? data.bpm.value : this.bpm,
      contact: data.contact.present ? data.contact.value : this.contact,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RawHeartRate(')
          ..write('id: $id, ')
          ..write('runId: $runId, ')
          ..write('timeUs: $timeUs, ')
          ..write('source: $source, ')
          ..write('state: $state, ')
          ..write('bpm: $bpm, ')
          ..write('contact: $contact')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, runId, timeUs, source, state, bpm, contact);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RawHeartRate &&
          other.id == this.id &&
          other.runId == this.runId &&
          other.timeUs == this.timeUs &&
          other.source == this.source &&
          other.state == this.state &&
          other.bpm == this.bpm &&
          other.contact == this.contact);
}

class RawHeartRatesCompanion extends UpdateCompanion<RawHeartRate> {
  final Value<int> id;
  final Value<int> runId;
  final Value<int> timeUs;
  final Value<String> source;
  final Value<String> state;
  final Value<int?> bpm;
  final Value<String> contact;
  const RawHeartRatesCompanion({
    this.id = const Value.absent(),
    this.runId = const Value.absent(),
    this.timeUs = const Value.absent(),
    this.source = const Value.absent(),
    this.state = const Value.absent(),
    this.bpm = const Value.absent(),
    this.contact = const Value.absent(),
  });
  RawHeartRatesCompanion.insert({
    this.id = const Value.absent(),
    required int runId,
    required int timeUs,
    required String source,
    required String state,
    this.bpm = const Value.absent(),
    required String contact,
  }) : runId = Value(runId),
       timeUs = Value(timeUs),
       source = Value(source),
       state = Value(state),
       contact = Value(contact);
  static Insertable<RawHeartRate> custom({
    Expression<int>? id,
    Expression<int>? runId,
    Expression<int>? timeUs,
    Expression<String>? source,
    Expression<String>? state,
    Expression<int>? bpm,
    Expression<String>? contact,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (runId != null) 'run_id': runId,
      if (timeUs != null) 'time_us': timeUs,
      if (source != null) 'source': source,
      if (state != null) 'state': state,
      if (bpm != null) 'bpm': bpm,
      if (contact != null) 'contact': contact,
    });
  }

  RawHeartRatesCompanion copyWith({
    Value<int>? id,
    Value<int>? runId,
    Value<int>? timeUs,
    Value<String>? source,
    Value<String>? state,
    Value<int?>? bpm,
    Value<String>? contact,
  }) {
    return RawHeartRatesCompanion(
      id: id ?? this.id,
      runId: runId ?? this.runId,
      timeUs: timeUs ?? this.timeUs,
      source: source ?? this.source,
      state: state ?? this.state,
      bpm: bpm ?? this.bpm,
      contact: contact ?? this.contact,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (runId.present) {
      map['run_id'] = Variable<int>(runId.value);
    }
    if (timeUs.present) {
      map['time_us'] = Variable<int>(timeUs.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(state.value);
    }
    if (bpm.present) {
      map['bpm'] = Variable<int>(bpm.value);
    }
    if (contact.present) {
      map['contact'] = Variable<String>(contact.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RawHeartRatesCompanion(')
          ..write('id: $id, ')
          ..write('runId: $runId, ')
          ..write('timeUs: $timeUs, ')
          ..write('source: $source, ')
          ..write('state: $state, ')
          ..write('bpm: $bpm, ')
          ..write('contact: $contact')
          ..write(')'))
        .toString();
  }
}

class RawAltitudes extends Table with TableInfo<RawAltitudes, RawAltitude> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  RawAltitudes(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL PRIMARY KEY AUTOINCREMENT',
  );
  static const VerificationMeta _runIdMeta = const VerificationMeta('runId');
  late final GeneratedColumn<int> runId = GeneratedColumn<int>(
    'run_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL REFERENCES runs(id)ON DELETE CASCADE',
  );
  static const VerificationMeta _timeUsMeta = const VerificationMeta('timeUs');
  late final GeneratedColumn<int> timeUs = GeneratedColumn<int>(
    'time_us',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
    'source',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _stateMeta = const VerificationMeta('state');
  late final GeneratedColumn<String> state = GeneratedColumn<String>(
    'state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (state IN (\'present\', \'estimated\', \'unavailable\', \'discarded\'))',
  );
  static const VerificationMeta _altitudeMMeta = const VerificationMeta(
    'altitudeM',
  );
  late final GeneratedColumn<double> altitudeM = GeneratedColumn<double>(
    'altitude_m',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _verticalAccuracyMMeta = const VerificationMeta(
    'verticalAccuracyM',
  );
  late final GeneratedColumn<double> verticalAccuracyM =
      GeneratedColumn<double>(
        'vertical_accuracy_m',
        aliasedName,
        true,
        type: DriftSqlType.double,
        requiredDuringInsert: false,
        $customConstraints: '',
      );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    runId,
    timeUs,
    source,
    state,
    altitudeM,
    verticalAccuracyM,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'raw_altitudes';
  @override
  VerificationContext validateIntegrity(
    Insertable<RawAltitude> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('run_id')) {
      context.handle(
        _runIdMeta,
        runId.isAcceptableOrUnknown(data['run_id']!, _runIdMeta),
      );
    } else if (isInserting) {
      context.missing(_runIdMeta);
    }
    if (data.containsKey('time_us')) {
      context.handle(
        _timeUsMeta,
        timeUs.isAcceptableOrUnknown(data['time_us']!, _timeUsMeta),
      );
    } else if (isInserting) {
      context.missing(_timeUsMeta);
    }
    if (data.containsKey('source')) {
      context.handle(
        _sourceMeta,
        source.isAcceptableOrUnknown(data['source']!, _sourceMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceMeta);
    }
    if (data.containsKey('state')) {
      context.handle(
        _stateMeta,
        state.isAcceptableOrUnknown(data['state']!, _stateMeta),
      );
    } else if (isInserting) {
      context.missing(_stateMeta);
    }
    if (data.containsKey('altitude_m')) {
      context.handle(
        _altitudeMMeta,
        altitudeM.isAcceptableOrUnknown(data['altitude_m']!, _altitudeMMeta),
      );
    }
    if (data.containsKey('vertical_accuracy_m')) {
      context.handle(
        _verticalAccuracyMMeta,
        verticalAccuracyM.isAcceptableOrUnknown(
          data['vertical_accuracy_m']!,
          _verticalAccuracyMMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  RawAltitude map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RawAltitude(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      runId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}run_id'],
      )!,
      timeUs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}time_us'],
      )!,
      source: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source'],
      )!,
      state: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}state'],
      )!,
      altitudeM: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}altitude_m'],
      ),
      verticalAccuracyM: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}vertical_accuracy_m'],
      ),
    );
  }

  @override
  RawAltitudes createAlias(String alias) {
    return RawAltitudes(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints => const [
    'CHECK(state = \'unavailable\' OR altitude_m IS NOT NULL)',
  ];
  @override
  bool get dontWriteConstraints => true;
}

class RawAltitude extends DataClass implements Insertable<RawAltitude> {
  final int id;
  final int runId;
  final int timeUs;
  final String source;
  final String state;
  final double? altitudeM;
  final double? verticalAccuracyM;
  const RawAltitude({
    required this.id,
    required this.runId,
    required this.timeUs,
    required this.source,
    required this.state,
    this.altitudeM,
    this.verticalAccuracyM,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['run_id'] = Variable<int>(runId);
    map['time_us'] = Variable<int>(timeUs);
    map['source'] = Variable<String>(source);
    map['state'] = Variable<String>(state);
    if (!nullToAbsent || altitudeM != null) {
      map['altitude_m'] = Variable<double>(altitudeM);
    }
    if (!nullToAbsent || verticalAccuracyM != null) {
      map['vertical_accuracy_m'] = Variable<double>(verticalAccuracyM);
    }
    return map;
  }

  RawAltitudesCompanion toCompanion(bool nullToAbsent) {
    return RawAltitudesCompanion(
      id: Value(id),
      runId: Value(runId),
      timeUs: Value(timeUs),
      source: Value(source),
      state: Value(state),
      altitudeM: altitudeM == null && nullToAbsent
          ? const Value.absent()
          : Value(altitudeM),
      verticalAccuracyM: verticalAccuracyM == null && nullToAbsent
          ? const Value.absent()
          : Value(verticalAccuracyM),
    );
  }

  factory RawAltitude.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RawAltitude(
      id: serializer.fromJson<int>(json['id']),
      runId: serializer.fromJson<int>(json['run_id']),
      timeUs: serializer.fromJson<int>(json['time_us']),
      source: serializer.fromJson<String>(json['source']),
      state: serializer.fromJson<String>(json['state']),
      altitudeM: serializer.fromJson<double?>(json['altitude_m']),
      verticalAccuracyM: serializer.fromJson<double?>(
        json['vertical_accuracy_m'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'run_id': serializer.toJson<int>(runId),
      'time_us': serializer.toJson<int>(timeUs),
      'source': serializer.toJson<String>(source),
      'state': serializer.toJson<String>(state),
      'altitude_m': serializer.toJson<double?>(altitudeM),
      'vertical_accuracy_m': serializer.toJson<double?>(verticalAccuracyM),
    };
  }

  RawAltitude copyWith({
    int? id,
    int? runId,
    int? timeUs,
    String? source,
    String? state,
    Value<double?> altitudeM = const Value.absent(),
    Value<double?> verticalAccuracyM = const Value.absent(),
  }) => RawAltitude(
    id: id ?? this.id,
    runId: runId ?? this.runId,
    timeUs: timeUs ?? this.timeUs,
    source: source ?? this.source,
    state: state ?? this.state,
    altitudeM: altitudeM.present ? altitudeM.value : this.altitudeM,
    verticalAccuracyM: verticalAccuracyM.present
        ? verticalAccuracyM.value
        : this.verticalAccuracyM,
  );
  RawAltitude copyWithCompanion(RawAltitudesCompanion data) {
    return RawAltitude(
      id: data.id.present ? data.id.value : this.id,
      runId: data.runId.present ? data.runId.value : this.runId,
      timeUs: data.timeUs.present ? data.timeUs.value : this.timeUs,
      source: data.source.present ? data.source.value : this.source,
      state: data.state.present ? data.state.value : this.state,
      altitudeM: data.altitudeM.present ? data.altitudeM.value : this.altitudeM,
      verticalAccuracyM: data.verticalAccuracyM.present
          ? data.verticalAccuracyM.value
          : this.verticalAccuracyM,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RawAltitude(')
          ..write('id: $id, ')
          ..write('runId: $runId, ')
          ..write('timeUs: $timeUs, ')
          ..write('source: $source, ')
          ..write('state: $state, ')
          ..write('altitudeM: $altitudeM, ')
          ..write('verticalAccuracyM: $verticalAccuracyM')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    runId,
    timeUs,
    source,
    state,
    altitudeM,
    verticalAccuracyM,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RawAltitude &&
          other.id == this.id &&
          other.runId == this.runId &&
          other.timeUs == this.timeUs &&
          other.source == this.source &&
          other.state == this.state &&
          other.altitudeM == this.altitudeM &&
          other.verticalAccuracyM == this.verticalAccuracyM);
}

class RawAltitudesCompanion extends UpdateCompanion<RawAltitude> {
  final Value<int> id;
  final Value<int> runId;
  final Value<int> timeUs;
  final Value<String> source;
  final Value<String> state;
  final Value<double?> altitudeM;
  final Value<double?> verticalAccuracyM;
  const RawAltitudesCompanion({
    this.id = const Value.absent(),
    this.runId = const Value.absent(),
    this.timeUs = const Value.absent(),
    this.source = const Value.absent(),
    this.state = const Value.absent(),
    this.altitudeM = const Value.absent(),
    this.verticalAccuracyM = const Value.absent(),
  });
  RawAltitudesCompanion.insert({
    this.id = const Value.absent(),
    required int runId,
    required int timeUs,
    required String source,
    required String state,
    this.altitudeM = const Value.absent(),
    this.verticalAccuracyM = const Value.absent(),
  }) : runId = Value(runId),
       timeUs = Value(timeUs),
       source = Value(source),
       state = Value(state);
  static Insertable<RawAltitude> custom({
    Expression<int>? id,
    Expression<int>? runId,
    Expression<int>? timeUs,
    Expression<String>? source,
    Expression<String>? state,
    Expression<double>? altitudeM,
    Expression<double>? verticalAccuracyM,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (runId != null) 'run_id': runId,
      if (timeUs != null) 'time_us': timeUs,
      if (source != null) 'source': source,
      if (state != null) 'state': state,
      if (altitudeM != null) 'altitude_m': altitudeM,
      if (verticalAccuracyM != null) 'vertical_accuracy_m': verticalAccuracyM,
    });
  }

  RawAltitudesCompanion copyWith({
    Value<int>? id,
    Value<int>? runId,
    Value<int>? timeUs,
    Value<String>? source,
    Value<String>? state,
    Value<double?>? altitudeM,
    Value<double?>? verticalAccuracyM,
  }) {
    return RawAltitudesCompanion(
      id: id ?? this.id,
      runId: runId ?? this.runId,
      timeUs: timeUs ?? this.timeUs,
      source: source ?? this.source,
      state: state ?? this.state,
      altitudeM: altitudeM ?? this.altitudeM,
      verticalAccuracyM: verticalAccuracyM ?? this.verticalAccuracyM,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (runId.present) {
      map['run_id'] = Variable<int>(runId.value);
    }
    if (timeUs.present) {
      map['time_us'] = Variable<int>(timeUs.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(state.value);
    }
    if (altitudeM.present) {
      map['altitude_m'] = Variable<double>(altitudeM.value);
    }
    if (verticalAccuracyM.present) {
      map['vertical_accuracy_m'] = Variable<double>(verticalAccuracyM.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RawAltitudesCompanion(')
          ..write('id: $id, ')
          ..write('runId: $runId, ')
          ..write('timeUs: $timeUs, ')
          ..write('source: $source, ')
          ..write('state: $state, ')
          ..write('altitudeM: $altitudeM, ')
          ..write('verticalAccuracyM: $verticalAccuracyM')
          ..write(')'))
        .toString();
  }
}

class RawSteps extends Table with TableInfo<RawSteps, RawStep> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  RawSteps(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL PRIMARY KEY AUTOINCREMENT',
  );
  static const VerificationMeta _runIdMeta = const VerificationMeta('runId');
  late final GeneratedColumn<int> runId = GeneratedColumn<int>(
    'run_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL REFERENCES runs(id)ON DELETE CASCADE',
  );
  static const VerificationMeta _timeUsMeta = const VerificationMeta('timeUs');
  late final GeneratedColumn<int> timeUs = GeneratedColumn<int>(
    'time_us',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
    'source',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _stateMeta = const VerificationMeta('state');
  late final GeneratedColumn<String> state = GeneratedColumn<String>(
    'state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (state IN (\'present\', \'estimated\', \'unavailable\', \'discarded\'))',
  );
  static const VerificationMeta _stepCountMeta = const VerificationMeta(
    'stepCount',
  );
  late final GeneratedColumn<int> stepCount = GeneratedColumn<int>(
    'step_count',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    runId,
    timeUs,
    source,
    state,
    stepCount,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'raw_steps';
  @override
  VerificationContext validateIntegrity(
    Insertable<RawStep> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('run_id')) {
      context.handle(
        _runIdMeta,
        runId.isAcceptableOrUnknown(data['run_id']!, _runIdMeta),
      );
    } else if (isInserting) {
      context.missing(_runIdMeta);
    }
    if (data.containsKey('time_us')) {
      context.handle(
        _timeUsMeta,
        timeUs.isAcceptableOrUnknown(data['time_us']!, _timeUsMeta),
      );
    } else if (isInserting) {
      context.missing(_timeUsMeta);
    }
    if (data.containsKey('source')) {
      context.handle(
        _sourceMeta,
        source.isAcceptableOrUnknown(data['source']!, _sourceMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceMeta);
    }
    if (data.containsKey('state')) {
      context.handle(
        _stateMeta,
        state.isAcceptableOrUnknown(data['state']!, _stateMeta),
      );
    } else if (isInserting) {
      context.missing(_stateMeta);
    }
    if (data.containsKey('step_count')) {
      context.handle(
        _stepCountMeta,
        stepCount.isAcceptableOrUnknown(data['step_count']!, _stepCountMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  RawStep map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RawStep(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      runId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}run_id'],
      )!,
      timeUs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}time_us'],
      )!,
      source: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source'],
      )!,
      state: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}state'],
      )!,
      stepCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}step_count'],
      ),
    );
  }

  @override
  RawSteps createAlias(String alias) {
    return RawSteps(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints => const [
    'CHECK(state = \'unavailable\' OR step_count IS NOT NULL)',
  ];
  @override
  bool get dontWriteConstraints => true;
}

class RawStep extends DataClass implements Insertable<RawStep> {
  final int id;
  final int runId;
  final int timeUs;
  final String source;
  final String state;
  final int? stepCount;
  const RawStep({
    required this.id,
    required this.runId,
    required this.timeUs,
    required this.source,
    required this.state,
    this.stepCount,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['run_id'] = Variable<int>(runId);
    map['time_us'] = Variable<int>(timeUs);
    map['source'] = Variable<String>(source);
    map['state'] = Variable<String>(state);
    if (!nullToAbsent || stepCount != null) {
      map['step_count'] = Variable<int>(stepCount);
    }
    return map;
  }

  RawStepsCompanion toCompanion(bool nullToAbsent) {
    return RawStepsCompanion(
      id: Value(id),
      runId: Value(runId),
      timeUs: Value(timeUs),
      source: Value(source),
      state: Value(state),
      stepCount: stepCount == null && nullToAbsent
          ? const Value.absent()
          : Value(stepCount),
    );
  }

  factory RawStep.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RawStep(
      id: serializer.fromJson<int>(json['id']),
      runId: serializer.fromJson<int>(json['run_id']),
      timeUs: serializer.fromJson<int>(json['time_us']),
      source: serializer.fromJson<String>(json['source']),
      state: serializer.fromJson<String>(json['state']),
      stepCount: serializer.fromJson<int?>(json['step_count']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'run_id': serializer.toJson<int>(runId),
      'time_us': serializer.toJson<int>(timeUs),
      'source': serializer.toJson<String>(source),
      'state': serializer.toJson<String>(state),
      'step_count': serializer.toJson<int?>(stepCount),
    };
  }

  RawStep copyWith({
    int? id,
    int? runId,
    int? timeUs,
    String? source,
    String? state,
    Value<int?> stepCount = const Value.absent(),
  }) => RawStep(
    id: id ?? this.id,
    runId: runId ?? this.runId,
    timeUs: timeUs ?? this.timeUs,
    source: source ?? this.source,
    state: state ?? this.state,
    stepCount: stepCount.present ? stepCount.value : this.stepCount,
  );
  RawStep copyWithCompanion(RawStepsCompanion data) {
    return RawStep(
      id: data.id.present ? data.id.value : this.id,
      runId: data.runId.present ? data.runId.value : this.runId,
      timeUs: data.timeUs.present ? data.timeUs.value : this.timeUs,
      source: data.source.present ? data.source.value : this.source,
      state: data.state.present ? data.state.value : this.state,
      stepCount: data.stepCount.present ? data.stepCount.value : this.stepCount,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RawStep(')
          ..write('id: $id, ')
          ..write('runId: $runId, ')
          ..write('timeUs: $timeUs, ')
          ..write('source: $source, ')
          ..write('state: $state, ')
          ..write('stepCount: $stepCount')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, runId, timeUs, source, state, stepCount);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RawStep &&
          other.id == this.id &&
          other.runId == this.runId &&
          other.timeUs == this.timeUs &&
          other.source == this.source &&
          other.state == this.state &&
          other.stepCount == this.stepCount);
}

class RawStepsCompanion extends UpdateCompanion<RawStep> {
  final Value<int> id;
  final Value<int> runId;
  final Value<int> timeUs;
  final Value<String> source;
  final Value<String> state;
  final Value<int?> stepCount;
  const RawStepsCompanion({
    this.id = const Value.absent(),
    this.runId = const Value.absent(),
    this.timeUs = const Value.absent(),
    this.source = const Value.absent(),
    this.state = const Value.absent(),
    this.stepCount = const Value.absent(),
  });
  RawStepsCompanion.insert({
    this.id = const Value.absent(),
    required int runId,
    required int timeUs,
    required String source,
    required String state,
    this.stepCount = const Value.absent(),
  }) : runId = Value(runId),
       timeUs = Value(timeUs),
       source = Value(source),
       state = Value(state);
  static Insertable<RawStep> custom({
    Expression<int>? id,
    Expression<int>? runId,
    Expression<int>? timeUs,
    Expression<String>? source,
    Expression<String>? state,
    Expression<int>? stepCount,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (runId != null) 'run_id': runId,
      if (timeUs != null) 'time_us': timeUs,
      if (source != null) 'source': source,
      if (state != null) 'state': state,
      if (stepCount != null) 'step_count': stepCount,
    });
  }

  RawStepsCompanion copyWith({
    Value<int>? id,
    Value<int>? runId,
    Value<int>? timeUs,
    Value<String>? source,
    Value<String>? state,
    Value<int?>? stepCount,
  }) {
    return RawStepsCompanion(
      id: id ?? this.id,
      runId: runId ?? this.runId,
      timeUs: timeUs ?? this.timeUs,
      source: source ?? this.source,
      state: state ?? this.state,
      stepCount: stepCount ?? this.stepCount,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (runId.present) {
      map['run_id'] = Variable<int>(runId.value);
    }
    if (timeUs.present) {
      map['time_us'] = Variable<int>(timeUs.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(state.value);
    }
    if (stepCount.present) {
      map['step_count'] = Variable<int>(stepCount.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RawStepsCompanion(')
          ..write('id: $id, ')
          ..write('runId: $runId, ')
          ..write('timeUs: $timeUs, ')
          ..write('source: $source, ')
          ..write('state: $state, ')
          ..write('stepCount: $stepCount')
          ..write(')'))
        .toString();
  }
}

class PreprocessingResults extends Table
    with TableInfo<PreprocessingResults, PreprocessingResult> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  PreprocessingResults(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL PRIMARY KEY AUTOINCREMENT',
  );
  static const VerificationMeta _runIdMeta = const VerificationMeta('runId');
  late final GeneratedColumn<int> runId = GeneratedColumn<int>(
    'run_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL UNIQUE REFERENCES runs(id)ON DELETE CASCADE',
  );
  static const VerificationMeta _methodMeta = const VerificationMeta('method');
  late final GeneratedColumn<String> method = GeneratedColumn<String>(
    'method',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _methodVersionMeta = const VerificationMeta(
    'methodVersion',
  );
  late final GeneratedColumn<int> methodVersion = GeneratedColumn<int>(
    'method_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _parameterVersionMeta = const VerificationMeta(
    'parameterVersion',
  );
  late final GeneratedColumn<int> parameterVersion = GeneratedColumn<int>(
    'parameter_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _computedAtUsMeta = const VerificationMeta(
    'computedAtUs',
  );
  late final GeneratedColumn<int> computedAtUs = GeneratedColumn<int>(
    'computed_at_us',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _totalTimeSMeta = const VerificationMeta(
    'totalTimeS',
  );
  late final GeneratedColumn<double> totalTimeS = GeneratedColumn<double>(
    'total_time_s',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _movingTimeSMeta = const VerificationMeta(
    'movingTimeS',
  );
  late final GeneratedColumn<double> movingTimeS = GeneratedColumn<double>(
    'moving_time_s',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _distanceMMeta = const VerificationMeta(
    'distanceM',
  );
  late final GeneratedColumn<double> distanceM = GeneratedColumn<double>(
    'distance_m',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _bridgedDistanceMMeta = const VerificationMeta(
    'bridgedDistanceM',
  );
  late final GeneratedColumn<double> bridgedDistanceM = GeneratedColumn<double>(
    'bridged_distance_m',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _averageBpmMeta = const VerificationMeta(
    'averageBpm',
  );
  late final GeneratedColumn<double> averageBpm = GeneratedColumn<double>(
    'average_bpm',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _maxBpmMeta = const VerificationMeta('maxBpm');
  late final GeneratedColumn<int> maxBpm = GeneratedColumn<int>(
    'max_bpm',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _medianBpmMeta = const VerificationMeta(
    'medianBpm',
  );
  late final GeneratedColumn<double> medianBpm = GeneratedColumn<double>(
    'median_bpm',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _bestPaceSPerKmMeta = const VerificationMeta(
    'bestPaceSPerKm',
  );
  late final GeneratedColumn<double> bestPaceSPerKm = GeneratedColumn<double>(
    'best_pace_s_per_km',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _lapCountMeta = const VerificationMeta(
    'lapCount',
  );
  late final GeneratedColumn<int> lapCount = GeneratedColumn<int>(
    'lap_count',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _heartRateTimeSMeta = const VerificationMeta(
    'heartRateTimeS',
  );
  late final GeneratedColumn<double> heartRateTimeS = GeneratedColumn<double>(
    'heart_rate_time_s',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    runId,
    method,
    methodVersion,
    parameterVersion,
    computedAtUs,
    totalTimeS,
    movingTimeS,
    distanceM,
    bridgedDistanceM,
    averageBpm,
    maxBpm,
    medianBpm,
    bestPaceSPerKm,
    lapCount,
    heartRateTimeS,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'preprocessing_results';
  @override
  VerificationContext validateIntegrity(
    Insertable<PreprocessingResult> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('run_id')) {
      context.handle(
        _runIdMeta,
        runId.isAcceptableOrUnknown(data['run_id']!, _runIdMeta),
      );
    } else if (isInserting) {
      context.missing(_runIdMeta);
    }
    if (data.containsKey('method')) {
      context.handle(
        _methodMeta,
        method.isAcceptableOrUnknown(data['method']!, _methodMeta),
      );
    } else if (isInserting) {
      context.missing(_methodMeta);
    }
    if (data.containsKey('method_version')) {
      context.handle(
        _methodVersionMeta,
        methodVersion.isAcceptableOrUnknown(
          data['method_version']!,
          _methodVersionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_methodVersionMeta);
    }
    if (data.containsKey('parameter_version')) {
      context.handle(
        _parameterVersionMeta,
        parameterVersion.isAcceptableOrUnknown(
          data['parameter_version']!,
          _parameterVersionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_parameterVersionMeta);
    }
    if (data.containsKey('computed_at_us')) {
      context.handle(
        _computedAtUsMeta,
        computedAtUs.isAcceptableOrUnknown(
          data['computed_at_us']!,
          _computedAtUsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_computedAtUsMeta);
    }
    if (data.containsKey('total_time_s')) {
      context.handle(
        _totalTimeSMeta,
        totalTimeS.isAcceptableOrUnknown(
          data['total_time_s']!,
          _totalTimeSMeta,
        ),
      );
    }
    if (data.containsKey('moving_time_s')) {
      context.handle(
        _movingTimeSMeta,
        movingTimeS.isAcceptableOrUnknown(
          data['moving_time_s']!,
          _movingTimeSMeta,
        ),
      );
    }
    if (data.containsKey('distance_m')) {
      context.handle(
        _distanceMMeta,
        distanceM.isAcceptableOrUnknown(data['distance_m']!, _distanceMMeta),
      );
    }
    if (data.containsKey('bridged_distance_m')) {
      context.handle(
        _bridgedDistanceMMeta,
        bridgedDistanceM.isAcceptableOrUnknown(
          data['bridged_distance_m']!,
          _bridgedDistanceMMeta,
        ),
      );
    }
    if (data.containsKey('average_bpm')) {
      context.handle(
        _averageBpmMeta,
        averageBpm.isAcceptableOrUnknown(data['average_bpm']!, _averageBpmMeta),
      );
    }
    if (data.containsKey('max_bpm')) {
      context.handle(
        _maxBpmMeta,
        maxBpm.isAcceptableOrUnknown(data['max_bpm']!, _maxBpmMeta),
      );
    }
    if (data.containsKey('median_bpm')) {
      context.handle(
        _medianBpmMeta,
        medianBpm.isAcceptableOrUnknown(data['median_bpm']!, _medianBpmMeta),
      );
    }
    if (data.containsKey('best_pace_s_per_km')) {
      context.handle(
        _bestPaceSPerKmMeta,
        bestPaceSPerKm.isAcceptableOrUnknown(
          data['best_pace_s_per_km']!,
          _bestPaceSPerKmMeta,
        ),
      );
    }
    if (data.containsKey('lap_count')) {
      context.handle(
        _lapCountMeta,
        lapCount.isAcceptableOrUnknown(data['lap_count']!, _lapCountMeta),
      );
    }
    if (data.containsKey('heart_rate_time_s')) {
      context.handle(
        _heartRateTimeSMeta,
        heartRateTimeS.isAcceptableOrUnknown(
          data['heart_rate_time_s']!,
          _heartRateTimeSMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PreprocessingResult map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PreprocessingResult(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      runId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}run_id'],
      )!,
      method: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}method'],
      )!,
      methodVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}method_version'],
      )!,
      parameterVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}parameter_version'],
      )!,
      computedAtUs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}computed_at_us'],
      )!,
      totalTimeS: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}total_time_s'],
      ),
      movingTimeS: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}moving_time_s'],
      ),
      distanceM: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}distance_m'],
      ),
      bridgedDistanceM: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}bridged_distance_m'],
      ),
      averageBpm: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}average_bpm'],
      ),
      maxBpm: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}max_bpm'],
      ),
      medianBpm: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}median_bpm'],
      ),
      bestPaceSPerKm: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}best_pace_s_per_km'],
      ),
      lapCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}lap_count'],
      ),
      heartRateTimeS: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}heart_rate_time_s'],
      ),
    );
  }

  @override
  PreprocessingResults createAlias(String alias) {
    return PreprocessingResults(attachedDatabase, alias);
  }

  @override
  bool get dontWriteConstraints => true;
}

class PreprocessingResult extends DataClass
    implements Insertable<PreprocessingResult> {
  final int id;
  final int runId;
  final String method;
  final int methodVersion;
  final int parameterVersion;
  final int computedAtUs;

  /// Gesamt- und Bewegungszeit getrennt (FR-0052); NULL = nicht verfügbar.
  final double? totalTimeS;
  final double? movingTimeS;
  final double? distanceM;
  final double? bridgedDistanceM;
  final double? averageBpm;
  final int? maxBpm;
  final double? medianBpm;

  /// Kurzfassung (run-overview, ab Schema 4): Bestpace, Rundenzahl und
  /// Bewegungszeit mit Puls; NULL = nicht verfügbar bzw. nicht bekannt.
  final double? bestPaceSPerKm;
  final int? lapCount;
  final double? heartRateTimeS;
  const PreprocessingResult({
    required this.id,
    required this.runId,
    required this.method,
    required this.methodVersion,
    required this.parameterVersion,
    required this.computedAtUs,
    this.totalTimeS,
    this.movingTimeS,
    this.distanceM,
    this.bridgedDistanceM,
    this.averageBpm,
    this.maxBpm,
    this.medianBpm,
    this.bestPaceSPerKm,
    this.lapCount,
    this.heartRateTimeS,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['run_id'] = Variable<int>(runId);
    map['method'] = Variable<String>(method);
    map['method_version'] = Variable<int>(methodVersion);
    map['parameter_version'] = Variable<int>(parameterVersion);
    map['computed_at_us'] = Variable<int>(computedAtUs);
    if (!nullToAbsent || totalTimeS != null) {
      map['total_time_s'] = Variable<double>(totalTimeS);
    }
    if (!nullToAbsent || movingTimeS != null) {
      map['moving_time_s'] = Variable<double>(movingTimeS);
    }
    if (!nullToAbsent || distanceM != null) {
      map['distance_m'] = Variable<double>(distanceM);
    }
    if (!nullToAbsent || bridgedDistanceM != null) {
      map['bridged_distance_m'] = Variable<double>(bridgedDistanceM);
    }
    if (!nullToAbsent || averageBpm != null) {
      map['average_bpm'] = Variable<double>(averageBpm);
    }
    if (!nullToAbsent || maxBpm != null) {
      map['max_bpm'] = Variable<int>(maxBpm);
    }
    if (!nullToAbsent || medianBpm != null) {
      map['median_bpm'] = Variable<double>(medianBpm);
    }
    if (!nullToAbsent || bestPaceSPerKm != null) {
      map['best_pace_s_per_km'] = Variable<double>(bestPaceSPerKm);
    }
    if (!nullToAbsent || lapCount != null) {
      map['lap_count'] = Variable<int>(lapCount);
    }
    if (!nullToAbsent || heartRateTimeS != null) {
      map['heart_rate_time_s'] = Variable<double>(heartRateTimeS);
    }
    return map;
  }

  PreprocessingResultsCompanion toCompanion(bool nullToAbsent) {
    return PreprocessingResultsCompanion(
      id: Value(id),
      runId: Value(runId),
      method: Value(method),
      methodVersion: Value(methodVersion),
      parameterVersion: Value(parameterVersion),
      computedAtUs: Value(computedAtUs),
      totalTimeS: totalTimeS == null && nullToAbsent
          ? const Value.absent()
          : Value(totalTimeS),
      movingTimeS: movingTimeS == null && nullToAbsent
          ? const Value.absent()
          : Value(movingTimeS),
      distanceM: distanceM == null && nullToAbsent
          ? const Value.absent()
          : Value(distanceM),
      bridgedDistanceM: bridgedDistanceM == null && nullToAbsent
          ? const Value.absent()
          : Value(bridgedDistanceM),
      averageBpm: averageBpm == null && nullToAbsent
          ? const Value.absent()
          : Value(averageBpm),
      maxBpm: maxBpm == null && nullToAbsent
          ? const Value.absent()
          : Value(maxBpm),
      medianBpm: medianBpm == null && nullToAbsent
          ? const Value.absent()
          : Value(medianBpm),
      bestPaceSPerKm: bestPaceSPerKm == null && nullToAbsent
          ? const Value.absent()
          : Value(bestPaceSPerKm),
      lapCount: lapCount == null && nullToAbsent
          ? const Value.absent()
          : Value(lapCount),
      heartRateTimeS: heartRateTimeS == null && nullToAbsent
          ? const Value.absent()
          : Value(heartRateTimeS),
    );
  }

  factory PreprocessingResult.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PreprocessingResult(
      id: serializer.fromJson<int>(json['id']),
      runId: serializer.fromJson<int>(json['run_id']),
      method: serializer.fromJson<String>(json['method']),
      methodVersion: serializer.fromJson<int>(json['method_version']),
      parameterVersion: serializer.fromJson<int>(json['parameter_version']),
      computedAtUs: serializer.fromJson<int>(json['computed_at_us']),
      totalTimeS: serializer.fromJson<double?>(json['total_time_s']),
      movingTimeS: serializer.fromJson<double?>(json['moving_time_s']),
      distanceM: serializer.fromJson<double?>(json['distance_m']),
      bridgedDistanceM: serializer.fromJson<double?>(
        json['bridged_distance_m'],
      ),
      averageBpm: serializer.fromJson<double?>(json['average_bpm']),
      maxBpm: serializer.fromJson<int?>(json['max_bpm']),
      medianBpm: serializer.fromJson<double?>(json['median_bpm']),
      bestPaceSPerKm: serializer.fromJson<double?>(json['best_pace_s_per_km']),
      lapCount: serializer.fromJson<int?>(json['lap_count']),
      heartRateTimeS: serializer.fromJson<double?>(json['heart_rate_time_s']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'run_id': serializer.toJson<int>(runId),
      'method': serializer.toJson<String>(method),
      'method_version': serializer.toJson<int>(methodVersion),
      'parameter_version': serializer.toJson<int>(parameterVersion),
      'computed_at_us': serializer.toJson<int>(computedAtUs),
      'total_time_s': serializer.toJson<double?>(totalTimeS),
      'moving_time_s': serializer.toJson<double?>(movingTimeS),
      'distance_m': serializer.toJson<double?>(distanceM),
      'bridged_distance_m': serializer.toJson<double?>(bridgedDistanceM),
      'average_bpm': serializer.toJson<double?>(averageBpm),
      'max_bpm': serializer.toJson<int?>(maxBpm),
      'median_bpm': serializer.toJson<double?>(medianBpm),
      'best_pace_s_per_km': serializer.toJson<double?>(bestPaceSPerKm),
      'lap_count': serializer.toJson<int?>(lapCount),
      'heart_rate_time_s': serializer.toJson<double?>(heartRateTimeS),
    };
  }

  PreprocessingResult copyWith({
    int? id,
    int? runId,
    String? method,
    int? methodVersion,
    int? parameterVersion,
    int? computedAtUs,
    Value<double?> totalTimeS = const Value.absent(),
    Value<double?> movingTimeS = const Value.absent(),
    Value<double?> distanceM = const Value.absent(),
    Value<double?> bridgedDistanceM = const Value.absent(),
    Value<double?> averageBpm = const Value.absent(),
    Value<int?> maxBpm = const Value.absent(),
    Value<double?> medianBpm = const Value.absent(),
    Value<double?> bestPaceSPerKm = const Value.absent(),
    Value<int?> lapCount = const Value.absent(),
    Value<double?> heartRateTimeS = const Value.absent(),
  }) => PreprocessingResult(
    id: id ?? this.id,
    runId: runId ?? this.runId,
    method: method ?? this.method,
    methodVersion: methodVersion ?? this.methodVersion,
    parameterVersion: parameterVersion ?? this.parameterVersion,
    computedAtUs: computedAtUs ?? this.computedAtUs,
    totalTimeS: totalTimeS.present ? totalTimeS.value : this.totalTimeS,
    movingTimeS: movingTimeS.present ? movingTimeS.value : this.movingTimeS,
    distanceM: distanceM.present ? distanceM.value : this.distanceM,
    bridgedDistanceM: bridgedDistanceM.present
        ? bridgedDistanceM.value
        : this.bridgedDistanceM,
    averageBpm: averageBpm.present ? averageBpm.value : this.averageBpm,
    maxBpm: maxBpm.present ? maxBpm.value : this.maxBpm,
    medianBpm: medianBpm.present ? medianBpm.value : this.medianBpm,
    bestPaceSPerKm: bestPaceSPerKm.present
        ? bestPaceSPerKm.value
        : this.bestPaceSPerKm,
    lapCount: lapCount.present ? lapCount.value : this.lapCount,
    heartRateTimeS: heartRateTimeS.present
        ? heartRateTimeS.value
        : this.heartRateTimeS,
  );
  PreprocessingResult copyWithCompanion(PreprocessingResultsCompanion data) {
    return PreprocessingResult(
      id: data.id.present ? data.id.value : this.id,
      runId: data.runId.present ? data.runId.value : this.runId,
      method: data.method.present ? data.method.value : this.method,
      methodVersion: data.methodVersion.present
          ? data.methodVersion.value
          : this.methodVersion,
      parameterVersion: data.parameterVersion.present
          ? data.parameterVersion.value
          : this.parameterVersion,
      computedAtUs: data.computedAtUs.present
          ? data.computedAtUs.value
          : this.computedAtUs,
      totalTimeS: data.totalTimeS.present
          ? data.totalTimeS.value
          : this.totalTimeS,
      movingTimeS: data.movingTimeS.present
          ? data.movingTimeS.value
          : this.movingTimeS,
      distanceM: data.distanceM.present ? data.distanceM.value : this.distanceM,
      bridgedDistanceM: data.bridgedDistanceM.present
          ? data.bridgedDistanceM.value
          : this.bridgedDistanceM,
      averageBpm: data.averageBpm.present
          ? data.averageBpm.value
          : this.averageBpm,
      maxBpm: data.maxBpm.present ? data.maxBpm.value : this.maxBpm,
      medianBpm: data.medianBpm.present ? data.medianBpm.value : this.medianBpm,
      bestPaceSPerKm: data.bestPaceSPerKm.present
          ? data.bestPaceSPerKm.value
          : this.bestPaceSPerKm,
      lapCount: data.lapCount.present ? data.lapCount.value : this.lapCount,
      heartRateTimeS: data.heartRateTimeS.present
          ? data.heartRateTimeS.value
          : this.heartRateTimeS,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PreprocessingResult(')
          ..write('id: $id, ')
          ..write('runId: $runId, ')
          ..write('method: $method, ')
          ..write('methodVersion: $methodVersion, ')
          ..write('parameterVersion: $parameterVersion, ')
          ..write('computedAtUs: $computedAtUs, ')
          ..write('totalTimeS: $totalTimeS, ')
          ..write('movingTimeS: $movingTimeS, ')
          ..write('distanceM: $distanceM, ')
          ..write('bridgedDistanceM: $bridgedDistanceM, ')
          ..write('averageBpm: $averageBpm, ')
          ..write('maxBpm: $maxBpm, ')
          ..write('medianBpm: $medianBpm, ')
          ..write('bestPaceSPerKm: $bestPaceSPerKm, ')
          ..write('lapCount: $lapCount, ')
          ..write('heartRateTimeS: $heartRateTimeS')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    runId,
    method,
    methodVersion,
    parameterVersion,
    computedAtUs,
    totalTimeS,
    movingTimeS,
    distanceM,
    bridgedDistanceM,
    averageBpm,
    maxBpm,
    medianBpm,
    bestPaceSPerKm,
    lapCount,
    heartRateTimeS,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PreprocessingResult &&
          other.id == this.id &&
          other.runId == this.runId &&
          other.method == this.method &&
          other.methodVersion == this.methodVersion &&
          other.parameterVersion == this.parameterVersion &&
          other.computedAtUs == this.computedAtUs &&
          other.totalTimeS == this.totalTimeS &&
          other.movingTimeS == this.movingTimeS &&
          other.distanceM == this.distanceM &&
          other.bridgedDistanceM == this.bridgedDistanceM &&
          other.averageBpm == this.averageBpm &&
          other.maxBpm == this.maxBpm &&
          other.medianBpm == this.medianBpm &&
          other.bestPaceSPerKm == this.bestPaceSPerKm &&
          other.lapCount == this.lapCount &&
          other.heartRateTimeS == this.heartRateTimeS);
}

class PreprocessingResultsCompanion
    extends UpdateCompanion<PreprocessingResult> {
  final Value<int> id;
  final Value<int> runId;
  final Value<String> method;
  final Value<int> methodVersion;
  final Value<int> parameterVersion;
  final Value<int> computedAtUs;
  final Value<double?> totalTimeS;
  final Value<double?> movingTimeS;
  final Value<double?> distanceM;
  final Value<double?> bridgedDistanceM;
  final Value<double?> averageBpm;
  final Value<int?> maxBpm;
  final Value<double?> medianBpm;
  final Value<double?> bestPaceSPerKm;
  final Value<int?> lapCount;
  final Value<double?> heartRateTimeS;
  const PreprocessingResultsCompanion({
    this.id = const Value.absent(),
    this.runId = const Value.absent(),
    this.method = const Value.absent(),
    this.methodVersion = const Value.absent(),
    this.parameterVersion = const Value.absent(),
    this.computedAtUs = const Value.absent(),
    this.totalTimeS = const Value.absent(),
    this.movingTimeS = const Value.absent(),
    this.distanceM = const Value.absent(),
    this.bridgedDistanceM = const Value.absent(),
    this.averageBpm = const Value.absent(),
    this.maxBpm = const Value.absent(),
    this.medianBpm = const Value.absent(),
    this.bestPaceSPerKm = const Value.absent(),
    this.lapCount = const Value.absent(),
    this.heartRateTimeS = const Value.absent(),
  });
  PreprocessingResultsCompanion.insert({
    this.id = const Value.absent(),
    required int runId,
    required String method,
    required int methodVersion,
    required int parameterVersion,
    required int computedAtUs,
    this.totalTimeS = const Value.absent(),
    this.movingTimeS = const Value.absent(),
    this.distanceM = const Value.absent(),
    this.bridgedDistanceM = const Value.absent(),
    this.averageBpm = const Value.absent(),
    this.maxBpm = const Value.absent(),
    this.medianBpm = const Value.absent(),
    this.bestPaceSPerKm = const Value.absent(),
    this.lapCount = const Value.absent(),
    this.heartRateTimeS = const Value.absent(),
  }) : runId = Value(runId),
       method = Value(method),
       methodVersion = Value(methodVersion),
       parameterVersion = Value(parameterVersion),
       computedAtUs = Value(computedAtUs);
  static Insertable<PreprocessingResult> custom({
    Expression<int>? id,
    Expression<int>? runId,
    Expression<String>? method,
    Expression<int>? methodVersion,
    Expression<int>? parameterVersion,
    Expression<int>? computedAtUs,
    Expression<double>? totalTimeS,
    Expression<double>? movingTimeS,
    Expression<double>? distanceM,
    Expression<double>? bridgedDistanceM,
    Expression<double>? averageBpm,
    Expression<int>? maxBpm,
    Expression<double>? medianBpm,
    Expression<double>? bestPaceSPerKm,
    Expression<int>? lapCount,
    Expression<double>? heartRateTimeS,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (runId != null) 'run_id': runId,
      if (method != null) 'method': method,
      if (methodVersion != null) 'method_version': methodVersion,
      if (parameterVersion != null) 'parameter_version': parameterVersion,
      if (computedAtUs != null) 'computed_at_us': computedAtUs,
      if (totalTimeS != null) 'total_time_s': totalTimeS,
      if (movingTimeS != null) 'moving_time_s': movingTimeS,
      if (distanceM != null) 'distance_m': distanceM,
      if (bridgedDistanceM != null) 'bridged_distance_m': bridgedDistanceM,
      if (averageBpm != null) 'average_bpm': averageBpm,
      if (maxBpm != null) 'max_bpm': maxBpm,
      if (medianBpm != null) 'median_bpm': medianBpm,
      if (bestPaceSPerKm != null) 'best_pace_s_per_km': bestPaceSPerKm,
      if (lapCount != null) 'lap_count': lapCount,
      if (heartRateTimeS != null) 'heart_rate_time_s': heartRateTimeS,
    });
  }

  PreprocessingResultsCompanion copyWith({
    Value<int>? id,
    Value<int>? runId,
    Value<String>? method,
    Value<int>? methodVersion,
    Value<int>? parameterVersion,
    Value<int>? computedAtUs,
    Value<double?>? totalTimeS,
    Value<double?>? movingTimeS,
    Value<double?>? distanceM,
    Value<double?>? bridgedDistanceM,
    Value<double?>? averageBpm,
    Value<int?>? maxBpm,
    Value<double?>? medianBpm,
    Value<double?>? bestPaceSPerKm,
    Value<int?>? lapCount,
    Value<double?>? heartRateTimeS,
  }) {
    return PreprocessingResultsCompanion(
      id: id ?? this.id,
      runId: runId ?? this.runId,
      method: method ?? this.method,
      methodVersion: methodVersion ?? this.methodVersion,
      parameterVersion: parameterVersion ?? this.parameterVersion,
      computedAtUs: computedAtUs ?? this.computedAtUs,
      totalTimeS: totalTimeS ?? this.totalTimeS,
      movingTimeS: movingTimeS ?? this.movingTimeS,
      distanceM: distanceM ?? this.distanceM,
      bridgedDistanceM: bridgedDistanceM ?? this.bridgedDistanceM,
      averageBpm: averageBpm ?? this.averageBpm,
      maxBpm: maxBpm ?? this.maxBpm,
      medianBpm: medianBpm ?? this.medianBpm,
      bestPaceSPerKm: bestPaceSPerKm ?? this.bestPaceSPerKm,
      lapCount: lapCount ?? this.lapCount,
      heartRateTimeS: heartRateTimeS ?? this.heartRateTimeS,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (runId.present) {
      map['run_id'] = Variable<int>(runId.value);
    }
    if (method.present) {
      map['method'] = Variable<String>(method.value);
    }
    if (methodVersion.present) {
      map['method_version'] = Variable<int>(methodVersion.value);
    }
    if (parameterVersion.present) {
      map['parameter_version'] = Variable<int>(parameterVersion.value);
    }
    if (computedAtUs.present) {
      map['computed_at_us'] = Variable<int>(computedAtUs.value);
    }
    if (totalTimeS.present) {
      map['total_time_s'] = Variable<double>(totalTimeS.value);
    }
    if (movingTimeS.present) {
      map['moving_time_s'] = Variable<double>(movingTimeS.value);
    }
    if (distanceM.present) {
      map['distance_m'] = Variable<double>(distanceM.value);
    }
    if (bridgedDistanceM.present) {
      map['bridged_distance_m'] = Variable<double>(bridgedDistanceM.value);
    }
    if (averageBpm.present) {
      map['average_bpm'] = Variable<double>(averageBpm.value);
    }
    if (maxBpm.present) {
      map['max_bpm'] = Variable<int>(maxBpm.value);
    }
    if (medianBpm.present) {
      map['median_bpm'] = Variable<double>(medianBpm.value);
    }
    if (bestPaceSPerKm.present) {
      map['best_pace_s_per_km'] = Variable<double>(bestPaceSPerKm.value);
    }
    if (lapCount.present) {
      map['lap_count'] = Variable<int>(lapCount.value);
    }
    if (heartRateTimeS.present) {
      map['heart_rate_time_s'] = Variable<double>(heartRateTimeS.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PreprocessingResultsCompanion(')
          ..write('id: $id, ')
          ..write('runId: $runId, ')
          ..write('method: $method, ')
          ..write('methodVersion: $methodVersion, ')
          ..write('parameterVersion: $parameterVersion, ')
          ..write('computedAtUs: $computedAtUs, ')
          ..write('totalTimeS: $totalTimeS, ')
          ..write('movingTimeS: $movingTimeS, ')
          ..write('distanceM: $distanceM, ')
          ..write('bridgedDistanceM: $bridgedDistanceM, ')
          ..write('averageBpm: $averageBpm, ')
          ..write('maxBpm: $maxBpm, ')
          ..write('medianBpm: $medianBpm, ')
          ..write('bestPaceSPerKm: $bestPaceSPerKm, ')
          ..write('lapCount: $lapCount, ')
          ..write('heartRateTimeS: $heartRateTimeS')
          ..write(')'))
        .toString();
  }
}

class PreprocessedSamples extends Table
    with TableInfo<PreprocessedSamples, PreprocessedSample> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  PreprocessedSamples(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL PRIMARY KEY AUTOINCREMENT',
  );
  static const VerificationMeta _runIdMeta = const VerificationMeta('runId');
  late final GeneratedColumn<int> runId = GeneratedColumn<int>(
    'run_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL REFERENCES runs(id)ON DELETE CASCADE',
  );
  static const VerificationMeta _channelMeta = const VerificationMeta(
    'channel',
  );
  late final GeneratedColumn<String> channel = GeneratedColumn<String>(
    'channel',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (channel IN (\'position\', \'heart_rate\', \'altitude\', \'steps\'))',
  );
  static const VerificationMeta _rawIdMeta = const VerificationMeta('rawId');
  late final GeneratedColumn<int> rawId = GeneratedColumn<int>(
    'raw_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _timeUsMeta = const VerificationMeta('timeUs');
  late final GeneratedColumn<int> timeUs = GeneratedColumn<int>(
    'time_us',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _stateMeta = const VerificationMeta('state');
  late final GeneratedColumn<String> state = GeneratedColumn<String>(
    'state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (state IN (\'present\', \'estimated\', \'unavailable\', \'discarded\'))',
  );
  static const VerificationMeta _discardReasonMeta = const VerificationMeta(
    'discardReason',
  );
  late final GeneratedColumn<String> discardReason = GeneratedColumn<String>(
    'discard_reason',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: 'CHECK (discard_reason IN (\'accuracy\', \'hardJump\', \'softJump\', \'nonMonotonicTime\', \'implausibleHeartRate\', \'noContact\', \'heartRateOutlier\', \'verticalAccuracy\', \'invalidValue\'))',
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    runId,
    channel,
    rawId,
    timeUs,
    state,
    discardReason,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'preprocessed_samples';
  @override
  VerificationContext validateIntegrity(
    Insertable<PreprocessedSample> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('run_id')) {
      context.handle(
        _runIdMeta,
        runId.isAcceptableOrUnknown(data['run_id']!, _runIdMeta),
      );
    } else if (isInserting) {
      context.missing(_runIdMeta);
    }
    if (data.containsKey('channel')) {
      context.handle(
        _channelMeta,
        channel.isAcceptableOrUnknown(data['channel']!, _channelMeta),
      );
    } else if (isInserting) {
      context.missing(_channelMeta);
    }
    if (data.containsKey('raw_id')) {
      context.handle(
        _rawIdMeta,
        rawId.isAcceptableOrUnknown(data['raw_id']!, _rawIdMeta),
      );
    } else if (isInserting) {
      context.missing(_rawIdMeta);
    }
    if (data.containsKey('time_us')) {
      context.handle(
        _timeUsMeta,
        timeUs.isAcceptableOrUnknown(data['time_us']!, _timeUsMeta),
      );
    } else if (isInserting) {
      context.missing(_timeUsMeta);
    }
    if (data.containsKey('state')) {
      context.handle(
        _stateMeta,
        state.isAcceptableOrUnknown(data['state']!, _stateMeta),
      );
    } else if (isInserting) {
      context.missing(_stateMeta);
    }
    if (data.containsKey('discard_reason')) {
      context.handle(
        _discardReasonMeta,
        discardReason.isAcceptableOrUnknown(
          data['discard_reason']!,
          _discardReasonMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PreprocessedSample map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PreprocessedSample(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      runId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}run_id'],
      )!,
      channel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}channel'],
      )!,
      rawId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}raw_id'],
      )!,
      timeUs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}time_us'],
      )!,
      state: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}state'],
      )!,
      discardReason: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}discard_reason'],
      ),
    );
  }

  @override
  PreprocessedSamples createAlias(String alias) {
    return PreprocessedSamples(attachedDatabase, alias);
  }

  @override
  bool get dontWriteConstraints => true;
}

class PreprocessedSample extends DataClass
    implements Insertable<PreprocessedSample> {
  final int id;
  final int runId;
  final String channel;
  final int rawId;
  final int timeUs;
  final String state;

  /// Namen wie DiscardReason in core; NULL, wenn nicht verworfen.
  final String? discardReason;
  const PreprocessedSample({
    required this.id,
    required this.runId,
    required this.channel,
    required this.rawId,
    required this.timeUs,
    required this.state,
    this.discardReason,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['run_id'] = Variable<int>(runId);
    map['channel'] = Variable<String>(channel);
    map['raw_id'] = Variable<int>(rawId);
    map['time_us'] = Variable<int>(timeUs);
    map['state'] = Variable<String>(state);
    if (!nullToAbsent || discardReason != null) {
      map['discard_reason'] = Variable<String>(discardReason);
    }
    return map;
  }

  PreprocessedSamplesCompanion toCompanion(bool nullToAbsent) {
    return PreprocessedSamplesCompanion(
      id: Value(id),
      runId: Value(runId),
      channel: Value(channel),
      rawId: Value(rawId),
      timeUs: Value(timeUs),
      state: Value(state),
      discardReason: discardReason == null && nullToAbsent
          ? const Value.absent()
          : Value(discardReason),
    );
  }

  factory PreprocessedSample.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PreprocessedSample(
      id: serializer.fromJson<int>(json['id']),
      runId: serializer.fromJson<int>(json['run_id']),
      channel: serializer.fromJson<String>(json['channel']),
      rawId: serializer.fromJson<int>(json['raw_id']),
      timeUs: serializer.fromJson<int>(json['time_us']),
      state: serializer.fromJson<String>(json['state']),
      discardReason: serializer.fromJson<String?>(json['discard_reason']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'run_id': serializer.toJson<int>(runId),
      'channel': serializer.toJson<String>(channel),
      'raw_id': serializer.toJson<int>(rawId),
      'time_us': serializer.toJson<int>(timeUs),
      'state': serializer.toJson<String>(state),
      'discard_reason': serializer.toJson<String?>(discardReason),
    };
  }

  PreprocessedSample copyWith({
    int? id,
    int? runId,
    String? channel,
    int? rawId,
    int? timeUs,
    String? state,
    Value<String?> discardReason = const Value.absent(),
  }) => PreprocessedSample(
    id: id ?? this.id,
    runId: runId ?? this.runId,
    channel: channel ?? this.channel,
    rawId: rawId ?? this.rawId,
    timeUs: timeUs ?? this.timeUs,
    state: state ?? this.state,
    discardReason: discardReason.present
        ? discardReason.value
        : this.discardReason,
  );
  PreprocessedSample copyWithCompanion(PreprocessedSamplesCompanion data) {
    return PreprocessedSample(
      id: data.id.present ? data.id.value : this.id,
      runId: data.runId.present ? data.runId.value : this.runId,
      channel: data.channel.present ? data.channel.value : this.channel,
      rawId: data.rawId.present ? data.rawId.value : this.rawId,
      timeUs: data.timeUs.present ? data.timeUs.value : this.timeUs,
      state: data.state.present ? data.state.value : this.state,
      discardReason: data.discardReason.present
          ? data.discardReason.value
          : this.discardReason,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PreprocessedSample(')
          ..write('id: $id, ')
          ..write('runId: $runId, ')
          ..write('channel: $channel, ')
          ..write('rawId: $rawId, ')
          ..write('timeUs: $timeUs, ')
          ..write('state: $state, ')
          ..write('discardReason: $discardReason')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, runId, channel, rawId, timeUs, state, discardReason);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PreprocessedSample &&
          other.id == this.id &&
          other.runId == this.runId &&
          other.channel == this.channel &&
          other.rawId == this.rawId &&
          other.timeUs == this.timeUs &&
          other.state == this.state &&
          other.discardReason == this.discardReason);
}

class PreprocessedSamplesCompanion extends UpdateCompanion<PreprocessedSample> {
  final Value<int> id;
  final Value<int> runId;
  final Value<String> channel;
  final Value<int> rawId;
  final Value<int> timeUs;
  final Value<String> state;
  final Value<String?> discardReason;
  const PreprocessedSamplesCompanion({
    this.id = const Value.absent(),
    this.runId = const Value.absent(),
    this.channel = const Value.absent(),
    this.rawId = const Value.absent(),
    this.timeUs = const Value.absent(),
    this.state = const Value.absent(),
    this.discardReason = const Value.absent(),
  });
  PreprocessedSamplesCompanion.insert({
    this.id = const Value.absent(),
    required int runId,
    required String channel,
    required int rawId,
    required int timeUs,
    required String state,
    this.discardReason = const Value.absent(),
  }) : runId = Value(runId),
       channel = Value(channel),
       rawId = Value(rawId),
       timeUs = Value(timeUs),
       state = Value(state);
  static Insertable<PreprocessedSample> custom({
    Expression<int>? id,
    Expression<int>? runId,
    Expression<String>? channel,
    Expression<int>? rawId,
    Expression<int>? timeUs,
    Expression<String>? state,
    Expression<String>? discardReason,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (runId != null) 'run_id': runId,
      if (channel != null) 'channel': channel,
      if (rawId != null) 'raw_id': rawId,
      if (timeUs != null) 'time_us': timeUs,
      if (state != null) 'state': state,
      if (discardReason != null) 'discard_reason': discardReason,
    });
  }

  PreprocessedSamplesCompanion copyWith({
    Value<int>? id,
    Value<int>? runId,
    Value<String>? channel,
    Value<int>? rawId,
    Value<int>? timeUs,
    Value<String>? state,
    Value<String?>? discardReason,
  }) {
    return PreprocessedSamplesCompanion(
      id: id ?? this.id,
      runId: runId ?? this.runId,
      channel: channel ?? this.channel,
      rawId: rawId ?? this.rawId,
      timeUs: timeUs ?? this.timeUs,
      state: state ?? this.state,
      discardReason: discardReason ?? this.discardReason,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (runId.present) {
      map['run_id'] = Variable<int>(runId.value);
    }
    if (channel.present) {
      map['channel'] = Variable<String>(channel.value);
    }
    if (rawId.present) {
      map['raw_id'] = Variable<int>(rawId.value);
    }
    if (timeUs.present) {
      map['time_us'] = Variable<int>(timeUs.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(state.value);
    }
    if (discardReason.present) {
      map['discard_reason'] = Variable<String>(discardReason.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PreprocessedSamplesCompanion(')
          ..write('id: $id, ')
          ..write('runId: $runId, ')
          ..write('channel: $channel, ')
          ..write('rawId: $rawId, ')
          ..write('timeUs: $timeUs, ')
          ..write('state: $state, ')
          ..write('discardReason: $discardReason')
          ..write(')'))
        .toString();
  }
}

class PreprocessedSpans extends Table
    with TableInfo<PreprocessedSpans, PreprocessedSpan> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  PreprocessedSpans(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL PRIMARY KEY AUTOINCREMENT',
  );
  static const VerificationMeta _runIdMeta = const VerificationMeta('runId');
  late final GeneratedColumn<int> runId = GeneratedColumn<int>(
    'run_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL REFERENCES runs(id)ON DELETE CASCADE',
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (kind IN (\'moving\', \'settling\', \'position_gap\', \'heart_rate_gap\'))',
  );
  static const VerificationMeta _startUsMeta = const VerificationMeta(
    'startUs',
  );
  late final GeneratedColumn<int> startUs = GeneratedColumn<int>(
    'start_us',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _endUsMeta = const VerificationMeta('endUs');
  late final GeneratedColumn<int> endUs = GeneratedColumn<int>(
    'end_us',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  @override
  List<GeneratedColumn> get $columns => [id, runId, kind, startUs, endUs];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'preprocessed_spans';
  @override
  VerificationContext validateIntegrity(
    Insertable<PreprocessedSpan> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('run_id')) {
      context.handle(
        _runIdMeta,
        runId.isAcceptableOrUnknown(data['run_id']!, _runIdMeta),
      );
    } else if (isInserting) {
      context.missing(_runIdMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('start_us')) {
      context.handle(
        _startUsMeta,
        startUs.isAcceptableOrUnknown(data['start_us']!, _startUsMeta),
      );
    } else if (isInserting) {
      context.missing(_startUsMeta);
    }
    if (data.containsKey('end_us')) {
      context.handle(
        _endUsMeta,
        endUs.isAcceptableOrUnknown(data['end_us']!, _endUsMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PreprocessedSpan map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PreprocessedSpan(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      runId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}run_id'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      startUs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}start_us'],
      )!,
      endUs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}end_us'],
      ),
    );
  }

  @override
  PreprocessedSpans createAlias(String alias) {
    return PreprocessedSpans(attachedDatabase, alias);
  }

  @override
  bool get dontWriteConstraints => true;
}

class PreprocessedSpan extends DataClass
    implements Insertable<PreprocessedSpan> {
  final int id;
  final int runId;
  final String kind;
  final int startUs;
  final int? endUs;
  const PreprocessedSpan({
    required this.id,
    required this.runId,
    required this.kind,
    required this.startUs,
    this.endUs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['run_id'] = Variable<int>(runId);
    map['kind'] = Variable<String>(kind);
    map['start_us'] = Variable<int>(startUs);
    if (!nullToAbsent || endUs != null) {
      map['end_us'] = Variable<int>(endUs);
    }
    return map;
  }

  PreprocessedSpansCompanion toCompanion(bool nullToAbsent) {
    return PreprocessedSpansCompanion(
      id: Value(id),
      runId: Value(runId),
      kind: Value(kind),
      startUs: Value(startUs),
      endUs: endUs == null && nullToAbsent
          ? const Value.absent()
          : Value(endUs),
    );
  }

  factory PreprocessedSpan.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PreprocessedSpan(
      id: serializer.fromJson<int>(json['id']),
      runId: serializer.fromJson<int>(json['run_id']),
      kind: serializer.fromJson<String>(json['kind']),
      startUs: serializer.fromJson<int>(json['start_us']),
      endUs: serializer.fromJson<int?>(json['end_us']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'run_id': serializer.toJson<int>(runId),
      'kind': serializer.toJson<String>(kind),
      'start_us': serializer.toJson<int>(startUs),
      'end_us': serializer.toJson<int?>(endUs),
    };
  }

  PreprocessedSpan copyWith({
    int? id,
    int? runId,
    String? kind,
    int? startUs,
    Value<int?> endUs = const Value.absent(),
  }) => PreprocessedSpan(
    id: id ?? this.id,
    runId: runId ?? this.runId,
    kind: kind ?? this.kind,
    startUs: startUs ?? this.startUs,
    endUs: endUs.present ? endUs.value : this.endUs,
  );
  PreprocessedSpan copyWithCompanion(PreprocessedSpansCompanion data) {
    return PreprocessedSpan(
      id: data.id.present ? data.id.value : this.id,
      runId: data.runId.present ? data.runId.value : this.runId,
      kind: data.kind.present ? data.kind.value : this.kind,
      startUs: data.startUs.present ? data.startUs.value : this.startUs,
      endUs: data.endUs.present ? data.endUs.value : this.endUs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PreprocessedSpan(')
          ..write('id: $id, ')
          ..write('runId: $runId, ')
          ..write('kind: $kind, ')
          ..write('startUs: $startUs, ')
          ..write('endUs: $endUs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, runId, kind, startUs, endUs);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PreprocessedSpan &&
          other.id == this.id &&
          other.runId == this.runId &&
          other.kind == this.kind &&
          other.startUs == this.startUs &&
          other.endUs == this.endUs);
}

class PreprocessedSpansCompanion extends UpdateCompanion<PreprocessedSpan> {
  final Value<int> id;
  final Value<int> runId;
  final Value<String> kind;
  final Value<int> startUs;
  final Value<int?> endUs;
  const PreprocessedSpansCompanion({
    this.id = const Value.absent(),
    this.runId = const Value.absent(),
    this.kind = const Value.absent(),
    this.startUs = const Value.absent(),
    this.endUs = const Value.absent(),
  });
  PreprocessedSpansCompanion.insert({
    this.id = const Value.absent(),
    required int runId,
    required String kind,
    required int startUs,
    this.endUs = const Value.absent(),
  }) : runId = Value(runId),
       kind = Value(kind),
       startUs = Value(startUs);
  static Insertable<PreprocessedSpan> custom({
    Expression<int>? id,
    Expression<int>? runId,
    Expression<String>? kind,
    Expression<int>? startUs,
    Expression<int>? endUs,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (runId != null) 'run_id': runId,
      if (kind != null) 'kind': kind,
      if (startUs != null) 'start_us': startUs,
      if (endUs != null) 'end_us': endUs,
    });
  }

  PreprocessedSpansCompanion copyWith({
    Value<int>? id,
    Value<int>? runId,
    Value<String>? kind,
    Value<int>? startUs,
    Value<int?>? endUs,
  }) {
    return PreprocessedSpansCompanion(
      id: id ?? this.id,
      runId: runId ?? this.runId,
      kind: kind ?? this.kind,
      startUs: startUs ?? this.startUs,
      endUs: endUs ?? this.endUs,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (runId.present) {
      map['run_id'] = Variable<int>(runId.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (startUs.present) {
      map['start_us'] = Variable<int>(startUs.value);
    }
    if (endUs.present) {
      map['end_us'] = Variable<int>(endUs.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PreprocessedSpansCompanion(')
          ..write('id: $id, ')
          ..write('runId: $runId, ')
          ..write('kind: $kind, ')
          ..write('startUs: $startUs, ')
          ..write('endUs: $endUs')
          ..write(')'))
        .toString();
  }
}

class RatedSections extends Table with TableInfo<RatedSections, RatedSection> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  RatedSections(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL PRIMARY KEY AUTOINCREMENT',
  );
  static const VerificationMeta _runIdMeta = const VerificationMeta('runId');
  late final GeneratedColumn<int> runId = GeneratedColumn<int>(
    'run_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL REFERENCES runs(id)ON DELETE CASCADE',
  );
  static const VerificationMeta _startUsMeta = const VerificationMeta(
    'startUs',
  );
  late final GeneratedColumn<int> startUs = GeneratedColumn<int>(
    'start_us',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _endUsMeta = const VerificationMeta('endUs');
  late final GeneratedColumn<int> endUs = GeneratedColumn<int>(
    'end_us',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _methodMeta = const VerificationMeta('method');
  late final GeneratedColumn<String> method = GeneratedColumn<String>(
    'method',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _methodVersionMeta = const VerificationMeta(
    'methodVersion',
  );
  late final GeneratedColumn<int> methodVersion = GeneratedColumn<int>(
    'method_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _parameterVersionMeta = const VerificationMeta(
    'parameterVersion',
  );
  late final GeneratedColumn<int> parameterVersion = GeneratedColumn<int>(
    'parameter_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _assessedAtUsMeta = const VerificationMeta(
    'assessedAtUs',
  );
  late final GeneratedColumn<int> assessedAtUs = GeneratedColumn<int>(
    'assessed_at_us',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _heartRatePresentMeta = const VerificationMeta(
    'heartRatePresent',
  );
  late final GeneratedColumn<int> heartRatePresent = GeneratedColumn<int>(
    'heart_rate_present',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _heartRateEstimatedMeta =
      const VerificationMeta('heartRateEstimated');
  late final GeneratedColumn<int> heartRateEstimated = GeneratedColumn<int>(
    'heart_rate_estimated',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _heartRateUnavailableMeta =
      const VerificationMeta('heartRateUnavailable');
  late final GeneratedColumn<int> heartRateUnavailable = GeneratedColumn<int>(
    'heart_rate_unavailable',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _heartRateDiscardedMeta =
      const VerificationMeta('heartRateDiscarded');
  late final GeneratedColumn<int> heartRateDiscarded = GeneratedColumn<int>(
    'heart_rate_discarded',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _positionPresentMeta = const VerificationMeta(
    'positionPresent',
  );
  late final GeneratedColumn<int> positionPresent = GeneratedColumn<int>(
    'position_present',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _positionEstimatedMeta = const VerificationMeta(
    'positionEstimated',
  );
  late final GeneratedColumn<int> positionEstimated = GeneratedColumn<int>(
    'position_estimated',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _positionUnavailableMeta =
      const VerificationMeta('positionUnavailable');
  late final GeneratedColumn<int> positionUnavailable = GeneratedColumn<int>(
    'position_unavailable',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _positionDiscardedMeta = const VerificationMeta(
    'positionDiscarded',
  );
  late final GeneratedColumn<int> positionDiscarded = GeneratedColumn<int>(
    'position_discarded',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _missingHeartRateShareMeta =
      const VerificationMeta('missingHeartRateShare');
  late final GeneratedColumn<double> missingHeartRateShare =
      GeneratedColumn<double>(
        'missing_heart_rate_share',
        aliasedName,
        false,
        type: DriftSqlType.double,
        requiredDuringInsert: true,
        $customConstraints: 'NOT NULL',
      );
  static const VerificationMeta _longestHeartRateGapSMeta =
      const VerificationMeta('longestHeartRateGapS');
  late final GeneratedColumn<double> longestHeartRateGapS =
      GeneratedColumn<double>(
        'longest_heart_rate_gap_s',
        aliasedName,
        false,
        type: DriftSqlType.double,
        requiredDuringInsert: true,
        $customConstraints: 'NOT NULL',
      );
  static const VerificationMeta _meetsHeartRateGapRuleMeta =
      const VerificationMeta('meetsHeartRateGapRule');
  late final GeneratedColumn<bool> meetsHeartRateGapRule =
      GeneratedColumn<bool>(
        'meets_heart_rate_gap_rule',
        aliasedName,
        false,
        type: DriftSqlType.bool,
        requiredDuringInsert: true,
        $customConstraints:
            'NOT NULL CHECK (meets_heart_rate_gap_rule IN (0, 1))',
      );
  static const VerificationMeta _settlingOverlapSMeta = const VerificationMeta(
    'settlingOverlapS',
  );
  late final GeneratedColumn<double> settlingOverlapS = GeneratedColumn<double>(
    'settling_overlap_s',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _settlingShareMeta = const VerificationMeta(
    'settlingShare',
  );
  late final GeneratedColumn<double> settlingShare = GeneratedColumn<double>(
    'settling_share',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _gpsGapsMeta = const VerificationMeta(
    'gpsGaps',
  );
  late final GeneratedColumn<String> gpsGaps = GeneratedColumn<String>(
    'gps_gaps',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (json_valid(gps_gaps))',
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    runId,
    startUs,
    endUs,
    method,
    methodVersion,
    parameterVersion,
    assessedAtUs,
    heartRatePresent,
    heartRateEstimated,
    heartRateUnavailable,
    heartRateDiscarded,
    positionPresent,
    positionEstimated,
    positionUnavailable,
    positionDiscarded,
    missingHeartRateShare,
    longestHeartRateGapS,
    meetsHeartRateGapRule,
    settlingOverlapS,
    settlingShare,
    gpsGaps,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'rated_sections';
  @override
  VerificationContext validateIntegrity(
    Insertable<RatedSection> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('run_id')) {
      context.handle(
        _runIdMeta,
        runId.isAcceptableOrUnknown(data['run_id']!, _runIdMeta),
      );
    } else if (isInserting) {
      context.missing(_runIdMeta);
    }
    if (data.containsKey('start_us')) {
      context.handle(
        _startUsMeta,
        startUs.isAcceptableOrUnknown(data['start_us']!, _startUsMeta),
      );
    } else if (isInserting) {
      context.missing(_startUsMeta);
    }
    if (data.containsKey('end_us')) {
      context.handle(
        _endUsMeta,
        endUs.isAcceptableOrUnknown(data['end_us']!, _endUsMeta),
      );
    } else if (isInserting) {
      context.missing(_endUsMeta);
    }
    if (data.containsKey('method')) {
      context.handle(
        _methodMeta,
        method.isAcceptableOrUnknown(data['method']!, _methodMeta),
      );
    } else if (isInserting) {
      context.missing(_methodMeta);
    }
    if (data.containsKey('method_version')) {
      context.handle(
        _methodVersionMeta,
        methodVersion.isAcceptableOrUnknown(
          data['method_version']!,
          _methodVersionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_methodVersionMeta);
    }
    if (data.containsKey('parameter_version')) {
      context.handle(
        _parameterVersionMeta,
        parameterVersion.isAcceptableOrUnknown(
          data['parameter_version']!,
          _parameterVersionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_parameterVersionMeta);
    }
    if (data.containsKey('assessed_at_us')) {
      context.handle(
        _assessedAtUsMeta,
        assessedAtUs.isAcceptableOrUnknown(
          data['assessed_at_us']!,
          _assessedAtUsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_assessedAtUsMeta);
    }
    if (data.containsKey('heart_rate_present')) {
      context.handle(
        _heartRatePresentMeta,
        heartRatePresent.isAcceptableOrUnknown(
          data['heart_rate_present']!,
          _heartRatePresentMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_heartRatePresentMeta);
    }
    if (data.containsKey('heart_rate_estimated')) {
      context.handle(
        _heartRateEstimatedMeta,
        heartRateEstimated.isAcceptableOrUnknown(
          data['heart_rate_estimated']!,
          _heartRateEstimatedMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_heartRateEstimatedMeta);
    }
    if (data.containsKey('heart_rate_unavailable')) {
      context.handle(
        _heartRateUnavailableMeta,
        heartRateUnavailable.isAcceptableOrUnknown(
          data['heart_rate_unavailable']!,
          _heartRateUnavailableMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_heartRateUnavailableMeta);
    }
    if (data.containsKey('heart_rate_discarded')) {
      context.handle(
        _heartRateDiscardedMeta,
        heartRateDiscarded.isAcceptableOrUnknown(
          data['heart_rate_discarded']!,
          _heartRateDiscardedMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_heartRateDiscardedMeta);
    }
    if (data.containsKey('position_present')) {
      context.handle(
        _positionPresentMeta,
        positionPresent.isAcceptableOrUnknown(
          data['position_present']!,
          _positionPresentMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_positionPresentMeta);
    }
    if (data.containsKey('position_estimated')) {
      context.handle(
        _positionEstimatedMeta,
        positionEstimated.isAcceptableOrUnknown(
          data['position_estimated']!,
          _positionEstimatedMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_positionEstimatedMeta);
    }
    if (data.containsKey('position_unavailable')) {
      context.handle(
        _positionUnavailableMeta,
        positionUnavailable.isAcceptableOrUnknown(
          data['position_unavailable']!,
          _positionUnavailableMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_positionUnavailableMeta);
    }
    if (data.containsKey('position_discarded')) {
      context.handle(
        _positionDiscardedMeta,
        positionDiscarded.isAcceptableOrUnknown(
          data['position_discarded']!,
          _positionDiscardedMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_positionDiscardedMeta);
    }
    if (data.containsKey('missing_heart_rate_share')) {
      context.handle(
        _missingHeartRateShareMeta,
        missingHeartRateShare.isAcceptableOrUnknown(
          data['missing_heart_rate_share']!,
          _missingHeartRateShareMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_missingHeartRateShareMeta);
    }
    if (data.containsKey('longest_heart_rate_gap_s')) {
      context.handle(
        _longestHeartRateGapSMeta,
        longestHeartRateGapS.isAcceptableOrUnknown(
          data['longest_heart_rate_gap_s']!,
          _longestHeartRateGapSMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_longestHeartRateGapSMeta);
    }
    if (data.containsKey('meets_heart_rate_gap_rule')) {
      context.handle(
        _meetsHeartRateGapRuleMeta,
        meetsHeartRateGapRule.isAcceptableOrUnknown(
          data['meets_heart_rate_gap_rule']!,
          _meetsHeartRateGapRuleMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_meetsHeartRateGapRuleMeta);
    }
    if (data.containsKey('settling_overlap_s')) {
      context.handle(
        _settlingOverlapSMeta,
        settlingOverlapS.isAcceptableOrUnknown(
          data['settling_overlap_s']!,
          _settlingOverlapSMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_settlingOverlapSMeta);
    }
    if (data.containsKey('settling_share')) {
      context.handle(
        _settlingShareMeta,
        settlingShare.isAcceptableOrUnknown(
          data['settling_share']!,
          _settlingShareMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_settlingShareMeta);
    }
    if (data.containsKey('gps_gaps')) {
      context.handle(
        _gpsGapsMeta,
        gpsGaps.isAcceptableOrUnknown(data['gps_gaps']!, _gpsGapsMeta),
      );
    } else if (isInserting) {
      context.missing(_gpsGapsMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  RatedSection map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RatedSection(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      runId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}run_id'],
      )!,
      startUs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}start_us'],
      )!,
      endUs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}end_us'],
      )!,
      method: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}method'],
      )!,
      methodVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}method_version'],
      )!,
      parameterVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}parameter_version'],
      )!,
      assessedAtUs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}assessed_at_us'],
      )!,
      heartRatePresent: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}heart_rate_present'],
      )!,
      heartRateEstimated: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}heart_rate_estimated'],
      )!,
      heartRateUnavailable: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}heart_rate_unavailable'],
      )!,
      heartRateDiscarded: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}heart_rate_discarded'],
      )!,
      positionPresent: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position_present'],
      )!,
      positionEstimated: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position_estimated'],
      )!,
      positionUnavailable: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position_unavailable'],
      )!,
      positionDiscarded: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position_discarded'],
      )!,
      missingHeartRateShare: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}missing_heart_rate_share'],
      )!,
      longestHeartRateGapS: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}longest_heart_rate_gap_s'],
      )!,
      meetsHeartRateGapRule: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}meets_heart_rate_gap_rule'],
      )!,
      settlingOverlapS: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}settling_overlap_s'],
      )!,
      settlingShare: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}settling_share'],
      )!,
      gpsGaps: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}gps_gaps'],
      )!,
    );
  }

  @override
  RatedSections createAlias(String alias) {
    return RatedSections(attachedDatabase, alias);
  }

  @override
  bool get dontWriteConstraints => true;
}

class RatedSection extends DataClass implements Insertable<RatedSection> {
  final int id;
  final int runId;
  final int startUs;
  final int endUs;
  final String method;
  final int methodVersion;
  final int parameterVersion;
  final int assessedAtUs;
  final int heartRatePresent;
  final int heartRateEstimated;
  final int heartRateUnavailable;
  final int heartRateDiscarded;
  final int positionPresent;
  final int positionEstimated;
  final int positionUnavailable;
  final int positionDiscarded;
  final double missingHeartRateShare;
  final double longestHeartRateGapS;
  final bool meetsHeartRateGapRule;
  final double settlingOverlapS;
  final double settlingShare;

  /// JSON-Liste der GPS-Lücken [[start_us, end_us, offen 0/1], ...] (FR-0048).
  final String gpsGaps;
  const RatedSection({
    required this.id,
    required this.runId,
    required this.startUs,
    required this.endUs,
    required this.method,
    required this.methodVersion,
    required this.parameterVersion,
    required this.assessedAtUs,
    required this.heartRatePresent,
    required this.heartRateEstimated,
    required this.heartRateUnavailable,
    required this.heartRateDiscarded,
    required this.positionPresent,
    required this.positionEstimated,
    required this.positionUnavailable,
    required this.positionDiscarded,
    required this.missingHeartRateShare,
    required this.longestHeartRateGapS,
    required this.meetsHeartRateGapRule,
    required this.settlingOverlapS,
    required this.settlingShare,
    required this.gpsGaps,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['run_id'] = Variable<int>(runId);
    map['start_us'] = Variable<int>(startUs);
    map['end_us'] = Variable<int>(endUs);
    map['method'] = Variable<String>(method);
    map['method_version'] = Variable<int>(methodVersion);
    map['parameter_version'] = Variable<int>(parameterVersion);
    map['assessed_at_us'] = Variable<int>(assessedAtUs);
    map['heart_rate_present'] = Variable<int>(heartRatePresent);
    map['heart_rate_estimated'] = Variable<int>(heartRateEstimated);
    map['heart_rate_unavailable'] = Variable<int>(heartRateUnavailable);
    map['heart_rate_discarded'] = Variable<int>(heartRateDiscarded);
    map['position_present'] = Variable<int>(positionPresent);
    map['position_estimated'] = Variable<int>(positionEstimated);
    map['position_unavailable'] = Variable<int>(positionUnavailable);
    map['position_discarded'] = Variable<int>(positionDiscarded);
    map['missing_heart_rate_share'] = Variable<double>(missingHeartRateShare);
    map['longest_heart_rate_gap_s'] = Variable<double>(longestHeartRateGapS);
    map['meets_heart_rate_gap_rule'] = Variable<bool>(meetsHeartRateGapRule);
    map['settling_overlap_s'] = Variable<double>(settlingOverlapS);
    map['settling_share'] = Variable<double>(settlingShare);
    map['gps_gaps'] = Variable<String>(gpsGaps);
    return map;
  }

  RatedSectionsCompanion toCompanion(bool nullToAbsent) {
    return RatedSectionsCompanion(
      id: Value(id),
      runId: Value(runId),
      startUs: Value(startUs),
      endUs: Value(endUs),
      method: Value(method),
      methodVersion: Value(methodVersion),
      parameterVersion: Value(parameterVersion),
      assessedAtUs: Value(assessedAtUs),
      heartRatePresent: Value(heartRatePresent),
      heartRateEstimated: Value(heartRateEstimated),
      heartRateUnavailable: Value(heartRateUnavailable),
      heartRateDiscarded: Value(heartRateDiscarded),
      positionPresent: Value(positionPresent),
      positionEstimated: Value(positionEstimated),
      positionUnavailable: Value(positionUnavailable),
      positionDiscarded: Value(positionDiscarded),
      missingHeartRateShare: Value(missingHeartRateShare),
      longestHeartRateGapS: Value(longestHeartRateGapS),
      meetsHeartRateGapRule: Value(meetsHeartRateGapRule),
      settlingOverlapS: Value(settlingOverlapS),
      settlingShare: Value(settlingShare),
      gpsGaps: Value(gpsGaps),
    );
  }

  factory RatedSection.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RatedSection(
      id: serializer.fromJson<int>(json['id']),
      runId: serializer.fromJson<int>(json['run_id']),
      startUs: serializer.fromJson<int>(json['start_us']),
      endUs: serializer.fromJson<int>(json['end_us']),
      method: serializer.fromJson<String>(json['method']),
      methodVersion: serializer.fromJson<int>(json['method_version']),
      parameterVersion: serializer.fromJson<int>(json['parameter_version']),
      assessedAtUs: serializer.fromJson<int>(json['assessed_at_us']),
      heartRatePresent: serializer.fromJson<int>(json['heart_rate_present']),
      heartRateEstimated: serializer.fromJson<int>(
        json['heart_rate_estimated'],
      ),
      heartRateUnavailable: serializer.fromJson<int>(
        json['heart_rate_unavailable'],
      ),
      heartRateDiscarded: serializer.fromJson<int>(
        json['heart_rate_discarded'],
      ),
      positionPresent: serializer.fromJson<int>(json['position_present']),
      positionEstimated: serializer.fromJson<int>(json['position_estimated']),
      positionUnavailable: serializer.fromJson<int>(
        json['position_unavailable'],
      ),
      positionDiscarded: serializer.fromJson<int>(json['position_discarded']),
      missingHeartRateShare: serializer.fromJson<double>(
        json['missing_heart_rate_share'],
      ),
      longestHeartRateGapS: serializer.fromJson<double>(
        json['longest_heart_rate_gap_s'],
      ),
      meetsHeartRateGapRule: serializer.fromJson<bool>(
        json['meets_heart_rate_gap_rule'],
      ),
      settlingOverlapS: serializer.fromJson<double>(json['settling_overlap_s']),
      settlingShare: serializer.fromJson<double>(json['settling_share']),
      gpsGaps: serializer.fromJson<String>(json['gps_gaps']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'run_id': serializer.toJson<int>(runId),
      'start_us': serializer.toJson<int>(startUs),
      'end_us': serializer.toJson<int>(endUs),
      'method': serializer.toJson<String>(method),
      'method_version': serializer.toJson<int>(methodVersion),
      'parameter_version': serializer.toJson<int>(parameterVersion),
      'assessed_at_us': serializer.toJson<int>(assessedAtUs),
      'heart_rate_present': serializer.toJson<int>(heartRatePresent),
      'heart_rate_estimated': serializer.toJson<int>(heartRateEstimated),
      'heart_rate_unavailable': serializer.toJson<int>(heartRateUnavailable),
      'heart_rate_discarded': serializer.toJson<int>(heartRateDiscarded),
      'position_present': serializer.toJson<int>(positionPresent),
      'position_estimated': serializer.toJson<int>(positionEstimated),
      'position_unavailable': serializer.toJson<int>(positionUnavailable),
      'position_discarded': serializer.toJson<int>(positionDiscarded),
      'missing_heart_rate_share': serializer.toJson<double>(
        missingHeartRateShare,
      ),
      'longest_heart_rate_gap_s': serializer.toJson<double>(
        longestHeartRateGapS,
      ),
      'meets_heart_rate_gap_rule': serializer.toJson<bool>(
        meetsHeartRateGapRule,
      ),
      'settling_overlap_s': serializer.toJson<double>(settlingOverlapS),
      'settling_share': serializer.toJson<double>(settlingShare),
      'gps_gaps': serializer.toJson<String>(gpsGaps),
    };
  }

  RatedSection copyWith({
    int? id,
    int? runId,
    int? startUs,
    int? endUs,
    String? method,
    int? methodVersion,
    int? parameterVersion,
    int? assessedAtUs,
    int? heartRatePresent,
    int? heartRateEstimated,
    int? heartRateUnavailable,
    int? heartRateDiscarded,
    int? positionPresent,
    int? positionEstimated,
    int? positionUnavailable,
    int? positionDiscarded,
    double? missingHeartRateShare,
    double? longestHeartRateGapS,
    bool? meetsHeartRateGapRule,
    double? settlingOverlapS,
    double? settlingShare,
    String? gpsGaps,
  }) => RatedSection(
    id: id ?? this.id,
    runId: runId ?? this.runId,
    startUs: startUs ?? this.startUs,
    endUs: endUs ?? this.endUs,
    method: method ?? this.method,
    methodVersion: methodVersion ?? this.methodVersion,
    parameterVersion: parameterVersion ?? this.parameterVersion,
    assessedAtUs: assessedAtUs ?? this.assessedAtUs,
    heartRatePresent: heartRatePresent ?? this.heartRatePresent,
    heartRateEstimated: heartRateEstimated ?? this.heartRateEstimated,
    heartRateUnavailable: heartRateUnavailable ?? this.heartRateUnavailable,
    heartRateDiscarded: heartRateDiscarded ?? this.heartRateDiscarded,
    positionPresent: positionPresent ?? this.positionPresent,
    positionEstimated: positionEstimated ?? this.positionEstimated,
    positionUnavailable: positionUnavailable ?? this.positionUnavailable,
    positionDiscarded: positionDiscarded ?? this.positionDiscarded,
    missingHeartRateShare: missingHeartRateShare ?? this.missingHeartRateShare,
    longestHeartRateGapS: longestHeartRateGapS ?? this.longestHeartRateGapS,
    meetsHeartRateGapRule: meetsHeartRateGapRule ?? this.meetsHeartRateGapRule,
    settlingOverlapS: settlingOverlapS ?? this.settlingOverlapS,
    settlingShare: settlingShare ?? this.settlingShare,
    gpsGaps: gpsGaps ?? this.gpsGaps,
  );
  RatedSection copyWithCompanion(RatedSectionsCompanion data) {
    return RatedSection(
      id: data.id.present ? data.id.value : this.id,
      runId: data.runId.present ? data.runId.value : this.runId,
      startUs: data.startUs.present ? data.startUs.value : this.startUs,
      endUs: data.endUs.present ? data.endUs.value : this.endUs,
      method: data.method.present ? data.method.value : this.method,
      methodVersion: data.methodVersion.present
          ? data.methodVersion.value
          : this.methodVersion,
      parameterVersion: data.parameterVersion.present
          ? data.parameterVersion.value
          : this.parameterVersion,
      assessedAtUs: data.assessedAtUs.present
          ? data.assessedAtUs.value
          : this.assessedAtUs,
      heartRatePresent: data.heartRatePresent.present
          ? data.heartRatePresent.value
          : this.heartRatePresent,
      heartRateEstimated: data.heartRateEstimated.present
          ? data.heartRateEstimated.value
          : this.heartRateEstimated,
      heartRateUnavailable: data.heartRateUnavailable.present
          ? data.heartRateUnavailable.value
          : this.heartRateUnavailable,
      heartRateDiscarded: data.heartRateDiscarded.present
          ? data.heartRateDiscarded.value
          : this.heartRateDiscarded,
      positionPresent: data.positionPresent.present
          ? data.positionPresent.value
          : this.positionPresent,
      positionEstimated: data.positionEstimated.present
          ? data.positionEstimated.value
          : this.positionEstimated,
      positionUnavailable: data.positionUnavailable.present
          ? data.positionUnavailable.value
          : this.positionUnavailable,
      positionDiscarded: data.positionDiscarded.present
          ? data.positionDiscarded.value
          : this.positionDiscarded,
      missingHeartRateShare: data.missingHeartRateShare.present
          ? data.missingHeartRateShare.value
          : this.missingHeartRateShare,
      longestHeartRateGapS: data.longestHeartRateGapS.present
          ? data.longestHeartRateGapS.value
          : this.longestHeartRateGapS,
      meetsHeartRateGapRule: data.meetsHeartRateGapRule.present
          ? data.meetsHeartRateGapRule.value
          : this.meetsHeartRateGapRule,
      settlingOverlapS: data.settlingOverlapS.present
          ? data.settlingOverlapS.value
          : this.settlingOverlapS,
      settlingShare: data.settlingShare.present
          ? data.settlingShare.value
          : this.settlingShare,
      gpsGaps: data.gpsGaps.present ? data.gpsGaps.value : this.gpsGaps,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RatedSection(')
          ..write('id: $id, ')
          ..write('runId: $runId, ')
          ..write('startUs: $startUs, ')
          ..write('endUs: $endUs, ')
          ..write('method: $method, ')
          ..write('methodVersion: $methodVersion, ')
          ..write('parameterVersion: $parameterVersion, ')
          ..write('assessedAtUs: $assessedAtUs, ')
          ..write('heartRatePresent: $heartRatePresent, ')
          ..write('heartRateEstimated: $heartRateEstimated, ')
          ..write('heartRateUnavailable: $heartRateUnavailable, ')
          ..write('heartRateDiscarded: $heartRateDiscarded, ')
          ..write('positionPresent: $positionPresent, ')
          ..write('positionEstimated: $positionEstimated, ')
          ..write('positionUnavailable: $positionUnavailable, ')
          ..write('positionDiscarded: $positionDiscarded, ')
          ..write('missingHeartRateShare: $missingHeartRateShare, ')
          ..write('longestHeartRateGapS: $longestHeartRateGapS, ')
          ..write('meetsHeartRateGapRule: $meetsHeartRateGapRule, ')
          ..write('settlingOverlapS: $settlingOverlapS, ')
          ..write('settlingShare: $settlingShare, ')
          ..write('gpsGaps: $gpsGaps')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    runId,
    startUs,
    endUs,
    method,
    methodVersion,
    parameterVersion,
    assessedAtUs,
    heartRatePresent,
    heartRateEstimated,
    heartRateUnavailable,
    heartRateDiscarded,
    positionPresent,
    positionEstimated,
    positionUnavailable,
    positionDiscarded,
    missingHeartRateShare,
    longestHeartRateGapS,
    meetsHeartRateGapRule,
    settlingOverlapS,
    settlingShare,
    gpsGaps,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RatedSection &&
          other.id == this.id &&
          other.runId == this.runId &&
          other.startUs == this.startUs &&
          other.endUs == this.endUs &&
          other.method == this.method &&
          other.methodVersion == this.methodVersion &&
          other.parameterVersion == this.parameterVersion &&
          other.assessedAtUs == this.assessedAtUs &&
          other.heartRatePresent == this.heartRatePresent &&
          other.heartRateEstimated == this.heartRateEstimated &&
          other.heartRateUnavailable == this.heartRateUnavailable &&
          other.heartRateDiscarded == this.heartRateDiscarded &&
          other.positionPresent == this.positionPresent &&
          other.positionEstimated == this.positionEstimated &&
          other.positionUnavailable == this.positionUnavailable &&
          other.positionDiscarded == this.positionDiscarded &&
          other.missingHeartRateShare == this.missingHeartRateShare &&
          other.longestHeartRateGapS == this.longestHeartRateGapS &&
          other.meetsHeartRateGapRule == this.meetsHeartRateGapRule &&
          other.settlingOverlapS == this.settlingOverlapS &&
          other.settlingShare == this.settlingShare &&
          other.gpsGaps == this.gpsGaps);
}

class RatedSectionsCompanion extends UpdateCompanion<RatedSection> {
  final Value<int> id;
  final Value<int> runId;
  final Value<int> startUs;
  final Value<int> endUs;
  final Value<String> method;
  final Value<int> methodVersion;
  final Value<int> parameterVersion;
  final Value<int> assessedAtUs;
  final Value<int> heartRatePresent;
  final Value<int> heartRateEstimated;
  final Value<int> heartRateUnavailable;
  final Value<int> heartRateDiscarded;
  final Value<int> positionPresent;
  final Value<int> positionEstimated;
  final Value<int> positionUnavailable;
  final Value<int> positionDiscarded;
  final Value<double> missingHeartRateShare;
  final Value<double> longestHeartRateGapS;
  final Value<bool> meetsHeartRateGapRule;
  final Value<double> settlingOverlapS;
  final Value<double> settlingShare;
  final Value<String> gpsGaps;
  const RatedSectionsCompanion({
    this.id = const Value.absent(),
    this.runId = const Value.absent(),
    this.startUs = const Value.absent(),
    this.endUs = const Value.absent(),
    this.method = const Value.absent(),
    this.methodVersion = const Value.absent(),
    this.parameterVersion = const Value.absent(),
    this.assessedAtUs = const Value.absent(),
    this.heartRatePresent = const Value.absent(),
    this.heartRateEstimated = const Value.absent(),
    this.heartRateUnavailable = const Value.absent(),
    this.heartRateDiscarded = const Value.absent(),
    this.positionPresent = const Value.absent(),
    this.positionEstimated = const Value.absent(),
    this.positionUnavailable = const Value.absent(),
    this.positionDiscarded = const Value.absent(),
    this.missingHeartRateShare = const Value.absent(),
    this.longestHeartRateGapS = const Value.absent(),
    this.meetsHeartRateGapRule = const Value.absent(),
    this.settlingOverlapS = const Value.absent(),
    this.settlingShare = const Value.absent(),
    this.gpsGaps = const Value.absent(),
  });
  RatedSectionsCompanion.insert({
    this.id = const Value.absent(),
    required int runId,
    required int startUs,
    required int endUs,
    required String method,
    required int methodVersion,
    required int parameterVersion,
    required int assessedAtUs,
    required int heartRatePresent,
    required int heartRateEstimated,
    required int heartRateUnavailable,
    required int heartRateDiscarded,
    required int positionPresent,
    required int positionEstimated,
    required int positionUnavailable,
    required int positionDiscarded,
    required double missingHeartRateShare,
    required double longestHeartRateGapS,
    required bool meetsHeartRateGapRule,
    required double settlingOverlapS,
    required double settlingShare,
    required String gpsGaps,
  }) : runId = Value(runId),
       startUs = Value(startUs),
       endUs = Value(endUs),
       method = Value(method),
       methodVersion = Value(methodVersion),
       parameterVersion = Value(parameterVersion),
       assessedAtUs = Value(assessedAtUs),
       heartRatePresent = Value(heartRatePresent),
       heartRateEstimated = Value(heartRateEstimated),
       heartRateUnavailable = Value(heartRateUnavailable),
       heartRateDiscarded = Value(heartRateDiscarded),
       positionPresent = Value(positionPresent),
       positionEstimated = Value(positionEstimated),
       positionUnavailable = Value(positionUnavailable),
       positionDiscarded = Value(positionDiscarded),
       missingHeartRateShare = Value(missingHeartRateShare),
       longestHeartRateGapS = Value(longestHeartRateGapS),
       meetsHeartRateGapRule = Value(meetsHeartRateGapRule),
       settlingOverlapS = Value(settlingOverlapS),
       settlingShare = Value(settlingShare),
       gpsGaps = Value(gpsGaps);
  static Insertable<RatedSection> custom({
    Expression<int>? id,
    Expression<int>? runId,
    Expression<int>? startUs,
    Expression<int>? endUs,
    Expression<String>? method,
    Expression<int>? methodVersion,
    Expression<int>? parameterVersion,
    Expression<int>? assessedAtUs,
    Expression<int>? heartRatePresent,
    Expression<int>? heartRateEstimated,
    Expression<int>? heartRateUnavailable,
    Expression<int>? heartRateDiscarded,
    Expression<int>? positionPresent,
    Expression<int>? positionEstimated,
    Expression<int>? positionUnavailable,
    Expression<int>? positionDiscarded,
    Expression<double>? missingHeartRateShare,
    Expression<double>? longestHeartRateGapS,
    Expression<bool>? meetsHeartRateGapRule,
    Expression<double>? settlingOverlapS,
    Expression<double>? settlingShare,
    Expression<String>? gpsGaps,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (runId != null) 'run_id': runId,
      if (startUs != null) 'start_us': startUs,
      if (endUs != null) 'end_us': endUs,
      if (method != null) 'method': method,
      if (methodVersion != null) 'method_version': methodVersion,
      if (parameterVersion != null) 'parameter_version': parameterVersion,
      if (assessedAtUs != null) 'assessed_at_us': assessedAtUs,
      if (heartRatePresent != null) 'heart_rate_present': heartRatePresent,
      if (heartRateEstimated != null)
        'heart_rate_estimated': heartRateEstimated,
      if (heartRateUnavailable != null)
        'heart_rate_unavailable': heartRateUnavailable,
      if (heartRateDiscarded != null)
        'heart_rate_discarded': heartRateDiscarded,
      if (positionPresent != null) 'position_present': positionPresent,
      if (positionEstimated != null) 'position_estimated': positionEstimated,
      if (positionUnavailable != null)
        'position_unavailable': positionUnavailable,
      if (positionDiscarded != null) 'position_discarded': positionDiscarded,
      if (missingHeartRateShare != null)
        'missing_heart_rate_share': missingHeartRateShare,
      if (longestHeartRateGapS != null)
        'longest_heart_rate_gap_s': longestHeartRateGapS,
      if (meetsHeartRateGapRule != null)
        'meets_heart_rate_gap_rule': meetsHeartRateGapRule,
      if (settlingOverlapS != null) 'settling_overlap_s': settlingOverlapS,
      if (settlingShare != null) 'settling_share': settlingShare,
      if (gpsGaps != null) 'gps_gaps': gpsGaps,
    });
  }

  RatedSectionsCompanion copyWith({
    Value<int>? id,
    Value<int>? runId,
    Value<int>? startUs,
    Value<int>? endUs,
    Value<String>? method,
    Value<int>? methodVersion,
    Value<int>? parameterVersion,
    Value<int>? assessedAtUs,
    Value<int>? heartRatePresent,
    Value<int>? heartRateEstimated,
    Value<int>? heartRateUnavailable,
    Value<int>? heartRateDiscarded,
    Value<int>? positionPresent,
    Value<int>? positionEstimated,
    Value<int>? positionUnavailable,
    Value<int>? positionDiscarded,
    Value<double>? missingHeartRateShare,
    Value<double>? longestHeartRateGapS,
    Value<bool>? meetsHeartRateGapRule,
    Value<double>? settlingOverlapS,
    Value<double>? settlingShare,
    Value<String>? gpsGaps,
  }) {
    return RatedSectionsCompanion(
      id: id ?? this.id,
      runId: runId ?? this.runId,
      startUs: startUs ?? this.startUs,
      endUs: endUs ?? this.endUs,
      method: method ?? this.method,
      methodVersion: methodVersion ?? this.methodVersion,
      parameterVersion: parameterVersion ?? this.parameterVersion,
      assessedAtUs: assessedAtUs ?? this.assessedAtUs,
      heartRatePresent: heartRatePresent ?? this.heartRatePresent,
      heartRateEstimated: heartRateEstimated ?? this.heartRateEstimated,
      heartRateUnavailable: heartRateUnavailable ?? this.heartRateUnavailable,
      heartRateDiscarded: heartRateDiscarded ?? this.heartRateDiscarded,
      positionPresent: positionPresent ?? this.positionPresent,
      positionEstimated: positionEstimated ?? this.positionEstimated,
      positionUnavailable: positionUnavailable ?? this.positionUnavailable,
      positionDiscarded: positionDiscarded ?? this.positionDiscarded,
      missingHeartRateShare:
          missingHeartRateShare ?? this.missingHeartRateShare,
      longestHeartRateGapS: longestHeartRateGapS ?? this.longestHeartRateGapS,
      meetsHeartRateGapRule:
          meetsHeartRateGapRule ?? this.meetsHeartRateGapRule,
      settlingOverlapS: settlingOverlapS ?? this.settlingOverlapS,
      settlingShare: settlingShare ?? this.settlingShare,
      gpsGaps: gpsGaps ?? this.gpsGaps,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (runId.present) {
      map['run_id'] = Variable<int>(runId.value);
    }
    if (startUs.present) {
      map['start_us'] = Variable<int>(startUs.value);
    }
    if (endUs.present) {
      map['end_us'] = Variable<int>(endUs.value);
    }
    if (method.present) {
      map['method'] = Variable<String>(method.value);
    }
    if (methodVersion.present) {
      map['method_version'] = Variable<int>(methodVersion.value);
    }
    if (parameterVersion.present) {
      map['parameter_version'] = Variable<int>(parameterVersion.value);
    }
    if (assessedAtUs.present) {
      map['assessed_at_us'] = Variable<int>(assessedAtUs.value);
    }
    if (heartRatePresent.present) {
      map['heart_rate_present'] = Variable<int>(heartRatePresent.value);
    }
    if (heartRateEstimated.present) {
      map['heart_rate_estimated'] = Variable<int>(heartRateEstimated.value);
    }
    if (heartRateUnavailable.present) {
      map['heart_rate_unavailable'] = Variable<int>(heartRateUnavailable.value);
    }
    if (heartRateDiscarded.present) {
      map['heart_rate_discarded'] = Variable<int>(heartRateDiscarded.value);
    }
    if (positionPresent.present) {
      map['position_present'] = Variable<int>(positionPresent.value);
    }
    if (positionEstimated.present) {
      map['position_estimated'] = Variable<int>(positionEstimated.value);
    }
    if (positionUnavailable.present) {
      map['position_unavailable'] = Variable<int>(positionUnavailable.value);
    }
    if (positionDiscarded.present) {
      map['position_discarded'] = Variable<int>(positionDiscarded.value);
    }
    if (missingHeartRateShare.present) {
      map['missing_heart_rate_share'] = Variable<double>(
        missingHeartRateShare.value,
      );
    }
    if (longestHeartRateGapS.present) {
      map['longest_heart_rate_gap_s'] = Variable<double>(
        longestHeartRateGapS.value,
      );
    }
    if (meetsHeartRateGapRule.present) {
      map['meets_heart_rate_gap_rule'] = Variable<bool>(
        meetsHeartRateGapRule.value,
      );
    }
    if (settlingOverlapS.present) {
      map['settling_overlap_s'] = Variable<double>(settlingOverlapS.value);
    }
    if (settlingShare.present) {
      map['settling_share'] = Variable<double>(settlingShare.value);
    }
    if (gpsGaps.present) {
      map['gps_gaps'] = Variable<String>(gpsGaps.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RatedSectionsCompanion(')
          ..write('id: $id, ')
          ..write('runId: $runId, ')
          ..write('startUs: $startUs, ')
          ..write('endUs: $endUs, ')
          ..write('method: $method, ')
          ..write('methodVersion: $methodVersion, ')
          ..write('parameterVersion: $parameterVersion, ')
          ..write('assessedAtUs: $assessedAtUs, ')
          ..write('heartRatePresent: $heartRatePresent, ')
          ..write('heartRateEstimated: $heartRateEstimated, ')
          ..write('heartRateUnavailable: $heartRateUnavailable, ')
          ..write('heartRateDiscarded: $heartRateDiscarded, ')
          ..write('positionPresent: $positionPresent, ')
          ..write('positionEstimated: $positionEstimated, ')
          ..write('positionUnavailable: $positionUnavailable, ')
          ..write('positionDiscarded: $positionDiscarded, ')
          ..write('missingHeartRateShare: $missingHeartRateShare, ')
          ..write('longestHeartRateGapS: $longestHeartRateGapS, ')
          ..write('meetsHeartRateGapRule: $meetsHeartRateGapRule, ')
          ..write('settlingOverlapS: $settlingOverlapS, ')
          ..write('settlingShare: $settlingShare, ')
          ..write('gpsGaps: $gpsGaps')
          ..write(')'))
        .toString();
  }
}

class ComputedValues extends Table
    with TableInfo<ComputedValues, ComputedValue> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  ComputedValues(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL PRIMARY KEY AUTOINCREMENT',
  );
  static const VerificationMeta _runIdMeta = const VerificationMeta('runId');
  late final GeneratedColumn<int> runId = GeneratedColumn<int>(
    'run_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: 'REFERENCES runs(id)ON DELETE CASCADE',
  );
  static const VerificationMeta _dayMeta = const VerificationMeta('day');
  late final GeneratedColumn<String> day = GeneratedColumn<String>(
    'day',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _valueKeyMeta = const VerificationMeta(
    'valueKey',
  );
  late final GeneratedColumn<String> valueKey = GeneratedColumn<String>(
    'value_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _roleMeta = const VerificationMeta('role');
  late final GeneratedColumn<String> role = GeneratedColumn<String>(
    'role',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (role IN (\'original\', \'current\'))',
  );
  static const VerificationMeta _valueRealMeta = const VerificationMeta(
    'valueReal',
  );
  late final GeneratedColumn<double> valueReal = GeneratedColumn<double>(
    'value_real',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _unitMeta = const VerificationMeta('unit');
  late final GeneratedColumn<String> unit = GeneratedColumn<String>(
    'unit',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _computedAtUsMeta = const VerificationMeta(
    'computedAtUs',
  );
  late final GeneratedColumn<int> computedAtUs = GeneratedColumn<int>(
    'computed_at_us',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _dataFromUsMeta = const VerificationMeta(
    'dataFromUs',
  );
  late final GeneratedColumn<int> dataFromUs = GeneratedColumn<int>(
    'data_from_us',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _dataToUsMeta = const VerificationMeta(
    'dataToUs',
  );
  late final GeneratedColumn<int> dataToUs = GeneratedColumn<int>(
    'data_to_us',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _measurementCountMeta = const VerificationMeta(
    'measurementCount',
  );
  late final GeneratedColumn<int> measurementCount = GeneratedColumn<int>(
    'measurement_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _sourcesMeta = const VerificationMeta(
    'sources',
  );
  late final GeneratedColumn<String> sources = GeneratedColumn<String>(
    'sources',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _methodMeta = const VerificationMeta('method');
  late final GeneratedColumn<String> method = GeneratedColumn<String>(
    'method',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _methodVersionMeta = const VerificationMeta(
    'methodVersion',
  );
  late final GeneratedColumn<int> methodVersion = GeneratedColumn<int>(
    'method_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _parameterVersionMeta = const VerificationMeta(
    'parameterVersion',
  );
  late final GeneratedColumn<int> parameterVersion = GeneratedColumn<int>(
    'parameter_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _qualityMeta = const VerificationMeta(
    'quality',
  );
  late final GeneratedColumn<String> quality = GeneratedColumn<String>(
    'quality',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (quality IN (\'provisional\', \'sufficient\', \'good\', \'undeterminable\'))',
  );
  static const VerificationMeta _unavailableReasonMeta = const VerificationMeta(
    'unavailableReason',
  );
  late final GeneratedColumn<String> unavailableReason =
      GeneratedColumn<String>(
        'unavailable_reason',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        $customConstraints: '',
      );
  static const VerificationMeta _hrMaxBpmMeta = const VerificationMeta(
    'hrMaxBpm',
  );
  late final GeneratedColumn<int> hrMaxBpm = GeneratedColumn<int>(
    'hr_max_bpm',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: 'CHECK (hr_max_bpm > 0)',
  );
  static const VerificationMeta _hrRestBpmMeta = const VerificationMeta(
    'hrRestBpm',
  );
  late final GeneratedColumn<int> hrRestBpm = GeneratedColumn<int>(
    'hr_rest_bpm',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: 'CHECK (hr_rest_bpm > 0)',
  );
  static const VerificationMeta _hrMaxIsEstimatedMeta = const VerificationMeta(
    'hrMaxIsEstimated',
  );
  late final GeneratedColumn<bool> hrMaxIsEstimated = GeneratedColumn<bool>(
    'hr_max_is_estimated',
    aliasedName,
    true,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    $customConstraints: 'CHECK (hr_max_is_estimated IN (0, 1))',
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    runId,
    day,
    valueKey,
    role,
    valueReal,
    unit,
    computedAtUs,
    dataFromUs,
    dataToUs,
    measurementCount,
    sources,
    method,
    methodVersion,
    parameterVersion,
    quality,
    unavailableReason,
    hrMaxBpm,
    hrRestBpm,
    hrMaxIsEstimated,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'computed_values';
  @override
  VerificationContext validateIntegrity(
    Insertable<ComputedValue> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('run_id')) {
      context.handle(
        _runIdMeta,
        runId.isAcceptableOrUnknown(data['run_id']!, _runIdMeta),
      );
    }
    if (data.containsKey('day')) {
      context.handle(
        _dayMeta,
        day.isAcceptableOrUnknown(data['day']!, _dayMeta),
      );
    }
    if (data.containsKey('value_key')) {
      context.handle(
        _valueKeyMeta,
        valueKey.isAcceptableOrUnknown(data['value_key']!, _valueKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_valueKeyMeta);
    }
    if (data.containsKey('role')) {
      context.handle(
        _roleMeta,
        role.isAcceptableOrUnknown(data['role']!, _roleMeta),
      );
    } else if (isInserting) {
      context.missing(_roleMeta);
    }
    if (data.containsKey('value_real')) {
      context.handle(
        _valueRealMeta,
        valueReal.isAcceptableOrUnknown(data['value_real']!, _valueRealMeta),
      );
    }
    if (data.containsKey('unit')) {
      context.handle(
        _unitMeta,
        unit.isAcceptableOrUnknown(data['unit']!, _unitMeta),
      );
    } else if (isInserting) {
      context.missing(_unitMeta);
    }
    if (data.containsKey('computed_at_us')) {
      context.handle(
        _computedAtUsMeta,
        computedAtUs.isAcceptableOrUnknown(
          data['computed_at_us']!,
          _computedAtUsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_computedAtUsMeta);
    }
    if (data.containsKey('data_from_us')) {
      context.handle(
        _dataFromUsMeta,
        dataFromUs.isAcceptableOrUnknown(
          data['data_from_us']!,
          _dataFromUsMeta,
        ),
      );
    }
    if (data.containsKey('data_to_us')) {
      context.handle(
        _dataToUsMeta,
        dataToUs.isAcceptableOrUnknown(data['data_to_us']!, _dataToUsMeta),
      );
    }
    if (data.containsKey('measurement_count')) {
      context.handle(
        _measurementCountMeta,
        measurementCount.isAcceptableOrUnknown(
          data['measurement_count']!,
          _measurementCountMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_measurementCountMeta);
    }
    if (data.containsKey('sources')) {
      context.handle(
        _sourcesMeta,
        sources.isAcceptableOrUnknown(data['sources']!, _sourcesMeta),
      );
    } else if (isInserting) {
      context.missing(_sourcesMeta);
    }
    if (data.containsKey('method')) {
      context.handle(
        _methodMeta,
        method.isAcceptableOrUnknown(data['method']!, _methodMeta),
      );
    } else if (isInserting) {
      context.missing(_methodMeta);
    }
    if (data.containsKey('method_version')) {
      context.handle(
        _methodVersionMeta,
        methodVersion.isAcceptableOrUnknown(
          data['method_version']!,
          _methodVersionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_methodVersionMeta);
    }
    if (data.containsKey('parameter_version')) {
      context.handle(
        _parameterVersionMeta,
        parameterVersion.isAcceptableOrUnknown(
          data['parameter_version']!,
          _parameterVersionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_parameterVersionMeta);
    }
    if (data.containsKey('quality')) {
      context.handle(
        _qualityMeta,
        quality.isAcceptableOrUnknown(data['quality']!, _qualityMeta),
      );
    } else if (isInserting) {
      context.missing(_qualityMeta);
    }
    if (data.containsKey('unavailable_reason')) {
      context.handle(
        _unavailableReasonMeta,
        unavailableReason.isAcceptableOrUnknown(
          data['unavailable_reason']!,
          _unavailableReasonMeta,
        ),
      );
    }
    if (data.containsKey('hr_max_bpm')) {
      context.handle(
        _hrMaxBpmMeta,
        hrMaxBpm.isAcceptableOrUnknown(data['hr_max_bpm']!, _hrMaxBpmMeta),
      );
    }
    if (data.containsKey('hr_rest_bpm')) {
      context.handle(
        _hrRestBpmMeta,
        hrRestBpm.isAcceptableOrUnknown(data['hr_rest_bpm']!, _hrRestBpmMeta),
      );
    }
    if (data.containsKey('hr_max_is_estimated')) {
      context.handle(
        _hrMaxIsEstimatedMeta,
        hrMaxIsEstimated.isAcceptableOrUnknown(
          data['hr_max_is_estimated']!,
          _hrMaxIsEstimatedMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ComputedValue map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ComputedValue(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      runId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}run_id'],
      ),
      day: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}day'],
      ),
      valueKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value_key'],
      )!,
      role: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}role'],
      )!,
      valueReal: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}value_real'],
      ),
      unit: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}unit'],
      )!,
      computedAtUs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}computed_at_us'],
      )!,
      dataFromUs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}data_from_us'],
      ),
      dataToUs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}data_to_us'],
      ),
      measurementCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}measurement_count'],
      )!,
      sources: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sources'],
      )!,
      method: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}method'],
      )!,
      methodVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}method_version'],
      )!,
      parameterVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}parameter_version'],
      )!,
      quality: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}quality'],
      )!,
      unavailableReason: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}unavailable_reason'],
      ),
      hrMaxBpm: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}hr_max_bpm'],
      ),
      hrRestBpm: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}hr_rest_bpm'],
      ),
      hrMaxIsEstimated: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}hr_max_is_estimated'],
      ),
    );
  }

  @override
  ComputedValues createAlias(String alias) {
    return ComputedValues(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints => const [
    'CHECK((run_id IS NULL)<>(day IS NULL))',
  ];
  @override
  bool get dontWriteConstraints => true;
}

class ComputedValue extends DataClass implements Insertable<ComputedValue> {
  final int id;
  final int? runId;
  final String? day;
  final String valueKey;
  final String role;

  /// NULL genau dann, wenn unavailable_reason gesetzt ist (Qualitätsstufe
  /// 'undeterminable'; Trigger computed_values_reason_*).
  final double? valueReal;
  final String unit;
  final int computedAtUs;
  final int? dataFromUs;
  final int? dataToUs;
  final int measurementCount;

  /// JSON-Liste der Quellgeräte und -quellen.
  final String sources;
  final String method;
  final int methodVersion;
  final int parameterVersion;
  final String quality;

  /// Seit Version 3 (WP09 D1): Grund, warum der Wert fehlt (FR-0068, PAR-037),
  /// als stabiler Code (Name von UnavailableReason im Core). Ein Code, den eine
  /// spätere App nicht kennt, ist beim Lesen ein Datenfehler.
  final String? unavailableReason;

  /// Seit Version 3 (WP09 D2a, OQ-0065): Schnappschuss der Herzfrequenzbasis,
  /// mit der der Wert gerechnet wurde, damit spätere Neuberechnungen alte Werte
  /// mit derselben Basis rechnen. hr_max_is_estimated ist der Anzeiger: NULL =
  /// kein Schnappschuss (Wert braucht keine Basis, oder Zeile aus Version 1:
  /// Basis unbekannt); sonst gilt der Schnappschuss, und hr_max_bpm bzw.
  /// hr_rest_bpm sind NULL, wenn die Basis diesen Wert nicht kannte. Bei
  /// hr_max_bpm / hr_rest_bpm ohne Anzeiger bricht der Trigger
  /// computed_values_basis_* ab.
  final int? hrMaxBpm;
  final int? hrRestBpm;
  final bool? hrMaxIsEstimated;
  const ComputedValue({
    required this.id,
    this.runId,
    this.day,
    required this.valueKey,
    required this.role,
    this.valueReal,
    required this.unit,
    required this.computedAtUs,
    this.dataFromUs,
    this.dataToUs,
    required this.measurementCount,
    required this.sources,
    required this.method,
    required this.methodVersion,
    required this.parameterVersion,
    required this.quality,
    this.unavailableReason,
    this.hrMaxBpm,
    this.hrRestBpm,
    this.hrMaxIsEstimated,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    if (!nullToAbsent || runId != null) {
      map['run_id'] = Variable<int>(runId);
    }
    if (!nullToAbsent || day != null) {
      map['day'] = Variable<String>(day);
    }
    map['value_key'] = Variable<String>(valueKey);
    map['role'] = Variable<String>(role);
    if (!nullToAbsent || valueReal != null) {
      map['value_real'] = Variable<double>(valueReal);
    }
    map['unit'] = Variable<String>(unit);
    map['computed_at_us'] = Variable<int>(computedAtUs);
    if (!nullToAbsent || dataFromUs != null) {
      map['data_from_us'] = Variable<int>(dataFromUs);
    }
    if (!nullToAbsent || dataToUs != null) {
      map['data_to_us'] = Variable<int>(dataToUs);
    }
    map['measurement_count'] = Variable<int>(measurementCount);
    map['sources'] = Variable<String>(sources);
    map['method'] = Variable<String>(method);
    map['method_version'] = Variable<int>(methodVersion);
    map['parameter_version'] = Variable<int>(parameterVersion);
    map['quality'] = Variable<String>(quality);
    if (!nullToAbsent || unavailableReason != null) {
      map['unavailable_reason'] = Variable<String>(unavailableReason);
    }
    if (!nullToAbsent || hrMaxBpm != null) {
      map['hr_max_bpm'] = Variable<int>(hrMaxBpm);
    }
    if (!nullToAbsent || hrRestBpm != null) {
      map['hr_rest_bpm'] = Variable<int>(hrRestBpm);
    }
    if (!nullToAbsent || hrMaxIsEstimated != null) {
      map['hr_max_is_estimated'] = Variable<bool>(hrMaxIsEstimated);
    }
    return map;
  }

  ComputedValuesCompanion toCompanion(bool nullToAbsent) {
    return ComputedValuesCompanion(
      id: Value(id),
      runId: runId == null && nullToAbsent
          ? const Value.absent()
          : Value(runId),
      day: day == null && nullToAbsent ? const Value.absent() : Value(day),
      valueKey: Value(valueKey),
      role: Value(role),
      valueReal: valueReal == null && nullToAbsent
          ? const Value.absent()
          : Value(valueReal),
      unit: Value(unit),
      computedAtUs: Value(computedAtUs),
      dataFromUs: dataFromUs == null && nullToAbsent
          ? const Value.absent()
          : Value(dataFromUs),
      dataToUs: dataToUs == null && nullToAbsent
          ? const Value.absent()
          : Value(dataToUs),
      measurementCount: Value(measurementCount),
      sources: Value(sources),
      method: Value(method),
      methodVersion: Value(methodVersion),
      parameterVersion: Value(parameterVersion),
      quality: Value(quality),
      unavailableReason: unavailableReason == null && nullToAbsent
          ? const Value.absent()
          : Value(unavailableReason),
      hrMaxBpm: hrMaxBpm == null && nullToAbsent
          ? const Value.absent()
          : Value(hrMaxBpm),
      hrRestBpm: hrRestBpm == null && nullToAbsent
          ? const Value.absent()
          : Value(hrRestBpm),
      hrMaxIsEstimated: hrMaxIsEstimated == null && nullToAbsent
          ? const Value.absent()
          : Value(hrMaxIsEstimated),
    );
  }

  factory ComputedValue.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ComputedValue(
      id: serializer.fromJson<int>(json['id']),
      runId: serializer.fromJson<int?>(json['run_id']),
      day: serializer.fromJson<String?>(json['day']),
      valueKey: serializer.fromJson<String>(json['value_key']),
      role: serializer.fromJson<String>(json['role']),
      valueReal: serializer.fromJson<double?>(json['value_real']),
      unit: serializer.fromJson<String>(json['unit']),
      computedAtUs: serializer.fromJson<int>(json['computed_at_us']),
      dataFromUs: serializer.fromJson<int?>(json['data_from_us']),
      dataToUs: serializer.fromJson<int?>(json['data_to_us']),
      measurementCount: serializer.fromJson<int>(json['measurement_count']),
      sources: serializer.fromJson<String>(json['sources']),
      method: serializer.fromJson<String>(json['method']),
      methodVersion: serializer.fromJson<int>(json['method_version']),
      parameterVersion: serializer.fromJson<int>(json['parameter_version']),
      quality: serializer.fromJson<String>(json['quality']),
      unavailableReason: serializer.fromJson<String?>(
        json['unavailable_reason'],
      ),
      hrMaxBpm: serializer.fromJson<int?>(json['hr_max_bpm']),
      hrRestBpm: serializer.fromJson<int?>(json['hr_rest_bpm']),
      hrMaxIsEstimated: serializer.fromJson<bool?>(json['hr_max_is_estimated']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'run_id': serializer.toJson<int?>(runId),
      'day': serializer.toJson<String?>(day),
      'value_key': serializer.toJson<String>(valueKey),
      'role': serializer.toJson<String>(role),
      'value_real': serializer.toJson<double?>(valueReal),
      'unit': serializer.toJson<String>(unit),
      'computed_at_us': serializer.toJson<int>(computedAtUs),
      'data_from_us': serializer.toJson<int?>(dataFromUs),
      'data_to_us': serializer.toJson<int?>(dataToUs),
      'measurement_count': serializer.toJson<int>(measurementCount),
      'sources': serializer.toJson<String>(sources),
      'method': serializer.toJson<String>(method),
      'method_version': serializer.toJson<int>(methodVersion),
      'parameter_version': serializer.toJson<int>(parameterVersion),
      'quality': serializer.toJson<String>(quality),
      'unavailable_reason': serializer.toJson<String?>(unavailableReason),
      'hr_max_bpm': serializer.toJson<int?>(hrMaxBpm),
      'hr_rest_bpm': serializer.toJson<int?>(hrRestBpm),
      'hr_max_is_estimated': serializer.toJson<bool?>(hrMaxIsEstimated),
    };
  }

  ComputedValue copyWith({
    int? id,
    Value<int?> runId = const Value.absent(),
    Value<String?> day = const Value.absent(),
    String? valueKey,
    String? role,
    Value<double?> valueReal = const Value.absent(),
    String? unit,
    int? computedAtUs,
    Value<int?> dataFromUs = const Value.absent(),
    Value<int?> dataToUs = const Value.absent(),
    int? measurementCount,
    String? sources,
    String? method,
    int? methodVersion,
    int? parameterVersion,
    String? quality,
    Value<String?> unavailableReason = const Value.absent(),
    Value<int?> hrMaxBpm = const Value.absent(),
    Value<int?> hrRestBpm = const Value.absent(),
    Value<bool?> hrMaxIsEstimated = const Value.absent(),
  }) => ComputedValue(
    id: id ?? this.id,
    runId: runId.present ? runId.value : this.runId,
    day: day.present ? day.value : this.day,
    valueKey: valueKey ?? this.valueKey,
    role: role ?? this.role,
    valueReal: valueReal.present ? valueReal.value : this.valueReal,
    unit: unit ?? this.unit,
    computedAtUs: computedAtUs ?? this.computedAtUs,
    dataFromUs: dataFromUs.present ? dataFromUs.value : this.dataFromUs,
    dataToUs: dataToUs.present ? dataToUs.value : this.dataToUs,
    measurementCount: measurementCount ?? this.measurementCount,
    sources: sources ?? this.sources,
    method: method ?? this.method,
    methodVersion: methodVersion ?? this.methodVersion,
    parameterVersion: parameterVersion ?? this.parameterVersion,
    quality: quality ?? this.quality,
    unavailableReason: unavailableReason.present
        ? unavailableReason.value
        : this.unavailableReason,
    hrMaxBpm: hrMaxBpm.present ? hrMaxBpm.value : this.hrMaxBpm,
    hrRestBpm: hrRestBpm.present ? hrRestBpm.value : this.hrRestBpm,
    hrMaxIsEstimated: hrMaxIsEstimated.present
        ? hrMaxIsEstimated.value
        : this.hrMaxIsEstimated,
  );
  ComputedValue copyWithCompanion(ComputedValuesCompanion data) {
    return ComputedValue(
      id: data.id.present ? data.id.value : this.id,
      runId: data.runId.present ? data.runId.value : this.runId,
      day: data.day.present ? data.day.value : this.day,
      valueKey: data.valueKey.present ? data.valueKey.value : this.valueKey,
      role: data.role.present ? data.role.value : this.role,
      valueReal: data.valueReal.present ? data.valueReal.value : this.valueReal,
      unit: data.unit.present ? data.unit.value : this.unit,
      computedAtUs: data.computedAtUs.present
          ? data.computedAtUs.value
          : this.computedAtUs,
      dataFromUs: data.dataFromUs.present
          ? data.dataFromUs.value
          : this.dataFromUs,
      dataToUs: data.dataToUs.present ? data.dataToUs.value : this.dataToUs,
      measurementCount: data.measurementCount.present
          ? data.measurementCount.value
          : this.measurementCount,
      sources: data.sources.present ? data.sources.value : this.sources,
      method: data.method.present ? data.method.value : this.method,
      methodVersion: data.methodVersion.present
          ? data.methodVersion.value
          : this.methodVersion,
      parameterVersion: data.parameterVersion.present
          ? data.parameterVersion.value
          : this.parameterVersion,
      quality: data.quality.present ? data.quality.value : this.quality,
      unavailableReason: data.unavailableReason.present
          ? data.unavailableReason.value
          : this.unavailableReason,
      hrMaxBpm: data.hrMaxBpm.present ? data.hrMaxBpm.value : this.hrMaxBpm,
      hrRestBpm: data.hrRestBpm.present ? data.hrRestBpm.value : this.hrRestBpm,
      hrMaxIsEstimated: data.hrMaxIsEstimated.present
          ? data.hrMaxIsEstimated.value
          : this.hrMaxIsEstimated,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ComputedValue(')
          ..write('id: $id, ')
          ..write('runId: $runId, ')
          ..write('day: $day, ')
          ..write('valueKey: $valueKey, ')
          ..write('role: $role, ')
          ..write('valueReal: $valueReal, ')
          ..write('unit: $unit, ')
          ..write('computedAtUs: $computedAtUs, ')
          ..write('dataFromUs: $dataFromUs, ')
          ..write('dataToUs: $dataToUs, ')
          ..write('measurementCount: $measurementCount, ')
          ..write('sources: $sources, ')
          ..write('method: $method, ')
          ..write('methodVersion: $methodVersion, ')
          ..write('parameterVersion: $parameterVersion, ')
          ..write('quality: $quality, ')
          ..write('unavailableReason: $unavailableReason, ')
          ..write('hrMaxBpm: $hrMaxBpm, ')
          ..write('hrRestBpm: $hrRestBpm, ')
          ..write('hrMaxIsEstimated: $hrMaxIsEstimated')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    runId,
    day,
    valueKey,
    role,
    valueReal,
    unit,
    computedAtUs,
    dataFromUs,
    dataToUs,
    measurementCount,
    sources,
    method,
    methodVersion,
    parameterVersion,
    quality,
    unavailableReason,
    hrMaxBpm,
    hrRestBpm,
    hrMaxIsEstimated,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ComputedValue &&
          other.id == this.id &&
          other.runId == this.runId &&
          other.day == this.day &&
          other.valueKey == this.valueKey &&
          other.role == this.role &&
          other.valueReal == this.valueReal &&
          other.unit == this.unit &&
          other.computedAtUs == this.computedAtUs &&
          other.dataFromUs == this.dataFromUs &&
          other.dataToUs == this.dataToUs &&
          other.measurementCount == this.measurementCount &&
          other.sources == this.sources &&
          other.method == this.method &&
          other.methodVersion == this.methodVersion &&
          other.parameterVersion == this.parameterVersion &&
          other.quality == this.quality &&
          other.unavailableReason == this.unavailableReason &&
          other.hrMaxBpm == this.hrMaxBpm &&
          other.hrRestBpm == this.hrRestBpm &&
          other.hrMaxIsEstimated == this.hrMaxIsEstimated);
}

class ComputedValuesCompanion extends UpdateCompanion<ComputedValue> {
  final Value<int> id;
  final Value<int?> runId;
  final Value<String?> day;
  final Value<String> valueKey;
  final Value<String> role;
  final Value<double?> valueReal;
  final Value<String> unit;
  final Value<int> computedAtUs;
  final Value<int?> dataFromUs;
  final Value<int?> dataToUs;
  final Value<int> measurementCount;
  final Value<String> sources;
  final Value<String> method;
  final Value<int> methodVersion;
  final Value<int> parameterVersion;
  final Value<String> quality;
  final Value<String?> unavailableReason;
  final Value<int?> hrMaxBpm;
  final Value<int?> hrRestBpm;
  final Value<bool?> hrMaxIsEstimated;
  const ComputedValuesCompanion({
    this.id = const Value.absent(),
    this.runId = const Value.absent(),
    this.day = const Value.absent(),
    this.valueKey = const Value.absent(),
    this.role = const Value.absent(),
    this.valueReal = const Value.absent(),
    this.unit = const Value.absent(),
    this.computedAtUs = const Value.absent(),
    this.dataFromUs = const Value.absent(),
    this.dataToUs = const Value.absent(),
    this.measurementCount = const Value.absent(),
    this.sources = const Value.absent(),
    this.method = const Value.absent(),
    this.methodVersion = const Value.absent(),
    this.parameterVersion = const Value.absent(),
    this.quality = const Value.absent(),
    this.unavailableReason = const Value.absent(),
    this.hrMaxBpm = const Value.absent(),
    this.hrRestBpm = const Value.absent(),
    this.hrMaxIsEstimated = const Value.absent(),
  });
  ComputedValuesCompanion.insert({
    this.id = const Value.absent(),
    this.runId = const Value.absent(),
    this.day = const Value.absent(),
    required String valueKey,
    required String role,
    this.valueReal = const Value.absent(),
    required String unit,
    required int computedAtUs,
    this.dataFromUs = const Value.absent(),
    this.dataToUs = const Value.absent(),
    required int measurementCount,
    required String sources,
    required String method,
    required int methodVersion,
    required int parameterVersion,
    required String quality,
    this.unavailableReason = const Value.absent(),
    this.hrMaxBpm = const Value.absent(),
    this.hrRestBpm = const Value.absent(),
    this.hrMaxIsEstimated = const Value.absent(),
  }) : valueKey = Value(valueKey),
       role = Value(role),
       unit = Value(unit),
       computedAtUs = Value(computedAtUs),
       measurementCount = Value(measurementCount),
       sources = Value(sources),
       method = Value(method),
       methodVersion = Value(methodVersion),
       parameterVersion = Value(parameterVersion),
       quality = Value(quality);
  static Insertable<ComputedValue> custom({
    Expression<int>? id,
    Expression<int>? runId,
    Expression<String>? day,
    Expression<String>? valueKey,
    Expression<String>? role,
    Expression<double>? valueReal,
    Expression<String>? unit,
    Expression<int>? computedAtUs,
    Expression<int>? dataFromUs,
    Expression<int>? dataToUs,
    Expression<int>? measurementCount,
    Expression<String>? sources,
    Expression<String>? method,
    Expression<int>? methodVersion,
    Expression<int>? parameterVersion,
    Expression<String>? quality,
    Expression<String>? unavailableReason,
    Expression<int>? hrMaxBpm,
    Expression<int>? hrRestBpm,
    Expression<bool>? hrMaxIsEstimated,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (runId != null) 'run_id': runId,
      if (day != null) 'day': day,
      if (valueKey != null) 'value_key': valueKey,
      if (role != null) 'role': role,
      if (valueReal != null) 'value_real': valueReal,
      if (unit != null) 'unit': unit,
      if (computedAtUs != null) 'computed_at_us': computedAtUs,
      if (dataFromUs != null) 'data_from_us': dataFromUs,
      if (dataToUs != null) 'data_to_us': dataToUs,
      if (measurementCount != null) 'measurement_count': measurementCount,
      if (sources != null) 'sources': sources,
      if (method != null) 'method': method,
      if (methodVersion != null) 'method_version': methodVersion,
      if (parameterVersion != null) 'parameter_version': parameterVersion,
      if (quality != null) 'quality': quality,
      if (unavailableReason != null) 'unavailable_reason': unavailableReason,
      if (hrMaxBpm != null) 'hr_max_bpm': hrMaxBpm,
      if (hrRestBpm != null) 'hr_rest_bpm': hrRestBpm,
      if (hrMaxIsEstimated != null) 'hr_max_is_estimated': hrMaxIsEstimated,
    });
  }

  ComputedValuesCompanion copyWith({
    Value<int>? id,
    Value<int?>? runId,
    Value<String?>? day,
    Value<String>? valueKey,
    Value<String>? role,
    Value<double?>? valueReal,
    Value<String>? unit,
    Value<int>? computedAtUs,
    Value<int?>? dataFromUs,
    Value<int?>? dataToUs,
    Value<int>? measurementCount,
    Value<String>? sources,
    Value<String>? method,
    Value<int>? methodVersion,
    Value<int>? parameterVersion,
    Value<String>? quality,
    Value<String?>? unavailableReason,
    Value<int?>? hrMaxBpm,
    Value<int?>? hrRestBpm,
    Value<bool?>? hrMaxIsEstimated,
  }) {
    return ComputedValuesCompanion(
      id: id ?? this.id,
      runId: runId ?? this.runId,
      day: day ?? this.day,
      valueKey: valueKey ?? this.valueKey,
      role: role ?? this.role,
      valueReal: valueReal ?? this.valueReal,
      unit: unit ?? this.unit,
      computedAtUs: computedAtUs ?? this.computedAtUs,
      dataFromUs: dataFromUs ?? this.dataFromUs,
      dataToUs: dataToUs ?? this.dataToUs,
      measurementCount: measurementCount ?? this.measurementCount,
      sources: sources ?? this.sources,
      method: method ?? this.method,
      methodVersion: methodVersion ?? this.methodVersion,
      parameterVersion: parameterVersion ?? this.parameterVersion,
      quality: quality ?? this.quality,
      unavailableReason: unavailableReason ?? this.unavailableReason,
      hrMaxBpm: hrMaxBpm ?? this.hrMaxBpm,
      hrRestBpm: hrRestBpm ?? this.hrRestBpm,
      hrMaxIsEstimated: hrMaxIsEstimated ?? this.hrMaxIsEstimated,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (runId.present) {
      map['run_id'] = Variable<int>(runId.value);
    }
    if (day.present) {
      map['day'] = Variable<String>(day.value);
    }
    if (valueKey.present) {
      map['value_key'] = Variable<String>(valueKey.value);
    }
    if (role.present) {
      map['role'] = Variable<String>(role.value);
    }
    if (valueReal.present) {
      map['value_real'] = Variable<double>(valueReal.value);
    }
    if (unit.present) {
      map['unit'] = Variable<String>(unit.value);
    }
    if (computedAtUs.present) {
      map['computed_at_us'] = Variable<int>(computedAtUs.value);
    }
    if (dataFromUs.present) {
      map['data_from_us'] = Variable<int>(dataFromUs.value);
    }
    if (dataToUs.present) {
      map['data_to_us'] = Variable<int>(dataToUs.value);
    }
    if (measurementCount.present) {
      map['measurement_count'] = Variable<int>(measurementCount.value);
    }
    if (sources.present) {
      map['sources'] = Variable<String>(sources.value);
    }
    if (method.present) {
      map['method'] = Variable<String>(method.value);
    }
    if (methodVersion.present) {
      map['method_version'] = Variable<int>(methodVersion.value);
    }
    if (parameterVersion.present) {
      map['parameter_version'] = Variable<int>(parameterVersion.value);
    }
    if (quality.present) {
      map['quality'] = Variable<String>(quality.value);
    }
    if (unavailableReason.present) {
      map['unavailable_reason'] = Variable<String>(unavailableReason.value);
    }
    if (hrMaxBpm.present) {
      map['hr_max_bpm'] = Variable<int>(hrMaxBpm.value);
    }
    if (hrRestBpm.present) {
      map['hr_rest_bpm'] = Variable<int>(hrRestBpm.value);
    }
    if (hrMaxIsEstimated.present) {
      map['hr_max_is_estimated'] = Variable<bool>(hrMaxIsEstimated.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ComputedValuesCompanion(')
          ..write('id: $id, ')
          ..write('runId: $runId, ')
          ..write('day: $day, ')
          ..write('valueKey: $valueKey, ')
          ..write('role: $role, ')
          ..write('valueReal: $valueReal, ')
          ..write('unit: $unit, ')
          ..write('computedAtUs: $computedAtUs, ')
          ..write('dataFromUs: $dataFromUs, ')
          ..write('dataToUs: $dataToUs, ')
          ..write('measurementCount: $measurementCount, ')
          ..write('sources: $sources, ')
          ..write('method: $method, ')
          ..write('methodVersion: $methodVersion, ')
          ..write('parameterVersion: $parameterVersion, ')
          ..write('quality: $quality, ')
          ..write('unavailableReason: $unavailableReason, ')
          ..write('hrMaxBpm: $hrMaxBpm, ')
          ..write('hrRestBpm: $hrRestBpm, ')
          ..write('hrMaxIsEstimated: $hrMaxIsEstimated')
          ..write(')'))
        .toString();
  }
}

class ValueSections extends Table
    with TableInfo<ValueSections, ValueSectionRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  ValueSections(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL PRIMARY KEY AUTOINCREMENT',
  );
  static const VerificationMeta _computedValueIdMeta = const VerificationMeta(
    'computedValueId',
  );
  late final GeneratedColumn<int> computedValueId = GeneratedColumn<int>(
    'computed_value_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints:
        'NOT NULL REFERENCES computed_values(id)ON DELETE CASCADE',
  );
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (position >= 0)',
  );
  static const VerificationMeta _startUsMeta = const VerificationMeta(
    'startUs',
  );
  late final GeneratedColumn<int> startUs = GeneratedColumn<int>(
    'start_us',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _endUsMeta = const VerificationMeta('endUs');
  late final GeneratedColumn<int> endUs = GeneratedColumn<int>(
    'end_us',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (end_us >= start_us)',
  );
  static const VerificationMeta _gpsMedianAccuracyMMeta =
      const VerificationMeta('gpsMedianAccuracyM');
  late final GeneratedColumn<double> gpsMedianAccuracyM =
      GeneratedColumn<double>(
        'gps_median_accuracy_m',
        aliasedName,
        true,
        type: DriftSqlType.double,
        requiredDuringInsert: false,
        $customConstraints: 'CHECK (gps_median_accuracy_m >= 0)',
      );
  static const VerificationMeta _weightMeta = const VerificationMeta('weight');
  late final GeneratedColumn<double> weight = GeneratedColumn<double>(
    'weight',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (weight >= 0)',
  );
  static const VerificationMeta _lateFactorMeta = const VerificationMeta(
    'lateFactor',
  );
  late final GeneratedColumn<double> lateFactor = GeneratedColumn<double>(
    'late_factor',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (late_factor >= 0)',
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (status IN (\'eligible\', \'provisional\', \'rejected\'))',
  );
  static const VerificationMeta _discardMeta = const VerificationMeta(
    'discard',
  );
  late final GeneratedColumn<String> discard = GeneratedColumn<String>(
    'discard',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints:
        'CHECK (discard IN (\'implausible\', \'incomplete\', \'zeroWeight\'))',
  );
  static const VerificationMeta _reasonsMeta = const VerificationMeta(
    'reasons',
  );
  late final GeneratedColumn<String> reasons = GeneratedColumn<String>(
    'reasons',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (json_valid(reasons))',
  );
  static const VerificationMeta _oxygenDemandMeta = const VerificationMeta(
    'oxygenDemand',
  );
  late final GeneratedColumn<double> oxygenDemand = GeneratedColumn<double>(
    'oxygen_demand',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _estimateMeta = const VerificationMeta(
    'estimate',
  );
  late final GeneratedColumn<double> estimate = GeneratedColumn<double>(
    'estimate',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    computedValueId,
    position,
    startUs,
    endUs,
    gpsMedianAccuracyM,
    weight,
    lateFactor,
    status,
    discard,
    reasons,
    oxygenDemand,
    estimate,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'value_sections';
  @override
  VerificationContext validateIntegrity(
    Insertable<ValueSectionRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('computed_value_id')) {
      context.handle(
        _computedValueIdMeta,
        computedValueId.isAcceptableOrUnknown(
          data['computed_value_id']!,
          _computedValueIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_computedValueIdMeta);
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    } else if (isInserting) {
      context.missing(_positionMeta);
    }
    if (data.containsKey('start_us')) {
      context.handle(
        _startUsMeta,
        startUs.isAcceptableOrUnknown(data['start_us']!, _startUsMeta),
      );
    } else if (isInserting) {
      context.missing(_startUsMeta);
    }
    if (data.containsKey('end_us')) {
      context.handle(
        _endUsMeta,
        endUs.isAcceptableOrUnknown(data['end_us']!, _endUsMeta),
      );
    } else if (isInserting) {
      context.missing(_endUsMeta);
    }
    if (data.containsKey('gps_median_accuracy_m')) {
      context.handle(
        _gpsMedianAccuracyMMeta,
        gpsMedianAccuracyM.isAcceptableOrUnknown(
          data['gps_median_accuracy_m']!,
          _gpsMedianAccuracyMMeta,
        ),
      );
    }
    if (data.containsKey('weight')) {
      context.handle(
        _weightMeta,
        weight.isAcceptableOrUnknown(data['weight']!, _weightMeta),
      );
    } else if (isInserting) {
      context.missing(_weightMeta);
    }
    if (data.containsKey('late_factor')) {
      context.handle(
        _lateFactorMeta,
        lateFactor.isAcceptableOrUnknown(data['late_factor']!, _lateFactorMeta),
      );
    } else if (isInserting) {
      context.missing(_lateFactorMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('discard')) {
      context.handle(
        _discardMeta,
        discard.isAcceptableOrUnknown(data['discard']!, _discardMeta),
      );
    }
    if (data.containsKey('reasons')) {
      context.handle(
        _reasonsMeta,
        reasons.isAcceptableOrUnknown(data['reasons']!, _reasonsMeta),
      );
    } else if (isInserting) {
      context.missing(_reasonsMeta);
    }
    if (data.containsKey('oxygen_demand')) {
      context.handle(
        _oxygenDemandMeta,
        oxygenDemand.isAcceptableOrUnknown(
          data['oxygen_demand']!,
          _oxygenDemandMeta,
        ),
      );
    }
    if (data.containsKey('estimate')) {
      context.handle(
        _estimateMeta,
        estimate.isAcceptableOrUnknown(data['estimate']!, _estimateMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {computedValueId, position},
  ];
  @override
  ValueSectionRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ValueSectionRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      computedValueId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}computed_value_id'],
      )!,
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position'],
      )!,
      startUs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}start_us'],
      )!,
      endUs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}end_us'],
      )!,
      gpsMedianAccuracyM: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}gps_median_accuracy_m'],
      ),
      weight: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}weight'],
      )!,
      lateFactor: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}late_factor'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      discard: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}discard'],
      ),
      reasons: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reasons'],
      )!,
      oxygenDemand: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}oxygen_demand'],
      ),
      estimate: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}estimate'],
      ),
    );
  }

  @override
  ValueSections createAlias(String alias) {
    return ValueSections(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints => const [
    'UNIQUE(computed_value_id, position)',
  ];
  @override
  bool get dontWriteConstraints => true;
}

class ValueSectionRow extends DataClass implements Insertable<ValueSectionRow> {
  final int id;
  final int computedValueId;
  final int position;
  final int startUs;
  final int endUs;

  /// NULL, wenn keine Genauigkeit gemeldet wurde.
  final double? gpsMedianAccuracyM;
  final double weight;
  final double lateFactor;
  final String status;
  final String? discard;
  final String reasons;
  final double? oxygenDemand;
  final double? estimate;
  const ValueSectionRow({
    required this.id,
    required this.computedValueId,
    required this.position,
    required this.startUs,
    required this.endUs,
    this.gpsMedianAccuracyM,
    required this.weight,
    required this.lateFactor,
    required this.status,
    this.discard,
    required this.reasons,
    this.oxygenDemand,
    this.estimate,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['computed_value_id'] = Variable<int>(computedValueId);
    map['position'] = Variable<int>(position);
    map['start_us'] = Variable<int>(startUs);
    map['end_us'] = Variable<int>(endUs);
    if (!nullToAbsent || gpsMedianAccuracyM != null) {
      map['gps_median_accuracy_m'] = Variable<double>(gpsMedianAccuracyM);
    }
    map['weight'] = Variable<double>(weight);
    map['late_factor'] = Variable<double>(lateFactor);
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || discard != null) {
      map['discard'] = Variable<String>(discard);
    }
    map['reasons'] = Variable<String>(reasons);
    if (!nullToAbsent || oxygenDemand != null) {
      map['oxygen_demand'] = Variable<double>(oxygenDemand);
    }
    if (!nullToAbsent || estimate != null) {
      map['estimate'] = Variable<double>(estimate);
    }
    return map;
  }

  ValueSectionsCompanion toCompanion(bool nullToAbsent) {
    return ValueSectionsCompanion(
      id: Value(id),
      computedValueId: Value(computedValueId),
      position: Value(position),
      startUs: Value(startUs),
      endUs: Value(endUs),
      gpsMedianAccuracyM: gpsMedianAccuracyM == null && nullToAbsent
          ? const Value.absent()
          : Value(gpsMedianAccuracyM),
      weight: Value(weight),
      lateFactor: Value(lateFactor),
      status: Value(status),
      discard: discard == null && nullToAbsent
          ? const Value.absent()
          : Value(discard),
      reasons: Value(reasons),
      oxygenDemand: oxygenDemand == null && nullToAbsent
          ? const Value.absent()
          : Value(oxygenDemand),
      estimate: estimate == null && nullToAbsent
          ? const Value.absent()
          : Value(estimate),
    );
  }

  factory ValueSectionRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ValueSectionRow(
      id: serializer.fromJson<int>(json['id']),
      computedValueId: serializer.fromJson<int>(json['computed_value_id']),
      position: serializer.fromJson<int>(json['position']),
      startUs: serializer.fromJson<int>(json['start_us']),
      endUs: serializer.fromJson<int>(json['end_us']),
      gpsMedianAccuracyM: serializer.fromJson<double?>(
        json['gps_median_accuracy_m'],
      ),
      weight: serializer.fromJson<double>(json['weight']),
      lateFactor: serializer.fromJson<double>(json['late_factor']),
      status: serializer.fromJson<String>(json['status']),
      discard: serializer.fromJson<String?>(json['discard']),
      reasons: serializer.fromJson<String>(json['reasons']),
      oxygenDemand: serializer.fromJson<double?>(json['oxygen_demand']),
      estimate: serializer.fromJson<double?>(json['estimate']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'computed_value_id': serializer.toJson<int>(computedValueId),
      'position': serializer.toJson<int>(position),
      'start_us': serializer.toJson<int>(startUs),
      'end_us': serializer.toJson<int>(endUs),
      'gps_median_accuracy_m': serializer.toJson<double?>(gpsMedianAccuracyM),
      'weight': serializer.toJson<double>(weight),
      'late_factor': serializer.toJson<double>(lateFactor),
      'status': serializer.toJson<String>(status),
      'discard': serializer.toJson<String?>(discard),
      'reasons': serializer.toJson<String>(reasons),
      'oxygen_demand': serializer.toJson<double?>(oxygenDemand),
      'estimate': serializer.toJson<double?>(estimate),
    };
  }

  ValueSectionRow copyWith({
    int? id,
    int? computedValueId,
    int? position,
    int? startUs,
    int? endUs,
    Value<double?> gpsMedianAccuracyM = const Value.absent(),
    double? weight,
    double? lateFactor,
    String? status,
    Value<String?> discard = const Value.absent(),
    String? reasons,
    Value<double?> oxygenDemand = const Value.absent(),
    Value<double?> estimate = const Value.absent(),
  }) => ValueSectionRow(
    id: id ?? this.id,
    computedValueId: computedValueId ?? this.computedValueId,
    position: position ?? this.position,
    startUs: startUs ?? this.startUs,
    endUs: endUs ?? this.endUs,
    gpsMedianAccuracyM: gpsMedianAccuracyM.present
        ? gpsMedianAccuracyM.value
        : this.gpsMedianAccuracyM,
    weight: weight ?? this.weight,
    lateFactor: lateFactor ?? this.lateFactor,
    status: status ?? this.status,
    discard: discard.present ? discard.value : this.discard,
    reasons: reasons ?? this.reasons,
    oxygenDemand: oxygenDemand.present ? oxygenDemand.value : this.oxygenDemand,
    estimate: estimate.present ? estimate.value : this.estimate,
  );
  ValueSectionRow copyWithCompanion(ValueSectionsCompanion data) {
    return ValueSectionRow(
      id: data.id.present ? data.id.value : this.id,
      computedValueId: data.computedValueId.present
          ? data.computedValueId.value
          : this.computedValueId,
      position: data.position.present ? data.position.value : this.position,
      startUs: data.startUs.present ? data.startUs.value : this.startUs,
      endUs: data.endUs.present ? data.endUs.value : this.endUs,
      gpsMedianAccuracyM: data.gpsMedianAccuracyM.present
          ? data.gpsMedianAccuracyM.value
          : this.gpsMedianAccuracyM,
      weight: data.weight.present ? data.weight.value : this.weight,
      lateFactor: data.lateFactor.present
          ? data.lateFactor.value
          : this.lateFactor,
      status: data.status.present ? data.status.value : this.status,
      discard: data.discard.present ? data.discard.value : this.discard,
      reasons: data.reasons.present ? data.reasons.value : this.reasons,
      oxygenDemand: data.oxygenDemand.present
          ? data.oxygenDemand.value
          : this.oxygenDemand,
      estimate: data.estimate.present ? data.estimate.value : this.estimate,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ValueSectionRow(')
          ..write('id: $id, ')
          ..write('computedValueId: $computedValueId, ')
          ..write('position: $position, ')
          ..write('startUs: $startUs, ')
          ..write('endUs: $endUs, ')
          ..write('gpsMedianAccuracyM: $gpsMedianAccuracyM, ')
          ..write('weight: $weight, ')
          ..write('lateFactor: $lateFactor, ')
          ..write('status: $status, ')
          ..write('discard: $discard, ')
          ..write('reasons: $reasons, ')
          ..write('oxygenDemand: $oxygenDemand, ')
          ..write('estimate: $estimate')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    computedValueId,
    position,
    startUs,
    endUs,
    gpsMedianAccuracyM,
    weight,
    lateFactor,
    status,
    discard,
    reasons,
    oxygenDemand,
    estimate,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ValueSectionRow &&
          other.id == this.id &&
          other.computedValueId == this.computedValueId &&
          other.position == this.position &&
          other.startUs == this.startUs &&
          other.endUs == this.endUs &&
          other.gpsMedianAccuracyM == this.gpsMedianAccuracyM &&
          other.weight == this.weight &&
          other.lateFactor == this.lateFactor &&
          other.status == this.status &&
          other.discard == this.discard &&
          other.reasons == this.reasons &&
          other.oxygenDemand == this.oxygenDemand &&
          other.estimate == this.estimate);
}

class ValueSectionsCompanion extends UpdateCompanion<ValueSectionRow> {
  final Value<int> id;
  final Value<int> computedValueId;
  final Value<int> position;
  final Value<int> startUs;
  final Value<int> endUs;
  final Value<double?> gpsMedianAccuracyM;
  final Value<double> weight;
  final Value<double> lateFactor;
  final Value<String> status;
  final Value<String?> discard;
  final Value<String> reasons;
  final Value<double?> oxygenDemand;
  final Value<double?> estimate;
  const ValueSectionsCompanion({
    this.id = const Value.absent(),
    this.computedValueId = const Value.absent(),
    this.position = const Value.absent(),
    this.startUs = const Value.absent(),
    this.endUs = const Value.absent(),
    this.gpsMedianAccuracyM = const Value.absent(),
    this.weight = const Value.absent(),
    this.lateFactor = const Value.absent(),
    this.status = const Value.absent(),
    this.discard = const Value.absent(),
    this.reasons = const Value.absent(),
    this.oxygenDemand = const Value.absent(),
    this.estimate = const Value.absent(),
  });
  ValueSectionsCompanion.insert({
    this.id = const Value.absent(),
    required int computedValueId,
    required int position,
    required int startUs,
    required int endUs,
    this.gpsMedianAccuracyM = const Value.absent(),
    required double weight,
    required double lateFactor,
    required String status,
    this.discard = const Value.absent(),
    required String reasons,
    this.oxygenDemand = const Value.absent(),
    this.estimate = const Value.absent(),
  }) : computedValueId = Value(computedValueId),
       position = Value(position),
       startUs = Value(startUs),
       endUs = Value(endUs),
       weight = Value(weight),
       lateFactor = Value(lateFactor),
       status = Value(status),
       reasons = Value(reasons);
  static Insertable<ValueSectionRow> custom({
    Expression<int>? id,
    Expression<int>? computedValueId,
    Expression<int>? position,
    Expression<int>? startUs,
    Expression<int>? endUs,
    Expression<double>? gpsMedianAccuracyM,
    Expression<double>? weight,
    Expression<double>? lateFactor,
    Expression<String>? status,
    Expression<String>? discard,
    Expression<String>? reasons,
    Expression<double>? oxygenDemand,
    Expression<double>? estimate,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (computedValueId != null) 'computed_value_id': computedValueId,
      if (position != null) 'position': position,
      if (startUs != null) 'start_us': startUs,
      if (endUs != null) 'end_us': endUs,
      if (gpsMedianAccuracyM != null)
        'gps_median_accuracy_m': gpsMedianAccuracyM,
      if (weight != null) 'weight': weight,
      if (lateFactor != null) 'late_factor': lateFactor,
      if (status != null) 'status': status,
      if (discard != null) 'discard': discard,
      if (reasons != null) 'reasons': reasons,
      if (oxygenDemand != null) 'oxygen_demand': oxygenDemand,
      if (estimate != null) 'estimate': estimate,
    });
  }

  ValueSectionsCompanion copyWith({
    Value<int>? id,
    Value<int>? computedValueId,
    Value<int>? position,
    Value<int>? startUs,
    Value<int>? endUs,
    Value<double?>? gpsMedianAccuracyM,
    Value<double>? weight,
    Value<double>? lateFactor,
    Value<String>? status,
    Value<String?>? discard,
    Value<String>? reasons,
    Value<double?>? oxygenDemand,
    Value<double?>? estimate,
  }) {
    return ValueSectionsCompanion(
      id: id ?? this.id,
      computedValueId: computedValueId ?? this.computedValueId,
      position: position ?? this.position,
      startUs: startUs ?? this.startUs,
      endUs: endUs ?? this.endUs,
      gpsMedianAccuracyM: gpsMedianAccuracyM ?? this.gpsMedianAccuracyM,
      weight: weight ?? this.weight,
      lateFactor: lateFactor ?? this.lateFactor,
      status: status ?? this.status,
      discard: discard ?? this.discard,
      reasons: reasons ?? this.reasons,
      oxygenDemand: oxygenDemand ?? this.oxygenDemand,
      estimate: estimate ?? this.estimate,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (computedValueId.present) {
      map['computed_value_id'] = Variable<int>(computedValueId.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (startUs.present) {
      map['start_us'] = Variable<int>(startUs.value);
    }
    if (endUs.present) {
      map['end_us'] = Variable<int>(endUs.value);
    }
    if (gpsMedianAccuracyM.present) {
      map['gps_median_accuracy_m'] = Variable<double>(gpsMedianAccuracyM.value);
    }
    if (weight.present) {
      map['weight'] = Variable<double>(weight.value);
    }
    if (lateFactor.present) {
      map['late_factor'] = Variable<double>(lateFactor.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (discard.present) {
      map['discard'] = Variable<String>(discard.value);
    }
    if (reasons.present) {
      map['reasons'] = Variable<String>(reasons.value);
    }
    if (oxygenDemand.present) {
      map['oxygen_demand'] = Variable<double>(oxygenDemand.value);
    }
    if (estimate.present) {
      map['estimate'] = Variable<double>(estimate.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ValueSectionsCompanion(')
          ..write('id: $id, ')
          ..write('computedValueId: $computedValueId, ')
          ..write('position: $position, ')
          ..write('startUs: $startUs, ')
          ..write('endUs: $endUs, ')
          ..write('gpsMedianAccuracyM: $gpsMedianAccuracyM, ')
          ..write('weight: $weight, ')
          ..write('lateFactor: $lateFactor, ')
          ..write('status: $status, ')
          ..write('discard: $discard, ')
          ..write('reasons: $reasons, ')
          ..write('oxygenDemand: $oxygenDemand, ')
          ..write('estimate: $estimate')
          ..write(')'))
        .toString();
  }
}

class Profile extends Table with TableInfo<Profile, ProfileData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  Profile(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL PRIMARY KEY CHECK (id = 1)',
  );
  static const VerificationMeta _birthYearMeta = const VerificationMeta(
    'birthYear',
  );
  late final GeneratedColumn<int> birthYear = GeneratedColumn<int>(
    'birth_year',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: 'CHECK (birth_year > 0)',
  );
  static const VerificationMeta _bodyWeightKgMeta = const VerificationMeta(
    'bodyWeightKg',
  );
  late final GeneratedColumn<double> bodyWeightKg = GeneratedColumn<double>(
    'body_weight_kg',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    $customConstraints: 'CHECK (body_weight_kg > 0)',
  );
  static const VerificationMeta _bodyHeightMMeta = const VerificationMeta(
    'bodyHeightM',
  );
  late final GeneratedColumn<double> bodyHeightM = GeneratedColumn<double>(
    'body_height_m',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    $customConstraints: 'CHECK (body_height_m > 0)',
  );
  static const VerificationMeta _restingHeartRateBpmMeta =
      const VerificationMeta('restingHeartRateBpm');
  late final GeneratedColumn<int> restingHeartRateBpm = GeneratedColumn<int>(
    'resting_heart_rate_bpm',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _maxHeartRateBpmMeta = const VerificationMeta(
    'maxHeartRateBpm',
  );
  late final GeneratedColumn<int> maxHeartRateBpm = GeneratedColumn<int>(
    'max_heart_rate_bpm',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _weeklyRunMinutesMeta = const VerificationMeta(
    'weeklyRunMinutes',
  );
  late final GeneratedColumn<int> weeklyRunMinutes = GeneratedColumn<int>(
    'weekly_run_minutes',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _trainingDaysMaskMeta = const VerificationMeta(
    'trainingDaysMask',
  );
  late final GeneratedColumn<int> trainingDaysMask = GeneratedColumn<int>(
    'training_days_mask',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: 'CHECK (training_days_mask BETWEEN 0 AND 127)',
  );
  static const VerificationMeta _usualTrainingMinutesMeta =
      const VerificationMeta('usualTrainingMinutes');
  late final GeneratedColumn<int> usualTrainingMinutes = GeneratedColumn<int>(
    'usual_training_minutes',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    birthYear,
    bodyWeightKg,
    bodyHeightM,
    restingHeartRateBpm,
    maxHeartRateBpm,
    weeklyRunMinutes,
    trainingDaysMask,
    usualTrainingMinutes,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'profile';
  @override
  VerificationContext validateIntegrity(
    Insertable<ProfileData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('birth_year')) {
      context.handle(
        _birthYearMeta,
        birthYear.isAcceptableOrUnknown(data['birth_year']!, _birthYearMeta),
      );
    }
    if (data.containsKey('body_weight_kg')) {
      context.handle(
        _bodyWeightKgMeta,
        bodyWeightKg.isAcceptableOrUnknown(
          data['body_weight_kg']!,
          _bodyWeightKgMeta,
        ),
      );
    }
    if (data.containsKey('body_height_m')) {
      context.handle(
        _bodyHeightMMeta,
        bodyHeightM.isAcceptableOrUnknown(
          data['body_height_m']!,
          _bodyHeightMMeta,
        ),
      );
    }
    if (data.containsKey('resting_heart_rate_bpm')) {
      context.handle(
        _restingHeartRateBpmMeta,
        restingHeartRateBpm.isAcceptableOrUnknown(
          data['resting_heart_rate_bpm']!,
          _restingHeartRateBpmMeta,
        ),
      );
    }
    if (data.containsKey('max_heart_rate_bpm')) {
      context.handle(
        _maxHeartRateBpmMeta,
        maxHeartRateBpm.isAcceptableOrUnknown(
          data['max_heart_rate_bpm']!,
          _maxHeartRateBpmMeta,
        ),
      );
    }
    if (data.containsKey('weekly_run_minutes')) {
      context.handle(
        _weeklyRunMinutesMeta,
        weeklyRunMinutes.isAcceptableOrUnknown(
          data['weekly_run_minutes']!,
          _weeklyRunMinutesMeta,
        ),
      );
    }
    if (data.containsKey('training_days_mask')) {
      context.handle(
        _trainingDaysMaskMeta,
        trainingDaysMask.isAcceptableOrUnknown(
          data['training_days_mask']!,
          _trainingDaysMaskMeta,
        ),
      );
    }
    if (data.containsKey('usual_training_minutes')) {
      context.handle(
        _usualTrainingMinutesMeta,
        usualTrainingMinutes.isAcceptableOrUnknown(
          data['usual_training_minutes']!,
          _usualTrainingMinutesMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ProfileData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ProfileData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      birthYear: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}birth_year'],
      ),
      bodyWeightKg: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}body_weight_kg'],
      ),
      bodyHeightM: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}body_height_m'],
      ),
      restingHeartRateBpm: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}resting_heart_rate_bpm'],
      ),
      maxHeartRateBpm: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}max_heart_rate_bpm'],
      ),
      weeklyRunMinutes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}weekly_run_minutes'],
      ),
      trainingDaysMask: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}training_days_mask'],
      ),
      usualTrainingMinutes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}usual_training_minutes'],
      ),
    );
  }

  @override
  Profile createAlias(String alias) {
    return Profile(attachedDatabase, alias);
  }

  @override
  bool get dontWriteConstraints => true;
}

class ProfileData extends DataClass implements Insertable<ProfileData> {
  final int id;
  final int? birthYear;
  final double? bodyWeightKg;
  final double? bodyHeightM;
  final int? restingHeartRateBpm;
  final int? maxHeartRateBpm;
  final int? weeklyRunMinutes;

  /// Bitmaske Montag = Bit 0 bis Sonntag = Bit 6.
  final int? trainingDaysMask;
  final int? usualTrainingMinutes;
  const ProfileData({
    required this.id,
    this.birthYear,
    this.bodyWeightKg,
    this.bodyHeightM,
    this.restingHeartRateBpm,
    this.maxHeartRateBpm,
    this.weeklyRunMinutes,
    this.trainingDaysMask,
    this.usualTrainingMinutes,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    if (!nullToAbsent || birthYear != null) {
      map['birth_year'] = Variable<int>(birthYear);
    }
    if (!nullToAbsent || bodyWeightKg != null) {
      map['body_weight_kg'] = Variable<double>(bodyWeightKg);
    }
    if (!nullToAbsent || bodyHeightM != null) {
      map['body_height_m'] = Variable<double>(bodyHeightM);
    }
    if (!nullToAbsent || restingHeartRateBpm != null) {
      map['resting_heart_rate_bpm'] = Variable<int>(restingHeartRateBpm);
    }
    if (!nullToAbsent || maxHeartRateBpm != null) {
      map['max_heart_rate_bpm'] = Variable<int>(maxHeartRateBpm);
    }
    if (!nullToAbsent || weeklyRunMinutes != null) {
      map['weekly_run_minutes'] = Variable<int>(weeklyRunMinutes);
    }
    if (!nullToAbsent || trainingDaysMask != null) {
      map['training_days_mask'] = Variable<int>(trainingDaysMask);
    }
    if (!nullToAbsent || usualTrainingMinutes != null) {
      map['usual_training_minutes'] = Variable<int>(usualTrainingMinutes);
    }
    return map;
  }

  ProfileCompanion toCompanion(bool nullToAbsent) {
    return ProfileCompanion(
      id: Value(id),
      birthYear: birthYear == null && nullToAbsent
          ? const Value.absent()
          : Value(birthYear),
      bodyWeightKg: bodyWeightKg == null && nullToAbsent
          ? const Value.absent()
          : Value(bodyWeightKg),
      bodyHeightM: bodyHeightM == null && nullToAbsent
          ? const Value.absent()
          : Value(bodyHeightM),
      restingHeartRateBpm: restingHeartRateBpm == null && nullToAbsent
          ? const Value.absent()
          : Value(restingHeartRateBpm),
      maxHeartRateBpm: maxHeartRateBpm == null && nullToAbsent
          ? const Value.absent()
          : Value(maxHeartRateBpm),
      weeklyRunMinutes: weeklyRunMinutes == null && nullToAbsent
          ? const Value.absent()
          : Value(weeklyRunMinutes),
      trainingDaysMask: trainingDaysMask == null && nullToAbsent
          ? const Value.absent()
          : Value(trainingDaysMask),
      usualTrainingMinutes: usualTrainingMinutes == null && nullToAbsent
          ? const Value.absent()
          : Value(usualTrainingMinutes),
    );
  }

  factory ProfileData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ProfileData(
      id: serializer.fromJson<int>(json['id']),
      birthYear: serializer.fromJson<int?>(json['birth_year']),
      bodyWeightKg: serializer.fromJson<double?>(json['body_weight_kg']),
      bodyHeightM: serializer.fromJson<double?>(json['body_height_m']),
      restingHeartRateBpm: serializer.fromJson<int?>(
        json['resting_heart_rate_bpm'],
      ),
      maxHeartRateBpm: serializer.fromJson<int?>(json['max_heart_rate_bpm']),
      weeklyRunMinutes: serializer.fromJson<int?>(json['weekly_run_minutes']),
      trainingDaysMask: serializer.fromJson<int?>(json['training_days_mask']),
      usualTrainingMinutes: serializer.fromJson<int?>(
        json['usual_training_minutes'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'birth_year': serializer.toJson<int?>(birthYear),
      'body_weight_kg': serializer.toJson<double?>(bodyWeightKg),
      'body_height_m': serializer.toJson<double?>(bodyHeightM),
      'resting_heart_rate_bpm': serializer.toJson<int?>(restingHeartRateBpm),
      'max_heart_rate_bpm': serializer.toJson<int?>(maxHeartRateBpm),
      'weekly_run_minutes': serializer.toJson<int?>(weeklyRunMinutes),
      'training_days_mask': serializer.toJson<int?>(trainingDaysMask),
      'usual_training_minutes': serializer.toJson<int?>(usualTrainingMinutes),
    };
  }

  ProfileData copyWith({
    int? id,
    Value<int?> birthYear = const Value.absent(),
    Value<double?> bodyWeightKg = const Value.absent(),
    Value<double?> bodyHeightM = const Value.absent(),
    Value<int?> restingHeartRateBpm = const Value.absent(),
    Value<int?> maxHeartRateBpm = const Value.absent(),
    Value<int?> weeklyRunMinutes = const Value.absent(),
    Value<int?> trainingDaysMask = const Value.absent(),
    Value<int?> usualTrainingMinutes = const Value.absent(),
  }) => ProfileData(
    id: id ?? this.id,
    birthYear: birthYear.present ? birthYear.value : this.birthYear,
    bodyWeightKg: bodyWeightKg.present ? bodyWeightKg.value : this.bodyWeightKg,
    bodyHeightM: bodyHeightM.present ? bodyHeightM.value : this.bodyHeightM,
    restingHeartRateBpm: restingHeartRateBpm.present
        ? restingHeartRateBpm.value
        : this.restingHeartRateBpm,
    maxHeartRateBpm: maxHeartRateBpm.present
        ? maxHeartRateBpm.value
        : this.maxHeartRateBpm,
    weeklyRunMinutes: weeklyRunMinutes.present
        ? weeklyRunMinutes.value
        : this.weeklyRunMinutes,
    trainingDaysMask: trainingDaysMask.present
        ? trainingDaysMask.value
        : this.trainingDaysMask,
    usualTrainingMinutes: usualTrainingMinutes.present
        ? usualTrainingMinutes.value
        : this.usualTrainingMinutes,
  );
  ProfileData copyWithCompanion(ProfileCompanion data) {
    return ProfileData(
      id: data.id.present ? data.id.value : this.id,
      birthYear: data.birthYear.present ? data.birthYear.value : this.birthYear,
      bodyWeightKg: data.bodyWeightKg.present
          ? data.bodyWeightKg.value
          : this.bodyWeightKg,
      bodyHeightM: data.bodyHeightM.present
          ? data.bodyHeightM.value
          : this.bodyHeightM,
      restingHeartRateBpm: data.restingHeartRateBpm.present
          ? data.restingHeartRateBpm.value
          : this.restingHeartRateBpm,
      maxHeartRateBpm: data.maxHeartRateBpm.present
          ? data.maxHeartRateBpm.value
          : this.maxHeartRateBpm,
      weeklyRunMinutes: data.weeklyRunMinutes.present
          ? data.weeklyRunMinutes.value
          : this.weeklyRunMinutes,
      trainingDaysMask: data.trainingDaysMask.present
          ? data.trainingDaysMask.value
          : this.trainingDaysMask,
      usualTrainingMinutes: data.usualTrainingMinutes.present
          ? data.usualTrainingMinutes.value
          : this.usualTrainingMinutes,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ProfileData(')
          ..write('id: $id, ')
          ..write('birthYear: $birthYear, ')
          ..write('bodyWeightKg: $bodyWeightKg, ')
          ..write('bodyHeightM: $bodyHeightM, ')
          ..write('restingHeartRateBpm: $restingHeartRateBpm, ')
          ..write('maxHeartRateBpm: $maxHeartRateBpm, ')
          ..write('weeklyRunMinutes: $weeklyRunMinutes, ')
          ..write('trainingDaysMask: $trainingDaysMask, ')
          ..write('usualTrainingMinutes: $usualTrainingMinutes')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    birthYear,
    bodyWeightKg,
    bodyHeightM,
    restingHeartRateBpm,
    maxHeartRateBpm,
    weeklyRunMinutes,
    trainingDaysMask,
    usualTrainingMinutes,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ProfileData &&
          other.id == this.id &&
          other.birthYear == this.birthYear &&
          other.bodyWeightKg == this.bodyWeightKg &&
          other.bodyHeightM == this.bodyHeightM &&
          other.restingHeartRateBpm == this.restingHeartRateBpm &&
          other.maxHeartRateBpm == this.maxHeartRateBpm &&
          other.weeklyRunMinutes == this.weeklyRunMinutes &&
          other.trainingDaysMask == this.trainingDaysMask &&
          other.usualTrainingMinutes == this.usualTrainingMinutes);
}

class ProfileCompanion extends UpdateCompanion<ProfileData> {
  final Value<int> id;
  final Value<int?> birthYear;
  final Value<double?> bodyWeightKg;
  final Value<double?> bodyHeightM;
  final Value<int?> restingHeartRateBpm;
  final Value<int?> maxHeartRateBpm;
  final Value<int?> weeklyRunMinutes;
  final Value<int?> trainingDaysMask;
  final Value<int?> usualTrainingMinutes;
  const ProfileCompanion({
    this.id = const Value.absent(),
    this.birthYear = const Value.absent(),
    this.bodyWeightKg = const Value.absent(),
    this.bodyHeightM = const Value.absent(),
    this.restingHeartRateBpm = const Value.absent(),
    this.maxHeartRateBpm = const Value.absent(),
    this.weeklyRunMinutes = const Value.absent(),
    this.trainingDaysMask = const Value.absent(),
    this.usualTrainingMinutes = const Value.absent(),
  });
  ProfileCompanion.insert({
    this.id = const Value.absent(),
    this.birthYear = const Value.absent(),
    this.bodyWeightKg = const Value.absent(),
    this.bodyHeightM = const Value.absent(),
    this.restingHeartRateBpm = const Value.absent(),
    this.maxHeartRateBpm = const Value.absent(),
    this.weeklyRunMinutes = const Value.absent(),
    this.trainingDaysMask = const Value.absent(),
    this.usualTrainingMinutes = const Value.absent(),
  });
  static Insertable<ProfileData> custom({
    Expression<int>? id,
    Expression<int>? birthYear,
    Expression<double>? bodyWeightKg,
    Expression<double>? bodyHeightM,
    Expression<int>? restingHeartRateBpm,
    Expression<int>? maxHeartRateBpm,
    Expression<int>? weeklyRunMinutes,
    Expression<int>? trainingDaysMask,
    Expression<int>? usualTrainingMinutes,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (birthYear != null) 'birth_year': birthYear,
      if (bodyWeightKg != null) 'body_weight_kg': bodyWeightKg,
      if (bodyHeightM != null) 'body_height_m': bodyHeightM,
      if (restingHeartRateBpm != null)
        'resting_heart_rate_bpm': restingHeartRateBpm,
      if (maxHeartRateBpm != null) 'max_heart_rate_bpm': maxHeartRateBpm,
      if (weeklyRunMinutes != null) 'weekly_run_minutes': weeklyRunMinutes,
      if (trainingDaysMask != null) 'training_days_mask': trainingDaysMask,
      if (usualTrainingMinutes != null)
        'usual_training_minutes': usualTrainingMinutes,
    });
  }

  ProfileCompanion copyWith({
    Value<int>? id,
    Value<int?>? birthYear,
    Value<double?>? bodyWeightKg,
    Value<double?>? bodyHeightM,
    Value<int?>? restingHeartRateBpm,
    Value<int?>? maxHeartRateBpm,
    Value<int?>? weeklyRunMinutes,
    Value<int?>? trainingDaysMask,
    Value<int?>? usualTrainingMinutes,
  }) {
    return ProfileCompanion(
      id: id ?? this.id,
      birthYear: birthYear ?? this.birthYear,
      bodyWeightKg: bodyWeightKg ?? this.bodyWeightKg,
      bodyHeightM: bodyHeightM ?? this.bodyHeightM,
      restingHeartRateBpm: restingHeartRateBpm ?? this.restingHeartRateBpm,
      maxHeartRateBpm: maxHeartRateBpm ?? this.maxHeartRateBpm,
      weeklyRunMinutes: weeklyRunMinutes ?? this.weeklyRunMinutes,
      trainingDaysMask: trainingDaysMask ?? this.trainingDaysMask,
      usualTrainingMinutes: usualTrainingMinutes ?? this.usualTrainingMinutes,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (birthYear.present) {
      map['birth_year'] = Variable<int>(birthYear.value);
    }
    if (bodyWeightKg.present) {
      map['body_weight_kg'] = Variable<double>(bodyWeightKg.value);
    }
    if (bodyHeightM.present) {
      map['body_height_m'] = Variable<double>(bodyHeightM.value);
    }
    if (restingHeartRateBpm.present) {
      map['resting_heart_rate_bpm'] = Variable<int>(restingHeartRateBpm.value);
    }
    if (maxHeartRateBpm.present) {
      map['max_heart_rate_bpm'] = Variable<int>(maxHeartRateBpm.value);
    }
    if (weeklyRunMinutes.present) {
      map['weekly_run_minutes'] = Variable<int>(weeklyRunMinutes.value);
    }
    if (trainingDaysMask.present) {
      map['training_days_mask'] = Variable<int>(trainingDaysMask.value);
    }
    if (usualTrainingMinutes.present) {
      map['usual_training_minutes'] = Variable<int>(usualTrainingMinutes.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProfileCompanion(')
          ..write('id: $id, ')
          ..write('birthYear: $birthYear, ')
          ..write('bodyWeightKg: $bodyWeightKg, ')
          ..write('bodyHeightM: $bodyHeightM, ')
          ..write('restingHeartRateBpm: $restingHeartRateBpm, ')
          ..write('maxHeartRateBpm: $maxHeartRateBpm, ')
          ..write('weeklyRunMinutes: $weeklyRunMinutes, ')
          ..write('trainingDaysMask: $trainingDaysMask, ')
          ..write('usualTrainingMinutes: $usualTrainingMinutes')
          ..write(')'))
        .toString();
  }
}

class Settings extends Table with TableInfo<Settings, Setting> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  Settings(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL PRIMARY KEY',
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _updatedAtUsMeta = const VerificationMeta(
    'updatedAtUs',
  );
  late final GeneratedColumn<int> updatedAtUs = GeneratedColumn<int>(
    'updated_at_us',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  @override
  List<GeneratedColumn> get $columns => [key, value, updatedAtUs];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<Setting> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    if (data.containsKey('updated_at_us')) {
      context.handle(
        _updatedAtUsMeta,
        updatedAtUs.isAcceptableOrUnknown(
          data['updated_at_us']!,
          _updatedAtUsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_updatedAtUsMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  Setting map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Setting(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
      updatedAtUs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at_us'],
      )!,
    );
  }

  @override
  Settings createAlias(String alias) {
    return Settings(attachedDatabase, alias);
  }

  @override
  bool get dontWriteConstraints => true;
}

class Setting extends DataClass implements Insertable<Setting> {
  final String key;
  final String value;
  final int updatedAtUs;
  const Setting({
    required this.key,
    required this.value,
    required this.updatedAtUs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    map['updated_at_us'] = Variable<int>(updatedAtUs);
    return map;
  }

  SettingsCompanion toCompanion(bool nullToAbsent) {
    return SettingsCompanion(
      key: Value(key),
      value: Value(value),
      updatedAtUs: Value(updatedAtUs),
    );
  }

  factory Setting.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Setting(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
      updatedAtUs: serializer.fromJson<int>(json['updated_at_us']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
      'updated_at_us': serializer.toJson<int>(updatedAtUs),
    };
  }

  Setting copyWith({String? key, String? value, int? updatedAtUs}) => Setting(
    key: key ?? this.key,
    value: value ?? this.value,
    updatedAtUs: updatedAtUs ?? this.updatedAtUs,
  );
  Setting copyWithCompanion(SettingsCompanion data) {
    return Setting(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
      updatedAtUs: data.updatedAtUs.present
          ? data.updatedAtUs.value
          : this.updatedAtUs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Setting(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('updatedAtUs: $updatedAtUs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value, updatedAtUs);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Setting &&
          other.key == this.key &&
          other.value == this.value &&
          other.updatedAtUs == this.updatedAtUs);
}

class SettingsCompanion extends UpdateCompanion<Setting> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> updatedAtUs;
  final Value<int> rowid;
  const SettingsCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.updatedAtUs = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SettingsCompanion.insert({
    required String key,
    required String value,
    required int updatedAtUs,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value),
       updatedAtUs = Value(updatedAtUs);
  static Insertable<Setting> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? updatedAtUs,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (updatedAtUs != null) 'updated_at_us': updatedAtUs,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SettingsCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? updatedAtUs,
    Value<int>? rowid,
  }) {
    return SettingsCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      updatedAtUs: updatedAtUs ?? this.updatedAtUs,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (updatedAtUs.present) {
      map['updated_at_us'] = Variable<int>(updatedAtUs.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SettingsCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('updatedAtUs: $updatedAtUs, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class KnownDevices extends Table with TableInfo<KnownDevices, KnownDevice> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  KnownDevices(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL PRIMARY KEY AUTOINCREMENT',
  );
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL UNIQUE',
  );
  static const VerificationMeta _displayNameMeta = const VerificationMeta(
    'displayName',
  );
  late final GeneratedColumn<String> displayName = GeneratedColumn<String>(
    'display_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _isPreferredMeta = const VerificationMeta(
    'isPreferred',
  );
  late final GeneratedColumn<bool> isPreferred = GeneratedColumn<bool>(
    'is_preferred',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL DEFAULT 0 CHECK (is_preferred IN (0, 1))',
    defaultValue: const CustomExpression('0'),
  );
  static const VerificationMeta _addedAtUsMeta = const VerificationMeta(
    'addedAtUs',
  );
  late final GeneratedColumn<int> addedAtUs = GeneratedColumn<int>(
    'added_at_us',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    deviceId,
    displayName,
    isPreferred,
    addedAtUs,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'known_devices';
  @override
  VerificationContext validateIntegrity(
    Insertable<KnownDevice> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('display_name')) {
      context.handle(
        _displayNameMeta,
        displayName.isAcceptableOrUnknown(
          data['display_name']!,
          _displayNameMeta,
        ),
      );
    }
    if (data.containsKey('is_preferred')) {
      context.handle(
        _isPreferredMeta,
        isPreferred.isAcceptableOrUnknown(
          data['is_preferred']!,
          _isPreferredMeta,
        ),
      );
    }
    if (data.containsKey('added_at_us')) {
      context.handle(
        _addedAtUsMeta,
        addedAtUs.isAcceptableOrUnknown(data['added_at_us']!, _addedAtUsMeta),
      );
    } else if (isInserting) {
      context.missing(_addedAtUsMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  KnownDevice map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return KnownDevice(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      )!,
      displayName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}display_name'],
      ),
      isPreferred: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_preferred'],
      )!,
      addedAtUs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}added_at_us'],
      )!,
    );
  }

  @override
  KnownDevices createAlias(String alias) {
    return KnownDevices(attachedDatabase, alias);
  }

  @override
  bool get dontWriteConstraints => true;
}

class KnownDevice extends DataClass implements Insertable<KnownDevice> {
  final int id;
  final String deviceId;
  final String? displayName;
  final bool isPreferred;
  final int addedAtUs;
  const KnownDevice({
    required this.id,
    required this.deviceId,
    this.displayName,
    required this.isPreferred,
    required this.addedAtUs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['device_id'] = Variable<String>(deviceId);
    if (!nullToAbsent || displayName != null) {
      map['display_name'] = Variable<String>(displayName);
    }
    map['is_preferred'] = Variable<bool>(isPreferred);
    map['added_at_us'] = Variable<int>(addedAtUs);
    return map;
  }

  KnownDevicesCompanion toCompanion(bool nullToAbsent) {
    return KnownDevicesCompanion(
      id: Value(id),
      deviceId: Value(deviceId),
      displayName: displayName == null && nullToAbsent
          ? const Value.absent()
          : Value(displayName),
      isPreferred: Value(isPreferred),
      addedAtUs: Value(addedAtUs),
    );
  }

  factory KnownDevice.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return KnownDevice(
      id: serializer.fromJson<int>(json['id']),
      deviceId: serializer.fromJson<String>(json['device_id']),
      displayName: serializer.fromJson<String?>(json['display_name']),
      isPreferred: serializer.fromJson<bool>(json['is_preferred']),
      addedAtUs: serializer.fromJson<int>(json['added_at_us']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'device_id': serializer.toJson<String>(deviceId),
      'display_name': serializer.toJson<String?>(displayName),
      'is_preferred': serializer.toJson<bool>(isPreferred),
      'added_at_us': serializer.toJson<int>(addedAtUs),
    };
  }

  KnownDevice copyWith({
    int? id,
    String? deviceId,
    Value<String?> displayName = const Value.absent(),
    bool? isPreferred,
    int? addedAtUs,
  }) => KnownDevice(
    id: id ?? this.id,
    deviceId: deviceId ?? this.deviceId,
    displayName: displayName.present ? displayName.value : this.displayName,
    isPreferred: isPreferred ?? this.isPreferred,
    addedAtUs: addedAtUs ?? this.addedAtUs,
  );
  KnownDevice copyWithCompanion(KnownDevicesCompanion data) {
    return KnownDevice(
      id: data.id.present ? data.id.value : this.id,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      displayName: data.displayName.present
          ? data.displayName.value
          : this.displayName,
      isPreferred: data.isPreferred.present
          ? data.isPreferred.value
          : this.isPreferred,
      addedAtUs: data.addedAtUs.present ? data.addedAtUs.value : this.addedAtUs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('KnownDevice(')
          ..write('id: $id, ')
          ..write('deviceId: $deviceId, ')
          ..write('displayName: $displayName, ')
          ..write('isPreferred: $isPreferred, ')
          ..write('addedAtUs: $addedAtUs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, deviceId, displayName, isPreferred, addedAtUs);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is KnownDevice &&
          other.id == this.id &&
          other.deviceId == this.deviceId &&
          other.displayName == this.displayName &&
          other.isPreferred == this.isPreferred &&
          other.addedAtUs == this.addedAtUs);
}

class KnownDevicesCompanion extends UpdateCompanion<KnownDevice> {
  final Value<int> id;
  final Value<String> deviceId;
  final Value<String?> displayName;
  final Value<bool> isPreferred;
  final Value<int> addedAtUs;
  const KnownDevicesCompanion({
    this.id = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.displayName = const Value.absent(),
    this.isPreferred = const Value.absent(),
    this.addedAtUs = const Value.absent(),
  });
  KnownDevicesCompanion.insert({
    this.id = const Value.absent(),
    required String deviceId,
    this.displayName = const Value.absent(),
    this.isPreferred = const Value.absent(),
    required int addedAtUs,
  }) : deviceId = Value(deviceId),
       addedAtUs = Value(addedAtUs);
  static Insertable<KnownDevice> custom({
    Expression<int>? id,
    Expression<String>? deviceId,
    Expression<String>? displayName,
    Expression<bool>? isPreferred,
    Expression<int>? addedAtUs,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (deviceId != null) 'device_id': deviceId,
      if (displayName != null) 'display_name': displayName,
      if (isPreferred != null) 'is_preferred': isPreferred,
      if (addedAtUs != null) 'added_at_us': addedAtUs,
    });
  }

  KnownDevicesCompanion copyWith({
    Value<int>? id,
    Value<String>? deviceId,
    Value<String?>? displayName,
    Value<bool>? isPreferred,
    Value<int>? addedAtUs,
  }) {
    return KnownDevicesCompanion(
      id: id ?? this.id,
      deviceId: deviceId ?? this.deviceId,
      displayName: displayName ?? this.displayName,
      isPreferred: isPreferred ?? this.isPreferred,
      addedAtUs: addedAtUs ?? this.addedAtUs,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (displayName.present) {
      map['display_name'] = Variable<String>(displayName.value);
    }
    if (isPreferred.present) {
      map['is_preferred'] = Variable<bool>(isPreferred.value);
    }
    if (addedAtUs.present) {
      map['added_at_us'] = Variable<int>(addedAtUs.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('KnownDevicesCompanion(')
          ..write('id: $id, ')
          ..write('deviceId: $deviceId, ')
          ..write('displayName: $displayName, ')
          ..write('isPreferred: $isPreferred, ')
          ..write('addedAtUs: $addedAtUs')
          ..write(')'))
        .toString();
  }
}

class Consents extends Table with TableInfo<Consents, Consent> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  Consents(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _sourceKeyMeta = const VerificationMeta(
    'sourceKey',
  );
  late final GeneratedColumn<String> sourceKey = GeneratedColumn<String>(
    'source_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL PRIMARY KEY',
  );
  static const VerificationMeta _stateMeta = const VerificationMeta('state');
  late final GeneratedColumn<String> state = GeneratedColumn<String>(
    'state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (state IN (\'granted\', \'revoked\'))',
  );
  static const VerificationMeta _changedAtUsMeta = const VerificationMeta(
    'changedAtUs',
  );
  late final GeneratedColumn<int> changedAtUs = GeneratedColumn<int>(
    'changed_at_us',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  @override
  List<GeneratedColumn> get $columns => [sourceKey, state, changedAtUs];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'consents';
  @override
  VerificationContext validateIntegrity(
    Insertable<Consent> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('source_key')) {
      context.handle(
        _sourceKeyMeta,
        sourceKey.isAcceptableOrUnknown(data['source_key']!, _sourceKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceKeyMeta);
    }
    if (data.containsKey('state')) {
      context.handle(
        _stateMeta,
        state.isAcceptableOrUnknown(data['state']!, _stateMeta),
      );
    } else if (isInserting) {
      context.missing(_stateMeta);
    }
    if (data.containsKey('changed_at_us')) {
      context.handle(
        _changedAtUsMeta,
        changedAtUs.isAcceptableOrUnknown(
          data['changed_at_us']!,
          _changedAtUsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_changedAtUsMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {sourceKey};
  @override
  Consent map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Consent(
      sourceKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_key'],
      )!,
      state: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}state'],
      )!,
      changedAtUs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}changed_at_us'],
      )!,
    );
  }

  @override
  Consents createAlias(String alias) {
    return Consents(attachedDatabase, alias);
  }

  @override
  bool get dontWriteConstraints => true;
}

class Consent extends DataClass implements Insertable<Consent> {
  final String sourceKey;
  final String state;
  final int changedAtUs;
  const Consent({
    required this.sourceKey,
    required this.state,
    required this.changedAtUs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['source_key'] = Variable<String>(sourceKey);
    map['state'] = Variable<String>(state);
    map['changed_at_us'] = Variable<int>(changedAtUs);
    return map;
  }

  ConsentsCompanion toCompanion(bool nullToAbsent) {
    return ConsentsCompanion(
      sourceKey: Value(sourceKey),
      state: Value(state),
      changedAtUs: Value(changedAtUs),
    );
  }

  factory Consent.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Consent(
      sourceKey: serializer.fromJson<String>(json['source_key']),
      state: serializer.fromJson<String>(json['state']),
      changedAtUs: serializer.fromJson<int>(json['changed_at_us']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'source_key': serializer.toJson<String>(sourceKey),
      'state': serializer.toJson<String>(state),
      'changed_at_us': serializer.toJson<int>(changedAtUs),
    };
  }

  Consent copyWith({String? sourceKey, String? state, int? changedAtUs}) =>
      Consent(
        sourceKey: sourceKey ?? this.sourceKey,
        state: state ?? this.state,
        changedAtUs: changedAtUs ?? this.changedAtUs,
      );
  Consent copyWithCompanion(ConsentsCompanion data) {
    return Consent(
      sourceKey: data.sourceKey.present ? data.sourceKey.value : this.sourceKey,
      state: data.state.present ? data.state.value : this.state,
      changedAtUs: data.changedAtUs.present
          ? data.changedAtUs.value
          : this.changedAtUs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Consent(')
          ..write('sourceKey: $sourceKey, ')
          ..write('state: $state, ')
          ..write('changedAtUs: $changedAtUs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(sourceKey, state, changedAtUs);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Consent &&
          other.sourceKey == this.sourceKey &&
          other.state == this.state &&
          other.changedAtUs == this.changedAtUs);
}

class ConsentsCompanion extends UpdateCompanion<Consent> {
  final Value<String> sourceKey;
  final Value<String> state;
  final Value<int> changedAtUs;
  final Value<int> rowid;
  const ConsentsCompanion({
    this.sourceKey = const Value.absent(),
    this.state = const Value.absent(),
    this.changedAtUs = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ConsentsCompanion.insert({
    required String sourceKey,
    required String state,
    required int changedAtUs,
    this.rowid = const Value.absent(),
  }) : sourceKey = Value(sourceKey),
       state = Value(state),
       changedAtUs = Value(changedAtUs);
  static Insertable<Consent> custom({
    Expression<String>? sourceKey,
    Expression<String>? state,
    Expression<int>? changedAtUs,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (sourceKey != null) 'source_key': sourceKey,
      if (state != null) 'state': state,
      if (changedAtUs != null) 'changed_at_us': changedAtUs,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ConsentsCompanion copyWith({
    Value<String>? sourceKey,
    Value<String>? state,
    Value<int>? changedAtUs,
    Value<int>? rowid,
  }) {
    return ConsentsCompanion(
      sourceKey: sourceKey ?? this.sourceKey,
      state: state ?? this.state,
      changedAtUs: changedAtUs ?? this.changedAtUs,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (sourceKey.present) {
      map['source_key'] = Variable<String>(sourceKey.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(state.value);
    }
    if (changedAtUs.present) {
      map['changed_at_us'] = Variable<int>(changedAtUs.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ConsentsCompanion(')
          ..write('sourceKey: $sourceKey, ')
          ..write('state: $state, ')
          ..write('changedAtUs: $changedAtUs, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final StorageMeta storageMeta = StorageMeta(this);
  late final Runs runs = Runs(this);
  late final Trigger runsOffsetInsert = Trigger(
    'CREATE TRIGGER runs_offset_insert BEFORE INSERT ON runs WHEN NEW.ended_utc_offset_s IS NOT NULL AND NEW.ended_at_us IS NULL BEGIN SELECT RAISE (ABORT, \'offset without end\');END',
    'runs_offset_insert',
  );
  late final Trigger runsOffsetUpdate = Trigger(
    'CREATE TRIGGER runs_offset_update BEFORE UPDATE ON runs WHEN NEW.ended_utc_offset_s IS NOT NULL AND NEW.ended_at_us IS NULL BEGIN SELECT RAISE (ABORT, \'offset without end\');END',
    'runs_offset_update',
  );
  late final Laps laps = Laps(this);
  late final RunGaps runGaps = RunGaps(this);
  late final Index runGapsRunTime = Index(
    'run_gaps_run_time',
    'CREATE INDEX run_gaps_run_time ON run_gaps (run_id, start_us)',
  );
  late final Index lapsRunTime = Index(
    'laps_run_time',
    'CREATE INDEX laps_run_time ON laps (run_id, marked_at_us)',
  );
  late final RawPositions rawPositions = RawPositions(this);
  late final RawHeartRates rawHeartRates = RawHeartRates(this);
  late final RawAltitudes rawAltitudes = RawAltitudes(this);
  late final RawSteps rawSteps = RawSteps(this);
  late final Index rawPositionsRunTime = Index(
    'raw_positions_run_time',
    'CREATE INDEX raw_positions_run_time ON raw_positions (run_id, time_us)',
  );
  late final Index rawHeartRatesRunTime = Index(
    'raw_heart_rates_run_time',
    'CREATE INDEX raw_heart_rates_run_time ON raw_heart_rates (run_id, time_us)',
  );
  late final Index rawAltitudesRunTime = Index(
    'raw_altitudes_run_time',
    'CREATE INDEX raw_altitudes_run_time ON raw_altitudes (run_id, time_us)',
  );
  late final Index rawStepsRunTime = Index(
    'raw_steps_run_time',
    'CREATE INDEX raw_steps_run_time ON raw_steps (run_id, time_us)',
  );
  late final Trigger rawPositionsNoUpdate = Trigger(
    'CREATE TRIGGER raw_positions_no_update BEFORE UPDATE ON raw_positions BEGIN SELECT RAISE (ABORT, \'raw data is append-only\');END',
    'raw_positions_no_update',
  );
  late final Trigger rawHeartRatesNoUpdate = Trigger(
    'CREATE TRIGGER raw_heart_rates_no_update BEFORE UPDATE ON raw_heart_rates BEGIN SELECT RAISE (ABORT, \'raw data is append-only\');END',
    'raw_heart_rates_no_update',
  );
  late final Trigger rawAltitudesNoUpdate = Trigger(
    'CREATE TRIGGER raw_altitudes_no_update BEFORE UPDATE ON raw_altitudes BEGIN SELECT RAISE (ABORT, \'raw data is append-only\');END',
    'raw_altitudes_no_update',
  );
  late final Trigger rawStepsNoUpdate = Trigger(
    'CREATE TRIGGER raw_steps_no_update BEFORE UPDATE ON raw_steps BEGIN SELECT RAISE (ABORT, \'raw data is append-only\');END',
    'raw_steps_no_update',
  );
  late final Trigger rawPositionsNoDirectDelete = Trigger(
    'CREATE TRIGGER raw_positions_no_direct_delete BEFORE DELETE ON raw_positions WHEN EXISTS (SELECT 1 FROM runs WHERE id = OLD.run_id) BEGIN SELECT RAISE (ABORT, \'raw data is deleted only with its run\');END',
    'raw_positions_no_direct_delete',
  );
  late final Trigger rawHeartRatesNoDirectDelete = Trigger(
    'CREATE TRIGGER raw_heart_rates_no_direct_delete BEFORE DELETE ON raw_heart_rates WHEN EXISTS (SELECT 1 FROM runs WHERE id = OLD.run_id) BEGIN SELECT RAISE (ABORT, \'raw data is deleted only with its run\');END',
    'raw_heart_rates_no_direct_delete',
  );
  late final Trigger rawAltitudesNoDirectDelete = Trigger(
    'CREATE TRIGGER raw_altitudes_no_direct_delete BEFORE DELETE ON raw_altitudes WHEN EXISTS (SELECT 1 FROM runs WHERE id = OLD.run_id) BEGIN SELECT RAISE (ABORT, \'raw data is deleted only with its run\');END',
    'raw_altitudes_no_direct_delete',
  );
  late final Trigger rawStepsNoDirectDelete = Trigger(
    'CREATE TRIGGER raw_steps_no_direct_delete BEFORE DELETE ON raw_steps WHEN EXISTS (SELECT 1 FROM runs WHERE id = OLD.run_id) BEGIN SELECT RAISE (ABORT, \'raw data is deleted only with its run\');END',
    'raw_steps_no_direct_delete',
  );
  late final PreprocessingResults preprocessingResults = PreprocessingResults(
    this,
  );
  late final PreprocessedSamples preprocessedSamples = PreprocessedSamples(
    this,
  );
  late final Index preprocessedSamplesRunTime = Index(
    'preprocessed_samples_run_time',
    'CREATE INDEX preprocessed_samples_run_time ON preprocessed_samples (run_id, channel, time_us)',
  );
  late final PreprocessedSpans preprocessedSpans = PreprocessedSpans(this);
  late final Index preprocessedSpansRunTime = Index(
    'preprocessed_spans_run_time',
    'CREATE INDEX preprocessed_spans_run_time ON preprocessed_spans (run_id, kind, start_us)',
  );
  late final RatedSections ratedSections = RatedSections(this);
  late final Index ratedSectionsRunTime = Index(
    'rated_sections_run_time',
    'CREATE INDEX rated_sections_run_time ON rated_sections (run_id, start_us)',
  );
  late final ComputedValues computedValues = ComputedValues(this);
  late final Index computedValuesRunUnique = Index(
    'computed_values_run_unique',
    'CREATE UNIQUE INDEX computed_values_run_unique ON computed_values (run_id, value_key, role) WHERE run_id IS NOT NULL',
  );
  late final Index computedValuesDayUnique = Index(
    'computed_values_day_unique',
    'CREATE UNIQUE INDEX computed_values_day_unique ON computed_values (day, value_key, role) WHERE day IS NOT NULL',
  );
  late final Trigger computedValuesOriginalImmutable = Trigger(
    'CREATE TRIGGER computed_values_original_immutable BEFORE UPDATE ON computed_values WHEN OLD.role = \'original\' OR NEW.role = \'original\' BEGIN SELECT RAISE (ABORT, \'original value is immutable\');END',
    'computed_values_original_immutable',
  );
  late final Trigger computedValuesReasonInsert = Trigger(
    'CREATE TRIGGER computed_values_reason_insert BEFORE INSERT ON computed_values WHEN(NEW.value_real IS NULL)=(NEW.unavailable_reason IS NULL)BEGIN SELECT RAISE (ABORT, \'value and unavailable_reason are exclusive\');END',
    'computed_values_reason_insert',
  );
  late final Trigger computedValuesReasonUpdate = Trigger(
    'CREATE TRIGGER computed_values_reason_update BEFORE UPDATE ON computed_values WHEN(NEW.value_real IS NULL)=(NEW.unavailable_reason IS NULL)BEGIN SELECT RAISE (ABORT, \'value and unavailable_reason are exclusive\');END',
    'computed_values_reason_update',
  );
  late final Trigger computedValuesBasisInsert = Trigger(
    'CREATE TRIGGER computed_values_basis_insert BEFORE INSERT ON computed_values WHEN NEW.hr_max_is_estimated IS NULL AND(NEW.hr_max_bpm IS NOT NULL OR NEW.hr_rest_bpm IS NOT NULL)BEGIN SELECT RAISE (ABORT, \'basis values without snapshot flag\');END',
    'computed_values_basis_insert',
  );
  late final Trigger computedValuesBasisUpdate = Trigger(
    'CREATE TRIGGER computed_values_basis_update BEFORE UPDATE ON computed_values WHEN NEW.hr_max_is_estimated IS NULL AND(NEW.hr_max_bpm IS NOT NULL OR NEW.hr_rest_bpm IS NOT NULL)BEGIN SELECT RAISE (ABORT, \'basis values without snapshot flag\');END',
    'computed_values_basis_update',
  );
  late final ValueSections valueSections = ValueSections(this);
  late final Trigger valueSectionsOriginalImmutable = Trigger(
    'CREATE TRIGGER value_sections_original_immutable BEFORE UPDATE ON value_sections WHEN (SELECT role FROM computed_values WHERE id = OLD.computed_value_id) = \'original\' OR (SELECT role FROM computed_values WHERE id = NEW.computed_value_id) = \'original\' BEGIN SELECT RAISE (ABORT, \'original value sections are immutable\');END',
    'value_sections_original_immutable',
  );
  late final Trigger valueSectionsOriginalNoLateInsert = Trigger(
    'CREATE TRIGGER value_sections_original_no_late_insert BEFORE INSERT ON value_sections WHEN (SELECT role FROM computed_values WHERE id = NEW.computed_value_id) = \'original\' AND NEW.computed_value_id <> (SELECT MAX(id) FROM computed_values) BEGIN SELECT RAISE (ABORT, \'original value sections are immutable\');END',
    'value_sections_original_no_late_insert',
  );
  late final Profile profile = Profile(this);
  late final Settings settings = Settings(this);
  late final KnownDevices knownDevices = KnownDevices(this);
  late final Index knownDevicesOnePreferred = Index(
    'known_devices_one_preferred',
    'CREATE UNIQUE INDEX known_devices_one_preferred ON known_devices (is_preferred) WHERE is_preferred = 1',
  );
  late final Consents consents = Consents(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    storageMeta,
    runs,
    runsOffsetInsert,
    runsOffsetUpdate,
    laps,
    runGaps,
    runGapsRunTime,
    lapsRunTime,
    rawPositions,
    rawHeartRates,
    rawAltitudes,
    rawSteps,
    rawPositionsRunTime,
    rawHeartRatesRunTime,
    rawAltitudesRunTime,
    rawStepsRunTime,
    rawPositionsNoUpdate,
    rawHeartRatesNoUpdate,
    rawAltitudesNoUpdate,
    rawStepsNoUpdate,
    rawPositionsNoDirectDelete,
    rawHeartRatesNoDirectDelete,
    rawAltitudesNoDirectDelete,
    rawStepsNoDirectDelete,
    preprocessingResults,
    preprocessedSamples,
    preprocessedSamplesRunTime,
    preprocessedSpans,
    preprocessedSpansRunTime,
    ratedSections,
    ratedSectionsRunTime,
    computedValues,
    computedValuesRunUnique,
    computedValuesDayUnique,
    computedValuesOriginalImmutable,
    computedValuesReasonInsert,
    computedValuesReasonUpdate,
    computedValuesBasisInsert,
    computedValuesBasisUpdate,
    valueSections,
    valueSectionsOriginalImmutable,
    valueSectionsOriginalNoLateInsert,
    profile,
    settings,
    knownDevices,
    knownDevicesOnePreferred,
    consents,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'runs',
        limitUpdateKind: UpdateKind.insert,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'runs',
        limitUpdateKind: UpdateKind.update,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'runs',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('laps', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'runs',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('run_gaps', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'runs',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('raw_positions', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'runs',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('raw_heart_rates', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'runs',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('raw_altitudes', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'runs',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('raw_steps', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'raw_positions',
        limitUpdateKind: UpdateKind.update,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'raw_heart_rates',
        limitUpdateKind: UpdateKind.update,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'raw_altitudes',
        limitUpdateKind: UpdateKind.update,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'raw_steps',
        limitUpdateKind: UpdateKind.update,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'raw_positions',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'raw_heart_rates',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'raw_altitudes',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'raw_steps',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'runs',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('preprocessing_results', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'runs',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('preprocessed_samples', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'runs',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('preprocessed_spans', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'runs',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('rated_sections', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'runs',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('computed_values', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'computed_values',
        limitUpdateKind: UpdateKind.update,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'computed_values',
        limitUpdateKind: UpdateKind.insert,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'computed_values',
        limitUpdateKind: UpdateKind.update,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'computed_values',
        limitUpdateKind: UpdateKind.insert,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'computed_values',
        limitUpdateKind: UpdateKind.update,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'computed_values',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('value_sections', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'value_sections',
        limitUpdateKind: UpdateKind.update,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'value_sections',
        limitUpdateKind: UpdateKind.insert,
      ),
      result: [],
    ),
  ]);
}

typedef $StorageMetaCreateCompanionBuilder = StorageMetaCompanion Function({
  required String key,
  required String value,
  Value<int> rowid,
});
typedef $StorageMetaUpdateCompanionBuilder = StorageMetaCompanion Function({
  Value<String> key,
  Value<String> value,
  Value<int> rowid,
});

class $StorageMetaFilterComposer extends Composer<_$AppDatabase, StorageMeta> {
  $StorageMetaFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );
}

class $StorageMetaOrderingComposer
    extends Composer<_$AppDatabase, StorageMeta> {
  $StorageMetaOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );
}

class $StorageMetaAnnotationComposer
    extends Composer<_$AppDatabase, StorageMeta> {
  $StorageMetaAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $StorageMetaTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          StorageMeta,
          StorageMetaData,
          $StorageMetaFilterComposer,
          $StorageMetaOrderingComposer,
          $StorageMetaAnnotationComposer,
          $StorageMetaCreateCompanionBuilder,
          $StorageMetaUpdateCompanionBuilder,
          (
            StorageMetaData,
            BaseReferences<_$AppDatabase, StorageMeta, StorageMetaData>,
          ),
          StorageMetaData,
          PrefetchHooks Function()
        > {
  $StorageMetaTableManager(_$AppDatabase db, StorageMeta table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $StorageMetaFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $StorageMetaOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $StorageMetaAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> key = const Value.absent(),
            Value<String> value = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) => StorageMetaCompanion(key: key, value: value, rowid: rowid),
          createCompanionCallback:
              ({
                required String key,
                required String value,
                Value<int> rowid = const Value.absent(),
              }) => StorageMetaCompanion.insert(
                key: key,
                value: value,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<StorageMeta, StorageMetaData>(table),
                  BaseReferences<_$AppDatabase, StorageMeta, StorageMetaData>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $StorageMetaProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      StorageMeta,
      StorageMetaData,
      $StorageMetaFilterComposer,
      $StorageMetaOrderingComposer,
      $StorageMetaAnnotationComposer,
      $StorageMetaCreateCompanionBuilder,
      $StorageMetaUpdateCompanionBuilder,
      (
        StorageMetaData,
        BaseReferences<_$AppDatabase, StorageMeta, StorageMetaData>,
      ),
      StorageMetaData,
      PrefetchHooks Function()
    >;
typedef $RunsCreateCompanionBuilder = RunsCompanion Function({
  Value<int> id,
  required String state,
  required int startedAtUs,
  Value<int?> endedAtUs,
  Value<int?> endedUtcOffsetS,
});
typedef $RunsUpdateCompanionBuilder = RunsCompanion Function({
  Value<int> id,
  Value<String> state,
  Value<int> startedAtUs,
  Value<int?> endedAtUs,
  Value<int?> endedUtcOffsetS,
});

final class $RunsReferences extends BaseReferences<_$AppDatabase, Runs, Run> {
  $RunsReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<Laps, List<Lap>> _lapsRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.laps,
    aliasName: 'runs__id__laps__run_id',
  );

  $LapsProcessedTableManager get lapsRefs {
    final manager = $LapsTableManager(
      $_db,
      $_db.laps,
    ).filter((f) => f.runId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_lapsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<RunGaps, List<RunGap>> _runGapsRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.runGaps,
    aliasName: 'runs__id__run_gaps__run_id',
  );

  $RunGapsProcessedTableManager get runGapsRefs {
    final manager = $RunGapsTableManager(
      $_db,
      $_db.runGaps,
    ).filter((f) => f.runId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_runGapsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<RawPositions, List<RawPosition>>
  _rawPositionsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.rawPositions,
    aliasName: 'runs__id__raw_positions__run_id',
  );

  $RawPositionsProcessedTableManager get rawPositionsRefs {
    final manager = $RawPositionsTableManager(
      $_db,
      $_db.rawPositions,
    ).filter((f) => f.runId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_rawPositionsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<RawHeartRates, List<RawHeartRate>>
  _rawHeartRatesRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.rawHeartRates,
    aliasName: 'runs__id__raw_heart_rates__run_id',
  );

  $RawHeartRatesProcessedTableManager get rawHeartRatesRefs {
    final manager = $RawHeartRatesTableManager(
      $_db,
      $_db.rawHeartRates,
    ).filter((f) => f.runId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_rawHeartRatesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<RawAltitudes, List<RawAltitude>>
  _rawAltitudesRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.rawAltitudes,
    aliasName: 'runs__id__raw_altitudes__run_id',
  );

  $RawAltitudesProcessedTableManager get rawAltitudesRefs {
    final manager = $RawAltitudesTableManager(
      $_db,
      $_db.rawAltitudes,
    ).filter((f) => f.runId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_rawAltitudesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<RawSteps, List<RawStep>> _rawStepsRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.rawSteps,
    aliasName: 'runs__id__raw_steps__run_id',
  );

  $RawStepsProcessedTableManager get rawStepsRefs {
    final manager = $RawStepsTableManager(
      $_db,
      $_db.rawSteps,
    ).filter((f) => f.runId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_rawStepsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<PreprocessingResults, List<PreprocessingResult>>
  _preprocessingResultsRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.preprocessingResults,
        aliasName: 'runs__id__preprocessing_results__run_id',
      );

  $PreprocessingResultsProcessedTableManager get preprocessingResultsRefs {
    final manager = $PreprocessingResultsTableManager(
      $_db,
      $_db.preprocessingResults,
    ).filter((f) => f.runId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _preprocessingResultsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<PreprocessedSamples, List<PreprocessedSample>>
  _preprocessedSamplesRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.preprocessedSamples,
        aliasName: 'runs__id__preprocessed_samples__run_id',
      );

  $PreprocessedSamplesProcessedTableManager get preprocessedSamplesRefs {
    final manager = $PreprocessedSamplesTableManager(
      $_db,
      $_db.preprocessedSamples,
    ).filter((f) => f.runId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _preprocessedSamplesRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<PreprocessedSpans, List<PreprocessedSpan>>
  _preprocessedSpansRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.preprocessedSpans,
        aliasName: 'runs__id__preprocessed_spans__run_id',
      );

  $PreprocessedSpansProcessedTableManager get preprocessedSpansRefs {
    final manager = $PreprocessedSpansTableManager(
      $_db,
      $_db.preprocessedSpans,
    ).filter((f) => f.runId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _preprocessedSpansRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<RatedSections, List<RatedSection>>
  _ratedSectionsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.ratedSections,
    aliasName: 'runs__id__rated_sections__run_id',
  );

  $RatedSectionsProcessedTableManager get ratedSectionsRefs {
    final manager = $RatedSectionsTableManager(
      $_db,
      $_db.ratedSections,
    ).filter((f) => f.runId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_ratedSectionsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<ComputedValues, List<ComputedValue>>
  _computedValuesRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.computedValues,
    aliasName: 'runs__id__computed_values__run_id',
  );

  $ComputedValuesProcessedTableManager get computedValuesRefs {
    final manager = $ComputedValuesTableManager(
      $_db,
      $_db.computedValues,
    ).filter((f) => f.runId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_computedValuesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $RunsFilterComposer extends Composer<_$AppDatabase, Runs> {
  $RunsFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get startedAtUs => $composableBuilder(
    column: $table.startedAtUs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get endedAtUs => $composableBuilder(
    column: $table.endedAtUs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get endedUtcOffsetS => $composableBuilder(
    column: $table.endedUtcOffsetS,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> lapsRefs(
    Expression<bool> Function($LapsFilterComposer f) f,
  ) {
    final $LapsFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.laps,
      getReferencedColumn: (t) => t.runId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $LapsFilterComposer(
            $db: $db,
            $table: $db.laps,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> runGapsRefs(
    Expression<bool> Function($RunGapsFilterComposer f) f,
  ) {
    final $RunGapsFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.runGaps,
      getReferencedColumn: (t) => t.runId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $RunGapsFilterComposer(
            $db: $db,
            $table: $db.runGaps,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> rawPositionsRefs(
    Expression<bool> Function($RawPositionsFilterComposer f) f,
  ) {
    final $RawPositionsFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.rawPositions,
      getReferencedColumn: (t) => t.runId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $RawPositionsFilterComposer(
            $db: $db,
            $table: $db.rawPositions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> rawHeartRatesRefs(
    Expression<bool> Function($RawHeartRatesFilterComposer f) f,
  ) {
    final $RawHeartRatesFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.rawHeartRates,
      getReferencedColumn: (t) => t.runId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $RawHeartRatesFilterComposer(
            $db: $db,
            $table: $db.rawHeartRates,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> rawAltitudesRefs(
    Expression<bool> Function($RawAltitudesFilterComposer f) f,
  ) {
    final $RawAltitudesFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.rawAltitudes,
      getReferencedColumn: (t) => t.runId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $RawAltitudesFilterComposer(
            $db: $db,
            $table: $db.rawAltitudes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> rawStepsRefs(
    Expression<bool> Function($RawStepsFilterComposer f) f,
  ) {
    final $RawStepsFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.rawSteps,
      getReferencedColumn: (t) => t.runId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $RawStepsFilterComposer(
            $db: $db,
            $table: $db.rawSteps,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> preprocessingResultsRefs(
    Expression<bool> Function($PreprocessingResultsFilterComposer f) f,
  ) {
    final $PreprocessingResultsFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.preprocessingResults,
      getReferencedColumn: (t) => t.runId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $PreprocessingResultsFilterComposer(
            $db: $db,
            $table: $db.preprocessingResults,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> preprocessedSamplesRefs(
    Expression<bool> Function($PreprocessedSamplesFilterComposer f) f,
  ) {
    final $PreprocessedSamplesFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.preprocessedSamples,
      getReferencedColumn: (t) => t.runId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $PreprocessedSamplesFilterComposer(
            $db: $db,
            $table: $db.preprocessedSamples,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> preprocessedSpansRefs(
    Expression<bool> Function($PreprocessedSpansFilterComposer f) f,
  ) {
    final $PreprocessedSpansFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.preprocessedSpans,
      getReferencedColumn: (t) => t.runId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $PreprocessedSpansFilterComposer(
            $db: $db,
            $table: $db.preprocessedSpans,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> ratedSectionsRefs(
    Expression<bool> Function($RatedSectionsFilterComposer f) f,
  ) {
    final $RatedSectionsFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.ratedSections,
      getReferencedColumn: (t) => t.runId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $RatedSectionsFilterComposer(
            $db: $db,
            $table: $db.ratedSections,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> computedValuesRefs(
    Expression<bool> Function($ComputedValuesFilterComposer f) f,
  ) {
    final $ComputedValuesFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.computedValues,
      getReferencedColumn: (t) => t.runId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $ComputedValuesFilterComposer(
            $db: $db,
            $table: $db.computedValues,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $RunsOrderingComposer extends Composer<_$AppDatabase, Runs> {
  $RunsOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get startedAtUs => $composableBuilder(
    column: $table.startedAtUs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get endedAtUs => $composableBuilder(
    column: $table.endedAtUs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get endedUtcOffsetS => $composableBuilder(
    column: $table.endedUtcOffsetS,
    builder: (column) => ColumnOrderings(column),
  );
}

class $RunsAnnotationComposer extends Composer<_$AppDatabase, Runs> {
  $RunsAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<int> get startedAtUs => $composableBuilder(
    column: $table.startedAtUs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get endedAtUs =>
      $composableBuilder(column: $table.endedAtUs, builder: (column) => column);

  GeneratedColumn<int> get endedUtcOffsetS => $composableBuilder(
    column: $table.endedUtcOffsetS,
    builder: (column) => column,
  );

  Expression<T> lapsRefs<T extends Object>(
    Expression<T> Function($LapsAnnotationComposer a) f,
  ) {
    final $LapsAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.laps,
      getReferencedColumn: (t) => t.runId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $LapsAnnotationComposer(
            $db: $db,
            $table: $db.laps,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> runGapsRefs<T extends Object>(
    Expression<T> Function($RunGapsAnnotationComposer a) f,
  ) {
    final $RunGapsAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.runGaps,
      getReferencedColumn: (t) => t.runId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $RunGapsAnnotationComposer(
            $db: $db,
            $table: $db.runGaps,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> rawPositionsRefs<T extends Object>(
    Expression<T> Function($RawPositionsAnnotationComposer a) f,
  ) {
    final $RawPositionsAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.rawPositions,
      getReferencedColumn: (t) => t.runId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $RawPositionsAnnotationComposer(
            $db: $db,
            $table: $db.rawPositions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> rawHeartRatesRefs<T extends Object>(
    Expression<T> Function($RawHeartRatesAnnotationComposer a) f,
  ) {
    final $RawHeartRatesAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.rawHeartRates,
      getReferencedColumn: (t) => t.runId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $RawHeartRatesAnnotationComposer(
            $db: $db,
            $table: $db.rawHeartRates,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> rawAltitudesRefs<T extends Object>(
    Expression<T> Function($RawAltitudesAnnotationComposer a) f,
  ) {
    final $RawAltitudesAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.rawAltitudes,
      getReferencedColumn: (t) => t.runId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $RawAltitudesAnnotationComposer(
            $db: $db,
            $table: $db.rawAltitudes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> rawStepsRefs<T extends Object>(
    Expression<T> Function($RawStepsAnnotationComposer a) f,
  ) {
    final $RawStepsAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.rawSteps,
      getReferencedColumn: (t) => t.runId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $RawStepsAnnotationComposer(
            $db: $db,
            $table: $db.rawSteps,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> preprocessingResultsRefs<T extends Object>(
    Expression<T> Function($PreprocessingResultsAnnotationComposer a) f,
  ) {
    final $PreprocessingResultsAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.preprocessingResults,
      getReferencedColumn: (t) => t.runId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $PreprocessingResultsAnnotationComposer(
            $db: $db,
            $table: $db.preprocessingResults,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> preprocessedSamplesRefs<T extends Object>(
    Expression<T> Function($PreprocessedSamplesAnnotationComposer a) f,
  ) {
    final $PreprocessedSamplesAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.preprocessedSamples,
      getReferencedColumn: (t) => t.runId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $PreprocessedSamplesAnnotationComposer(
            $db: $db,
            $table: $db.preprocessedSamples,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> preprocessedSpansRefs<T extends Object>(
    Expression<T> Function($PreprocessedSpansAnnotationComposer a) f,
  ) {
    final $PreprocessedSpansAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.preprocessedSpans,
      getReferencedColumn: (t) => t.runId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $PreprocessedSpansAnnotationComposer(
            $db: $db,
            $table: $db.preprocessedSpans,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> ratedSectionsRefs<T extends Object>(
    Expression<T> Function($RatedSectionsAnnotationComposer a) f,
  ) {
    final $RatedSectionsAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.ratedSections,
      getReferencedColumn: (t) => t.runId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $RatedSectionsAnnotationComposer(
            $db: $db,
            $table: $db.ratedSections,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> computedValuesRefs<T extends Object>(
    Expression<T> Function($ComputedValuesAnnotationComposer a) f,
  ) {
    final $ComputedValuesAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.computedValues,
      getReferencedColumn: (t) => t.runId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $ComputedValuesAnnotationComposer(
            $db: $db,
            $table: $db.computedValues,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $RunsTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          Runs,
          Run,
          $RunsFilterComposer,
          $RunsOrderingComposer,
          $RunsAnnotationComposer,
          $RunsCreateCompanionBuilder,
          $RunsUpdateCompanionBuilder,
          (Run, $RunsReferences),
          Run,
          PrefetchHooks Function({
            bool lapsRefs,
            bool runGapsRefs,
            bool rawPositionsRefs,
            bool rawHeartRatesRefs,
            bool rawAltitudesRefs,
            bool rawStepsRefs,
            bool preprocessingResultsRefs,
            bool preprocessedSamplesRefs,
            bool preprocessedSpansRefs,
            bool ratedSectionsRefs,
            bool computedValuesRefs,
          })
        > {
  $RunsTableManager(_$AppDatabase db, Runs table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $RunsFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $RunsOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $RunsAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> state = const Value.absent(),
                Value<int> startedAtUs = const Value.absent(),
                Value<int?> endedAtUs = const Value.absent(),
                Value<int?> endedUtcOffsetS = const Value.absent(),
              }) => RunsCompanion(
                id: id,
                state: state,
                startedAtUs: startedAtUs,
                endedAtUs: endedAtUs,
                endedUtcOffsetS: endedUtcOffsetS,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String state,
                required int startedAtUs,
                Value<int?> endedAtUs = const Value.absent(),
                Value<int?> endedUtcOffsetS = const Value.absent(),
              }) => RunsCompanion.insert(
                id: id,
                state: state,
                startedAtUs: startedAtUs,
                endedAtUs: endedAtUs,
                endedUtcOffsetS: endedUtcOffsetS,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<Runs, Run>(table),
                  $RunsReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                lapsRefs = false,
                runGapsRefs = false,
                rawPositionsRefs = false,
                rawHeartRatesRefs = false,
                rawAltitudesRefs = false,
                rawStepsRefs = false,
                preprocessingResultsRefs = false,
                preprocessedSamplesRefs = false,
                preprocessedSpansRefs = false,
                ratedSectionsRefs = false,
                computedValuesRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (lapsRefs) db.laps,
                    if (runGapsRefs) db.runGaps,
                    if (rawPositionsRefs) db.rawPositions,
                    if (rawHeartRatesRefs) db.rawHeartRates,
                    if (rawAltitudesRefs) db.rawAltitudes,
                    if (rawStepsRefs) db.rawSteps,
                    if (preprocessingResultsRefs) db.preprocessingResults,
                    if (preprocessedSamplesRefs) db.preprocessedSamples,
                    if (preprocessedSpansRefs) db.preprocessedSpans,
                    if (ratedSectionsRefs) db.ratedSections,
                    if (computedValuesRefs) db.computedValues,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (lapsRefs)
                        await $_getPrefetchedDataByColumns<
                          Run,
                          Runs,
                          Lap,
                          Laps
                        >(
                          currentTable: table,
                          referencedTable: $RunsReferences._lapsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $RunsReferences(db, table, p0).lapsRefs,
                          currentColumn: 'id',
                          referencedColumn: 'run_id',
                          typedResults: items,
                        ),
                      if (runGapsRefs)
                        await $_getPrefetchedDataByColumns<
                          Run,
                          Runs,
                          RunGap,
                          RunGaps
                        >(
                          currentTable: table,
                          referencedTable: $RunsReferences._runGapsRefsTable(
                            db,
                          ),
                          managerFromTypedResult: (p0) =>
                              $RunsReferences(db, table, p0).runGapsRefs,
                          currentColumn: 'id',
                          referencedColumn: 'run_id',
                          typedResults: items,
                        ),
                      if (rawPositionsRefs)
                        await $_getPrefetchedDataByColumns<
                          Run,
                          Runs,
                          RawPosition,
                          RawPositions
                        >(
                          currentTable: table,
                          referencedTable: $RunsReferences
                              ._rawPositionsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $RunsReferences(db, table, p0).rawPositionsRefs,
                          currentColumn: 'id',
                          referencedColumn: 'run_id',
                          typedResults: items,
                        ),
                      if (rawHeartRatesRefs)
                        await $_getPrefetchedDataByColumns<
                          Run,
                          Runs,
                          RawHeartRate,
                          RawHeartRates
                        >(
                          currentTable: table,
                          referencedTable: $RunsReferences
                              ._rawHeartRatesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $RunsReferences(db, table, p0).rawHeartRatesRefs,
                          currentColumn: 'id',
                          referencedColumn: 'run_id',
                          typedResults: items,
                        ),
                      if (rawAltitudesRefs)
                        await $_getPrefetchedDataByColumns<
                          Run,
                          Runs,
                          RawAltitude,
                          RawAltitudes
                        >(
                          currentTable: table,
                          referencedTable: $RunsReferences
                              ._rawAltitudesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $RunsReferences(db, table, p0).rawAltitudesRefs,
                          currentColumn: 'id',
                          referencedColumn: 'run_id',
                          typedResults: items,
                        ),
                      if (rawStepsRefs)
                        await $_getPrefetchedDataByColumns<
                          Run,
                          Runs,
                          RawStep,
                          RawSteps
                        >(
                          currentTable: table,
                          referencedTable: $RunsReferences._rawStepsRefsTable(
                            db,
                          ),
                          managerFromTypedResult: (p0) =>
                              $RunsReferences(db, table, p0).rawStepsRefs,
                          currentColumn: 'id',
                          referencedColumn: 'run_id',
                          typedResults: items,
                        ),
                      if (preprocessingResultsRefs)
                        await $_getPrefetchedDataByColumns<
                          Run,
                          Runs,
                          PreprocessingResult,
                          PreprocessingResults
                        >(
                          currentTable: table,
                          referencedTable: $RunsReferences
                              ._preprocessingResultsRefsTable(db),
                          managerFromTypedResult: (p0) => $RunsReferences(
                            db,
                            table,
                            p0,
                          ).preprocessingResultsRefs,
                          currentColumn: 'id',
                          referencedColumn: 'run_id',
                          typedResults: items,
                        ),
                      if (preprocessedSamplesRefs)
                        await $_getPrefetchedDataByColumns<
                          Run,
                          Runs,
                          PreprocessedSample,
                          PreprocessedSamples
                        >(
                          currentTable: table,
                          referencedTable: $RunsReferences
                              ._preprocessedSamplesRefsTable(db),
                          managerFromTypedResult: (p0) => $RunsReferences(
                            db,
                            table,
                            p0,
                          ).preprocessedSamplesRefs,
                          currentColumn: 'id',
                          referencedColumn: 'run_id',
                          typedResults: items,
                        ),
                      if (preprocessedSpansRefs)
                        await $_getPrefetchedDataByColumns<
                          Run,
                          Runs,
                          PreprocessedSpan,
                          PreprocessedSpans
                        >(
                          currentTable: table,
                          referencedTable: $RunsReferences
                              ._preprocessedSpansRefsTable(db),
                          managerFromTypedResult: (p0) => $RunsReferences(
                            db,
                            table,
                            p0,
                          ).preprocessedSpansRefs,
                          currentColumn: 'id',
                          referencedColumn: 'run_id',
                          typedResults: items,
                        ),
                      if (ratedSectionsRefs)
                        await $_getPrefetchedDataByColumns<
                          Run,
                          Runs,
                          RatedSection,
                          RatedSections
                        >(
                          currentTable: table,
                          referencedTable: $RunsReferences
                              ._ratedSectionsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $RunsReferences(db, table, p0).ratedSectionsRefs,
                          currentColumn: 'id',
                          referencedColumn: 'run_id',
                          typedResults: items,
                        ),
                      if (computedValuesRefs)
                        await $_getPrefetchedDataByColumns<
                          Run,
                          Runs,
                          ComputedValue,
                          ComputedValues
                        >(
                          currentTable: table,
                          referencedTable: $RunsReferences
                              ._computedValuesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $RunsReferences(db, table, p0).computedValuesRefs,
                          currentColumn: 'id',
                          referencedColumn: 'run_id',
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $RunsProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      Runs,
      Run,
      $RunsFilterComposer,
      $RunsOrderingComposer,
      $RunsAnnotationComposer,
      $RunsCreateCompanionBuilder,
      $RunsUpdateCompanionBuilder,
      (Run, $RunsReferences),
      Run,
      PrefetchHooks Function({
        bool lapsRefs,
        bool runGapsRefs,
        bool rawPositionsRefs,
        bool rawHeartRatesRefs,
        bool rawAltitudesRefs,
        bool rawStepsRefs,
        bool preprocessingResultsRefs,
        bool preprocessedSamplesRefs,
        bool preprocessedSpansRefs,
        bool ratedSectionsRefs,
        bool computedValuesRefs,
      })
    >;
typedef $LapsCreateCompanionBuilder = LapsCompanion Function({
  Value<int> id,
  required int runId,
  required int lapIndex,
  required int markedAtUs,
  required double lapTimeS,
});
typedef $LapsUpdateCompanionBuilder = LapsCompanion Function({
  Value<int> id,
  Value<int> runId,
  Value<int> lapIndex,
  Value<int> markedAtUs,
  Value<double> lapTimeS,
});

final class $LapsReferences extends BaseReferences<_$AppDatabase, Laps, Lap> {
  $LapsReferences(super.$_db, super.$_table, super.$_typedResult);

  static Runs _runIdTable(_$AppDatabase db) =>
      db.runs.createAlias('laps__run_id__runs__id');

  $RunsProcessedTableManager get runId {
    final $_column = $_itemColumn<int>('run_id')!;

    final manager = $RunsTableManager(
      $_db,
      $_db.runs,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_runIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $LapsFilterComposer extends Composer<_$AppDatabase, Laps> {
  $LapsFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lapIndex => $composableBuilder(
    column: $table.lapIndex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get markedAtUs => $composableBuilder(
    column: $table.markedAtUs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get lapTimeS => $composableBuilder(
    column: $table.lapTimeS,
    builder: (column) => ColumnFilters(column),
  );

  $RunsFilterComposer get runId {
    final $RunsFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.runId,
      referencedTable: $db.runs,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $RunsFilterComposer(
            $db: $db,
            $table: $db.runs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $LapsOrderingComposer extends Composer<_$AppDatabase, Laps> {
  $LapsOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lapIndex => $composableBuilder(
    column: $table.lapIndex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get markedAtUs => $composableBuilder(
    column: $table.markedAtUs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get lapTimeS => $composableBuilder(
    column: $table.lapTimeS,
    builder: (column) => ColumnOrderings(column),
  );

  $RunsOrderingComposer get runId {
    final $RunsOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.runId,
      referencedTable: $db.runs,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $RunsOrderingComposer(
            $db: $db,
            $table: $db.runs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $LapsAnnotationComposer extends Composer<_$AppDatabase, Laps> {
  $LapsAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get lapIndex =>
      $composableBuilder(column: $table.lapIndex, builder: (column) => column);

  GeneratedColumn<int> get markedAtUs => $composableBuilder(
    column: $table.markedAtUs,
    builder: (column) => column,
  );

  GeneratedColumn<double> get lapTimeS =>
      $composableBuilder(column: $table.lapTimeS, builder: (column) => column);

  $RunsAnnotationComposer get runId {
    final $RunsAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.runId,
      referencedTable: $db.runs,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $RunsAnnotationComposer(
            $db: $db,
            $table: $db.runs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $LapsTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          Laps,
          Lap,
          $LapsFilterComposer,
          $LapsOrderingComposer,
          $LapsAnnotationComposer,
          $LapsCreateCompanionBuilder,
          $LapsUpdateCompanionBuilder,
          (Lap, $LapsReferences),
          Lap,
          PrefetchHooks Function({bool runId})
        > {
  $LapsTableManager(_$AppDatabase db, Laps table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $LapsFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $LapsOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $LapsAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> runId = const Value.absent(),
                Value<int> lapIndex = const Value.absent(),
                Value<int> markedAtUs = const Value.absent(),
                Value<double> lapTimeS = const Value.absent(),
              }) => LapsCompanion(
                id: id,
                runId: runId,
                lapIndex: lapIndex,
                markedAtUs: markedAtUs,
                lapTimeS: lapTimeS,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int runId,
                required int lapIndex,
                required int markedAtUs,
                required double lapTimeS,
              }) => LapsCompanion.insert(
                id: id,
                runId: runId,
                lapIndex: lapIndex,
                markedAtUs: markedAtUs,
                lapTimeS: lapTimeS,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<Laps, Lap>(table),
                  $LapsReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({runId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (runId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.runId,
                        referencedTable: $LapsReferences._runIdTable(db),
                        referencedColumn: $LapsReferences._runIdTable(db).id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $LapsProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      Laps,
      Lap,
      $LapsFilterComposer,
      $LapsOrderingComposer,
      $LapsAnnotationComposer,
      $LapsCreateCompanionBuilder,
      $LapsUpdateCompanionBuilder,
      (Lap, $LapsReferences),
      Lap,
      PrefetchHooks Function({bool runId})
    >;
typedef $RunGapsCreateCompanionBuilder = RunGapsCompanion Function({
  Value<int> id,
  required int runId,
  required String kind,
  required int startUs,
  Value<int?> endUs,
});
typedef $RunGapsUpdateCompanionBuilder = RunGapsCompanion Function({
  Value<int> id,
  Value<int> runId,
  Value<String> kind,
  Value<int> startUs,
  Value<int?> endUs,
});

final class $RunGapsReferences
    extends BaseReferences<_$AppDatabase, RunGaps, RunGap> {
  $RunGapsReferences(super.$_db, super.$_table, super.$_typedResult);

  static Runs _runIdTable(_$AppDatabase db) =>
      db.runs.createAlias('run_gaps__run_id__runs__id');

  $RunsProcessedTableManager get runId {
    final $_column = $_itemColumn<int>('run_id')!;

    final manager = $RunsTableManager(
      $_db,
      $_db.runs,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_runIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $RunGapsFilterComposer extends Composer<_$AppDatabase, RunGaps> {
  $RunGapsFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get startUs => $composableBuilder(
    column: $table.startUs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get endUs => $composableBuilder(
    column: $table.endUs,
    builder: (column) => ColumnFilters(column),
  );

  $RunsFilterComposer get runId {
    final $RunsFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.runId,
      referencedTable: $db.runs,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $RunsFilterComposer(
            $db: $db,
            $table: $db.runs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $RunGapsOrderingComposer extends Composer<_$AppDatabase, RunGaps> {
  $RunGapsOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get startUs => $composableBuilder(
    column: $table.startUs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get endUs => $composableBuilder(
    column: $table.endUs,
    builder: (column) => ColumnOrderings(column),
  );

  $RunsOrderingComposer get runId {
    final $RunsOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.runId,
      referencedTable: $db.runs,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $RunsOrderingComposer(
            $db: $db,
            $table: $db.runs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $RunGapsAnnotationComposer extends Composer<_$AppDatabase, RunGaps> {
  $RunGapsAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<int> get startUs =>
      $composableBuilder(column: $table.startUs, builder: (column) => column);

  GeneratedColumn<int> get endUs =>
      $composableBuilder(column: $table.endUs, builder: (column) => column);

  $RunsAnnotationComposer get runId {
    final $RunsAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.runId,
      referencedTable: $db.runs,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $RunsAnnotationComposer(
            $db: $db,
            $table: $db.runs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $RunGapsTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          RunGaps,
          RunGap,
          $RunGapsFilterComposer,
          $RunGapsOrderingComposer,
          $RunGapsAnnotationComposer,
          $RunGapsCreateCompanionBuilder,
          $RunGapsUpdateCompanionBuilder,
          (RunGap, $RunGapsReferences),
          RunGap,
          PrefetchHooks Function({bool runId})
        > {
  $RunGapsTableManager(_$AppDatabase db, RunGaps table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $RunGapsFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $RunGapsOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $RunGapsAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> runId = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<int> startUs = const Value.absent(),
                Value<int?> endUs = const Value.absent(),
              }) => RunGapsCompanion(
                id: id,
                runId: runId,
                kind: kind,
                startUs: startUs,
                endUs: endUs,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int runId,
                required String kind,
                required int startUs,
                Value<int?> endUs = const Value.absent(),
              }) => RunGapsCompanion.insert(
                id: id,
                runId: runId,
                kind: kind,
                startUs: startUs,
                endUs: endUs,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<RunGaps, RunGap>(table),
                  $RunGapsReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({runId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (runId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.runId,
                        referencedTable: $RunGapsReferences._runIdTable(db),
                        referencedColumn: $RunGapsReferences._runIdTable(db).id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $RunGapsProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      RunGaps,
      RunGap,
      $RunGapsFilterComposer,
      $RunGapsOrderingComposer,
      $RunGapsAnnotationComposer,
      $RunGapsCreateCompanionBuilder,
      $RunGapsUpdateCompanionBuilder,
      (RunGap, $RunGapsReferences),
      RunGap,
      PrefetchHooks Function({bool runId})
    >;
typedef $RawPositionsCreateCompanionBuilder = RawPositionsCompanion Function({
  Value<int> id,
  required int runId,
  required int timeUs,
  required String source,
  required String state,
  Value<double?> latitudeDeg,
  Value<double?> longitudeDeg,
  Value<double?> accuracyM,
  Value<double?> speedMps,
  Value<double?> speedAccuracyMps,
  Value<double?> verticalAccuracyM,
});
typedef $RawPositionsUpdateCompanionBuilder = RawPositionsCompanion Function({
  Value<int> id,
  Value<int> runId,
  Value<int> timeUs,
  Value<String> source,
  Value<String> state,
  Value<double?> latitudeDeg,
  Value<double?> longitudeDeg,
  Value<double?> accuracyM,
  Value<double?> speedMps,
  Value<double?> speedAccuracyMps,
  Value<double?> verticalAccuracyM,
});

final class $RawPositionsReferences
    extends BaseReferences<_$AppDatabase, RawPositions, RawPosition> {
  $RawPositionsReferences(super.$_db, super.$_table, super.$_typedResult);

  static Runs _runIdTable(_$AppDatabase db) =>
      db.runs.createAlias('raw_positions__run_id__runs__id');

  $RunsProcessedTableManager get runId {
    final $_column = $_itemColumn<int>('run_id')!;

    final manager = $RunsTableManager(
      $_db,
      $_db.runs,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_runIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $RawPositionsFilterComposer
    extends Composer<_$AppDatabase, RawPositions> {
  $RawPositionsFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get timeUs => $composableBuilder(
    column: $table.timeUs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get latitudeDeg => $composableBuilder(
    column: $table.latitudeDeg,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get longitudeDeg => $composableBuilder(
    column: $table.longitudeDeg,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get accuracyM => $composableBuilder(
    column: $table.accuracyM,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get speedMps => $composableBuilder(
    column: $table.speedMps,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get speedAccuracyMps => $composableBuilder(
    column: $table.speedAccuracyMps,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get verticalAccuracyM => $composableBuilder(
    column: $table.verticalAccuracyM,
    builder: (column) => ColumnFilters(column),
  );

  $RunsFilterComposer get runId {
    final $RunsFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.runId,
      referencedTable: $db.runs,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $RunsFilterComposer(
            $db: $db,
            $table: $db.runs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $RawPositionsOrderingComposer
    extends Composer<_$AppDatabase, RawPositions> {
  $RawPositionsOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get timeUs => $composableBuilder(
    column: $table.timeUs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get latitudeDeg => $composableBuilder(
    column: $table.latitudeDeg,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get longitudeDeg => $composableBuilder(
    column: $table.longitudeDeg,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get accuracyM => $composableBuilder(
    column: $table.accuracyM,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get speedMps => $composableBuilder(
    column: $table.speedMps,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get speedAccuracyMps => $composableBuilder(
    column: $table.speedAccuracyMps,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get verticalAccuracyM => $composableBuilder(
    column: $table.verticalAccuracyM,
    builder: (column) => ColumnOrderings(column),
  );

  $RunsOrderingComposer get runId {
    final $RunsOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.runId,
      referencedTable: $db.runs,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $RunsOrderingComposer(
            $db: $db,
            $table: $db.runs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $RawPositionsAnnotationComposer
    extends Composer<_$AppDatabase, RawPositions> {
  $RawPositionsAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get timeUs =>
      $composableBuilder(column: $table.timeUs, builder: (column) => column);

  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumn<String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<double> get latitudeDeg => $composableBuilder(
    column: $table.latitudeDeg,
    builder: (column) => column,
  );

  GeneratedColumn<double> get longitudeDeg => $composableBuilder(
    column: $table.longitudeDeg,
    builder: (column) => column,
  );

  GeneratedColumn<double> get accuracyM =>
      $composableBuilder(column: $table.accuracyM, builder: (column) => column);

  GeneratedColumn<double> get speedMps =>
      $composableBuilder(column: $table.speedMps, builder: (column) => column);

  GeneratedColumn<double> get speedAccuracyMps => $composableBuilder(
    column: $table.speedAccuracyMps,
    builder: (column) => column,
  );

  GeneratedColumn<double> get verticalAccuracyM => $composableBuilder(
    column: $table.verticalAccuracyM,
    builder: (column) => column,
  );

  $RunsAnnotationComposer get runId {
    final $RunsAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.runId,
      referencedTable: $db.runs,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $RunsAnnotationComposer(
            $db: $db,
            $table: $db.runs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $RawPositionsTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          RawPositions,
          RawPosition,
          $RawPositionsFilterComposer,
          $RawPositionsOrderingComposer,
          $RawPositionsAnnotationComposer,
          $RawPositionsCreateCompanionBuilder,
          $RawPositionsUpdateCompanionBuilder,
          (RawPosition, $RawPositionsReferences),
          RawPosition,
          PrefetchHooks Function({bool runId})
        > {
  $RawPositionsTableManager(_$AppDatabase db, RawPositions table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $RawPositionsFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $RawPositionsOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $RawPositionsAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> runId = const Value.absent(),
                Value<int> timeUs = const Value.absent(),
                Value<String> source = const Value.absent(),
                Value<String> state = const Value.absent(),
                Value<double?> latitudeDeg = const Value.absent(),
                Value<double?> longitudeDeg = const Value.absent(),
                Value<double?> accuracyM = const Value.absent(),
                Value<double?> speedMps = const Value.absent(),
                Value<double?> speedAccuracyMps = const Value.absent(),
                Value<double?> verticalAccuracyM = const Value.absent(),
              }) => RawPositionsCompanion(
                id: id,
                runId: runId,
                timeUs: timeUs,
                source: source,
                state: state,
                latitudeDeg: latitudeDeg,
                longitudeDeg: longitudeDeg,
                accuracyM: accuracyM,
                speedMps: speedMps,
                speedAccuracyMps: speedAccuracyMps,
                verticalAccuracyM: verticalAccuracyM,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int runId,
                required int timeUs,
                required String source,
                required String state,
                Value<double?> latitudeDeg = const Value.absent(),
                Value<double?> longitudeDeg = const Value.absent(),
                Value<double?> accuracyM = const Value.absent(),
                Value<double?> speedMps = const Value.absent(),
                Value<double?> speedAccuracyMps = const Value.absent(),
                Value<double?> verticalAccuracyM = const Value.absent(),
              }) => RawPositionsCompanion.insert(
                id: id,
                runId: runId,
                timeUs: timeUs,
                source: source,
                state: state,
                latitudeDeg: latitudeDeg,
                longitudeDeg: longitudeDeg,
                accuracyM: accuracyM,
                speedMps: speedMps,
                speedAccuracyMps: speedAccuracyMps,
                verticalAccuracyM: verticalAccuracyM,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<RawPositions, RawPosition>(table),
                  $RawPositionsReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({runId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (runId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.runId,
                        referencedTable: $RawPositionsReferences._runIdTable(
                          db,
                        ),
                        referencedColumn: $RawPositionsReferences
                            ._runIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $RawPositionsProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      RawPositions,
      RawPosition,
      $RawPositionsFilterComposer,
      $RawPositionsOrderingComposer,
      $RawPositionsAnnotationComposer,
      $RawPositionsCreateCompanionBuilder,
      $RawPositionsUpdateCompanionBuilder,
      (RawPosition, $RawPositionsReferences),
      RawPosition,
      PrefetchHooks Function({bool runId})
    >;
typedef $RawHeartRatesCreateCompanionBuilder = RawHeartRatesCompanion Function({
  Value<int> id,
  required int runId,
  required int timeUs,
  required String source,
  required String state,
  Value<int?> bpm,
  required String contact,
});
typedef $RawHeartRatesUpdateCompanionBuilder = RawHeartRatesCompanion Function({
  Value<int> id,
  Value<int> runId,
  Value<int> timeUs,
  Value<String> source,
  Value<String> state,
  Value<int?> bpm,
  Value<String> contact,
});

final class $RawHeartRatesReferences
    extends BaseReferences<_$AppDatabase, RawHeartRates, RawHeartRate> {
  $RawHeartRatesReferences(super.$_db, super.$_table, super.$_typedResult);

  static Runs _runIdTable(_$AppDatabase db) =>
      db.runs.createAlias('raw_heart_rates__run_id__runs__id');

  $RunsProcessedTableManager get runId {
    final $_column = $_itemColumn<int>('run_id')!;

    final manager = $RunsTableManager(
      $_db,
      $_db.runs,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_runIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $RawHeartRatesFilterComposer
    extends Composer<_$AppDatabase, RawHeartRates> {
  $RawHeartRatesFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get timeUs => $composableBuilder(
    column: $table.timeUs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get bpm => $composableBuilder(
    column: $table.bpm,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get contact => $composableBuilder(
    column: $table.contact,
    builder: (column) => ColumnFilters(column),
  );

  $RunsFilterComposer get runId {
    final $RunsFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.runId,
      referencedTable: $db.runs,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $RunsFilterComposer(
            $db: $db,
            $table: $db.runs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $RawHeartRatesOrderingComposer
    extends Composer<_$AppDatabase, RawHeartRates> {
  $RawHeartRatesOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get timeUs => $composableBuilder(
    column: $table.timeUs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get bpm => $composableBuilder(
    column: $table.bpm,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get contact => $composableBuilder(
    column: $table.contact,
    builder: (column) => ColumnOrderings(column),
  );

  $RunsOrderingComposer get runId {
    final $RunsOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.runId,
      referencedTable: $db.runs,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $RunsOrderingComposer(
            $db: $db,
            $table: $db.runs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $RawHeartRatesAnnotationComposer
    extends Composer<_$AppDatabase, RawHeartRates> {
  $RawHeartRatesAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get timeUs =>
      $composableBuilder(column: $table.timeUs, builder: (column) => column);

  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumn<String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<int> get bpm =>
      $composableBuilder(column: $table.bpm, builder: (column) => column);

  GeneratedColumn<String> get contact =>
      $composableBuilder(column: $table.contact, builder: (column) => column);

  $RunsAnnotationComposer get runId {
    final $RunsAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.runId,
      referencedTable: $db.runs,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $RunsAnnotationComposer(
            $db: $db,
            $table: $db.runs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $RawHeartRatesTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          RawHeartRates,
          RawHeartRate,
          $RawHeartRatesFilterComposer,
          $RawHeartRatesOrderingComposer,
          $RawHeartRatesAnnotationComposer,
          $RawHeartRatesCreateCompanionBuilder,
          $RawHeartRatesUpdateCompanionBuilder,
          (RawHeartRate, $RawHeartRatesReferences),
          RawHeartRate,
          PrefetchHooks Function({bool runId})
        > {
  $RawHeartRatesTableManager(_$AppDatabase db, RawHeartRates table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $RawHeartRatesFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $RawHeartRatesOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $RawHeartRatesAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> runId = const Value.absent(),
                Value<int> timeUs = const Value.absent(),
                Value<String> source = const Value.absent(),
                Value<String> state = const Value.absent(),
                Value<int?> bpm = const Value.absent(),
                Value<String> contact = const Value.absent(),
              }) => RawHeartRatesCompanion(
                id: id,
                runId: runId,
                timeUs: timeUs,
                source: source,
                state: state,
                bpm: bpm,
                contact: contact,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int runId,
                required int timeUs,
                required String source,
                required String state,
                Value<int?> bpm = const Value.absent(),
                required String contact,
              }) => RawHeartRatesCompanion.insert(
                id: id,
                runId: runId,
                timeUs: timeUs,
                source: source,
                state: state,
                bpm: bpm,
                contact: contact,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<RawHeartRates, RawHeartRate>(table),
                  $RawHeartRatesReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({runId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (runId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.runId,
                        referencedTable: $RawHeartRatesReferences._runIdTable(
                          db,
                        ),
                        referencedColumn: $RawHeartRatesReferences
                            ._runIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $RawHeartRatesProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      RawHeartRates,
      RawHeartRate,
      $RawHeartRatesFilterComposer,
      $RawHeartRatesOrderingComposer,
      $RawHeartRatesAnnotationComposer,
      $RawHeartRatesCreateCompanionBuilder,
      $RawHeartRatesUpdateCompanionBuilder,
      (RawHeartRate, $RawHeartRatesReferences),
      RawHeartRate,
      PrefetchHooks Function({bool runId})
    >;
typedef $RawAltitudesCreateCompanionBuilder = RawAltitudesCompanion Function({
  Value<int> id,
  required int runId,
  required int timeUs,
  required String source,
  required String state,
  Value<double?> altitudeM,
  Value<double?> verticalAccuracyM,
});
typedef $RawAltitudesUpdateCompanionBuilder = RawAltitudesCompanion Function({
  Value<int> id,
  Value<int> runId,
  Value<int> timeUs,
  Value<String> source,
  Value<String> state,
  Value<double?> altitudeM,
  Value<double?> verticalAccuracyM,
});

final class $RawAltitudesReferences
    extends BaseReferences<_$AppDatabase, RawAltitudes, RawAltitude> {
  $RawAltitudesReferences(super.$_db, super.$_table, super.$_typedResult);

  static Runs _runIdTable(_$AppDatabase db) =>
      db.runs.createAlias('raw_altitudes__run_id__runs__id');

  $RunsProcessedTableManager get runId {
    final $_column = $_itemColumn<int>('run_id')!;

    final manager = $RunsTableManager(
      $_db,
      $_db.runs,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_runIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $RawAltitudesFilterComposer
    extends Composer<_$AppDatabase, RawAltitudes> {
  $RawAltitudesFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get timeUs => $composableBuilder(
    column: $table.timeUs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get altitudeM => $composableBuilder(
    column: $table.altitudeM,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get verticalAccuracyM => $composableBuilder(
    column: $table.verticalAccuracyM,
    builder: (column) => ColumnFilters(column),
  );

  $RunsFilterComposer get runId {
    final $RunsFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.runId,
      referencedTable: $db.runs,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $RunsFilterComposer(
            $db: $db,
            $table: $db.runs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $RawAltitudesOrderingComposer
    extends Composer<_$AppDatabase, RawAltitudes> {
  $RawAltitudesOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get timeUs => $composableBuilder(
    column: $table.timeUs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get altitudeM => $composableBuilder(
    column: $table.altitudeM,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get verticalAccuracyM => $composableBuilder(
    column: $table.verticalAccuracyM,
    builder: (column) => ColumnOrderings(column),
  );

  $RunsOrderingComposer get runId {
    final $RunsOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.runId,
      referencedTable: $db.runs,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $RunsOrderingComposer(
            $db: $db,
            $table: $db.runs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $RawAltitudesAnnotationComposer
    extends Composer<_$AppDatabase, RawAltitudes> {
  $RawAltitudesAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get timeUs =>
      $composableBuilder(column: $table.timeUs, builder: (column) => column);

  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumn<String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<double> get altitudeM =>
      $composableBuilder(column: $table.altitudeM, builder: (column) => column);

  GeneratedColumn<double> get verticalAccuracyM => $composableBuilder(
    column: $table.verticalAccuracyM,
    builder: (column) => column,
  );

  $RunsAnnotationComposer get runId {
    final $RunsAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.runId,
      referencedTable: $db.runs,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $RunsAnnotationComposer(
            $db: $db,
            $table: $db.runs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $RawAltitudesTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          RawAltitudes,
          RawAltitude,
          $RawAltitudesFilterComposer,
          $RawAltitudesOrderingComposer,
          $RawAltitudesAnnotationComposer,
          $RawAltitudesCreateCompanionBuilder,
          $RawAltitudesUpdateCompanionBuilder,
          (RawAltitude, $RawAltitudesReferences),
          RawAltitude,
          PrefetchHooks Function({bool runId})
        > {
  $RawAltitudesTableManager(_$AppDatabase db, RawAltitudes table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $RawAltitudesFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $RawAltitudesOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $RawAltitudesAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> runId = const Value.absent(),
                Value<int> timeUs = const Value.absent(),
                Value<String> source = const Value.absent(),
                Value<String> state = const Value.absent(),
                Value<double?> altitudeM = const Value.absent(),
                Value<double?> verticalAccuracyM = const Value.absent(),
              }) => RawAltitudesCompanion(
                id: id,
                runId: runId,
                timeUs: timeUs,
                source: source,
                state: state,
                altitudeM: altitudeM,
                verticalAccuracyM: verticalAccuracyM,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int runId,
                required int timeUs,
                required String source,
                required String state,
                Value<double?> altitudeM = const Value.absent(),
                Value<double?> verticalAccuracyM = const Value.absent(),
              }) => RawAltitudesCompanion.insert(
                id: id,
                runId: runId,
                timeUs: timeUs,
                source: source,
                state: state,
                altitudeM: altitudeM,
                verticalAccuracyM: verticalAccuracyM,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<RawAltitudes, RawAltitude>(table),
                  $RawAltitudesReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({runId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (runId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.runId,
                        referencedTable: $RawAltitudesReferences._runIdTable(
                          db,
                        ),
                        referencedColumn: $RawAltitudesReferences
                            ._runIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $RawAltitudesProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      RawAltitudes,
      RawAltitude,
      $RawAltitudesFilterComposer,
      $RawAltitudesOrderingComposer,
      $RawAltitudesAnnotationComposer,
      $RawAltitudesCreateCompanionBuilder,
      $RawAltitudesUpdateCompanionBuilder,
      (RawAltitude, $RawAltitudesReferences),
      RawAltitude,
      PrefetchHooks Function({bool runId})
    >;
typedef $RawStepsCreateCompanionBuilder = RawStepsCompanion Function({
  Value<int> id,
  required int runId,
  required int timeUs,
  required String source,
  required String state,
  Value<int?> stepCount,
});
typedef $RawStepsUpdateCompanionBuilder = RawStepsCompanion Function({
  Value<int> id,
  Value<int> runId,
  Value<int> timeUs,
  Value<String> source,
  Value<String> state,
  Value<int?> stepCount,
});

final class $RawStepsReferences
    extends BaseReferences<_$AppDatabase, RawSteps, RawStep> {
  $RawStepsReferences(super.$_db, super.$_table, super.$_typedResult);

  static Runs _runIdTable(_$AppDatabase db) =>
      db.runs.createAlias('raw_steps__run_id__runs__id');

  $RunsProcessedTableManager get runId {
    final $_column = $_itemColumn<int>('run_id')!;

    final manager = $RunsTableManager(
      $_db,
      $_db.runs,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_runIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $RawStepsFilterComposer extends Composer<_$AppDatabase, RawSteps> {
  $RawStepsFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get timeUs => $composableBuilder(
    column: $table.timeUs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get stepCount => $composableBuilder(
    column: $table.stepCount,
    builder: (column) => ColumnFilters(column),
  );

  $RunsFilterComposer get runId {
    final $RunsFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.runId,
      referencedTable: $db.runs,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $RunsFilterComposer(
            $db: $db,
            $table: $db.runs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $RawStepsOrderingComposer extends Composer<_$AppDatabase, RawSteps> {
  $RawStepsOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get timeUs => $composableBuilder(
    column: $table.timeUs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get stepCount => $composableBuilder(
    column: $table.stepCount,
    builder: (column) => ColumnOrderings(column),
  );

  $RunsOrderingComposer get runId {
    final $RunsOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.runId,
      referencedTable: $db.runs,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $RunsOrderingComposer(
            $db: $db,
            $table: $db.runs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $RawStepsAnnotationComposer extends Composer<_$AppDatabase, RawSteps> {
  $RawStepsAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get timeUs =>
      $composableBuilder(column: $table.timeUs, builder: (column) => column);

  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumn<String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<int> get stepCount =>
      $composableBuilder(column: $table.stepCount, builder: (column) => column);

  $RunsAnnotationComposer get runId {
    final $RunsAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.runId,
      referencedTable: $db.runs,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $RunsAnnotationComposer(
            $db: $db,
            $table: $db.runs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $RawStepsTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          RawSteps,
          RawStep,
          $RawStepsFilterComposer,
          $RawStepsOrderingComposer,
          $RawStepsAnnotationComposer,
          $RawStepsCreateCompanionBuilder,
          $RawStepsUpdateCompanionBuilder,
          (RawStep, $RawStepsReferences),
          RawStep,
          PrefetchHooks Function({bool runId})
        > {
  $RawStepsTableManager(_$AppDatabase db, RawSteps table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $RawStepsFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $RawStepsOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $RawStepsAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> runId = const Value.absent(),
                Value<int> timeUs = const Value.absent(),
                Value<String> source = const Value.absent(),
                Value<String> state = const Value.absent(),
                Value<int?> stepCount = const Value.absent(),
              }) => RawStepsCompanion(
                id: id,
                runId: runId,
                timeUs: timeUs,
                source: source,
                state: state,
                stepCount: stepCount,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int runId,
                required int timeUs,
                required String source,
                required String state,
                Value<int?> stepCount = const Value.absent(),
              }) => RawStepsCompanion.insert(
                id: id,
                runId: runId,
                timeUs: timeUs,
                source: source,
                state: state,
                stepCount: stepCount,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<RawSteps, RawStep>(table),
                  $RawStepsReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({runId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (runId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.runId,
                        referencedTable: $RawStepsReferences._runIdTable(db),
                        referencedColumn: $RawStepsReferences
                            ._runIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $RawStepsProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      RawSteps,
      RawStep,
      $RawStepsFilterComposer,
      $RawStepsOrderingComposer,
      $RawStepsAnnotationComposer,
      $RawStepsCreateCompanionBuilder,
      $RawStepsUpdateCompanionBuilder,
      (RawStep, $RawStepsReferences),
      RawStep,
      PrefetchHooks Function({bool runId})
    >;
typedef $PreprocessingResultsCreateCompanionBuilder =
    PreprocessingResultsCompanion Function({
      Value<int> id,
      required int runId,
      required String method,
      required int methodVersion,
      required int parameterVersion,
      required int computedAtUs,
      Value<double?> totalTimeS,
      Value<double?> movingTimeS,
      Value<double?> distanceM,
      Value<double?> bridgedDistanceM,
      Value<double?> averageBpm,
      Value<int?> maxBpm,
      Value<double?> medianBpm,
      Value<double?> bestPaceSPerKm,
      Value<int?> lapCount,
      Value<double?> heartRateTimeS,
    });
typedef $PreprocessingResultsUpdateCompanionBuilder =
    PreprocessingResultsCompanion Function({
      Value<int> id,
      Value<int> runId,
      Value<String> method,
      Value<int> methodVersion,
      Value<int> parameterVersion,
      Value<int> computedAtUs,
      Value<double?> totalTimeS,
      Value<double?> movingTimeS,
      Value<double?> distanceM,
      Value<double?> bridgedDistanceM,
      Value<double?> averageBpm,
      Value<int?> maxBpm,
      Value<double?> medianBpm,
      Value<double?> bestPaceSPerKm,
      Value<int?> lapCount,
      Value<double?> heartRateTimeS,
    });

final class $PreprocessingResultsReferences
    extends
        BaseReferences<
          _$AppDatabase,
          PreprocessingResults,
          PreprocessingResult
        > {
  $PreprocessingResultsReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static Runs _runIdTable(_$AppDatabase db) =>
      db.runs.createAlias('preprocessing_results__run_id__runs__id');

  $RunsProcessedTableManager get runId {
    final $_column = $_itemColumn<int>('run_id')!;

    final manager = $RunsTableManager(
      $_db,
      $_db.runs,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_runIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $PreprocessingResultsFilterComposer
    extends Composer<_$AppDatabase, PreprocessingResults> {
  $PreprocessingResultsFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get method => $composableBuilder(
    column: $table.method,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get methodVersion => $composableBuilder(
    column: $table.methodVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get parameterVersion => $composableBuilder(
    column: $table.parameterVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get computedAtUs => $composableBuilder(
    column: $table.computedAtUs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get totalTimeS => $composableBuilder(
    column: $table.totalTimeS,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get movingTimeS => $composableBuilder(
    column: $table.movingTimeS,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get distanceM => $composableBuilder(
    column: $table.distanceM,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get bridgedDistanceM => $composableBuilder(
    column: $table.bridgedDistanceM,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get averageBpm => $composableBuilder(
    column: $table.averageBpm,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get maxBpm => $composableBuilder(
    column: $table.maxBpm,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get medianBpm => $composableBuilder(
    column: $table.medianBpm,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get bestPaceSPerKm => $composableBuilder(
    column: $table.bestPaceSPerKm,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lapCount => $composableBuilder(
    column: $table.lapCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get heartRateTimeS => $composableBuilder(
    column: $table.heartRateTimeS,
    builder: (column) => ColumnFilters(column),
  );

  $RunsFilterComposer get runId {
    final $RunsFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.runId,
      referencedTable: $db.runs,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $RunsFilterComposer(
            $db: $db,
            $table: $db.runs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $PreprocessingResultsOrderingComposer
    extends Composer<_$AppDatabase, PreprocessingResults> {
  $PreprocessingResultsOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get method => $composableBuilder(
    column: $table.method,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get methodVersion => $composableBuilder(
    column: $table.methodVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get parameterVersion => $composableBuilder(
    column: $table.parameterVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get computedAtUs => $composableBuilder(
    column: $table.computedAtUs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get totalTimeS => $composableBuilder(
    column: $table.totalTimeS,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get movingTimeS => $composableBuilder(
    column: $table.movingTimeS,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get distanceM => $composableBuilder(
    column: $table.distanceM,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get bridgedDistanceM => $composableBuilder(
    column: $table.bridgedDistanceM,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get averageBpm => $composableBuilder(
    column: $table.averageBpm,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get maxBpm => $composableBuilder(
    column: $table.maxBpm,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get medianBpm => $composableBuilder(
    column: $table.medianBpm,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get bestPaceSPerKm => $composableBuilder(
    column: $table.bestPaceSPerKm,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lapCount => $composableBuilder(
    column: $table.lapCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get heartRateTimeS => $composableBuilder(
    column: $table.heartRateTimeS,
    builder: (column) => ColumnOrderings(column),
  );

  $RunsOrderingComposer get runId {
    final $RunsOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.runId,
      referencedTable: $db.runs,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $RunsOrderingComposer(
            $db: $db,
            $table: $db.runs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $PreprocessingResultsAnnotationComposer
    extends Composer<_$AppDatabase, PreprocessingResults> {
  $PreprocessingResultsAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get method =>
      $composableBuilder(column: $table.method, builder: (column) => column);

  GeneratedColumn<int> get methodVersion => $composableBuilder(
    column: $table.methodVersion,
    builder: (column) => column,
  );

  GeneratedColumn<int> get parameterVersion => $composableBuilder(
    column: $table.parameterVersion,
    builder: (column) => column,
  );

  GeneratedColumn<int> get computedAtUs => $composableBuilder(
    column: $table.computedAtUs,
    builder: (column) => column,
  );

  GeneratedColumn<double> get totalTimeS => $composableBuilder(
    column: $table.totalTimeS,
    builder: (column) => column,
  );

  GeneratedColumn<double> get movingTimeS => $composableBuilder(
    column: $table.movingTimeS,
    builder: (column) => column,
  );

  GeneratedColumn<double> get distanceM =>
      $composableBuilder(column: $table.distanceM, builder: (column) => column);

  GeneratedColumn<double> get bridgedDistanceM => $composableBuilder(
    column: $table.bridgedDistanceM,
    builder: (column) => column,
  );

  GeneratedColumn<double> get averageBpm => $composableBuilder(
    column: $table.averageBpm,
    builder: (column) => column,
  );

  GeneratedColumn<int> get maxBpm =>
      $composableBuilder(column: $table.maxBpm, builder: (column) => column);

  GeneratedColumn<double> get medianBpm =>
      $composableBuilder(column: $table.medianBpm, builder: (column) => column);

  GeneratedColumn<double> get bestPaceSPerKm => $composableBuilder(
    column: $table.bestPaceSPerKm,
    builder: (column) => column,
  );

  GeneratedColumn<int> get lapCount =>
      $composableBuilder(column: $table.lapCount, builder: (column) => column);

  GeneratedColumn<double> get heartRateTimeS => $composableBuilder(
    column: $table.heartRateTimeS,
    builder: (column) => column,
  );

  $RunsAnnotationComposer get runId {
    final $RunsAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.runId,
      referencedTable: $db.runs,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $RunsAnnotationComposer(
            $db: $db,
            $table: $db.runs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $PreprocessingResultsTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          PreprocessingResults,
          PreprocessingResult,
          $PreprocessingResultsFilterComposer,
          $PreprocessingResultsOrderingComposer,
          $PreprocessingResultsAnnotationComposer,
          $PreprocessingResultsCreateCompanionBuilder,
          $PreprocessingResultsUpdateCompanionBuilder,
          (PreprocessingResult, $PreprocessingResultsReferences),
          PreprocessingResult,
          PrefetchHooks Function({bool runId})
        > {
  $PreprocessingResultsTableManager(
    _$AppDatabase db,
    PreprocessingResults table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $PreprocessingResultsFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $PreprocessingResultsOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $PreprocessingResultsAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> runId = const Value.absent(),
                Value<String> method = const Value.absent(),
                Value<int> methodVersion = const Value.absent(),
                Value<int> parameterVersion = const Value.absent(),
                Value<int> computedAtUs = const Value.absent(),
                Value<double?> totalTimeS = const Value.absent(),
                Value<double?> movingTimeS = const Value.absent(),
                Value<double?> distanceM = const Value.absent(),
                Value<double?> bridgedDistanceM = const Value.absent(),
                Value<double?> averageBpm = const Value.absent(),
                Value<int?> maxBpm = const Value.absent(),
                Value<double?> medianBpm = const Value.absent(),
                Value<double?> bestPaceSPerKm = const Value.absent(),
                Value<int?> lapCount = const Value.absent(),
                Value<double?> heartRateTimeS = const Value.absent(),
              }) => PreprocessingResultsCompanion(
                id: id,
                runId: runId,
                method: method,
                methodVersion: methodVersion,
                parameterVersion: parameterVersion,
                computedAtUs: computedAtUs,
                totalTimeS: totalTimeS,
                movingTimeS: movingTimeS,
                distanceM: distanceM,
                bridgedDistanceM: bridgedDistanceM,
                averageBpm: averageBpm,
                maxBpm: maxBpm,
                medianBpm: medianBpm,
                bestPaceSPerKm: bestPaceSPerKm,
                lapCount: lapCount,
                heartRateTimeS: heartRateTimeS,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int runId,
                required String method,
                required int methodVersion,
                required int parameterVersion,
                required int computedAtUs,
                Value<double?> totalTimeS = const Value.absent(),
                Value<double?> movingTimeS = const Value.absent(),
                Value<double?> distanceM = const Value.absent(),
                Value<double?> bridgedDistanceM = const Value.absent(),
                Value<double?> averageBpm = const Value.absent(),
                Value<int?> maxBpm = const Value.absent(),
                Value<double?> medianBpm = const Value.absent(),
                Value<double?> bestPaceSPerKm = const Value.absent(),
                Value<int?> lapCount = const Value.absent(),
                Value<double?> heartRateTimeS = const Value.absent(),
              }) => PreprocessingResultsCompanion.insert(
                id: id,
                runId: runId,
                method: method,
                methodVersion: methodVersion,
                parameterVersion: parameterVersion,
                computedAtUs: computedAtUs,
                totalTimeS: totalTimeS,
                movingTimeS: movingTimeS,
                distanceM: distanceM,
                bridgedDistanceM: bridgedDistanceM,
                averageBpm: averageBpm,
                maxBpm: maxBpm,
                medianBpm: medianBpm,
                bestPaceSPerKm: bestPaceSPerKm,
                lapCount: lapCount,
                heartRateTimeS: heartRateTimeS,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<PreprocessingResults, PreprocessingResult>(table),
                  $PreprocessingResultsReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({runId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (runId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.runId,
                        referencedTable: $PreprocessingResultsReferences
                            ._runIdTable(db),
                        referencedColumn: $PreprocessingResultsReferences
                            ._runIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $PreprocessingResultsProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      PreprocessingResults,
      PreprocessingResult,
      $PreprocessingResultsFilterComposer,
      $PreprocessingResultsOrderingComposer,
      $PreprocessingResultsAnnotationComposer,
      $PreprocessingResultsCreateCompanionBuilder,
      $PreprocessingResultsUpdateCompanionBuilder,
      (PreprocessingResult, $PreprocessingResultsReferences),
      PreprocessingResult,
      PrefetchHooks Function({bool runId})
    >;
typedef $PreprocessedSamplesCreateCompanionBuilder =
    PreprocessedSamplesCompanion Function({
      Value<int> id,
      required int runId,
      required String channel,
      required int rawId,
      required int timeUs,
      required String state,
      Value<String?> discardReason,
    });
typedef $PreprocessedSamplesUpdateCompanionBuilder =
    PreprocessedSamplesCompanion Function({
      Value<int> id,
      Value<int> runId,
      Value<String> channel,
      Value<int> rawId,
      Value<int> timeUs,
      Value<String> state,
      Value<String?> discardReason,
    });

final class $PreprocessedSamplesReferences
    extends
        BaseReferences<_$AppDatabase, PreprocessedSamples, PreprocessedSample> {
  $PreprocessedSamplesReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static Runs _runIdTable(_$AppDatabase db) =>
      db.runs.createAlias('preprocessed_samples__run_id__runs__id');

  $RunsProcessedTableManager get runId {
    final $_column = $_itemColumn<int>('run_id')!;

    final manager = $RunsTableManager(
      $_db,
      $_db.runs,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_runIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $PreprocessedSamplesFilterComposer
    extends Composer<_$AppDatabase, PreprocessedSamples> {
  $PreprocessedSamplesFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get channel => $composableBuilder(
    column: $table.channel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get rawId => $composableBuilder(
    column: $table.rawId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get timeUs => $composableBuilder(
    column: $table.timeUs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get discardReason => $composableBuilder(
    column: $table.discardReason,
    builder: (column) => ColumnFilters(column),
  );

  $RunsFilterComposer get runId {
    final $RunsFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.runId,
      referencedTable: $db.runs,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $RunsFilterComposer(
            $db: $db,
            $table: $db.runs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $PreprocessedSamplesOrderingComposer
    extends Composer<_$AppDatabase, PreprocessedSamples> {
  $PreprocessedSamplesOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get channel => $composableBuilder(
    column: $table.channel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get rawId => $composableBuilder(
    column: $table.rawId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get timeUs => $composableBuilder(
    column: $table.timeUs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get discardReason => $composableBuilder(
    column: $table.discardReason,
    builder: (column) => ColumnOrderings(column),
  );

  $RunsOrderingComposer get runId {
    final $RunsOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.runId,
      referencedTable: $db.runs,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $RunsOrderingComposer(
            $db: $db,
            $table: $db.runs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $PreprocessedSamplesAnnotationComposer
    extends Composer<_$AppDatabase, PreprocessedSamples> {
  $PreprocessedSamplesAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get channel =>
      $composableBuilder(column: $table.channel, builder: (column) => column);

  GeneratedColumn<int> get rawId =>
      $composableBuilder(column: $table.rawId, builder: (column) => column);

  GeneratedColumn<int> get timeUs =>
      $composableBuilder(column: $table.timeUs, builder: (column) => column);

  GeneratedColumn<String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<String> get discardReason => $composableBuilder(
    column: $table.discardReason,
    builder: (column) => column,
  );

  $RunsAnnotationComposer get runId {
    final $RunsAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.runId,
      referencedTable: $db.runs,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $RunsAnnotationComposer(
            $db: $db,
            $table: $db.runs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $PreprocessedSamplesTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          PreprocessedSamples,
          PreprocessedSample,
          $PreprocessedSamplesFilterComposer,
          $PreprocessedSamplesOrderingComposer,
          $PreprocessedSamplesAnnotationComposer,
          $PreprocessedSamplesCreateCompanionBuilder,
          $PreprocessedSamplesUpdateCompanionBuilder,
          (PreprocessedSample, $PreprocessedSamplesReferences),
          PreprocessedSample,
          PrefetchHooks Function({bool runId})
        > {
  $PreprocessedSamplesTableManager(_$AppDatabase db, PreprocessedSamples table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $PreprocessedSamplesFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $PreprocessedSamplesOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $PreprocessedSamplesAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> runId = const Value.absent(),
                Value<String> channel = const Value.absent(),
                Value<int> rawId = const Value.absent(),
                Value<int> timeUs = const Value.absent(),
                Value<String> state = const Value.absent(),
                Value<String?> discardReason = const Value.absent(),
              }) => PreprocessedSamplesCompanion(
                id: id,
                runId: runId,
                channel: channel,
                rawId: rawId,
                timeUs: timeUs,
                state: state,
                discardReason: discardReason,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int runId,
                required String channel,
                required int rawId,
                required int timeUs,
                required String state,
                Value<String?> discardReason = const Value.absent(),
              }) => PreprocessedSamplesCompanion.insert(
                id: id,
                runId: runId,
                channel: channel,
                rawId: rawId,
                timeUs: timeUs,
                state: state,
                discardReason: discardReason,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<PreprocessedSamples, PreprocessedSample>(table),
                  $PreprocessedSamplesReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({runId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (runId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.runId,
                        referencedTable: $PreprocessedSamplesReferences
                            ._runIdTable(db),
                        referencedColumn: $PreprocessedSamplesReferences
                            ._runIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $PreprocessedSamplesProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      PreprocessedSamples,
      PreprocessedSample,
      $PreprocessedSamplesFilterComposer,
      $PreprocessedSamplesOrderingComposer,
      $PreprocessedSamplesAnnotationComposer,
      $PreprocessedSamplesCreateCompanionBuilder,
      $PreprocessedSamplesUpdateCompanionBuilder,
      (PreprocessedSample, $PreprocessedSamplesReferences),
      PreprocessedSample,
      PrefetchHooks Function({bool runId})
    >;
typedef $PreprocessedSpansCreateCompanionBuilder =
    PreprocessedSpansCompanion Function({
      Value<int> id,
      required int runId,
      required String kind,
      required int startUs,
      Value<int?> endUs,
    });
typedef $PreprocessedSpansUpdateCompanionBuilder =
    PreprocessedSpansCompanion Function({
      Value<int> id,
      Value<int> runId,
      Value<String> kind,
      Value<int> startUs,
      Value<int?> endUs,
    });

final class $PreprocessedSpansReferences
    extends BaseReferences<_$AppDatabase, PreprocessedSpans, PreprocessedSpan> {
  $PreprocessedSpansReferences(super.$_db, super.$_table, super.$_typedResult);

  static Runs _runIdTable(_$AppDatabase db) =>
      db.runs.createAlias('preprocessed_spans__run_id__runs__id');

  $RunsProcessedTableManager get runId {
    final $_column = $_itemColumn<int>('run_id')!;

    final manager = $RunsTableManager(
      $_db,
      $_db.runs,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_runIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $PreprocessedSpansFilterComposer
    extends Composer<_$AppDatabase, PreprocessedSpans> {
  $PreprocessedSpansFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get startUs => $composableBuilder(
    column: $table.startUs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get endUs => $composableBuilder(
    column: $table.endUs,
    builder: (column) => ColumnFilters(column),
  );

  $RunsFilterComposer get runId {
    final $RunsFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.runId,
      referencedTable: $db.runs,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $RunsFilterComposer(
            $db: $db,
            $table: $db.runs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $PreprocessedSpansOrderingComposer
    extends Composer<_$AppDatabase, PreprocessedSpans> {
  $PreprocessedSpansOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get startUs => $composableBuilder(
    column: $table.startUs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get endUs => $composableBuilder(
    column: $table.endUs,
    builder: (column) => ColumnOrderings(column),
  );

  $RunsOrderingComposer get runId {
    final $RunsOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.runId,
      referencedTable: $db.runs,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $RunsOrderingComposer(
            $db: $db,
            $table: $db.runs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $PreprocessedSpansAnnotationComposer
    extends Composer<_$AppDatabase, PreprocessedSpans> {
  $PreprocessedSpansAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<int> get startUs =>
      $composableBuilder(column: $table.startUs, builder: (column) => column);

  GeneratedColumn<int> get endUs =>
      $composableBuilder(column: $table.endUs, builder: (column) => column);

  $RunsAnnotationComposer get runId {
    final $RunsAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.runId,
      referencedTable: $db.runs,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $RunsAnnotationComposer(
            $db: $db,
            $table: $db.runs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $PreprocessedSpansTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          PreprocessedSpans,
          PreprocessedSpan,
          $PreprocessedSpansFilterComposer,
          $PreprocessedSpansOrderingComposer,
          $PreprocessedSpansAnnotationComposer,
          $PreprocessedSpansCreateCompanionBuilder,
          $PreprocessedSpansUpdateCompanionBuilder,
          (PreprocessedSpan, $PreprocessedSpansReferences),
          PreprocessedSpan,
          PrefetchHooks Function({bool runId})
        > {
  $PreprocessedSpansTableManager(_$AppDatabase db, PreprocessedSpans table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $PreprocessedSpansFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $PreprocessedSpansOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $PreprocessedSpansAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> runId = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<int> startUs = const Value.absent(),
                Value<int?> endUs = const Value.absent(),
              }) => PreprocessedSpansCompanion(
                id: id,
                runId: runId,
                kind: kind,
                startUs: startUs,
                endUs: endUs,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int runId,
                required String kind,
                required int startUs,
                Value<int?> endUs = const Value.absent(),
              }) => PreprocessedSpansCompanion.insert(
                id: id,
                runId: runId,
                kind: kind,
                startUs: startUs,
                endUs: endUs,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<PreprocessedSpans, PreprocessedSpan>(table),
                  $PreprocessedSpansReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({runId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (runId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.runId,
                        referencedTable: $PreprocessedSpansReferences
                            ._runIdTable(db),
                        referencedColumn: $PreprocessedSpansReferences
                            ._runIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $PreprocessedSpansProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      PreprocessedSpans,
      PreprocessedSpan,
      $PreprocessedSpansFilterComposer,
      $PreprocessedSpansOrderingComposer,
      $PreprocessedSpansAnnotationComposer,
      $PreprocessedSpansCreateCompanionBuilder,
      $PreprocessedSpansUpdateCompanionBuilder,
      (PreprocessedSpan, $PreprocessedSpansReferences),
      PreprocessedSpan,
      PrefetchHooks Function({bool runId})
    >;
typedef $RatedSectionsCreateCompanionBuilder = RatedSectionsCompanion Function({
  Value<int> id,
  required int runId,
  required int startUs,
  required int endUs,
  required String method,
  required int methodVersion,
  required int parameterVersion,
  required int assessedAtUs,
  required int heartRatePresent,
  required int heartRateEstimated,
  required int heartRateUnavailable,
  required int heartRateDiscarded,
  required int positionPresent,
  required int positionEstimated,
  required int positionUnavailable,
  required int positionDiscarded,
  required double missingHeartRateShare,
  required double longestHeartRateGapS,
  required bool meetsHeartRateGapRule,
  required double settlingOverlapS,
  required double settlingShare,
  required String gpsGaps,
});
typedef $RatedSectionsUpdateCompanionBuilder = RatedSectionsCompanion Function({
  Value<int> id,
  Value<int> runId,
  Value<int> startUs,
  Value<int> endUs,
  Value<String> method,
  Value<int> methodVersion,
  Value<int> parameterVersion,
  Value<int> assessedAtUs,
  Value<int> heartRatePresent,
  Value<int> heartRateEstimated,
  Value<int> heartRateUnavailable,
  Value<int> heartRateDiscarded,
  Value<int> positionPresent,
  Value<int> positionEstimated,
  Value<int> positionUnavailable,
  Value<int> positionDiscarded,
  Value<double> missingHeartRateShare,
  Value<double> longestHeartRateGapS,
  Value<bool> meetsHeartRateGapRule,
  Value<double> settlingOverlapS,
  Value<double> settlingShare,
  Value<String> gpsGaps,
});

final class $RatedSectionsReferences
    extends BaseReferences<_$AppDatabase, RatedSections, RatedSection> {
  $RatedSectionsReferences(super.$_db, super.$_table, super.$_typedResult);

  static Runs _runIdTable(_$AppDatabase db) =>
      db.runs.createAlias('rated_sections__run_id__runs__id');

  $RunsProcessedTableManager get runId {
    final $_column = $_itemColumn<int>('run_id')!;

    final manager = $RunsTableManager(
      $_db,
      $_db.runs,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_runIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $RatedSectionsFilterComposer
    extends Composer<_$AppDatabase, RatedSections> {
  $RatedSectionsFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get startUs => $composableBuilder(
    column: $table.startUs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get endUs => $composableBuilder(
    column: $table.endUs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get method => $composableBuilder(
    column: $table.method,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get methodVersion => $composableBuilder(
    column: $table.methodVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get parameterVersion => $composableBuilder(
    column: $table.parameterVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get assessedAtUs => $composableBuilder(
    column: $table.assessedAtUs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get heartRatePresent => $composableBuilder(
    column: $table.heartRatePresent,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get heartRateEstimated => $composableBuilder(
    column: $table.heartRateEstimated,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get heartRateUnavailable => $composableBuilder(
    column: $table.heartRateUnavailable,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get heartRateDiscarded => $composableBuilder(
    column: $table.heartRateDiscarded,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get positionPresent => $composableBuilder(
    column: $table.positionPresent,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get positionEstimated => $composableBuilder(
    column: $table.positionEstimated,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get positionUnavailable => $composableBuilder(
    column: $table.positionUnavailable,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get positionDiscarded => $composableBuilder(
    column: $table.positionDiscarded,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get missingHeartRateShare => $composableBuilder(
    column: $table.missingHeartRateShare,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get longestHeartRateGapS => $composableBuilder(
    column: $table.longestHeartRateGapS,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get meetsHeartRateGapRule => $composableBuilder(
    column: $table.meetsHeartRateGapRule,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get settlingOverlapS => $composableBuilder(
    column: $table.settlingOverlapS,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get settlingShare => $composableBuilder(
    column: $table.settlingShare,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get gpsGaps => $composableBuilder(
    column: $table.gpsGaps,
    builder: (column) => ColumnFilters(column),
  );

  $RunsFilterComposer get runId {
    final $RunsFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.runId,
      referencedTable: $db.runs,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $RunsFilterComposer(
            $db: $db,
            $table: $db.runs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $RatedSectionsOrderingComposer
    extends Composer<_$AppDatabase, RatedSections> {
  $RatedSectionsOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get startUs => $composableBuilder(
    column: $table.startUs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get endUs => $composableBuilder(
    column: $table.endUs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get method => $composableBuilder(
    column: $table.method,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get methodVersion => $composableBuilder(
    column: $table.methodVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get parameterVersion => $composableBuilder(
    column: $table.parameterVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get assessedAtUs => $composableBuilder(
    column: $table.assessedAtUs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get heartRatePresent => $composableBuilder(
    column: $table.heartRatePresent,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get heartRateEstimated => $composableBuilder(
    column: $table.heartRateEstimated,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get heartRateUnavailable => $composableBuilder(
    column: $table.heartRateUnavailable,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get heartRateDiscarded => $composableBuilder(
    column: $table.heartRateDiscarded,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get positionPresent => $composableBuilder(
    column: $table.positionPresent,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get positionEstimated => $composableBuilder(
    column: $table.positionEstimated,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get positionUnavailable => $composableBuilder(
    column: $table.positionUnavailable,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get positionDiscarded => $composableBuilder(
    column: $table.positionDiscarded,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get missingHeartRateShare => $composableBuilder(
    column: $table.missingHeartRateShare,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get longestHeartRateGapS => $composableBuilder(
    column: $table.longestHeartRateGapS,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get meetsHeartRateGapRule => $composableBuilder(
    column: $table.meetsHeartRateGapRule,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get settlingOverlapS => $composableBuilder(
    column: $table.settlingOverlapS,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get settlingShare => $composableBuilder(
    column: $table.settlingShare,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get gpsGaps => $composableBuilder(
    column: $table.gpsGaps,
    builder: (column) => ColumnOrderings(column),
  );

  $RunsOrderingComposer get runId {
    final $RunsOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.runId,
      referencedTable: $db.runs,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $RunsOrderingComposer(
            $db: $db,
            $table: $db.runs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $RatedSectionsAnnotationComposer
    extends Composer<_$AppDatabase, RatedSections> {
  $RatedSectionsAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get startUs =>
      $composableBuilder(column: $table.startUs, builder: (column) => column);

  GeneratedColumn<int> get endUs =>
      $composableBuilder(column: $table.endUs, builder: (column) => column);

  GeneratedColumn<String> get method =>
      $composableBuilder(column: $table.method, builder: (column) => column);

  GeneratedColumn<int> get methodVersion => $composableBuilder(
    column: $table.methodVersion,
    builder: (column) => column,
  );

  GeneratedColumn<int> get parameterVersion => $composableBuilder(
    column: $table.parameterVersion,
    builder: (column) => column,
  );

  GeneratedColumn<int> get assessedAtUs => $composableBuilder(
    column: $table.assessedAtUs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get heartRatePresent => $composableBuilder(
    column: $table.heartRatePresent,
    builder: (column) => column,
  );

  GeneratedColumn<int> get heartRateEstimated => $composableBuilder(
    column: $table.heartRateEstimated,
    builder: (column) => column,
  );

  GeneratedColumn<int> get heartRateUnavailable => $composableBuilder(
    column: $table.heartRateUnavailable,
    builder: (column) => column,
  );

  GeneratedColumn<int> get heartRateDiscarded => $composableBuilder(
    column: $table.heartRateDiscarded,
    builder: (column) => column,
  );

  GeneratedColumn<int> get positionPresent => $composableBuilder(
    column: $table.positionPresent,
    builder: (column) => column,
  );

  GeneratedColumn<int> get positionEstimated => $composableBuilder(
    column: $table.positionEstimated,
    builder: (column) => column,
  );

  GeneratedColumn<int> get positionUnavailable => $composableBuilder(
    column: $table.positionUnavailable,
    builder: (column) => column,
  );

  GeneratedColumn<int> get positionDiscarded => $composableBuilder(
    column: $table.positionDiscarded,
    builder: (column) => column,
  );

  GeneratedColumn<double> get missingHeartRateShare => $composableBuilder(
    column: $table.missingHeartRateShare,
    builder: (column) => column,
  );

  GeneratedColumn<double> get longestHeartRateGapS => $composableBuilder(
    column: $table.longestHeartRateGapS,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get meetsHeartRateGapRule => $composableBuilder(
    column: $table.meetsHeartRateGapRule,
    builder: (column) => column,
  );

  GeneratedColumn<double> get settlingOverlapS => $composableBuilder(
    column: $table.settlingOverlapS,
    builder: (column) => column,
  );

  GeneratedColumn<double> get settlingShare => $composableBuilder(
    column: $table.settlingShare,
    builder: (column) => column,
  );

  GeneratedColumn<String> get gpsGaps =>
      $composableBuilder(column: $table.gpsGaps, builder: (column) => column);

  $RunsAnnotationComposer get runId {
    final $RunsAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.runId,
      referencedTable: $db.runs,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $RunsAnnotationComposer(
            $db: $db,
            $table: $db.runs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $RatedSectionsTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          RatedSections,
          RatedSection,
          $RatedSectionsFilterComposer,
          $RatedSectionsOrderingComposer,
          $RatedSectionsAnnotationComposer,
          $RatedSectionsCreateCompanionBuilder,
          $RatedSectionsUpdateCompanionBuilder,
          (RatedSection, $RatedSectionsReferences),
          RatedSection,
          PrefetchHooks Function({bool runId})
        > {
  $RatedSectionsTableManager(_$AppDatabase db, RatedSections table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $RatedSectionsFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $RatedSectionsOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $RatedSectionsAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> runId = const Value.absent(),
                Value<int> startUs = const Value.absent(),
                Value<int> endUs = const Value.absent(),
                Value<String> method = const Value.absent(),
                Value<int> methodVersion = const Value.absent(),
                Value<int> parameterVersion = const Value.absent(),
                Value<int> assessedAtUs = const Value.absent(),
                Value<int> heartRatePresent = const Value.absent(),
                Value<int> heartRateEstimated = const Value.absent(),
                Value<int> heartRateUnavailable = const Value.absent(),
                Value<int> heartRateDiscarded = const Value.absent(),
                Value<int> positionPresent = const Value.absent(),
                Value<int> positionEstimated = const Value.absent(),
                Value<int> positionUnavailable = const Value.absent(),
                Value<int> positionDiscarded = const Value.absent(),
                Value<double> missingHeartRateShare = const Value.absent(),
                Value<double> longestHeartRateGapS = const Value.absent(),
                Value<bool> meetsHeartRateGapRule = const Value.absent(),
                Value<double> settlingOverlapS = const Value.absent(),
                Value<double> settlingShare = const Value.absent(),
                Value<String> gpsGaps = const Value.absent(),
              }) => RatedSectionsCompanion(
                id: id,
                runId: runId,
                startUs: startUs,
                endUs: endUs,
                method: method,
                methodVersion: methodVersion,
                parameterVersion: parameterVersion,
                assessedAtUs: assessedAtUs,
                heartRatePresent: heartRatePresent,
                heartRateEstimated: heartRateEstimated,
                heartRateUnavailable: heartRateUnavailable,
                heartRateDiscarded: heartRateDiscarded,
                positionPresent: positionPresent,
                positionEstimated: positionEstimated,
                positionUnavailable: positionUnavailable,
                positionDiscarded: positionDiscarded,
                missingHeartRateShare: missingHeartRateShare,
                longestHeartRateGapS: longestHeartRateGapS,
                meetsHeartRateGapRule: meetsHeartRateGapRule,
                settlingOverlapS: settlingOverlapS,
                settlingShare: settlingShare,
                gpsGaps: gpsGaps,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int runId,
                required int startUs,
                required int endUs,
                required String method,
                required int methodVersion,
                required int parameterVersion,
                required int assessedAtUs,
                required int heartRatePresent,
                required int heartRateEstimated,
                required int heartRateUnavailable,
                required int heartRateDiscarded,
                required int positionPresent,
                required int positionEstimated,
                required int positionUnavailable,
                required int positionDiscarded,
                required double missingHeartRateShare,
                required double longestHeartRateGapS,
                required bool meetsHeartRateGapRule,
                required double settlingOverlapS,
                required double settlingShare,
                required String gpsGaps,
              }) => RatedSectionsCompanion.insert(
                id: id,
                runId: runId,
                startUs: startUs,
                endUs: endUs,
                method: method,
                methodVersion: methodVersion,
                parameterVersion: parameterVersion,
                assessedAtUs: assessedAtUs,
                heartRatePresent: heartRatePresent,
                heartRateEstimated: heartRateEstimated,
                heartRateUnavailable: heartRateUnavailable,
                heartRateDiscarded: heartRateDiscarded,
                positionPresent: positionPresent,
                positionEstimated: positionEstimated,
                positionUnavailable: positionUnavailable,
                positionDiscarded: positionDiscarded,
                missingHeartRateShare: missingHeartRateShare,
                longestHeartRateGapS: longestHeartRateGapS,
                meetsHeartRateGapRule: meetsHeartRateGapRule,
                settlingOverlapS: settlingOverlapS,
                settlingShare: settlingShare,
                gpsGaps: gpsGaps,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<RatedSections, RatedSection>(table),
                  $RatedSectionsReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({runId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (runId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.runId,
                        referencedTable: $RatedSectionsReferences._runIdTable(
                          db,
                        ),
                        referencedColumn: $RatedSectionsReferences
                            ._runIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $RatedSectionsProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      RatedSections,
      RatedSection,
      $RatedSectionsFilterComposer,
      $RatedSectionsOrderingComposer,
      $RatedSectionsAnnotationComposer,
      $RatedSectionsCreateCompanionBuilder,
      $RatedSectionsUpdateCompanionBuilder,
      (RatedSection, $RatedSectionsReferences),
      RatedSection,
      PrefetchHooks Function({bool runId})
    >;
typedef $ComputedValuesCreateCompanionBuilder =
    ComputedValuesCompanion Function({
      Value<int> id,
      Value<int?> runId,
      Value<String?> day,
      required String valueKey,
      required String role,
      Value<double?> valueReal,
      required String unit,
      required int computedAtUs,
      Value<int?> dataFromUs,
      Value<int?> dataToUs,
      required int measurementCount,
      required String sources,
      required String method,
      required int methodVersion,
      required int parameterVersion,
      required String quality,
      Value<String?> unavailableReason,
      Value<int?> hrMaxBpm,
      Value<int?> hrRestBpm,
      Value<bool?> hrMaxIsEstimated,
    });
typedef $ComputedValuesUpdateCompanionBuilder =
    ComputedValuesCompanion Function({
      Value<int> id,
      Value<int?> runId,
      Value<String?> day,
      Value<String> valueKey,
      Value<String> role,
      Value<double?> valueReal,
      Value<String> unit,
      Value<int> computedAtUs,
      Value<int?> dataFromUs,
      Value<int?> dataToUs,
      Value<int> measurementCount,
      Value<String> sources,
      Value<String> method,
      Value<int> methodVersion,
      Value<int> parameterVersion,
      Value<String> quality,
      Value<String?> unavailableReason,
      Value<int?> hrMaxBpm,
      Value<int?> hrRestBpm,
      Value<bool?> hrMaxIsEstimated,
    });

final class $ComputedValuesReferences
    extends BaseReferences<_$AppDatabase, ComputedValues, ComputedValue> {
  $ComputedValuesReferences(super.$_db, super.$_table, super.$_typedResult);

  static Runs _runIdTable(_$AppDatabase db) =>
      db.runs.createAlias('computed_values__run_id__runs__id');

  $RunsProcessedTableManager? get runId {
    final $_column = $_itemColumn<int>('run_id');
    if ($_column == null) return null;
    final manager = $RunsTableManager(
      $_db,
      $_db.runs,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_runIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<ValueSections, List<ValueSectionRow>>
  _valueSectionsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.valueSections,
    aliasName: 'computed_values__id__value_sections__computed_value_id',
  );

  $ValueSectionsProcessedTableManager get valueSectionsRefs {
    final manager = $ValueSectionsTableManager(
      $_db,
      $_db.valueSections,
    ).filter((f) => f.computedValueId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_valueSectionsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $ComputedValuesFilterComposer
    extends Composer<_$AppDatabase, ComputedValues> {
  $ComputedValuesFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get day => $composableBuilder(
    column: $table.day,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get valueKey => $composableBuilder(
    column: $table.valueKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get valueReal => $composableBuilder(
    column: $table.valueReal,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get unit => $composableBuilder(
    column: $table.unit,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get computedAtUs => $composableBuilder(
    column: $table.computedAtUs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get dataFromUs => $composableBuilder(
    column: $table.dataFromUs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get dataToUs => $composableBuilder(
    column: $table.dataToUs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get measurementCount => $composableBuilder(
    column: $table.measurementCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sources => $composableBuilder(
    column: $table.sources,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get method => $composableBuilder(
    column: $table.method,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get methodVersion => $composableBuilder(
    column: $table.methodVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get parameterVersion => $composableBuilder(
    column: $table.parameterVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get quality => $composableBuilder(
    column: $table.quality,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get unavailableReason => $composableBuilder(
    column: $table.unavailableReason,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get hrMaxBpm => $composableBuilder(
    column: $table.hrMaxBpm,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get hrRestBpm => $composableBuilder(
    column: $table.hrRestBpm,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get hrMaxIsEstimated => $composableBuilder(
    column: $table.hrMaxIsEstimated,
    builder: (column) => ColumnFilters(column),
  );

  $RunsFilterComposer get runId {
    final $RunsFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.runId,
      referencedTable: $db.runs,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $RunsFilterComposer(
            $db: $db,
            $table: $db.runs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> valueSectionsRefs(
    Expression<bool> Function($ValueSectionsFilterComposer f) f,
  ) {
    final $ValueSectionsFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.valueSections,
      getReferencedColumn: (t) => t.computedValueId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $ValueSectionsFilterComposer(
            $db: $db,
            $table: $db.valueSections,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $ComputedValuesOrderingComposer
    extends Composer<_$AppDatabase, ComputedValues> {
  $ComputedValuesOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get day => $composableBuilder(
    column: $table.day,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get valueKey => $composableBuilder(
    column: $table.valueKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get valueReal => $composableBuilder(
    column: $table.valueReal,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get unit => $composableBuilder(
    column: $table.unit,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get computedAtUs => $composableBuilder(
    column: $table.computedAtUs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get dataFromUs => $composableBuilder(
    column: $table.dataFromUs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get dataToUs => $composableBuilder(
    column: $table.dataToUs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get measurementCount => $composableBuilder(
    column: $table.measurementCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sources => $composableBuilder(
    column: $table.sources,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get method => $composableBuilder(
    column: $table.method,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get methodVersion => $composableBuilder(
    column: $table.methodVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get parameterVersion => $composableBuilder(
    column: $table.parameterVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get quality => $composableBuilder(
    column: $table.quality,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get unavailableReason => $composableBuilder(
    column: $table.unavailableReason,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get hrMaxBpm => $composableBuilder(
    column: $table.hrMaxBpm,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get hrRestBpm => $composableBuilder(
    column: $table.hrRestBpm,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get hrMaxIsEstimated => $composableBuilder(
    column: $table.hrMaxIsEstimated,
    builder: (column) => ColumnOrderings(column),
  );

  $RunsOrderingComposer get runId {
    final $RunsOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.runId,
      referencedTable: $db.runs,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $RunsOrderingComposer(
            $db: $db,
            $table: $db.runs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $ComputedValuesAnnotationComposer
    extends Composer<_$AppDatabase, ComputedValues> {
  $ComputedValuesAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get day =>
      $composableBuilder(column: $table.day, builder: (column) => column);

  GeneratedColumn<String> get valueKey =>
      $composableBuilder(column: $table.valueKey, builder: (column) => column);

  GeneratedColumn<String> get role =>
      $composableBuilder(column: $table.role, builder: (column) => column);

  GeneratedColumn<double> get valueReal =>
      $composableBuilder(column: $table.valueReal, builder: (column) => column);

  GeneratedColumn<String> get unit =>
      $composableBuilder(column: $table.unit, builder: (column) => column);

  GeneratedColumn<int> get computedAtUs => $composableBuilder(
    column: $table.computedAtUs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get dataFromUs => $composableBuilder(
    column: $table.dataFromUs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get dataToUs =>
      $composableBuilder(column: $table.dataToUs, builder: (column) => column);

  GeneratedColumn<int> get measurementCount => $composableBuilder(
    column: $table.measurementCount,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sources =>
      $composableBuilder(column: $table.sources, builder: (column) => column);

  GeneratedColumn<String> get method =>
      $composableBuilder(column: $table.method, builder: (column) => column);

  GeneratedColumn<int> get methodVersion => $composableBuilder(
    column: $table.methodVersion,
    builder: (column) => column,
  );

  GeneratedColumn<int> get parameterVersion => $composableBuilder(
    column: $table.parameterVersion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get quality =>
      $composableBuilder(column: $table.quality, builder: (column) => column);

  GeneratedColumn<String> get unavailableReason => $composableBuilder(
    column: $table.unavailableReason,
    builder: (column) => column,
  );

  GeneratedColumn<int> get hrMaxBpm =>
      $composableBuilder(column: $table.hrMaxBpm, builder: (column) => column);

  GeneratedColumn<int> get hrRestBpm =>
      $composableBuilder(column: $table.hrRestBpm, builder: (column) => column);

  GeneratedColumn<bool> get hrMaxIsEstimated => $composableBuilder(
    column: $table.hrMaxIsEstimated,
    builder: (column) => column,
  );

  $RunsAnnotationComposer get runId {
    final $RunsAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.runId,
      referencedTable: $db.runs,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $RunsAnnotationComposer(
            $db: $db,
            $table: $db.runs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> valueSectionsRefs<T extends Object>(
    Expression<T> Function($ValueSectionsAnnotationComposer a) f,
  ) {
    final $ValueSectionsAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.valueSections,
      getReferencedColumn: (t) => t.computedValueId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $ValueSectionsAnnotationComposer(
            $db: $db,
            $table: $db.valueSections,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $ComputedValuesTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          ComputedValues,
          ComputedValue,
          $ComputedValuesFilterComposer,
          $ComputedValuesOrderingComposer,
          $ComputedValuesAnnotationComposer,
          $ComputedValuesCreateCompanionBuilder,
          $ComputedValuesUpdateCompanionBuilder,
          (ComputedValue, $ComputedValuesReferences),
          ComputedValue,
          PrefetchHooks Function({bool runId, bool valueSectionsRefs})
        > {
  $ComputedValuesTableManager(_$AppDatabase db, ComputedValues table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $ComputedValuesFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $ComputedValuesOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $ComputedValuesAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int?> runId = const Value.absent(),
                Value<String?> day = const Value.absent(),
                Value<String> valueKey = const Value.absent(),
                Value<String> role = const Value.absent(),
                Value<double?> valueReal = const Value.absent(),
                Value<String> unit = const Value.absent(),
                Value<int> computedAtUs = const Value.absent(),
                Value<int?> dataFromUs = const Value.absent(),
                Value<int?> dataToUs = const Value.absent(),
                Value<int> measurementCount = const Value.absent(),
                Value<String> sources = const Value.absent(),
                Value<String> method = const Value.absent(),
                Value<int> methodVersion = const Value.absent(),
                Value<int> parameterVersion = const Value.absent(),
                Value<String> quality = const Value.absent(),
                Value<String?> unavailableReason = const Value.absent(),
                Value<int?> hrMaxBpm = const Value.absent(),
                Value<int?> hrRestBpm = const Value.absent(),
                Value<bool?> hrMaxIsEstimated = const Value.absent(),
              }) => ComputedValuesCompanion(
                id: id,
                runId: runId,
                day: day,
                valueKey: valueKey,
                role: role,
                valueReal: valueReal,
                unit: unit,
                computedAtUs: computedAtUs,
                dataFromUs: dataFromUs,
                dataToUs: dataToUs,
                measurementCount: measurementCount,
                sources: sources,
                method: method,
                methodVersion: methodVersion,
                parameterVersion: parameterVersion,
                quality: quality,
                unavailableReason: unavailableReason,
                hrMaxBpm: hrMaxBpm,
                hrRestBpm: hrRestBpm,
                hrMaxIsEstimated: hrMaxIsEstimated,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int?> runId = const Value.absent(),
                Value<String?> day = const Value.absent(),
                required String valueKey,
                required String role,
                Value<double?> valueReal = const Value.absent(),
                required String unit,
                required int computedAtUs,
                Value<int?> dataFromUs = const Value.absent(),
                Value<int?> dataToUs = const Value.absent(),
                required int measurementCount,
                required String sources,
                required String method,
                required int methodVersion,
                required int parameterVersion,
                required String quality,
                Value<String?> unavailableReason = const Value.absent(),
                Value<int?> hrMaxBpm = const Value.absent(),
                Value<int?> hrRestBpm = const Value.absent(),
                Value<bool?> hrMaxIsEstimated = const Value.absent(),
              }) => ComputedValuesCompanion.insert(
                id: id,
                runId: runId,
                day: day,
                valueKey: valueKey,
                role: role,
                valueReal: valueReal,
                unit: unit,
                computedAtUs: computedAtUs,
                dataFromUs: dataFromUs,
                dataToUs: dataToUs,
                measurementCount: measurementCount,
                sources: sources,
                method: method,
                methodVersion: methodVersion,
                parameterVersion: parameterVersion,
                quality: quality,
                unavailableReason: unavailableReason,
                hrMaxBpm: hrMaxBpm,
                hrRestBpm: hrRestBpm,
                hrMaxIsEstimated: hrMaxIsEstimated,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<ComputedValues, ComputedValue>(table),
                  $ComputedValuesReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({runId = false, valueSectionsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (valueSectionsRefs) db.valueSections,
              ],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (runId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.runId,
                        referencedTable: $ComputedValuesReferences._runIdTable(
                          db,
                        ),
                        referencedColumn: $ComputedValuesReferences
                            ._runIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [
                  if (valueSectionsRefs)
                    await $_getPrefetchedDataByColumns<
                      ComputedValue,
                      ComputedValues,
                      ValueSectionRow,
                      ValueSections
                    >(
                      currentTable: table,
                      referencedTable: $ComputedValuesReferences
                          ._valueSectionsRefsTable(db),
                      managerFromTypedResult: (p0) => $ComputedValuesReferences(
                        db,
                        table,
                        p0,
                      ).valueSectionsRefs,
                      currentColumn: 'id',
                      referencedColumn: 'computed_value_id',
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $ComputedValuesProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      ComputedValues,
      ComputedValue,
      $ComputedValuesFilterComposer,
      $ComputedValuesOrderingComposer,
      $ComputedValuesAnnotationComposer,
      $ComputedValuesCreateCompanionBuilder,
      $ComputedValuesUpdateCompanionBuilder,
      (ComputedValue, $ComputedValuesReferences),
      ComputedValue,
      PrefetchHooks Function({bool runId, bool valueSectionsRefs})
    >;
typedef $ValueSectionsCreateCompanionBuilder = ValueSectionsCompanion Function({
  Value<int> id,
  required int computedValueId,
  required int position,
  required int startUs,
  required int endUs,
  Value<double?> gpsMedianAccuracyM,
  required double weight,
  required double lateFactor,
  required String status,
  Value<String?> discard,
  required String reasons,
  Value<double?> oxygenDemand,
  Value<double?> estimate,
});
typedef $ValueSectionsUpdateCompanionBuilder = ValueSectionsCompanion Function({
  Value<int> id,
  Value<int> computedValueId,
  Value<int> position,
  Value<int> startUs,
  Value<int> endUs,
  Value<double?> gpsMedianAccuracyM,
  Value<double> weight,
  Value<double> lateFactor,
  Value<String> status,
  Value<String?> discard,
  Value<String> reasons,
  Value<double?> oxygenDemand,
  Value<double?> estimate,
});

final class $ValueSectionsReferences
    extends BaseReferences<_$AppDatabase, ValueSections, ValueSectionRow> {
  $ValueSectionsReferences(super.$_db, super.$_table, super.$_typedResult);

  static ComputedValues _computedValueIdTable(_$AppDatabase db) => db
      .computedValues
      .createAlias('value_sections__computed_value_id__computed_values__id');

  $ComputedValuesProcessedTableManager get computedValueId {
    final $_column = $_itemColumn<int>('computed_value_id')!;

    final manager = $ComputedValuesTableManager(
      $_db,
      $_db.computedValues,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_computedValueIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $ValueSectionsFilterComposer
    extends Composer<_$AppDatabase, ValueSections> {
  $ValueSectionsFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get startUs => $composableBuilder(
    column: $table.startUs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get endUs => $composableBuilder(
    column: $table.endUs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get gpsMedianAccuracyM => $composableBuilder(
    column: $table.gpsMedianAccuracyM,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get weight => $composableBuilder(
    column: $table.weight,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get lateFactor => $composableBuilder(
    column: $table.lateFactor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get discard => $composableBuilder(
    column: $table.discard,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get reasons => $composableBuilder(
    column: $table.reasons,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get oxygenDemand => $composableBuilder(
    column: $table.oxygenDemand,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get estimate => $composableBuilder(
    column: $table.estimate,
    builder: (column) => ColumnFilters(column),
  );

  $ComputedValuesFilterComposer get computedValueId {
    final $ComputedValuesFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.computedValueId,
      referencedTable: $db.computedValues,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $ComputedValuesFilterComposer(
            $db: $db,
            $table: $db.computedValues,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $ValueSectionsOrderingComposer
    extends Composer<_$AppDatabase, ValueSections> {
  $ValueSectionsOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get startUs => $composableBuilder(
    column: $table.startUs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get endUs => $composableBuilder(
    column: $table.endUs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get gpsMedianAccuracyM => $composableBuilder(
    column: $table.gpsMedianAccuracyM,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get weight => $composableBuilder(
    column: $table.weight,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get lateFactor => $composableBuilder(
    column: $table.lateFactor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get discard => $composableBuilder(
    column: $table.discard,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get reasons => $composableBuilder(
    column: $table.reasons,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get oxygenDemand => $composableBuilder(
    column: $table.oxygenDemand,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get estimate => $composableBuilder(
    column: $table.estimate,
    builder: (column) => ColumnOrderings(column),
  );

  $ComputedValuesOrderingComposer get computedValueId {
    final $ComputedValuesOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.computedValueId,
      referencedTable: $db.computedValues,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $ComputedValuesOrderingComposer(
            $db: $db,
            $table: $db.computedValues,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $ValueSectionsAnnotationComposer
    extends Composer<_$AppDatabase, ValueSections> {
  $ValueSectionsAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);

  GeneratedColumn<int> get startUs =>
      $composableBuilder(column: $table.startUs, builder: (column) => column);

  GeneratedColumn<int> get endUs =>
      $composableBuilder(column: $table.endUs, builder: (column) => column);

  GeneratedColumn<double> get gpsMedianAccuracyM => $composableBuilder(
    column: $table.gpsMedianAccuracyM,
    builder: (column) => column,
  );

  GeneratedColumn<double> get weight =>
      $composableBuilder(column: $table.weight, builder: (column) => column);

  GeneratedColumn<double> get lateFactor => $composableBuilder(
    column: $table.lateFactor,
    builder: (column) => column,
  );

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get discard =>
      $composableBuilder(column: $table.discard, builder: (column) => column);

  GeneratedColumn<String> get reasons =>
      $composableBuilder(column: $table.reasons, builder: (column) => column);

  GeneratedColumn<double> get oxygenDemand => $composableBuilder(
    column: $table.oxygenDemand,
    builder: (column) => column,
  );

  GeneratedColumn<double> get estimate =>
      $composableBuilder(column: $table.estimate, builder: (column) => column);

  $ComputedValuesAnnotationComposer get computedValueId {
    final $ComputedValuesAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.computedValueId,
      referencedTable: $db.computedValues,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $ComputedValuesAnnotationComposer(
            $db: $db,
            $table: $db.computedValues,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $ValueSectionsTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          ValueSections,
          ValueSectionRow,
          $ValueSectionsFilterComposer,
          $ValueSectionsOrderingComposer,
          $ValueSectionsAnnotationComposer,
          $ValueSectionsCreateCompanionBuilder,
          $ValueSectionsUpdateCompanionBuilder,
          (ValueSectionRow, $ValueSectionsReferences),
          ValueSectionRow,
          PrefetchHooks Function({bool computedValueId})
        > {
  $ValueSectionsTableManager(_$AppDatabase db, ValueSections table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $ValueSectionsFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $ValueSectionsOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $ValueSectionsAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> computedValueId = const Value.absent(),
                Value<int> position = const Value.absent(),
                Value<int> startUs = const Value.absent(),
                Value<int> endUs = const Value.absent(),
                Value<double?> gpsMedianAccuracyM = const Value.absent(),
                Value<double> weight = const Value.absent(),
                Value<double> lateFactor = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String?> discard = const Value.absent(),
                Value<String> reasons = const Value.absent(),
                Value<double?> oxygenDemand = const Value.absent(),
                Value<double?> estimate = const Value.absent(),
              }) => ValueSectionsCompanion(
                id: id,
                computedValueId: computedValueId,
                position: position,
                startUs: startUs,
                endUs: endUs,
                gpsMedianAccuracyM: gpsMedianAccuracyM,
                weight: weight,
                lateFactor: lateFactor,
                status: status,
                discard: discard,
                reasons: reasons,
                oxygenDemand: oxygenDemand,
                estimate: estimate,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int computedValueId,
                required int position,
                required int startUs,
                required int endUs,
                Value<double?> gpsMedianAccuracyM = const Value.absent(),
                required double weight,
                required double lateFactor,
                required String status,
                Value<String?> discard = const Value.absent(),
                required String reasons,
                Value<double?> oxygenDemand = const Value.absent(),
                Value<double?> estimate = const Value.absent(),
              }) => ValueSectionsCompanion.insert(
                id: id,
                computedValueId: computedValueId,
                position: position,
                startUs: startUs,
                endUs: endUs,
                gpsMedianAccuracyM: gpsMedianAccuracyM,
                weight: weight,
                lateFactor: lateFactor,
                status: status,
                discard: discard,
                reasons: reasons,
                oxygenDemand: oxygenDemand,
                estimate: estimate,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<ValueSections, ValueSectionRow>(table),
                  $ValueSectionsReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({computedValueId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (computedValueId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.computedValueId,
                        referencedTable: $ValueSectionsReferences
                            ._computedValueIdTable(db),
                        referencedColumn: $ValueSectionsReferences
                            ._computedValueIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $ValueSectionsProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      ValueSections,
      ValueSectionRow,
      $ValueSectionsFilterComposer,
      $ValueSectionsOrderingComposer,
      $ValueSectionsAnnotationComposer,
      $ValueSectionsCreateCompanionBuilder,
      $ValueSectionsUpdateCompanionBuilder,
      (ValueSectionRow, $ValueSectionsReferences),
      ValueSectionRow,
      PrefetchHooks Function({bool computedValueId})
    >;
typedef $ProfileCreateCompanionBuilder = ProfileCompanion Function({
  Value<int> id,
  Value<int?> birthYear,
  Value<double?> bodyWeightKg,
  Value<double?> bodyHeightM,
  Value<int?> restingHeartRateBpm,
  Value<int?> maxHeartRateBpm,
  Value<int?> weeklyRunMinutes,
  Value<int?> trainingDaysMask,
  Value<int?> usualTrainingMinutes,
});
typedef $ProfileUpdateCompanionBuilder = ProfileCompanion Function({
  Value<int> id,
  Value<int?> birthYear,
  Value<double?> bodyWeightKg,
  Value<double?> bodyHeightM,
  Value<int?> restingHeartRateBpm,
  Value<int?> maxHeartRateBpm,
  Value<int?> weeklyRunMinutes,
  Value<int?> trainingDaysMask,
  Value<int?> usualTrainingMinutes,
});

class $ProfileFilterComposer extends Composer<_$AppDatabase, Profile> {
  $ProfileFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get birthYear => $composableBuilder(
    column: $table.birthYear,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get bodyWeightKg => $composableBuilder(
    column: $table.bodyWeightKg,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get bodyHeightM => $composableBuilder(
    column: $table.bodyHeightM,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get restingHeartRateBpm => $composableBuilder(
    column: $table.restingHeartRateBpm,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get maxHeartRateBpm => $composableBuilder(
    column: $table.maxHeartRateBpm,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get weeklyRunMinutes => $composableBuilder(
    column: $table.weeklyRunMinutes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get trainingDaysMask => $composableBuilder(
    column: $table.trainingDaysMask,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get usualTrainingMinutes => $composableBuilder(
    column: $table.usualTrainingMinutes,
    builder: (column) => ColumnFilters(column),
  );
}

class $ProfileOrderingComposer extends Composer<_$AppDatabase, Profile> {
  $ProfileOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get birthYear => $composableBuilder(
    column: $table.birthYear,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get bodyWeightKg => $composableBuilder(
    column: $table.bodyWeightKg,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get bodyHeightM => $composableBuilder(
    column: $table.bodyHeightM,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get restingHeartRateBpm => $composableBuilder(
    column: $table.restingHeartRateBpm,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get maxHeartRateBpm => $composableBuilder(
    column: $table.maxHeartRateBpm,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get weeklyRunMinutes => $composableBuilder(
    column: $table.weeklyRunMinutes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get trainingDaysMask => $composableBuilder(
    column: $table.trainingDaysMask,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get usualTrainingMinutes => $composableBuilder(
    column: $table.usualTrainingMinutes,
    builder: (column) => ColumnOrderings(column),
  );
}

class $ProfileAnnotationComposer extends Composer<_$AppDatabase, Profile> {
  $ProfileAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get birthYear =>
      $composableBuilder(column: $table.birthYear, builder: (column) => column);

  GeneratedColumn<double> get bodyWeightKg => $composableBuilder(
    column: $table.bodyWeightKg,
    builder: (column) => column,
  );

  GeneratedColumn<double> get bodyHeightM => $composableBuilder(
    column: $table.bodyHeightM,
    builder: (column) => column,
  );

  GeneratedColumn<int> get restingHeartRateBpm => $composableBuilder(
    column: $table.restingHeartRateBpm,
    builder: (column) => column,
  );

  GeneratedColumn<int> get maxHeartRateBpm => $composableBuilder(
    column: $table.maxHeartRateBpm,
    builder: (column) => column,
  );

  GeneratedColumn<int> get weeklyRunMinutes => $composableBuilder(
    column: $table.weeklyRunMinutes,
    builder: (column) => column,
  );

  GeneratedColumn<int> get trainingDaysMask => $composableBuilder(
    column: $table.trainingDaysMask,
    builder: (column) => column,
  );

  GeneratedColumn<int> get usualTrainingMinutes => $composableBuilder(
    column: $table.usualTrainingMinutes,
    builder: (column) => column,
  );
}

class $ProfileTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          Profile,
          ProfileData,
          $ProfileFilterComposer,
          $ProfileOrderingComposer,
          $ProfileAnnotationComposer,
          $ProfileCreateCompanionBuilder,
          $ProfileUpdateCompanionBuilder,
          (ProfileData, BaseReferences<_$AppDatabase, Profile, ProfileData>),
          ProfileData,
          PrefetchHooks Function()
        > {
  $ProfileTableManager(_$AppDatabase db, Profile table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $ProfileFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $ProfileOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $ProfileAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int?> birthYear = const Value.absent(),
                Value<double?> bodyWeightKg = const Value.absent(),
                Value<double?> bodyHeightM = const Value.absent(),
                Value<int?> restingHeartRateBpm = const Value.absent(),
                Value<int?> maxHeartRateBpm = const Value.absent(),
                Value<int?> weeklyRunMinutes = const Value.absent(),
                Value<int?> trainingDaysMask = const Value.absent(),
                Value<int?> usualTrainingMinutes = const Value.absent(),
              }) => ProfileCompanion(
                id: id,
                birthYear: birthYear,
                bodyWeightKg: bodyWeightKg,
                bodyHeightM: bodyHeightM,
                restingHeartRateBpm: restingHeartRateBpm,
                maxHeartRateBpm: maxHeartRateBpm,
                weeklyRunMinutes: weeklyRunMinutes,
                trainingDaysMask: trainingDaysMask,
                usualTrainingMinutes: usualTrainingMinutes,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int?> birthYear = const Value.absent(),
                Value<double?> bodyWeightKg = const Value.absent(),
                Value<double?> bodyHeightM = const Value.absent(),
                Value<int?> restingHeartRateBpm = const Value.absent(),
                Value<int?> maxHeartRateBpm = const Value.absent(),
                Value<int?> weeklyRunMinutes = const Value.absent(),
                Value<int?> trainingDaysMask = const Value.absent(),
                Value<int?> usualTrainingMinutes = const Value.absent(),
              }) => ProfileCompanion.insert(
                id: id,
                birthYear: birthYear,
                bodyWeightKg: bodyWeightKg,
                bodyHeightM: bodyHeightM,
                restingHeartRateBpm: restingHeartRateBpm,
                maxHeartRateBpm: maxHeartRateBpm,
                weeklyRunMinutes: weeklyRunMinutes,
                trainingDaysMask: trainingDaysMask,
                usualTrainingMinutes: usualTrainingMinutes,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<Profile, ProfileData>(table),
                  BaseReferences<_$AppDatabase, Profile, ProfileData>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $ProfileProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      Profile,
      ProfileData,
      $ProfileFilterComposer,
      $ProfileOrderingComposer,
      $ProfileAnnotationComposer,
      $ProfileCreateCompanionBuilder,
      $ProfileUpdateCompanionBuilder,
      (ProfileData, BaseReferences<_$AppDatabase, Profile, ProfileData>),
      ProfileData,
      PrefetchHooks Function()
    >;
typedef $SettingsCreateCompanionBuilder = SettingsCompanion Function({
  required String key,
  required String value,
  required int updatedAtUs,
  Value<int> rowid,
});
typedef $SettingsUpdateCompanionBuilder = SettingsCompanion Function({
  Value<String> key,
  Value<String> value,
  Value<int> updatedAtUs,
  Value<int> rowid,
});

class $SettingsFilterComposer extends Composer<_$AppDatabase, Settings> {
  $SettingsFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAtUs => $composableBuilder(
    column: $table.updatedAtUs,
    builder: (column) => ColumnFilters(column),
  );
}

class $SettingsOrderingComposer extends Composer<_$AppDatabase, Settings> {
  $SettingsOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAtUs => $composableBuilder(
    column: $table.updatedAtUs,
    builder: (column) => ColumnOrderings(column),
  );
}

class $SettingsAnnotationComposer extends Composer<_$AppDatabase, Settings> {
  $SettingsAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);

  GeneratedColumn<int> get updatedAtUs => $composableBuilder(
    column: $table.updatedAtUs,
    builder: (column) => column,
  );
}

class $SettingsTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          Settings,
          Setting,
          $SettingsFilterComposer,
          $SettingsOrderingComposer,
          $SettingsAnnotationComposer,
          $SettingsCreateCompanionBuilder,
          $SettingsUpdateCompanionBuilder,
          (Setting, BaseReferences<_$AppDatabase, Settings, Setting>),
          Setting,
          PrefetchHooks Function()
        > {
  $SettingsTableManager(_$AppDatabase db, Settings table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $SettingsFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $SettingsOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $SettingsAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> value = const Value.absent(),
                Value<int> updatedAtUs = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SettingsCompanion(
                key: key,
                value: value,
                updatedAtUs: updatedAtUs,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String key,
                required String value,
                required int updatedAtUs,
                Value<int> rowid = const Value.absent(),
              }) => SettingsCompanion.insert(
                key: key,
                value: value,
                updatedAtUs: updatedAtUs,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<Settings, Setting>(table),
                  BaseReferences<_$AppDatabase, Settings, Setting>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $SettingsProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      Settings,
      Setting,
      $SettingsFilterComposer,
      $SettingsOrderingComposer,
      $SettingsAnnotationComposer,
      $SettingsCreateCompanionBuilder,
      $SettingsUpdateCompanionBuilder,
      (Setting, BaseReferences<_$AppDatabase, Settings, Setting>),
      Setting,
      PrefetchHooks Function()
    >;
typedef $KnownDevicesCreateCompanionBuilder = KnownDevicesCompanion Function({
  Value<int> id,
  required String deviceId,
  Value<String?> displayName,
  Value<bool> isPreferred,
  required int addedAtUs,
});
typedef $KnownDevicesUpdateCompanionBuilder = KnownDevicesCompanion Function({
  Value<int> id,
  Value<String> deviceId,
  Value<String?> displayName,
  Value<bool> isPreferred,
  Value<int> addedAtUs,
});

class $KnownDevicesFilterComposer
    extends Composer<_$AppDatabase, KnownDevices> {
  $KnownDevicesFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isPreferred => $composableBuilder(
    column: $table.isPreferred,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get addedAtUs => $composableBuilder(
    column: $table.addedAtUs,
    builder: (column) => ColumnFilters(column),
  );
}

class $KnownDevicesOrderingComposer
    extends Composer<_$AppDatabase, KnownDevices> {
  $KnownDevicesOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isPreferred => $composableBuilder(
    column: $table.isPreferred,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get addedAtUs => $composableBuilder(
    column: $table.addedAtUs,
    builder: (column) => ColumnOrderings(column),
  );
}

class $KnownDevicesAnnotationComposer
    extends Composer<_$AppDatabase, KnownDevices> {
  $KnownDevicesAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isPreferred => $composableBuilder(
    column: $table.isPreferred,
    builder: (column) => column,
  );

  GeneratedColumn<int> get addedAtUs =>
      $composableBuilder(column: $table.addedAtUs, builder: (column) => column);
}

class $KnownDevicesTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          KnownDevices,
          KnownDevice,
          $KnownDevicesFilterComposer,
          $KnownDevicesOrderingComposer,
          $KnownDevicesAnnotationComposer,
          $KnownDevicesCreateCompanionBuilder,
          $KnownDevicesUpdateCompanionBuilder,
          (
            KnownDevice,
            BaseReferences<_$AppDatabase, KnownDevices, KnownDevice>,
          ),
          KnownDevice,
          PrefetchHooks Function()
        > {
  $KnownDevicesTableManager(_$AppDatabase db, KnownDevices table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $KnownDevicesFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $KnownDevicesOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $KnownDevicesAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> deviceId = const Value.absent(),
                Value<String?> displayName = const Value.absent(),
                Value<bool> isPreferred = const Value.absent(),
                Value<int> addedAtUs = const Value.absent(),
              }) => KnownDevicesCompanion(
                id: id,
                deviceId: deviceId,
                displayName: displayName,
                isPreferred: isPreferred,
                addedAtUs: addedAtUs,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String deviceId,
                Value<String?> displayName = const Value.absent(),
                Value<bool> isPreferred = const Value.absent(),
                required int addedAtUs,
              }) => KnownDevicesCompanion.insert(
                id: id,
                deviceId: deviceId,
                displayName: displayName,
                isPreferred: isPreferred,
                addedAtUs: addedAtUs,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<KnownDevices, KnownDevice>(table),
                  BaseReferences<_$AppDatabase, KnownDevices, KnownDevice>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $KnownDevicesProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      KnownDevices,
      KnownDevice,
      $KnownDevicesFilterComposer,
      $KnownDevicesOrderingComposer,
      $KnownDevicesAnnotationComposer,
      $KnownDevicesCreateCompanionBuilder,
      $KnownDevicesUpdateCompanionBuilder,
      (KnownDevice, BaseReferences<_$AppDatabase, KnownDevices, KnownDevice>),
      KnownDevice,
      PrefetchHooks Function()
    >;
typedef $ConsentsCreateCompanionBuilder = ConsentsCompanion Function({
  required String sourceKey,
  required String state,
  required int changedAtUs,
  Value<int> rowid,
});
typedef $ConsentsUpdateCompanionBuilder = ConsentsCompanion Function({
  Value<String> sourceKey,
  Value<String> state,
  Value<int> changedAtUs,
  Value<int> rowid,
});

class $ConsentsFilterComposer extends Composer<_$AppDatabase, Consents> {
  $ConsentsFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get sourceKey => $composableBuilder(
    column: $table.sourceKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get changedAtUs => $composableBuilder(
    column: $table.changedAtUs,
    builder: (column) => ColumnFilters(column),
  );
}

class $ConsentsOrderingComposer extends Composer<_$AppDatabase, Consents> {
  $ConsentsOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get sourceKey => $composableBuilder(
    column: $table.sourceKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get changedAtUs => $composableBuilder(
    column: $table.changedAtUs,
    builder: (column) => ColumnOrderings(column),
  );
}

class $ConsentsAnnotationComposer extends Composer<_$AppDatabase, Consents> {
  $ConsentsAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get sourceKey =>
      $composableBuilder(column: $table.sourceKey, builder: (column) => column);

  GeneratedColumn<String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<int> get changedAtUs => $composableBuilder(
    column: $table.changedAtUs,
    builder: (column) => column,
  );
}

class $ConsentsTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          Consents,
          Consent,
          $ConsentsFilterComposer,
          $ConsentsOrderingComposer,
          $ConsentsAnnotationComposer,
          $ConsentsCreateCompanionBuilder,
          $ConsentsUpdateCompanionBuilder,
          (Consent, BaseReferences<_$AppDatabase, Consents, Consent>),
          Consent,
          PrefetchHooks Function()
        > {
  $ConsentsTableManager(_$AppDatabase db, Consents table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $ConsentsFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $ConsentsOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $ConsentsAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> sourceKey = const Value.absent(),
                Value<String> state = const Value.absent(),
                Value<int> changedAtUs = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ConsentsCompanion(
                sourceKey: sourceKey,
                state: state,
                changedAtUs: changedAtUs,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String sourceKey,
                required String state,
                required int changedAtUs,
                Value<int> rowid = const Value.absent(),
              }) => ConsentsCompanion.insert(
                sourceKey: sourceKey,
                state: state,
                changedAtUs: changedAtUs,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<Consents, Consent>(table),
                  BaseReferences<_$AppDatabase, Consents, Consent>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $ConsentsProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      Consents,
      Consent,
      $ConsentsFilterComposer,
      $ConsentsOrderingComposer,
      $ConsentsAnnotationComposer,
      $ConsentsCreateCompanionBuilder,
      $ConsentsUpdateCompanionBuilder,
      (Consent, BaseReferences<_$AppDatabase, Consents, Consent>),
      Consent,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $StorageMetaTableManager get storageMeta =>
      $StorageMetaTableManager(_db, _db.storageMeta);
  $RunsTableManager get runs => $RunsTableManager(_db, _db.runs);
  $LapsTableManager get laps => $LapsTableManager(_db, _db.laps);
  $RunGapsTableManager get runGaps => $RunGapsTableManager(_db, _db.runGaps);
  $RawPositionsTableManager get rawPositions =>
      $RawPositionsTableManager(_db, _db.rawPositions);
  $RawHeartRatesTableManager get rawHeartRates =>
      $RawHeartRatesTableManager(_db, _db.rawHeartRates);
  $RawAltitudesTableManager get rawAltitudes =>
      $RawAltitudesTableManager(_db, _db.rawAltitudes);
  $RawStepsTableManager get rawSteps =>
      $RawStepsTableManager(_db, _db.rawSteps);
  $PreprocessingResultsTableManager get preprocessingResults =>
      $PreprocessingResultsTableManager(_db, _db.preprocessingResults);
  $PreprocessedSamplesTableManager get preprocessedSamples =>
      $PreprocessedSamplesTableManager(_db, _db.preprocessedSamples);
  $PreprocessedSpansTableManager get preprocessedSpans =>
      $PreprocessedSpansTableManager(_db, _db.preprocessedSpans);
  $RatedSectionsTableManager get ratedSections =>
      $RatedSectionsTableManager(_db, _db.ratedSections);
  $ComputedValuesTableManager get computedValues =>
      $ComputedValuesTableManager(_db, _db.computedValues);
  $ValueSectionsTableManager get valueSections =>
      $ValueSectionsTableManager(_db, _db.valueSections);
  $ProfileTableManager get profile => $ProfileTableManager(_db, _db.profile);
  $SettingsTableManager get settings =>
      $SettingsTableManager(_db, _db.settings);
  $KnownDevicesTableManager get knownDevices =>
      $KnownDevicesTableManager(_db, _db.knownDevices);
  $ConsentsTableManager get consents =>
      $ConsentsTableManager(_db, _db.consents);
}
