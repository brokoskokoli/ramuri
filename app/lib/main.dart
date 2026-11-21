import 'package:flutter/widgets.dart';

import 'app.dart';
import 'app_dependencies.dart';
import 'error_counter.dart';
import 'ui/font_licenses.dart';

/// Unbehandelte Fehler werden nur nach Typ und Ort gezählt ([ErrorCounter]);
/// im Release-Build gibt es dazu keine Ausgabe.
void main() {
  final errors = ErrorCounter();
  runCountingErrors(errors, () {
    registerFontLicenses();
    runApp(RunningApp(dependencies: AppDependencies.create(errors: errors)));
  });
}
