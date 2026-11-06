import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter/foundation.dart';

/// Einordnung der Herzfrequenzzone für die Anzeige (FR-0026, OQ-0012).
enum LiveZoneKind { zone, belowZone1, noHeartRate, noBasis }

class LiveZone {
  const LiveZone(this.kind, {this.zone, this.aboveHint = false});

  final LiveZoneKind kind;

  /// 1-basiert, nur bei [LiveZoneKind.zone].
  final int? zone;

  /// Puls über 100 % der Reserve (FR-0062).
  final bool aboveHint;
}

/// Führt einen Lauf im Vordergrund: verbindet [RunRecorder] mit Standortquelle,
/// Pulsquelle und dem Anzeigetakt. Die Oberfläche liest nur [snapshot],
/// [preprocessing] und die abgeleiteten Getter.
///
/// Es gehen keine Messwerte in Logs; Fehler tragen nur ihre Art.
class RunController extends ChangeNotifier {
  RunController({
    required this.clock,
    required this.storage,
    required this.location,
    this.heartRate,
    this.tickEvery = const Duration(seconds: 1),
    RunRecorder? recorder,
  }) : _recorder =
           recorder ??
           RunRecorder(
             clock: clock,
             runs: storage.runs,
             rawData: storage.rawData,
             markers: storage.markers,
           ) {
    _snapshot = _recorder.snapshot();
  }

  final Clock clock;
  final StorageSession storage;
  final LocationSource location;
  final Stream<HeartRateReading> Function()? heartRate;
  final Duration tickEvery;
  final RunRecorder _recorder;

  Timer? _timer;
  StreamSubscription<LocationSample>? _locationSub;
  StreamSubscription<HeartRateReading>? _heartSub;
  bool _disposed = false;

  late RecordingSnapshot _snapshot;
  RunPreprocessing? _pre;
  bool _autoPause = false;
  bool _startFailed = false;
  bool _starting = false;
  bool _locationError = false;
  bool _heartRateSeen = false;
  ResolvedHeartRate? _basis;
  FitnessParameters _fitness = const FitnessParameters.v3();

  RecordingSnapshot get snapshot => _snapshot;
  RunPreprocessing? get preprocessing => _pre;
  RecordingPhase get phase => _snapshot.phase;

  /// Gewünschter Stand der Autopause (auch vor dem Start gesetzt).
  bool get autoPause => _autoPause;

  /// Anlegen des Laufs scheiterte; ein erneuter [start] ist möglich.
  bool get startFailed => _startFailed;

  /// Die Standortquelle meldete einen Fehler und seitdem keinen Punkt mehr.
  bool get locationError => _locationError;

  /// Von der Pulsquelle kam in diesem Lauf schon ein Wert.
  bool get heartRateSourceSeen => _heartRateSeen;

  /// Art des letzten Speicherfehlers (nie Inhalte), `null` ohne Fehler.
  StorageFailure? get writeFailure => _recorder.lastWriteFailure;

  /// Mindestens ein akzeptierter Punkt liegt vor (Strecke bekannt).
  bool get hasFix => _snapshot.distanceMeters != null;

  LiveZone get zone {
    final bpm = _snapshot.heartRateBpm;
    if (bpm == null) return const LiveZone(LiveZoneKind.noHeartRate);
    final basis = _basis;
    if (basis == null) return const LiveZone(LiveZoneKind.noBasis);
    final r = const ReserveZones(reserve: HeartRateReserve())
        .zoneFor(basis.basis, bpm, _fitness);
    if (r is! FitnessAvailable<ReserveZonePlacement>) {
      return const LiveZone(LiveZoneKind.noBasis);
    }
    final p = r.value;
    return switch (p) {
      InReserveZone() => LiveZone(
        LiveZoneKind.zone,
        zone: p.zone,
        aboveHint: p.aboveHint,
      ),
      BelowReserveZone1() => const LiveZone(LiveZoneKind.belowZone1),
    };
  }

  /// Lädt Einstellungen und Profil, legt den Lauf an und beginnt, Punkte und
  /// Puls anzunehmen. Scheitert das Anlegen, bleibt [startFailed] gesetzt.
  Future<void> start() async {
    if (_starting || phase != RecordingPhase.idle) return;
    _starting = true;
    _startFailed = false;
    notifyListeners();
    try {
      try {
        _autoPause = await storage.settings.get(SettingKeys.autoPause) == '1';
      } on Object {
        _autoPause = false;
      }
      try {
        _fitness = await ReserveZoneSettings.loadParameters(storage.settings);
      } on Object {
        _fitness = const FitnessParameters.v3();
      }
      try {
        _basis = resolveHeartRate(
          await storage.profile.read(),
          currentYear: clock.now().year,
        );
      } on Object {
        _basis = null;
      }
      _recorder.setAutoPause(_autoPause);
      try {
        await _recorder.start();
      } on Object {
        _startFailed = true;
        return;
      }
      _locationSub = location.samples().listen(
        (s) {
          _locationError = false;
          _recorder.addPosition(s);
        },
        onError: (Object _) {
          _locationError = true;
          _update();
        },
      );
      final hr = heartRate;
      if (hr != null) {
        _heartSub = hr().listen((r) {
          _heartRateSeen = true;
          _recorder.addHeartRate(r);
        }, onError: (Object _) {});
      }
      _timer = Timer.periodic(tickEvery, (_) {
        _recorder.tick();
        _update();
      });
    } finally {
      _starting = false;
      _update();
    }
  }

  /// Schaltet die Autopause und merkt sie dauerhaft (FR-0029). Ein
  /// Speicherfehler ändert die laufende Aufzeichnung nicht.
  Future<void> setAutoPause(bool enabled) async {
    _autoPause = enabled;
    _recorder.setAutoPause(enabled);
    _update();
    try {
      await storage.settings.set(
        SettingKeys.autoPause,
        enabled ? '1' : '0',
        at: clock.now(),
      );
    } on Object {
      // Nur das Merken scheitert; der Lauf bleibt wie eingestellt.
    }
  }

  Future<void> pause() => _command(_recorder.pause);
  Future<void> resume() => _command(_recorder.resume);
  Future<void> lap() => _command(_recorder.lap);

  Future<void> finish() async {
    await _command(_recorder.finish);
    if (phase == RecordingPhase.finished) _stopInputs();
  }

  Future<void> _command(Future<CommandResult> Function() run) async {
    try {
      await run();
    } on Object {
      // Der Zustand der Sitzung gilt; der Speicherfehler steht in
      // [writeFailure] und wird angezeigt.
    }
    _update();
  }

  void _stopInputs() {
    _timer?.cancel();
    _timer = null;
    unawaited(_locationSub?.cancel());
    _locationSub = null;
    unawaited(_heartSub?.cancel());
    _heartSub = null;
  }

  void _update() {
    if (_disposed) return;
    _snapshot = _recorder.snapshot();
    _pre = _recorder.preprocessing();
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _stopInputs();
    super.dispose();
  }
}
