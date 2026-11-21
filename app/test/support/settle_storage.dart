import 'package:flutter_test/flutter_test.dart';

/// Warten in Widget-Tests auf Speicherereignisse statt auf feste Echtzeit.
///
/// Der Speicher der Widget-Tests ist der Fake im Arbeitsspeicher
/// (`FakeStorage`): Seine Operationen enden über Mikrotasks und Timer der
/// Test-Uhr, nicht über echte Zeit. Feste Echtzeit-Pausen
/// in `runAsync` machen die Tests nur langsamer und
/// unter Last wackelig. Die Helfer hier pumpen stattdessen Frames der Test-Uhr
/// und geben je Frame der echten Ereignisschleife einige Durchläufe (für
/// Arbeit, die außerhalb der Test-Uhr begonnen hat, etwa eine in `runAsync`
/// geöffnete Sitzung) – ohne Wartezeit.
///
/// Das Werkzeug `tool/check_test_waits.py` zählt die festen Wartezeiten in
/// `app/test/`; ihre Zahl darf nur sinken.

/// Wartet auf das nächste Speicherereignis bzw. das Ende offener
/// Speicheroperationen und gibt die Zahl der gepumpten Frames zurück.
///
/// - Mit [until]: endet, sobald die Bedingung gilt (das Ereignis, auf das der
///   Test wartet, etwa „Wert gespeichert“ oder „Karte neu geladen“). Sie wird
///   nach jedem Frame geprüft, auch vor dem ersten.
/// - Ohne [until]: endet, sobald kein Frame mehr geplant ist (alle
///   Operationen durch, die Oberfläche ist ruhig) – frühestens nach einem
///   Frame.
///
/// Jeder Frame rückt die Test-Uhr um [frame] vor; [onFrame] sieht jeden Frame
/// (etwa um zu zählen, in wie vielen eine Karte fehlte). Nach [maxFrames]
/// Frames schlägt der Test fehl; die Meldung nennt [what].
Future<int> settleStorage(
  WidgetTester tester, {
  bool Function()? until,
  void Function()? onFrame,
  String what = 'Speicher ruhig',
  Duration frame = const Duration(milliseconds: 16),
  int maxFrames = 200,
}) async {
  if (until != null && until()) return 0;
  for (var n = 1; n <= maxFrames; n++) {
    await _realTurn(tester);
    await tester.pump(frame);
    onFrame?.call();
    if (until != null) {
      if (until()) return n;
    } else if (!tester.binding.hasScheduledFrame) {
      return n;
    }
  }
  throw TestFailure(
    'settleStorage: „$what“ nach $maxFrames Frames zu je '
    '${frame.inMilliseconds} ms Testzeit nicht erreicht'
    '${until == null ? ' (es sind weiter Frames geplant)' : ''}',
  );
}

/// Beobachtet genau [frames] Frames der Test-Uhr zu je [frame] (für Prüfungen
/// „in keinem Frame“), ohne Echtzeit-Pausen. [onFrame] sieht jeden Frame.
Future<void> observeFrames(
  WidgetTester tester,
  int frames, {
  Duration frame = const Duration(milliseconds: 16),
  void Function(int i)? onFrame,
}) async {
  for (var i = 0; i < frames; i++) {
    await _realTurn(tester);
    await tester.pump(frame);
    onFrame?.call(i);
  }
}

/// Durchläufe der echten Ereignisschleife je Frame. Fakes, die außerhalb der
/// Test-Uhr begonnen haben (etwa ein HTTP-Fake mit Byte-Strom), brauchen
/// mehr als einen Durchlauf; die Zahl hängt nur vom Code ab, nicht von der
/// Last, und kostet keine Wartezeit.
const _realTurns = 3;

/// [_realTurns] Durchläufe der echten Ereignisschleife, ohne Wartezeit.
Future<void> _realTurn(WidgetTester tester) => tester.runAsync(() async {
  for (var i = 0; i < _realTurns; i++) {
    await Future<void>(() {});
  }
});
