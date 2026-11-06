import 'package:core/core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
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

  /// Liest den Stand neu aus dem Speicher, etwa nach "Alles löschen": danach
  /// gilt wieder der Zustand des ersten Starts (km, Einrichtung offen).
  Future<void> reload() async {
    final unit = await _store.get(SettingKeys.distanceUnit);
    final done = await _store.get(SettingKeys.setupDone);
    _unit = DistanceUnit.fromStorage(unit);
    _setupDone = done == '1';
    notifyListeners();
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

/// Hält die geladenen [AppSettings]. Die Einstellungen liegen erst nach dem
/// Öffnen des Speichers vor, der Scope steht aber über dem Navigator
/// (MaterialApp.builder); der Halter überbrückt das.
class AppSettingsHolder extends ChangeNotifier {
  AppSettings? _settings;

  AppSettings? get settings => _settings;

  /// Setzt die geladenen Einstellungen; deren Änderungen melden sich weiter.
  void attach(AppSettings settings) {
    if (identical(_settings, settings)) return;
    _settings?.removeListener(notifyListeners);
    _settings = settings..addListener(notifyListeners);
    notifyListeners();
  }

  @override
  void dispose() {
    _settings?.removeListener(notifyListeners);
    super.dispose();
  }
}

/// Stellt [AppSettings] im Widget-Baum bereit, über dem Navigator, damit jede
/// Seite (auch per normalem `Navigator.push`) sie sieht.
class AppSettingsScope extends InheritedNotifier<AppSettingsHolder> {
  const AppSettingsScope({
    super.key,
    required AppSettingsHolder holder,
    required super.child,
  }) : super(notifier: holder);

  static AppSettingsHolder holderOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppSettingsScope>()!.notifier!;

  /// Die geladenen Einstellungen; erst nach dem Öffnen des Speichers da, jede
  /// Seite mit Einheiten entsteht erst danach.
  static AppSettings of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<AppSettingsScope>()!
      .notifier!
      .settings!;

  /// Der gemeinsame Formatierer für Strecke und Pace in der gewählten Einheit
  /// und Sprache (NFR-0006). Alle Anzeigen von Strecke und Pace nutzen ihn.
  static UnitFormatter formatterOf(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final unit = of(context).distanceUnit;
    final miles = unit == DistanceUnit.miles;
    return UnitFormatter(
      unit: unit,
      languageCode: Localizations.localeOf(context).languageCode,
      distanceLabel: miles ? l10n.unitMiles : l10n.unitKilometers,
      paceLabel: miles ? l10n.unitPacePerMile : l10n.unitPacePerKilometer,
    );
  }
}
