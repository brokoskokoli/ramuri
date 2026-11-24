// Abgleich der PAR-Werte des App-Pakets und des Android-Codes mit
// docs/phase-2-3-rules.md (Abschnitt 7.1, Kamera-Messung).
//
// Ergänzt den Abgleich in core (packages/core/test/fitness/
// par_constants_test.dart), der diese Werte nicht erreicht: die Fristen und
// Fenster aus resting_measure_controller.dart (PAR-221 bis PAR-226, Fenster
// aus PAR-234) und die Sättigungsgrenze aus PpgFrameStats.kt (PAR-217, als
// Text gelesen). Parser und Abgleich sind dieselben wie in core
// (packages/core/test/support/par_docs.dart). In core stehen diese IDs als
// Ausnahme bzw. Doku-Zahl mit dem Grund [parCheckedInApp]; der Test hier
// prüft, dass das für jede hier zugeordnete ID gilt und umgekehrt.
//
// Arbeitsverzeichnis von `flutter test` ist app/.
import 'dart:io';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/measure/resting_measure_controller.dart';

import '../packages/core/test/support/par_docs.dart';
import '../packages/core/test/support/par_exceptions.dart';

const _doc = '../docs/phase-2-3-rules.md';
const _kotlinFile =
    'android/app/src/main/kotlin/io/github/brokoskokoli/ramuri/PpgFrameStats.kt';
const _kotlinConst = 'SATURATED_Y';

/// Wert der Kotlin-Konstante `const val <name> = <Zahl>` in [text], sonst
/// null.
int? kotlinIntConst(String text, String name) {
  final m = RegExp('const val ${RegExp.escape(name)} = (\\d+)')
      .firstMatch(text);
  return m == null ? null : int.parse(m.group(1)!);
}

/// Reserve der Gesamtfrist (PAR-225): Frist minus Ende der Daten, Startfrist
/// und Frist ohne Bild.
double _reserve(double total, double dataEnd) =>
    total - dataEnd - restingStartTimeoutSeconds - restingNoImageTimeoutSeconds;

/// [a], wenn beide Werte gleich sind (die Doku nennt sie einmal), sonst NaN.
num _both(num a, num b) => a == b ? a : double.nan;

/// PAR-ID → Einträge in Sekunden bzw. Helligkeit, wie in der Doku.
Map<String, List<Object>> appParValues(int saturatedY) {
  final fixedReserve = _reserve(
    restingTotalTimeoutSeconds,
    ppgStandardWindow.dataEnd,
  );
  final searchReserve = _reserve(
    restingSearchTotalTimeoutSeconds,
    ppgSearchMaxRecordSeconds,
  );
  return {
    'PAR-217': [
      const DocOnly(0, 'Untergrenze der Helligkeitsskala Y.'),
      const DocOnly(255, 'Obergrenze der Helligkeitsskala Y.'),
      saturatedY,
    ],
    'PAR-221': [restingCheckIntervalSeconds],
    'PAR-222': [
      restingCheckStartSeconds,
      ppgStandardWindow.start,
      ppgStandardWindow.dataEnd,
    ],
    'PAR-223': [restingStartTimeoutSeconds],
    'PAR-224': [restingNoImageTimeoutSeconds],
    'PAR-225': [
      _both(fixedReserve, searchReserve),
      // Festes Fenster: 66,5 + 5 + 3 + 12 = 86,5 s.
      ppgStandardWindow.dataEnd,
      restingStartTimeoutSeconds,
      restingNoImageTimeoutSeconds,
      fixedReserve,
      restingTotalTimeoutSeconds,
      // Fenstersuche: 120 + 5 + 3 + 12 = 140 s.
      ppgSearchMaxRecordSeconds,
      restingStartTimeoutSeconds,
      restingNoImageTimeoutSeconds,
      searchReserve,
      restingSearchTotalTimeoutSeconds,
    ],
    'PAR-226': [restingLiveWindowSeconds],
    'PAR-234': [
      restingLiveStageWindowSeconds,
      const DocOnly(0.3, 'Signalqualität, geprüft im Abgleich in core.'),
      const DocOnly(70, 'Anteil gültiger Intervalle, geprüft in core.'),
    ],
  };
}

void main() {
  test('Kotlin-Konstante wird gelesen, fehlende ergibt null', () {
    expect(
      kotlinIntConst('    const val SATURATED_Y = 250\n', 'SATURATED_Y'),
      250,
    );
    expect(
      kotlinIntConst('    const val SATURATED = 250\n', 'SATURATED_Y'),
      isNull,
    );
    expect(
      kotlinIntConst('    val SATURATED_Y = 250\n', 'SATURATED_Y'),
      isNull,
    );
  });

  group('Zuständigkeit App-Test und core', () {
    test(
      'ID hier geprüft, in core ohne Ausnahme mit Verweis, ist ein Fehler',
      () {
        final app = {
          'PAR-900': [3],
          'PAR-901': [5],
        };
        expect(compareAppCoverage(app, {'PAR-900': parCheckedInApp}, {}), [
          'PAR-901: im App-Test geprüft, in core aber nicht als Ausnahme '
              '„$parCheckedInApp“ (Code-Werte hier [5], in core als Doku-Zahl '
              'mit Verweis [])',
        ]);
        // Ausnahme mit anderem Grund zählt nicht.
        expect(
          compareAppCoverage(app, {
            'PAR-900': parCheckedInApp,
            'PAR-901': 'anderer Grund',
          }, {}),
          hasLength(1),
        );
      },
    );

    test('teilweise in core: Doku-Zahl mit Verweis muss dem Wert hier entsprechen', () {
      final app = {
        'PAR-900': [5, const DocOnly(0.3, 'in core.')],
      };
      expect(
        compareAppCoverage(app, {}, {
          'PAR-900': [const DocOnly(5, parCheckedInApp), 0.3],
        }),
        isEmpty,
      );
      expect(
        compareAppCoverage(app, {}, {
          'PAR-900': [const DocOnly(6, parCheckedInApp), 0.3],
        }),
        [
          'PAR-900: im App-Test geprüft, in core aber nicht als Ausnahme '
              '„$parCheckedInApp“ (Code-Werte hier [5], in core als Doku-Zahl '
              'mit Verweis [6])',
        ],
      );
    });

    test('Verweis in core ohne Zuordnung hier ist ein Fehler', () {
      expect(
        compareAppCoverage(
          {},
          {'PAR-900': parCheckedInApp},
          {
            'PAR-901': [const DocOnly(5, parCheckedInApp)],
          },
        ),
        [
          'PAR-900: in core als „$parCheckedInApp“, im App-Test nicht '
              'zugeordnet',
          'PAR-901: in core Doku-Zahl mit „$parCheckedInApp“, im App-Test '
              'nicht zugeordnet',
        ],
      );
    });
  });

  test('PAR-Werte im App-Paket entsprechen docs/phase-2-3-rules.md', () {
    final kotlin = File(_kotlinFile).readAsStringSync();
    final saturatedY = kotlinIntConst(kotlin, _kotlinConst);
    expect(
      saturatedY,
      isNotNull,
      reason:
          '$_kotlinFile: Konstante $_kotlinConst nicht gefunden '
          '(gesucht: const val $_kotlinConst = <Zahl>)',
    );
    final values = appParValues(saturatedY!);
    final rows = parseParTables(
      File(_doc).readAsStringSync(),
      'docs/phase-2-3-rules.md',
    ).where((r) => values.containsKey(r.id)).toList();
    final problems = compareParValues(rows, values, const {});
    expect(problems, isEmpty, reason: problems.join('\n'));
  });

  test('jede hier geprüfte ID steht in core als Ausnahme mit Verweis', () {
    final problems = compareAppCoverage(
      appParValues(0),
      parExceptions,
      parDocOnlyCheckedInApp,
    );
    expect(problems, isEmpty, reason: problems.join('\n'));
  });
  test('PAR-227: Takt des Wechsels in PpgCameraLogic.kt wie in core', () {
    // Der Wert selbst wird in core gegen die Doku geprüft (ppgCameraFinderTurnSeconds).
    final text = File(
      'android/app/src/main/kotlin/io/github/brokoskokoli/ramuri/PpgCameraLogic.kt',
    ).readAsStringSync();
    final m = RegExp(r'const val PREVIEW_TURN_NS = ([\d_]+)L').firstMatch(text);
    expect(m, isNotNull);
    expect(
      int.parse(m!.group(1)!.replaceAll('_', '')),
      (ppgCameraFinderTurnSeconds * 1e9).round(),
    );
  });
}
