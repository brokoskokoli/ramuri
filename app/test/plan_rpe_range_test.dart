import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/plan/plan_unit_screen.dart';
import 'package:running_app/features/settings/unit_format.dart';
import 'package:running_app/ui/ui.dart';

import 'helpers/widget_helpers.dart';

// WP24 NB5: Gehen 1 bis 2, Laufen 1 bis 4 (PAR-115), jeweils mit dem Wort der
// oberen Stufe; die Zahlen kommen aus dem Kern, nicht aus dem Test.
void main() {
  Future<void> pumpRow(WidgetTester tester, PlanSegmentKind kind) async {
    final target = segmentTarget(
      unitKind: PlanUnitKind.walkRun,
      segment: kind,
      inputs: IntensityInputs(),
    )!;
    await tester.pumpWidget(
      localizedApp(
        home: Scaffold(
          body: PlanSegmentRow(
            segment: PlanSegment(
              kind: kind,
              minutes: 5,
              intensity: target.intensity,
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
  }

  testWidgets('Gehabschnitt: 1–2 mit dem Wort der Stufe 2', (tester) async {
    await pumpRow(tester, PlanSegmentKind.walk);
    expect(
      find.text('Anstrengung 1–2 · Locker, Reden ohne Mühe'),
      findsOneWidget,
    );
    expect(find.textContaining('Kaum Anstrengung'), findsNothing);
  });

  testWidgets('Laufabschnitt: 1–4 mit dem Wort der Stufe 4', (tester) async {
    await pumpRow(tester, PlanSegmentKind.run);
    expect(
      find.text('Anstrengung 1–4 · Fordert etwas, ganze Sätze gehen noch'),
      findsOneWidget,
    );
  });
}
