import 'package:flutter/services.dart';

import 'health_connect_port.dart';

/// Kanalname zu `HealthConnectChannel.kt`; dieselbe Zeichenkette steht dort.
const String healthChannelName = 'ramuri/health';

/// [HealthConnectPort] über den Kanal `ramuri/health` (ADR-0007). Keine Logik, nur Umwandlung; nichts davon geht in
/// ein Log. Ein fehlender Kanal (kein Android) heißt „nicht verfügbar“.
class MethodChannelHealthConnect implements HealthConnectPort {
  MethodChannelHealthConnect({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(healthChannelName);

  final MethodChannel _channel;

  @override
  Future<HealthSdkStatus> sdkStatus() async {
    try {
      return switch (await _channel.invokeMethod<String>('sdkStatus')) {
        'available' => HealthSdkStatus.available,
        'update_required' => HealthSdkStatus.updateRequired,
        _ => HealthSdkStatus.unavailable,
      };
    } on PlatformException {
      return HealthSdkStatus.unavailable;
    } on MissingPluginException {
      return HealthSdkStatus.unavailable;
    }
  }

  @override
  Future<Set<HealthDataKind>> grantedKinds() async =>
      _kinds(await _call<List<Object?>>('grantedKinds'));

  @override
  Future<Set<HealthDataKind>> requestPermissions(
    Set<HealthDataKind> kinds,
  ) async => _kinds(
    await _call<List<Object?>>('requestPermissions', {
      'kinds': [for (final k in kinds) k.key],
    }),
  );

  @override
  Future<HealthPage> readPage({
    required HealthDataKind kind,
    required DateTime from,
    required DateTime to,
    String? pageToken,
    int? pageSize,
  }) async {
    final raw = await _call<Map<Object?, Object?>>('readPage', {
      'kind': kind.key,
      'fromMs': from.toUtc().millisecondsSinceEpoch,
      'toMs': to.toUtc().millisecondsSinceEpoch,
      'pageToken': pageToken,
      'pageSize': pageSize,
    });
    final records = raw['records'];
    if (records is! List)
      throw const HealthReadException(HealthReadError.other);
    final next = raw['nextToken'];
    return HealthPage([
      for (final r in records) _record(kind, r as Map<Object?, Object?>),
    ], next is String && next.isNotEmpty ? next : null);
  }

  Future<T> _call<T>(String method, [Map<String, Object?>? args]) async {
    try {
      final v = await _channel.invokeMethod<T>(method, args);
      if (v == null) throw const HealthReadException(HealthReadError.other);
      return v;
    } on PlatformException catch (e) {
      throw HealthReadException(switch (e.code) {
        'permission_missing' => HealthReadError.permissionMissing,
        'bad_arguments' => HealthReadError.badArguments,
        'rate_limited' => HealthReadError.rateLimited,
        'unavailable' => HealthReadError.unavailable,
        'busy' => HealthReadError.busy,
        _ => HealthReadError.other,
      });
    } on MissingPluginException {
      throw const HealthReadException(HealthReadError.unavailable);
    }
  }

  static Set<HealthDataKind> _kinds(List<Object?> keys) => {
    for (final k in keys)
      for (final kind in HealthDataKind.values)
        if (kind.key == k) kind,
  };

  static DateTime _time(Object? ms) =>
      DateTime.fromMillisecondsSinceEpoch((ms! as num).toInt(), isUtc: true);

  static HealthRecord _record(HealthDataKind kind, Map<Object?, Object?> m) =>
      HealthRecord(
        kind: kind,
        id: m['id']! as String,
        origin: m['origin']! as String,
        start: _time(m['startMs']),
        end: _time(m['endMs']),
        offsetSeconds: (m['offsetSeconds'] as num?)?.toInt(),
        value: (m['value'] as num?)?.toDouble(),
        unit: m['unit'] as String?,
        exerciseType: (m['exerciseType'] as num?)?.toInt(),
        samples: [
          for (final s in (m['samples'] as List?) ?? const [])
            HealthHeartRateSample(_time((s as List)[0]), (s[1] as num).toInt()),
        ],
        stages: [
          for (final s in (m['stages'] as List?) ?? const [])
            HealthSleepStage(
              _time((s as List)[0]),
              _time(s[1]),
              (s[2] as num).toInt(),
            ),
        ],
      );
}
