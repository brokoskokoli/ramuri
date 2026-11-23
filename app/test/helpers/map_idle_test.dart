// Kartenhelfer settleUntilMapIdle: endet erst, wenn keine Kachelanfrage mehr offen ist.
import 'dart:async';

import 'package:adapters/map_testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'widget_helpers.dart';

final _style = Uri.parse('https://$host/styles/test');
final _tileJson = Uri.parse('https://$host/planet');

void main() {
  testWidgets('keine Anfrage offen: endet nach zwei ruhigen Frames', (
    tester,
  ) async {
    await tester.pumpWidget(const SizedBox());
    final net = FakeInner();
    final n = await settleUntilMapIdle(tester, net, maxFrames: 10);
    expect(n, 2);
    expect(net.requests, isEmpty);
  });

  testWidgets('Anfrage hängt: Fehler nach maxFrames, Meldung nennt das Ziel', (
    tester,
  ) async {
    await tester.pumpWidget(const SizedBox());
    final net = FakeInner()..hold = Completer<void>();
    late Future<Object?> pending;
    await tester.runAsync(() async {
      pending = net.get(_style);
    });
    expect(net.active, 1);
    await expectLater(
      settleUntilMapIdle(tester, net, maxFrames: 4),
      throwsA(
        isA<TestFailure>().having(
          (e) => e.message,
          'message',
          allOf(contains('„keine Kachelanfrage offen“'), contains('4 Frames')),
        ),
      ),
    );
    net.hold!.complete();
    await tester.runAsync(() => pending);
    expect(net.active, 0);
  });

  testWidgets('Antwort löst Folgeanfrage aus: endet erst danach', (
    tester,
  ) async {
    await tester.pumpWidget(const SizedBox());
    final net = FakeInner();
    var followUp = false;
    await tester.runAsync(() async {
      // Wie die Dekodierung des Stils: kurz nach der Antwort folgt das TileJSON.
      unawaited(
        net.get(_style).then((_) {
          Timer(const Duration(milliseconds: 30), () {
            followUp = true;
            unawaited(net.get(_tileJson));
          });
        }),
      );
    });
    await settleUntilMapIdle(tester, net);
    expect(followUp, isTrue);
    expect(net.requests.map((r) => r.url), [_style, _tileJson]);
    expect(net.active, 0);
  });

  testWidgets('Folgeanfrage erst nach einem ruhigen Frame: endet erst danach', (
    tester,
  ) async {
    await tester.pumpWidget(const SizedBox());
    final net = FakeInner();
    var followUp = false;
    // Antwort im ersten Frame; die Folgeanfrage kommt erst im zweiten Frame
    // (Test-Uhr, Frames zu je 300 ms) – nach einem Frame ohne offene Anfrage.
    unawaited(
      net.get(_style).then((_) {
        Timer(const Duration(milliseconds: 400), () {
          followUp = true;
          unawaited(net.get(_tileJson));
        });
      }),
    );
    final n = await settleUntilMapIdle(tester, net);
    expect(followUp, isTrue);
    expect(net.requests.map((r) => r.url), [_style, _tileJson]);
    expect(net.active, 0);
    expect(n, greaterThanOrEqualTo(4), reason: 'zwei ruhige Frames danach');
  });
}
