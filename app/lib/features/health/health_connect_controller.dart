import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter/foundation.dart';

/// Stand und Aktionen der Seite „Gesundheitsdaten aus Health Connect“ (WP32 Teil C2). Eine Instanz je Sitzung; sie
/// besitzt den [ConsentService] und den [HealthImportService], damit Widerrufe sofort für den Import gelten (SEC-0001).
/// Keine Werte in Fehlern oder Logs.
class HealthConnectController extends ChangeNotifier {
  HealthConnectController({
    required this.port,
    required this.store,
    required SettingsStore settings,
    required ConsentStore consentStore,
    required this.clock,
  }) : _settings = settings,
       consents = ConsentService(consentStore, clock) {
    importer = HealthImportService(
      port: port,
      store: store,
      consents: consents,
      clock: clock,
      settings: settings,
    );
  }

  final HealthConnectPort port;
  final HealthImportStore store;
  final ConsentService consents;
  final Clock clock;
  final SettingsStore _settings;
  late final HealthImportService importer;

  bool loaded = false;
  HealthSdkStatus sdk = HealthSdkStatus.unavailable;

  /// Arten mit eigener Einwilligung.
  Set<HealthDataKind> enabled = {};

  /// Arten, für die Health Connect das Leserecht erteilt hat.
  Set<HealthDataKind> permitted = {};
  DateTime? lastImport;
  bool fetching = false;

  /// Arten mit offener Löschfrage (Recht fehlt trotz Einwilligung, oder eine Antwort steht aus).
  List<HealthDataKind> questions = [];

  /// Gesetzt, solange eine Löschfrage auf dem Bildschirm steht (je Sitzung höchstens eine Abfolge zugleich).
  bool asking = false;

  /// Arten, deren Frage in dieser Sitzung beim Öffnen der App schon mit „Abbrechen“ zurückgestellt wurde (nicht erneut
  /// beim nächsten Öffnen von „Heute“); die Seite selbst fragt immer.
  final Set<HealthDataKind> deferred = {};

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Import beim App-Start und beim Öffnen von „Heute“; Fehler bleiben still, die Sperre hält der Dienst.
  void runInBackground(HealthImportTrigger trigger) {
    importer.run(trigger).then<void>((_) {}, onError: (Object _) {});
  }

  /// Import wie [runInBackground], danach Zustand neu lesen, damit offene Löschfragen beim Öffnen der App gezeigt werden
  /// können (SEC-0007, nicht nur auf der Health-Connect-Seite). Fehler bleiben still.
  Future<void> importThenLoad(HealthImportTrigger trigger) async {
    try {
      await importer.run(trigger);
    } catch (_) {}
    try {
      await load();
    } catch (_) {}
  }

  /// Liest Zustand, Einwilligungen, Rechte und offene Löschfragen neu. Fehlt ein Recht für eine eingewilligte Art (oder ist Health Connect nicht mehr
  /// verfügbar), deren importierte Daten es gibt, wird die Löschfrage geöffnet (SEC-0007); ohne Daten wird sie still geschlossen.
  Future<void> load() async {
    try {
      sdk = await port.sdkStatus();
    } catch (_) {
      sdk = HealthSdkStatus.unavailable;
    }
    final on = <HealthDataKind>{};
    for (final k in HealthDataKind.values) {
      if (await consents.isGranted(healthSourceKey(k))) on.add(k);
    }
    enabled = on;
    permitted = {};
    if (sdk == HealthSdkStatus.available) {
      try {
        permitted = await port.grantedKinds();
      } catch (_) {
        permitted = {};
      }
    }
    final open = <HealthDataKind>[];
    for (final k in HealthDataKind.values) {
      final key = healthSourceKey(k);
      var ask = false;
      try {
        ask = await consents.isDeleteQuestionOpen(key);
        // Ohne Health Connect ist [permitted] leer: „nicht verfügbar“ zählt wie ein fehlendes Recht.
        final missing = on.contains(k) && !permitted.contains(k);
        if (!ask && missing && await store.count(k) > 0) {
          await consents.openDeleteQuestion(key);
          ask = true;
        } else if (ask && await store.count(k) == 0) {
          await consents.closeDeleteQuestion(key);
          ask = false;
        }
      } catch (_) {
        // Lesefehler: die Frage bleibt, wie sie war; der nächste Start fragt wieder.
      }
      if (ask) open.add(k);
    }
    questions = open;
    lastImport = await _readLastImport();
    loaded = true;
    _notify();
  }

  Future<DateTime?> _readLastImport() async {
    try {
      final ms = int.tryParse(
        await _settings.get(HealthImportService.lastImportKey) ?? '',
      );
      return ms == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toLocal();
    } catch (_) {
      return null;
    }
  }

  /// Schaltet die Einwilligung einer Art ein. Nur diese Art ändert sich (SEC-0002).
  Future<void> enable(HealthDataKind kind) async {
    final key = healthSourceKey(kind);
    await consents.grant(key);
    try {
      await consents.closeDeleteQuestion(key);
    } catch (_) {}
    enabled = {...enabled, kind};
    questions = [...questions]..remove(kind);
    _notify();
  }

  /// Schaltet die Einwilligung einer Art aus; ab jetzt liest der Import sie nicht mehr. Die Löschfrage wird gemerkt, bis
  /// sie beantwortet ist (auch nach einem Ende der App); scheitert das Merken, wird trotzdem jetzt gefragt.
  Future<void> disable(HealthDataKind kind) async {
    final key = healthSourceKey(kind);
    await consents.revoke(key);
    enabled = {...enabled}..remove(kind);
    try {
      await consents.openDeleteQuestion(key);
    } catch (_) {}
    if (!questions.contains(kind)) questions = [...questions, kind];
    _notify();
  }

  /// „Abbrechen, weiter lesen“ nach dem Ausschalten: Einwilligung wieder erteilen.
  Future<void> cancelDisable(HealthDataKind kind) => enable(kind);

  /// Antwort auf die Löschfrage: [delete] löscht die importierten Daten genau dieser Art, sonst bleiben sie. Der Import
  /// dieser Art endet in beiden Fällen (Einwilligung widerrufen). Scheitert das Löschen, bleibt die Frage offen.
  Future<void> answerDeleteQuestion(
    HealthDataKind kind, {
    required bool delete,
  }) async {
    final key = healthSourceKey(kind);
    if (await consents.isGranted(key)) await consents.revoke(key);
    if (delete) await store.deleteKind(kind);
    await consents.closeDeleteQuestion(key);
    enabled = {...enabled}..remove(kind);
    questions = [...questions]..remove(kind);
    _notify();
  }

  /// „Health Connect installieren“: öffnet den Play Store; `false`, wenn sich nichts öffnen ließ (kein Absturz).
  Future<bool> openInstall() async {
    try {
      return await port.openInstall();
    } catch (_) {
      return false;
    }
  }

  /// Zeigt den Berechtigungsdialog von Health Connect, nur für die eingeschalteten Arten.
  Future<void> requestRights() async {
    if (enabled.isEmpty) return;
    try {
      permitted = await port.requestPermissions({...enabled});
    } catch (_) {
      permitted = {};
    }
    _notify();
  }

  /// „Jetzt abrufen“.
  Future<HealthImportResult> fetchNow() async {
    fetching = true;
    _notify();
    try {
      return await importer.run(HealthImportTrigger.manual);
    } finally {
      fetching = false;
      lastImport = await _readLastImport();
      await load();
    }
  }
}
