import 'package:core/core.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/run/voice_texts.dart';
import 'package:running_app/l10n/app_localizations.dart';

VoiceTexts _t(String lang) => VoiceTexts(lookupAppLocalizations(Locale(lang)));

GuidanceEvent _km(int km, int seconds, int? paceSeconds) =>
    GuidanceEvent.kilometer(
      kilometer: km,
      time: Duration(seconds: seconds),
      duration: paceSeconds == null ? null : Duration(seconds: paceSeconds),
    );

void main() {
  const km = DistanceUnit.kilometers;
  const mi = DistanceUnit.miles;

  test('Kilometer: Zeit und Pace wie die Anzeige (m:ss je km)', () {
    expect(
      _t('de').text(_km(3, 1000, 312), km),
      'Kilometer 3. Zeit 16 Minuten 40 Sekunden. Pace 5:12 pro Kilometer.',
    );
    expect(
      _t('en').text(_km(1, 305, 305), km),
      'Kilometer 1. Time 5 minutes 5 seconds. Pace 5:05 per kilometer.',
    );
  });

  test('Kilometer ab einer Stunde; Pace fehlt, wenn unbekannt', () {
    expect(
      _t('de').text(_km(10, 3661, null), km),
      'Kilometer 10. Zeit 1 Stunde 1 Minute.',
    );
  });

  test('Meilen-Einstellung: Strecke in Meilen, Pace je Meile', () {
    // 5:00 je km = 8:03 je Meile (4:60 x 1,609344 = 482,8 s).
    expect(
      _t('de').text(_km(2, 600, 300), mi),
      '1,2 Meilen. Zeit 10 Minuten 0 Sekunden. Pace 8:03 pro Meile.',
    );
    expect(
      _t('en').text(_km(2, 600, 300), mi),
      '1.2 miles. Time 10 minutes 0 seconds. Pace 8:03 per mile.',
    );
  });

  test('Abschnittswechsel mit Ziel: Pace, sonst Puls, sonst RPE', () {
    const seg = PlanSegment(
      kind: PlanSegmentKind.interval,
      minutes: 4,
      intensity: PlanTargetIntensity(
        paceFastSecondsPerKm: 270,
        paceSlowSecondsPerKm: 285,
        hrMinBpm: 160,
        hrMaxBpm: 170,
        rpeMin: 7,
        rpeMax: 8,
      ),
    );
    expect(
      _t('de').text(GuidanceEvent.segmentChange(index: 1, segment: seg), km),
      'Intervall, 4 Minuten 0 Sekunden. Pace 4:30 bis 4:45.',
    );
    const hr = PlanSegment(
      kind: PlanSegmentKind.easy,
      minutes: 10,
      intensity: PlanTargetIntensity(
        hrMinBpm: 120,
        hrMaxBpm: 140,
        rpeMin: 3,
        rpeMax: 3,
      ),
    );
    expect(
      _t('en').text(GuidanceEvent.segmentChange(index: 0, segment: hr), km),
      'Easy running, 10 minutes 0 seconds. Heart rate 120 to 140.',
    );
    const rpe = PlanSegment(
      kind: PlanSegmentKind.walk,
      minutes: 1,
      seconds: 90,
      intensity: PlanTargetIntensity(rpeMin: 2, rpeMax: 2),
    );
    expect(
      _t('de').text(GuidanceEvent.segmentChange(index: 0, segment: rpe), km),
      'Gehen, 1 Minute 30 Sekunden. Anstrengung 2 von 10.',
    );
    const limit = PlanSegment(
      kind: PlanSegmentKind.easy,
      minutes: 5,
      intensity: PlanTargetIntensity(
        paceSlowSecondsPerKm: 360,
        paceIsLimit: true,
      ),
    );
    expect(
      _t('de').text(GuidanceEvent.segmentChange(index: 0, segment: limit), km),
      'Locker laufen, 5 Minuten 0 Sekunden. Nicht schneller als 6:00.',
    );
  });

  test('Vorankündigung, Ende, Puls, Gehpausen; Sprache aus der App-Locale', () {
    const seg = PlanSegment(kind: PlanSegmentKind.recovery, minutes: 2);
    final de = _t('de');
    expect(
      de.text(
        GuidanceEvent.segmentPreview(
          index: 1,
          segment: seg,
          until: const Duration(seconds: 10),
        ),
        km,
      ),
      'In 10 Sekunden: Trabpause.',
    );
    expect(
      de.text(const GuidanceEvent.unitComplete(), km),
      'Einheit geschafft.',
    );
    expect(
      de.text(GuidanceEvent.heartRateAbove(bpm: 171, maxBpm: 160), km),
      'Puls 171, über 160. Etwas langsamer.',
    );
    expect(de.text(const GuidanceEvent.walkBreakHint(), km), isNotEmpty);
    expect(de.languageTag, 'de');
    expect(_t('en').languageTag, 'en');
  });
}
