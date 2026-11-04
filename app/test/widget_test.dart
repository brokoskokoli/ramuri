import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/app.dart';
import 'package:running_app/app_dependencies.dart';

Future<void> _pump(WidgetTester tester, Locale locale) async {
  tester.platformDispatcher.localesTestValue = [locale];
  addTearDown(tester.platformDispatcher.clearLocalesTestValue);
  await tester.pumpWidget(const RunningApp(dependencies: AppDependencies()));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Startbildschirm auf Deutsch', (tester) async {
    await _pump(tester, const Locale('de'));
    expect(find.text('Willkommen bei der Lauf-App'), findsOneWidget);
  });

  testWidgets('Startbildschirm auf Englisch', (tester) async {
    await _pump(tester, const Locale('en'));
    expect(find.text('Welcome to the running app'), findsOneWidget);
    expect(find.text('Willkommen bei der Lauf-App'), findsNothing);
  });
}
