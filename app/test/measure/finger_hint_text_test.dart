import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/l10n/app_localizations.dart';

// FR-0214: Der Hinweis vor der Kamera-Messung verlangt leichtes, gleichmäßiges
// Auflegen statt „nicht drücken“; der Hinweis bei schwachem Signal bleibt.

void main() {
  final de = lookupAppLocalizations(const Locale('de'));
  final en = lookupAppLocalizations(const Locale('en'));

  test('de: Finger leicht auflegen, nicht fest drücken', () {
    expect(de.measureFingerBody, contains('leicht und gleichmäßig auflegen'));
    expect(de.measureFingerBody, contains('nicht fest drücken'));
    expect(de.measureFingerBody, isNot(contains(', nicht drücken.')));
  });

  test('en: resting lightly, without pressing hard', () {
    expect(en.measureFingerBody, contains('resting lightly and evenly'));
    expect(en.measureFingerBody, contains('without pressing hard'));
    expect(en.measureFingerBody, isNot(contains(', without pressing.')));
  });

  test('Hinweis bei schwachem Signal bleibt unverändert', () {
    expect(
      de.measureHintWeakBody,
      'Deck Kamera und Blitz ganz mit der Fingerkuppe ab, ohne zu fest zu '
      'drücken.',
    );
    expect(
      en.measureHintWeakBody,
      'Cover the camera and the flash completely with your fingertip, '
      'without pressing too hard.',
    );
  });
}
