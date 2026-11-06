import 'package:core/core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _messenger = ScaffoldMessenger.of(context);
  }

  @override
  void dispose() {
    // Der ScaffoldMessenger gehört der App, nicht der Seite: Die Rückmeldung
    // bliebe sonst über die Seite hinaus stehen und verdeckte beim nächsten
    // Besuch den Speichern-Knopf.
    _messenger?.clearSnackBars();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.profileTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(l10n.profileIntro),
          const SizedBox(height: 16),
          ProfileForm(
            service: _NotifyingProfileService(
              widget.session.profile,
              widget.clock,
              widget.recalculation,
            ),
            clock: widget.clock,
            onSaved: (_) {
              final messenger = ScaffoldMessenger.of(context);
              messenger.showSnackBar(
                SnackBar(
                  content: Text(
                    widget.recalculation.offer == null
                        ? l10n.profileSaved
                        : '${l10n.profileSaved}\n${l10n.recalcOffered}',
                  ),
                ),
              );
            },
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
  _NotifyingProfileService(super.store, super.clock, this._recalc);

  final RecalculationController _recalc;

  @override
  Future<ProfileSaveResult> save(ProfileRecord profile) async {
    final before = await load();
    final result = await super.save(profile);
    if (result.saved) await _recalc.profileChanged(before, profile);
    return result;
  }
}
