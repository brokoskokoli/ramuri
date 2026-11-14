import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/readiness/readiness_texts.dart';
import 'package:running_app/l10n/app_localizations.dart';
import 'package:running_app/l10n/app_localizations_de.dart';
import 'package:running_app/l10n/app_localizations_en.dart';

import 'arb_language_test.dart' show load;

// WP34 Teil D1: Sprachregeln der Erholung (PAR-172, PAR-174, PAR-184,
// FR-0118). Kein „erholt“ oder „bereit“ in Sätzen; der Bandname „Gut erholt“
// bleibt (OQ-0029). Werte stehen als Schätzung mit Stufe und Grund (PAR-159).

final _forbidden = RegExp(
  r'erholt|bereit|\bready\b|recovered|rested|\bfit\b|diagnos|krank|\bill\b',
  caseSensitive: false,
);

/// Das einzige Wort der Liste, das ein Name sein darf, und die Verneinung.
const _allowedKeys = {
  'readinessBandWellRecovered': 'Gut erholt|Well recovered',
  'readinessNumberNote': 'Sie ist keine Diagnose|It is not a diagnosis',
};

List<String> violations(Map<String, String> texts) => [
  for (final e in texts.entries)
    if (e.key.startsWith('readiness') &&
        _forbidden.hasMatch(
          _allowedKeys.containsKey(e.key)
              ? e.value.replaceAll(RegExp(_allowedKeys[e.key]!), '')
              : e.value,
        ))
      e.key,
];

void main() {
  test(
    'Textschlüssel `readiness…`: kein „erholt“/„bereit“, keine Diagnose',
    () {
      for (final loc in ['de', 'en']) {
        expect(violations(load(loc)), isEmpty, reason: loc);
      }
    },
  );

  test('die Prüfung erkennt Verstöße', () {
    expect(violations({'readinessX': 'Du bist gut erholt.'}), isNotEmpty);
    expect(violations({'readinessX': 'You are ready to train.'}), isNotEmpty);
    expect(violations({'readinessX': 'Bereit für Tempo'}), isNotEmpty);
    expect(violations({'readinessX': 'Das ist eine Diagnose.'}), isNotEmpty);
    // Der Bandname darf nur als ganzer Name stehen.
    expect(
      violations({'readinessBandWellRecovered': 'Gut erholt, bereit'}),
      isNotEmpty,
    );
    expect(violations({'readinessBandWellRecovered': 'Gut erholt'}), isEmpty);
    expect(violations({'other': 'bereit'}), isEmpty);
  });

  for (final l in <AppLocalizations>[
    AppLocalizationsDe(),
    AppLocalizationsEn(),
  ]) {
    test('alle erzeugten Texte (${l.localeName}) halten die Regeln', () {
      final texts = <String>[
        for (final b in ReadinessBand.values)
          if (b != ReadinessBand.wellRecovered) readinessBandName(l, b),
        for (final lv in ReadinessLevel.values) readinessLevelWord(l, lv),
        for (final c in ReadinessLevelReasonCode.values)
          readinessReasonText(
            l,
            ReadinessLevelReason(c, count: 15, required: 18),
          ),
        for (final id in ReadinessFactorId.values) ...[
          readinessFactorName(l, id),
          readinessMissingText(l, id),
          for (final dir in ReadinessDirection.values)
            for (final cause in [null, ...ReadinessSleepCause.values])
              readinessDriverText(
                l,
                ReadinessDriver(
                  id: id,
                  source: ReadinessFactorSource.camera,
                  direction: dir,
                  impact: 1,
                  estimated: true,
                  fewMeasurements: true,
                  sleepCause: cause,
                ),
              ),
        ],
        for (final s in ReadinessFactorSource.values) readinessSourceName(l, s),
        for (final k in ReadinessFactKind.values)
          for (final z in [-1.0, 0.0, 1.0])
            readinessFactText(
              l,
              ReadinessFact(
                kind: k,
                source: ReadinessFactorSource.healthConnect,
                z: z,
                hours: 6,
              ),
            ),
        for (final k in [
          ReadinessFactKind.hrvDeviation,
          ReadinessFactKind.restingHeartRateDeviation,
        ])
          for (final today in [50.0, 53.0, 47.0])
            readinessFactText(
              l,
              ReadinessFact(
                kind: k,
                source: ReadinessFactorSource.healthConnect,
                z: 1,
                values: ReadinessValues(
                  windowMean: 50,
                  referenceMedian: 50,
                  today: today,
                  todayIsFallback: true,
                  decimals: 0,
                ),
              ),
            ),
        for (final m in MorningRmssdMark.values) ?readinessMarkText(l, m),
      ];
      expect(texts, isNotEmpty);
      for (final t in texts) {
        expect(t.trim(), isNotEmpty);
        expect(_forbidden.hasMatch(t), isFalse, reason: t);
      }
    });
  }

  test('Tatsache mit Zahl (PAR-171K), gerundet nach FR-0114', () {
    ReadinessFact fact(
      ReadinessFactKind k, {
      required double today,
      int decimals = 0,
      bool fallback = false,
    }) => ReadinessFact(
      kind: k,
      source: ReadinessFactorSource.healthConnect,
      z: -1,
      values: ReadinessValues(
        windowMean: 58,
        referenceMedian: 56,
        today: today,
        todayIsFallback: fallback,
        decimals: decimals,
      ),
    );
    final de = AppLocalizationsDe(), en = AppLocalizationsEn();
    final rhr = fact(ReadinessFactKind.restingHeartRateDeviation, today: 61);
    expect(
      readinessFactText(de, rhr),
      startsWith('Ruhepuls heute 3/min über deinem Mittel'),
    );
    expect(
      readinessFactText(en, rhr),
      startsWith('Resting heart rate today 3/min above your average'),
    );
    expect(
      readinessFactText(
        de,
        fact(ReadinessFactKind.hrvDeviation, today: 52.4, decimals: 1),
      ),
      startsWith('HRV heute 5,6 ms unter deinem Mittel'),
    );
    // Rundet die Differenz auf 0: „auf deinem Mittel“, keine Scheinpräzision.
    expect(
      readinessFactText(
        de,
        fact(ReadinessFactKind.restingHeartRateDeviation, today: 58),
      ),
      startsWith('Ruhepuls heute auf deinem Mittel'),
    );
    // Ersatzwert (PAR-160) wird genannt.
    expect(
      readinessFactText(
        de,
        fact(
          ReadinessFactKind.restingHeartRateDeviation,
          today: 61,
          fallback: true,
        ),
      ),
      contains('Ersatzwert'),
    );
  });
}
