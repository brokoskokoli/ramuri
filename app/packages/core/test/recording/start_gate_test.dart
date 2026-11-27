import 'dart:async';

import 'package:core/core.dart';
import 'package:test/test.dart';

void main() {
  group('RecordingStartGate (FR-0195)', () {
    test(
      'genauer Standort und GPS an: Start erlaubt, ohne zu fragen',
      () async {
        final a = FakeLocationAccess();
        final r = await RecordingStartGate(a).check(askUser: true);
        expect(r.canStart, isTrue);
        expect(r.block, isNull);
        expect(a.requestCount, 0);
      },
    );

    test('verweigert ohne Frage: kein Start, Grund permissionDenied', () async {
      final a = FakeLocationAccess(current: LocationAccess.denied);
      final r = await RecordingStartGate(a).check();
      expect(r.canStart, isFalse);
      expect(r.block, StartBlock.permissionDenied);
      expect(a.requestCount, 0);
    });

    test('nur ungefähr: kein Start, Grund approximateOnly', () async {
      final a = FakeLocationAccess(current: LocationAccess.approximateOnly);
      final r = await RecordingStartGate(a).check();
      expect(r.block, StartBlock.approximateOnly);
    });

    test('Nutzer erteilt im Dialog genau: Start erlaubt', () async {
      final a = FakeLocationAccess(
        current: LocationAccess.denied,
        onRequest: LocationAccess.precise,
      );
      final r = await RecordingStartGate(a).check(askUser: true);
      expect(r.canStart, isTrue);
      expect(a.requestCount, 1);
    });

    test('Dialog liefert nur ungefähr: weiter kein Start', () async {
      final a = FakeLocationAccess(
        current: LocationAccess.denied,
        onRequest: LocationAccess.approximateOnly,
      );
      final r = await RecordingStartGate(a).check(askUser: true);
      expect(r.block, StartBlock.approximateOnly);
    });

    test('Dialog abgelehnt: Grund permissionDenied', () async {
      final a = FakeLocationAccess(current: LocationAccess.denied);
      final r = await RecordingStartGate(a).check(askUser: true);
      expect(r.block, StartBlock.permissionDenied);
      expect(a.requestCount, 1);
    });

    test('GPS aus: kein Start, Grund gpsOff', () async {
      final a = FakeLocationAccess(gps: false);
      expect((await RecordingStartGate(a).check()).block, StartBlock.gpsOff);
    });

    test('Stand nicht lesbar: kein Start, Grund unknown', () async {
      final a = FakeLocationAccess()..fail = true;
      expect((await RecordingStartGate(a).check()).block, StartBlock.unknown);
    });

    test('Frist PAR-249: 10 s, Standard der Prüfung', () {
      expect(startCheckTimeout, const Duration(seconds: 10));
      expect(
        RecordingStartGate(FakeLocationAccess()).timeout,
        startCheckTimeout,
      );
    });

    test('Stand antwortet nie: nach der Frist unknown, kein Start', () async {
      final a = FakeLocationAccess()..accessNeverAnswers = true;
      final r = await RecordingStartGate(
        a,
        timeout: const Duration(milliseconds: 1),
      ).check();
      expect(r.canStart, isFalse);
      expect(r.block, StartBlock.unknown);
      expect(a.requestCount, 0);
    });

    test('GPS-Schalter antwortet nie: nach der Frist unknown', () async {
      final a = FakeLocationAccess()..gpsNeverAnswers = true;
      final r = await RecordingStartGate(
        a,
        timeout: const Duration(milliseconds: 1),
      ).check();
      expect(r.canStart, isFalse);
      expect(r.block, StartBlock.unknown);
    });

    test('Dialog ohne Frist: wartet auf den Nutzer', () async {
      final answer = Completer<LocationAccess>();
      final a = _SlowDialog(answer.future);
      var done = false;
      final pending =
          RecordingStartGate(
            a,
            timeout: const Duration(milliseconds: 1),
          ).check(askUser: true).then((r) {
            done = true;
            return r;
          });
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(done, isFalse, reason: 'Dialog offen: kein Ergebnis');
      answer.complete(LocationAccess.precise);
      expect((await pending).canStart, isTrue);
    });

    test('nach Erteilung startet er (gleiche Prüfung, neuer Stand)', () async {
      final a = FakeLocationAccess(current: LocationAccess.denied);
      final g = RecordingStartGate(a);
      expect((await g.check()).canStart, isFalse);
      a.current = LocationAccess.precise;
      expect((await g.check()).canStart, isTrue);
    });
  });
}

/// Dialog, dessen Antwort der Test freigibt.
class _SlowDialog extends FakeLocationAccess {
  _SlowDialog(this.answer) : super(current: LocationAccess.denied);
  final Future<LocationAccess> answer;

  @override
  Future<LocationAccess> request() {
    requestCount++;
    return answer;
  }
}
