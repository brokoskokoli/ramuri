import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:test/test.dart';

class _BrokenStore implements ConsentStore {
  _BrokenStore({this.failRead = true, this.failWrite = false});
  final bool failRead;
  final bool failWrite;
  final data = <String, ConsentState>{};

  @override
  Future<ConsentState?> get(String k) async {
    if (failRead) throw const StorageException(StorageFailure.failed);
    return data[k];
  }

  @override
  Future<Map<String, ConsentState>> all() async => data;

  @override
  Future<void> set(String k, ConsentState s, {required DateTime at}) async {
    if (failWrite) throw const StorageException(StorageFailure.failed);
    data[k] = s;
  }
}

void main() {
  final clock = FakeClock(DateTime.utc(2026, 11, 1));
  late FakeStorage storage;
  late StorageSession session;
  late ConsentService consents;
  late FakeConsentedSource<int> a;
  late FakeConsentedSource<int> b;

  Future<void> setUpWorld() async {
    storage = FakeStorage();
    session = await storage.open(Uint8List.fromList(List.filled(32, 1)));
    consents = ConsentService(session.consents, clock);
    a = FakeConsentedSource<int>('source_a', [1, 2]);
    b = FakeConsentedSource<int>('source_b', [3]);
  }

  setUp(setUpWorld);

  test(
    'SEC-0001: ohne Einwilligung keine Daten und kein Zugriff auf die Quelle',
    () async {
      final r = await ConsentGuard(consents, a).read();
      expect(r, isA<ConsentDenied<int>>());
      expect(a.fetchCount, 0);
    },
  );

  test('mit Einwilligung kommen die Daten', () async {
    await consents.grant('source_a');
    final r = await ConsentGuard(consents, a).read();
    expect((r as ConsentedData<int>).items, [1, 2]);
  });

  test('SEC-0002: Freigabe von A gibt B nicht frei', () async {
    await consents.grant('source_a');
    expect(await ConsentGuard(consents, b).read(), isA<ConsentDenied<int>>());
    expect(b.fetchCount, 0);
    expect(await consents.isGranted('source_a'), isTrue);
    expect(await consents.isGranted('source_b'), isFalse);
  });

  test(
    'SEC-0007: Widerruf sperrt nur diese Quelle und fragt nach Löschen',
    () async {
      await consents.grant('source_a');
      await consents.grant('source_b');
      final out = await consents.revoke('source_a');
      expect(out.askDeleteImportedData, isTrue);
      expect(await ConsentGuard(consents, a).read(), isA<ConsentDenied<int>>());
      expect(a.fetchCount, 0);
      expect(await ConsentGuard(consents, b).read(), isA<ConsentedData<int>>());
    },
  );

  test(
    'Widerruf ohne vorherige Einwilligung fragt nicht nach Löschen',
    () async {
      expect(
        (await consents.revoke('source_a')).askDeleteImportedData,
        isFalse,
      );
      await consents.grant('source_a');
      await consents.revoke('source_a');
      expect(
        (await consents.revoke('source_a')).askDeleteImportedData,
        isFalse,
      );
    },
  );

  test('erneute Einwilligung nach Widerruf gibt wieder frei', () async {
    await consents.grant('source_a');
    await consents.revoke('source_a');
    await consents.grant('source_a');
    expect(await consents.isGranted('source_a'), isTrue);
  });

  test('Widerruf während des Abrufs verwirft die Daten', () async {
    await consents.grant('source_a');
    a.onFetch = () => consents.revoke('source_a');
    expect(await ConsentGuard(consents, a).read(), isA<ConsentDenied<int>>());
  });

  test('Zustand bleibt über neue Dienste und Sitzungen erhalten', () async {
    await consents.grant('source_a');
    await session.close();
    final s2 = await storage.open(Uint8List.fromList(List.filled(32, 1)));
    final again = ConsentService(s2.consents, clock);
    expect(await again.isGranted('source_a'), isTrue);
    expect(await again.isGranted('source_b'), isFalse);
    await again.revoke('source_a');
    expect(
      await ConsentService(s2.consents, clock).isGranted('source_a'),
      isFalse,
    );
  });

  test('fail-closed: Lesefehler des Speichers verweigert', () async {
    final store = _BrokenStore();
    store.data['source_a'] = ConsentState.granted;
    final broken = ConsentService(store, clock);
    expect(await broken.isGranted('source_a'), isFalse);
    expect(await ConsentGuard(broken, a).read(), isA<ConsentDenied<int>>());
    expect(a.fetchCount, 0);
  });

  test('fail-closed: unbekannte Quelle ist nicht freigegeben', () async {
    expect(await consents.isGranted('unbekannt'), isFalse);
  });

  test(
    'Schreibfehler beim Erteilen: bleibt verweigert, Fehler geht weiter',
    () async {
      final svc = ConsentService(
        _BrokenStore(failRead: false, failWrite: true),
        clock,
      );
      await expectLater(
        svc.grant('source_a'),
        throwsA(isA<StorageException>()),
      );
      expect(await svc.isGranted('source_a'), isFalse);
    },
  );

  test('Schreibfehler beim Widerruf: Sperre gilt trotzdem', () async {
    final store = _BrokenStore(failRead: false, failWrite: true)
      ..data['source_a'] = ConsentState.granted;
    final svc = ConsentService(store, clock);
    expect(await svc.isGranted('source_a'), isTrue);
    await expectLater(svc.revoke('source_a'), throwsA(isA<StorageException>()));
    expect(await svc.isGranted('source_a'), isFalse);
  });

  test('CON-0007: ohne jede Freigabe bleibt das Profil nutzbar', () async {
    expect(await consents.isGranted('source_a'), isFalse);
    final profile = ProfileService(session.profile, clock);
    final r = await profile.save(const ProfileRecord(birthYear: 1990));
    expect(r.saved, isTrue);
    expect((await profile.load()).birthYear, 1990);
    expect((await profile.resolve()).basis, isNotNull);
  });
}
