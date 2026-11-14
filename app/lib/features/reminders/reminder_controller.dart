import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../plan/plan_texts.dart' show planKindName;

/// Nur Debug-Einstieg (`main_debug.dart`): plant eine Erinnerung zusätzlich
/// über denselben Weg wie die echten (E2E-Test der Benachrichtigung).
typedef ReminderDebugAdd = Future<void> Function(
  ScheduledReminder reminder, {
  required ReminderLabels labels,
});

/// Texte der Benachrichtigung in der App-Sprache: Titel und „Art um Uhrzeit“,
/// keine Gesundheitswerte (SEC-0001).
class AppReminderTexts implements ReminderTexts, MorningReminderTexts {
  AppReminderTexts(this.l10n, this.material, {this.use24h = false});

  final AppLocalizations l10n;
  final MaterialLocalizations material;
  final bool use24h;

  /// Sprache und Uhrformat; ändern sie sich, wird neu geplant.
  String get signature => '${l10n.localeName}/$use24h';

  @override
  String get channelName => l10n.reminderChannelName;

  @override
  String get title => l10n.reminderTitle;

  @override
  MorningReminderLabels get morningLabels => MorningReminderLabels(
    channelName: l10n.morningReminderChannel,
    title: l10n.morningReminderTitle,
    body: l10n.morningReminderBody,
  );

  @override
  String body(PlanUnitKind kind, int minuteOfDay) => l10n.reminderBody(
    planKindName(l10n, kind),
    material.formatTimeOfDay(
      TimeOfDay(hour: minuteOfDay ~/ 60, minute: minuteOfDay % 60),
      alwaysUse24HourFormat: use24h,
    ),
  );
}

/// Erinnerungen vor geplanten Einheiten (FR-0174, WP22 Teil F): Stand der
/// Einstellungen für die Oberfläche, Einschalten mit Berechtigung und Neuplanen
/// nach jeder Änderung. Lebt über den Sitzungen (wie die Einstellungen); die
/// Wurzel einer Sitzung bindet sie an ([attach]). Fehler beim Planen ändern
/// nichts an der App: Die nächste Synchronisierung holt es nach.
class ReminderController extends ChangeNotifier with WidgetsBindingObserver {
  ReminderController({
    required this.scheduler,
    required this.clock,
    this.debugAdd,
    this.validationState = ppgValidationState,
  });

  /// Validierungsstand für die Erreichbarkeit der Morgenmessung (Tests).
  final Map<ValidationQuantity, ValidationState> validationState;

  /// Gesetzt von der Wurzel: öffnet die Morgenmessung, wenn das Tippen auf die
  /// Morgen-Erinnerung die App gestartet oder geholt hat.
  VoidCallback? onOpenMorning;

  final ReminderScheduler scheduler;
  final Clock clock;
  final ReminderDebugAdd? debugAdd;

  StorageSession? _session;
  AppReminderTexts? _texts;
  ReminderSettings _settings = const ReminderSettings();
  MorningReminderSettings _morning = const MorningReminderSettings();
  bool _loaded = false;
  bool _denied = false;
  bool _observing = false;
  bool _disposed = false;
  Future<void> _tail = Future.value();

  /// Gespeicherte Einstellungen.
  ReminderSettings get settings => _settings;

  /// Eingeschaltet und erlaubt: Erinnerungen sind aktiv (Stand des Schalters).
  bool get active => _settings.enabled && !_denied;

  /// Benachrichtigungen nicht erlaubt (beim Einschalten abgelehnt oder später
  /// im System entzogen): Der Schalter steht aus, die Seite erklärt es.
  bool get denied => _denied;

  bool get loaded => _loaded;

  /// Gespeicherte Einstellungen der Morgen-Erinnerung.
  MorningReminderSettings get morning => _morning;

  /// Morgen-Erinnerung eingeschaltet und erlaubt.
  bool get morningActive => _morning.enabled && !_denied;

  /// Bindet die Sitzung an, liest die Einstellungen und plant neu.
  void attach(StorageSession session) {
    _session = session;
    _loaded = false;
    if (!_observing) {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    }
    unawaited(_serial(_reload));
  }

  /// Löst die Sitzung, falls sie noch angebunden ist.
  void detach(StorageSession session) {
    if (identical(_session, session)) _session = null;
  }

  /// Texte der App-Sprache; eine andere Sprache plant neu.
  set texts(AppReminderTexts value) {
    final changed = _texts?.signature != value.signature;
    _texts = value;
    if (changed) sync();
  }

  /// Plant aus dem gespeicherten Plan neu (nach Planänderung,
  /// Neuberechnung, Ziel löschen, Einstellungsänderung, Rückkehr in die App).
  Future<void> sync() => _serial(_sync);

  /// Storniert alle Erinnerungen („Alles löschen“).
  Future<void> cancelAll() => _serial(() async {
    try {
      await scheduler.cancelAll();
    } on Object {
      // Kein Kanal: nichts geplant.
    }
    try {
      await scheduler.cancelMorning();
    } on Object {
      // Kein Kanal: nichts geplant.
    }
    _settings = const ReminderSettings();
    _morning = const MorningReminderSettings();
    _denied = false;
    _notify();
  });

  /// Einschalten fragt die Berechtigung (erst jetzt); abgelehnt bleibt der
  /// Schalter aus und die App läuft normal. Gibt den neuen Stand zurück.
  Future<bool> setEnabled(bool on) => _serial(() async {
    if (on) {
      var granted = false;
      try {
        granted = await scheduler.requestPermission();
        // API 31/32 kennen keine Laufzeitberechtigung: Die Anfrage meldet
        // immer „erteilt“, auch wenn Benachrichtigungen im System aus sind.
        // Dann ehrlich als abgelehnt zeigen statt eines Schalters, der nichts
        // plant.
        if (granted) granted = await scheduler.permitted();
      } on Object {
        granted = false;
      }
      if (!granted) {
        _denied = true;
        await _save(_settings.copyWith(enabled: false));
        await _sync();
        return false;
      }
    }
    _denied = false;
    await _save(_settings.copyWith(enabled: on));
    await _sync();
    return on;
  });

  /// Plant die Morgen-Erinnerung neu oder streicht sie (nach Öffnen der App,
  /// Änderung, Ausschalten des Entwicklermodus).
  Future<void> syncMorning() => _serial(_syncMorning);

  /// Morgen-Erinnerung ein/aus; Einschalten fragt die Berechtigung.
  Future<bool> setMorningEnabled(bool on) => _serial(() async {
    if (on) {
      var granted = false;
      try {
        granted = await scheduler.requestPermission();
        if (granted) granted = await scheduler.permitted();
      } on Object {
        granted = false;
      }
      if (!granted) {
        _denied = true;
        await _saveMorning(_morning.copyWith(enabled: false));
        await _syncMorning();
        return false;
      }
    }
    _denied = false;
    await _saveMorning(_morning.copyWith(enabled: on));
    await _syncMorning();
    return on;
  });

  Future<void> setMorningTime(int minuteOfDay) => _serial(() async {
    await _saveMorning(_morning.copyWith(minuteOfDay: minuteOfDay));
    await _syncMorning();
  });

  Future<void> setTime(int minuteOfDay) => _serial(() async {
    await _save(_settings.copyWith(minuteOfDay: minuteOfDay));
    await _sync();
  });

  Future<void> setLead(int minutes) => _serial(() async {
    await _save(_settings.copyWith(leadMinutes: minutes));
    await _sync();
  });

  /// Debug-Einstieg: eine Erinnerung an einen lockeren Lauf in [delay] über
  /// denselben Weg.
  Future<void> debugFireSoon({
    Duration delay = const Duration(seconds: 10),
  }) async {
    final add = debugAdd;
    final texts = _texts;
    if (add == null || texts == null) return;
    await add(
      ScheduledReminder(
        at: clock.now().add(delay),
        kind: PlanUnitKind.easy.name,
      ),
      labels: reminderLabels(texts, _settings),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Zurück in der App: Berechtigung kann im System geändert sein, das
    // Fenster der geplanten Erinnerungen rückt weiter.
    if (state == AppLifecycleState.resumed) unawaited(_serial(_reload));
  }

  Future<T> _serial<T>(Future<T> Function() action) {
    final done = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        done.complete(await action());
      } on Object catch (e, s) {
        done.completeError(e, s);
      }
    });
    return done.future;
  }

  Future<void> _reload() async {
    final session = _session;
    if (session == null) return;
    try {
      _settings = await ReminderSettings.load(session.settings);
      _morning = await MorningReminderSettings.load(session.settings);
      // Eingeschaltet: entzogen heißt abgelehnt. Ausgeschaltet bleibt eine
      // Ablehnung stehen (auch über die Rückkehr aus dem Systemdialog), bis
      // die Berechtigung im System erteilt ist.
      final permitted = await scheduler.permitted();
      if (_settings.enabled) {
        _denied = !permitted;
      } else if (_morning.enabled) {
        _denied = !permitted;
      } else if (permitted) {
        _denied = false;
      }
    } on Object {
      // Unlesbar: Stand bleibt; die Seite zeigt die Vorschläge.
    }
    _loaded = true;
    _notify();
    await _sync();
    // Tippen auf die Morgen-Erinnerung: Morgenmessung öffnen.
    try {
      if (await scheduler.takeLaunchTarget() == 'morning') {
        onOpenMorning?.call();
      }
    } on Object {
      // Kein Kanal: kein Anliegen.
    }
  }

  Future<void> _saveMorning(MorningReminderSettings next) async {
    final session = _session;
    if (session == null) return;
    await next.save(session.settings, at: clock.now());
    _morning = next;
    _notify();
  }

  Future<void> _syncMorning() async {
    final session = _session;
    final texts = _texts;
    if (session == null || texts == null) return;
    try {
      await syncMorningReminder(
        settings: session.settings,
        clock: clock,
        scheduler: scheduler,
        texts: texts,
        validationState: validationState,
      );
    } on Object {
      // Siehe Klassenkommentar.
    }
  }

  Future<void> _save(ReminderSettings next) async {
    final session = _session;
    if (session == null) return;
    await next.save(session.settings, at: clock.now());
    _settings = next;
    _notify();
  }

  Future<void> _sync() async {
    final session = _session;
    final texts = _texts;
    if (session == null || texts == null) return;
    try {
      await syncTrainingReminders(
        settings: session.settings,
        goals: (session as GoalStorage).goals,
        plans: (session as PlanStorage).plans,
        scheduler: scheduler,
        clock: clock,
        texts: texts,
      );
    } on Object {
      // Siehe Klassenkommentar.
    }
    await _syncMorning();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    if (_observing) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

/// Stellt den [ReminderController] über dem Navigator bereit (wie die
/// Einstellungen), damit auch per `Navigator.push` geöffnete Seiten ihn sehen.
class ReminderScope extends InheritedNotifier<ReminderController> {
  const ReminderScope({
    super.key,
    required ReminderController controller,
    required super.child,
  }) : super(notifier: controller);

  /// Der Controller oder `null`, wenn keiner bereitgestellt ist (Tests).
  static ReminderController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ReminderScope>()?.notifier;

  /// Ohne Abhängigkeit (für Aktionen, nicht zum Bauen).
  static ReminderController? read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ReminderScope>()?.notifier;
}
