// Die Karten-Frage geht nur auf, wenn die Seite oben liegt und kein Lauf läuft (M2-Abschluss C, WP31-Flake: die
// asynchron aufgehende Frage legte sich über den Beenden-Dialog der Lauf-Seite).
import 'package:adapters/adapters.dart';
import 'package:adapters/map_testing.dart';
import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/map/map_consent_controller.dart';
import 'package:running_app/features/map/map_services.dart';
import 'package:running_app/features/map/map_source_holder.dart';
import 'package:running_app/l10n/app_localizations.dart';

class _Consents implements ConsentStore {
  final Map<String, ConsentState> data = {};
  @override
  Future<ConsentState?> get(String k) async => data[k];
  @override
  Future<Map<String, ConsentState>> all() async => Map.of(data);
  @override
  Future<void> set(String k, ConsentState s, {required DateTime at}) async =>
      data[k] = s;
}

class _Cache implements MapCacheAdmin {
  @override
  Future<int> sizeBytes() async => 0;
  @override
  Future<void> delete() async {}
}

MapConsentController _controller() {
  final inner = FakeInner();
  return MapConsentController(
    store: _Consents(),
    clock: FakeClock(DateTime.utc(2026, 6, 1)),
    services: MapServices(
      gate: (c) =>
          MapGate(provider: MapProvider.openFreeMap, consent: c, inner: inner),
      cache: _Cache(),
      attribution: MapProvider.openFreeMap.attribution,
    ),
  );
}

Future<void> _wait(WidgetTester tester, [int rounds = 8]) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}

final _dialog = find.byKey(const Key('map_consent_dialog'));

void main() {
  late BuildContext context;
  late MapConsentController controller;
  var mayAsk = true;

  Future<MapSourceHolder> holder(WidgetTester tester) async {
    mayAsk = true;
    controller = _controller();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (c) {
            context = c;
            return const Scaffold(body: SizedBox());
          },
        ),
      ),
    );
    await tester.runAsync(() => controller.ready);
    final h = MapSourceHolder(askContext: () => context, mayAsk: () => mayAsk)
      ..bind(controller);
    addTearDown(h.dispose);
    return h;
  }

  testWidgets('nicht über einem offenen Dialog; danach wieder', (tester) async {
    final h = await holder(tester);
    // Ein anderer Dialog liegt schon über der Seite, wenn die Frage aufgehen wollte.
    showDialog<void>(
      context: context,
      builder: (_) => const AlertDialog(key: Key('other_dialog')),
    );
    await tester.pump();
    h.setWanted(true);
    await _wait(tester);
    expect(find.byKey(const Key('other_dialog')), findsOneWidget);
    expect(_dialog, findsNothing);
    expect(h.source, isNull);
    // Dialog weg, Karte wird wieder gebraucht: jetzt fragt sie (nicht als "Nicht jetzt" gezählt).
    Navigator.of(context).pop();
    await tester.pumpAndSettle();
    h.setWanted(false);
    h.setWanted(true);
    await _wait(tester);
    expect(_dialog, findsOneWidget);
  });

  testWidgets('nicht während des Laufs; danach außerhalb des Laufs wieder', (
    tester,
  ) async {
    final h = await holder(tester);
    mayAsk = false; // Lauf läuft
    h.setWanted(true);
    await _wait(tester);
    expect(_dialog, findsNothing);
    expect(h.source, isNull);
    // Lauf vorbei, Karte wird wieder gebraucht (z. B. Zusammenfassung).
    mayAsk = true;
    h.setWanted(false);
    h.setWanted(true);
    await _wait(tester);
    expect(_dialog, findsOneWidget);
  });
}
