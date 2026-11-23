import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter/foundation.dart';

/// Baut den Controller einer Sitzung aus dem ganzen Port: Die Seite bekommt nur [HealthConnectPermissions], das Lesen
/// geht nur über [ConsentedHealthReader] in den [HealthImportService] (SEC-0001, SEC-0002). Seite, Import und Wächter
/// teilen sich eine [ConsentService]-Instanz, damit Widerrufe sofort für den Import gelten.
HealthConnectController healthConnectSession({
  required HealthConnectPort port,
  required HealthImportStore store,
  required SettingsStore settings,
  required ConsentStore consentStore,
  required Clock clock,
  void Function(Object error, StackTrace stack)? countError,
}) {
  final consents = ConsentService(consentStore, clock);
  return HealthConnectController(
    permissions: port,
    importer: HealthImportService(
      permissions: port,
      reader: ConsentedHealthReader(port, consents),
      store: store,
      clock: clock,
      settings: settings,
    ),
    store: store,
    settings: settings,
    clock: clock,
    countError: countError,
  );
}

/// Stand und Aktionen der Seite „Health Connect“ (WP32 Teil C2). Eine Instanz je Sitzung (siehe
/// [healthConnectSession]); sie hat nur Rechte und Zustand von Health Connect ([permissions]), kein Lesen, und nutzt die
/// Einwilligungen des [importer], damit Widerrufe sofort für den Import gelten (SEC-0001). Keine Werte in Fehlern oder
/// Logs.
class HealthConnectController extends ChangeNotifier {
  HealthConnectController({
    required this.permissions,
    required this.importer,
    required this.store,
    required this._settings,
    required this.clock,
    this.countError,
  });

  final HealthConnectPermissions permissions;
  final HealthImportStore store;
  final Clock clock;
  final SettingsStore _settings;
  final HealthImportService importer;

  /// Dieselbe Instanz wie im Import und im Wächter.
  ConsentService get consents => importer.consents;

  /// Zählt die hier still abgefangenen Fehler (nur Typ und Ort, `ErrorCounter.record`); `null`: nicht verdrahtet.
  final void Function(Object error, StackTrace stack)? countError;

  void _count(Object error, StackTrace stack) {
    try {
      countError?.call(error, stack);
    } catch (_) {}
  }

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

  /// Ob die laufende Abfolge auch zurückgestellte Fragen ([deferred]) stellt: ihr eigener Aufruf oder ein weiterer
  /// während des Laufs hat es verlangt.
  bool askDeferredToo = false;

  /// Arten, deren Löschdialog gerade steht oder deren Antwort noch gespeichert wird, mit dem Ende dieser Frage.
  final Map<HealthDataKind, Future<void>> _asked = {};

  /// Belegt die Löschfrage einer Art, bevor sie gezeigt wird; `null`, wenn zu dieser Art schon eine offen ist (je Art
  /// höchstens eine zugleich, SEC-0007). Freigabe mit [endQuestion].
  Completer<void>? beginQuestion(HealthDataKind kind) {
    if (_asked.containsKey(kind)) return null;
    final done = Completer<void>();
    _asked[kind] = done.future;
    return done;
  }

  /// Gibt die mit [beginQuestion] belegte Löschfrage frei.
  void endQuestion(HealthDataKind kind, Completer<void> done) {
    if (identical(_asked[kind], done.future)) _asked.remove(kind);
    if (!done.isCompleted) done.complete();
  }

  /// Ende der Löschfrage, die gerade die Sperre der Art hält; `null`, wenn keine.
  Future<void>? questionEnd(HealthDataKind kind) => _asked[kind];

  /// Arten, die per Schalter ausgeschaltet wurden, während eine andere Löschfrage dieser Art die Sperre hielt. Der
  /// Dialog dieser Frage gilt dann als der des Schalters („Abbrechen“ schaltet wieder ein); zeigt sie keinen, fragt
  /// der Schalter danach selbst.
  final Set<HealthDataKind> _switchWaiting = {};

  /// Vermerkt, dass der Schalter der Art auf die laufende Frage wartet.
  void markSwitchWaiting(HealthDataKind kind) => _switchWaiting.add(kind);

  /// Ob der Schalter der Art noch auf eine Frage wartet.
  bool isSwitchWaiting(HealthDataKind kind) => _switchWaiting.contains(kind);

  /// Übernimmt den Vermerk des Schalters (die gezeigte Frage gilt als seine); `true`, wenn er wartete.
  bool takeSwitchWaiting(HealthDataKind kind) => _switchWaiting.remove(kind);

  /// Wartet, bis keine Löschfrage mehr steht (auch die des Schalters).
  Future<void> questionsSettled() async {
    while (_asked.isNotEmpty) {
      await Future.wait(List.of(_asked.values));
    }
  }

  /// Ob die Löschfrage der Art noch offen ist: vorgemerkt und gespeichert offen. Lässt sich das Gespeicherte nicht
  /// lesen, gilt sie als offen (lieber erneut fragen).
  Future<bool> isQuestionOpen(HealthDataKind kind) async {
    if (!questions.contains(kind)) return false;
    try {
      return await consents.isDeleteQuestionOpen(healthSourceKey(kind));
    } catch (e, s) {
      _count(e, s);
      return true;
    }
  }

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

  /// Nach einem Import, der neue Sätze gespeichert hat (Auslöser „veränderter Erholungszustand“, FR-0157). Ohne
  /// Werte; Fehler darin bleiben still und werden nur gezählt.
  VoidCallback? onNewData;

  /// Ein Import über den Dienst; meldet neue Sätze an [onNewData].
  Future<HealthImportResult> _run(HealthImportTrigger trigger) async {
    final result = await importer.run(trigger);
    if (healthImportStoredNew(result)) {
      try {
        onNewData?.call();
      } catch (e, s) {
        _count(e, s);
      }
    }
    return result;
  }

  /// Import beim App-Start und beim Öffnen von „Heute“; Fehler bleiben still (nur gezählt), die Sperre hält der Dienst.
  void runInBackground(HealthImportTrigger trigger) {
    _run(trigger).then<void>((_) {}, onError: _count);
  }

  /// Import wie [runInBackground], danach Zustand neu lesen, damit offene Löschfragen beim Öffnen der App gezeigt werden
  /// können (SEC-0007, nicht nur auf der Health-Connect-Seite). Fehler bleiben still (nur gezählt).
  Future<void> importThenLoad(HealthImportTrigger trigger) async {
    try {
      await _run(trigger);
    } catch (e, s) {
      _count(e, s);
    }
    try {
      await load();
    } catch (e, s) {
      _count(e, s);
    }
  }

  /// Liest Zustand, Einwilligungen, Rechte und offene Löschfragen neu. Fehlt ein Recht für eine eingewilligte Art (oder ist Health Connect nicht mehr
  /// verfügbar), deren importierte Daten es gibt, wird die Löschfrage geöffnet (SEC-0007); ohne Daten wird sie still geschlossen.
  Future<void> load() async {
    try {
      sdk = await permissions.sdkStatus();
    } catch (e, s) {
      _count(e, s);
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
        permitted = await permissions.grantedKinds();
      } catch (e, s) {
        _count(e, s);
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
      } catch (e, s) {
        _count(e, s);
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
    } catch (e, s) {
      _count(e, s);
      return null;
    }
  }

  /// Schaltet die Einwilligung einer Art ein. Nur diese Art ändert sich (SEC-0002).
  Future<void> enable(HealthDataKind kind) async {
    final key = healthSourceKey(kind);
    await consents.grant(key);
    try {
      await consents.closeDeleteQuestion(key);
    } catch (e, s) {
      _count(e, s);
    }
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
    } catch (e, s) {
      _count(e, s);
    }
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
      return await permissions.openInstall();
    } catch (e, s) {
      _count(e, s);
      return false;
    }
  }

  /// Zeigt den Berechtigungsdialog von Health Connect, nur für die eingeschalteten Arten.
  Future<void> requestRights() async {
    if (enabled.isEmpty) return;
    try {
      permitted = await permissions.requestPermissions({...enabled});
    } catch (e, s) {
      _count(e, s);
      permitted = {};
    }
    _notify();
  }

  /// „Jetzt abrufen“.
  Future<HealthImportResult> fetchNow() async {
    fetching = true;
    _notify();
    try {
      return await _run(HealthImportTrigger.manual);
    } finally {
      fetching = false;
      lastImport = await _readLastImport();
      await load();
    }
  }
}

/// Hat der Import neue (oder überschriebene) Sätze gespeichert?
bool healthImportStoredNew(HealthImportResult result) =>
    result.status == HealthImportStatus.done &&
    result.kinds.values.any(
      (k) => k.status == HealthKindStatus.imported && k.stored > 0,
    );
