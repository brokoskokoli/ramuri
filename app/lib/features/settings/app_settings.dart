import 'package:core/core.dart';
import 'package:flutter/material.dart';

import 'unit_format.dart';

/// Einstellungen, die die ganze App betreffen: Anzeigeeinheit und Stand der
/// Ersteinrichtung. Gespeichert wird über [SettingsStore] (storage_settings).
class AppSettings extends ChangeNotifier {
  AppSettings._(this._store, this._clock, this._unit, this._setupDone);

  final SettingsStore _store;
  final Clock _clock;
  DistanceUnit _unit;
  bool _setupDone;

  static Future<AppSettings> load(SettingsStore store, Clock clock) async {
    final unit = await store.get(SettingKeys.distanceUnit);
    final done = await store.get(SettingKeys.setupDone);
    return AppSettings._(
      store,
      clock,
      DistanceUnit.fromStorage(unit),
      done == '1',
    );
  }

  DistanceUnit get distanceUnit => _unit;

  /// Die Ersteinrichtung wurde abgeschlossen oder übersprungen (FR-0001).
  bool get setupDone => _setupDone;

  /// Ändert nur die Anzeige (NFR-0006); Rohdaten bleiben unberührt. Bei einem
  /// Speicherfehler bleibt der alte Wert und der Fehler geht weiter.
  Future<void> setDistanceUnit(DistanceUnit unit) async {
    await _store.set(
      SettingKeys.distanceUnit,
      unit.storageValue,
      at: _clock.now(),
    );
    _unit = unit;
    notifyListeners();
  }

  Future<void> markSetupDone() async {
    await _store.set(SettingKeys.setupDone, '1', at: _clock.now());
    _setupDone = true;
    notifyListeners();
  }
}

/// Stellt [AppSettings] im Widget-Baum bereit.
class AppSettingsScope extends InheritedNotifier<AppSettings> {
  const AppSettingsScope({
    super.key,
    required AppSettings settings,
    required super.child,
  }) : super(notifier: settings);

  static AppSettings of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppSettingsScope>()!.notifier!;

  /// Öffnet [builder] als neue Seite so, dass [of] und [formatterOf] auch dort
  /// gelten (der Navigator liegt über dem Scope). Alle Seiten nach der
  /// Startseite öffnen sich so.
  static Future<T?> push<T>(BuildContext context, WidgetBuilder builder) {
    final settings = of(context);
    return Navigator.of(context).push<T>(
      MaterialPageRoute<T>(
        builder: (_) => AppSettingsScope(
          settings: settings,
          child: Builder(builder: builder),
        ),
      ),
    );
  }

  /// Der gemeinsame Formatierer für Strecke und Pace in der gewählten Einheit
  /// und Sprache (NFR-0006). Alle Anzeigen von Strecke und Pace nutzen ihn.
  static UnitFormatter formatterOf(BuildContext context) => UnitFormatter(
    unit: of(context).distanceUnit,
    languageCode: Localizations.localeOf(context).languageCode,
  );
}
