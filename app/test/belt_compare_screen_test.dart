import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/export/file_handoff_scope.dart';
import 'package:running_app/features/settings/belt_compare_screen.dart';
import 'package:running_app/features/settings/developer_settings_screen.dart';
import 'package:running_app/l10n/app_localizations.dart';
import 'package:running_app/ui/ui.dart';

// Synthetische Gurt-Folge in 1/1024 s (keine echten Messwerte).
const _raw = [
  1000, 1040, 980, 1100, 1020, 960, 1080, 1000, 1120, 940, //
  1060, 1010, 990, 1130, 970, 1050, 1090, 950, 1030, 1070,
];
const _noise = [5.0, -5, 0, 5, -5, 0, 5, -5, 0, 5, -5, 0];

double _ms(int v) => v * 1000 / 1024;

/// Kamera = Gurt ab Position 4 plus ±5 ms; [nanAt] macht einen ungültig.
List<double> _camera({int? nanAt}) => [
  for (var i = 0; i < 12; i++)
    i == nanAt ? double.nan : _ms(_raw[4 + i]) + _noise[i],
];

List<RrPacket> _packets(DateTime at, [List<int> raw = _raw]) => [
  for (var i = 0; i < raw.length; i += 4)
    RrPacket(
      time: at.add(Duration(seconds: i)),
      source: 'gurt-1',
      intervals: raw.sublist(i, i + 4),
    ),
];

MorningMeasurement _m(
  DateTime at, {
  Duration offset = Duration.zero,
  PpgQuality quality = PpgQuality.good,
  double? rmssd = 120,
  List<double>? ibis,
  RestingPosture posture = RestingPosture.lying,
}) => MorningMeasurement(
  measuredAt: at,
  utcOffset: offset,
  posture: posture,
  deviceManufacturer: 'Testhersteller',
  deviceModel: 'Modell',
  method: ppgMethod,
  methodVersion: ppgMethodVersion,
  quality: quality,
  restingHrBpm: quality == PpgQuality.unusable ? null : 61,
  rmssdMs: rmssd,
  timingNoiseMs: 12.5,
  cameraIntervalsMs: ibis ?? _camera(),
  beforeValidation: true,
  outsideWindow: false,
  windowStartS: 20,
  windowEndS: 80,
);

Future<MorningStore> _store() async {
  final session = await FakeStorage().open(Uint8List(32));
  return (session as MorningStorage).morning;
}

Future<void> _pump(
  WidgetTester tester,
  MorningStore store, {
  String locale = 'de',
  bool on = true,
}) async {
  final session = await FakeStorage().open(Uint8List(32));
  final mode = SettingsDeveloperModeStore(
    session.settings,
    FakeClock(DateTime.utc(2030, 1, 10)),
  );
  await mode.set(on);
  tester.view.physicalSize = const Size(800, 3200);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: Locale(locale),
      theme: RamuriTheme.light,
      home: FileHandoffScope(
        handoff: FakeFileHandoff(),
        child: DeveloperSettingsScreen(
          developerMode: mode,
          morning: store,
          clock: () => DateTime.utc(2030, 1, 10),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _rowKeys() => find.byWidgetPredicate(
  (w) =>
      w.key is ValueKey<String> &&
      (w.key! as ValueKey<String>).value.startsWith('dev_compare_row_'),
);

String _rowText(WidgetTester tester, int id) => tester
    .widgetList<Text>(
      find.descendant(
        of: find.byKey(Key('dev_compare_row_$id')),
        matching: find.byType(Text),
      ),
    )
    .map((t) => t.data)
    .join('\n');

void main() {
  for (final lang in ['de', 'en']) {
    testWidgets('Liste: neueste zuerst, nur Messungen mit Gurt-RR, $lang', (
      tester,
    ) async {
      final s = await _store();
      final a = await s.add(
        _m(DateTime.utc(2030, 1, 1, 6)),
        beltPackets: _packets(DateTime.utc(2030, 1, 1, 6)),
      );
      await s.add(_m(DateTime.utc(2030, 1, 2, 6))); // ohne Gurt
      final c = await s.add(
        _m(DateTime.utc(2030, 1, 3, 6), posture: RestingPosture.sitting),
        beltPackets: _packets(DateTime.utc(2030, 1, 3, 6)),
      );
      await _pump(tester, s, locale: lang);
      expect(find.byKey(const Key('dev_compare')), findsOneWidget);
      expect(_rowKeys(), findsNWidgets(2));
      final ya = tester.getTopLeft(find.byKey(Key('dev_compare_row_$a'))).dy;
      final yc = tester.getTopLeft(find.byKey(Key('dev_compare_row_$c'))).dy;
      expect(yc, lessThan(ya));
      final text = _rowText(tester, a);
      if (lang == 'de') {
        expect(find.text('Kamera gegen Gurt'), findsOneWidget);
        expect(text, contains('1.1.2030 06:00 · liegend · gut'));
        expect(text, contains('RMSSD Kamera / Gurt: 120,0 / 110,2 ms'));
        expect(text, contains('Differenz +9,8 ms (+8,9 %)'));
        expect(_rowText(tester, c), contains('sitzend'));
      } else {
        expect(find.text('Camera vs. strap'), findsOneWidget);
        expect(text, contains('1/1/2030 06:00 · lying · good'));
        expect(text, contains('RMSSD camera / strap: 120.0 / 110.2 ms'));
        expect(text, contains('Difference +9.8 ms (+8.9 %)'));
      }
      expect(find.byKey(const Key('dev_compare_empty')), findsNothing);
    });

    testWidgets('Liste: ohne Kamera-RMSSD „–“, keine Zuordnung, $lang', (
      tester,
    ) async {
      final s = await _store();
      final a = await s.add(
        _m(
          DateTime.utc(2030, 1, 1, 6),
          quality: PpgQuality.limited,
          rmssd: null,
        ),
        beltPackets: _packets(DateTime.utc(2030, 1, 1, 6)),
      );
      // Gurt mit nur 8 Werten: zu wenige Paare.
      final b = await s.add(
        _m(DateTime.utc(2030, 1, 2, 6)),
        beltPackets: _packets(DateTime.utc(2030, 1, 2, 6), _raw.sublist(0, 8)),
      );
      await _pump(tester, s, locale: lang);
      final ta = _rowText(tester, a);
      final tb = _rowText(tester, b);
      if (lang == 'de') {
        expect(ta, contains('eingeschränkt'));
        expect(ta, contains('RMSSD Kamera / Gurt: – / 110,2 ms'));
        expect(ta, contains('Differenz – ms (– %)'));
        expect(tb, contains('keine Zuordnung'));
        expect(tb, isNot(contains('RMSSD')));
      } else {
        expect(ta, contains('RMSSD camera / strap: – / 110.2 ms'));
        expect(tb, contains('no match'));
      }
    });

    testWidgets('Liste: Hinweis, wenn keine Messung Gurt-RR hat, $lang', (
      tester,
    ) async {
      final s = await _store();
      await s.add(_m(DateTime.utc(2030, 1, 1, 6)));
      await _pump(tester, s, locale: lang);
      expect(_rowKeys(), findsNothing);
      expect(find.byKey(const Key('dev_compare_empty')), findsOneWidget);
      expect(
        find.text(
          lang == 'de'
              ? 'Für den Vergleich beim Messen einen Brustgurt verbinden.'
              : 'Connect a chest strap while measuring to compare.',
        ),
        findsOneWidget,
      );
    });
  }

  testWidgets('Liste: Ortszeit um Mitternacht (UTC und Ort an anderem Tag)', (
    tester,
  ) async {
    final s = await _store();
    // 23:30 UTC am 1. Januar, Ort UTC+1: 00:30 am 2. Januar.
    final a = await s.add(
      _m(DateTime.utc(2030, 1, 1, 23, 30), offset: const Duration(hours: 1)),
      beltPackets: _packets(DateTime.utc(2030, 1, 1, 23, 30)),
    );
    // 00:15 UTC am 3. Januar, Ort UTC−1: 23:15 am 2. Januar.
    final b = await s.add(
      _m(DateTime.utc(2030, 1, 3, 0, 15), offset: const Duration(hours: -1)),
      beltPackets: _packets(DateTime.utc(2030, 1, 3, 0, 15)),
    );
    await _pump(tester, s);
    expect(_rowText(tester, a), contains('2.1.2030 00:30'));
    expect(_rowText(tester, b), contains('2.1.2030 23:15'));
    // Reihenfolge nach Zeitpunkt, nicht nach Ortszeit.
    final ya = tester.getTopLeft(find.byKey(Key('dev_compare_row_$a'))).dy;
    final yb = tester.getTopLeft(find.byKey(Key('dev_compare_row_$b'))).dy;
    expect(yb, lessThan(ya));
  });

  testWidgets('Ohne Entwicklermodus kein Abschnitt „Kamera gegen Gurt“', (
    tester,
  ) async {
    final s = await _store();
    await s.add(
      _m(DateTime.utc(2030, 1, 1, 6)),
      beltPackets: _packets(DateTime.utc(2030, 1, 1, 6)),
    );
    await _pump(tester, s, on: false);
    expect(find.byKey(const Key('dev_compare')), findsNothing);
    expect(_rowKeys(), findsNothing);
  });

  for (final lang in ['de', 'en']) {
    testWidgets(
      'Detail: alle Kennwerte, Kamera aus dem Rohsignal, Kurve, $lang',
      (tester) async {
        final s = await _store();
        final a = await s.add(
          _m(DateTime.utc(2030, 1, 1, 6), ibis: _camera(nanAt: 3)),
          beltPackets: _packets(DateTime.utc(2030, 1, 1, 6)),
          rawSignal: const MorningRawSignal(
            frames: [],
            frameGapCount: 0,
            frameGapTotalS: 0,
            cameraId: '0',
            physicalCameraId: '2',
          ),
        );
        await _pump(tester, s, locale: lang);
        await tester.tap(find.byKey(Key('dev_compare_row_$a')));
        await tester.pumpAndSettle();
        String v(String k) => tester
            .widgetList<Text>(
              find.descendant(
                of: find.byKey(Key('dev_compare_detail_$k')),
                matching: find.byType(Text),
              ),
            )
            .map((t) => t.data)
            .join(' | ');
        if (lang == 'de') {
          expect(v('rmssd_camera'), 'RMSSD Kamera | 120,0 ms');
          expect(v('rmssd_belt'), 'RMSSD Gurt | 110,2 ms');
          expect(v('rmssd_diff'), 'Differenz RMSSD | +9,8 ms (+8,9 %)');
          expect(v('hr_camera'), 'Ruhepuls Kamera | 61,0 /min');
          expect(v('hr_belt'), 'Ruhepuls Gurt | 59,8 /min');
          expect(v('hr_diff'), 'Differenz Ruhepuls | +1,2 /min (+2,0 %)');
          expect(
            v('paired'),
            'RMSSD auf denselben Paaren | Kamera 116,4 / Gurt 112,4 ms · '
            '9 Differenzen',
          );
          expect(v('error'), startsWith('Fehler je Schlagabstand | '));
          expect(v('noise'), 'Zeitrauschen | 12,5 ms');
          expect(v('valid'), 'Gültige Kamera-Abstände | 11/12');
          expect(v('window'), 'Fenster | 20,0 bis 80,0 s');
          expect(v('camera'), 'Kamera | Kamera 0/2');
        } else {
          expect(v('rmssd_belt'), 'RMSSD strap | 110.2 ms');
          expect(v('hr_belt'), 'Resting HR strap | 59.8 bpm');
          expect(v('valid'), 'Valid camera intervals | 11/12');
          expect(v('camera'), 'Camera | Camera 0/2');
        }
        // Kurve: Gurt als Linie (11 Stücke), Kamera als Punkte (11 gültige).
        final chart = find.byKey(const Key('dev_compare_chart'));
        expect(chart, findsOneWidget);
        final box = tester.renderObject(chart);
        expect(box, paintsExactlyCountTimes(#drawLine, 11));
        expect(box, paintsExactlyCountTimes(#drawCircle, 11));
        // Semantik: Kennzahlen, nicht jeder Punkt.
        final label = tester.getSemantics(chart).label;
        expect(
          label,
          lang == 'de'
              ? startsWith(
                  'Kurve der Schlagabstände, Gurt als Linie, Kamera als '
                  'Punkte. RMSSD Kamera 116,4, Gurt 112,4 ms; ',
                )
              : startsWith('Curve of beat intervals'),
        );
        expect(label, contains(lang == 'de' ? '11 Paare' : '11 pairs'));
        expect(label, isNot(contains('1031')));
      },
    );
  }

  testWidgets('Detail: Kamera „unbekannt“ ohne Rohsignal', (tester) async {
    final s = await _store();
    final a = await s.add(
      _m(DateTime.utc(2030, 1, 1, 6)),
      beltPackets: _packets(DateTime.utc(2030, 1, 1, 6)),
    );
    await _pump(tester, s);
    await tester.tap(find.byKey(Key('dev_compare_row_$a')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const Key('dev_compare_detail_camera')),
        matching: find.text('unbekannt'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('Detail: keine Zuordnung ohne Kurve', (tester) async {
    final s = await _store();
    final a = await s.add(
      _m(DateTime.utc(2030, 1, 1, 6)),
      beltPackets: _packets(DateTime.utc(2030, 1, 1, 6), _raw.sublist(0, 8)),
    );
    await _pump(tester, s);
    await tester.tap(find.byKey(Key('dev_compare_row_$a')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('dev_compare_detail_no_match')), findsOne);
    expect(find.byKey(const Key('dev_compare_chart')), findsNothing);
  });

  test('Painter: Lücke im Gurt unterbricht die Linie, NaN kein Punkt', () {
    final p = BeltComparePainter(
      camera: const [1000, double.nan, 1010, 990],
      belt: const [1000, 1005, null, 995],
      line: const Color(0xFF000000),
      dot: const Color(0xFF000001),
      grid: const Color(0xFF000002),
    );
    expect(
      (Canvas c) => p.paint(c, const Size(200, 100)),
      paintsExactlyCountTimes(#drawLine, 1),
    );
    expect(
      (Canvas c) => p.paint(c, const Size(200, 100)),
      paintsExactlyCountTimes(#drawCircle, 3),
    );
  });
}
