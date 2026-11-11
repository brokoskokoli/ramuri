import 'package:core/core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../measure/resting_measure_launcher.dart';
import '../measure/resting_measure_screen.dart';
import '../recalculation/recalculation_controller.dart';
import 'profile_form.dart';

/// Profilseite (FR-0002 bis FR-0005).
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    required this.session,
    required this.clock,
    required this.recalculation,
  });

  final StorageSession session;
  final Clock clock;
  final RecalculationController recalculation;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  ScaffoldMessengerState? _messenger;
  PpgCamera? _camera;
  late final ProfileService _service = _NotifyingProfileService(
    widget.session.profile,
    widget.clock,
    widget.recalculation,
    settings: widget.session.settings,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _messenger = ScaffoldMessenger.of(context);
    _camera = PpgCameraScope.maybeOf(context);
  }

  @override
  void dispose() {
    // Der ScaffoldMessenger gehört der App, nicht der Seite: Die Rückmeldung
    // bliebe sonst über die Seite hinaus stehen und verdeckte beim nächsten
    // Besuch den Speichern-Knopf.
    _messenger?.clearSnackBars();
    super.dispose();
  }

  /// Rückmeldung nach dem Speichern, von Hand wie nach der Übernahme eines
  /// Messwerts: das Angebot der Neuberechnung steht schon, wenn der Dienst
  /// gespeichert hat.
  void _showSaved() {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          widget.recalculation.offer == null
              ? l10n.profileSaved
              : '${l10n.profileSaved}\n${l10n.recalcOffered}',
        ),
      ),
    );
  }

  /// Die Messung mit demselben Dienst wie das Speichern (Zonen und
  /// Neuberechnung laufen wie bei manueller Eingabe) und derselben Rückmeldung
  /// nach der Übernahme.
  RestingMeasureLauncher _launcher() {
    final launch = restingMeasureLauncher(
      camera: _camera!,
      profile: _service,
      settings: widget.session.settings,
      clock: widget.clock,
      evaluate: PpgCameraScope.evaluateOf(context),
    );
    return (context) async {
      final outcome = await launch(context);
      if (outcome == RestingMeasureOutcome.adopted) _showSaved();
      return outcome;
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.profileTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          Text(l10n.profileIntro, style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height: 16),
          ProfileForm(
            service: _service,
            clock: widget.clock,
            // Gleicher Dienst wie beim Speichern: Zonen und Neuberechnung
            // laufen wie bei manueller Eingabe.
            restingMeasure: _camera == null ? null : _launcher(),
            coefficients: _Coefficients(widget.session, widget.recalculation),
            onSaved: (_) => _showSaved(),
          ),
        ],
      ),
    );
  }
}

/// Meldet dem Neuberechnungsdienst nach dem Speichern die Änderung (alt und
/// neu), damit er eine geänderte Herzfrequenzbasis anbieten kann. Das Angebot
/// ist fertig, bevor die Seite die Rückmeldung zeigt.
class _NotifyingProfileService extends ProfileService {
  _NotifyingProfileService(
    super.store,
    super.clock,
    this._recalc, {
    super.settings,
  });

  final RecalculationController _recalc;

  @override
  Future<ProfileSaveResult> save(ProfileRecord profile) async {
    final before = await load();
    final result = await super.save(profile);
    if (result.saved) {
      await _recalc.profileChanged(before, profile);
      // Ruhepuls, HFmax und Geburtsjahr (Näherung der HFmax) tragen die
      // Belastungsrechnung; danach prüft sie, ob das gewählte Profil noch
      // trägt (kein stiller Wechsel der Skala).
      if (before.restingHeartRateBpm != profile.restingHeartRateBpm ||
          before.maxHeartRateBpm != profile.maxHeartRateBpm ||
          before.birthYear != profile.birthYear) {
        await _recalc.loadBasisChanged();
      }
    }
    return result;
  }
}

/// Die Koeffizienten-Angabe aus den Einstellungen; Änderungen gehen über den
/// Controller der Neuberechnung (bei aktivem Banister als Angebot).
class _Coefficients implements LoadCoefficientsAccess {
  _Coefficients(this._session, this._recalc);

  final StorageSession _session;
  final RecalculationController _recalc;

  /// Eine noch unbestätigte Änderung gilt als gewählt, wie beim Profil: die
  /// Seite zeigt, was angeboten wurde, bis bestätigt oder abgelehnt ist.
  @override
  Future<LoadCoefficients?> read() async {
    final pending = await LoadSettings.pendingCoefficients(_session.settings);
    if (pending != null) return pending.value;
    return LoadSettings.coefficients(_session.settings);
  }

  @override
  Future<bool> banisterActive() async =>
      await LoadSettings.activeProfile(_session.settings) ==
      LoadProfile.banister;

  @override
  Future<void> apply(LoadCoefficients? value) =>
      _recalc.requestLoadCoefficients(value);
}
