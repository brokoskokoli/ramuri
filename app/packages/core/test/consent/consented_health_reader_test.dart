import 'package:core/core.dart';
import 'package:test/test.dart';

/// Zählender Leser: merkt jeden Aufruf mit seinen Argumenten.
class _CountingReader implements HealthConnectReader {
  final calls = <(HealthDataKind, String?, int?)>[];
  Future<void> Function()? onRead;

  @override
  Future<HealthPage> readPage({
    required HealthDataKind kind,
    required DateTime from,
    required DateTime to,
    String? pageToken,
    int? pageSize,
  }) async {
    calls.add((kind, pageToken, pageSize));
    await onRead?.call();
    return HealthPage([
      HealthRecord(
        kind: kind,
        id: 'r${calls.length}',
        origin: 'app.a',
        start: from,
        end: from,
        value: 50,
      ),
    ], 'next');
  }
}

class _Consents implements ConsentStore {
  final data = <String, ConsentState>{};
  @override
  Future<ConsentState?> get(String k) async => data[k];
  @override
  Future<Map<String, ConsentState>> all() async => data;
  @override
  Future<void> set(String k, ConsentState s, {required DateTime at}) async =>
      data[k] = s;
}

void main() {
  const kind = HealthDataKind.hrvRmssd;
  final from = DateTime.utc(2026, 11, 1);
  final to = DateTime.utc(2026, 11, 2);
  late _CountingReader reader;
  late ConsentService consents;
  late ConsentedHealthReader guard;

  setUp(() {
    reader = _CountingReader();
    consents = ConsentService(
      _Consents(),
      FakeClock(DateTime.utc(2026, 11, 10)),
    );
    guard = ConsentedHealthReader(reader, consents);
  });

  test('ohne Einwilligung keine Daten und kein Aufruf des Lesers (SEC-0001, SEC-0002)', () async {
    final page = await guard.readPage(kind: kind, from: from, to: to);
    expect(page, isNull);
    expect(reader.calls, isEmpty);
  });

  test('Einwilligung einer anderen Art gibt diese Art nicht frei', () async {
    await consents.grant(healthSourceKey(HealthDataKind.sleep));
    final page = await guard.readPage(kind: kind, from: from, to: to);
    expect(page, isNull);
    expect(reader.calls, isEmpty);
  });

  test('nach Widerruf kein Aufruf des Lesers mehr', () async {
    await consents.grant(healthSourceKey(kind));
    await consents.revoke(healthSourceKey(kind));
    expect(await guard.readPage(kind: kind, from: from, to: to), isNull);
    expect(reader.calls, isEmpty);
  });

  test('mit Einwilligung reicht er Seite und Argumente durch', () async {
    await consents.grant(healthSourceKey(kind));
    final page = await guard.readPage(
      kind: kind,
      from: from,
      to: to,
      pageToken: 't1',
      pageSize: 7,
    );
    expect(reader.calls, [(kind, 't1', 7)]);
    expect(page!.records.single.id, 'r1');
    expect(page.nextToken, 'next');
  });

  test('Widerruf während der Seite: Seite verworfen (SEC-0007)', () async {
    await consents.grant(healthSourceKey(kind));
    reader.onRead = () => consents.revoke(healthSourceKey(kind));
    final page = await guard.readPage(kind: kind, from: from, to: to);
    expect(page, isNull);
    expect(reader.calls, hasLength(1));
  });
}
