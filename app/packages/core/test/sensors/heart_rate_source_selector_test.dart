import 'package:core/core.dart';
import 'package:test/test.dart';

final t0 = DateTime.utc(2026, 11, 6, 8);
DateTime at(int s) => t0.add(Duration(seconds: s));

/// Speist [sel] wie ein Host: Ereignisse mit Zeit, nur durchgelassene Werte
/// landen in `out`.
class Feed {
  Feed(this.sel);
  final HeartRateSourceSelector sel;
  final out = <HeartRateReading>[];

  void connect(String id, int s) => sel.handle(HeartRateConnected(id), at(s));
  void drop(String id, int s, {bool lost = true}) =>
      sel.handle(HeartRateDisconnected(id, lost: lost), at(s));
  void reading(String id, int s, int bpm) {
    final r = sel.handle(HeartRateReading(id, at(s), bpm), at(s));
    if (r != null) out.add(r);
  }
}

void main() {
  late HeartRateSourceSelector sel;
  late Feed f;
  setUp(() {
    sel = HeartRateSourceSelector(preferredId: 'pref');
    f = Feed(sel);
  });

  test('FR-0019: zwei aktive Quellen, nur eine speist, keine Vermischung', () {
    f.connect('other', 0);
    sel.lock(at(1)); // Lauf läuft
    f.connect('pref', 1); // bevorzugt, aber 'other' ist schon Quelle
    for (var s = 2; s < 6; s++) {
      f.reading('other', s, 100 + s);
      f.reading('pref', s, 150 + s);
    }
    expect(f.out.map((r) => r.deviceId).toSet(), {'other'});
    expect(f.out.map((r) => r.beatsPerMinute), [102, 103, 104, 105]);
  });

  test(
    'Vorrang beim Abbruch: das bevorzugte folgt, nicht das länger verbundene',
    () {
      // Ersatz nach Abbruch: Vorrang entscheidet, nicht die Reihenfolge.
      f.connect('a', 0);
      sel.lock(at(0));
      f.connect('other', 1);
      f.connect('pref', 2);
      expect(sel.activeId, 'a');
      f.drop('a', 3);
      expect(sel.activeId, 'pref'); // nicht 'other', obwohl länger verbunden
      expect(sel.switches.single.reason, SourceSwitchReason.lost);
    },
  );

  test('Vorrang vor dem Start: bevorzugtes übernimmt, sobald verbunden', () {
    f.connect('other', 0);
    f.reading('other', 1, 100);
    f.connect('pref', 2);
    expect(sel.activeId, 'pref');
    expect(sel.switches.single.reason, SourceSwitchReason.preferred);
    expect(sel.switches.single.at, at(2));
    f.reading('other', 3, 101);
    f.reading('pref', 3, 150);
    expect(f.out.map((r) => r.deviceId), ['other', 'pref']);
    expect(sel.sourceAt(at(1)), 'other');
    expect(sel.sourceAt(at(2)), 'pref');
  });

  test('Vorrang vor dem Start: nicht nach manueller Wahl', () {
    f.connect('other', 0);
    f.connect('x', 1);
    sel.select('x', at(2));
    f.connect('pref', 3);
    expect(sel.activeId, 'x');
  });

  test('Ab lock kein Rückwechsel zum später verbundenen bevorzugten', () {
    f.connect('other', 0);
    sel.lock(at(1));
    f.connect('pref', 2);
    expect(sel.activeId, 'other');
    expect(sel.switches, isEmpty);
  });

  test(
    'Trennen eines Zweitgeräts ändert Quelle, Abschnitte und Wechsel nicht',
    () {
      f.connect('pref', 0);
      f.connect('other', 1);
      f.reading('pref', 2, 120);
      f.drop('other', 3);
      f.reading('pref', 4, 121);
      expect(sel.activeId, 'pref');
      expect(sel.segments, hasLength(1));
      expect(sel.segments.single.end, isNull);
      expect(sel.switches, isEmpty);
      expect(sel.connectedIds, {'pref'});
      expect(f.out.map((r) => r.beatsPerMinute), [120, 121]);
    },
  );

  test('close friert ein: keine Werte, keine Abschnitte, keine Wechsel', () {
    f.connect('a', 0);
    f.connect('b', 1);
    sel.lock(at(1));
    f.reading('a', 2, 100);
    sel.close(at(5));
    f.reading('a', 6, 101);
    f.drop('a', 7); // würde sonst auf 'b' wechseln
    f.connect('c', 8);
    f.drop('b', 9);
    expect(sel.select('c', at(10)), isFalse);
    expect(sel.activeId, isNull);
    expect(sel.segments, hasLength(1));
    expect(sel.segments.single.end, at(5));
    expect(sel.switches, isEmpty);
    expect(f.out.map((r) => r.beatsPerMinute), [100]);
  });

  test(
    'bewusstes Trennen der aktiven Quelle: Grund disconnected, nicht lost',
    () {
      f.connect('a', 0);
      f.connect('b', 1);
      sel.lock(at(1));
      f.drop('a', 2, lost: false);
      expect(sel.activeId, 'b');
      expect(sel.switches.single.reason, SourceSwitchReason.disconnected);
      f.drop('b', 3); // Abbruch bleibt lost
      f.connect('c', 4);
      expect(sel.switches.last.reason, SourceSwitchReason.lost);
    },
  );

  test('ohne bevorzugtes Gerät: am längsten verbundenes', () {
    sel = HeartRateSourceSelector();
    f = Feed(sel);
    f.connect('a', 0);
    f.connect('b', 1);
    f.connect('c', 2);
    f.drop('a', 3);
    expect(sel.activeId, 'b');
  });

  test('FR-0018: kein Rückwechsel, wenn das bevorzugte Gerät zurückkommt', () {
    f.connect('pref', 0);
    sel.lock(at(0));
    f.connect('other', 1);
    f.reading('pref', 2, 120);
    f.drop('pref', 3); // Abbruch -> Wechsel auf 'other'
    expect(sel.activeId, 'other');
    f.reading('other', 4, 130);
    f.connect('pref', 5); // wieder erreichbar
    f.reading('pref', 6, 999);
    f.reading('other', 7, 131);
    expect(sel.activeId, 'other');
    expect(f.out.map((r) => '${r.deviceId}:${r.beatsPerMinute}'), [
      'pref:120',
      'other:130',
      'other:131',
    ]);
    expect(sel.switches, hasLength(1));
    expect(sel.switches.single.from, 'pref');
    expect(sel.switches.single.to, 'other');
    expect(sel.switches.single.at, at(3));
  });

  test('Wechsel nur manuell: select wechselt, Abschnitte lückenlos', () {
    f.connect('pref', 0);
    f.connect('other', 1);
    expect(sel.select('other', at(10)), isTrue);
    expect(sel.activeId, 'other');
    expect(sel.switches.single.reason, SourceSwitchReason.manual);
    expect(sel.select('ghost', at(11)), isFalse);
    expect(sel.activeId, 'other');
    expect(sel.sourceAt(at(5)), 'pref');
    expect(sel.sourceAt(at(10)), 'other');
    expect(sel.sourceAt(at(50)), 'other');
    f.reading('pref', 12, 140);
    expect(f.out, isEmpty);
  });

  test('bevorzugtes Gerät ändern wechselt die Quelle nicht', () {
    f.connect('pref', 0);
    f.connect('other', 1);
    sel.preferredId = 'other';
    expect(sel.activeId, 'pref');
    expect(sel.switches, isEmpty);
  });

  test('setPreferred vor dem Laufstart: verbundenes bevorzugtes übernimmt', () {
    f.connect('a', 0);
    f.connect('b', 1);
    sel.setPreferred('b', at(2));
    expect(sel.activeId, 'b');
    expect(sel.switches.single.reason, SourceSwitchReason.preferred);
    sel.setPreferred('zz', at(3)); // nicht verbunden: keine Änderung
    expect(sel.activeId, 'b');
    sel.setPreferred(null, at(4));
    expect(sel.activeId, 'b');
  });

  test('setPreferred nach lock: Quelle bleibt', () {
    f.connect('a', 0);
    f.connect('b', 1);
    sel.lock(at(2));
    sel.setPreferred('b', at(3));
    expect(sel.activeId, 'a');
    expect(sel.switches, isEmpty);
  });

  test('setPreferred nach close: kein neuer Abschnitt, activeId null', () {
    f.connect('a', 0);
    f.connect('b', 1);
    sel.close(at(2));
    final n = sel.segments.length;
    sel.setPreferred('b', at(3));
    expect(sel.segments.length, n);
    expect(sel.activeId, isNull);
    expect(sel.switches, isEmpty);
  });

  test('setPreferred auf die aktive Quelle teilt den Abschnitt nicht', () {
    f.connect('a', 0);
    f.connect('b', 1);
    expect(sel.activeId, 'a');
    final n = sel.segments.length;
    sel.setPreferred('a', at(2));
    expect(sel.segments.length, n);
    expect(sel.activeId, 'a');
    expect(sel.switches, isEmpty);
  });

  test('OQ-0064: dasselbe Gerät nach Abbruch ist kein Quellwechsel', () {
    f.connect('pref', 0);
    f.reading('pref', 1, 120);
    f.drop('pref', 2);
    expect(sel.activeId, isNull);
    f.reading('pref', 3, 121); // Nachzügler nach Abbruch
    f.connect('pref', 5);
    f.reading('pref', 6, 122);
    expect(sel.activeId, 'pref');
    expect(sel.switches, isEmpty);
    expect(f.out.map((r) => r.beatsPerMinute), [120, 122]);
  });

  test('anderes Gerät nach Abbruch ohne Ersatz ist ein Quellwechsel', () {
    f.connect('a', 0);
    f.drop('a', 2);
    f.connect('b', 5);
    expect(sel.switches.single.from, 'a');
    expect(sel.switches.single.to, 'b');
    expect(sel.switches.single.reason, SourceSwitchReason.lost);
  });

  test('Herkunft je Zeitabschnitt; Zeit ohne Quelle bleibt null', () {
    f.connect('a', 0);
    f.drop('a', 10);
    f.connect('b', 20);
    f.sel.close(at(30));
    expect(sel.sourceAt(at(-1)), isNull);
    expect(sel.sourceAt(at(0)), 'a');
    expect(sel.sourceAt(at(9)), 'a');
    expect(sel.sourceAt(at(10)), isNull);
    expect(sel.sourceAt(at(19)), isNull);
    expect(sel.sourceAt(at(20)), 'b');
    expect(sel.sourceAt(at(30)), isNull);
    expect(sel.segments.map((s) => s.deviceId), ['a', 'b']);
  });

  test('FR-0012: nach dem Trennen keine Werte mehr', () {
    f.connect('a', 0);
    f.reading('a', 1, 100);
    f.drop('a', 2, lost: false);
    f.reading('a', 3, 101);
    expect(f.out, hasLength(1));
    expect(sel.activeId, isNull);
  });

  test('Wert ohne vorheriges Connected wird nicht durchgelassen', () {
    f.reading('a', 1, 100);
    expect(f.out, isEmpty);
  });

  test('doppeltes Connected ändert nichts', () {
    f.connect('a', 0);
    f.connect('a', 1);
    expect(sel.segments, hasLength(1));
    expect(sel.connectedIds, {'a'});
  });

  test('FR-0016: Batterie nur wenn gemeldet, je Gerät, weg nach Trennen', () {
    f.connect('a', 0);
    expect(sel.batteryOf('a'), isNull);
    sel.handle(const HeartRateBattery('a', 80), at(1));
    sel.handle(const HeartRateBattery('zzz', 50), at(1)); // nicht verbunden
    expect(sel.batteryOf('a'), 80);
    expect(sel.batteryOf('zzz'), isNull);
    f.drop('a', 2);
    expect(sel.batteryOf('a'), isNull);
  });

  test(
    'mit dem Fake-Sensor: Abbruch der Quelle, Rückkehr ohne Rückwechsel',
    () async {
      final fake = FakeHeartRateSensor();
      final out = <HeartRateReading>[];
      var now = 0;
      void pump(HeartRateEvent e) {
        final r = sel.handle(e, at(now));
        if (r != null) out.add(r);
      }

      sel.lock(at(0));
      final subs = [
        fake.connect('pref').listen(pump),
        fake.connect('other').listen(pump),
      ];
      await Future<void>.delayed(Duration.zero);
      fake.emitReading('pref', at(1), 120);
      fake.emitReading('other', at(1), 90);
      now = 2;
      await fake.drop('pref');
      await Future<void>.delayed(Duration.zero);
      fake.emitReading('other', at(3), 91);
      now = 4;
      subs.add(fake.connect('pref').listen(pump));
      await Future<void>.delayed(Duration.zero);
      fake.emitReading('pref', at(5), 121);
      fake.emitReading('other', at(5), 92);
      await Future<void>.delayed(Duration.zero);
      expect(out.map((r) => '${r.deviceId}:${r.beatsPerMinute}'), [
        'pref:120',
        'other:91',
        'other:92',
      ]);
      for (final s in subs) {
        await s.cancel();
      }
    },
  );
}
