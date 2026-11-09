import 'package:core/core.dart';
import 'package:test/test.dart';

import 'recalc_support.dart';

/// Bestätigen und Ablehnen wirken auf den Faktor, den das Angebot zeigt
/// (WP19 NB2b, Review 2 Befund 5): wurde er inzwischen zurückgenommen oder
/// ersetzt, ändert sich nichts und die Oberfläche liest das Angebot neu.
void main() {
  late RecalcWorld w;
  late RecalculationService s;

  LoadFactorRecord factor(double v) => LoadFactorRecord(
    profile: LoadProfile.edwards,
    value: v,
    runs: 12,
    day: DateTime.utc(2030, 3, 1),
  );

  setUp(() async {
    w = await RecalcWorld.create();
    s = w.recalc();
  });

  Future<LoadFactorRecord?> stored() => LoadSettings.factor(w.session.settings);
  Future<LoadFactorRecord?> pending() =>
      LoadSettings.pendingFactor(w.session.settings);
  Future<LoadFactorRecord?> declined() =>
      LoadSettings.declinedFactor(w.session.settings);

  test('zurückgenommenes Angebot: confirm und decline ändern nichts', () async {
    final shown = await s.requestPersonalFactor(factor(2.5));
    await s.withdrawPersonalFactor();
    await expectLater(
      s.confirm(shown),
      throwsA(isA<RecalculationOfferChangedException>()),
    );
    await expectLater(
      s.decline(shown),
      throwsA(isA<RecalculationOfferChangedException>()),
    );
    expect(await stored(), isNull);
    expect(await declined(), isNull);
    expect(await s.pendingOffer(), isNull);
  });

  test('ersetztes Angebot: confirm übernimmt den neuen Wert nicht', () async {
    final shown = await s.requestPersonalFactor(factor(2.5));
    // So ersetzt load() den offenen Faktor (TrainingLoadService._syncFactor).
    await LoadSettings.writePendingFactor(
      w.session.settings,
      factor(3.0),
      at: w.clock.now(),
    );
    await expectLater(
      s.confirm(shown),
      throwsA(isA<RecalculationOfferChangedException>()),
    );
    expect(await stored(), isNull);
    expect(await pending(), factor(3.0));
    // Mit dem neuen Angebot geht es.
    final now = await s.pendingOffer();
    expect(now!.personalFactor, factor(3.0));
    await s.confirm(now);
    expect(await stored(), factor(3.0));
  });

  test(
    'ersetztes Angebot: decline merkt den neuen Wert nicht als abgelehnt',
    () async {
      final shown = await s.requestPersonalFactor(factor(2.5));
      await LoadSettings.writePendingFactor(
        w.session.settings,
        factor(3.0),
        at: w.clock.now(),
      );
      await expectLater(
        s.decline(shown),
        throwsA(isA<RecalculationOfferChangedException>()),
      );
      expect(await declined(), isNull);
      expect(await pending(), factor(3.0));
    },
  );

  test(
    'unverändertes Angebot: confirm und decline wirken wie bisher',
    () async {
      final shown = await s.requestPersonalFactor(factor(2.5));
      await s.decline(shown);
      expect(await declined(), factor(2.5));
      final again = await s.requestPersonalFactor(factor(2.6));
      await s.confirm(again);
      expect(await stored(), factor(2.6));
    },
  );
}
