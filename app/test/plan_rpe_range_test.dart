import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/plan/plan_unit_screen.dart';
import 'package:running_app/features/settings/unit_format.dart';
import 'package:running_app/ui/ui.dart';

import 'helpers/widget_helpers.dart';

// WP24 NB4: Bei einer RPE-Spanne steht das Wort der unteren Stufe.
void main() {
  testWidgets('Spanne 1 bis 4 (Gehen) trägt das Wort der Stufe 1, nicht 4', (
    tester,
  ) async {
    await tester.pumpWidget(
      localizedApp(
        home: Scaffold(
          body: PlanSegmentRow(
            segment: const PlanSegment(
              kind: PlanSegmentKind.walk,
              minutes: 5,
              intensity: PlanTargetIntensity(rpeMin: 1, rpeMax: 4),
            ),
            formatter: const UnitFormatter(
              unit: DistanceUnit.kilometers,
              languageCode: 'de',
              distanceLabel: 'km',
              paceLabel: 'min/km',
              elevationLabel: 'm',
            ),
            colors: RamuriColors.light,
          ),
        ),
      ),
    );
    expect(
      find.text('Anstrengung 1–4 · Kaum Anstrengung, wie gemütliches Gehen'),
      findsOneWidget,
    );
    expect(find.textContaining('Fordert etwas'), findsNothing);
  });
}
