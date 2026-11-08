import 'package:flutter/widgets.dart';

import 'app.dart';
import 'app_dependencies.dart';
import 'ui/font_licenses.dart';

void main() {
  registerFontLicenses();
  runApp(RunningApp(dependencies: AppDependencies.create()));
}
