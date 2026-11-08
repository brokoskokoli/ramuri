import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Lizenztexte der gebündelten Schriften (SIL OFL 1.1, FR-0205). Liegen unter
/// `assets/fonts/` und stehen mit dem Namen der Schrift in den Lizenzangaben.
const Map<String, String> fontLicenseAssets = {
  'Sora': 'assets/fonts/OFL-Sora.txt',
  'Manrope': 'assets/fonts/OFL-Manrope.txt',
};

/// Meldet die Lizenzen bei der [LicenseRegistry] an. `main.dart` und
/// `main_debug.dart` rufen das einmal beim Start. Geladen wird erst, wenn die
/// Lizenzseite sie liest.
void registerFontLicenses({AssetBundle? bundle}) {
  LicenseRegistry.addLicense(() async* {
    final source = bundle ?? rootBundle;
    for (final entry in fontLicenseAssets.entries) {
      final text = await source.loadString(entry.value);
      yield LicenseEntryWithLineBreaks([entry.key], text);
    }
  });
}
