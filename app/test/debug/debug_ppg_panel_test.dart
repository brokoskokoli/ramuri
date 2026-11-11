import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/debug/debug_ppg_panel.dart';
import 'package:running_app/debug/debug_test_ppg_camera.dart';

void main() {
  testWidgets('Zeitraffer bleibt über Navigation und Zuklappen erhalten', (
    tester,
  ) async {
    final cam = DebugTestPpgCamera();
    await tester.pumpWidget(
      DebugPpgPanel(
        camera: cam,
        child: MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => Scaffold(
                    body: TextButton(
                      key: const Key('back'),
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('zurück'),
                    ),
                  ),
                ),
              ),
              child: const Text('weiter'),
            ),
          ),
        ),
      ),
    );
    // Beim Einschalten ist der Zustand schon am zugeklappten Knopf sichtbar.
    expect(find.text('PPG'), findsOneWidget);
    await tester.tap(find.textContaining(RegExp(r'^PPG( x30| x)?$')));
    await tester.pump();
    await tester.tap(find.textContaining('PPG Zeitraffer'));
    await tester.pump();
    expect(cam.speed, 30);
    await tester.tap(find.textContaining(RegExp(r'^PPG( x30| x)?$')));
    await tester.pump();
    expect(find.text('PPG x30'), findsOneWidget);

    await tester.tap(find.text('weiter'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('back')), findsOneWidget);
    expect(cam.speed, 30);
    expect(find.text('PPG x30'), findsOneWidget);
    await tester.tap(find.byKey(const Key('back')));
    await tester.pumpAndSettle();
    expect(cam.speed, 30);
    await tester.tap(find.textContaining(RegExp(r'^PPG( x30| x)?$')));
    await tester.pump();
    expect(find.text('PPG Zeitraffer an'), findsOneWidget);
  });
}
